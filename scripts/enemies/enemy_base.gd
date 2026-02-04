extends CharacterBody3D
class_name Enemy
## Base enemy class with AI pathfinding, attacking, and health

signal died(enemy: Enemy, killer_id: int, is_headshot: bool)
signal damaged(amount: int, is_headshot: bool)

enum EnemyState { SPAWNING, IDLE, CHASING, ATTACKING, DYING, DEAD }

# Enemy type config (override in subclasses)
@export var enemy_type: String = "dretch"
@export var display_name: String = "Dretch"

# Base stats (scaled by round)
@export var base_health: int = 30
@export var base_damage: int = 20
@export var base_speed: float = 4.0
@export var attack_rate: float = 1.0
@export var point_value: int = 10

# Enemy dimensions for damage calculation
@export var enemy_height: float = 1.8
@export var head_position_y: float = 1.6

# Special abilities
@export var can_pounce: bool = false
@export var pounce_range: float = 5.0
@export var pounce_cooldown: float = 3.0

@export var has_special_attack: bool = false
@export var special_attack_type: String = ""

# Runtime state
var health: int = 30
var max_health: int = 30
var damage: int = 20
var speed: float = 4.0
var state: EnemyState = EnemyState.SPAWNING

var target_player: Node3D = null
var players_in_attack_range: Array[Node3D] = []
var can_attack: bool = true
var last_attacker_id: int = 0
var last_hit_was_headshot: bool = false

var pounce_timer: float = 0.0
var is_pouncing: bool = false

# Stuck detection and lifetime
const MAX_LIFETIME := 120.0  # Die after 2 minutes if stuck
const MAX_LIFETIME_LAST_ZOMBIE := 30.0  # Die faster if last zombie
const STUCK_CHECK_INTERVAL := 3.0  # Check stuck every 3 seconds
const STUCK_DISTANCE_THRESHOLD := 2.0  # Must move at least 2 units
var lifetime: float = 0.0
var stuck_check_timer: float = 0.0
var last_stuck_check_pos: Vector3 = Vector3.ZERO
var stuck_count: int = 0

# Varied pathing
var path_offset: Vector3 = Vector3.ZERO
var path_offset_timer: float = 0.0
const PATH_OFFSET_INTERVAL := 2.0
const PATH_OFFSET_RANGE := 5.0

# Jumping
var can_jump: bool = true
var jump_cooldown: float = 0.0
const JUMP_COOLDOWN_TIME := 1.5
const JUMP_FORCE := 10.0
var obstacle_check_timer: float = 0.0

# Components
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var model: Node3D = $Model
@onready var attack_timer: Timer = $AttackTimer
@onready var path_update_timer: Timer = $PathUpdateTimer

# Animation
var anim_player: AnimationPlayer = null
var current_anim: String = ""

# Animation names from the model (Godot strips _metarig suffix)
const ANIM_IDLE := "m root"
const ANIM_RUN := "m run"
const ANIM_DEATH := "m death"
const ANIM_ATTACK := "swipe"  # Proper attack animation


func _ready() -> void:
	# Find AnimationPlayer in model
	if model:
		_find_animation_player(model)
		if anim_player:
			print("Enemy: Found AnimationPlayer with ", anim_player.get_animation_list().size(), " animations")
			for anim_name in anim_player.get_animation_list():
				print("  - ", anim_name)
			_play_animation(ANIM_IDLE)
		else:
			push_warning("Enemy: No AnimationPlayer found in model!")
	# Only server controls enemies
	if not multiplayer.is_server():
		set_physics_process(false)
		return

	# Scale stats by round
	_scale_stats_for_round()

	# Start spawning animation
	state = EnemyState.SPAWNING
	await get_tree().create_timer(0.5).timeout
	state = EnemyState.CHASING

	# Set meta for point value
	set_meta("point_value", point_value)


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


