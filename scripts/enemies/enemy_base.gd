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

# Components
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var model: Node3D = $Model
@onready var attack_timer: Timer = $AttackTimer
@onready var path_update_timer: Timer = $PathUpdateTimer

# Animation
var anim_player: AnimationPlayer = null
var current_anim: String = ""

# Animation names from the model
const ANIM_IDLE := "m root_metarig"
const ANIM_RUN := "m run_metarig"
const ANIM_DEATH := "m death_metarig"


func _ready() -> void:
	# Find AnimationPlayer in model
	_find_animation_player(model)
	if anim_player:
		_play_animation(ANIM_IDLE)
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
			_play_animation(ANIM_RUN, 0.5)
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
	var direction := (next_pos - global_position).normalized()
	direction.y = 0

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	# Face movement direction
	if direction.length() > 0.1:
		look_at(global_position + direction, Vector3.UP)

	move_and_slide()


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


func take_damage(amount: int, attacker: Node = null, is_headshot: bool = false) -> void:
	if state == EnemyState.DYING or state == EnemyState.DEAD:
		return

	health -= amount

	last_hit_was_headshot = is_headshot
	if attacker and attacker.has_method("get") and "player_id" in attacker:
		last_attacker_id = attacker.player_id

	damaged.emit(amount, is_headshot)
	AudioManager.play_sound_3d("zombie_hurt", global_position, -5.0)

	# Sync damage to clients
	rpc("_sync_damage", health)

	if health <= 0:
		die()


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
