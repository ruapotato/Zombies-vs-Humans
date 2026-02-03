extends CharacterBody3D
class_name Player
## Player controller with FPS movement, health, weapons, and perks

signal health_changed(new_health: int, max_health: int)
signal points_changed(new_points: int)
signal weapon_changed(weapon: Node)
signal downed()
signal revived()
signal perk_acquired(perk_name: String)
signal perk_lost(perk_name: String)

# Networked properties
@export var player_id: int = 1
@export var player_name: String = "Player"
@export var player_color: Color = Color.WHITE

# Movement
const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const CROUCH_SPEED := 2.5
const JUMP_VELOCITY := 6.0
const ACCELERATION := 15.0
const FRICTION := 10.0
const AIR_CONTROL := 0.3

var current_speed := WALK_SPEED
var is_sprinting := false
var is_crouching := false
var can_sprint := true

# Health
const BASE_HEALTH := 100
const JUGGERNOG_HEALTH := 250
const BLEEDOUT_TIME := 45.0
const REVIVE_TIME := 4.0

var health: int = BASE_HEALTH
var max_health: int = BASE_HEALTH
var is_downed := false
var bleedout_timer := 0.0
var revive_progress := 0.0
var reviver: Player = null

# Points
var points: int = 500  # Starting points

# Weapons
var weapons: Array[Node] = []
var current_weapon_index := 0
var max_weapons := 2
var is_reloading := false

# Perks
var perks: Array[String] = []
const MAX_PERKS := 4

# Input tracking for network sync
var input_direction := Vector2.ZERO
var look_rotation := Vector2.ZERO  # x = yaw, y = pitch

# Components
@onready var camera_mount: Node3D = $CameraMount
@onready var camera: Camera3D = $CameraMount/Camera3D
@onready var weapon_holder: Node3D = $CameraMount/Camera3D/WeaponHolder
@onready var aim_ray: RayCast3D = $CameraMount/Camera3D/RayCast3D
@onready var interaction_ray: RayCast3D = $CameraMount/Camera3D/InteractionRay
@onready var model: Node3D = $Model
@onready var footstep_timer: Timer = $FootstepTimer

# Animation
var anim_player: AnimationPlayer = null
var current_anim: String = ""
const ANIM_IDLE := "m root"
const ANIM_RUN := "m run"
const ANIM_JUMP := "m jump"


func _ready() -> void:
	print("=== PLAYER _ready() called, authority: ", is_multiplayer_authority(), " ===")

	# Find AnimationPlayer in model
	if model:
		_find_animation_player(model)
		if anim_player:
			_play_animation(ANIM_IDLE)

	# Set up based on authority
	if is_multiplayer_authority():
		camera.current = true
		$CameraMount/Camera3D/AudioListener3D.make_current()
		model.visible = false  # Hide own model in first person
	else:
		camera.current = false
		set_physics_process(false)

	# Give starting weapon
	_give_starting_weapon()


func _find_animation_player(node: Node) -> void:
	if node is AnimationPlayer:
		anim_player = node as AnimationPlayer
		return
	for child in node.get_children():
		_find_animation_player(child)
		if anim_player:
			return


func _play_animation(anim_name: String, speed: float = 1.0) -> void:
	if not anim_player:
		return
	if current_anim == anim_name and anim_player.is_playing():
		return
	if anim_player.has_animation(anim_name):
		current_anim = anim_name
		anim_player.play(anim_name, -1, speed)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if is_downed:
		_process_downed(delta)
		return

	# Handle movement input
	_handle_movement_input(delta)

	# Handle weapon input
	_handle_weapon_input()

	# Handle interaction
	_handle_interaction()

	# Apply gravity
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	move_and_slide()

	# Footstep sounds
	if is_on_floor() and velocity.length() > 0.5 and footstep_timer.is_stopped():
		AudioManager.play_sound_3d("footstep", global_position, -10.0, randf_range(0.9, 1.1))
		footstep_timer.start(0.3 if is_sprinting else 0.4)


