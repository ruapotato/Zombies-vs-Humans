extends Node
## GameManager - Core game state singleton
## Manages rounds, players, zombies, points, and overall game flow

signal round_started(round_number: int)
signal round_ended(round_number: int)
signal game_over(final_round: int)
signal player_joined(player_id: int)
signal player_left(player_id: int)
signal zombie_killed(zombie: Node, killer_id: int, points: int)
signal power_up_spawned(power_up: Node)
signal power_up_collected(power_up_type: String, player_id: int)
signal power_activated

enum GameState { MENU, LOBBY, PLAYING, PAUSED, GAME_OVER }

const MAX_PLAYERS := 4
const ZOMBIE_HEALTH_MULTIPLIER := 1.08  # Slightly slower scaling for longer games
const ZOMBIE_DAMAGE_MULTIPLIER := 1.06
const BOSS_ROUND_INTERVAL := 10  # Tank boss every 10 rounds
const HORDE_SURGE_INTERVAL := 5  # Extra intense every 5 rounds

# Pacing curve - zombies per round (tuned for massive horde gameplay)
# Early game: Learn mechanics, build confidence
# Mid game: Escalating tension, introduce new zombie types
# Late game: MASSIVE hordes that test your limits
const ROUND_ZOMBIE_COUNTS: Array[int] = [
	24,    # Round 1: Warm up
	36,    # Round 2: Getting started
	48,    # Round 3: Finding rhythm
	64,    # Round 4: Building up
	100,   # Round 5: First horde surge!
	80,    # Round 6: Brief reprieve
	96,    # Round 7: Ramping again
	120,   # Round 8: Getting serious
	140,   # Round 9: Pre-boss tension
	200,   # Round 10: BOSS ROUND - Tank + horde
	160,   # Round 11: Post-boss cooldown
	180,   # Round 12: Back to business
	220,   # Round 13: Escalating
	260,   # Round 14: Pressure building
	350,   # Round 15: Horde surge!
	280,   # Round 16: Sustained intensity
	320,   # Round 17: No mercy
	380,   # Round 18: Overwhelming
	420,   # Round 19: Chaos
	500,   # Round 20: BOSS ROUND - Epic battle
]

var current_state: GameState = GameState.MENU
var current_round: int = 0
var zombies_remaining: int = 0
var zombies_killed_this_round: int = 0
var total_zombies_killed: int = 0

var players: Dictionary = {}  # player_id -> Player node
var player_stats: Dictionary = {}  # player_id -> stats dict

var active_power_ups: Dictionary = {}  # power_up_type -> end_time
var power_is_on: bool = false

var game_start_time: float = 0.0
var round_start_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if current_state != GameState.PLAYING:
		return

	# Update active power-ups
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var expired_power_ups: Array[String] = []

	for key: String in active_power_ups:
		if current_time >= active_power_ups[key]:
			expired_power_ups.append(key)

	for key: String in expired_power_ups:
		active_power_ups.erase(key)


func start_game() -> void:
	current_state = GameState.PLAYING
	current_round = 0
	total_zombies_killed = 0
	active_power_ups.clear()
	power_is_on = false
	game_start_time = Time.get_ticks_msec() / 1000.0

	# Initialize player stats
	for player_id: int in players:
		player_stats[player_id] = {
			"kills": 0,
			"headshots": 0,
			"revives": 0,
			"downs": 0,
			"points_earned": 0
		}

	start_next_round()


func start_next_round() -> void:
	current_round += 1
	zombies_killed_this_round = 0
	round_start_time = Time.get_ticks_msec() / 1000.0

	# Get zombie count from pacing curve or calculate for high rounds
	zombies_remaining = _calculate_zombies_for_round()

	# Scale for player count (more players = more zombies)
	var player_count: int = max(1, players.size())
	if player_count > 1:
		zombies_remaining = int(zombies_remaining * (1.0 + (player_count - 1) * 0.5))

	round_started.emit(current_round)

	if multiplayer.is_server():
		_server_start_wave_spawning()


func _calculate_zombies_for_round() -> int:
	# Use pacing curve for first 20 rounds
	if current_round <= ROUND_ZOMBIE_COUNTS.size():
		return ROUND_ZOMBIE_COUNTS[current_round - 1]

	# Beyond round 20: exponential scaling from the last defined value
	var base: int = ROUND_ZOMBIE_COUNTS[ROUND_ZOMBIE_COUNTS.size() - 1]  # 500
	var rounds_beyond: int = current_round - ROUND_ZOMBIE_COUNTS.size()

	# Add 15% more zombies per round after 20, with surge rounds
	var scaled: int = int(base * pow(1.15, rounds_beyond))

	# Horde surge bonus on multiples of 5
	if current_round % HORDE_SURGE_INTERVAL == 0:
		scaled = int(scaled * 1.4)

	# Boss round bonus on multiples of 10
	if current_round % BOSS_ROUND_INTERVAL == 0:
		scaled = int(scaled * 1.25)

	return mini(scaled, 2000)  # Cap at 2000 for sanity


