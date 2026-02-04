extends Resource
class_name WeaponData
## Weapon stats and configuration data

@export var weapon_id: String = ""
@export var display_name: String = ""
@export var weapon_type: WeaponType = WeaponType.PISTOL

enum WeaponType {
	PISTOL,
	SHOTGUN,
	RIFLE,
	SMG,
	AR,
	LMG,
	SNIPER,
	WONDER
}

# Damage
@export var base_damage: int = 30
@export var headshot_multiplier: float = 2.0
@export var pellet_count: int = 1  # For shotguns

# Fire rate
@export var fire_rate: float = 0.2  # Time between shots
@export var is_automatic: bool = false

# Ammo
@export var magazine_size: int = 8
@export var reserve_ammo: int = 80
@export var max_reserve: int = 80

# Reload
@export var reload_time: float = 1.5
@export var reload_slows_movement: bool = false  # If true, slows player during reload
@export var reload_speed_multiplier: float = 1.0  # Movement speed multiplier during reload
@export var reload_cancellable: bool = false  # If true, sprint/jump cancels reload

# Accuracy
@export var spread: float = 0.0  # In degrees
@export var aim_spread: float = 0.0
@export var recoil: float = 0.05

# Range
@export var max_range: float = 100.0

# Wall buy
@export var wall_cost: int = 0  # 0 = not wall buyable
@export var ammo_cost: int = 0

# Mystery box
@export var mystery_box_weapon: bool = false

# Pack-a-Punch
@export var pap_name: String = ""
@export var pap_damage_multiplier: float = 2.0
@export var pap_magazine_bonus: int = 0
@export var pap_special_effect: String = ""  # "explosive", "electric", etc.

# Audio
@export var fire_sound: String = "pistol_fire"
@export var reload_sound: String = "reload"

# Visuals
@export var model_path: String = ""
@export var muzzle_flash: bool = true


# Create weapon data from dictionary
static func from_dict(data: Dictionary) -> Resource:
	var script: GDScript = load("res://scripts/weapons/weapon_data.gd")
	var weapon: Resource = script.new()

	weapon.weapon_id = data.get("weapon_id", "")
	weapon.display_name = data.get("display_name", "")
	weapon.weapon_type = data.get("weapon_type", WeaponType.PISTOL)

	weapon.base_damage = data.get("base_damage", 30)
	weapon.headshot_multiplier = data.get("headshot_multiplier", 2.0)
	weapon.pellet_count = data.get("pellet_count", 1)

	weapon.fire_rate = data.get("fire_rate", 0.2)
	weapon.is_automatic = data.get("is_automatic", false)

	weapon.magazine_size = data.get("magazine_size", 8)
	weapon.reserve_ammo = data.get("reserve_ammo", 80)
	weapon.max_reserve = data.get("max_reserve", 80)

	weapon.reload_time = data.get("reload_time", 1.5)
	weapon.reload_slows_movement = data.get("reload_slows_movement", false)
	weapon.reload_speed_multiplier = data.get("reload_speed_multiplier", 1.0)
	weapon.reload_cancellable = data.get("reload_cancellable", false)

	weapon.spread = data.get("spread", 0.0)
	weapon.aim_spread = data.get("aim_spread", 0.0)
	weapon.recoil = data.get("recoil", 0.05)

	weapon.max_range = data.get("max_range", 100.0)

	weapon.wall_cost = data.get("wall_cost", 0)
	weapon.ammo_cost = data.get("ammo_cost", 0)

	weapon.mystery_box_weapon = data.get("mystery_box_weapon", false)

	weapon.pap_name = data.get("pap_name", "")
	weapon.pap_damage_multiplier = data.get("pap_damage_multiplier", 2.0)
	weapon.pap_magazine_bonus = data.get("pap_magazine_bonus", 0)
	weapon.pap_special_effect = data.get("pap_special_effect", "")

	weapon.fire_sound = data.get("fire_sound", "pistol_fire")
	weapon.reload_sound = data.get("reload_sound", "reload")

	weapon.model_path = data.get("model_path", "")
	weapon.muzzle_flash = data.get("muzzle_flash", true)

	return weapon
