extends Control
## Tactical minimap with map geometry, zombie radar, compass, smart POIs, and teammate markers

# Configuration
const MINIMAP_RADIUS := 116.0  # Half of 240 minus border
const DEFAULT_MINIMAP_SCALE := 4.0  # Fallback pixels per world unit
const MAX_ZOMBIE_DOTS := 30
const ZOMBIE_UPDATE_INTERVAL := 0.2
const POI_REFRESH_INTERVAL := 2.0
const MAP_SCAN_INTERVAL := 1.0  # Retry scan if no geometry found
const ZOMBIE_DOT_SIZE := 5.0
const POI_DOT_SIZE := 7.0
const EDGE_ARROW_MARGIN := 10.0
const MIN_WALL_PIXEL_WIDTH := 3.0  # Minimum rendered wall thickness in pixels

# All POI types get off-screen edge indicators (dots + distance)
# Important ones get larger arrows, minor ones get small dots
const IMPORTANT_POI_TYPES: Array[String] = ["power", "perk", "mystery_box", "pack_a_punch"]

# Perk icon colors (shared with HUD)
const PERK_COLORS: Dictionary = {
	"juggernog": Color(1, 0.3, 0.3),
	"speed_cola": Color(0.3, 1, 0.3),
	"double_tap": Color(1, 1, 0.3),
	"quick_revive": Color(0.3, 0.7, 1),
	"stamin_up": Color(1, 0.8, 0.3),
	"phd_flopper": Color(0.6, 0.3, 1),
	"deadshot": Color(0.3, 0.3, 0.3),
	"mule_kick": Color(0.5, 1, 0.5),
	"spring_heels": Color(0.3, 1, 1)
}

# Teammate colors
const TEAMMATE_COLORS: Array[Color] = [
	Color(0.3, 0.5, 1.0),   # Blue
	Color(0.3, 1.0, 0.3),   # Green
	Color(0.7, 0.3, 1.0),   # Purple
	Color(1.0, 0.6, 0.2),   # Orange
]

# Map geometry drawing colors - high contrast for readability
const WALL_COLOR := Color(0.85, 0.85, 0.9, 0.95)
const WALL_OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const FLOOR_COLOR := Color(0.12, 0.15, 0.22, 0.55)
const PILLAR_COLOR := Color(0.65, 0.65, 0.7, 0.85)

# Node references
var map_container: Control
var geometry_layer: Control
var zombie_container: Control
var poi_container: Control
var teammate_container: Control
var edge_indicator_container: Control
var compass_ring: Control
var player_marker: Control
var damage_border: ColorRect
var objective_arrow: Control

# State
var local_player: Node = null
var zombie_dots: Array[Control] = []
var poi_entries: Array[Dictionary] = []  # {node, marker, type, edge_dot, edge_label}
var teammate_markers: Dictionary = {}  # player_id -> {marker, label}
var zombie_timer: float = 0.0
var poi_timer: float = 0.0
var map_scan_timer: float = 0.0
var objective_target: Node = null
var damage_intensity: float = 0.0

# Map geometry cache
var map_scanned: bool = false
var minimap_scale: float = DEFAULT_MINIMAP_SCALE
var map_walls: Array[PackedVector2Array] = []   # Each is 4 corners in world XZ
var map_floors: Array[PackedVector2Array] = []  # Each is 4 corners in world XZ
var map_pillars: Array[PackedVector2Array] = [] # Each is 4 corners in world XZ
var map_center: Vector2 = Vector2.ZERO  # Center of map bounds for offset


func _ready() -> void:
	_build_subtree()
	_create_zombie_dot_pool()


func set_local_player(player: Node) -> void:
	local_player = player
	if local_player and local_player.has_signal("damage_intensity_changed"):
		if not local_player.damage_intensity_changed.is_connected(_on_damage_intensity_changed):
			local_player.damage_intensity_changed.connect(_on_damage_intensity_changed)


func set_objective_target(target: Node) -> void:
	objective_target = target


