@tool

## SpriteForge slice extractor.
## Exports PNG slices, AtlasTextures, Shader scenes and SpriteFrames.
## Key optimisation: actual_tex (load from disk) resolved once before any loop.

static func extract(
	texture: Texture2D,
	rects: Array[Rect2],
	export_png: bool,
	export_atlas: bool,
	export_spriteframes: bool,
	tex_path: String = "",
	names: Array[String] = [],
	anim_name: String = "default",
	slice_materials: Array[String] = [],
	custom_folder: String = "",
	custom_base: String = "",
	use_subfolder: bool = true,
	auto_unique_names: bool = true
) -> void:
	# --- Path setup ---
	var src_path: String = tex_path if tex_path != "" else texture.resource_path
	var base_path: String = src_path.get_base_dir()
	if base_path == "":
		base_path = "res://"
	var base_name: String = src_path.get_file().get_basename()
	if base_name == "":
		base_name = "slice"

	var out_dir: String = base_path
	if use_subfolder:
		var folder_name: String = custom_folder.strip_edges()
		if folder_name == "":
			folder_name = base_name + "_slices"
		out_dir = base_path + "/" + folder_name
		var dir := DirAccess.open(base_path)
		if dir and not dir.dir_exists(folder_name):
			dir.make_dir(folder_name)

	var file_base: String = custom_base.strip_edges()
	if file_base == "":
		file_base = base_name

	var img: Image = texture.get_image()
	if img == null or img.is_empty():
		push_error("SpriteSlicer: Source image is null or empty.")
		return

	# Resolve actual_tex ONCE — avoids calling load() N times per slice
	var actual_tex: Texture2D = _resolve_texture(texture, src_path)

	# --- Per-slice exports ---
	for i in range(rects.size()):
		var r: Rect2 = rects[i]

		# Determine file name (custom name or auto index)
		var file_name: String = file_base + "_" + str(i)
		if i < names.size():
			var stripped: String = names[i].strip_edges()
			if stripped != "":
				file_name = stripped

		if export_png:
			_export_png(img, r, out_dir, file_name, auto_unique_names)

		if export_atlas:
			_export_atlas(actual_tex, r, out_dir, file_name, auto_unique_names)

		# Scene with shader/material
		if i < slice_materials.size() and slice_materials[i] != "":
			_export_scene(actual_tex, r, slice_materials[i], out_dir, file_name, auto_unique_names)

	# --- SpriteFrames export ---
	if export_spriteframes:
		_export_spriteframes(actual_tex, rects, anim_name, out_dir, file_base, auto_unique_names)

	# Trigger editor filesystem rescan
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.scan()

# ---------------------------------------------------------------------------
# Sub-exporters
# ---------------------------------------------------------------------------

static func _export_png(img: Image, r: Rect2, out_dir: String, file_name: String, auto_unique: bool) -> void:
	var region: Image = img.get_region(Rect2i(r))
	var save_path: String = out_dir + "/" + file_name + ".png"
	if auto_unique:
		save_path = _get_unique_path(out_dir, file_name, "png")
	var abs_save: String = ProjectSettings.globalize_path(save_path)
	var err: int = region.save_png(abs_save)
	if err != OK:
		push_error("SpriteSlicer: Could not save PNG: %s (error %d)" % [abs_save, err])
	else:
		print("Saved PNG: ", save_path)

static func _export_atlas(actual_tex: Texture2D, r: Rect2, out_dir: String, file_name: String, auto_unique: bool) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = actual_tex
	atlas.region = r
	var save_path: String = out_dir + "/" + file_name + ".tres"
	if auto_unique:
		save_path = _get_unique_path(out_dir, file_name, "tres")
	var err: int = ResourceSaver.save(atlas, save_path)
	if err != OK:
		push_error("SpriteSlicer: Could not save AtlasTexture: %s (error %d)" % [save_path, err])
	else:
		print("Saved AtlasTexture: ", save_path)

static func _export_scene(actual_tex: Texture2D, r: Rect2, mat_path: String, out_dir: String, file_name: String, auto_unique: bool) -> void:
	var loaded_mat: Resource = load(mat_path)
	if not loaded_mat:
		return
	var sprite := Sprite2D.new()
	sprite.name = file_name
	sprite.texture = actual_tex
	sprite.region_enabled = true
	sprite.region_rect = r
	sprite.material = loaded_mat as Material

	var packed_scene := PackedScene.new()
	var pack_err: int = packed_scene.pack(sprite)
	if pack_err == OK:
		var scene_path: String = out_dir + "/" + file_name + ".tscn"
		if auto_unique:
			scene_path = _get_unique_path(out_dir, file_name, "tscn")
		var save_err: int = ResourceSaver.save(packed_scene, scene_path)
		if save_err != OK:
			push_error("SpriteSlicer: Could not save TSCN scene: %s (error %d)" % [scene_path, save_err])
		else:
			print("Saved Shader Scene: ", scene_path)
	else:
		push_error("SpriteSlicer: Could not pack Sprite2D node (error %d)" % pack_err)

	# Node was never added to scene tree — use free() for immediate deallocation
	sprite.free()

static func _export_spriteframes(actual_tex: Texture2D, rects: Array[Rect2], anim_name: String, out_dir: String, file_base: String, auto_unique: bool) -> void:
	var sf := SpriteFrames.new()
	var a_name: String = anim_name.strip_edges()
	if a_name == "":
		a_name = "default"

	if sf.has_animation("default") and a_name != "default":
		sf.remove_animation("default")
	if not sf.has_animation(a_name):
		sf.add_animation(a_name)
	sf.set_animation_speed(a_name, 8.0)
	sf.set_animation_loop(a_name, true)

	for r in rects:
		var atlas := AtlasTexture.new()
		atlas.atlas = actual_tex
		atlas.region = r
		sf.add_frame(a_name, atlas)

	var sf_save_path: String = out_dir + "/" + file_base + "_animation.tres"
	if auto_unique:
		sf_save_path = _get_unique_path(out_dir, file_base + "_animation", "tres")
	var err: int = ResourceSaver.save(sf, sf_save_path)
	if err != OK:
		push_error("SpriteSlicer: Could not save SpriteFrames: %s (error %d)" % [sf_save_path, err])
	else:
		print("Saved SpriteFrames: ", sf_save_path)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Resolves the canonical Texture2D for the source path.
## If texture is a transient ImageTexture and src_path is valid, loads from disk
## to get a proper resource reference (needed for AtlasTexture.atlas).
static func _resolve_texture(texture: Texture2D, src_path: String) -> Texture2D:
	if texture is ImageTexture and src_path != "":
		var loaded: Resource = load(src_path)
		if loaded is Texture2D:
			return loaded as Texture2D
	return texture

## Returns a path guaranteed not to conflict with existing files.
## Appends _1, _2, … suffixes until a free slot is found.
static func _get_unique_path(dir_path: String, base_filename: String, extension: String) -> String:
	var candidate: String = dir_path + "/" + base_filename + "." + extension
	if not FileAccess.file_exists(candidate):
		return candidate
	var counter := 1
	while true:
		candidate = "%s/%s_%d.%s" % [dir_path, base_filename, counter, extension]
		if not FileAccess.file_exists(candidate):
			break
		counter += 1
	return candidate  # counter found a free slot above
