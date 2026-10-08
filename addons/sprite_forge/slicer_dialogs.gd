@tool
extends Node

signal texture_selected(path: String)
signal frame_selected(path: String)
signal material_selected(path: String)
signal font_selected(path: String)
signal grid_slice_requested(cell_w: int, cell_h: int, off_x: int, off_y: int, sep_x: int, sep_y: int, keep_empty: bool)
signal resize_image_requested(new_w: int, new_h: int, interp_mode: int, scale_slices: bool)

var file_dialog: FileDialog
var frame_dialog: FileDialog
var material_dialog: FileDialog
var font_dialog: FileDialog
var grid_dialog: ConfirmationDialog
var resize_dialog: ConfirmationDialog

var _grid_spin_w: SpinBox
var _grid_spin_h: SpinBox
var _grid_spin_off_x: SpinBox
var _grid_spin_off_y: SpinBox
var _grid_spin_sep_x: SpinBox
var _grid_spin_sep_y: SpinBox
var _grid_chk_keep_empty: CheckBox

var _resize_spin_w: SpinBox
var _resize_spin_h: SpinBox
var _resize_chk_aspect: CheckBox
var _resize_opt_interp: OptionButton
var _resize_chk_scale_slices: CheckBox
var _resize_aspect_ratio: float = 1.0
var _updating_resize_spin: bool = false

func setup_dialogs(parent_node: Node) -> void:
	_setup_file_dialog(parent_node)
	_setup_frame_dialog(parent_node)
	_setup_material_dialog(parent_node)
	_setup_font_dialog(parent_node)
	_setup_grid_dialog(parent_node)
	_setup_resize_dialog(parent_node)

func open_texture_dialog() -> void:
	if file_dialog:
		file_dialog.popup_centered_ratio(0.6)

func open_frame_dialog() -> void:
	if frame_dialog:
		frame_dialog.popup_centered_ratio(0.6)

func open_material_dialog() -> void:
	if material_dialog:
		material_dialog.popup_centered_ratio(0.5)

func open_font_dialog() -> void:
	if font_dialog:
		font_dialog.popup_centered_ratio(0.5)

func open_grid_dialog() -> void:
	if grid_dialog:
		grid_dialog.popup_centered()

func open_resize_dialog(cur_w: int, cur_h: int) -> void:
	if not resize_dialog:
		return
	_updating_resize_spin = true
	_resize_spin_w.value = cur_w
	_resize_spin_h.value = cur_h
	_resize_aspect_ratio = float(cur_w) / float(max(1, cur_h))
	_updating_resize_spin = false
	resize_dialog.popup_centered()

func _setup_file_dialog(parent: Node) -> void:
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.title = "Select Texture"
	file_dialog.add_filter("*.png", "PNG Images")
	file_dialog.add_filter("*.jpg", "JPEG Images")
	file_dialog.add_filter("*.jpeg", "JPEG Images")
	file_dialog.add_filter("*.webp", "WebP Images")
	file_dialog.add_filter("*.tres", "Godot Resource Textures")
	file_dialog.file_selected.connect(func(path: String): texture_selected.emit(path))
	parent.add_child(file_dialog)

func _setup_frame_dialog(parent: Node) -> void:
	frame_dialog = FileDialog.new()
	frame_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	frame_dialog.access = FileDialog.ACCESS_RESOURCES
	frame_dialog.title = "Select Frame Image or Resource"
	frame_dialog.add_filter("*.png", "PNG Images")
	frame_dialog.add_filter("*.jpg", "JPEG Images")
	frame_dialog.add_filter("*.jpeg", "JPEG Images")
	frame_dialog.add_filter("*.webp", "WebP Images")
	frame_dialog.add_filter("*.tres", "Godot Resource Files")
	frame_dialog.add_filter("*.res", "Godot Binary Resource Files")
	frame_dialog.file_selected.connect(func(path: String): frame_selected.emit(path))
	parent.add_child(frame_dialog)

func _setup_material_dialog(parent: Node) -> void:
	material_dialog = FileDialog.new()
	material_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	material_dialog.access = FileDialog.ACCESS_RESOURCES
	material_dialog.title = "Select Shader/Material Resource"
	material_dialog.add_filter("*.tres", "Material Resources")
	material_dialog.add_filter("*.material", "Material Resources")
	material_dialog.file_selected.connect(func(path: String): material_selected.emit(path))
	parent.add_child(material_dialog)

func _setup_font_dialog(parent: Node) -> void:
	font_dialog = FileDialog.new()
	font_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	font_dialog.access = FileDialog.ACCESS_RESOURCES
	font_dialog.title = "Select Font File"
	font_dialog.add_filter("*.ttf", "TrueType Fonts")
	font_dialog.add_filter("*.otf", "OpenType Fonts")
	font_dialog.add_filter("*.woff", "Web Open Fonts")
	font_dialog.add_filter("*.woff2", "Web Open Fonts 2")
	font_dialog.add_filter("*.tres", "Godot Resource Fonts")
	font_dialog.add_filter("*.font", "Godot Font Resources")
	font_dialog.file_selected.connect(func(path: String): font_selected.emit(path))
	parent.add_child(font_dialog)