func _process(delta: float) -> void:
	if not local_player or not is_instance_valid(local_player):
		return

	# Scan map geometry if not done yet (retry periodically)
	if not map_scanned:
		map_scan_timer += delta
		if map_scan_timer >= MAP_SCAN_INTERVAL:
			map_scan_timer = 0.0
			_scan_map_geometry()

	# Zombie radar update (throttled)
	zombie_timer += delta
	if zombie_timer >= ZOMBIE_UPDATE_INTERVAL:
		zombie_timer = 0.0
		_update_zombie_dots()

	# POI refresh (throttled)
	poi_timer += delta
	if poi_timer >= POI_REFRESH_INTERVAL:
		poi_timer = 0.0
		_refresh_pois()

	# These update every frame (cheap)
	_update_poi_positions()
	_update_teammate_markers()
	_update_objective_arrow()
	_update_damage_border(delta)
	geometry_layer.queue_redraw()
	compass_ring.queue_redraw()
	player_marker.queue_redraw()


func _build_subtree() -> void:
	# MapContainer (clip_contents, centered content)
	map_container = Control.new()
	map_container.name = "MapContainer"
	map_container.clip_contents = true
	map_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_container.offset_left = 2.0
	map_container.offset_top = 2.0
	map_container.offset_right = -2.0
	map_container.offset_bottom = -2.0
	add_child(map_container)

	# GeometryLayer (draws map walls/floors behind everything)
	geometry_layer = Control.new()
	geometry_layer.name = "GeometryLayer"
	geometry_layer.set_anchors_preset(Control.PRESET_CENTER)
	geometry_layer.z_index = -1
	map_container.add_child(geometry_layer)
	geometry_layer.draw.connect(_draw_map_geometry)

	# ZombieContainer
	zombie_container = Control.new()
	zombie_container.name = "ZombieContainer"
	zombie_container.set_anchors_preset(Control.PRESET_CENTER)
	map_container.add_child(zombie_container)

	# POIContainer
	poi_container = Control.new()
	poi_container.name = "POIContainer"
	poi_container.set_anchors_preset(Control.PRESET_CENTER)
	map_container.add_child(poi_container)

	# TeammateContainer
	teammate_container = Control.new()
	teammate_container.name = "TeammateContainer"
	teammate_container.set_anchors_preset(Control.PRESET_CENTER)
	map_container.add_child(teammate_container)

	# ObjectiveArrow
	objective_arrow = Control.new()
	objective_arrow.name = "ObjectiveArrow"
	objective_arrow.set_anchors_preset(Control.PRESET_CENTER)
	objective_arrow.visible = false
	map_container.add_child(objective_arrow)
	objective_arrow.draw.connect(_draw_objective_arrow)

	# PlayerMarker (custom draw triangle)
	player_marker = Control.new()
	player_marker.name = "PlayerMarker"
	player_marker.set_anchors_preset(Control.PRESET_CENTER)
	player_marker.z_index = 10
	map_container.add_child(player_marker)
	player_marker.draw.connect(_draw_player_marker)

	# EdgeIndicatorContainer (outside clip, so edge dots are visible)
	edge_indicator_container = Control.new()
	edge_indicator_container.name = "EdgeIndicators"
	edge_indicator_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(edge_indicator_container)

	# CompassRing
	compass_ring = Control.new()
	compass_ring.name = "CompassRing"
	compass_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	compass_ring.z_index = 5
	add_child(compass_ring)
	compass_ring.draw.connect(_draw_compass)

	# DamageBorder
	damage_border = ColorRect.new()
	damage_border.name = "DamageBorder"
	damage_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_border.color = Color(0.8, 0.0, 0.0, 0.0)
	damage_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_border.z_index = 4
	add_child(damage_border)


# --- Map Geometry Scanning ---

func _scan_map_geometry() -> void:
	var scene := get_tree().current_scene
	if not scene:
		return

	var map_node := scene.get_node_or_null("Map")
	if not map_node:
		return

	# Check if map has any children (geometry loaded)
	if map_node.get_child_count() == 0:
		return

	map_walls.clear()
	map_floors.clear()
	map_pillars.clear()

	# Recursively scan for StaticBody3D nodes with MeshInstance3D children
	_scan_node_recursive(map_node)

	# If we found geometry, compute auto-scale
	if map_walls.size() > 0 or map_floors.size() > 0:
		_compute_auto_scale()
		map_scanned = true