func _server_start_wave_spawning() -> void:
	# This will be called by WaveManager
	pass


func on_zombie_killed(zombie: Node, killer_id: int, is_headshot: bool, hit_position: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return

	zombies_remaining -= 1
	zombies_killed_this_round += 1
	total_zombies_killed += 1

	# Calculate points - headshot = 100, body = 50
	var points: int = 100 if is_headshot else 50

	if is_headshot:
		if killer_id in player_stats:
			player_stats[killer_id]["headshots"] += 1

	# Double points power-up
	if is_power_up_active("double_points"):
		points *= 2

	if killer_id in player_stats:
		player_stats[killer_id]["kills"] += 1
		player_stats[killer_id]["points_earned"] += points

	# Award points to player
	if killer_id in players:
		players[killer_id].add_points(points)

	# Spawn 3D point popup at hit location
	var popup_pos: Vector3 = hit_position if hit_position != Vector3.ZERO else zombie.global_position + Vector3(0, 1.5, 0)
	rpc("_spawn_point_popup", popup_pos, points, is_headshot)

	zombie_killed.emit(zombie, killer_id, points)

	# Chance to spawn power-up
	_try_spawn_power_up(zombie.global_position)

	# Check for round end
	if zombies_remaining <= 0:
		end_round()


func _try_spawn_power_up(position: Vector3) -> void:
	# 3% base chance, slightly higher on later rounds
	var chance: float = 0.03 + (current_round * 0.002)
	chance = min(chance, 0.08)  # Cap at 8%

	if randf() < chance:
		spawn_power_up(position)


func spawn_power_up(position: Vector3, forced_type: String = "") -> void:
	if not multiplayer.is_server():
		return

	var power_up_types: Array[String] = ["max_ammo", "insta_kill", "double_points", "nuke", "carpenter"]

	# Fire sale only when mystery box exists and power is on
	if power_is_on:
		power_up_types.append("fire_sale")

	var selected_type: String = forced_type if forced_type != "" else power_up_types[randi_range(0, power_up_types.size() - 1)]

	rpc("_spawn_power_up_at", position, selected_type)


@rpc("authority", "call_local", "reliable")
func _spawn_power_up_at(position: Vector3, power_up_type: String) -> void:
	var power_up_scene: PackedScene = preload("res://scenes/interactables/power_up.tscn")
	var power_up: Node3D = power_up_scene.instantiate()
	power_up.set("power_up_type", power_up_type)

	var game_scene: Node = get_tree().current_scene
	if game_scene and game_scene.has_node("PowerUps"):
		game_scene.get_node("PowerUps").add_child(power_up)
		power_up.global_position = position  # Set position AFTER adding to tree

	power_up_spawned.emit(power_up)


@rpc("authority", "call_local", "reliable")
func _spawn_point_popup(position: Vector3, points: int, is_headshot: bool) -> void:
	# Create a 3D label to show points
	var label := Label3D.new()
	label.text = "+%d" % points
	label.font_size = 48 if is_headshot else 32
	label.modulate = Color.YELLOW if is_headshot else Color.WHITE
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true  # Always visible

	var game_scene: Node = get_tree().current_scene
	if game_scene:
		game_scene.add_child(label)
		label.global_position = position  # Set position AFTER adding to tree

		# Animate: float up and fade out
		var tween := label.create_tween()
		tween.set_parallel(true)
		tween.tween_property(label, "global_position", position + Vector3(0, 1.5, 0), 0.8)
		tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
		tween.set_parallel(false)
		tween.tween_callback(label.queue_free)


func collect_power_up(power_up_type: String, collector_id: int) -> void:
	if not multiplayer.is_server():
		return

	rpc("_apply_power_up", power_up_type, collector_id)


@rpc("authority", "call_local", "reliable")
func _apply_power_up(power_up_type: String, collector_id: int) -> void:
	var duration: float = 30.0
	var current_time: float = Time.get_ticks_msec() / 1000.0

	match power_up_type:
		"max_ammo":
			for player: Node in players.values():
				if player.has_method("refill_ammo"):
					player.refill_ammo()

		"insta_kill":
			active_power_ups["insta_kill"] = current_time + duration

		"double_points":
			active_power_ups["double_points"] = current_time + duration

		"nuke":
			_nuke_all_zombies()

		"carpenter":
			_repair_all_barriers()

		"fire_sale":
			active_power_ups["fire_sale"] = current_time + duration

	power_up_collected.emit(power_up_type, collector_id)


func _nuke_all_zombies() -> void:
	var game_scene: Node = get_tree().current_scene
	if game_scene and game_scene.has_node("Zombies"):
		for zombie: Node in game_scene.get_node("Zombies").get_children():
			if zombie.has_method("die"):
				zombie.die()
				# Award 400 points to all players
				for player: Node in players.values():
					if player.has_method("add_points"):
						player.add_points(400)


func _repair_all_barriers() -> void:
	var game_scene: Node = get_tree().current_scene
	if game_scene and game_scene.has_node("Barriers"):
		for barrier: Node in game_scene.get_node("Barriers").get_children():
			if barrier.has_method("repair_fully"):
				barrier.repair_fully()
		# Award 200 points to all players
		for player: Node in players.values():
			if player.has_method("add_points"):
				player.add_points(200)


func is_power_up_active(power_up_type: String) -> bool:
	if power_up_type not in active_power_ups:
		return false

	var current_time: float = Time.get_ticks_msec() / 1000.0
	return current_time < active_power_ups[power_up_type]


func end_round() -> void:
	round_ended.emit(current_round)

	# Give all players max ammo between rounds
	_give_round_end_rewards()

	# Dynamic break time based on round intensity
	var break_time := _get_between_round_delay()
	await get_tree().create_timer(break_time).timeout

	if current_state == GameState.PLAYING:
		start_next_round()


func _get_between_round_delay() -> float:
	# Boss rounds always get a longer break after
	if is_boss_round():
		return 15.0

	# Short breaks early, longer breaks after intense rounds
	var zombies_killed := zombies_killed_this_round

	if zombies_killed < 50:
		return 3.0  # Quick rounds get quick breaks
	elif zombies_killed < 100:
		return 5.0  # Medium rounds
	elif zombies_killed < 200:
		return 7.0  # Larger rounds need more recovery
	elif zombies_killed < 350:
		return 10.0  # Big horde - catch your breath
	else:
		return 12.0  # Massive round - earned a real break


func _give_round_end_rewards() -> void:
	# Max ammo for everyone
	for player: Node in players.values():
		if player.has_method("refill_ammo"):
			player.refill_ammo()

	# Play round end sound
	AudioManager.play_sound_ui("round_start", 0.0)


func trigger_game_over() -> void:
	current_state = GameState.GAME_OVER
	game_over.emit(current_round)


func register_player(player_id: int, player_node: Node) -> void:
	players[player_id] = player_node
	player_joined.emit(player_id)


func unregister_player(player_id: int) -> void:
	if player_id in players:
		players.erase(player_id)
		player_stats.erase(player_id)
		player_left.emit(player_id)

	# Check if all players are gone or dead
	if players.is_empty() and current_state == GameState.PLAYING:
		trigger_game_over()


func get_alive_players() -> Array:
	var alive: Array = []
	for player: Node in players.values():
		if player and not player.get("is_downed"):
			alive.append(player)
	return alive


func get_downed_players() -> Array:
	var downed: Array = []
	for player: Node in players.values():
		if player and player.get("is_downed"):
			downed.append(player)
	return downed


func all_players_downed() -> bool:
	for player: Node in players.values():
		if player and not player.get("is_downed"):
			return false
	return players.size() > 0


func get_zombie_health_for_round(base_health: float) -> float:
	if current_round <= 10:
		# Linear growth: +15% per round
		return base_health * (1.0 + (current_round - 1) * 0.15)
	else:
		# Exponential after round 10: 1.1x per round
		var round10_health := base_health * (1.0 + 9 * 0.15)  # = base * 2.35
		return round10_health * pow(1.1, current_round - 10)


func get_zombie_damage_for_round(base_damage: float) -> float:
	return base_damage * pow(ZOMBIE_DAMAGE_MULTIPLIER, current_round - 1)


func is_horde_surge_round() -> bool:
	# Every 5 rounds is a horde surge (fast spawns, more zombies)
	return current_round > 0 and current_round % HORDE_SURGE_INTERVAL == 0


func is_boss_round() -> bool:
	# Every 10 rounds has a Tank boss
	return current_round > 0 and current_round % BOSS_ROUND_INTERVAL == 0


# Legacy compatibility
func is_special_round() -> bool:
	return is_horde_surge_round()


func is_tyrant_round() -> bool:
	return is_boss_round()


func get_game_time() -> float:
	if game_start_time == 0.0:
		return 0.0
	return (Time.get_ticks_msec() / 1000.0) - game_start_time


func activate_power() -> void:
	power_is_on = true
	# Notify all perk machines and pack-a-punch
	get_tree().call_group("power_dependent", "on_power_activated")
	power_activated.emit()


func reset_game() -> void:
	current_state = GameState.MENU
	current_round = 0
	zombies_remaining = 0
	zombies_killed_this_round = 0
	total_zombies_killed = 0
	players.clear()
	player_stats.clear()
	active_power_ups.clear()
	power_is_on = false
	game_start_time = 0.0
	round_start_time = 0.0
	if Engine.has_singleton("ProgressionManager") or get_node_or_null("/root/ProgressionManager"):
		ProgressionManager.reset()
