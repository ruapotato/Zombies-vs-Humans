extends Interactable
class_name MysteryBox
## Mystery Box - gives random weapons for points

signal weapon_ready(weapon_id: String)
signal box_moving

const NORMAL_COST := 950
const FIRE_SALE_COST := 10
const CYCLE_DURATION := 4.0
const GRAB_DURATION := 8.0
const USES_BEFORE_MOVE := 5  # Average uses before box moves

enum BoxState { IDLE, CYCLING, READY, MOVING }

var box_state: BoxState = BoxState.IDLE
var current_weapon_id: String = ""
var uses_count: int = 0
var waiting_player: Node = null

@onready var lid: MeshInstance3D = $Lid
@onready var weapon_display: Node3D = $WeaponDisplay
@onready var cycle_timer: Timer = $CycleTimer
@onready var grab_timer: Timer = $GrabTimer
@onready var label: Label3D = $Label3D
@onready var light: OmniLight3D = $Light
@onready var sprite: Sprite3D = $Sprite3D

var displayed_weapon_mesh: Node3D = null
var cycle_count: int = 0
var anim_time: float = 0.0


func _ready() -> void:
	super._ready()

	cost = NORMAL_COST
	interaction_prompt = "Buy Mystery Box"
	requires_power = false
	one_time_use = false

	# Set up billboard sprite
	if sprite:
		sprite.texture = InteractableTextureGenerator.get_mystery_box_texture()
		sprite.visible = true
		if lid:
			lid.visible = false

	anim_time = randf() * TAU


func _process(delta: float) -> void:
	# Update cost based on fire sale
	if GameManager.is_power_up_active("fire_sale"):
		cost = FIRE_SALE_COST
	else:
		cost = NORMAL_COST

	# Animate sprite
	anim_time += delta
	if sprite and sprite.visible:
		# Gentle float
		sprite.position.y = 0.5 + sin(anim_time * 1.5) * 0.05
		# Glow when ready
		if box_state == BoxState.READY:
			sprite.modulate = Color(1, 1, 1, 0.8 + sin(anim_time * 6.0) * 0.2)
		elif box_state == BoxState.CYCLING:
			sprite.modulate = Color(1, 1, 1, 0.7 + sin(anim_time * 10.0) * 0.3)
		else:
			sprite.modulate = Color.WHITE


func interact(player: Node) -> bool:
	match box_state:
		BoxState.IDLE:
			_start_cycle(player)  # Coroutine, don't await
			return true

		BoxState.READY:
			if waiting_player == player:
				return _grab_weapon(player)

		_:
			return false

	return false


func _start_cycle(player: Node) -> bool:
	if not player.can_afford(cost):
		AudioManager.play_sound_ui("denied")
		return false

	player.spend_points(cost)
	waiting_player = player
	uses_count += 1

	box_state = BoxState.CYCLING
	cycle_count = 0

	# Open lid animation
	var tween := create_tween()
	tween.tween_property(lid, "rotation_degrees", Vector3(-110, 0, 0), 0.3)

	AudioManager.play_sound_3d("mystery_box_open", global_position)

	cycle_timer.start()

	# Schedule end of cycling
	await get_tree().create_timer(CYCLE_DURATION).timeout

	if box_state == BoxState.CYCLING:
		_finish_cycling()

	return true


func _on_cycle_timer_timeout() -> void:
	if box_state != BoxState.CYCLING:
		cycle_timer.stop()
		return

	cycle_count += 1

	# Display random weapon
	var random_weapon := WeaponRegistry.get_random_mystery_box_weapon()
	_display_weapon(random_weapon)


func _finish_cycling() -> void:
	cycle_timer.stop()

	# Determine final weapon
	current_weapon_id = WeaponRegistry.get_random_mystery_box_weapon()
	_display_weapon(current_weapon_id)

	box_state = BoxState.READY
	AudioManager.play_sound_3d("mystery_box_weapon", global_position)

	# Start grab timer
	grab_timer.wait_time = GRAB_DURATION
	grab_timer.start()


