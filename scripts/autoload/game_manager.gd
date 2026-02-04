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

enum GameState { MENU, LOBBY, PLAYING, PAUSED, GAME_OVER }

const MAX_PLAYERS := 4
const BASE_ZOMBIES_PER_ROUND := 15
const ZOMBIES_PER_PLAYER := 5
const ZOMBIE_HEALTH_MULTIPLIER := 1.1
const ZOMBIE_DAMAGE_MULTIPLIER := 1.05
const TYRANT_ROUND_INTERVAL := 5
const SPECIAL_ROUND_INTERVAL := 5

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

	# Calculate zombies for this round (exponential growth)
	var player_count: int = max(1, players.size())
	var round_multiplier: int = current_round * 4  # More zombies per round
	var wave_bonus: int = int(pow(current_round, 1.2))  # Exponential growth
	zombies_remaining = BASE_ZOMBIES_PER_ROUND + round_multiplier + wave_bonus + (player_count * ZOMBIES_PER_PLAYER)

	# Round 2 is extra heavy - double zombies to test new weapon
	if current_round == 2:
		zombies_remaining = int(zombies_remaining * 1.8)

	round_started.emit(current_round)

	if multiplayer.is_server():
		_server_start_wave_spawning()


func _server_start_wave_spawning() -> void:
	# This will be called by WaveManager
	pass


func on_zombie_killed(zombie: Node, killer_id: int, is_headshot: bool, hit_position: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return

	zombies_remaining -= 1
	zombies_killed_this_round += 1
	total_zombies_killed += 1

	# Calculate points - headshot = 50, body = 10
	var points: int = 50 if is_headshot else 10

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
	var popup_pos := hit_position if hit_position != Vector3.ZERO else zombie.global_position + Vector3(0, 1.5, 0)
	rpc("_spawn_point_popup", popup_pos, points, is_headshot)

	zombie_killed.emit(zombie, killer_id, points)

	# Chance to spawn power-up
	_try_spawn_power_up(zombie.global_position)

	# Check for round end
	if zombies_remaining <= 0:
		# Round 1 complete - give all players a better weapon for round 2
		if current_round == 1:
			_give_round1_reward()
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

	var selected_type: String = forced_type if forced_type != "" else power_up_types[randi() % power_up_types.size()]

	rpc("_spawn_power_up_at", position, selected_type)


@rpc("authority", "call_local", "reliable")
func _spawn_power_up_at(position: Vector3, power_up_type: String) -> void:
	var power_up_scene: PackedScene = preload("res://scenes/interactables/power_up.tscn")
	var power_up: Node3D = power_up_scene.instantiate()
	power_up.set("power_up_type", power_up_type)
	power_up.global_position = position

	var game_scene: Node = get_tree().current_scene
	if game_scene and game_scene.has_node("PowerUps"):
		game_scene.get_node("PowerUps").add_child(power_up)

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
	label.global_position = position

	var game_scene: Node = get_tree().current_scene
	if game_scene:
		game_scene.add_child(label)

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

	# Brief delay before next round
	await get_tree().create_timer(5.0).timeout

	if current_state == GameState.PLAYING:
		start_next_round()


func _give_round_end_rewards() -> void:
	# Max ammo for everyone
	for player: Node in players.values():
		if player.has_method("refill_ammo"):
			player.refill_ammo()

	# Every 5 rounds, give a random new gun to all players
	if current_round > 0 and current_round % 5 == 0:
		_give_bonus_weapon()

	# Play round end sound
	AudioManager.play_sound_ui("round_start", 0.0)


func _give_bonus_weapon() -> void:
	# Pool of bonus weapons that can be given
	var bonus_weapons: Array[String] = [
		"mp5", "ak47", "m14", "olympia", "stakeout",
		"rpk", "galil", "python", "spas12", "commando"
	]

	for player: Node in players.values():
		# Only give weapon if player has room
		if player.has_method("give_weapon") and player.weapons.size() < player.max_weapons:
			var random_weapon: String = bonus_weapons[randi() % bonus_weapons.size()]
			player.give_weapon(random_weapon)
			AudioManager.play_sound_3d("purchase", player.global_position, 3.0)


func _give_round1_reward() -> void:
	# Give all players a good SMG or shotgun for round 2
	var round1_rewards: Array[String] = ["mp5", "stakeout", "ak47", "m14"]
	var reward_weapon: String = round1_rewards[randi() % round1_rewards.size()]

	for player: Node in players.values():
		if player.has_method("give_weapon"):
			# Replace pistol or add weapon
			if player.weapons.size() >= player.max_weapons:
				player.replace_weapon(reward_weapon)
			else:
				player.give_weapon(reward_weapon)
			AudioManager.play_sound_3d("mystery_box_weapon", player.global_position, 5.0)


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
	return base_health * pow(ZOMBIE_HEALTH_MULTIPLIER, current_round - 1)


func get_zombie_damage_for_round(base_damage: float) -> float:
	return base_damage * pow(ZOMBIE_DAMAGE_MULTIPLIER, current_round - 1)


func is_special_round() -> bool:
	return current_round > 0 and current_round % SPECIAL_ROUND_INTERVAL == 0


func is_tyrant_round() -> bool:
	return current_round > 0 and current_round % TYRANT_ROUND_INTERVAL == 0


func get_game_time() -> float:
	if game_start_time == 0.0:
		return 0.0
	return (Time.get_ticks_msec() / 1000.0) - game_start_time


func activate_power() -> void:
	power_is_on = true
	# Notify all perk machines and pack-a-punch
	get_tree().call_group("power_dependent", "on_power_activated")


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
