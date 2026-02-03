extends Interactable
class_name WallWeapon
## Wall weapon buy location

@export var weapon_id: String = "m14"

var weapon_data: WeaponData
var ammo_cost: int = 0

@onready var label: Label3D = $Label3D
@onready var cost_label: Label3D = $CostLabel
@onready var mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	super._ready()

	requires_power = false
	one_time_use = false

	_setup_weapon()


func _setup_weapon() -> void:
	weapon_data = WeaponRegistry.get_weapon_data(weapon_id)

	if not weapon_data:
		push_warning("Unknown weapon: %s" % weapon_id)
		return

	cost = weapon_data.wall_cost
	ammo_cost = weapon_data.ammo_cost

	if ammo_cost == 0:
		ammo_cost = cost / 2

	interaction_prompt = "Buy %s" % weapon_data.display_name
	label.text = weapon_data.display_name
	cost_label.text = str(cost)


func interact(player: Node) -> bool:
	# Check if player already has this weapon
	var has_weapon := false
	for weapon in player.weapons:
		if weapon.weapon_id == weapon_id:
			has_weapon = true
			break

	if has_weapon:
		# Buy ammo instead
		return _buy_ammo(player)
	else:
		# Buy weapon
		return _buy_weapon(player)


func _buy_weapon(player: Node) -> bool:
	if not player.can_afford(cost):
		AudioManager.play_sound_ui("denied")
		return false

	if player.weapons.size() >= player.max_weapons:
		# Replace current weapon
		player.spend_points(cost)
		player.replace_weapon(weapon_id)
	else:
		player.spend_points(cost)
		player.give_weapon(weapon_id)

	AudioManager.play_sound_ui("purchase")
	return true


func _buy_ammo(player: Node) -> bool:
	if not player.can_afford(ammo_cost):
		AudioManager.play_sound_ui("denied")
		return false

	# Find the weapon and check if it needs ammo
	for weapon in player.weapons:
		if weapon.weapon_id == weapon_id:
			if weapon.reserve_ammo >= weapon.max_reserve:
				# Already full
				return false

			player.spend_points(ammo_cost)
			weapon.refill_ammo()
			AudioManager.play_sound_ui("purchase")
			return true

	return false


func get_prompt(player: Node) -> String:
	if not weapon_data:
		return ""

	# Check if player has this weapon
	var has_weapon := false
	var weapon_full := false

	for weapon in player.weapons:
		if weapon.weapon_id == weapon_id:
			has_weapon = true
			weapon_full = weapon.reserve_ammo >= weapon.max_reserve
			break

	if has_weapon:
		if weapon_full:
			return "Ammo Full"

		if player.can_afford(ammo_cost):
			return "Buy Ammo [Cost: %d]" % ammo_cost
		else:
			return "Buy Ammo [Cost: %d] (Need more points)" % ammo_cost
	else:
		if player.can_afford(cost):
			return "Buy %s [Cost: %d]" % [weapon_data.display_name, cost]
		else:
			return "Buy %s [Cost: %d] (Need more points)" % [weapon_data.display_name, cost]
