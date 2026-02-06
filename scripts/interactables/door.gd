extends StaticBody3D
class_name Door
## Door/debris that can be purchased to unlock new areas

signal door_opened(door: Door)

@export var door_cost: int = 750
@export var door_id: String = ""
@export var is_debris: bool = false

var is_open: bool = false

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D = $Label3D
@onready var cost_label: Label3D = $CostLabel
@onready var interaction_area: Area3D = $InteractionArea


func _ready() -> void:
	add_to_group("doors")
	add_to_group("interactables")

	cost_label.text = str(door_cost)

	if is_debris:
		label.text = "Clear Debris"
	else:
		label.text = "Open Door"


func interact(player: Node) -> bool:
	if is_open:
		return false

	if not player.can_afford(door_cost):
		AudioManager.play_sound_ui("denied")
		return false

	player.spend_points(door_cost)

	# Server opens directly; clients request server to open
	if multiplayer.is_server():
		_open_door_networked()
	else:
		rpc_id(1, "_request_open_door")

	return true


@rpc("any_peer", "reliable")
func _request_open_door() -> void:
	if not multiplayer.is_server():
		return
	_open_door_networked()


func _open_door_networked() -> void:
	if is_open:
		return
	rpc("_sync_open")


func open_door() -> void:
	if is_open:
		return

	is_open = true

	AudioManager.play_sound_3d("door_open", global_position)

	# Animate door opening
	var tween := create_tween()

	if is_debris:
		# Debris falls apart
		tween.tween_property(mesh, "scale", Vector3(1, 0.1, 1), 0.5)
		tween.parallel().tween_property(mesh, "position:y", -1.5, 0.5)
	else:
		# Door slides open
		tween.tween_property(mesh, "position:x", mesh.position.x + 4.0, 0.8)
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)

	tween.tween_callback(_finish_open)


func _finish_open() -> void:
	# Disable collision
	collision.disabled = true
	interaction_area.monitoring = false

	# Hide labels
	label.visible = false
	cost_label.visible = false

	door_opened.emit(self)


@rpc("authority", "call_local", "reliable")
func _sync_open() -> void:
	if not is_open:
		open_door()


func get_prompt(player: Node) -> String:
	if is_open:
		return ""

	var action := "Clear Debris" if is_debris else "Open Door"

	if player.can_afford(door_cost):
		return "%s [Cost: %d]" % [action, door_cost]
	else:
		return "%s [Cost: %d] (Need more points)" % [action, door_cost]
