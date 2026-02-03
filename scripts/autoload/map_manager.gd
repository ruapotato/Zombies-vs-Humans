extends Node
## MapManager - Map loading and selection singleton
## Handles available maps, loading, and map-specific configurations

signal map_loaded(map_name: String)
signal map_list_updated

const MAPS_DIRECTORY := "res://scenes/maps/"
const MAP_DATA_DIRECTORY := "res://data/maps/"

var available_maps: Array[Dictionary] = []
var current_map: String = ""
var current_map_data: Dictionary = {}

# Map configuration template
const DEFAULT_MAP_DATA := {
	"name": "",
	"display_name": "",
	"description": "",
	"author": "Unknown",
	"max_players": 4,
	"difficulty": 1,  # 1-5
	"spawn_points": [],  # Player spawn positions
	"zombie_spawn_points": [],  # Zombie spawn positions
	"perk_machine_locations": {},  # perk_name -> position
	"mystery_box_locations": [],  # List of possible positions
	"pack_a_punch_location": Vector3.ZERO,
	"power_switch_location": Vector3.ZERO,
	"wall_weapons": [],  # {weapon_id, position, rotation}
	"doors": [],  # {id, cost, unlock_area}
	"barriers": [],  # {id, position, health}
	"nav_mesh_path": "",
	"ambient_sound": "",
	"preview_image": ""
}


func _ready() -> void:
	_scan_available_maps()


func _scan_available_maps() -> void:
	available_maps.clear()

	var dir := DirAccess.open(MAPS_DIRECTORY)
	if not dir:
		push_warning("Cannot access maps directory: %s" % MAPS_DIRECTORY)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name.ends_with(".tscn"):
			var map_name := file_name.get_basename()
			var map_data := _load_map_data(map_name)

			if map_data.is_empty():
				map_data = DEFAULT_MAP_DATA.duplicate()
				map_data["name"] = map_name
				map_data["display_name"] = map_name.capitalize()

			available_maps.append(map_data)

		file_name = dir.get_next()

	dir.list_dir_end()

	# Sort by name
	available_maps.sort_custom(func(a, b): return a["display_name"] < b["display_name"])

	map_list_updated.emit()


func _load_map_data(map_name: String) -> Dictionary:
	var data_path := MAP_DATA_DIRECTORY + map_name + ".tres"

	if ResourceLoader.exists(data_path):
		var resource := load(data_path)
		if resource and resource is Resource:
			return resource.get_meta("map_data", {})

	# Try JSON format
	var json_path := MAP_DATA_DIRECTORY + map_name + ".json"
	if FileAccess.file_exists(json_path):
		var file := FileAccess.open(json_path, FileAccess.READ)
		if file:
			var json := JSON.new()
			var error := json.parse(file.get_as_text())
			file.close()

			if error == OK:
				return json.data

	return {}


func get_available_maps() -> Array[Dictionary]:
	return available_maps


func get_map_by_name(map_name: String) -> Dictionary:
	for map_data in available_maps:
		if map_data["name"] == map_name:
			return map_data
	return {}


func load_map(map_name: String) -> bool:
	var map_path := MAPS_DIRECTORY + map_name + ".tscn"

	if not ResourceLoader.exists(map_path):
		push_error("Map not found: %s" % map_path)
		return false

	current_map = map_name
	current_map_data = _load_map_data(map_name)

	if current_map_data.is_empty():
		current_map_data = DEFAULT_MAP_DATA.duplicate()
		current_map_data["name"] = map_name

	map_loaded.emit(map_name)
	return true


func get_map_scene_path(map_name: String) -> String:
	return MAPS_DIRECTORY + map_name + ".tscn"


func get_current_map_scene() -> PackedScene:
	if current_map.is_empty():
		return null

	var map_path := get_map_scene_path(current_map)
	if ResourceLoader.exists(map_path):
		return load(map_path)

	return null


func get_spawn_points() -> Array:
	return current_map_data.get("spawn_points", [])


func get_zombie_spawn_points() -> Array:
	return current_map_data.get("zombie_spawn_points", [])


func get_perk_machine_location(perk_name: String) -> Vector3:
	var locations: Dictionary = current_map_data.get("perk_machine_locations", {})
	return locations.get(perk_name, Vector3.ZERO)


func get_mystery_box_locations() -> Array:
	return current_map_data.get("mystery_box_locations", [])


func get_pack_a_punch_location() -> Vector3:
	return current_map_data.get("pack_a_punch_location", Vector3.ZERO)


func get_power_switch_location() -> Vector3:
	return current_map_data.get("power_switch_location", Vector3.ZERO)


func get_wall_weapons() -> Array:
	return current_map_data.get("wall_weapons", [])


func get_doors() -> Array:
	return current_map_data.get("doors", [])


func get_barriers() -> Array:
	return current_map_data.get("barriers", [])


func get_random_zombie_spawn() -> Vector3:
	var spawn_points := get_zombie_spawn_points()
	if spawn_points.is_empty():
		return Vector3.ZERO

	return spawn_points[randi() % spawn_points.size()]


func get_random_player_spawn() -> Vector3:
	var spawn_points := get_spawn_points()
	if spawn_points.is_empty():
		return Vector3.ZERO

	return spawn_points[randi() % spawn_points.size()]


# Create map data file for a new map
func create_map_data(map_name: String, data: Dictionary) -> bool:
	var json_path := MAP_DATA_DIRECTORY + map_name + ".json"

	# Ensure directory exists
	var dir := DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive(MAP_DATA_DIRECTORY.replace("res://", ""))

	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if not file:
		push_error("Cannot create map data file: %s" % json_path)
		return false

	var json_string := JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()

	_scan_available_maps()
	return true


# Validate map has required components
func validate_map(map_name: String) -> Dictionary:
	var issues: Array[String] = []
	var warnings: Array[String] = []

	var data := get_map_by_name(map_name)

	if data.is_empty():
		issues.append("Map data not found")
		return {"valid": false, "issues": issues, "warnings": warnings}

	# Check spawn points
	var spawn_points: Array = data.get("spawn_points", [])
	if spawn_points.is_empty():
		issues.append("No player spawn points defined")
	elif spawn_points.size() < 4:
		warnings.append("Less than 4 player spawn points (max players may be limited)")

	var zombie_spawns: Array = data.get("zombie_spawn_points", [])
	if zombie_spawns.is_empty():
		issues.append("No zombie spawn points defined")
	elif zombie_spawns.size() < 5:
		warnings.append("Very few zombie spawn points (may cause crowding)")

	# Check essential locations
	if data.get("power_switch_location", Vector3.ZERO) == Vector3.ZERO:
		warnings.append("No power switch location defined")

	if data.get("pack_a_punch_location", Vector3.ZERO) == Vector3.ZERO:
		warnings.append("No Pack-a-Punch location defined")

	var mystery_boxes: Array = data.get("mystery_box_locations", [])
	if mystery_boxes.is_empty():
		warnings.append("No Mystery Box locations defined")

	var perks: Dictionary = data.get("perk_machine_locations", {})
	if perks.is_empty():
		warnings.append("No perk machine locations defined")

	return {
		"valid": issues.is_empty(),
		"issues": issues,
		"warnings": warnings
	}