func _scan_node_recursive(node: Node) -> void:
	if node is StaticBody3D:
		_extract_geometry_from_static_body(node)

	for child in node.get_children():
		_scan_node_recursive(child)


func _extract_geometry_from_static_body(body: StaticBody3D) -> void:
	# Find MeshInstance3D child with BoxMesh
	for child in body.get_children():
		if child is MeshInstance3D:
			var mesh_inst: MeshInstance3D = child as MeshInstance3D
			if mesh_inst.mesh is BoxMesh:
				var box: BoxMesh = mesh_inst.mesh as BoxMesh
				var box_size: Vector3 = box.size

				# Get global transform of the mesh instance
				var global_xform: Transform3D = mesh_inst.global_transform

				# Extract the 4 corners in XZ plane (world space)
				var half_x: float = box_size.x / 2.0
				var half_z: float = box_size.z / 2.0

				var corners_local := [
					Vector3(-half_x, 0, -half_z),
					Vector3(half_x, 0, -half_z),
					Vector3(half_x, 0, half_z),
					Vector3(-half_x, 0, half_z),
				]

				var corners_2d := PackedVector2Array()
				for corner: Vector3 in corners_local:
					var world_pos: Vector3 = global_xform * corner
					corners_2d.append(Vector2(world_pos.x, world_pos.z))

				# Classify: wall vs floor vs pillar
				var min_horizontal: float = minf(box_size.x, box_size.z)
				var height: float = box_size.y

				if height < 0.5:
					# Flat = floor or ceiling (skip ceilings based on Y)
					var center_y: float = global_xform.origin.y
					if center_y < 2.0:
						map_floors.append(corners_2d)
				elif min_horizontal <= 1.2 and box_size.x > 1.5 and box_size.z > 1.5:
					# Both horizontal dimensions > 1.5 but one is small = pillar
					map_pillars.append(corners_2d)
				elif min_horizontal <= 0.8:
					# Thin in one dimension = wall
					map_walls.append(corners_2d)
				elif box_size.x <= 1.5 and box_size.z <= 1.5:
					# Small footprint, tall = pillar
					map_pillars.append(corners_2d)
				else:
					# Default: treat as floor if flat-ish, wall otherwise
					if height >= 2.0:
						map_walls.append(corners_2d)
					else:
						map_floors.append(corners_2d)

			break  # Only process first MeshInstance3D


func _compute_auto_scale() -> void:
	# Compute bounding box of all geometry in XZ
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF

	var all_polys: Array = []
	all_polys.append_array(map_walls)
	all_polys.append_array(map_floors)
	all_polys.append_array(map_pillars)

	for poly: PackedVector2Array in all_polys:
		for point: Vector2 in poly:
			min_x = minf(min_x, point.x)
			max_x = maxf(max_x, point.x)
			min_z = minf(min_z, point.y)
			max_z = maxf(max_z, point.y)

	if min_x >= max_x or min_z >= max_z:
		minimap_scale = DEFAULT_MINIMAP_SCALE
		return

	var extent_x: float = max_x - min_x
	var extent_z: float = max_z - min_z
	var max_extent: float = maxf(extent_x, extent_z)

	# Scale so the entire map fits in 80% of the minimap diameter
	minimap_scale = (MINIMAP_RADIUS * 2.0 * 0.75) / max_extent

	# Clamp scale to reasonable range
	minimap_scale = clampf(minimap_scale, 0.5, 8.0)

	# Store map center for reference
	map_center = Vector2((min_x + max_x) / 2.0, (min_z + max_z) / 2.0)


