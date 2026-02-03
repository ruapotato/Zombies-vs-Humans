extends Area3D
class_name PowerUp
## Power-up drop that players can collect

signal collected(power_up_type: String, collector: Node)

const POWER_UP_DATA: Dictionary = {
	"max_ammo": {
		"display_name": "Max Ammo",
		"color": Color(0.2, 1, 0.2),
		"sound": "max_ammo",
		"announcement": "MAX AMMO!"
	},
	"insta_kill": {
		"display_name": "Insta-Kill",
		"color": Color(1, 1, 1),
		"sound": "insta_kill",
		"announcement": "INSTA-KILL!"
	},
	"double_points": {
		"display_name": "Double Points",
		"color": Color(1, 1, 0),
		"sound": "double_points",
		"announcement": "DOUBLE POINTS!"
	},
	"nuke": {
		"display_name": "Nuke",
		"color": Color(1, 0.5, 0),
		"sound": "nuke",
		"announcement": "NUKE!"
	},
	"carpenter": {
		"display_name": "Carpenter",
		"color": Color(0.6, 0.4, 0.2),
		"sound": "carpenter",
		"announcement": "CARPENTER!"
	},
	"fire_sale": {
		"display_name": "Fire Sale",
		"color": Color(1, 0, 0),
		"sound": "fire_sale",
		"announcement": "FIRE SALE!"
	}
}

@export var power_up_type: String = "max_ammo"

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var light: OmniLight3D = $Light
@onready var label: Label3D = $Label3D
@onready var despawn_timer: Timer = $DespawnTimer

var bob_offset: float = 0.0
var original_y: float = 0.0


func _ready() -> void:
	original_y = position.y
	_setup_appearance()

	AudioManager.play_sound_3d("powerup_spawn", global_position)


func _process(delta: float) -> void:
	# Bobbing animation
	bob_offset += delta * 3.0
	position.y = original_y + sin(bob_offset) * 0.2

	# Rotation
	rotation.y += delta * 2.0


func _setup_appearance() -> void:
	var data: Dictionary = POWER_UP_DATA.get(power_up_type, POWER_UP_DATA["max_ammo"])

	var material := StandardMaterial3D.new()
	material.albedo_color = data["color"]
	material.emission_enabled = true
	material.emission = data["color"]
	material.emission_energy_multiplier = 2.0
	mesh.set_surface_override_material(0, material)

	light.light_color = data["color"]
	label.text = data["display_name"]


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("players"):
		return

	_collect(body)


func _collect(player: Node) -> void:
	var data: Dictionary = POWER_UP_DATA.get(power_up_type, POWER_UP_DATA["max_ammo"])

	# Play sound
	AudioManager.play_sound_ui(data["sound"])

	# Notify game manager
	if multiplayer.is_server():
		GameManager.collect_power_up(power_up_type, player.player_id)

	collected.emit(power_up_type, player)

	# Remove power-up
	queue_free()


func _on_despawn_timer_timeout() -> void:
	# Fade out and despawn
	var tween := create_tween()
	tween.tween_property(mesh, "transparency", 1.0, 1.0)
	tween.parallel().tween_property(light, "light_energy", 0.0, 1.0)
	tween.tween_callback(queue_free)
