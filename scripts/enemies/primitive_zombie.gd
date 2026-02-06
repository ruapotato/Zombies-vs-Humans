extends CharacterBody3D
class_name PrimitiveZombie
## Primitive zombie with code-based animation - extremely lightweight

signal died(enemy: Node3D, killer_id: int, is_headshot: bool)
signal damaged(amount: int, is_headshot: bool)

enum EnemyState { SPAWNING, IDLE, CHASING, ATTACKING, DYING, DEAD }

# Enemy config
@export var enemy_type: String = "walker"
@export var display_name: String = "Walker"
@export var base_health: int = 20
@export var base_damage: int = 15
@export var base_speed: float = 3.0
@export var attack_rate: float = 1.0
@export var point_value: int = 10
@export var enemy_height: float = 1.8
@export var head_position_y: float = 1.5
@export var can_pounce: bool = false
@export var pounce_range: float = 5.0

# Runtime state
var health: int = 20
var max_health: int = 20
var damage: int = 15
var speed: float = 3.0
var state: EnemyState = EnemyState.SPAWNING

var target_player: Node3D = null
var players_in_attack_range: Array[Node3D] = []
var can_attack: bool = true
var last_attacker_id: int = 0
var last_hit_was_headshot: bool = false
var last_hit_position: Vector3 = Vector3.ZERO

# Horde control
var horde_controlled: bool = false

# Animation state (procedural)
var anim_time: float = 0.0
var walk_cycle: float = 0.0
var is_moving: bool = false

# Body parts for animation - simplified for performance
@onready var body: MeshInstance3D = $Model/DetailParts/Body
@onready var head: Node3D = $Model/DetailParts/Head
@onready var left_arm: MeshInstance3D = $Model/DetailParts/LeftArm
@onready var right_arm: MeshInstance3D = $Model/DetailParts/RightArm
@onready var left_leg: MeshInstance3D = $Model/DetailParts/LeftLeg
@onready var right_leg: MeshInstance3D = $Model/DetailParts/RightLeg
@onready var model: Node3D = $Model
@onready var attack_timer: Timer = $AttackTimer
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

# LOD meshes
@onready var detail_parts: Node3D = $Model/DetailParts
@onready var simple_mesh: MeshInstance3D = $Model/SimpleMesh
var current_lod: int = 0  # 0 = detailed, 1 = simple


func _ready() -> void:
	_scale_stats_for_round()
	set_meta("point_value", point_value)

	state = EnemyState.SPAWNING
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		state = EnemyState.CHASING

	if not multiplayer.is_server():
		set_physics_process(false)


func set_horde_controlled(controlled: bool) -> void:
	horde_controlled = controlled
	if controlled:
		set_physics_process(false)


func _scale_stats_for_round() -> void:
	var round_num := GameManager.current_round
	max_health = int(GameManager.get_zombie_health_for_round(base_health))
	health = max_health
	damage = int(GameManager.get_zombie_damage_for_round(base_damage))
	speed = base_speed + (round_num * 0.1)
	speed = min(speed, base_speed * 1.5)


# Called by horde controller to update procedural animation
func update_animation_from_velocity() -> void:
	var dominated_velocity := absf(velocity.x) + absf(velocity.z)
	is_moving = dominated_velocity > 0.5

	if state == EnemyState.ATTACKING:
		_animate_attack()
	elif is_moving:
		_animate_walk()
	else:
		_animate_idle()


func set_lod(lod: int) -> void:
	if current_lod == lod:
		return
	current_lod = lod
	if lod == 0:
		# Detailed view
		if detail_parts:
			detail_parts.visible = true
		if simple_mesh:
			simple_mesh.visible = false
	else:
		# Simple capsule only
		if detail_parts:
			detail_parts.visible = false
		if simple_mesh:
			simple_mesh.visible = true


func _animate_walk() -> void:
	anim_time += get_physics_process_delta_time() * speed * 2.0
	walk_cycle = sin(anim_time)

	# Simple LOD - just bob the whole model
	if current_lod == 1:
		if model:
			model.position.y = abs(walk_cycle) * 0.03
		return

	# Body bob and slight lean forward
	if body:
		body.position.y = abs(walk_cycle) * 0.04
		body.rotation.x = 0.1
		body.rotation.z = walk_cycle * 0.03

	# Head bob
	if head:
		head.rotation.x = sin(anim_time * 0.7) * 0.08

	# Arms swing
	if left_arm:
		left_arm.rotation.x = walk_cycle * 0.5
	if right_arm:
		right_arm.rotation.x = -walk_cycle * 0.5

	# Legs walk
	if left_leg:
		left_leg.rotation.x = -walk_cycle * 0.4
	if right_leg:
		right_leg.rotation.x = walk_cycle * 0.4