func _draw_map_geometry() -> void:
	if not local_player or not is_instance_valid(local_player):
		return

	if not map_scanned:
		return

	var player_pos := Vector2(local_player.global_position.x, local_player.global_position.z)
	var player_yaw: float = local_player.rotation.y

	# Draw floors first (background)
	for floor_poly: PackedVector2Array in map_floors:
		var transformed := _transform_polygon(floor_poly, player_pos, player_yaw)
		if _polygon_in_radius(transformed):
			geometry_layer.draw_colored_polygon(transformed, FLOOR_COLOR)

	# Draw pillars
	for pillar_poly: PackedVector2Array in map_pillars:
		var transformed := _transform_polygon(pillar_poly, player_pos, player_yaw)
		if _polygon_in_radius(transformed):
			geometry_layer.draw_colored_polygon(transformed, PILLAR_COLOR)

	# Draw walls - inflate thin walls so they're always visible
	for wall_poly: PackedVector2Array in map_walls:
		var transformed := _transform_polygon(wall_poly, player_pos, player_yaw)
		if _polygon_in_radius(transformed):
			var inflated := _inflate_thin_polygon(transformed)
			geometry_layer.draw_colored_polygon(inflated, WALL_COLOR)
			var outline := PackedVector2Array(inflated)
			outline.append(inflated[0])
			geometry_layer.draw_polyline(outline, WALL_OUTLINE_COLOR, 2.5)


func _transform_polygon(world_poly: PackedVector2Array, player_pos: Vector2, player_yaw: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in world_poly:
		var offset: Vector2 = (point - player_pos) * minimap_scale
		var rotated: Vector2 = offset.rotated(-player_yaw)
		result.append(rotated)
	return result


func _polygon_in_radius(poly: PackedVector2Array) -> bool:
	# Check if any corner is within the minimap radius (with margin)
	var check_radius: float = MINIMAP_RADIUS + 20.0
	for point: Vector2 in poly:
		if point.length() <= check_radius:
			return true
	return false


func _inflate_thin_polygon(poly: PackedVector2Array) -> PackedVector2Array:
	# For a 4-corner rectangle, check if either edge pair is too thin
	# and inflate outward to ensure minimum visible width
	if poly.size() != 4:
		return poly

	# Measure the two edge lengths (adjacent edges of the rectangle)
	var edge0_len: float = poly[0].distance_to(poly[1])
	var edge1_len: float = poly[1].distance_to(poly[2])

	# Determine which dimension is thin
	var thin_edge_len := minf(edge0_len, edge1_len)
	if thin_edge_len >= MIN_WALL_PIXEL_WIDTH:
		return poly

	# Compute how much to inflate
	var inflate_amount: float = (MIN_WALL_PIXEL_WIDTH - thin_edge_len) / 2.0

	# Find the thin axis direction (perpendicular to the long edges)
	var thin_dir: Vector2
	if edge0_len <= edge1_len:
		# Edge 0-1 is short, inflate perpendicular to edge 1-2 (the long edge)
		thin_dir = (poly[1] - poly[0]).normalized()
	else:
		# Edge 1-2 is short, inflate perpendicular to edge 0-1 (the long edge)
		thin_dir = (poly[2] - poly[1]).normalized()

	# Push corners outward along the thin direction
	var result := PackedVector2Array()
	var center: Vector2 = (poly[0] + poly[1] + poly[2] + poly[3]) / 4.0
	for point: Vector2 in poly:
		var from_center: float = (point - center).dot(thin_dir)
		var push: Vector2 = thin_dir * sign(from_center) * inflate_amount
		result.append(point + push)

	return result


# --- Zombie Radar ---

func _create_zombie_dot_pool() -> void:
	for i in MAX_ZOMBIE_DOTS:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(ZOMBIE_DOT_SIZE, ZOMBIE_DOT_SIZE)
		dot.size = Vector2(ZOMBIE_DOT_SIZE, ZOMBIE_DOT_SIZE)
		dot.color = Color(1.0, 0.2, 0.2)
		dot.visible = false
		zombie_container.add_child(dot)
		zombie_dots.append(dot)


func _update_zombie_dots() -> void:
	var player_pos := Vector2(local_player.global_position.x, local_player.global_position.z)
	var player_yaw: float = local_player.rotation.y

	# Get all zombies and sort by distance
	var zombies_node := get_tree().current_scene.get_node_or_null("Zombies")
	if not zombies_node:
		for dot in zombie_dots:
			dot.visible = false
		return

	var zombie_data: Array[Dictionary] = []
	for zombie: Node in zombies_node.get_children():
		if not is_instance_valid(zombie):
			continue
		var zpos := Vector2(zombie.global_position.x, zombie.global_position.z)
		var dist: float = player_pos.distance_to(zpos)
		zombie_data.append({"pos": zpos, "dist": dist})

	# Sort by distance (nearest first)
	zombie_data.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))

	# Update dots
	for i in MAX_ZOMBIE_DOTS:
		if i < zombie_data.size():
			var zd: Dictionary = zombie_data[i]
			var zd_pos: Vector2 = zd["pos"]
			var zd_dist: float = zd["dist"]
			var offset: Vector2 = (zd_pos - player_pos) * minimap_scale
			# Rotate by -player_yaw for north-up
			var rotated: Vector2 = offset.rotated(-player_yaw)

			# Check if within minimap radius
			if rotated.length() <= MINIMAP_RADIUS:
				zombie_dots[i].position = rotated - Vector2(ZOMBIE_DOT_SIZE / 2.0, ZOMBIE_DOT_SIZE / 2.0)
				# Fade alpha by distance (closer = brighter)
				var alpha := clampf(1.0 - (zd_dist / 30.0), 0.3, 1.0)
				zombie_dots[i].color = Color(1.0, 0.2, 0.2, alpha)
				zombie_dots[i].visible = true
			else:
				zombie_dots[i].visible = false
		else:
			zombie_dots[i].visible = false


