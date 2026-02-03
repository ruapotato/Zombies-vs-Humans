extends Area3D
class_name Interactable
## Base class for all interactable objects

signal interacted(player: Node)

@export var interaction_prompt: String = "Press F to interact"
@export var cost: int = 0
@export var requires_power: bool = false
@export var one_time_use: bool = false

var is_usable: bool = true
var has_been_used: bool = false


func _ready() -> void:
	collision_layer = 16  # Interactable layer
	collision_mask = 0
	add_to_group("interactables")

	if requires_power:
		add_to_group("power_dependent")
		is_usable = GameManager.power_is_on


func interact(player: Node) -> bool:
	if not is_usable:
		AudioManager.play_sound_ui("denied")
		return false

	if one_time_use and has_been_used:
		return false

	if cost > 0:
		if not player.can_afford(cost):
			AudioManager.play_sound_ui("denied")
			return false

		player.spend_points(cost)

	has_been_used = true
	interacted.emit(player)
	_on_interacted(player)

	AudioManager.play_sound_ui("purchase")
	return true


func _on_interacted(player: Node) -> void:
	# Override in subclasses
	pass


func on_power_activated() -> void:
	if requires_power:
		is_usable = true


func get_prompt(player: Node) -> String:
	if not is_usable:
		if requires_power:
			return "Requires Power"
		return ""

	if one_time_use and has_been_used:
		return ""

	if cost > 0:
		if player.can_afford(cost):
			return "%s [Cost: %d]" % [interaction_prompt, cost]
		else:
			return "%s [Cost: %d] (Not enough points)" % [interaction_prompt, cost]

	return interaction_prompt
