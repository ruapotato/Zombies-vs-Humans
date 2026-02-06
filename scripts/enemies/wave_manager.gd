extends Node
## WaveManager - Controls zombie spawning in waves

const EnemyScript = preload("res://scripts/enemies/enemy_base.gd")

signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal zombie_spawned(zombie: Node)

# Spawn timing - creates waves of intensity within rounds
const SPAWN_DELAY_EARLY := 0.4  # Early rounds: relaxed pace to learn
const SPAWN_DELAY_MID := 0.15  # Mid rounds: building pressure
const SPAWN_DELAY_LATE := 0.06  # Late rounds: horde mode
const SPAWN_DELAY_SURGE := 0.03  # Surge rounds: overwhelming
const MAX_ACTIVE_ZOMBIES := 400  # Allow massive hordes
const SPAWNS_PER_TICK_BASE := 3  # Base zombies per spawn tick
const SPAWNS_PER_TICK_MAX := 8  # Max zombies per tick in late game

# Set to true to use simple capsule zombies for performance testing
const USE_SIMPLE_ZOMBIES := true

# Cached zombie count to avoid get_child_count() every frame
var cached_zombie_count: int = 0
var zombie_count_update_timer: float = 0.0
const ZOMBIE_COUNT_UPDATE_INTERVAL := 0.25  # Update count 4x per second

# Enemy scenes - each type has its own distinct model
var enemy_scenes: Dictionary = {
	"walker": preload("res://scenes/enemies/walker.tscn"),
	"runner": preload("res://scenes/enemies/runner.tscn"),
	"brute": preload("res://scenes/enemies/brute.tscn"),
	"leaper": preload("res://scenes/enemies/leaper.tscn"),
	"tank": preload("res://scenes/enemies/tank.tscn")
}

# Simple zombie for performance testing
var simple_zombie_scene: PackedScene = preload("res://scenes/enemies/billboard_zombie.tscn")

# Enemy type configurations (reduced health for horde mode)
var enemy_configs: Dictionary = {
	"walker": {
		"display_name": "Walker",
		"base_health": 100,
		"base_damage": 20,
		"base_speed": 2.5,
		"attack_rate": 1.0,
		"point_value": 10,
		"color": Color(0.4, 0.5, 0.3),
		"scale": Vector3(1.0, 1.0, 1.0)
	},
	"runner": {
		"display_name": "Runner",
		"base_health": 80,
		"base_damage": 25,
		"base_speed": 4.0,
		"attack_rate": 0.8,
		"point_value": 20,
		"color": Color(0.5, 0.4, 0.4),
		"scale": Vector3(1.0, 1.0, 1.0)
	},
	"brute": {
		"display_name": "Brute",
		"base_health": 300,
		"base_damage": 35,
		"base_speed": 2.2,
		"attack_rate": 1.5,
		"point_value": 50,
		"color": Color(0.5, 0.4, 0.3),
		"scale": Vector3(1.1, 1.1, 1.1)
	},
	"leaper": {
		"display_name": "Leaper",
		"base_health": 120,
		"base_damage": 30,
		"base_speed": 3.5,
		"attack_rate": 1.2,
		"point_value": 40,
		"can_pounce": true,
		"pounce_range": 6.0,
		"color": Color(0.6, 0.3, 0.3),
		"scale": Vector3(1.0, 1.0, 1.0)
	},
	"tank": {
		"display_name": "Tank",
		"base_health": 1500,
		"base_damage": 60,
		"base_speed": 1.8,
		"attack_rate": 2.0,
		"point_value": 200,
		"color": Color(0.3, 0.25, 0.25),
		"scale": Vector3(1.3, 1.3, 1.3)
	}
}

# References set by game controller
var zombies_container: Node3D
var spawn_positions: Array[Vector3] = []
var barrier_spawn_points: Array[Dictionary] = []  # {position: Vector3, barrier: Node}

# Wave state
var current_wave: int = 0
var zombies_to_spawn: int = 0
var zombies_spawned: int = 0
var is_spawning: bool = false

var spawn_timer: float = 0.0
var spawn_delay: float = SPAWN_DELAY_EARLY


func _ready() -> void:
	if not multiplayer.is_server():
		set_process(false)


