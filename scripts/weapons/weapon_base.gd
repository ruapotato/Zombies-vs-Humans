extends Node3D
class_name Weapon
## Base weapon class with shooting, reloading, and damage

signal ammo_changed(current_ammo: int, reserve_ammo: int)
signal reloading_started
signal reloading_finished
signal weapon_fired

@export var weapon_id: String = "m1911"
var owner_player: Node = null

# Stats (loaded from WeaponData)
var display_name: String = "Weapon"
var weapon_type: int = 0

var base_damage: int = 30
var headshot_multiplier: float = 2.0
var pellet_count: int = 1

var fire_rate: float = 0.2
var is_automatic: bool = false

var magazine_size: int = 8
var max_reserve: int = 80

var reload_time: float = 1.5
var reload_slows_movement: bool = false
var reload_speed_multiplier: float = 1.0
var reload_cancellable: bool = false

var spread: float = 0.0
var aim_spread: float = 0.0
var recoil: float = 0.05

var max_range: float = 100.0

var fire_sound: String = "pistol_fire"
var reload_sound: String = "reload"

# Runtime state
var current_ammo: int = 8
var reserve_ammo: int = 80
var is_reloading: bool = false
var can_fire: bool = true
var is_aiming: bool = false
var is_pack_a_punched: bool = false
var pap_damage_multiplier: float = 2.0
var pap_special_effect: String = ""

# Hit effect scenes
var hit_effect_scene: PackedScene = preload("res://scenes/effects/hit_effect.tscn")
var headshot_effect_scene: PackedScene = preload("res://scenes/effects/headshot_effect.tscn")

# Components
@onready var model: MeshInstance3D = $Model
@onready var muzzle_point: Marker3D = $MuzzlePoint
@onready var fire_timer: Timer = $FireTimer
@onready var reload_timer: Timer = $ReloadTimer
@onready var muzzle_flash: OmniLight3D = $MuzzlePoint/MuzzleFlash


func _ready() -> void:
	_load_weapon_data()
	current_ammo = magazine_size
	reserve_ammo = max_reserve


func _load_weapon_data() -> void:
	var registry_script: GDScript = load("res://scripts/weapons/weapon_registry.gd")
	var data: Resource = registry_script.get_weapon_data(weapon_id)
	if not data:
		push_warning("Weapon data not found for: %s" % weapon_id)
		return

	display_name = data.display_name
	weapon_type = data.weapon_type

	base_damage = data.base_damage
	headshot_multiplier = data.headshot_multiplier
	pellet_count = data.pellet_count

	fire_rate = data.fire_rate
	is_automatic = data.is_automatic

	magazine_size = data.magazine_size
	max_reserve = data.max_reserve

	reload_time = data.reload_time
	reload_slows_movement = data.reload_slows_movement
	reload_speed_multiplier = data.reload_speed_multiplier
	reload_cancellable = data.reload_cancellable

	spread = data.spread
	aim_spread = data.aim_spread
	recoil = data.recoil

	max_range = data.max_range

	fire_sound = data.fire_sound
	reload_sound = data.reload_sound

	pap_damage_multiplier = data.pap_damage_multiplier
	pap_special_effect = data.pap_special_effect

	fire_timer.wait_time = fire_rate
	reload_timer.wait_time = reload_time


func try_shoot() -> bool:
	if not can_fire:
		return false

	if is_reloading:
		return false

	if current_ammo <= 0:
		# Empty click
		AudioManager.play_sound_3d("empty_clip", global_position, -5.0)
		try_reload()
		return false

	if not owner_player:
		push_warning("Weapon has no owner_player set!")
		return false

	_shoot()
	return true


func _shoot() -> void:
	can_fire = false
	current_ammo -= 1

	# Apply fire rate modifier from Double Tap
	var actual_fire_rate := fire_rate
	if owner_player and owner_player.has_perk("double_tap"):
		actual_fire_rate *= 0.67

	# Apply Speed Cola to fire rate slightly
	if owner_player and owner_player.has_perk("speed_cola"):
		actual_fire_rate *= 0.93

	fire_timer.wait_time = actual_fire_rate
	fire_timer.start()

	# Calculate damage
	var damage := base_damage
	if is_pack_a_punched:
		damage = int(damage * pap_damage_multiplier)

	# Insta-kill power-up
	if GameManager.is_power_up_active("insta_kill"):
		damage = 9999

	# Calculate spread - ADS is much more accurate (half the aim_spread)
	var current_spread := (aim_spread * 0.5) if is_aiming else spread

	# Fire pellets (for shotguns)
	for i in range(pellet_count):
		_fire_pellet(damage, current_spread)

	# Effects
	_play_fire_effects()

	# Apply recoil
	_apply_recoil()

	# Network sync
	if owner_player:
		rpc("_sync_shoot")

	ammo_changed.emit(current_ammo, reserve_ammo)
	weapon_fired.emit()


