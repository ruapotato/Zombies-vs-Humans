extends Node
## WaveManager - Controls zombie spawning in waves

const EnemyScript = preload("res://scripts/enemies/enemy_base.gd")

signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal zombie_spawned(zombie: Node)

const SPAWN_DELAY_BASE := 2.0
const SPAWN_DELAY_MIN := 0.5
const MAX_ACTIVE_ZOMBIES := 24

# Enemy scenes - each type has its own distinct model
var enemy_scenes: Dictionary = {
	"dretch": preload("res://scenes/enemies/dretch.tscn"),
	"basilisk": preload("res://scenes/enemies/basilisk.tscn"),
	"marauder": preload("res://scenes/enemies/marauder.tscn"),
	"dragoon": preload("res://scenes/enemies/dragoon.tscn"),
	"tyrant": preload("res://scenes/enemies/tyrant.tscn")
}

# Enemy type configurations (speeds reduced ~30% for better gameplay)
var enemy_configs: Dictionary = {
	"dretch": {
		"display_name": "Dretch",
		"base_health": 30,
		"base_damage": 20,
		"base_speed": 3.5,
		"attack_rate": 0.8,
		"point_value": 10,
		"color": Color(0.3, 0.5, 0.2),
		"scale": Vector3(0.8, 0.8, 0.8)
	},
	"basilisk": {
		"display_name": "Basilisk",
		"base_health": 75,
		"base_damage": 40,
		"base_speed": 4.0,
		"attack_rate": 1.0,
		"point_value": 30,
		"can_pounce": true,
		"color": Color(0.4, 0.3, 0.5),
		"scale": Vector3(1.0, 0.9, 1.0)
	},
	"marauder": {
		"display_name": "Marauder",
		"base_health": 100,
		"base_damage": 50,
		"base_speed": 3.0,
		"attack_rate": 1.2,
		"point_value": 50,
		"color": Color(0.5, 0.4, 0.3),
		"scale": Vector3(1.0, 1.0, 1.0)
	},
	"dragoon": {
		"display_name": "Dragoon",
		"base_health": 150,
		"base_damage": 75,
		"base_speed": 3.2,
		"attack_rate": 1.5,
		"point_value": 70,
		"can_pounce": true,
		"pounce_range": 8.0,
		"color": Color(0.6, 0.3, 0.3),
		"scale": Vector3(1.2, 1.2, 1.2)
	},
	"tyrant": {
		"display_name": "Tyrant",
		"base_health": 500,
		"base_damage": 150,
		"base_speed": 2.0,
		"attack_rate": 2.0,
		"point_value": 200,
		"color": Color(0.3, 0.2, 0.2),
		"scale": Vector3(1.8, 2.0, 1.8)
	}
}

# References set by game controller
var zombies_container: Node3D
var spawn_positions: Array[Vector3] = []

# Wave state
var current_wave: int = 0
var zombies_to_spawn: int = 0
var zombies_spawned: int = 0
var is_spawning: bool = false

var spawn_timer: float = 0.0
var spawn_delay: float = SPAWN_DELAY_BASE


func _ready() -> void:
	if not multiplayer.is_server():
		set_process(false)


func _process(delta: float) -> void:
	if not is_spawning:
		return

	if zombies_to_spawn <= 0:
		is_spawning = false
		return

	# Check if we can spawn more
	var active_zombies := zombies_container.get_child_count() if zombies_container else 0
	if active_zombies >= MAX_ACTIVE_ZOMBIES:
		return

	spawn_timer -= delta
	if spawn_timer <= 0:
		_spawn_zombie()
		spawn_timer = spawn_delay


func start_wave(wave_number: int) -> void:
	if not multiplayer.is_server():
		return

	current_wave = wave_number
	zombies_spawned = 0

	# Calculate zombies for this wave
	zombies_to_spawn = GameManager.zombies_remaining

	# Calculate spawn delay (faster in later rounds)
	spawn_delay = max(SPAWN_DELAY_MIN, SPAWN_DELAY_BASE - (wave_number * 0.1))

	is_spawning = true
	spawn_timer = 1.0  # Initial delay before first spawn

	wave_started.emit(wave_number)

	print("Wave %d started: %d zombies to spawn, %d spawn positions, container: %s" % [
		wave_number,
		zombies_to_spawn,
		spawn_positions.size(),
		zombies_container != null
	])


