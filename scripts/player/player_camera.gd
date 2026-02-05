extends Camera3D
## First-person camera controller with mouse look

const MOUSE_SENSITIVITY := 0.002
const ADS_SENSITIVITY_MULTIPLIER := 0.5  # Half sensitivity when aiming
const CONTROLLER_SENSITIVITY := 3.0
const MAX_PITCH := 89.0
const MIN_PITCH := -89.0

var pitch := 0.0
var yaw := 0.0

var player: CharacterBody3D = null
var camera_mount: Node3D = null


func _ready() -> void:
	# Camera3D -> CameraMount -> Player (2 levels up)
	camera_mount = get_parent() as Node3D
	player = get_parent().get_parent() as CharacterBody3D

	if not player:
		push_error("player_camera: Could not find player node")
		set_process_input(false)
		set_process(false)
		return

	# Only process input for local player
	if not player.is_multiplayer_authority():
		set_process_input(false)
		set_process(false)


func _input(event: InputEvent) -> void:
	if not player or not player.is_multiplayer_authority():
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	# Reduce sensitivity when aiming down sights
	var sensitivity := MOUSE_SENSITIVITY
	if player.is_aiming:
		sensitivity *= ADS_SENSITIVITY_MULTIPLIER

	yaw -= event.relative.x * sensitivity
	pitch -= event.relative.y * sensitivity

	pitch = clamp(pitch, deg_to_rad(MIN_PITCH), deg_to_rad(MAX_PITCH))

	# Apply rotation
	player.rotation.y = yaw
	camera_mount.rotation.x = pitch


func _process(_delta: float) -> void:
	if not player or not player.is_multiplayer_authority():
		return

	# Controller look support is disabled - mouse look only
	# To add controller support, define look_left/right/up/down actions in Project Settings
	pass