func _process(delta: float) -> void:
	# Update cached zombie count periodically
	zombie_count_update_timer -= delta
	if zombie_count_update_timer <= 0:
		zombie_count_update_timer = ZOMBIE_COUNT_UPDATE_INTERVAL
		cached_zombie_count = zombies_container.get_child_count() if zombies_container else 0

	if not is_spawning:
		return

	if zombies_to_spawn <= 0:
		is_spawning = false
		return

	# Check if we can spawn more (use cached count)
	if cached_zombie_count >= MAX_ACTIVE_ZOMBIES:
		return

	spawn_timer -= delta
	if spawn_timer <= 0:
		# Spawn multiple zombies per tick - scales with wave
		var spawns_per_tick := _get_spawns_per_tick()
		var spawn_count := mini(spawns_per_tick, zombies_to_spawn)
		spawn_count = mini(spawn_count, MAX_ACTIVE_ZOMBIES - cached_zombie_count)

		for i in spawn_count:
			_spawn_zombie()
			cached_zombie_count += 1

		spawn_timer = spawn_delay


func start_wave(wave_number: int) -> void:
	if not multiplayer.is_server():
		return

	current_wave = wave_number
	zombies_spawned = 0

	# Calculate zombies for this wave
	zombies_to_spawn = GameManager.zombies_remaining

	# Dynamic spawn pacing based on wave number
	spawn_delay = _get_spawn_delay_for_wave(wave_number)

	is_spawning = true
	spawn_timer = 1.0  # Brief calm before the storm

	wave_started.emit(wave_number)



func _get_spawn_delay_for_wave(wave: int) -> float:
	# Horde surge rounds spawn extra fast
	if GameManager.is_horde_surge_round():
		return SPAWN_DELAY_SURGE

	# Pacing curve
	if wave <= 3:
		return SPAWN_DELAY_EARLY  # Relaxed early game
	elif wave <= 7:
		return lerpf(SPAWN_DELAY_EARLY, SPAWN_DELAY_MID, (wave - 3) / 4.0)
	elif wave <= 12:
		return SPAWN_DELAY_MID  # Building tension
	elif wave <= 18:
		return lerpf(SPAWN_DELAY_MID, SPAWN_DELAY_LATE, (wave - 12) / 6.0)
	else:
		return SPAWN_DELAY_LATE  # Full horde mode


func _get_spawns_per_tick() -> int:
	# More zombies spawn per tick in later waves
	if current_wave <= 5:
		return SPAWNS_PER_TICK_BASE
	elif current_wave <= 10:
		return SPAWNS_PER_TICK_BASE + 1
	elif current_wave <= 15:
		return SPAWNS_PER_TICK_BASE + 2
	else:
		return SPAWNS_PER_TICK_MAX


func _spawn_zombie() -> void:
	if not zombies_container:
		push_warning("No zombies container set")
		return

	if spawn_positions.is_empty() and barrier_spawn_points.is_empty():
		push_warning("No spawn positions available")
		return

	# Determine enemy type based on wave
	var enemy_type := _get_enemy_type_for_spawn()

	# Get spawn position from regular spawn points (outside the playable area)
	var spawn_pos: Vector3 = spawn_positions[randi_range(0, spawn_positions.size() - 1)]

	# Spawn on all clients
	rpc("_spawn_enemy_at", enemy_type, spawn_pos)

	zombies_spawned += 1
	zombies_to_spawn -= 1