func _scale_stats_for_round() -> void:
	var round_num := GameManager.current_round

	max_health = int(GameManager.get_zombie_health_for_round(base_health))
	health = max_health

	damage = int(GameManager.get_zombie_damage_for_round(base_damage))

	# Speed increases slightly
	speed = base_speed + (round_num * 0.1)
	speed = min(speed, base_speed * 1.5)  # Cap at 150% base speed


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	# Update lifetime and stuck detection
	lifetime += delta
	_update_stuck_detection(delta)

	# Kill zombie if stuck too long (faster if last zombie remaining)
	var is_last_zombie := GameManager.zombies_remaining <= 1 and _is_only_zombie_alive()
	var max_time := MAX_LIFETIME_LAST_ZOMBIE if is_last_zombie else MAX_LIFETIME

	if lifetime >= max_time:
		print("Zombie died from timeout (stuck for too long)")
		die()
		return

	match state:
		EnemyState.SPAWNING:
			_play_animation(ANIM_IDLE)

		EnemyState.IDLE:
			_play_animation(ANIM_IDLE)
			_find_target()

		EnemyState.CHASING:
			_play_animation(ANIM_RUN, 1.5)
			_chase_target(delta)

		EnemyState.ATTACKING:
			_attack_target(delta)

		EnemyState.DYING:
			pass  # Death animation handled in die()

		EnemyState.DEAD:
			pass

	# Apply gravity
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	# Handle pounce cooldown
	if pounce_timer > 0:
		pounce_timer -= delta

	# Handle jump cooldown
	if jump_cooldown > 0:
		jump_cooldown -= delta
	else:
		can_jump = true

	# Update path offset timer
	path_offset_timer -= delta
	if path_offset_timer <= 0:
		_update_path_offset()
		path_offset_timer = PATH_OFFSET_INTERVAL


func _find_target() -> void:
	var game_controller := get_tree().current_scene
	if game_controller and game_controller.has_method("get_nearest_player_to"):
		target_player = game_controller.get_nearest_player_to(global_position)

	if target_player:
		state = EnemyState.CHASING


func _chase_target(delta: float) -> void:
	if not target_player or not is_instance_valid(target_player):
		_find_target()
		if not target_player:
			state = EnemyState.IDLE
			return

	# Check if target is valid
	if target_player.has_method("is_valid_target") and not target_player.is_valid_target():
		_find_target()
		return

	# Check if in attack range
	if not players_in_attack_range.is_empty():
		state = EnemyState.ATTACKING
		return

	# Check for pounce opportunity
	if can_pounce and pounce_timer <= 0:
		var dist := global_position.distance_to(target_player.global_position)
		if dist <= pounce_range and dist > 2.0:
			_try_pounce()
			return

	# Move toward target using navigation
	if nav_agent.is_navigation_finished():
		return

	var next_pos := nav_agent.get_next_path_position()

	# Add path offset for varied movement (unless very close to target)
	var dist_to_target := global_position.distance_to(target_player.global_position)
	if dist_to_target > 5.0:
		next_pos += path_offset

	var direction := (next_pos - global_position).normalized()
	direction.y = 0

	# Check for obstacles and try to jump
	_check_and_jump(direction)

	# Lerp velocity for smoother direction changes
	var target_velocity_x := direction.x * speed
	var target_velocity_z := direction.z * speed
	velocity.x = lerpf(velocity.x, target_velocity_x, 0.08)
	velocity.z = lerpf(velocity.z, target_velocity_z, 0.08)

	# Add slight random strafing for unpredictable movement
	if randf() < 0.01:  # 1% chance per frame
		var strafe := Vector3(-direction.z, 0, direction.x) * randf_range(-1.0, 1.0)
		velocity.x += strafe.x
		velocity.z += strafe.z

	# Smoothly rotate to face movement direction
	if direction.length() > 0.1:
		var target_rot := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot, 0.1)

	move_and_slide()

	# Check if we hit a wall and should jump
	if is_on_wall() and can_jump and is_on_floor():
		_perform_jump()


func _attack_target(delta: float) -> void:
	if players_in_attack_range.is_empty():
		state = EnemyState.CHASING
		return

	# Attack if we can
	if can_attack:
		_perform_attack()