func _fire_pellet(damage: int, current_spread: float) -> void:
	if not owner_player:
		return

	var camera: Camera3D = owner_player.get_node("CameraMount/Camera3D")
	if not camera:
		return

	# Calculate direction with spread
	var direction := -camera.global_transform.basis.z

	if current_spread > 0:
		var spread_rad := deg_to_rad(current_spread)
		direction = direction.rotated(camera.global_transform.basis.x, randf_range(-spread_rad, spread_rad))
		direction = direction.rotated(camera.global_transform.basis.y, randf_range(-spread_rad, spread_rad))

	# Raycast
	var space_state := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from + direction * max_range

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b1101  # World, enemy, interactable
	query.exclude = [owner_player]

	var result := space_state.intersect_ray(query)

	if result:
		var hit_point: Vector3 = result.position
		var hit_normal: Vector3 = result.normal
		var collider: Object = result.collider

		# Check if headshot
		var is_headshot := false
		if collider and collider.has_method("get_parent") and collider.get_parent() and collider.get_parent().name == "HeadHitbox":
			is_headshot = true

		# Find the enemy node for damage calculation
		var enemy_node: Node = null
		if collider.has_method("take_damage"):
			enemy_node = collider
		elif collider.get_parent() and collider.get_parent().has_method("take_damage"):
			enemy_node = collider.get_parent()

		# Calculate final damage - pass hit_point for distance-based damage
		var final_damage := damage
		if is_headshot:
			final_damage = int(damage * headshot_multiplier)

		# Apply damage with hit position for distance-based calculation
		if enemy_node:
			enemy_node.take_damage(final_damage, owner_player, is_headshot, hit_point)

		# Spawn appropriate hit effect
		_spawn_hit_effect(hit_point, hit_normal, is_headshot)


func _play_fire_effects() -> void:
	# Sound
	AudioManager.play_sound_3d(fire_sound, global_position, 0.0, randf_range(0.98, 1.02))

	# Muzzle flash
	if muzzle_flash:
		muzzle_flash.visible = true
		await get_tree().create_timer(0.05).timeout
		muzzle_flash.visible = false


func _apply_recoil() -> void:
	if not owner_player:
		return

	var camera_mount: Node3D = owner_player.get_node("CameraMount")
	if camera_mount:
		# Apply vertical recoil
		var recoil_amount := recoil
		if is_aiming:
			recoil_amount *= 0.6

		camera_mount.rotation.x -= recoil_amount

		# Clamp pitch
		camera_mount.rotation.x = clamp(camera_mount.rotation.x, deg_to_rad(-89), deg_to_rad(89))


func _spawn_hit_effect(hit_position: Vector3, normal: Vector3, is_headshot: bool = false) -> void:
	var effect: Node3D
	if is_headshot:
		effect = headshot_effect_scene.instantiate()
		AudioManager.play_sound_3d("hit_head", hit_position, 0.0)
	else:
		effect = hit_effect_scene.instantiate()
		AudioManager.play_sound_3d("hit_body", hit_position, -3.0)

	# Add to scene tree
	get_tree().current_scene.add_child(effect)
	effect.global_position = hit_position

	# Orient effect along hit normal (optional, looks better for sparks)
	if normal != Vector3.ZERO:
		effect.look_at(hit_position + normal, Vector3.UP)


@rpc("any_peer", "call_remote", "unreliable")
func _sync_shoot() -> void:
	# Play effects for other players
	_play_fire_effects()


func try_reload() -> bool:
	if is_reloading:
		return false

	if current_ammo >= magazine_size:
		return false

	if reserve_ammo <= 0:
		return false

	_start_reload()
	return true


func _start_reload() -> void:
	is_reloading = true

	# Speed Cola effect
	var actual_reload_time := reload_time
	if owner_player and owner_player.has_perk("speed_cola"):
		actual_reload_time *= 0.5

	reload_timer.wait_time = actual_reload_time
	reload_timer.start()

	AudioManager.play_sound_3d(reload_sound, global_position)
	reloading_started.emit()

	if owner_player:
		owner_player.is_reloading = true


func _finish_reload() -> void:
	is_reloading = false

	var needed: int = magazine_size - current_ammo
	var available: int = min(needed, reserve_ammo) as int

	current_ammo += available
	reserve_ammo -= available

	ammo_changed.emit(current_ammo, reserve_ammo)
	reloading_finished.emit()

	if owner_player:
		owner_player.is_reloading = false


func cancel_reload() -> void:
	if not is_reloading:
		return

	if not reload_cancellable:
		return

	is_reloading = false
	reload_timer.stop()

	if owner_player:
		owner_player.is_reloading = false


func set_aiming(aiming: bool) -> void:
	is_aiming = aiming
	# Weapon position is controlled by gun_mount, no offset needed


func refill_ammo() -> void:
	reserve_ammo = max_reserve
	ammo_changed.emit(current_ammo, reserve_ammo)


func add_ammo(amount: int) -> void:
	reserve_ammo = min(reserve_ammo + amount, max_reserve)
	ammo_changed.emit(current_ammo, reserve_ammo)


func pack_a_punch() -> void:
	if is_pack_a_punched:
		return

	is_pack_a_punched = true

	# Update weapon name
	var registry_script: GDScript = load("res://scripts/weapons/weapon_registry.gd")
	var data: Resource = registry_script.get_weapon_data(weapon_id)
	if data and data.pap_name != "":
		display_name = data.pap_name

	# Increase magazine if specified
	if data and data.pap_magazine_bonus > 0:
		magazine_size += data.pap_magazine_bonus

	# Refill ammo
	current_ammo = magazine_size
	reserve_ammo = max_reserve

	ammo_changed.emit(current_ammo, reserve_ammo)


func get_total_ammo() -> int:
	return current_ammo + reserve_ammo


func _on_fire_timer_timeout() -> void:
	can_fire = true


func _on_reload_timer_timeout() -> void:
	_finish_reload()