func _handle_movement_input(delta: float) -> void:
	input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# Sprinting
	is_sprinting = Input.is_action_pressed("sprint") and can_sprint and not is_crouching

	# Determine speed
	if is_sprinting:
		current_speed = SPRINT_SPEED
		if has_perk("stamin_up"):
			current_speed = SPRINT_SPEED * 1.2
	elif is_crouching:
		current_speed = CROUCH_SPEED
	else:
		current_speed = WALK_SPEED

	# Speed Cola affects movement slightly
	if has_perk("speed_cola"):
		current_speed *= 1.07

	# Calculate movement direction
	var direction: Vector3 = (transform.basis * Vector3(input_direction.x, 0, input_direction.y)).normalized()

	if direction:
		var accel: float = ACCELERATION if is_on_floor() else ACCELERATION * AIR_CONTROL
		velocity.x = move_toward(velocity.x, direction.x * current_speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, accel * delta)
	else:
		var friction_val: float = FRICTION if is_on_floor() else FRICTION * AIR_CONTROL
		velocity.x = move_toward(velocity.x, 0, friction_val * delta)
		velocity.z = move_toward(velocity.z, 0, friction_val * delta)

	# Jumping
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		_play_animation(ANIM_JUMP, 1.5)
		AudioManager.play_sound_3d("jump", global_position, -5.0)

	# Update animation based on movement
	if is_on_floor():
		if velocity.length() > 0.5:
			_play_animation(ANIM_RUN, 1.0 if not is_sprinting else 1.5)
		else:
			_play_animation(ANIM_IDLE)


func _handle_weapon_input() -> void:
	if weapons.is_empty():
		return

	var current_weapon: Node = get_current_weapon()
	if not current_weapon:
		return

	# Shooting
	if Input.is_action_pressed("shoot"):
		if not is_sprinting and not is_reloading:
			if current_weapon.has_method("try_shoot"):
				current_weapon.try_shoot()

	# Aiming
	if Input.is_action_pressed("aim"):
		if current_weapon.has_method("set_aiming"):
			current_weapon.set_aiming(true)
	else:
		if current_weapon.has_method("set_aiming"):
			current_weapon.set_aiming(false)

	# Reload
	if Input.is_action_just_pressed("reload"):
		if current_weapon.has_method("try_reload"):
			current_weapon.try_reload()

	# Switch weapon
	if Input.is_action_just_pressed("switch_weapon"):
		_switch_weapon()


func _switch_weapon() -> void:
	if weapons.size() <= 1:
		return

	current_weapon_index = (current_weapon_index + 1) % weapons.size()

	for i: int in range(weapons.size()):
		weapons[i].visible = (i == current_weapon_index)

	weapon_changed.emit(get_current_weapon())
	AudioManager.play_sound_3d("weapon_switch", global_position)

	# Sync to network
	rpc("_sync_weapon_switch", current_weapon_index)


@rpc("any_peer", "call_remote", "reliable")
func _sync_weapon_switch(index: int) -> void:
	current_weapon_index = index
	for i: int in range(weapons.size()):
		weapons[i].visible = (i == current_weapon_index)


func _handle_interaction() -> void:
	if not interaction_ray.is_colliding():
		return

	var collider: Object = interaction_ray.get_collider()
	if not collider:
		return

	if Input.is_action_just_pressed("interact"):
		if collider.has_method("interact"):
			collider.interact(self)


func get_current_weapon() -> Node:
	if weapons.is_empty() or current_weapon_index >= weapons.size():
		return null
	return weapons[current_weapon_index]


func _give_starting_weapon() -> void:
	# Give M1911 pistol
	print("Player _give_starting_weapon called, weapon_holder: ", weapon_holder)
	if not weapon_holder:
		push_error("weapon_holder is null!")
		return
	give_weapon("m1911")


