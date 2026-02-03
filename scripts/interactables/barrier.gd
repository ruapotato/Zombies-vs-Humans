extends StaticBody3D
class_name Barrier
## Barrier/window that zombies break through and players repair

signal board_broken(boards_remaining: int)
signal board_repaired(boards_remaining: int)
signal barrier_destroyed
signal barrier_fully_repaired

const MAX_BOARDS := 6
const REPAIR_POINTS := 10
const REPAIR_COOLDOWN := 0.5

var boards_remaining: int = MAX_BOARDS
var is_repairing: bool = false
var repair_player: Node = null

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var boards_container: Node3D = $Boards
@onready var interaction_area: Area3D = $InteractionArea
@onready var spawn_point: Marker3D = $ZombieSpawnPoint
@onready var repair_timer: Timer = $RepairTimer


func _ready() -> void:
	add_to_group("barriers")
	_create_board_meshes()
	_update_visual()


func _create_board_meshes() -> void:
	# Create visual board pieces
	for i in range(MAX_BOARDS):
		var board := MeshInstance3D.new()
		var board_mesh := BoxMesh.new()
		board_mesh.size = Vector3(2.8, 0.3, 0.1)
		board.mesh = board_mesh

		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.4, 0.3, 0.2)
		board.set_surface_override_material(0, material)

		board.position = Vector3(0, 0.3 + (i * 0.35), 0.15)
		boards_container.add_child(board)


func _update_visual() -> void:
	# Show/hide boards based on remaining count
	var boards := boards_container.get_children()
	for i in range(boards.size()):
		boards[i].visible = (i < boards_remaining)

	# Update collision
	collision.disabled = (boards_remaining <= 0)

	# Update mesh visibility
	mesh.visible = false  # Use individual boards instead


func break_board() -> void:
	if boards_remaining <= 0:
		return

	boards_remaining -= 1
	_update_visual()

	AudioManager.play_sound_3d("barrier_break", global_position)
	board_broken.emit(boards_remaining)

	if boards_remaining <= 0:
		barrier_destroyed.emit()


func repair_board(player: Node) -> bool:
	if boards_remaining >= MAX_BOARDS:
		return false

	if is_repairing:
		return false

	is_repairing = true
	repair_player = player

	repair_timer.start()
	return true


func _on_repair_timer_timeout() -> void:
	if not repair_player:
		is_repairing = false
		return

	boards_remaining += 1
	_update_visual()

	# Award points
	repair_player.add_points(REPAIR_POINTS)

	AudioManager.play_sound_3d("barrier_repair", global_position)
	board_repaired.emit(boards_remaining)

	is_repairing = false

	if boards_remaining >= MAX_BOARDS:
		barrier_fully_repaired.emit()


func repair_fully() -> void:
	boards_remaining = MAX_BOARDS
	_update_visual()
	barrier_fully_repaired.emit()


func is_broken() -> bool:
	return boards_remaining <= 0


func get_spawn_position() -> Vector3:
	return spawn_point.global_position


func interact(player: Node) -> bool:
	return repair_board(player)


func get_prompt(player: Node) -> String:
	if boards_remaining >= MAX_BOARDS:
		return ""

	return "Hold F to Repair [+%d points]" % REPAIR_POINTS
