extends CharacterBody3D
class_name BillboardZombie
## Paper Mario style 2D billboard zombie - extremely fast to render

const ZombieTextureGen = preload("res://scripts/enemies/zombie_texture_generator.gd")

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
var barriers_in_attack_range: Array[Node3D] = []
var can_attack: bool = true
var last_attacker_id: int = 0
var last_hit_was_headshot: bool = false
var last_hit_position: Vector3 = Vector3.ZERO

# Horde control
var horde_controlled: bool = false

# Animation
var anim_time: float = 0.0
var base_y: float = 0.0
var is_attacking_anim: bool = false
var attack_anim_time: float = 0.0

@onready var sprite: Sprite3D = $Sprite3D
@onready var attack_sprite: Sprite3D = $AttackSprite
@onready var attack_timer: Timer = $AttackTimer
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

# Health bar
var health_bar_sprite: Sprite3D = null
var health_bar_image: Image = null
var health_bar_texture: ImageTexture = null
const HEALTH_BAR_WIDTH := 32
const HEALTH_BAR_HEIGHT := 4
var health_bar_hide_timer := 0.0

# Attack swipe texture (cached)
static var swipe_texture: ImageTexture = null


func _ready() -> void:
	_scale_stats_for_round()
	set_meta("point_value", point_value)

	# Set zombie texture based on type
	if sprite:
		sprite.texture = ZombieTextureGen.get_zombie_texture(enemy_type)
		# Tank is bigger
		if enemy_type == "tank":
			sprite.pixel_size = 0.03

	# Set up attack sprite
	if attack_sprite:
		if not swipe_texture:
			swipe_texture = _generate_swipe_texture()
		attack_sprite.texture = swipe_texture
		attack_sprite.visible = false

	# Create health bar sprite (hidden until damaged)
	_create_health_bar()

	# Randomize animation offset so zombies don't all sync
	anim_time = randf() * TAU
	base_y = sprite.position.y if sprite else 0.9

	state = EnemyState.SPAWNING
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(self):
		state = EnemyState.CHASING

	if not multiplayer.is_server():
		set_physics_process(false)


