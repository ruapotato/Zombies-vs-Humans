extends Interactable
class_name ShopMachine
## Shop machine - buy ammo, armor, and weapons

enum ShopItem { AMMO, ARMOR, RANDOM_WEAPON }

const AMMO_COST := 500
const ARMOR_COST := 1500
const WEAPON_COST := 2000
const ARMOR_AMOUNT := 50  # Extra health from armor

var current_selection: ShopItem = ShopItem.AMMO

@onready var label: Label3D = $Label3D
@onready var info_label: Label3D = $InfoLabel
@onready var mesh: MeshInstance3D = $MeshInstance3D

# Available weapons for random purchase
var shop_weapons: Array[String] = [
	"mp5", "ak47", "m14", "olympia", "stakeout",
	"rpk", "galil", "python", "spas12", "commando", "aug"
]


func _ready() -> void:
	super._ready()
	requires_power = false
	one_time_use = false
	label.text = "SHOP"
	_update_info_label()


func _update_info_label() -> void:
	info_label.text = "Ammo | Armor | Gun"


func interact(player: Node) -> bool:
	# Cycle through options on interact
	# Press F once = ammo, twice = armor, three times = weapon
	# Actually, let's make it simpler - just buy ammo for current weapon
	return _buy_ammo(player)


func _buy_ammo(player: Node) -> bool:
	if not player.can_afford(AMMO_COST):
		AudioManager.play_sound_ui("denied")
		return false

	var current_weapon: Node = player.get_current_weapon()
	if not current_weapon:
		return false

	if current_weapon.reserve_ammo >= current_weapon.max_reserve:
		AudioManager.play_sound_ui("denied")
		return false

	player.spend_points(AMMO_COST)
	current_weapon.refill_ammo()
	AudioManager.play_sound_ui("purchase")
	return true


func buy_armor(player: Node) -> bool:
	if not player.can_afford(ARMOR_COST):
		AudioManager.play_sound_ui("denied")
		return false

	# Add temporary armor/health boost
	player.spend_points(ARMOR_COST)
	player.max_health += ARMOR_AMOUNT
	player.health = player.max_health
	player.health_changed.emit(player.health, player.max_health)
	AudioManager.play_sound_ui("purchase")
	return true


func buy_random_weapon(player: Node) -> bool:
	if not player.can_afford(WEAPON_COST):
		AudioManager.play_sound_ui("denied")
		return false

	# Get a random weapon the player doesn't have
	var available_weapons: Array[String] = []
	for weapon_id in shop_weapons:
		var has_weapon := false
		for weapon in player.weapons:
			if weapon.weapon_id == weapon_id:
				has_weapon = true
				break
		if not has_weapon:
			available_weapons.append(weapon_id)

	if available_weapons.is_empty():
		AudioManager.play_sound_ui("denied")
		return false

	var random_weapon: String = available_weapons[randi() % available_weapons.size()]

	player.spend_points(WEAPON_COST)

	if player.weapons.size() >= player.max_weapons:
		player.replace_weapon(random_weapon)
	else:
		player.give_weapon(random_weapon)

	AudioManager.play_sound_ui("purchase")
	return true


func get_prompt(player: Node) -> String:
	var current_weapon: Node = player.get_current_weapon()
	var ammo_full := false

	if current_weapon:
		ammo_full = current_weapon.reserve_ammo >= current_weapon.max_reserve

	var lines: Array[String] = []

	# Ammo option
	if ammo_full:
		lines.append("[F] Ammo Full")
	elif player.can_afford(AMMO_COST):
		lines.append("[F] Buy Ammo - %d pts" % AMMO_COST)
	else:
		lines.append("[F] Ammo - %d pts (need more)" % AMMO_COST)

	return lines[0]
