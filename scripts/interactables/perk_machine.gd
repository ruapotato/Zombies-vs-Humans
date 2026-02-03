extends Interactable
class_name PerkMachine
## Perk machine - allows players to buy perks

@export var perk_name: String = "juggernog"

# Perk definitions
const PERKS: Dictionary = {
	"juggernog": {
		"display_name": "Juggernog",
		"cost": 2500,
		"color": Color(1, 0.3, 0.3),
		"description": "250 HP instead of 100"
	},
	"speed_cola": {
		"display_name": "Speed Cola",
		"cost": 3000,
		"color": Color(0.3, 1, 0.3),
		"description": "50% faster reload"
	},
	"double_tap": {
		"display_name": "Double Tap",
		"cost": 2000,
		"color": Color(1, 1, 0.3),
		"description": "33% faster fire rate"
	},
	"quick_revive": {
		"display_name": "Quick Revive",
		"cost": 1500,  # 500 in solo
		"color": Color(0.3, 0.7, 1),
		"description": "Faster revive / Self-revive (solo)"
	},
	"stamin_up": {
		"display_name": "Stamin-Up",
		"cost": 2000,
		"color": Color(1, 0.8, 0.3),
		"description": "Faster sprint, unlimited stamina"
	},
	"phd_flopper": {
		"display_name": "PhD Flopper",
		"cost": 2000,
		"color": Color(0.6, 0.3, 1),
		"description": "No explosive self-damage"
	},
	"deadshot": {
		"display_name": "Deadshot Daiquiri",
		"cost": 1500,
		"color": Color(0.3, 0.3, 0.3),
		"description": "Auto-aim to head"
	},
	"mule_kick": {
		"display_name": "Mule Kick",
		"cost": 4000,
		"color": Color(0.5, 1, 0.5),
		"description": "Carry 3 weapons"
	}
}

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D = $Label3D
@onready var light: OmniLight3D = $Light


func _ready() -> void:
	super._ready()

	requires_power = true
	one_time_use = false

	_setup_perk()


func _setup_perk() -> void:
	if perk_name not in PERKS:
		push_warning("Unknown perk: %s" % perk_name)
		return

	var perk_data: Dictionary = PERKS[perk_name]

	cost = perk_data["cost"]

	# Adjust Quick Revive cost for solo
	if perk_name == "quick_revive" and GameManager.players.size() == 1:
		cost = 500

	interaction_prompt = "Buy %s" % perk_data["display_name"]

	# Set color
	var material := StandardMaterial3D.new()
	material.albedo_color = perk_data["color"]
	mesh.set_surface_override_material(0, material)

	light.light_color = perk_data["color"]
	label.text = perk_data["display_name"]


func _on_interacted(player: Node) -> void:
	if not player.has_method("add_perk"):
		return

	# Check if player already has this perk
	if player.has_perk(perk_name):
		AudioManager.play_sound_ui("denied")
		return

	# Check if player has max perks
	if player.perks.size() >= player.MAX_PERKS:
		AudioManager.play_sound_ui("denied")
		return

	# Add the perk
	player.add_perk(perk_name)

	# Play effects
	AudioManager.play_sound_3d("perk_drink", global_position)

	# Could play jingle here


func interact(player: Node) -> bool:
	if not is_usable:
		AudioManager.play_sound_ui("denied")
		return false

	# Check if player already has this perk
	if player.has_perk(perk_name):
		return false

	# Check max perks
	if player.perks.size() >= player.MAX_PERKS:
		return false

	if not player.can_afford(cost):
		AudioManager.play_sound_ui("denied")
		return false

	player.spend_points(cost)
	_on_interacted(player)
	AudioManager.play_sound_ui("purchase")

	return true


func get_prompt(player: Node) -> String:
	if not is_usable:
		return "Requires Power"

	if player.has_perk(perk_name):
		return ""

	if player.perks.size() >= player.MAX_PERKS:
		return "Max Perks Reached"

	var perk_data: Dictionary = PERKS.get(perk_name, {})
	var display_name: String = perk_data.get("display_name", perk_name)

	if player.can_afford(cost):
		return "Buy %s [Cost: %d]" % [display_name, cost]
	else:
		return "Buy %s [Cost: %d] (Need more points)" % [display_name, cost]