func give_weapon(weapon_id_to_give: String) -> bool:
	if weapons.size() >= max_weapons:
		return false

	var weapon_scene_path: String = "res://scenes/weapons/guns/%s.tscn" % weapon_id_to_give
	if not ResourceLoader.exists(weapon_scene_path):
		weapon_scene_path = "res://scenes/weapons/weapon_base.tscn"

	var weapon_scene: PackedScene = load(weapon_scene_path)
	var weapon: Node3D = weapon_scene.instantiate() as Node3D

	# Set weapon properties directly
	if weapon.has_method("set_owner_player"):
		weapon.set_owner_player(self)
	else:
		weapon.owner_player = self
	weapon.weapon_id = weapon_id_to_give

	weapon_holder.add_child(weapon)
	weapons.append(weapon)

	# Hide if not current
	weapon.visible = (weapons.size() - 1 == current_weapon_index)

	weapon_changed.emit(get_current_weapon())
	print("Gave weapon: %s, owner: %s" % [weapon_id_to_give, weapon.owner_player])
	return true


func replace_weapon(weapon_id: String) -> void:
	if weapons.is_empty():
		give_weapon(weapon_id)
		return

	var old_weapon: Node = weapons[current_weapon_index]
	old_weapon.queue_free()

	var weapon_scene_path: String = "res://scenes/weapons/guns/%s.tscn" % weapon_id
	if not ResourceLoader.exists(weapon_scene_path):
		weapon_scene_path = "res://scenes/weapons/weapon_base.tscn"

	var weapon_scene: PackedScene = load(weapon_scene_path)
	var weapon: Node3D = weapon_scene.instantiate() as Node3D
	weapon.set("weapon_id", weapon_id)
	weapon.set("owner_player", self)

	weapon_holder.add_child(weapon)
	weapons[current_weapon_index] = weapon

	weapon_changed.emit(weapon)


func take_damage(amount: int, _attacker: Node = null) -> void:
	if is_downed:
		return

	health -= amount
	health_changed.emit(health, max_health)

	AudioManager.play_sound_3d("player_hurt", global_position)

	if health <= 0:
		_go_down()


func _go_down() -> void:
	is_downed = true
	health = 0
	bleedout_timer = BLEEDOUT_TIME
	revive_progress = 0.0

	# Quick Revive solo self-revive check
	if has_perk("quick_revive") and GameManager.players.size() == 1:
		# Auto self-revive after delay
		await get_tree().create_timer(3.0).timeout
		if is_downed:
			_revive()
			remove_perk("quick_revive")
		return

	downed.emit()
	AudioManager.play_sound_3d("player_down", global_position)

	# Notify server
	if multiplayer.is_server():
		_check_all_players_down()
	else:
		rpc_id(1, "_notify_player_downed")


@rpc("any_peer", "reliable")
func _notify_player_downed() -> void:
	if multiplayer.is_server():
		_check_all_players_down()


func _check_all_players_down() -> void:
	if GameManager.all_players_downed():
		GameManager.trigger_game_over()


func _process_downed(delta: float) -> void:
	bleedout_timer -= delta

	if bleedout_timer <= 0:
		_die()
		return

	# Check if being revived
	if reviver and is_instance_valid(reviver):
		var revive_speed: float = 1.0
		if reviver.has_perk("quick_revive"):
			revive_speed = 2.0

		revive_progress += delta * revive_speed

		if revive_progress >= REVIVE_TIME:
			_revive()
			if reviver:
				reviver.add_points(100)
				if reviver.player_id in GameManager.player_stats:
					GameManager.player_stats[reviver.player_id]["revives"] += 1


func start_revive(reviving_player: Player) -> void:
	reviver = reviving_player
	revive_progress = 0.0
	AudioManager.play_sound_3d("player_revive", global_position)


func stop_revive() -> void:
	reviver = null
	revive_progress = 0.0