# --- Compass Ring ---

func _draw_compass() -> void:
	if not local_player:
		return

	var center := compass_ring.size / 2.0
	var radius := center.x - 2.0
	var player_yaw: float = local_player.rotation.y

	# Cardinal directions
	var directions := [
		{"label": "N", "angle": 0.0, "color": Color.RED},
		{"label": "E", "angle": PI / 2.0, "color": Color.WHITE},
		{"label": "S", "angle": PI, "color": Color.WHITE},
		{"label": "W", "angle": -PI / 2.0, "color": Color.WHITE},
	]

	var font := ThemeDB.fallback_font
	var font_size := 14

	for dir: Dictionary in directions:
		var angle: float = float(dir["angle"]) - player_yaw - PI / 2.0
		var pos := center + Vector2(cos(angle), sin(angle)) * (radius - 4.0)
		var label_text: String = dir["label"]
		var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var draw_color: Color = dir["color"]
		compass_ring.draw_string(font, pos - text_size / 2.0 + Vector2(0, text_size.y / 2.0), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, draw_color)


# --- Smart POI System ---

func _refresh_pois() -> void:
	# Clean up stale entries
	var valid_entries: Array[Dictionary] = []
	for entry: Dictionary in poi_entries:
		if is_instance_valid(entry["node"]):
			valid_entries.append(entry)
		else:
			if is_instance_valid(entry["marker"]):
				entry["marker"].queue_free()
			if entry.has("edge_dot") and is_instance_valid(entry["edge_dot"]):
				entry["edge_dot"].queue_free()
	poi_entries = valid_entries

	# Scan for new interactables
	var interactables := get_tree().get_nodes_in_group("interactables")
	var tracked_nodes: Array[Node] = []
	for entry: Dictionary in poi_entries:
		tracked_nodes.append(entry["node"])

	for node: Node in interactables:
		if node in tracked_nodes:
			continue
		_add_poi(node)

	# Update state of existing POIs
	for entry: Dictionary in poi_entries:
		_update_poi_state(entry)


