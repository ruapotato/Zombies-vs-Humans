extends Area3D
class_name PowerSwitch
## Power switch that activates perk machines and Pack-a-Punch

signal power_activated

var is_activated: bool = false

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var lever: MeshInstance3D = $Lever
@onready var label: Label3D = $Label3D
@onready var light: OmniLight3D = $Light


func _ready() -> void:
	add_to_group("interactables")

	# Create lever mesh
	var lever_mesh := CylinderMesh.new()
	lever_mesh.top_radius = 0.05
	lever_mesh.bottom_radius = 0.05
	lever_mesh.height = 0.4
	lever.mesh = lever_mesh

	lever.rotation_degrees = Vector3(-45, 0, 0)  # Off position


func interact(player: Node) -> bool:
	if is_activated:
		return false

	activate_power()
	return true


func activate_power() -> void:
	if is_activated:
		return

	is_activated = true

	# Animate lever
	var tween := create_tween()
	tween.tween_property(lever, "rotation_degrees", Vector3(45, 0, 0), 0.3)

	# Show light
	light.visible = true

	# Play sound
	AudioManager.play_sound_3d("power_switch", global_position)

	# Notify game manager
	GameManager.activate_power()

	power_activated.emit()

	# Sync to network
	if multiplayer.is_server():
		rpc("_sync_activate")


@rpc("authority", "call_remote", "reliable")
func _sync_activate() -> void:
	if not is_activated:
		activate_power()


func get_prompt(_player: Node) -> String:
	if is_activated:
		return ""

	return "Activate Power"