func _setup_grid_dialog(parent: Node) -> void:
	grid_dialog = ConfirmationDialog.new()
	grid_dialog.title = "Grid Slice Settings"
	
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	
	_grid_spin_w = _add_grid_spin("Cell Width:", grid, 32)
	_grid_spin_h = _add_grid_spin("Cell Height:", grid, 32)
	_grid_spin_off_x = _add_grid_spin("Offset X:", grid, 0)
	_grid_spin_off_y = _add_grid_spin("Offset Y:", grid, 0)
	_grid_spin_sep_x = _add_grid_spin("Separation X:", grid, 0)
	_grid_spin_sep_y = _add_grid_spin("Separation Y:", grid, 0)
	
	var lbl_keep := Label.new()
	lbl_keep.text = "Keep Empty Slices:"
	grid.add_child(lbl_keep)
	_grid_chk_keep_empty = CheckBox.new()
	_grid_chk_keep_empty.button_pressed = false
	grid.add_child(_grid_chk_keep_empty)
	
	grid_dialog.add_child(grid)
	grid_dialog.confirmed.connect(_on_grid_confirmed)
	parent.add_child(grid_dialog)

func _add_grid_spin(label_text: String, parent: Control, default_val: int) -> SpinBox:
	var lbl := Label.new()
	lbl.text = label_text
	parent.add_child(lbl)
	var sb := SpinBox.new()
	sb.min_value = 0 if "Offset" in label_text or "Separation" in label_text else 1
	sb.max_value = 8192
	sb.value = default_val
	parent.add_child(sb)
	return sb

func _on_grid_confirmed() -> void:
	grid_slice_requested.emit(
		int(_grid_spin_w.value),
		int(_grid_spin_h.value),
		int(_grid_spin_off_x.value),
		int(_grid_spin_off_y.value),
		int(_grid_spin_sep_x.value),
		int(_grid_spin_sep_y.value),
		_grid_chk_keep_empty.button_pressed
	)

func _setup_resize_dialog(parent: Node) -> void:
	resize_dialog = ConfirmationDialog.new()
	resize_dialog.title = "Resize Image"

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)

	_resize_spin_w = _add_grid_spin("New Width (px):", grid, 256)
	_resize_spin_h = _add_grid_spin("New Height (px):", grid, 256)
	_resize_spin_w.max_value = 16384
	_resize_spin_h.max_value = 16384

	_resize_spin_w.value_changed.connect(func(v: float):
		if _updating_resize_spin or not _resize_chk_aspect or not _resize_chk_aspect.button_pressed:
			return
		_updating_resize_spin = true
		_resize_spin_h.value = max(1.0, round(v / max(0.001, _resize_aspect_ratio)))
		_updating_resize_spin = false
	)

	_resize_spin_h.value_changed.connect(func(v: float):
		if _updating_resize_spin or not _resize_chk_aspect or not _resize_chk_aspect.button_pressed:
			return
		_updating_resize_spin = true
		_resize_spin_w.value = max(1.0, round(v * _resize_aspect_ratio))
		_updating_resize_spin = false
	)

	var lbl_aspect := Label.new()
	lbl_aspect.text = "Keep Aspect Ratio:"
	grid.add_child(lbl_aspect)
	_resize_chk_aspect = CheckBox.new()
	_resize_chk_aspect.button_pressed = true
	grid.add_child(_resize_chk_aspect)

	var lbl_interp := Label.new()
	lbl_interp.text = "Filter / Interpolation:"
	grid.add_child(lbl_interp)
	_resize_opt_interp = OptionButton.new()
	_resize_opt_interp.add_item("Nearest (Pixel Art)")
	_resize_opt_interp.add_item("Bilinear (Smooth)")
	_resize_opt_interp.add_item("Cubic (High Quality)")
	_resize_opt_interp.add_item("Lanczos (Sharp)")
	_resize_opt_interp.selected = 0
	grid.add_child(_resize_opt_interp)

	var lbl_scale_slices := Label.new()
	lbl_scale_slices.text = "Scale Slice Rects:"
	grid.add_child(lbl_scale_slices)
	_resize_chk_scale_slices = CheckBox.new()
	_resize_chk_scale_slices.button_pressed = true
	_resize_chk_scale_slices.tooltip_text = "Scale existing slice boundaries proportionally with image resize"
	grid.add_child(_resize_chk_scale_slices)

	resize_dialog.add_child(grid)
	resize_dialog.confirmed.connect(_on_resize_confirmed)
	parent.add_child(resize_dialog)

func _on_resize_confirmed() -> void:
	var interp_map := [
		Image.INTERPOLATE_NEAREST,
		Image.INTERPOLATE_BILINEAR,
		Image.INTERPOLATE_CUBIC,
		Image.INTERPOLATE_LANCZOS
	]
	var selected_idx: int = clamp(_resize_opt_interp.selected, 0, 3)
	resize_image_requested.emit(
		int(_resize_spin_w.value),
		int(_resize_spin_h.value),
		interp_map[selected_idx],
		_resize_chk_scale_slices.button_pressed
	)