func _add_poi(node: Node) -> void:
	var poi_type := _classify_poi(node)
	var color := _get_poi_color(node, poi_type)

	# On-map marker (dot + label)
	var marker := Control.new()
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(POI_DOT_SIZE, POI_DOT_SIZE)
	dot.size = Vector2(POI_DOT_SIZE, POI_DOT_SIZE)
	dot.position = Vector2(-POI_DOT_SIZE / 2.0, -POI_DOT_SIZE / 2.0)
	dot.color = color
	dot.name = "Dot"
	marker.add_child(dot)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 2)
	label.position = Vector2(POI_DOT_SIZE / 2.0 + 2.0, -7.0)
	label.text = _get_poi_label(node, poi_type)
	label.modulate = color
	label.name = "Label"
	marker.add_child(label)

	poi_container.add_child(marker)

	var entry: Dictionary = {
		"node": node,
		"marker": marker,
		"type": poi_type,
	}

	# Every POI gets an off-screen edge indicator (colored dot + distance)
	var is_important: bool = poi_type in IMPORTANT_POI_TYPES
	var edge_dot_size := 8.0 if is_important else 5.0

	var edge_ctrl := Control.new()
	edge_ctrl.visible = false
	edge_ctrl.z_index = 3 if is_important else 1
	edge_indicator_container.add_child(edge_ctrl)

	# Draw a colored dot at the edge
	var edge_dot_rect := ColorRect.new()
	edge_dot_rect.custom_minimum_size = Vector2(edge_dot_size, edge_dot_size)
	edge_dot_rect.size = Vector2(edge_dot_size, edge_dot_size)
	edge_dot_rect.position = Vector2(-edge_dot_size / 2.0, -edge_dot_size / 2.0)
	edge_dot_rect.color = color
	edge_dot_rect.name = "EdgeDotRect"
	edge_ctrl.add_child(edge_dot_rect)

	# Distance label for important POIs
	var edge_label := Label.new()
	edge_label.add_theme_font_size_override("font_size", 11)
	edge_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	edge_label.add_theme_constant_override("outline_size", 2)
	edge_label.modulate = color
	edge_label.name = "DistLabel"
	edge_label.visible = is_important
	edge_ctrl.add_child(edge_label)

	entry["edge_dot"] = edge_ctrl
	entry["edge_label"] = edge_label
	entry["is_important"] = is_important

	poi_entries.append(entry)


func _update_poi_state(entry: Dictionary) -> void:
	var node: Node = entry["node"]
	var marker: Control = entry["marker"]
	var poi_type: String = entry["type"]
	var dot: ColorRect = marker.get_node("Dot")

	if not is_instance_valid(node) or not is_instance_valid(marker):
		return

	# Door state: hide if opened
	if poi_type == "door":
		var is_open: bool = node.get("is_open") if node.get("is_open") != null else false
		if is_open:
			marker.visible = false
			if entry.has("edge_dot") and is_instance_valid(entry["edge_dot"]):
				entry["edge_dot"].visible = false
			entry["hidden"] = true
		else:
			entry["hidden"] = false
		return

	# Power-dependent dimming
	var needs_power: bool = node.is_in_group("power_dependent")
	if needs_power and not GameManager.power_is_on:
		dot.color.a = 0.3
		marker.get_node("Label").modulate.a = 0.3
	else:
		var base_color := _get_poi_color(node, poi_type)
		dot.color = base_color
		marker.get_node("Label").modulate = base_color

	# Proximity pulse
	if local_player and is_instance_valid(local_player):
		var dist: float = local_player.global_position.distance_to(node.global_position)
		if dist < 3.0:
			var pulse := 0.7 + sin(Time.get_ticks_msec() / 200.0) * 0.3
			dot.color.a = pulse
		elif needs_power and not GameManager.power_is_on:
			dot.color.a = 0.3