@rpc("authority", "call_local", "reliable")
func _spawn_enemy_at(enemy_type: String, spawn_pos: Vector3) -> void:
	var scene: PackedScene
	if USE_SIMPLE_ZOMBIES:
		scene = simple_zombie_scene
	else:
		scene = enemy_scenes.get(enemy_type, enemy_scenes["walker"])
	var zombie: Node3D = scene.instantiate()

	# Apply configuration using set() for compatibility
	var config: Dictionary = enemy_configs.get(enemy_type, enemy_configs["walker"])

	zombie.set("enemy_type", enemy_type)
	zombie.set("display_name", config.get("display_name", "Zombie"))
	zombie.set("base_health", config.get("base_health", 30))
	zombie.set("base_damage", config.get("base_damage", 20))
	zombie.set("base_speed", config.get("base_speed", 4.0))
	zombie.set("attack_rate", config.get("attack_rate", 1.0))
	zombie.set("point_value", config.get("point_value", 10))
	zombie.set("can_pounce", config.get("can_pounce", false))

	if config.has("pounce_range"):
		zombie.set("pounce_range", config["pounce_range"])

	# Add to tree first, then set position
	zombies_container.add_child(zombie)
	zombie.global_position = spawn_pos

	# Apply scale and color after adding to tree
	if config.has("scale"):
		zombie.scale = config["scale"]

	# Apply color to zombie
	if config.has("color"):
		var base_color: Color = config["color"]

		# For billboard zombies - tint the sprite
		var sprite := zombie.get_node_or_null("Sprite3D") as Sprite3D
		if sprite:
			# Tint toward the color while keeping some original
			sprite.modulate = base_color.lightened(0.3)
		else:
			# For mesh-based zombies
			var limb_color := base_color.darkened(0.12)
			_apply_color_to_mesh(zombie, "Model/SimpleMesh", base_color)
			_apply_color_to_mesh(zombie, "Model/DetailParts/Body", base_color)
			_apply_color_to_mesh(zombie, "Model/DetailParts/Head/Mesh", base_color.lightened(0.1))
			_apply_color_to_mesh(zombie, "Model/DetailParts/LeftArm", limb_color)
			_apply_color_to_mesh(zombie, "Model/DetailParts/RightArm", limb_color)
			_apply_color_to_mesh(zombie, "Model/DetailParts/LeftLeg", limb_color)
			_apply_color_to_mesh(zombie, "Model/DetailParts/RightLeg", limb_color)

	AudioManager.play_sound_3d("zombie_spawn", spawn_pos, -10.0)
	zombie_spawned.emit(zombie)


func _get_enemy_type_for_spawn() -> String:
	# Boss rounds spawn Tank first, then mixed horde
	if GameManager.is_boss_round():
		if zombies_spawned == 0:
			AudioManager.play_sound_3d("tank_roar", Vector3.ZERO)
			return "tank"
		# After tank, spawn tough mix
		var roll := randf()
		if roll < 0.3:
			return "brute"
		elif roll < 0.6:
			return "leaper"
		elif roll < 0.9:
			return "runner"
		else:
			return "walker"

	# Horde surge rounds - fast weak zombies (quantity over quality)
	if GameManager.is_horde_surge_round():
		var roll := randf()
		if roll < 0.6:
			return "walker"
		elif roll < 0.85:
			return "runner"
		else:
			return "leaper"

	# Normal wave composition - gradual introduction of types
	var roll := randf()

	if current_wave <= 2:
		# Tutorial rounds - just walkers
		return "walker"

	elif current_wave <= 4:
		# Introduce runners
		if roll < 0.75:
			return "walker"
		else:
			return "runner"

	elif current_wave <= 6:
		# More runners, runners get dangerous
		if roll < 0.5:
			return "walker"
		else:
			return "runner"

	elif current_wave <= 8:
		# Introduce brutes
		if roll < 0.35:
			return "walker"
		elif roll < 0.7:
			return "runner"
		else:
			return "brute"

	elif current_wave <= 11:
		# Introduce leapers
		if roll < 0.25:
			return "walker"
		elif roll < 0.5:
			return "runner"
		elif roll < 0.75:
			return "brute"
		else:
			return "leaper"

	elif current_wave <= 15:
		# Full variety, leaning dangerous
		if roll < 0.15:
			return "walker"
		elif roll < 0.35:
			return "runner"
		elif roll < 0.6:
			return "brute"
		else:
			return "leaper"

	else:
		# Endgame - mostly dangerous types, occasional tank
		if roll < 0.1:
			return "walker"
		elif roll < 0.25:
			return "runner"
		elif roll < 0.45:
			return "brute"
		elif roll < 0.85:
			return "leaper"
		else:
			return "tank"


func get_active_zombie_count() -> int:
	return cached_zombie_count


func register_barrier_spawn_points(barriers_node: Node) -> void:
	barrier_spawn_points.clear()
	if not barriers_node:
		return

	for barrier in barriers_node.get_children():
		if barrier.has_method("get_spawn_position"):
			barrier_spawn_points.append({
				"position": barrier.get_spawn_position(),
				"barrier": barrier
			})



func kill_all_zombies() -> void:
	if not zombies_container:
		return

	for zombie in zombies_container.get_children():
		if zombie.has_method("die"):
			zombie.die()


func _apply_color_to_mesh(zombie: Node3D, path: String, color: Color) -> void:
	var mesh := zombie.get_node_or_null(path) as MeshInstance3D
	if not mesh:
		return

	var material := mesh.get_surface_override_material(0)
	if material:
		material = material.duplicate()
		material.albedo_color = color
		mesh.set_surface_override_material(0, material)
