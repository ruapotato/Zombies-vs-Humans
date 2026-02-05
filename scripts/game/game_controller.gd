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
@onready var wave_manager: Node = $WaveManager

var zombie_horde: Node  # Centralized zombie controller for performance
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

		# Update spawn points from map
		if map_instance.has_node("SpawnPoints"):
			for child in map_instance.get_node("SpawnPoints").get_children():
				if child is Marker3D:
					player_spawn_positions.append(child.global_position)

		if map_instance.has_node("ZombieSpawnPoints"):
			for child in map_instance.get_node("ZombieSpawnPoints").get_children():
				if child is Marker3D:
					zombie_spawn_positions.append(child.global_position)

		# Spawn interactables from map placeholders
		if map_instance.has_node("Interactables"):
			_spawn_interactables_from_map(map_instance.get_node("Interactables"))
	else:
		push_error("Map not found: %s" % map_scene_path)

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
	# WaveManager has script attached in scene via @onready
	# Pass references to it
	if wave_manager:
		print("WaveManager found, script: ", wave_manager.get_script())
		print("Has start_wave: ", wave_manager.has_method("start_wave"))
		wave_manager.zombies_container = zombies_container
		wave_manager.spawn_positions = zombie_spawn_positions
	else:
		push_error("WaveManager node not found!")

	# Setup centralized zombie horde controller (server only)
	if multiplayer.is_server():
		_setup_zombie_horde()


func _setup_zombie_horde() -> void:
	var horde_script := preload("res://scripts/enemies/zombie_horde.gd")
	zombie_horde = Node.new()
	zombie_horde.set_script(horde_script)
	zombie_horde.name = "ZombieHorde"
	add_child(zombie_horde)

	# Initialize with references
	zombie_horde.initialize(zombies_container, self)


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


func _spawn_interactables_from_map(interactables_node: Node3D) -> void:
	# Preload interactable scenes
	var perk_machine_scene: PackedScene = preload("res://scenes/interactables/perk_machine.tscn")
	var mystery_box_scene: PackedScene = preload("res://scenes/interactables/mystery_box.tscn")
	var power_switch_scene: PackedScene = preload("res://scenes/interactables/power_switch.tscn")
	var wall_weapon_scene: PackedScene = preload("res://scenes/interactables/wall_weapon.tscn")
	var shop_machine_scene: PackedScene = preload("res://scenes/interactables/shop_machine.tscn")

	for placeholder in interactables_node.get_children():
		# Skip nodes that already have scripts (they're already proper instances)
		if placeholder.get_script() != null:
			continue

		# Skip nodes that are in the interactables group (already set up)
		if placeholder.is_in_group("interactables"):
			continue

		var node_name: String = placeholder.name.to_lower()
		var spawn_transform: Transform3D = placeholder.transform
		var instance: Node3D = null

		if "perk" in node_name:
			instance = perk_machine_scene.instantiate() as Node3D
			# Extract perk name from placeholder name (e.g., "PerkJuggernog" -> "juggernog")
			var perk_name := _extract_perk_name(placeholder.name)
			if perk_name:
				instance.set("perk_name", perk_name)

		elif "mysterybox" in node_name or "mystery_box" in node_name:
			instance = mystery_box_scene.instantiate() as Node3D

		elif "power" in node_name:
			instance = power_switch_scene.instantiate() as Node3D

		elif "wallweapon" in node_name or "wall_weapon" in node_name:
			instance = wall_weapon_scene.instantiate() as Node3D
			# Extract weapon name from placeholder
			var weapon_id := _extract_weapon_name(placeholder.name)
			if weapon_id:
				instance.set("weapon_id", weapon_id)

		elif "shop" in node_name:
			instance = shop_machine_scene.instantiate() as Node3D

		if instance:
			interactables_container.add_child(instance)
			instance.transform = spawn_transform
			print("Spawned interactable: %s at %s" % [placeholder.name, spawn_transform.origin])


func _extract_perk_name(placeholder_name: String) -> String:
	# Convert "PerkJuggernog" or "Perk_Juggernog" to "juggernog"
	var name_lower := placeholder_name.to_lower()
	name_lower = name_lower.replace("perk_", "").replace("perk", "")

	# Map common variations to perk names
	var perk_map := {
		"juggernog": "juggernog",
		"jug": "juggernog",
		"speedcola": "speed_cola",
		"speed_cola": "speed_cola",
		"speed": "speed_cola",
		"doubletap": "double_tap",
		"double_tap": "double_tap",
		"quickrevive": "quick_revive",
		"quick_revive": "quick_revive",
		"revive": "quick_revive",
		"staminup": "stamin_up",
		"stamin_up": "stamin_up",
		"stamina": "stamin_up",
		"phdflopper": "phd_flopper",
		"phd_flopper": "phd_flopper",
		"phd": "phd_flopper",
		"deadshot": "deadshot",
		"mulekick": "mule_kick",
		"mule_kick": "mule_kick",
		"mule": "mule_kick",
		"springheels": "spring_heels",
		"spring_heels": "spring_heels",
		"spring": "spring_heels"
	}

	return perk_map.get(name_lower, name_lower)


func _extract_weapon_name(placeholder_name: String) -> String:
	# Convert "WallWeaponM14" to "m14"
	var name_lower := placeholder_name.to_lower()
	name_lower = name_lower.replace("wallweapon", "").replace("wall_weapon", "").replace("wall", "")
	return name_lower
