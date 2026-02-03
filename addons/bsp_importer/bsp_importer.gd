@tool
extends EditorPlugin
## BSP Map Importer - Imports Quake 3 / Tremulous BSP format maps

var import_plugin: BSPImportPlugin


func _enter_tree() -> void:
	import_plugin = BSPImportPlugin.new()
	add_import_plugin(import_plugin)


func _exit_tree() -> void:
	remove_import_plugin(import_plugin)
	import_plugin = null


class BSPImportPlugin extends EditorImportPlugin:
	# BSP lumps
	const LUMP_ENTITIES := 0
	const LUMP_TEXTURES := 1
	const LUMP_PLANES := 2
	const LUMP_NODES := 3
	const LUMP_LEAFS := 4
	const LUMP_LEAFFACES := 5
	const LUMP_LEAFBRUSHES := 6
	const LUMP_MODELS := 7
	const LUMP_BRUSHES := 8
	const LUMP_BRUSHSIDES := 9
	const LUMP_VERTEXES := 10
	const LUMP_MESHVERTS := 11
	const LUMP_EFFECTS := 12
	const LUMP_FACES := 13
	const LUMP_LIGHTMAPS := 14
	const LUMP_LIGHTVOLS := 15
	const LUMP_VISDATA := 16

	func _get_importer_name() -> String:
		return "bsp_importer"

	func _get_visible_name() -> String:
		return "BSP Map"

	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(["bsp"])

	func _get_save_extension() -> String:
		return "scn"

	func _get_resource_type() -> String:
		return "PackedScene"

	func _get_preset_count() -> int:
		return 1

	func _get_preset_name(preset_index: int) -> String:
		return "Default"

	func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
		return [
			{
				"name": "scale",
				"default_value": 0.03,
				"property_hint": PROPERTY_HINT_RANGE,
				"hint_string": "0.001,1.0,0.001"
			},
			{
				"name": "generate_collision",
				"default_value": true
			},
			{
				"name": "generate_navigation",
				"default_value": true
			}
		]

	func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
		return true

	func _get_import_order() -> int:
		return 0

	func _get_priority() -> float:
		return 1.0

	func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
		var file := FileAccess.open(source_file, FileAccess.READ)
		if not file:
			push_error("Cannot open BSP file: %s" % source_file)
			return ERR_FILE_CANT_OPEN

		# Read BSP header
		var magic := file.get_buffer(4).get_string_from_ascii()
		if magic != "IBSP":
			push_error("Invalid BSP file (magic: %s)" % magic)
			return ERR_FILE_CORRUPT

		var version := file.get_32()
		if version != 46:  # Quake 3 BSP version
			push_warning("BSP version %d may not be fully supported" % version)

		# Read directory entries (lumps)
		var lumps := []
		for i in range(17):
			var offset := file.get_32()
			var length := file.get_32()
			lumps.append({"offset": offset, "length": length})

		var scale: float = options.get("scale", 0.03)

		# Create root node
		var root := Node3D.new()
		root.name = source_file.get_file().get_basename()

		# Read vertices
		var vertices := _read_vertices(file, lumps[LUMP_VERTEXES], scale)

		# Read mesh vertices (indices)
		var mesh_verts := _read_mesh_verts(file, lumps[LUMP_MESHVERTS])

		# Read textures
		var textures := _read_textures(file, lumps[LUMP_TEXTURES])

		# Read faces
		var faces := _read_faces(file, lumps[LUMP_FACES])

		file.close()

		# Build mesh from faces
		var map_mesh := _build_mesh(vertices, mesh_verts, faces, textures)
		if map_mesh:
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.name = "MapGeometry"
			mesh_instance.mesh = map_mesh
			root.add_child(mesh_instance)
			mesh_instance.owner = root

			# Generate collision
			if options.get("generate_collision", true):
				mesh_instance.create_trimesh_collision()
				for child in mesh_instance.get_children():
					child.owner = root

		# Generate navigation mesh
		if options.get("generate_navigation", true):
			var nav_region := NavigationRegion3D.new()
			nav_region.name = "NavigationRegion3D"
			root.add_child(nav_region)
			nav_region.owner = root

			# Create nav mesh from geometry
			var nav_mesh := NavigationMesh.new()
			nav_mesh.agent_radius = 0.5
			nav_mesh.agent_height = 1.8
			nav_mesh.cell_size = 0.25
			nav_mesh.cell_height = 0.25
			nav_region.navigation_mesh = nav_mesh

		# Save as PackedScene
		var scene := PackedScene.new()
		scene.pack(root)

		var save_file := "%s.%s" % [save_path, _get_save_extension()]
		return ResourceSaver.save(scene, save_file)

	func _read_vertices(file: FileAccess, lump: Dictionary, scale: float) -> Array:
		var vertices := []
		file.seek(lump.offset)

		var count := lump.length / 44  # Vertex struct size

		for i in range(count):
			var pos_x := file.get_float() * scale
			var pos_y := file.get_float() * scale
			var pos_z := file.get_float() * scale

			var tex_s := file.get_float()
			var tex_t := file.get_float()
			var lm_s := file.get_float()
			var lm_t := file.get_float()

			var norm_x := file.get_float()
			var norm_y := file.get_float()
			var norm_z := file.get_float()

			var color := file.get_buffer(4)

			# Convert from Quake coordinate system
			vertices.append({
				"position": Vector3(pos_x, pos_z, -pos_y),
				"uv": Vector2(tex_s, tex_t),
				"normal": Vector3(norm_x, norm_z, -norm_y).normalized()
			})

		return vertices

	func _read_mesh_verts(file: FileAccess, lump: Dictionary) -> PackedInt32Array:
		var mesh_verts := PackedInt32Array()
		file.seek(lump.offset)

		var count := lump.length / 4

		for i in range(count):
			mesh_verts.append(file.get_32())

		return mesh_verts

	func _read_textures(file: FileAccess, lump: Dictionary) -> Array:
		var textures := []
		file.seek(lump.offset)

		var count := lump.length / 72  # Texture struct size

		for i in range(count):
			var name := ""
			var name_buffer := file.get_buffer(64)
			var end := name_buffer.find(0)
			if end >= 0:
				name_buffer = name_buffer.slice(0, end)
			name = name_buffer.get_string_from_ascii()

			var flags := file.get_32()
			var contents := file.get_32()

			textures.append({
				"name": name,
				"flags": flags,
				"contents": contents
			})

		return textures

	func _read_faces(file: FileAccess, lump: Dictionary) -> Array:
		var faces := []
		file.seek(lump.offset)

		var count := lump.length / 104  # Face struct size

		for i in range(count):
			var texture := file.get_32()
			var effect := file.get_32()
			var face_type := file.get_32()
			var vertex := file.get_32()
			var n_vertexes := file.get_32()
			var meshvert := file.get_32()
			var n_meshverts := file.get_32()
			var lm_index := file.get_32()
			var lm_start := [file.get_32(), file.get_32()]
			var lm_size := [file.get_32(), file.get_32()]
			var lm_origin := Vector3(file.get_float(), file.get_float(), file.get_float())
			var lm_vecs := [
				Vector3(file.get_float(), file.get_float(), file.get_float()),
				Vector3(file.get_float(), file.get_float(), file.get_float())
			]
			var normal := Vector3(file.get_float(), file.get_float(), file.get_float())
			var size := [file.get_32(), file.get_32()]

			faces.append({
				"texture": texture,
				"type": face_type,
				"vertex": vertex,
				"n_vertexes": n_vertexes,
				"meshvert": meshvert,
				"n_meshverts": n_meshverts
			})

		return faces

	func _build_mesh(vertices: Array, mesh_verts: PackedInt32Array, faces: Array, textures: Array) -> ArrayMesh:
		# Group faces by texture for separate surfaces
		var surfaces := {}

		for face in faces:
			# Only process polygon/mesh faces (type 1 and 3)
			if face.type != 1 and face.type != 3:
				continue

			var tex_idx: int = face.texture
			if tex_idx not in surfaces:
				surfaces[tex_idx] = {
					"vertices": PackedVector3Array(),
					"normals": PackedVector3Array(),
					"uvs": PackedVector2Array(),
					"indices": PackedInt32Array()
				}

			var surface: Dictionary = surfaces[tex_idx]
			var base_vertex := surface.vertices.size()

			# Add vertices
			for v in range(face.n_vertexes):
				var vert_idx: int = face.vertex + v
				if vert_idx < vertices.size():
					var vert: Dictionary = vertices[vert_idx]
					surface.vertices.append(vert.position)
					surface.normals.append(vert.normal)
					surface.uvs.append(vert.uv)

			# Add indices
			for m in range(face.n_meshverts):
				var mv_idx: int = face.meshvert + m
				if mv_idx < mesh_verts.size():
					surface.indices.append(base_vertex + mesh_verts[mv_idx])

		if surfaces.is_empty():
			return null

		var mesh := ArrayMesh.new()

		for tex_idx in surfaces:
			var surface: Dictionary = surfaces[tex_idx]

			if surface.vertices.is_empty():
				continue

			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = surface.vertices
			arrays[Mesh.ARRAY_NORMAL] = surface.normals
			arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
			arrays[Mesh.ARRAY_INDEX] = surface.indices

			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

			# Create material
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.7, 0.7, 0.7)

			if tex_idx < textures.size():
				var tex_name: String = textures[tex_idx].name

				# Try to load texture
				var texture_paths := [
					"res://assets/tremulous/textures/%s.png" % tex_name,
					"res://assets/tremulous/textures/%s.jpg" % tex_name,
					"res://assets/tremulous/textures/%s.tga" % tex_name
				]

				for tex_path in texture_paths:
					if ResourceLoader.exists(tex_path):
						material.albedo_texture = load(tex_path)
						break

			mesh.surface_set_material(mesh.get_surface_count() - 1, material)

		return mesh