func _display_weapon(weapon_id: String) -> void:
	# Clear previous
	if displayed_weapon_mesh:
		displayed_weapon_mesh.queue_free()
		displayed_weapon_mesh = null

	# Create simple mesh representation
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.1, 0.15, 0.5)
	mesh.mesh = box_mesh

	# Color based on weapon type
	var material := StandardMaterial3D.new()
	var data := WeaponRegistry.get_weapon_data(weapon_id)
	if data:
		match data.weapon_type:
			WeaponData.WeaponType.PISTOL:
				material.albedo_color = Color(0.6, 0.6, 0.6)
			WeaponData.WeaponType.SHOTGUN:
				material.albedo_color = Color(0.5, 0.3, 0.2)
			WeaponData.WeaponType.SMG:
				material.albedo_color = Color(0.3, 0.3, 0.3)
			WeaponData.WeaponType.AR:
				material.albedo_color = Color(0.4, 0.4, 0.3)
			WeaponData.WeaponType.LMG:
				material.albedo_color = Color(0.3, 0.4, 0.3)
			WeaponData.WeaponType.SNIPER:
				material.albedo_color = Color(0.2, 0.3, 0.2)
			WeaponData.WeaponType.WONDER:
				material.albedo_color = Color(0.2, 1, 0.5)
				material.emission_enabled = true
				material.emission = Color(0.2, 1, 0.5)
				material.emission_energy_multiplier = 2.0

	mesh.set_surface_override_material(0, material)
	weapon_display.add_child(mesh)
	displayed_weapon_mesh = mesh

	# Floating animation
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(mesh, "position:y", 0.3, 0.5)
	tween.tween_property(mesh, "position:y", 0.0, 0.5)


func _grab_weapon(player: Node) -> bool:
	if current_weapon_id.is_empty():
		return false

	grab_timer.stop()

	# Give weapon to player
	if player.weapons.size() >= player.max_weapons:
		# Replace current weapon
		player.replace_weapon(current_weapon_id)
	else:
		player.give_weapon(current_weapon_id)

	AudioManager.play_sound_ui("purchase")

	_close_box()

	# Check if box should move
	if randf() < (float(uses_count) / float(USES_BEFORE_MOVE)):
		_start_move()

	return true


func _on_grab_timer_timeout() -> void:
	# Player didn't grab weapon in time
	_close_box()


func _close_box() -> void:
	box_state = BoxState.IDLE
	waiting_player = null
	current_weapon_id = ""

	# Clear weapon display
	if displayed_weapon_mesh:
		displayed_weapon_mesh.queue_free()
		displayed_weapon_mesh = null

	# Close lid animation
	var tween := create_tween()
	tween.tween_property(lid, "rotation_degrees", Vector3(0, 0, 0), 0.3)

	AudioManager.play_sound_3d("mystery_box_close", global_position)


func _start_move() -> void:
	box_state = BoxState.MOVING
	uses_count = 0

	AudioManager.play_sound_3d("mystery_box_move", global_position)
	box_moving.emit()

	# Play move animation (teddy bear floats up, box disappears)
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y + 10, 2.0)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 2.0)

	await tween.finished

	# Notify map to move box to new location
	# This would be handled by the map/game controller
	queue_free()


func get_prompt(player: Node) -> String:
	match box_state:
		BoxState.IDLE:
			if player.can_afford(cost):
				return "Open Mystery Box [Cost: %d]" % cost
			else:
				return "Open Mystery Box [Cost: %d] (Need more points)" % cost

		BoxState.CYCLING:
			return "Opening..."

		BoxState.READY:
			if waiting_player == player:
				var data := WeaponRegistry.get_weapon_data(current_weapon_id)
				var weapon_name: String = data.display_name if data else current_weapon_id
				return "Take %s" % weapon_name
			else:
				return ""

		BoxState.MOVING:
			return "Box is moving..."

	return ""
