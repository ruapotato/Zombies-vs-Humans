extends Node3D
## Game scene controller
## Manages the active game session, spawning, and coordination

@onready var map_container: Node3D = $Map
@onready var players_container: Node3D = $Players
@onready var zombies_container: Node3D = $Zombies
@onready var interactables_container: Node3D = $Interactables
@onready var power_ups_container: Node3D = $PowerUps
@onready var barriers_container: Node3D = $Barriers
@onready var spawn_points: Node3D = $SpawnPoints
@onready var zombie_spawn_points: Node3D = $ZombieSpawnPoints
@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var hud_control: Control = $HUD/HUDControl

var wave_manager: Node
var hud: Control

var player_spawn_positions: Array[Vector3] = []
var zombie_spawn_positions: Array[Vector3] = []
var spawn_index := 0


func _ready() -> void:
	# Connect to network events
	NetworkManager.all_players_loaded.connect(_on_all_players_loaded)

	# Connect to game events
	GameManager.round_started.connect(_on_round_started)
	GameManager.round_ended.connect(_on_round_ended)
	GameManager.game_over.connect(_on_game_over)

	# Collect spawn points
	_collect_spawn_points()

	# Load map
	_load_map()

	# Setup HUD
	_setup_hud()

	# Setup wave manager
	_setup_wave_manager()

	# Capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _collect_spawn_points() -> void:
	player_spawn_positions.clear()
	zombie_spawn_positions.clear()

	for child in spawn_points.get_children():
		if child is Marker3D:
			player_spawn_positions.append(child.global_position)

	for child in zombie_spawn_points.get_children():
		if child is Marker3D:
			zombie_spawn_positions.append(child.global_position)


func _load_map() -> void:
	var map_name: String = str(NetworkManager.server_info.get("map", "nacht"))
	var map_scene_path: String = MapManager.get_map_scene_path(map_name)

	print("Loading map: %s from path: %s" % [map_name, map_scene_path])
	print("ResourceLoader.exists: %s" % ResourceLoader.exists(map_scene_path))

	if ResourceLoader.exists(map_scene_path):
		var map_scene: PackedScene = load(map_scene_path) as PackedScene
		var map_instance: Node3D = map_scene.instantiate() as Node3D
		map_container.add_child(map_instance)
		print("Map loaded successfully: %s" % map_instance.name)
	else:
		push_error("Map not found: %s" % map_scene_path)

		# Update spawn points from map
		if map_instance.has_node("SpawnPoints"):
			for child in map_instance.get_node("SpawnPoints").get_children():
				if child is Marker3D:
					player_spawn_positions.append(child.global_position)

		if map_instance.has_node("ZombieSpawnPoints"):
			for child in map_instance.get_node("ZombieSpawnPoints").get_children():
				if child is Marker3D:
					zombie_spawn_positions.append(child.global_position)

	# Ensure we have default spawn points
	if player_spawn_positions.is_empty():
		player_spawn_positions.append(Vector3(0, 1, 0))
		player_spawn_positions.append(Vector3(2, 1, 0))
		player_spawn_positions.append(Vector3(-2, 1, 0))
		player_spawn_positions.append(Vector3(0, 1, 2))

	if zombie_spawn_positions.is_empty():
		zombie_spawn_positions.append(Vector3(10, 0, 10))
		zombie_spawn_positions.append(Vector3(-10, 0, 10))
		zombie_spawn_positions.append(Vector3(10, 0, -10))
		zombie_spawn_positions.append(Vector3(-10, 0, -10))


func _setup_hud() -> void:
	var hud_scene := preload("res://scenes/ui/hud.tscn")
	hud = hud_scene.instantiate()
	hud_control.add_child(hud)


func _setup_wave_manager() -> void:
	var wave_manager_script := preload("res://scripts/enemies/wave_manager.gd")
	wave_manager = Node.new()
	wave_manager.set_script(wave_manager_script)
	wave_manager.name = "WaveManagerScript"
	$WaveManager.add_child(wave_manager)

	# Pass references
	wave_manager.zombies_container = zombies_container
	wave_manager.spawn_positions = zombie_spawn_positions


func _on_all_players_loaded() -> void:
	print("All players loaded, is_server: ", multiplayer.is_server())
	if multiplayer.is_server():
		_spawn_all_players()


func _spawn_all_players() -> void:
	spawn_index = 0
	print("Spawning all players, count: ", NetworkManager.connected_players.size())

	for peer_id: int in NetworkManager.connected_players:
		var spawn_pos := _get_next_spawn_position()
		print("Spawning player %d at %s" % [peer_id, spawn_pos])
		NetworkManager.spawn_player(peer_id, spawn_pos)


func _get_next_spawn_position() -> Vector3:
	if player_spawn_positions.is_empty():
		return Vector3(0, 1, 0)

	var pos := player_spawn_positions[spawn_index % player_spawn_positions.size()]
	spawn_index += 1
	return pos


func _on_round_started(round_number: int) -> void:
	AudioManager.play_sound_ui("round_start")

	if multiplayer.is_server() and wave_manager:
		wave_manager.start_wave(round_number)


func _on_round_ended(round_number: int) -> void:
	AudioManager.play_sound_ui("round_end")


func _on_game_over(final_round: int) -> void:
	AudioManager.play_sound_ui("game_over")
	AudioManager.play_music("game_over")

	# Show game over screen
	var game_over_scene := preload("res://scenes/ui/game_over.tscn")
	var game_over_ui := game_over_scene.instantiate()
	game_over_ui.final_round = final_round
	hud_control.add_child(game_over_ui)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()


func _toggle_pause() -> void:
	if GameManager.current_state == GameManager.GameState.GAME_OVER:
		return

	if GameManager.current_state == GameManager.GameState.PAUSED:
		GameManager.current_state = GameManager.GameState.PLAYING
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Hide pause menu
	else:
		GameManager.current_state = GameManager.GameState.PAUSED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# Show pause menu


func get_random_zombie_spawn() -> Vector3:
	if zombie_spawn_positions.is_empty():
		return Vector3(10, 0, 10)

	return zombie_spawn_positions[randi() % zombie_spawn_positions.size()]


func get_nearest_player_to(position: Vector3) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := INF

	for player in players_container.get_children():
		if player.has_method("is_valid_target") and not player.is_valid_target():
			continue

		var dist := position.distance_to(player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = player

	return nearest