func _animate_idle() -> void:
	anim_time += get_physics_process_delta_time()
	var sway := sin(anim_time * 1.5) * 0.02

	# Simple LOD - just sway
	if current_lod == 1:
		if model:
			model.rotation.z = sway
		return

	if body:
		body.rotation.z = sway
		body.rotation.x = 0.05

	if head:
		head.rotation.x = 0.1 + sin(anim_time * 0.8) * 0.05
		head.rotation.y = sin(anim_time * 0.4) * 0.1

	if left_arm:
		left_arm.rotation.x = 0.2 + sin(anim_time * 1.1) * 0.05
	if right_arm:
		right_arm.rotation.x = 0.2 + sin(anim_time * 1.3) * 0.05

	if left_leg:
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, 0.1)
	if right_leg:
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, 0.1)


func _animate_attack() -> void:
	anim_time += get_physics_process_delta_time() * 4.0
	var attack_phase := sin(anim_time * 5.0)

	if left_arm:
		left_arm.rotation.x = -1.3 + attack_phase * 0.3
	if right_arm:
		right_arm.rotation.x = -1.3 - attack_phase * 0.3

	if body:
		body.rotation.x = 0.15 + attack_phase * 0.05


func stop_animation() -> void:
	# Reset to neutral pose
	anim_time = 0.0
	is_moving = false


func _attack_target(_delta: float) -> void:
	if players_in_attack_range.is_empty():
		state = EnemyState.CHASING
		return

	if can_attack:
		_perform_attack()


func _perform_attack() -> void:
	can_attack = false
	attack_timer.wait_time = attack_rate
	attack_timer.start()

	var attack_target: Node3D = null
	for player in players_in_attack_range:
		if is_instance_valid(player) and player.has_method("is_valid_target"):
			if player.is_valid_target():
				attack_target = player
				break

	if attack_target and attack_target.has_method("take_damage"):
		attack_target.take_damage(damage, self)
		AudioManager.play_sound_3d("zombie_attack", global_position)


func take_damage(amount: int, attacker: Node = null, is_headshot: bool = false, hit_position: Vector3 = Vector3.ZERO) -> void:
	if state == EnemyState.DYING or state == EnemyState.DEAD:
		return

	var final_damage := amount

	health -= final_damage

	last_hit_was_headshot = is_headshot
	last_hit_position = hit_position if hit_position != Vector3.ZERO else global_position + Vector3(0, 1, 0)
	if attacker and attacker.has_method("get") and "player_id" in attacker:
		last_attacker_id = attacker.player_id

	damaged.emit(final_damage, is_headshot)
	AudioManager.play_sound_3d("zombie_hurt", global_position, -5.0)

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
	collision_layer = 0
	collision_mask = 0

	if last_hit_was_headshot:
		AudioManager.play_sound_3d("headshot_kill", global_position, 3.0)
	else:
		AudioManager.play_sound_3d("zombie_death", global_position)

	if multiplayer.is_server():
		GameManager.on_zombie_killed(self, last_attacker_id, last_hit_was_headshot, last_hit_position)

	died.emit(self, last_attacker_id, last_hit_was_headshot)

	# Death animation - fall over
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(model, "rotation:x", -PI/2, 0.4)
	tween.tween_property(model, "position:y", -0.5, 0.4)
	tween.set_parallel(false)
	tween.tween_callback(_finish_death)


func _finish_death() -> void:
	state = EnemyState.DEAD
	queue_free()


func _on_attack_area_body_entered(body_node: Node3D) -> void:
	if body_node.is_in_group("players"):
		if body_node not in players_in_attack_range:
			players_in_attack_range.append(body_node)


func _on_attack_area_body_exited(body_node: Node3D) -> void:
	if body_node in players_in_attack_range:
		players_in_attack_range.erase(body_node)


func _on_attack_timer_timeout() -> void:
	can_attack = true


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_state(pos: Vector3, rot_y: float, vel: Vector3, s: int) -> void:
	if multiplayer.is_server():
		return
	global_position = global_position.lerp(pos, 0.3)
	rotation.y = rot_y
	velocity = vel
	state = s as EnemyState
	update_animation_from_velocity()
