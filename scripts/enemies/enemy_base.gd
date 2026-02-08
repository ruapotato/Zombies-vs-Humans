extends CharacterBody3D
class_name Enemy
## Base enemy class - can be controlled by ZombieHorde (efficient) or run individually

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
var last_hit_position: Vector3 = Vector3.ZERO

# Horde control - when true, ZombieHorde handles AI
var horde_controlled: bool = false

# Components
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var model: Node3D = $Model
@onready var attack_timer: Timer = $AttackTimer

# Health bar
var health_bar_sprite: Sprite3D = null
var health_bar_image: Image = null
var health_bar_texture: ImageTexture = null
const HEALTH_BAR_WIDTH := 32
const HEALTH_BAR_HEIGHT := 4

# Animation
var anim_player: AnimationPlayer = null
var current_anim: String = ""

const ANIM_IDLE := "m root"
const ANIM_RUN := "m run"
const ANIM_DEATH := "m death"
const ANIM_ATTACK := "swipe"


func _ready() -> void:
	# Find AnimationPlayer in model (may not exist for simple zombies)
	if model:
		_find_animation_player(model)
		if anim_player:
			_play_animation(ANIM_IDLE)
		# Note: No warning if no AnimationPlayer - simple zombies don't have one

	# Scale stats by round
	_scale_stats_for_round()

	# Set meta for point value
	set_meta("point_value", point_value)

	# Create health bar
	_create_health_bar()

	# Start spawning state briefly
	state = EnemyState.SPAWNING
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		state = EnemyState.CHASING

	# Disable individual physics if horde will control us
	# The horde manager will call set_horde_controlled(true) after spawn
	if not multiplayer.is_server():
		set_physics_process(false)


func set_horde_controlled(controlled: bool) -> void:
	horde_controlled = controlled
	if controlled:
		# Disable individual AI - horde handles everything
		set_physics_process(false)
		# Stop path update timer - horde handles paths
		var path_timer := get_node_or_null("PathUpdateTimer") as Timer
		if path_timer:
			path_timer.stop()
		# Stop sync timer - horde handles sync
		var sync_timer := get_node_or_null("SyncTimer") as Timer
		if sync_timer:
			sync_timer.stop()


func _find_animation_player(node: Node) -> void:
	if node is AnimationPlayer:
		anim_player = node as AnimationPlayer
		return
	for child in node.get_children():
		_find_animation_player(child)
		if anim_player:
			return


func _play_animation(anim_name: String, anim_speed: float = 1.0) -> void:
	if not anim_player:
		return
	if current_anim == anim_name and anim_player.is_playing():
		return
	if anim_player.has_animation(anim_name):
		current_anim = anim_name
		anim_player.play(anim_name, -1, anim_speed)


func _scale_stats_for_round() -> void:
	var round_num := GameManager.current_round

	max_health = int(GameManager.get_zombie_health_for_round(base_health))
	health = max_health

	damage = int(GameManager.get_zombie_damage_for_round(base_damage))

	speed = base_speed + (round_num * 0.1)
	speed = min(speed, base_speed * 1.5)


# Called by horde to update animation based on movement
func update_animation_from_velocity() -> void:
	var dominated_velocity := absf(velocity.x) + absf(velocity.z)
	if state == EnemyState.ATTACKING:
		return  # Don't override attack animation
	if dominated_velocity > 0.5:
		_play_animation(ANIM_RUN, 1.5)
	else:
		_play_animation(ANIM_IDLE)


# Called by horde to stop animation for far zombies
func stop_animation() -> void:
	if anim_player and anim_player.is_playing():
		anim_player.stop()
	current_anim = ""


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

	_play_animation(ANIM_ATTACK, 2.0)

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

	if is_headshot:
		final_damage = max_health
	else:
		final_damage = _calculate_distance_based_damage(amount, hit_position)

	health -= final_damage

	last_hit_was_headshot = is_headshot
	last_hit_position = hit_position if hit_position != Vector3.ZERO else global_position + Vector3(0, 1, 0)
	if attacker and attacker.has_method("get") and "player_id" in attacker:
		last_attacker_id = attacker.player_id

	damaged.emit(final_damage, is_headshot)
	AudioManager.play_sound_3d("zombie_hurt", global_position, -5.0)
	_update_health_bar()

	# Only server syncs damage to clients
	if multiplayer.is_server():
		rpc("_sync_damage", health)

	if health <= 0:
		die()


func _calculate_distance_based_damage(base_amount: int, hit_position: Vector3) -> int:
	if hit_position == Vector3.ZERO:
		return base_amount

	var enemy_head_y := global_position.y + head_position_y
	var distance_from_head := enemy_head_y - hit_position.y
	distance_from_head = clampf(distance_from_head, 0.0, enemy_height)

	var normalized_distance := distance_from_head / enemy_height
	var min_multiplier := 0.25
	var max_multiplier := 0.5
	var damage_multiplier := lerpf(max_multiplier, min_multiplier, normalized_distance)

	var final_damage := int(max_health * damage_multiplier)
	return max(final_damage, 1)


@rpc("authority", "call_remote", "reliable")
func _sync_damage(new_health: int) -> void:
	health = new_health
	_update_health_bar()


func _create_health_bar() -> void:
	health_bar_sprite = Sprite3D.new()
	health_bar_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_bar_sprite.pixel_size = 0.02
	health_bar_sprite.position = Vector3(0, enemy_height + 0.15, 0)
	health_bar_sprite.no_depth_test = true
	health_bar_sprite.render_priority = 10
	health_bar_sprite.visible = false
	add_child(health_bar_sprite)

	health_bar_image = Image.create(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT, false, Image.FORMAT_RGBA8)
	health_bar_texture = ImageTexture.create_from_image(health_bar_image)
	health_bar_sprite.texture = health_bar_texture


func _update_health_bar() -> void:
	if not health_bar_sprite or max_health <= 0:
		return

	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	var filled := int(ratio * HEALTH_BAR_WIDTH)

	health_bar_image.fill(Color(0, 0, 0, 0.7))
	for x in range(1, HEALTH_BAR_WIDTH - 1):
		for y in range(1, HEALTH_BAR_HEIGHT - 1):
			if x < filled:
				var bar_color: Color
				if ratio > 0.5:
					bar_color = Color(0.1, 0.9, 0.1)
				elif ratio > 0.25:
					bar_color = Color(0.9, 0.9, 0.1)
				else:
					bar_color = Color(0.9, 0.1, 0.1)
				health_bar_image.set_pixel(x, y, bar_color)
			else:
				health_bar_image.set_pixel(x, y, Color(0.2, 0.0, 0.0, 0.5))

	health_bar_texture.update(health_bar_image)
	health_bar_sprite.visible = true


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

	if anim_player and anim_player.has_animation(ANIM_DEATH):
		_play_animation(ANIM_DEATH)
		await anim_player.animation_finished
		_finish_death()
	else:
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


# Network sync for clients
func _on_sync_timer_timeout() -> void:
	if multiplayer.is_server() and not horde_controlled and state != EnemyState.DYING and state != EnemyState.DEAD:
		rpc("_sync_state", global_position, rotation.y, velocity, int(state))


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_state(pos: Vector3, rot_y: float, vel: Vector3, s: int) -> void:
	if multiplayer.is_server():
		return
	global_position = global_position.lerp(pos, 0.3)
	rotation.y = rot_y
	velocity = vel
	state = s as EnemyState
	# Update animation on client based on state
	update_animation_from_velocity()