func _revive() -> void:
	is_downed = false
	health = max_health / 2
	revive_progress = 0.0
	reviver = null

	health_changed.emit(health, max_health)
	revived.emit()
	AudioManager.play_sound_3d("player_revived", global_position)


func _die() -> void:
	is_downed = true
	health = 0

	# Record down in stats
	if player_id in GameManager.player_stats:
		GameManager.player_stats[player_id]["downs"] += 1

	# Check game over
	if multiplayer.is_server():
		_check_all_players_down()


func heal(amount: int) -> void:
	health = min(health + amount, max_health)
	health_changed.emit(health, max_health)


func add_points(amount: int) -> void:
	points += amount
	points_changed.emit(points)
	AudioManager.play_sound_ui("points_gain", -10.0)


func spend_points(amount: int) -> bool:
	if points >= amount:
		points -= amount
		points_changed.emit(points)
		return true
	return false


func can_afford(amount: int) -> bool:
	return points >= amount


func add_perk(perk_name: String) -> bool:
	if perks.size() >= MAX_PERKS:
		return false

	if perk_name in perks:
		return false

	perks.append(perk_name)
	_apply_perk_effect(perk_name)
	perk_acquired.emit(perk_name)

	# Sync to network
	rpc("_sync_add_perk", perk_name)

	return true


@rpc("any_peer", "call_remote", "reliable")
func _sync_add_perk(perk_name: String) -> void:
	if perk_name not in perks:
		perks.append(perk_name)
		_apply_perk_effect(perk_name)


func remove_perk(perk_name: String) -> void:
	if perk_name in perks:
		perks.erase(perk_name)
		_remove_perk_effect(perk_name)
		perk_lost.emit(perk_name)

		rpc("_sync_remove_perk", perk_name)


@rpc("any_peer", "call_remote", "reliable")
func _sync_remove_perk(perk_name: String) -> void:
	if perk_name in perks:
		perks.erase(perk_name)
		_remove_perk_effect(perk_name)


func has_perk(perk_name: String) -> bool:
	return perk_name in perks


func _apply_perk_effect(perk_name: String) -> void:
	match perk_name:
		"juggernog":
			max_health = JUGGERNOG_HEALTH
			health = max_health
			health_changed.emit(health, max_health)

		"mule_kick":
			max_weapons = 3

		"stamin_up":
			can_sprint = true

		# Other perks are checked dynamically


func _remove_perk_effect(perk_name: String) -> void:
	match perk_name:
		"juggernog":
			max_health = BASE_HEALTH
			health = min(health, max_health)
			health_changed.emit(health, max_health)

		"mule_kick":
			max_weapons = 2
			# Drop third weapon if holding one
			if weapons.size() > 2:
				var dropped: Node = weapons.pop_back()
				dropped.queue_free()
				current_weapon_index = min(current_weapon_index, weapons.size() - 1)


func clear_perks() -> void:
	for perk_name: String in perks.duplicate():
		remove_perk(perk_name)


func refill_ammo() -> void:
	for weapon: Node in weapons:
		if weapon.has_method("refill_ammo"):
			weapon.refill_ammo()


func is_valid_target() -> bool:
	return not is_downed


# Network synchronization
func _on_sync_timer_timeout() -> void:
	if is_multiplayer_authority():
		rpc("_sync_state", global_position, rotation.y, camera_mount.rotation.x, velocity, health, is_downed)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync_state(pos: Vector3, yaw: float, pitch: float, vel: Vector3, hp: int, down: bool) -> void:
	if is_multiplayer_authority():
		return

	# Interpolate position
	global_position = global_position.lerp(pos, 0.5)
	rotation.y = yaw
	camera_mount.rotation.x = pitch
	velocity = vel
	health = hp
	is_downed = down


func _on_footstep_timer_timeout() -> void:
	pass  # Timer handles interval


# Input handling for camera is in player_camera.gd