func _perform_attack() -> void:
	can_attack = false
	attack_timer.wait_time = attack_rate
	attack_timer.start()

	# Play attack animation
	_play_animation(ANIM_ATTACK, 2.0)  # Fast swipe

	# Find valid target in range
	var attack_target: Node3D = null
	for player in players_in_attack_range:
		if is_instance_valid(player) and player.has_method("is_valid_target"):
			if player.is_valid_target():
				attack_target = player
				break

	if attack_target and attack_target.has_method("take_damage"):
		attack_target.take_damage(damage, self)
		AudioManager.play_sound_3d("zombie_attack", global_position)


func _try_pounce() -> void:
	if not can_pounce or is_pouncing:
		return

	is_pouncing = true
	pounce_timer = pounce_cooldown

	# Calculate pounce trajectory
	var direction := (target_player.global_position - global_position).normalized()
	direction.y = 0.3  # Add upward component

	velocity = direction * speed * 3.0
	velocity.y = 8.0  # Jump force

	AudioManager.play_sound_3d("zombie_growl", global_position)

	# End pounce after landing
	await get_tree().create_timer(0.5).timeout
	is_pouncing = false


func _update_stuck_detection(delta: float) -> void:
	stuck_check_timer += delta

	if stuck_check_timer >= STUCK_CHECK_INTERVAL:
		stuck_check_timer = 0.0

		var distance_moved := global_position.distance_to(last_stuck_check_pos)

		if distance_moved < STUCK_DISTANCE_THRESHOLD and state == EnemyState.CHASING:
			stuck_count += 1
			# If stuck 3 times in a row, try to unstick
			if stuck_count >= 3:
				_try_unstick()
		else:
			stuck_count = 0

		last_stuck_check_pos = global_position


func _try_unstick() -> void:
	# Try jumping
	if is_on_floor() and can_jump:
		_perform_jump()

	# Randomize path offset more aggressively
	path_offset = Vector3(
		randf_range(-PATH_OFFSET_RANGE * 2, PATH_OFFSET_RANGE * 2),
		0,
		randf_range(-PATH_OFFSET_RANGE * 2, PATH_OFFSET_RANGE * 2)
	)

	# Give a random velocity push
	velocity.x = randf_range(-speed, speed)
	velocity.z = randf_range(-speed, speed)

	stuck_count = 0


func _update_path_offset() -> void:
	# Generate random offset for varied pathing
	path_offset = Vector3(
		randf_range(-PATH_OFFSET_RANGE, PATH_OFFSET_RANGE),
		0,
		randf_range(-PATH_OFFSET_RANGE, PATH_OFFSET_RANGE)
	)


func _check_and_jump(move_direction: Vector3) -> void:
	if not can_jump or not is_on_floor():
		return

	# Raycast forward to check for obstacles
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.5, 0),
		global_position + Vector3(0, 0.5, 0) + move_direction * 1.5
	)
	query.exclude = [self]

	var result := space_state.intersect_ray(query)
	if result:
		# Check if obstacle is jumpable (low enough)
		var hit_pos: Vector3 = result.position
		var obstacle_height: float = hit_pos.y - global_position.y
		if obstacle_height < 2.0 and obstacle_height > 0.3:
			_perform_jump()


func _perform_jump() -> void:
	if not can_jump or not is_on_floor():
		return

	can_jump = false
	jump_cooldown = JUMP_COOLDOWN_TIME
	velocity.y = JUMP_FORCE

	# Add forward momentum
	if target_player and is_instance_valid(target_player):
		var direction := (target_player.global_position - global_position).normalized()
		direction.y = 0
		velocity.x += direction.x * speed * 0.5
		velocity.z += direction.z * speed * 0.5


func _is_only_zombie_alive() -> bool:
	var parent := get_parent()
	if not parent:
		return true
	return parent.get_child_count() <= 1


func take_damage(amount: int, attacker: Node = null, is_headshot: bool = false, hit_position: Vector3 = Vector3.ZERO) -> void:
	if state == EnemyState.DYING or state == EnemyState.DEAD:
		return

	var final_damage := amount

	# Headshots are instant kills
	if is_headshot:
		final_damage = max_health  # Instant kill
	else:
		# Distance-based damage calculation for body shots
		# Minimum 2 hits to kill, maximum 4 hits based on distance from head
		final_damage = _calculate_distance_based_damage(amount, hit_position)

	health -= final_damage

	last_hit_was_headshot = is_headshot
	if attacker and attacker.has_method("get") and "player_id" in attacker:
		last_attacker_id = attacker.player_id

	damaged.emit(final_damage, is_headshot)
	AudioManager.play_sound_3d("zombie_hurt", global_position, -5.0)

	# Sync damage to clients
	rpc("_sync_damage", health)

	if health <= 0:
		die()


