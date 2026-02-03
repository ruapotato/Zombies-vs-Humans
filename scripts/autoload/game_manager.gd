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
const BASE_ZOMBIES_PER_ROUND := 6
const ZOMBIES_PER_PLAYER := 2
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


func _process(delta: float) -> void:
	if current_state != GameState.PLAYING:
		return

	# Update active power-ups
	var current_time := Time.get_ticks_msec() / 1000.0
	var expired_power_ups: Array[String] = []

	for power_up_type in active_power_ups:
		if current_time >= active_power_ups[power_up_type]:
			expired_power_ups.append(power_up_type)

	for power_up_type in expired_power_ups:
		active_power_ups.erase(power_up_type)


func start_game() -> void:
	current_state = GameState.PLAYING
	current_round = 0
	total_zombies_killed = 0
	active_power_ups.clear()
	power_is_on = false
	game_start_time = Time.get_ticks_msec() / 1000.0

	# Initialize player stats
	for player_id in players:
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

	# Calculate zombies for this round
	var player_count := max(1, players.size())
	zombies_remaining = BASE_ZOMBIES_PER_ROUND + (current_round * 2) + (player_count * ZOMBIES_PER_PLAYER)

	round_started.emit(current_round)

	if multiplayer.is_server():
		_server_start_wave_spawning()


func _server_start_wave_spawning() -> void:
	# This will be called by WaveManager
	pass


func on_zombie_killed(zombie: Node, killer_id: int, is_headshot: bool) -> void:
	if not multiplayer.is_server():
		return

	zombies_remaining -= 1
	zombies_killed_this_round += 1
	total_zombies_killed += 1

	# Calculate points
	var base_points := zombie.get_meta("point_value", 10)
	var points := base_points

	if is_headshot:
		points += 50
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

	zombie_killed.emit(zombie, killer_id, points)

	# Chance to spawn power-up
	_try_spawn_power_up(zombie.global_position)

	# Check for round end
	if zombies_remaining <= 0:
		end_round()


func _try_spawn_power_up(position: Vector3) -> void:
	# 2% base chance, slightly higher on later rounds
	var chance := 0.02 + (current_round * 0.002)
	chance = min(chance, 0.05)  # Cap at 5%

	if randf() < chance:
		spawn_power_up(position)


func spawn_power_up(position: Vector3, forced_type: String = "") -> void:
	if not multiplayer.is_server():
		return

	var power_up_types := ["max_ammo", "insta_kill", "double_points", "nuke", "carpenter"]

	# Fire sale only when mystery box exists and power is on
	if power_is_on:
		power_up_types.append("fire_sale")

	var power_up_type := forced_type if forced_type != "" else power_up_types[randi() % power_up_types.size()]

	rpc("_spawn_power_up_at", position, power_up_type)


@rpc("authority", "call_local", "reliable")
func _spawn_power_up_at(position: Vector3, power_up_type: String) -> void:
	var power_up_scene := preload("res://scenes/interactables/power_up.tscn")
	var power_up := power_up_scene.instantiate()
	power_up.power_up_type = power_up_type
	power_up.global_position = position

	var game_scene := get_tree().current_scene
	if game_scene and game_scene.has_node("PowerUps"):
		game_scene.get_node("PowerUps").add_child(power_up)

	power_up_spawned.emit(power_up)


func collect_power_up(power_up_type: String, collector_id: int) -> void:
	if not multiplayer.is_server():
		return

	rpc("_apply_power_up", power_up_type, collector_id)


@rpc("authority", "call_local", "reliable")
func _apply_power_up(power_up_type: String, collector_id: int) -> void:
	var duration := 30.0
	var current_time := Time.get_ticks_msec() / 1000.0

	match power_up_type:
		"max_ammo":
			for player in players.values():
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
	var game_scene := get_tree().current_scene
	if game_scene and game_scene.has_node("Zombies"):
		for zombie in game_scene.get_node("Zombies").get_children():
			if zombie.has_method("die"):
				zombie.die()
				# Award 400 points to all players
				for player in players.values():
					player.add_points(400)


func _repair_all_barriers() -> void:
	var game_scene := get_tree().current_scene
	if game_scene and game_scene.has_node("Barriers"):
		for barrier in game_scene.get_node("Barriers").get_children():
			if barrier.has_method("repair_fully"):
				barrier.repair_fully()
		# Award 200 points to all players
		for player in players.values():
			player.add_points(200)


func is_power_up_active(power_up_type: String) -> bool:
	if power_up_type not in active_power_ups:
		return false

	var current_time := Time.get_ticks_msec() / 1000.0
	return current_time < active_power_ups[power_up_type]


func end_round() -> void:
	round_ended.emit(current_round)

	# Brief delay before next round
	await get_tree().create_timer(5.0).timeout

	if current_state == GameState.PLAYING:
		start_next_round()


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
	var alive := []
	for player in players.values():
		if player and not player.is_downed:
			alive.append(player)
	return alive


func get_downed_players() -> Array:
	var downed := []
	for player in players.values():
		if player and player.is_downed:
			downed.append(player)
	return downed


func all_players_downed() -> bool:
	for player in players.values():
		if player and not player.is_downed:
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