func _update_poi_positions() -> void:
	if not local_player:
		return

	var player_pos := Vector2(local_player.global_position.x, local_player.global_position.z)
	var player_yaw: float = local_player.rotation.y
	var minimap_center := size / 2.0

	for entry: Dictionary in poi_entries:
		if not is_instance_valid(entry["node"]) or not is_instance_valid(entry["marker"]):
			continue

		# Skip hidden entries (opened doors)
		if entry.get("hidden", false):
			continue

		var marker: Control = entry["marker"]
		var node: Node = entry["node"]
		var poi_pos := Vector2(node.global_position.x, node.global_position.z)
		var offset: Vector2 = (poi_pos - player_pos) * minimap_scale
		var rotated: Vector2 = offset.rotated(-player_yaw)
		var dist_on_map: float = rotated.length()

		if dist_on_map <= MINIMAP_RADIUS:
			# On-map: show marker, hide edge dot
			marker.position = rotated
			marker.visible = true
			if entry.has("edge_dot") and is_instance_valid(entry["edge_dot"]):
				entry["edge_dot"].visible = false
		else:
			# Off-screen: hide marker, show edge dot pinned to minimap edge
			marker.visible = false
			if entry.has("edge_dot") and is_instance_valid(entry["edge_dot"]):
				var dir: Vector2 = rotated.normalized()
				var edge_pos: Vector2 = dir * (MINIMAP_RADIUS - EDGE_ARROW_MARGIN) + minimap_center
				entry["edge_dot"].position = edge_pos
				entry["edge_dot"].visible = true

				# Update distance text for important POIs
				if entry.get("is_important", false) and entry.has("edge_label") and is_instance_valid(entry["edge_label"]):
					var world_dist: float = player_pos.distance_to(poi_pos)
					entry["edge_label"].text = "%dm" % int(world_dist)
					entry["edge_label"].position = Vector2(6, -14)


func _classify_poi(node: Node) -> String:
	var node_name := node.name.to_lower()
	if "perk" in node_name:
		return "perk"
	elif "shop" in node_name:
		return "shop"
	elif "mystery" in node_name or "box" in node_name:
		return "mystery_box"
	elif "power" in node_name and "up" not in node_name:
		return "power"
	elif "packapunch" in node_name or "pack_a_punch" in node_name or "pap" in node_name:
		return "pack_a_punch"
	elif "door" in node_name or "debris" in node_name:
		return "door"
	elif "weapon" in node_name or "wall" in node_name:
		return "wall_weapon"
	return "generic"


func _get_poi_color(node: Node, poi_type: String) -> Color:
	match poi_type:
		"perk":
			var perk_name_str: String = node.get("perk_name") if node.get("perk_name") else "perk"
			return PERK_COLORS.get(perk_name_str, Color(0.8, 0.3, 0.8))
		"shop":
			return Color(0.3, 0.8, 1.0)
		"mystery_box":
			return Color(1.0, 0.8, 0.2)
		"power":
			return Color(1.0, 1.0, 0.3)
		"pack_a_punch":
			return Color(0.9, 0.4, 1.0)
		"door":
			return Color(1.0, 0.3, 0.3)
		"wall_weapon":
			return Color(0.7, 0.7, 0.7)
	return Color(0.5, 0.5, 0.5)


func _get_poi_label(node: Node, poi_type: String) -> String:
	match poi_type:
		"perk":
			var perk_name_str: String = node.get("perk_name") if node.get("perk_name") else ""
			var short_names := {
				"juggernog": "Jug", "speed_cola": "Speed", "double_tap": "DblTap",
				"quick_revive": "Revive", "stamin_up": "Stam", "phd_flopper": "PhD",
				"deadshot": "Dead", "mule_kick": "Mule", "spring_heels": "Spring"
			}
			return short_names.get(perk_name_str, perk_name_str.substr(0, 4))
		"shop":
			return "Shop"
		"mystery_box":
			return "Box"
		"power":
			return "Power"
		"pack_a_punch":
			return "PaP"
		"door":
			return ""
		"wall_weapon":
			return "Gun"
	return ""


# --- Teammate Markers ---

