extends Node
class_name WeaponRegistry
## Static weapon data registry

const WeaponDataScript = preload("res://scripts/weapons/weapon_data.gd")

# All weapon definitions
static var WEAPONS: Dictionary = {
	# Starting Pistol
	"m1911": {
		"weapon_id": "m1911",
		"display_name": "M1911",
		"weapon_type": WeaponDataScript.WeaponType.PISTOL,
		"base_damage": 30,
		"fire_rate": 0.15,
		"is_automatic": false,
		"magazine_size": 8,
		"reserve_ammo": 80,
		"max_reserve": 80,
		"reload_time": 1.5,
		"spread": 1.0,
		"aim_spread": 0.2,
		"recoil": 0.03,
		"wall_cost": 0,
		"pap_name": "Mustang & Sally",
		"pap_special_effect": "explosive",
		"fire_sound": "pistol_fire"
	},

	# Wall Weapons
	"olympia": {
		"weapon_id": "olympia",
		"display_name": "Olympia",
		"weapon_type": WeaponDataScript.WeaponType.SHOTGUN,
		"base_damage": 120,
		"pellet_count": 8,
		"fire_rate": 0.8,
		"is_automatic": false,
		"magazine_size": 2,
		"reserve_ammo": 38,
		"max_reserve": 38,
		"reload_time": 2.5,
		"reload_slows_movement": true,
		"reload_speed_multiplier": 0.25,
		"reload_cancellable": true,
		"spread": 8.0,
		"aim_spread": 5.0,
		"recoil": 0.15,
		"max_range": 20.0,
		"wall_cost": 500,
		"ammo_cost": 250,
		"pap_name": "Hades",
		"fire_sound": "shotgun_fire"
	},

	"m14": {
		"weapon_id": "m14",
		"display_name": "M14",
		"weapon_type": WeaponDataScript.WeaponType.RIFLE,
		"base_damage": 80,
		"fire_rate": 0.2,
		"is_automatic": false,
		"magazine_size": 8,
		"reserve_ammo": 96,
		"max_reserve": 96,
		"reload_time": 1.8,
		"spread": 0.5,
		"aim_spread": 0.1,
		"recoil": 0.06,
		"wall_cost": 500,
		"ammo_cost": 250,
		"pap_name": "Mnesia",
		"fire_sound": "rifle_fire"
	},

	"mp5": {
		"weapon_id": "mp5",
		"display_name": "MP5K",
		"weapon_type": WeaponDataScript.WeaponType.SMG,
		"base_damage": 40,
		"fire_rate": 0.075,
		"is_automatic": true,
		"magazine_size": 30,
		"reserve_ammo": 120,
		"max_reserve": 120,
		"reload_time": 2.0,
		"spread": 2.0,
		"aim_spread": 0.8,
		"recoil": 0.02,
		"wall_cost": 1000,
		"ammo_cost": 500,
		"pap_name": "MP115 Kollider",
		"fire_sound": "smg_fire"
	},

	"ak47": {
		"weapon_id": "ak47",
		"display_name": "AK-47",
		"weapon_type": WeaponDataScript.WeaponType.AR,
		"base_damage": 70,
		"fire_rate": 0.1,
		"is_automatic": true,
		"magazine_size": 30,
		"reserve_ammo": 180,
		"max_reserve": 180,
		"reload_time": 2.5,
		"spread": 1.5,
		"aim_spread": 0.5,
		"recoil": 0.05,
		"wall_cost": 1200,
		"ammo_cost": 600,
		"pap_name": "AK-47u",
		"pap_special_effect": "electric",
		"fire_sound": "rifle_fire"
	},

	"stakeout": {
		"weapon_id": "stakeout",
		"display_name": "Stakeout",
		"weapon_type": WeaponDataScript.WeaponType.SHOTGUN,
		"base_damage": 160,
		"pellet_count": 8,
		"fire_rate": 0.6,
		"is_automatic": false,
		"magazine_size": 6,
		"reserve_ammo": 54,
		"max_reserve": 54,
		"reload_time": 3.0,
		"spread": 6.0,
		"aim_spread": 4.0,
		"recoil": 0.12,
		"max_range": 25.0,
		"wall_cost": 1500,
		"ammo_cost": 750,
		"pap_name": "Raid",
		"fire_sound": "shotgun_fire"
	},

	# Mystery Box Weapons
	"ray_gun": {
		"weapon_id": "ray_gun",
		"display_name": "Ray Gun",
		"weapon_type": WeaponDataScript.WeaponType.WONDER,
		"base_damage": 200,
		"fire_rate": 0.3,
		"is_automatic": false,
		"magazine_size": 20,
		"reserve_ammo": 160,
		"max_reserve": 160,
		"reload_time": 3.0,
		"spread": 0.0,
		"aim_spread": 0.0,
		"recoil": 0.08,
		"mystery_box_weapon": true,
		"pap_name": "Porter's X2 Ray Gun",
		"pap_special_effect": "splash",
		"fire_sound": "raygun_fire"
	},

	"thundergun": {
		"weapon_id": "thundergun",
		"display_name": "Thundergun",
		"weapon_type": WeaponDataScript.WeaponType.WONDER,
		"base_damage": 9999,
		"fire_rate": 1.5,
		"is_automatic": false,
		"magazine_size": 2,
		"reserve_ammo": 12,
		"max_reserve": 12,
		"reload_time": 4.0,
		"spread": 15.0,
		"aim_spread": 15.0,
		"recoil": 0.2,
		"max_range": 30.0,
		"mystery_box_weapon": true,
		"pap_name": "Zeus Cannon",
		"pap_magazine_bonus": 2,
		"fire_sound": "thundergun_fire"
	},

	"rpk": {
		"weapon_id": "rpk",
		"display_name": "RPK",
		"weapon_type": WeaponDataScript.WeaponType.LMG,
		"base_damage": 60,
		"fire_rate": 0.08,
		"is_automatic": true,
		"magazine_size": 100,
		"reserve_ammo": 400,
		"max_reserve": 400,
		"reload_time": 4.5,
		"spread": 2.5,
		"aim_spread": 1.0,
		"recoil": 0.04,
		"mystery_box_weapon": true,
		"pap_name": "R115 Resonator",
		"fire_sound": "lmg_fire"
	},

	"galil": {
		"weapon_id": "galil",
		"display_name": "Galil",
		"weapon_type": WeaponDataScript.WeaponType.AR,
		"base_damage": 75,
		"fire_rate": 0.09,
		"is_automatic": true,
		"magazine_size": 35,
		"reserve_ammo": 315,
		"max_reserve": 315,
		"reload_time": 2.8,
		"spread": 1.2,
		"aim_spread": 0.4,
		"recoil": 0.04,
		"mystery_box_weapon": true,
		"pap_name": "Lamentation",
		"fire_sound": "rifle_fire"
	},

	"python": {
		"weapon_id": "python",
		"display_name": "Python",
		"weapon_type": WeaponDataScript.WeaponType.PISTOL,
		"base_damage": 100,
		"fire_rate": 0.25,
		"is_automatic": false,
		"magazine_size": 6,
		"reserve_ammo": 84,
		"max_reserve": 84,
		"reload_time": 2.2,
		"spread": 0.8,
		"aim_spread": 0.2,
		"recoil": 0.1,
		"mystery_box_weapon": true,
		"pap_name": "Cobra",
		"fire_sound": "pistol_fire"
	},

	"spas12": {
		"weapon_id": "spas12",
		"display_name": "SPAS-12",
		"weapon_type": WeaponDataScript.WeaponType.SHOTGUN,
		"base_damage": 140,
		"pellet_count": 8,
		"fire_rate": 0.4,
		"is_automatic": true,
		"magazine_size": 8,
		"reserve_ammo": 32,
		"max_reserve": 32,
		"reload_time": 3.5,
		"spread": 7.0,
		"aim_spread": 5.0,
		"recoil": 0.1,
		"max_range": 22.0,
		"mystery_box_weapon": true,
		"pap_name": "SPAZ-24",
		"fire_sound": "shotgun_fire"
	},

	"dragunov": {
		"weapon_id": "dragunov",
		"display_name": "Dragunov",
		"weapon_type": WeaponDataScript.WeaponType.SNIPER,
		"base_damage": 300,
		"fire_rate": 0.35,
		"is_automatic": false,
		"magazine_size": 10,
		"reserve_ammo": 40,
		"max_reserve": 40,
		"reload_time": 2.5,
		"spread": 0.0,
		"aim_spread": 0.0,
		"recoil": 0.12,
		"mystery_box_weapon": true,
		"pap_name": "D115 Disassembler",
		"fire_sound": "sniper_fire"
	},

	"commando": {
		"weapon_id": "commando",
		"display_name": "Commando",
		"weapon_type": WeaponDataScript.WeaponType.AR,
		"base_damage": 65,
		"fire_rate": 0.085,
		"is_automatic": true,
		"magazine_size": 30,
		"reserve_ammo": 270,
		"max_reserve": 270,
		"reload_time": 2.3,
		"spread": 1.0,
		"aim_spread": 0.3,
		"recoil": 0.035,
		"mystery_box_weapon": true,
		"pap_name": "Predator",
		"fire_sound": "rifle_fire"
	},

	"aug": {
		"weapon_id": "aug",
		"display_name": "AUG",
		"weapon_type": WeaponDataScript.WeaponType.AR,
		"base_damage": 68,
		"fire_rate": 0.08,
		"is_automatic": true,
		"magazine_size": 30,
		"reserve_ammo": 270,
		"max_reserve": 270,
		"reload_time": 2.4,
		"spread": 1.0,
		"aim_spread": 0.2,
		"recoil": 0.03,
		"mystery_box_weapon": true,
		"pap_name": "AUG-50M3",
		"fire_sound": "rifle_fire"
	},

	"famas": {
		"weapon_id": "famas",
		"display_name": "FAMAS",
		"weapon_type": WeaponDataScript.WeaponType.AR,
		"base_damage": 60,
		"fire_rate": 0.065,
		"is_automatic": true,
		"magazine_size": 30,
		"reserve_ammo": 240,
		"max_reserve": 240,
		"reload_time": 2.2,
		"spread": 1.2,
		"aim_spread": 0.4,
		"recoil": 0.025,
		"mystery_box_weapon": true,
		"pap_name": "G16-GL35",
		"fire_sound": "rifle_fire"
	}
}


static func get_weapon_data(weapon_id: String) -> Resource:
	if weapon_id in WEAPONS:
		return WeaponDataScript.from_dict(WEAPONS[weapon_id])
	return null


static func get_wall_weapons() -> Array[String]:
	var result: Array[String] = []
	for weapon_id in WEAPONS:
		var data: Dictionary = WEAPONS[weapon_id]
		if data.get("wall_cost", 0) > 0:
			result.append(weapon_id)
	return result


static func get_mystery_box_weapons() -> Array[String]:
	var result: Array[String] = []
	for weapon_id in WEAPONS:
		var data: Dictionary = WEAPONS[weapon_id]
		if data.get("mystery_box_weapon", false):
			result.append(weapon_id)
	return result


static func get_random_mystery_box_weapon() -> String:
	var weapons := get_mystery_box_weapons()
	if weapons.is_empty():
		return "m1911"
	return weapons[randi_range(0, weapons.size() - 1)]
