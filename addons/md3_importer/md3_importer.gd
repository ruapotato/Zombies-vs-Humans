@tool
extends EditorPlugin
## MD3 Model Importer - Imports Quake 3 / Tremulous MD3 format models

var import_plugin: MD3ImportPlugin


func _enter_tree() -> void:
	import_plugin = MD3ImportPlugin.new()
	add_import_plugin(import_plugin)


func _exit_tree() -> void:
	remove_import_plugin(import_plugin)
	import_plugin = null


class MD3ImportPlugin extends EditorImportPlugin:
	func _get_importer_name() -> String:
		return "md3_importer"

	func _get_visible_name() -> String:
		return "MD3 Model"

	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(["md3"])

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
			push_error("Cannot open MD3 file: %s" % source_file)
			return ERR_FILE_CANT_OPEN

		# Read MD3 header
		var magic := file.get_buffer(4).get_string_from_ascii()
		if magic != "IDP3":
			push_error("Invalid MD3 file (magic: %s)" % magic)
			return ERR_FILE_CORRUPT

		var version := file.get_32()
		if version != 15:
			push_warning("MD3 version %d may not be fully supported" % version)

		var name := _read_string(file, 64)
		var flags := file.get_32()
		var num_frames := file.get_32()
		var num_tags := file.get_32()
		var num_surfaces := file.get_32()
		var num_skins := file.get_32()
		var ofs_frames := file.get_32()
		var ofs_tags := file.get_32()
		var ofs_surfaces := file.get_32()
		var ofs_eof := file.get_32()

		# Create root node
		var root := Node3D.new()
		root.name = source_file.get_file().get_basename()

		var scale: float = options.get("scale", 0.03)

		# Read surfaces (meshes)
		file.seek(ofs_surfaces)

		for i in range(num_surfaces):
			var surface := _read_surface(file, scale)
			if surface:
				root.add_child(surface)
				surface.owner = root

		file.close()

		# Generate collision if requested
		if options.get("generate_collision", true):
			for child in root.get_children():
				if child is MeshInstance3D:
					child.create_trimesh_collision()
					for collision_child in child.get_children():
						collision_child.owner = root

		# Save as PackedScene
		var scene := PackedScene.new()
		scene.pack(root)

		var save_file := "%s.%s" % [save_path, _get_save_extension()]
		return ResourceSaver.save(scene, save_file)

	func _read_string(file: FileAccess, length: int) -> String:
		var buffer := file.get_buffer(length)
		var end := buffer.find(0)
		if end >= 0:
			buffer = buffer.slice(0, end)
		return buffer.get_string_from_ascii()

	func _read_surface(file: FileAccess, scale: float) -> MeshInstance3D:
		var start_pos := file.get_position()

		var magic := file.get_buffer(4).get_string_from_ascii()
		if magic != "IDP3":
			push_error("Invalid surface magic: %s" % magic)
			return null

		var name := _read_string(file, 64)
		var flags := file.get_32()
		var num_frames := file.get_32()
		var num_shaders := file.get_32()
		var num_verts := file.get_32()
		var num_triangles := file.get_32()
		var ofs_triangles := file.get_32()
		var ofs_shaders := file.get_32()
		var ofs_st := file.get_32()
		var ofs_xyznormal := file.get_32()
		var ofs_end := file.get_32()

		# Read shaders (for texture reference)
		file.seek(start_pos + ofs_shaders)
		var shader_name := ""
		if num_shaders > 0:
			shader_name = _read_string(file, 64)
			var _shader_index := file.get_32()

		# Read triangles (indices)
		file.seek(start_pos + ofs_triangles)
		var indices := PackedInt32Array()
		for t in range(num_triangles):
			indices.append(file.get_32())
			indices.append(file.get_32())
			indices.append(file.get_32())

		# Read texture coordinates
		file.seek(start_pos + ofs_st)
		var uvs := PackedVector2Array()
		for v in range(num_verts):
			var s := file.get_float()
			var t := file.get_float()
			uvs.append(Vector2(s, 1.0 - t))  # Flip V coordinate

		# Read vertices (first frame only)
		file.seek(start_pos + ofs_xyznormal)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()

		for v in range(num_verts):
			var x := file.get_16() * scale / 64.0
			var y := file.get_16() * scale / 64.0
			var z := file.get_16() * scale / 64.0

			# Convert from Quake coordinate system
			vertices.append(Vector3(x, z, -y))

			# Decode normal from latitude/longitude
			var lat := file.get_8()
			var lng := file.get_8()
			var lat_rad := lat * (2.0 * PI / 255.0)
			var lng_rad := lng * (2.0 * PI / 255.0)
			var nx := cos(lat_rad) * sin(lng_rad)
			var ny := sin(lat_rad) * sin(lng_rad)
			var nz := cos(lng_rad)
			normals.append(Vector3(nx, nz, -ny).normalized())

		# Create mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices

		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		# Create material
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.6, 0.6, 0.6)

		# Try to load texture
		if shader_name != "":
			var texture_paths := [
				"res://assets/tremulous/textures/%s.png" % shader_name,
				"res://assets/tremulous/textures/%s.jpg" % shader_name,
				"res://assets/tremulous/textures/%s.tga" % shader_name
			]
			for tex_path in texture_paths:
				if ResourceLoader.exists(tex_path):
					material.albedo_texture = load(tex_path)
					break

		mesh.surface_set_material(0, material)

		# Create MeshInstance3D
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = name if name != "" else "Surface"
		mesh_instance.mesh = mesh

		# Move to end of surface
		file.seek(start_pos + ofs_end)

		return mesh_instance