func _spawn_zombie() -> void:
	if not zombies_container:
		push_warning("No zombies container set")
		return

	if spawn_positions.is_empty():
		push_warning("No spawn positions available")
		return

	# Determine enemy type based on wave
	var enemy_type := _get_enemy_type_for_spawn()

	# Get spawn position
	var spawn_pos := spawn_positions[randi() % spawn_positions.size()]

	# Spawn on all clients
	rpc("_spawn_enemy_at", enemy_type, spawn_pos)

	zombies_spawned += 1
	zombies_to_spawn -= 1


@rpc("authority", "call_local", "reliable")
func _spawn_enemy_at(enemy_type: String, spawn_pos: Vector3) -> void:
	var scene: PackedScene = enemy_scenes.get(enemy_type, enemy_scenes["dretch"])
	var zombie: CharacterBody3D = scene.instantiate() as CharacterBody3D

	# Apply configuration
	var config: Dictionary = enemy_configs.get(enemy_type, enemy_configs["dretch"])

	zombie.enemy_type = enemy_type
	zombie.display_name = config.get("display_name", "Zombie")
	zombie.base_health = config.get("base_health", 30)
	zombie.base_damage = config.get("base_damage", 20)
	zombie.base_speed = config.get("base_speed", 4.0)
	zombie.attack_rate = config.get("attack_rate", 1.0)
	zombie.point_value = config.get("point_value", 10)
	zombie.can_pounce = config.get("can_pounce", false)

	if config.has("pounce_range"):
		zombie.pounce_range = config["pounce_range"]

	# Add to tree first, then set position
	zombies_container.add_child(zombie)
	zombie.global_position = spawn_pos

	# Apply scale and color after adding to tree
	if config.has("scale"):
		zombie.scale = config["scale"]

	var mesh := zombie.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh and config.has("color"):
		var material := mesh.get_surface_override_material(0)
		if material:
			material = material.duplicate()
			material.albedo_color = config["color"]
			mesh.set_surface_override_material(0, material)

	AudioManager.play_sound_3d("zombie_spawn", spawn_pos, -10.0)
	zombie_spawned.emit(zombie)


func _get_enemy_type_for_spawn() -> String:
	# Special rounds
	if GameManager.is_special_round():
		# Swarm round - all dretch
		return "dretch"

	# Tyrant round - spawn one tyrant
	if GameManager.is_tyrant_round() and zombies_spawned == 0:
		AudioManager.play_sound_3d("tyrant_roar", Vector3.ZERO)
		return "tyrant"

	# Normal wave composition based on round
	var roll := randf()

	if current_wave < 3:
		# Early rounds - mostly dretch
		return "dretch"

	elif current_wave < 6:
		# Mid-early - dretch and basilisk
		if roll < 0.7:
			return "dretch"
		else:
			return "basilisk"

	elif current_wave < 10:
		# Mid rounds - add marauder
		if roll < 0.4:
			return "dretch"
		elif roll < 0.7:
			return "basilisk"
		else:
			return "marauder"

	elif current_wave < 15:
		# Later rounds - add dragoon
		if roll < 0.25:
			return "dretch"
		elif roll < 0.5:
			return "basilisk"
		elif roll < 0.75:
			return "marauder"
		else:
			return "dragoon"

	else:
		# High rounds - all types including occasional tyrant
		if roll < 0.15:
			return "dretch"
		elif roll < 0.35:
			return "basilisk"
		elif roll < 0.55:
			return "marauder"
		elif roll < 0.85:
			return "dragoon"
		else:
			return "tyrant"


func get_active_zombie_count() -> int:
	if zombies_container:
		return zombies_container.get_child_count()
	return 0


func kill_all_zombies() -> void:
	if not zombies_container:
		return

	for zombie in zombies_container.get_children():
		if zombie.has_method("die"):
			zombie.die()