func _update_teammate_markers() -> void:
	if not local_player:
		return

	var players_node := get_tree().current_scene.get_node_or_null("Players")
	if not players_node:
		return

	var player_pos := Vector2(local_player.global_position.x, local_player.global_position.z)
	var player_yaw: float = local_player.rotation.y
	var color_index := 0

	# Track which IDs are still valid
	var valid_ids: Array[int] = []

	for player: Node in players_node.get_children():
		if player == local_player:
			continue

		var pid: int = player.get("player_id")
		if pid == 0:
			continue
		valid_ids.append(pid)

		if pid not in teammate_markers:
			# Create new marker
			var marker := Control.new()
			marker.z_index = 8
			teammate_container.add_child(marker)
			var tm_color := TEAMMATE_COLORS[color_index % TEAMMATE_COLORS.size()]
			marker.draw.connect(_draw_teammate_arrow.bind(marker, tm_color))

			var name_label := Label.new()
			name_label.add_theme_font_size_override("font_size", 8)
			name_label.text = player.get("player_name") if player.get("player_name") else "P%d" % pid
			name_label.modulate = tm_color
			name_label.position = Vector2(6, -6)
			marker.add_child(name_label)

			teammate_markers[pid] = {"marker": marker, "label": name_label, "color": tm_color}

		# Update position
		var tm_pos := Vector2(player.global_position.x, player.global_position.z)
		var offset: Vector2 = (tm_pos - player_pos) * minimap_scale
		var rotated: Vector2 = offset.rotated(-player_yaw)

		if rotated.length() <= MINIMAP_RADIUS:
			var tm_data: Dictionary = teammate_markers[pid]
			tm_data["marker"].position = rotated
			tm_data["marker"].rotation = -player.rotation.y + player_yaw
			tm_data["marker"].visible = true
			tm_data["marker"].queue_redraw()
		else:
			teammate_markers[pid]["marker"].visible = false

		color_index += 1

	# Clean up disconnected players
	var to_remove: Array[int] = []
	for pid: int in teammate_markers:
		if pid not in valid_ids:
			to_remove.append(pid)
	for pid: int in to_remove:
		if is_instance_valid(teammate_markers[pid]["marker"]):
			teammate_markers[pid]["marker"].queue_free()
		teammate_markers.erase(pid)


func _draw_teammate_arrow(ctrl: Control, color: Color) -> void:
	var points := PackedVector2Array([
		Vector2(0, -5),
		Vector2(-4, 4),
		Vector2(4, 4),
	])
	ctrl.draw_colored_polygon(points, color)


# --- Player Marker ---

func _draw_player_marker() -> void:
	# Directional triangle pointing up (forward) - larger for visibility
	var points := PackedVector2Array([
		Vector2(0, -8),
		Vector2(-6, 6),
		Vector2(6, 6),
	])
	player_marker.draw_colored_polygon(points, Color(0.3, 0.9, 1.0))
	# White outline
	var outline := PackedVector2Array([
		Vector2(0, -8),
		Vector2(-6, 6),
		Vector2(6, 6),
		Vector2(0, -8),
	])
	player_marker.draw_polyline(outline, Color(1, 1, 1, 0.8), 1.5)


# --- Objective Arrow ---

func _update_objective_arrow() -> void:
	if not objective_target or not is_instance_valid(objective_target) or not local_player:
		objective_arrow.visible = false
		return

	var player_pos := Vector2(local_player.global_position.x, local_player.global_position.z)
	var target_pos := Vector2(objective_target.global_position.x, objective_target.global_position.z)
	var player_yaw: float = local_player.rotation.y
	var offset: Vector2 = (target_pos - player_pos) * minimap_scale
	var rotated: Vector2 = offset.rotated(-player_yaw)

	# Show arrow at edge of minimap pointing toward objective
	var dir: Vector2 = rotated.normalized()
	var arrow_dist := minf(rotated.length(), MINIMAP_RADIUS - 12.0)
	objective_arrow.position = dir * arrow_dist
	objective_arrow.rotation = dir.angle() + PI / 2.0
	objective_arrow.visible = true
	objective_arrow.queue_redraw()


func _draw_objective_arrow() -> void:
	# Golden arrow
	var points := PackedVector2Array([
		Vector2(0, -8),
		Vector2(-5, 4),
		Vector2(5, 4),
	])
	# Pulse golden color
	var pulse := 0.8 + sin(Time.get_ticks_msec() / 300.0) * 0.2
	objective_arrow.draw_colored_polygon(points, Color(1.0, 0.85, 0.2, pulse))


# --- Damage Border ---

func _on_damage_intensity_changed(intensity: float) -> void:
	damage_intensity = intensity


func _update_damage_border(_delta: float) -> void:
	if damage_border:
		damage_border.color.a = damage_intensity * 0.4