func _generate_swipe_texture() -> ImageTexture:
	var img := Image.create(48, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var claw_color := Color(0.3, 0.25, 0.2)
	var slash_color := Color(1.0, 0.3, 0.2, 0.8)

	# Draw slashing claws
	for i in range(3):
		var x_start := 8 + i * 12
		var y_start := 4 + i * 3
		# Claw
		for j in range(20):
			var x := x_start + j
			var y := y_start + int(j * 0.8)
			for dy in range(-2, 3):
				if x < 48 and y + dy < 32 and y + dy >= 0:
					img.set_pixel(x, y + dy, claw_color if abs(dy) < 2 else slash_color)

		# Slash trail
		for j in range(15):
			var x := x_start + j + 5
			var y := y_start + int(j * 0.8) + 2
			if x < 48 and y < 32:
				img.set_pixel(x, y, Color(slash_color.r, slash_color.g, slash_color.b, 0.5 - j * 0.03))

	return ImageTexture.create_from_image(img)


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

	# Draw: 1px black border, green fill, red remainder
	health_bar_image.fill(Color(0, 0, 0, 0.7))  # Background
	for x in range(1, HEALTH_BAR_WIDTH - 1):
		for y in range(1, HEALTH_BAR_HEIGHT - 1):
			if x < filled:
				# Green → yellow → red gradient based on health
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


func set_zombie_color(color: Color) -> void:
	if sprite and sprite.texture:
		sprite.modulate = color


func update_animation_from_velocity() -> void:
	var dominated_velocity := absf(velocity.x) + absf(velocity.z)

	# Always update swipe effect timer (even when not attacking)
	if is_attacking_anim:
		attack_anim_time += get_physics_process_delta_time()
		if attack_anim_time > 0.35:
			is_attacking_anim = false
			if attack_sprite:
				attack_sprite.visible = false

	if state == EnemyState.ATTACKING:
		_animate_attack()
	elif dominated_velocity > 0.5:
		_animate_walk()
	else:
		_animate_idle()


func _animate_walk() -> void:
	anim_time += get_physics_process_delta_time() * speed * 3.0

	if sprite:
		# Bounce up and down
		sprite.position.y = base_y + abs(sin(anim_time)) * 0.08
		# Slight squash and stretch
		var squash := 1.0 + sin(anim_time * 2.0) * 0.05
		sprite.scale.x = 1.0 / squash
		sprite.scale.y = squash
		# Tilt side to side like walking
		sprite.rotation.z = sin(anim_time) * 0.1


func _animate_idle() -> void:
	anim_time += get_physics_process_delta_time() * 2.0

	if sprite:
		# Gentle sway
		sprite.position.y = base_y + sin(anim_time * 0.8) * 0.02
		sprite.rotation.z = sin(anim_time * 0.5) * 0.05
		sprite.scale.x = 1.0
		sprite.scale.y = 1.0


func _animate_attack() -> void:
	anim_time += get_physics_process_delta_time() * 6.0

	if sprite:
		# Lunge forward
		var lunge := sin(anim_time * 4.0)
		sprite.position.z = 0.2 * max(0, lunge)
		sprite.scale.x = 1.0 + max(0, lunge) * 0.2
		sprite.rotation.z = lunge * 0.15

	# Animate swipe effect
	if attack_sprite and is_attacking_anim:
		attack_sprite.visible = true
		var swipe_progress := attack_anim_time * 5.0
		attack_sprite.position.x = sin(swipe_progress) * 0.4
		attack_sprite.position.z = 0.3 + cos(swipe_progress) * 0.2
		attack_sprite.rotation.z = swipe_progress * 2.0
		attack_sprite.modulate.a = 1.0 - (attack_anim_time * 2.5)


func stop_animation() -> void:
	anim_time = randf() * TAU
	is_attacking_anim = false
	if attack_sprite:
		attack_sprite.visible = false


func _attack_target(_delta: float) -> void:
	# Check for valid targets (players or barriers with boards)
	var has_player_target := false
	for player in players_in_attack_range:
		if is_instance_valid(player):
			has_player_target = true
			break

	var has_barrier_target := false
	for barrier in barriers_in_attack_range:
		if is_instance_valid(barrier) and barrier.has_method("is_broken"):
			if not barrier.is_broken():
				has_barrier_target = true
				break

	if not has_player_target and not has_barrier_target:
		state = EnemyState.CHASING
		return

	if can_attack:
		_perform_attack()


func _perform_attack() -> void:
	can_attack = false
	attack_timer.wait_time = attack_rate
	attack_timer.start()

	# Trigger swipe animation
	is_attacking_anim = true
	attack_anim_time = 0.0
	if attack_sprite:
		attack_sprite.visible = true
		attack_sprite.modulate.a = 1.0

	# First priority: attack players
	var attack_target: Node3D = null
	for player in players_in_attack_range:
		if is_instance_valid(player) and player.has_method("is_valid_target"):
			if player.is_valid_target():
				attack_target = player
				break

	if attack_target and attack_target.has_method("take_damage"):
		attack_target.take_damage(damage, self)
		AudioManager.play_sound_3d("zombie_attack", global_position)
		return

	# Second priority: attack barriers
	for barrier in barriers_in_attack_range:
		if is_instance_valid(barrier) and barrier.has_method("break_board"):
			if not barrier.is_broken():
				barrier.break_board()
				AudioManager.play_sound_3d("zombie_attack", global_position)
				return


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
	_update_health_bar()

	# Flash white on hit
	if sprite:
		sprite.modulate = Color.WHITE
		await get_tree().create_timer(0.05).timeout
		if is_instance_valid(self) and sprite:
			sprite.modulate = Color.WHITE  # Will be set by color system

	if multiplayer.is_server():
		rpc("_sync_damage", health)

	if health <= 0:
		die()


@rpc("authority", "call_remote", "reliable")
func _sync_damage(new_health: int) -> void:
	health = new_health
	_update_health_bar()


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

	# Death animation - fall flat
	if sprite:
		var tween := create_tween()
		tween.tween_property(sprite, "rotation:x", -PI/2, 0.3)
		tween.parallel().tween_property(sprite, "position:y", 0.1, 0.3)
		tween.parallel().tween_property(sprite, "modulate:a", 0.5, 0.3)
		tween.tween_callback(_finish_death)
	else:
		_finish_death()


func _finish_death() -> void:
	state = EnemyState.DEAD
	queue_free()


func _on_attack_area_body_entered(body_node: Node3D) -> void:
	if body_node.is_in_group("players"):
		if body_node not in players_in_attack_range:
			players_in_attack_range.append(body_node)
	elif body_node.is_in_group("barriers"):
		if body_node not in barriers_in_attack_range:
			barriers_in_attack_range.append(body_node)


func _on_attack_area_body_exited(body_node: Node3D) -> void:
	if body_node in players_in_attack_range:
		players_in_attack_range.erase(body_node)
	if body_node in barriers_in_attack_range:
		barriers_in_attack_range.erase(body_node)


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