func _calculate_distance_based_damage(base_amount: int, hit_position: Vector3) -> int:
	# If no hit position provided, use default damage
	if hit_position == Vector3.ZERO:
		return base_amount

	# Calculate the relative Y position of the hit on the enemy
	# Enemy's feet are at global_position.y, head is at global_position.y + head_position_y
	var enemy_feet_y := global_position.y
	var enemy_head_y := global_position.y + head_position_y

	# Calculate how far the hit is from the head (0 = at head, 1 = at feet)
	var hit_relative_y := hit_position.y
	var distance_from_head := enemy_head_y - hit_relative_y

	# Clamp to enemy body range
	distance_from_head = clampf(distance_from_head, 0.0, enemy_height)

	# Normalize distance (0 = head, 1 = feet)
	var normalized_distance := distance_from_head / enemy_height

	# Calculate damage multiplier
	# At head (0): multiplier = 0.5 (2 hits to kill = max_health / 2 per hit)
	# At feet (1): multiplier = 0.25 (4 hits to kill = max_health / 4 per hit)
	# Linear interpolation between these values
	var min_multiplier := 0.25  # 4 hits to kill
	var max_multiplier := 0.5   # 2 hits to kill
	var damage_multiplier := lerpf(max_multiplier, min_multiplier, normalized_distance)

	# Calculate final damage based on max_health
	# This ensures consistent hit-to-kill regardless of base_damage
	var final_damage := int(max_health * damage_multiplier)

	return max(final_damage, 1)  # Ensure at least 1 damage


@rpc("authority", "call_remote", "reliable")
func _sync_damage(new_health: int) -> void:
	health = new_health


func die() -> void:
	if state == EnemyState.DYING or state == EnemyState.DEAD:
		return

	state = EnemyState.DYING

	# Disable collision
	collision_layer = 0
	collision_mask = 0

	# Play appropriate death sound
	if last_hit_was_headshot:
		AudioManager.play_sound_3d("headshot_kill", global_position, 3.0)
	else:
		AudioManager.play_sound_3d("zombie_death", global_position)

	# Notify game manager
	if multiplayer.is_server():
		GameManager.on_zombie_killed(self, last_attacker_id, last_hit_was_headshot)

	died.emit(self, last_attacker_id, last_hit_was_headshot)

	# Play death animation if available
	if anim_player and anim_player.has_animation(ANIM_DEATH):
		_play_animation(ANIM_DEATH)
		await anim_player.animation_finished
		_finish_death()
	else:
		# Fallback: simple scale tween
		var tween := create_tween()
		tween.tween_property(model, "scale", Vector3(1, 0.1, 1), 0.3)
		tween.tween_callback(_finish_death)


func _finish_death() -> void:
	state = EnemyState.DEAD
	queue_free()


func _on_attack_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("players"):
		if body not in players_in_attack_range:
			players_in_attack_range.append(body)


func _on_attack_area_body_exited(body: Node3D) -> void:
	if body in players_in_attack_range:
		players_in_attack_range.erase(body)


func _on_attack_timer_timeout() -> void:
	can_attack = true


func _on_path_update_timer_timeout() -> void:
	if target_player and is_instance_valid(target_player):
		nav_agent.target_position = target_player.global_position


func _on_sync_timer_timeout() -> void:
	if multiplayer.is_server():
		rpc("_sync_state", global_position, rotation.y, velocity, int(state))


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_state(pos: Vector3, rot_y: float, vel: Vector3, s: int) -> void:
	if multiplayer.is_server():
		return

	global_position = global_position.lerp(pos, 0.3)
	rotation.y = rot_y
	velocity = vel
	state = s as EnemyState
