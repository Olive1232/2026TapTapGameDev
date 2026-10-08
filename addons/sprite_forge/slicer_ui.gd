@tool
extends HBoxContainer

# Preloads
const _AutoSlicer   = preload("res://addons/sprite_forge/auto_slicer.gd")
const _Extractor    = preload("res://addons/sprite_forge/extractor.gd")
const _CanvasScript = preload("res://addons/sprite_forge/slicer_canvas.gd")
const _BgRemover    = preload("res://addons/sprite_forge/bg_remover.gd")
const _PreviewPlayerScript = preload("res://addons/sprite_forge/slicer_preview_player.gd")
const _HistoryScript = preload("res://addons/sprite_forge/slicer_history.gd")
const _DialogScript  = preload("res://addons/sprite_forge/slicer_dialogs.gd")


# UI References
var _canvas: _CanvasScript
var _path_label:  LineEdit
var _count_label: Label
var _slice_list:  ItemList
var _name_edit:   LineEdit
var _spin_x:      SpinBox
var _spin_y:      SpinBox
var _spin_w:      SpinBox
var _spin_h:      SpinBox
var _zoom_label:  Label
var _format_opt:  OptionButton
var _props_box:   VBoxContainer
var _file_dialog: FileDialog
var _chk_atlas:   CheckBox
var _chk_spriteframes: CheckBox
var _chk_png: CheckBox
var _wand_btn:    Button
var _brush_erase_btn: Button
var _paint_btn: Button
var _recolor_btn: Button
var _stamp_btn: Button # Frame button alias
var _text_btn: Button
var _order_opt: OptionButton
var _color_picker: ColorPickerButton
var _props_grid: GridContainer

# State & Managers
var _history: _HistoryScript
var _dialogs: _DialogScript
var _current_tex:      Texture2D
var _current_tex_path: String  = ""
var _zoom:             float   = 1.0
var _updating_props:   bool    = false
var _bg_tolerance:     float   = 0.18
var _brush_size_spin: SpinBox

var _merge_btn: Button
var _lock_btn: Button
var _chk_snap: CheckBox
var _spin_snap_w: SpinBox
var _spin_snap_h: SpinBox

var _undo_btn: Button
var _redo_btn: Button

# UI references for Preview Player
var _preview_player: _PreviewPlayerScript
var _anim_name_edit: LineEdit

var _mat_edit: LineEdit
var _mat_browse_btn: Button
var _mat_box: HBoxContainer
var _stamp_props_box: VBoxContainer
var _stamp_pos_x: SpinBox
var _stamp_pos_y: SpinBox
var _stamp_scale_x: SpinBox
var _stamp_scale_y: SpinBox
var _stamp_pivot_x: SpinBox
var _stamp_pivot_y: SpinBox
var _stamp_rot: SpinBox

# Frame animation frames
var _stamp_frames: Array[Texture2D] = []
var _stamp_frame_idx: int = 0
var _stamp_frame_label: Label
var _stamp_prev_frame_btn: Button
var _stamp_next_frame_btn: Button

var _export_folder_edit: LineEdit
var _export_base_edit: LineEdit
var _chk_subfolder: CheckBox
var _chk_auto_unique: CheckBox

# Text Tool UI
var _text_props_box: VBoxContainer
var _text_input: LineEdit
var _font_path_label: LineEdit
var _font_browse_btn: Button
var _text_font_size_spin: SpinBox
var _text_color_picker: ColorPickerButton
var _current_font: Font = null
var _current_font_path: String = ""



func _ready() -> void:
	_history = _HistoryScript.new()
	_history.history_changed.connect(_on_history_changed)

	_build_ui()

	_dialogs = _DialogScript.new()
	_dialogs.texture_selected.connect(_load_texture)
	_dialogs.frame_selected.connect(_load_stamp_image)
	_dialogs.material_selected.connect(_assign_material_to_selected)
	_dialogs.font_selected.connect(_load_font_file)
	_dialogs.grid_slice_requested.connect(_on_grid_slice_confirmed_args)
	_dialogs.resize_image_requested.connect(_on_resize_image_requested)
	add_child(_dialogs)
	_dialogs.setup_dialogs(self)

	if _canvas:
		_canvas.tolerance = _bg_tolerance

# --- UI Construction ---

func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	add_child(split)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	split.add_child(left)

	left.add_child(_make_toolbar())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)

	_canvas = _CanvasScript.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.selection_changed.connect(_on_canvas_selection_changed)
	_canvas.rects_changed.connect(_on_rects_changed)
	_canvas.rects_updated.connect(_on_rects_updated)
	_canvas.zoom_changed.connect(_on_canvas_zoom_changed)
	_canvas.erase_clicked.connect(_on_erase_clicked)
	_canvas.brush_erase_clicked.connect(_on_brush_erase_clicked)
	_canvas.brush_erase_dragged.connect(_on_brush_erase_dragged)
	_canvas.brush_erase_released.connect(_on_brush_erase_released)
	_canvas.brush_paint_clicked.connect(_on_brush_paint_clicked)
	_canvas.brush_paint_dragged.connect(_on_brush_paint_dragged)
	_canvas.brush_paint_released.connect(_on_brush_paint_released)
	_canvas.recolor_clicked.connect(_on_recolor_clicked)
	_canvas.stamp_pos_changed.connect(_on_canvas_stamp_pos_changed)
	_canvas.stamp_rotation_changed.connect(_on_canvas_stamp_rotation_changed)
	_canvas.stamp_scale_changed.connect(_on_canvas_stamp_scale_changed)
	_canvas.slice_action_started.connect(_push_slices_state)
	scroll.add_child(_canvas)

	var right := _make_right_panel()
	split.add_child(right)
	split.split_offset = -260

func _make_toolbar() -> Control:
	var tb_outer := VBoxContainer.new()
	tb_outer.add_theme_constant_override("separation", 4)

	# --- Row 1: File, Slice, Undo/Redo, Zoom ---
	var tb1 := HFlowContainer.new()
	tb1.add_theme_constant_override("h_separation", 4)
	tb1.add_theme_constant_override("v_separation", 4)
	tb_outer.add_child(tb1)

	var browse_btn := Button.new()
	browse_btn.text = "Browse..."
	browse_btn.pressed.connect(_on_browse)
	tb1.add_child(browse_btn)

	_path_label = LineEdit.new()
	_path_label.editable              = false
	_path_label.placeholder_text      = "No texture selected"
	_path_label.custom_minimum_size   = Vector2(80, 0)
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb1.add_child(_path_label)

	tb1.add_child(VSeparator.new())

	var auto_btn := Button.new()
	auto_btn.text = "Auto Slice"
	auto_btn.tooltip_text = "Detect sprites via flood-fill"
	auto_btn.pressed.connect(_on_auto_slice)
	tb1.add_child(auto_btn)

	var grid_btn := Button.new()
	grid_btn.text = "Grid Slice..."
	grid_btn.tooltip_text = "Slice into a uniform grid"
	grid_btn.pressed.connect(func():
		if _dialogs:
			_dialogs.open_grid_dialog()
	)
	tb1.add_child(grid_btn)

	var resize_btn := Button.new()
	resize_btn.text = "Resize Image..."
	resize_btn.tooltip_text = "Resize the main image resolution (with optional slice scaling)"
	resize_btn.pressed.connect(func():
		if _dialogs and _current_tex:
			var img: Image = _current_tex.get_image()
			if img:
				_dialogs.open_resize_dialog(img.get_width(), img.get_height())
	)
	tb1.add_child(resize_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.tooltip_text = "Remove all slices"
	clear_btn.pressed.connect(_on_clear)
	tb1.add_child(clear_btn)

	tb1.add_child(VSeparator.new())
	
	var flip_h_btn := Button.new()
	flip_h_btn.text = "↔"
	flip_h_btn.tooltip_text = "Flip Image Horizontally"
	flip_h_btn.pressed.connect(func(): _flip_main_texture(true, false))
	tb1.add_child(flip_h_btn)
	
	var flip_v_btn := Button.new()
	flip_v_btn.text = "↕"
	flip_v_btn.tooltip_text = "Flip Image Vertically"
	flip_v_btn.pressed.connect(func(): _flip_main_texture(false, true))
	tb1.add_child(flip_v_btn)

	tb1.add_child(VSeparator.new())

	_undo_btn = Button.new()
	_undo_btn.text = "Undo"
	_undo_btn.tooltip_text = "Undo last action (Ctrl+Z)"
	_undo_btn.disabled = true
	_undo_btn.pressed.connect(_undo)
	tb1.add_child(_undo_btn)

	_redo_btn = Button.new()
	_redo_btn.text = "Redo"
	_redo_btn.tooltip_text = "Redo (Ctrl+Y / Ctrl+Shift+Z)"
	_redo_btn.disabled = true
	_redo_btn.pressed.connect(_redo)
	tb1.add_child(_redo_btn)

	tb1.add_child(VSeparator.new())

	var zminus := Button.new()
	zminus.text = "-"
	zminus.custom_minimum_size = Vector2(26, 0)
	zminus.pressed.connect(func(): _canvas.set_zoom(_zoom / 1.25))
	tb1.add_child(zminus)

	_zoom_label = Label.new()
	_zoom_label.text                  = "100%"
	_zoom_label.custom_minimum_size   = Vector2(50, 0)
	_zoom_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	tb1.add_child(_zoom_label)

	var zplus := Button.new()
	zplus.text = "+"
	zplus.custom_minimum_size = Vector2(26, 0)
	zplus.pressed.connect(func(): _canvas.set_zoom(_zoom * 1.25))
	tb1.add_child(zplus)

	var extract_btn := Button.new()
	extract_btn.text = "Extract All"
	extract_btn.tooltip_text = "Export slices to disk"
	extract_btn.pressed.connect(func(): _on_extract(false))
	tb1.add_child(extract_btn)
	
	var extract_sel_btn := Button.new()
	extract_sel_btn.text = "Extract Selected"
	extract_sel_btn.tooltip_text = "Export ONLY the currently selected slices to disk"
	extract_sel_btn.pressed.connect(func(): _on_extract(true))
	tb1.add_child(extract_sel_btn)

	# --- Row 2: Erase tools ---
	var tb2 := HFlowContainer.new()
	tb2.add_theme_constant_override("h_separation", 4)
	tb2.add_theme_constant_override("v_separation", 4)
	tb_outer.add_child(tb2)

	var remove_bg_btn := Button.new()
	remove_bg_btn.text = "Remove BG"
	remove_bg_btn.tooltip_text = "Remove background color using flood-fill"
	remove_bg_btn.pressed.connect(_on_remove_bg)
	tb2.add_child(remove_bg_btn)

	var tol_label := Label.new()
	tol_label.text = "Tol:"
	tb2.add_child(tol_label)

	var tol_spin := SpinBox.new()
	tol_spin.min_value = 1
	tol_spin.max_value = 80
	tol_spin.step = 1
	tol_spin.value = int(_bg_tolerance * 100)
	tol_spin.custom_minimum_size = Vector2(68, 0)
	tol_spin.suffix = "%"
	tol_spin.tooltip_text = "Background removal tolerance"
	tol_spin.value_changed.connect(func(v: float): 
		_bg_tolerance = v / 100.0
		if _canvas:
			_canvas.tolerance = _bg_tolerance
	)
	tb2.add_child(tol_spin)

	tb2.add_child(VSeparator.new())

	_wand_btn = Button.new()
	_wand_btn.text = "Magic Wand Erase"
	_wand_btn.toggle_mode = true
	_wand_btn.tooltip_text = "Click to erase matching color regions"
	_wand_btn.toggled.connect(_on_wand_toggled)
	tb2.add_child(_wand_btn)

	_brush_erase_btn = Button.new()
	_brush_erase_btn.text = "Brush Erase"
	_brush_erase_btn.toggle_mode = true
	_brush_erase_btn.tooltip_text = "Click and drag to erase pixels"
	_brush_erase_btn.toggled.connect(_on_brush_toggled)
	tb2.add_child(_brush_erase_btn)

	tb2.add_child(VSeparator.new())

	_recolor_btn = Button.new()
	_recolor_btn.text = "Magic Wand Recolor"
	_recolor_btn.toggle_mode = true
	_recolor_btn.tooltip_text = "Click to recolor matching color regions"
	_recolor_btn.toggled.connect(_on_recolor_toggled)
	tb2.add_child(_recolor_btn)

	_paint_btn = Button.new()
	_paint_btn.text = "Brush Paint"
	_paint_btn.toggle_mode = true
	_paint_btn.tooltip_text = "Click and drag to paint with color"
	_paint_btn.toggled.connect(_on_paint_toggled)
	tb2.add_child(_paint_btn)

	_color_picker = ColorPickerButton.new()
	_color_picker.color = Color.WHITE
	_color_picker.custom_minimum_size = Vector2(40, 0)
	_color_picker.tooltip_text = "Select paint/recolor color"
	_color_picker.color_changed.connect(func(col: Color):
		if _canvas:
			_canvas.paint_color = col
			_canvas.queue_redraw()
	)
	tb2.add_child(_color_picker)

	tb2.add_child(VSeparator.new())

	_stamp_btn = Button.new()
	_stamp_btn.text = "Frame..."
	_stamp_btn.toggle_mode = true
	_stamp_btn.tooltip_text = "Load an image frame onto the canvas (click again while active to load another)"
	_stamp_btn.toggled.connect(func(pressed: bool):
		if pressed:
			if _dialogs:
				_dialogs.open_frame_dialog()
		else:
			if _canvas and _canvas.frame_mode:
				_select_tool("")
	)
	tb2.add_child(_stamp_btn)

	_text_btn = Button.new()
	_text_btn.text = "Text..."
	_text_btn.toggle_mode = true
	_text_btn.tooltip_text = "Write custom text with font selection onto the canvas"
	_text_btn.toggled.connect(func(pressed: bool):
		if pressed:
			_select_tool("text")
		else:
			if _canvas and _canvas.frame_mode:
				_select_tool("")
	)
	tb2.add_child(_text_btn)

	# --- Stamp animation frame navigation ---
	_stamp_prev_frame_btn = Button.new()
	_stamp_prev_frame_btn.text = "◀"
	_stamp_prev_frame_btn.custom_minimum_size = Vector2(24, 0)
	_stamp_prev_frame_btn.disabled = true
	_stamp_prev_frame_btn.tooltip_text = "Previous frame (animation)"
	_stamp_prev_frame_btn.pressed.connect(func():
		_stamp_frame_idx -= 1
		_update_stamp_frame()
	)
	tb2.add_child(_stamp_prev_frame_btn)

	_stamp_frame_label = Label.new()
	_stamp_frame_label.text = "-/-"
	_stamp_frame_label.custom_minimum_size = Vector2(32, 0)
	_stamp_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stamp_frame_label.tooltip_text = "Current frame / Total frames"
	tb2.add_child(_stamp_frame_label)

	_stamp_next_frame_btn = Button.new()
	_stamp_next_frame_btn.text = "▶"
	_stamp_next_frame_btn.custom_minimum_size = Vector2(24, 0)
	_stamp_next_frame_btn.disabled = true
	_stamp_next_frame_btn.tooltip_text = "Next frame (animation)"
	_stamp_next_frame_btn.pressed.connect(func():
		_stamp_frame_idx += 1
		_update_stamp_frame()
	)
	tb2.add_child(_stamp_next_frame_btn)



	tb2.add_child(VSeparator.new())

	var brush_size_label := Label.new()
	brush_size_label.text = "Size:"
	tb2.add_child(brush_size_label)

	_brush_size_spin = SpinBox.new()
	_brush_size_spin.min_value = 0.5
	_brush_size_spin.max_value = 100.0
	_brush_size_spin.value = 8.0
	_brush_size_spin.step = 0.25
	_brush_size_spin.custom_minimum_size = Vector2(60, 0)
	_brush_size_spin.tooltip_text = "Brush radius"
	_brush_size_spin.value_changed.connect(func(val: float):
		if _canvas != null:
			_canvas.brush_size = float(val)
			_canvas.queue_redraw()
	)
	tb2.add_child(_brush_size_spin)
	if _canvas != null:
		_canvas.brush_size = 8.0

	tb2.add_child(VSeparator.new())

	var shape_lbl := Label.new()
	shape_lbl.text = "Shape:"
	tb2.add_child(shape_lbl)

	var shape_opt := OptionButton.new()
	shape_opt.add_item("Circle", 0)
	shape_opt.add_item("Square", 1)
	shape_opt.selected = 0
	shape_opt.item_selected.connect(func(idx: int):
		if _canvas != null:
			_canvas.brush_is_square = (idx == 1)
			_canvas.queue_redraw()
	)
	tb2.add_child(shape_opt)

	tb2.add_child(VSeparator.new())

	var order_lbl := Label.new()
	order_lbl.text = "Order:"
	tb2.add_child(order_lbl)

	_order_opt = OptionButton.new()
	_order_opt.add_item("In Front", 0)
	_order_opt.add_item("Behind", 1)
	_order_opt.selected = 0
	_order_opt.tooltip_text = "Layer order: paint/frame placed in front of or behind existing sprite pixels"
	_order_opt.item_selected.connect(func(idx: int):
		if _canvas != null:
			_canvas.order_behind = (idx == 1)
			_canvas.queue_redraw()
	)
	tb2.add_child(_order_opt)

	return tb_outer

func _make_right_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	panel.size_flags_vertical  = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var list_header := HBoxContainer.new()
	list_header.add_theme_constant_override("separation", 4)
	vbox.add_child(list_header)

	_count_label = Label.new()
	_count_label.text = "SLICES (0)"
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_header.add_child(_count_label)

	var sel_all_btn := Button.new()
	sel_all_btn.text = "All"
	sel_all_btn.tooltip_text = "Select all slices (Ctrl + A)"
	sel_all_btn.pressed.connect(func():
		if _canvas and not _canvas.rects.is_empty():
			_canvas.selected_indices.clear()
			for i in range(_canvas.rects.size()):
				_canvas.selected_indices.append(i)
			_canvas.selection_changed.emit(_canvas.selected_indices)
			_canvas.queue_redraw()
	)
	list_header.add_child(sel_all_btn)

	var desel_all_btn := Button.new()
	desel_all_btn.text = "None"
	desel_all_btn.tooltip_text = "Deselect all slices (Escape)"
	desel_all_btn.pressed.connect(func():
		if _canvas and not _canvas.selected_indices.is_empty():
			_canvas.selected_indices.clear()
			_canvas.selection_changed.emit(_canvas.selected_indices)
			_canvas.queue_redraw()
	)
	list_header.add_child(desel_all_btn)

	_slice_list = ItemList.new()
	_slice_list.select_mode = ItemList.SELECT_MULTI
	_slice_list.size_flags_vertical  = Control.SIZE_EXPAND_FILL
	_slice_list.custom_minimum_size  = Vector2(0, 150)
	_slice_list.item_selected.connect(_on_list_item_selected)
	vbox.add_child(_slice_list)

	vbox.add_child(HSeparator.new())

	_props_box = VBoxContainer.new()
	_props_box.add_theme_constant_override("separation", 4)
	_props_box.visible = false
	vbox.add_child(_props_box)

	# Frame Properties Box
	_stamp_props_box = VBoxContainer.new()
	_stamp_props_box.add_theme_constant_override("separation", 6)
	_stamp_props_box.visible = false
	vbox.add_child(_stamp_props_box)

	var stamp_title := Label.new()
	stamp_title.text = "Frame Properties"
	_stamp_props_box.add_child(stamp_title)

	var stamp_grid := GridContainer.new()
	stamp_grid.columns = 4
	stamp_grid.add_theme_constant_override("h_separation", 4)
	stamp_grid.add_theme_constant_override("v_separation", 4)
	_stamp_props_box.add_child(stamp_grid)

	_stamp_pos_x = _make_stamp_spin_inline("Pos X", stamp_grid, -8192.0, 8192.0, 1.0, 0.0)
	_stamp_pos_y = _make_stamp_spin_inline("Pos Y", stamp_grid, -8192.0, 8192.0, 1.0, 0.0)
	
	_stamp_scale_x = _make_stamp_spin_inline("Scale X", stamp_grid, 0.05, 50.0, 0.05, 1.0)
	_stamp_scale_y = _make_stamp_spin_inline("Scale Y", stamp_grid, 0.05, 50.0, 0.05, 1.0)
	
	_stamp_pivot_x = _make_stamp_spin_inline("Pivot X", stamp_grid, -8192.0, 8192.0, 1.0, 0.0)
	_stamp_pivot_y = _make_stamp_spin_inline("Pivot Y", stamp_grid, -8192.0, 8192.0, 1.0, 0.0)
	
	_stamp_rot = _make_stamp_spin_inline("Rot Deg", stamp_grid, -360.0, 360.0, 1.0, 0.0)
	
	# Empty labels to align grid
	var empty_lbl1 := Label.new()
	var empty_lbl2 := Label.new()
	stamp_grid.add_child(empty_lbl1)
	stamp_grid.add_child(empty_lbl2)

	# Stamp Actions
	var stamp_actions := HBoxContainer.new()
	stamp_actions.add_theme_constant_override("separation", 6)
	_stamp_props_box.add_child(stamp_actions)
	
	var stamp_flip_h := Button.new()
	stamp_flip_h.text = "↔"
	stamp_flip_h.tooltip_text = "Flip Horizontal"
	stamp_flip_h.pressed.connect(func():
		if _canvas:
			_canvas.frame_flip_h = not _canvas.frame_flip_h
			_canvas.queue_redraw()
	)
	stamp_actions.add_child(stamp_flip_h)
	
	var stamp_flip_v := Button.new()
	stamp_flip_v.text = "↕"
	stamp_flip_v.tooltip_text = "Flip Vertical"
	stamp_flip_v.pressed.connect(func():
		if _canvas:
			_canvas.frame_flip_v = not _canvas.frame_flip_v
			_canvas.queue_redraw()
	)
	stamp_actions.add_child(stamp_flip_v)

	var apply_stamp_btn := Button.new()
	apply_stamp_btn.text = "Apply Frame"
	apply_stamp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_stamp_btn.pressed.connect(_apply_stamp)
	stamp_actions.add_child(apply_stamp_btn)

	var cancel_stamp_btn := Button.new()
	cancel_stamp_btn.text = "Cancel"
	cancel_stamp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_stamp_btn.pressed.connect(_cancel_stamp)
	stamp_actions.add_child(cancel_stamp_btn)

	# Text Tool Properties Box
	_text_props_box = VBoxContainer.new()
	_text_props_box.add_theme_constant_override("separation", 6)
	_text_props_box.visible = false
	vbox.add_child(_text_props_box)

	var text_title := Label.new()
	text_title.text = "Text Properties"
	_text_props_box.add_child(text_title)

	_text_input = LineEdit.new()
	_text_input.placeholder_text = "Enter text..."
	_text_input.text = "Text"
	_text_input.text_changed.connect(func(_t: String): _update_text_preview())
	_text_props_box.add_child(_text_input)

	var font_box := HBoxContainer.new()
	font_box.add_theme_constant_override("separation", 4)
	_text_props_box.add_child(font_box)

	_font_path_label = LineEdit.new()
	_font_path_label.placeholder_text = "Default Font"
	_font_path_label.editable = false
	_font_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	font_box.add_child(_font_path_label)

	_font_browse_btn = Button.new()
	_font_browse_btn.text = "..."
	_font_browse_btn.tooltip_text = "Select Font File (.ttf, .otf, .woff, .tres)"
	_font_browse_btn.pressed.connect(func():
		if _dialogs:
			_dialogs.open_font_dialog()
	)
	font_box.add_child(_font_browse_btn)

	var text_style_grid := GridContainer.new()
	text_style_grid.columns = 2
	text_style_grid.add_theme_constant_override("h_separation", 4)
	text_style_grid.add_theme_constant_override("v_separation", 4)
	_text_props_box.add_child(text_style_grid)

	var size_lbl := Label.new()
	size_lbl.text = "Font Size:"
	text_style_grid.add_child(size_lbl)

	_text_font_size_spin = SpinBox.new()
	_text_font_size_spin.min_value = 8
	_text_font_size_spin.max_value = 256
	_text_font_size_spin.value = 24
	_text_font_size_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_font_size_spin.value_changed.connect(func(_v: float): _update_text_preview())
	text_style_grid.add_child(_text_font_size_spin)

	var col_lbl := Label.new()
	col_lbl.text = "Color:"
	text_style_grid.add_child(col_lbl)

	_text_color_picker = ColorPickerButton.new()
	_text_color_picker.color = Color.WHITE
	_text_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_color_picker.color_changed.connect(func(_c: Color): _update_text_preview())
	text_style_grid.add_child(_text_color_picker)

	# Text Actions
	var text_actions := HBoxContainer.new()
	text_actions.add_theme_constant_override("separation", 6)
	_text_props_box.add_child(text_actions)
	
	var text_flip_h := Button.new()
	text_flip_h.text = "↔"
	text_flip_h.tooltip_text = "Flip Horizontal"
	text_flip_h.pressed.connect(func():
		if _canvas:
			_canvas.frame_flip_h = not _canvas.frame_flip_h
			_canvas.queue_redraw()
	)
	text_actions.add_child(text_flip_h)
	
	var text_flip_v := Button.new()
	text_flip_v.text = "↕"
	text_flip_v.tooltip_text = "Flip Vertical"
	text_flip_v.pressed.connect(func():
		if _canvas:
			_canvas.frame_flip_v = not _canvas.frame_flip_v
			_canvas.queue_redraw()
	)
	text_actions.add_child(text_flip_v)

	var apply_text_btn := Button.new()
	apply_text_btn.text = "Apply Text"
	apply_text_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_text_btn.pressed.connect(_apply_stamp)
	text_actions.add_child(apply_text_btn)

	var cancel_text_btn := Button.new()
	cancel_text_btn.text = "Cancel"
	cancel_text_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_text_btn.pressed.connect(func(): _select_tool(""))
	text_actions.add_child(cancel_text_btn)

	var props_title := Label.new()
	props_title.text = "Selected Slice"
	_props_box.add_child(props_title)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Custom Name"
	_name_edit.text_changed.connect(_on_name_changed)
	_props_box.add_child(_name_edit)

	_mat_box = HBoxContainer.new()
	_mat_box.add_theme_constant_override("separation", 4)
	_props_box.add_child(_mat_box)
	
	_mat_edit = LineEdit.new()
	_mat_edit.placeholder_text = "No Material/Shader"
	_mat_edit.editable = false
	_mat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mat_box.add_child(_mat_edit)
	
	_mat_browse_btn = Button.new()
	_mat_browse_btn.text = "..."
	_mat_browse_btn.tooltip_text = "Select Shader/Material file (.tres)"
	_mat_browse_btn.pressed.connect(func():
		if _dialogs:
			_dialogs.open_material_dialog()
	)
	_mat_box.add_child(_mat_browse_btn)

	_props_grid = GridContainer.new()
	_props_grid.columns = 2
	_props_grid.add_theme_constant_override("h_separation", 4)
	_props_grid.add_theme_constant_override("v_separation", 3)
	_props_box.add_child(_props_grid)

	_spin_x = _make_spin("X", _props_grid)
	_spin_y = _make_spin("Y", _props_grid)
	_spin_w = _make_spin("W", _props_grid)
	_spin_h = _make_spin("H", _props_grid)

	for sb in [_spin_x, _spin_y, _spin_w, _spin_h]:
		sb.value_changed.connect(func(_v: float) -> void: _on_prop_changed())

	var actions_grid := GridContainer.new()
	actions_grid.columns = 2
	actions_grid.add_theme_constant_override("h_separation", 4)
	actions_grid.add_theme_constant_override("v_separation", 4)
	_props_box.add_child(actions_grid)

	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del_btn.tooltip_text = "Delete selected slices (Delete / Backspace)"
	del_btn.pressed.connect(_on_delete_selected)
	actions_grid.add_child(del_btn)

	var dup_btn := Button.new()
	dup_btn.text = "Duplicate"
	dup_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dup_btn.tooltip_text = "Duplicate selected slices (Ctrl + D)"
	dup_btn.pressed.connect(func():
		if _canvas and not _canvas.selected_indices.is_empty():
			_canvas._duplicate_selected_rects()
	)
	actions_grid.add_child(dup_btn)

	_merge_btn = Button.new()
	_merge_btn.text = "Merge"
	_merge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merge_btn.tooltip_text = "Merge selected slices into one (Ctrl + M)"
	_merge_btn.pressed.connect(func():
		if _canvas and _canvas.selected_indices.size() >= 2:
			_canvas._merge_selected_rects()
	)
	actions_grid.add_child(_merge_btn)

	_lock_btn = Button.new()
	_lock_btn.text = "Lock"
	_lock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lock_btn.tooltip_text = "Lock/Unlock selected slices to prevent editing (L)"
	_lock_btn.pressed.connect(_on_lock_toggle)
	actions_grid.add_child(_lock_btn)

	vbox.add_child(HSeparator.new())

	var exp_lbl := Label.new()
	exp_lbl.text = "Export Formats"
	vbox.add_child(exp_lbl)

	_chk_png = CheckBox.new()
	_chk_png.text = "PNG Slices (.png)"
	_chk_png.button_pressed = true
	vbox.add_child(_chk_png)

	_chk_atlas = CheckBox.new()
	_chk_atlas.text = "AtlasTexture (.tres)"
	_chk_atlas.button_pressed = false
	vbox.add_child(_chk_atlas)

	var sf_box := HBoxContainer.new()
	sf_box.add_theme_constant_override("separation", 4)
	vbox.add_child(sf_box)

	_chk_spriteframes = CheckBox.new()
	_chk_spriteframes.text = "SpriteFrames"
	_chk_spriteframes.button_pressed = false
	sf_box.add_child(_chk_spriteframes)

	_anim_name_edit = LineEdit.new()
	_anim_name_edit.placeholder_text = "Anim: default"
	_anim_name_edit.custom_minimum_size = Vector2(80, 0)
	_anim_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sf_box.add_child(_anim_name_edit)

	var naming_grid := GridContainer.new()
	naming_grid.columns = 2
	naming_grid.add_theme_constant_override("h_separation", 4)
	naming_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(naming_grid)
	
	var folder_lbl := Label.new()
	folder_lbl.text = "Folder:"
	naming_grid.add_child(folder_lbl)
	
	_export_folder_edit = LineEdit.new()
	_export_folder_edit.placeholder_text = "slices_folder"
	_export_folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	naming_grid.add_child(_export_folder_edit)
	
	var base_lbl := Label.new()
	base_lbl.text = "Base File:"
	naming_grid.add_child(base_lbl)
	
	_export_base_edit = LineEdit.new()
	_export_base_edit.placeholder_text = "file_base"
	_export_base_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	naming_grid.add_child(_export_base_edit)

	_chk_subfolder = CheckBox.new()
	_chk_subfolder.text = "Create Subfolder"
	_chk_subfolder.button_pressed = true
	_chk_subfolder.tooltip_text = "If unchecked, exports directly into the same directory as the texture"
	_chk_subfolder.toggled.connect(func(pressed: bool):
		if _export_folder_edit:
			_export_folder_edit.editable = pressed
	)
	vbox.add_child(_chk_subfolder)

	_chk_auto_unique = CheckBox.new()
	_chk_auto_unique.text = "Auto Unique Names"
	_chk_auto_unique.button_pressed = true
	_chk_auto_unique.tooltip_text = "If a file with the same name exists, automatically appends _1, _2 to prevent overwriting"
	vbox.add_child(_chk_auto_unique)

	vbox.add_child(HSeparator.new())

	var snap_title := Label.new()
	snap_title.text = "Grid Snapping"
	vbox.add_child(snap_title)

	_chk_snap = CheckBox.new()
	_chk_snap.text = "Snap to Grid"
	_chk_snap.button_pressed = false
	_chk_snap.toggled.connect(func(t: bool):
		if _canvas:
			_canvas.snap_to_grid = t
			_canvas.queue_redraw()
	)
	vbox.add_child(_chk_snap)

	var snap_grid := GridContainer.new()
	snap_grid.columns = 2
	snap_grid.add_theme_constant_override("h_separation", 6)
	snap_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(snap_grid)

	var snap_w_lbl := Label.new()
	snap_w_lbl.text = "Snap W:"
	snap_grid.add_child(snap_w_lbl)

	_spin_snap_w = SpinBox.new()
	_spin_snap_w.min_value = 1
	_spin_snap_w.max_value = 1024
	_spin_snap_w.value = 16
	_spin_snap_w.step = 1
	_spin_snap_w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_snap_w.value_changed.connect(func(v: float):
		if _canvas:
			_canvas.snap_w = int(v)
	)
	snap_grid.add_child(_spin_snap_w)

	var snap_h_lbl := Label.new()
	snap_h_lbl.text = "Snap H:"
	snap_grid.add_child(snap_h_lbl)

	_spin_snap_h = SpinBox.new()
	_spin_snap_h.min_value = 1
	_spin_snap_h.max_value = 1024
	_spin_snap_h.value = 16
	_spin_snap_h.step = 1
	_spin_snap_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_snap_h.value_changed.connect(func(v: float):
		if _canvas:
			_canvas.snap_h = int(v)
	)
	snap_grid.add_child(_spin_snap_h)

	vbox.add_child(HSeparator.new())
	_preview_player = _PreviewPlayerScript.new()
	vbox.add_child(_preview_player)

	return panel

func _make_spin(lbl_text: String, parent: Control) -> SpinBox:
	var lbl := Label.new()
	lbl.text = lbl_text
	lbl.custom_minimum_size = Vector2(16, 0)
	parent.add_child(lbl)

	var sb := SpinBox.new()
	sb.min_value              = 0
	sb.max_value              = 8192
	sb.step                   = 1
	sb.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	parent.add_child(sb)
	return sb

func _make_stamp_spin_inline(lbl_text: String, parent: Control, min_val: float, max_val: float, step_val: float, default_val: float) -> SpinBox:
	var lbl := Label.new()
	lbl.text = lbl_text
	lbl.custom_minimum_size = Vector2(45, 0)
	parent.add_child(lbl)
	
	var sb := SpinBox.new()
	sb.min_value = min_val
	sb.max_value = max_val
	sb.step = step_val
	sb.value = default_val
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sb)
	
	sb.value_changed.connect(func(_v: float) -> void:
		_on_stamp_prop_changed()
	)
	return sb

func _on_grid_slice_confirmed_args(cell_w: int, cell_h: int, off_x: int, off_y: int, sep_x: int, sep_y: int, keep_empty: bool) -> void:
	if not _current_tex:
		return
	var img: Image = _current_tex.get_image()
	if not img or img.is_empty():
		return

	_push_slices_state()
	var rects := _AutoSlicer.slice_grid(img, cell_w, cell_h, off_x, off_y, sep_x, sep_y, keep_empty)
	_canvas.set_rects(rects)
	_refresh_list()
	_update_props()
	if _preview_player:
		_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)

func _on_resize_image_requested(new_w: int, new_h: int, interp_mode: int, scale_slices: bool) -> void:
	if not _current_tex or _current_tex_path.is_empty() or not _canvas:
		return
	var base_img: Image = _current_tex.get_image()
	if not base_img or base_img.is_empty():
		return

	var old_w: int = base_img.get_width()
	var old_h: int = base_img.get_height()
	if old_w == new_w and old_h == new_h:
		return

	_push_image_state()
	_ensure_edited_path()

	var resized_img := base_img.duplicate()
	resized_img.resize(new_w, new_h, interp_mode)

	if scale_slices and not _canvas.rects.is_empty():
		var sx: float = float(new_w) / float(old_w)
		var sy: float = float(new_h) / float(old_h)
		for i in range(_canvas.rects.size()):
			var r := _canvas.rects[i]
			_canvas.rects[i] = Rect2(r.position.x * sx, r.position.y * sy, r.size.x * sx, r.size.y * sy)

	var new_tex := ImageTexture.create_from_image(resized_img)
	_current_tex = new_tex
	_canvas.update_texture(new_tex)
	_save_edited_texture()
	_refresh_list()
	_update_props()
	if _preview_player:
		_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)
	_canvas.queue_redraw()

func _on_browse() -> void:
	if _dialogs:
		_dialogs.open_texture_dialog()

# --- Action handlers ---

func _load_texture(path: String) -> void:
	var tex: Texture2D = null
	var res = load(path)
	if res is Texture2D:
		tex = res
	elif res is Image:
		tex = ImageTexture.create_from_image(res)
	elif res != null and res.has_method("get_image"):
		var img: Image = res.get_image()
		if img and not img.is_empty():
			tex = ImageTexture.create_from_image(img)

	if tex == null:
		# Fallback: load directly from file system (useful for unimported PNGs or external paths)
		var abs_p := ProjectSettings.globalize_path(path)
		var img := Image.load_from_file(abs_p)
		if img and not img.is_empty():
			tex = ImageTexture.create_from_image(img)

	if tex == null:
		push_error("SpriteForge: Could not load texture from path: " + path)
		return

	if _history:
		_history.clear()
	_current_tex      = tex
	_current_tex_path = path
	_path_label.text  = path.get_file()
	_path_label.tooltip_text = path
	_canvas.load_texture(tex)
	_canvas.set_zoom(1.0)
	_refresh_list()
	_update_props()
	if _preview_player:
		_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)

func _on_auto_slice() -> void:
	if not _current_tex:
		return
	_push_slices_state()
	_canvas.set_rects(_AutoSlicer.slice(_current_tex.get_image()))
	_refresh_list()
	_update_props()
	if _preview_player:
		_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)

func _on_clear() -> void:
	_push_slices_state()
	_canvas.rects.clear()
	_canvas.slice_names.clear()
	_canvas.slice_materials.clear()
	_canvas.selected_indices.clear()
	_canvas.locked_states.clear()
	_canvas.queue_redraw()
	_refresh_list()
	_update_props()
	if _preview_player:
		_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)

func _flip_main_texture(flip_h: bool, flip_v: bool) -> void:
	if not _current_tex or _current_tex_path.is_empty():
		return
	_push_image_state()
	_ensure_edited_path()
	var img: Image = _current_tex.get_image()
	if not img:
		return
	
	if flip_h:
		img.flip_x()
	if flip_v:
		img.flip_y()
		
	var new_tex := ImageTexture.create_from_image(img)
	_current_tex = new_tex
	_canvas.update_texture(new_tex)
	_save_edited_texture()
	
	# Flip all rects symmetrically
	var w := float(img.get_width())
	var h := float(img.get_height())
	
	for i in range(_canvas.rects.size()):
		var r: Rect2 = _canvas.rects[i]
		if flip_h:
			r.position.x = w - r.position.x - r.size.x
		if flip_v:
			r.position.y = h - r.position.y - r.size.y
		_canvas.rects[i] = r
	
	_canvas.queue_redraw()
	_update_props()
	if _preview_player:
		_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)

func _on_extract(only_selected: bool = false) -> void:
	if not _current_tex or _canvas.rects.is_empty():
		return
		
	var export_rects: Array[Rect2] = []
	var export_names: Array[String] = []
	var export_materials: Array[String] = []
	
	if only_selected and not _canvas.selected_indices.is_empty():
		var sel_sorted = _canvas.selected_indices.duplicate()
		sel_sorted.sort()
		for idx in sel_sorted:
			if idx >= 0 and idx < _canvas.rects.size():
				export_rects.append(_canvas.rects[idx])
				export_names.append(_canvas.slice_names[idx])
				export_materials.append(_canvas.slice_materials[idx])
	else:
		export_rects = _canvas.rects.duplicate()
		export_names = _canvas.slice_names.duplicate()
		export_materials = _canvas.slice_materials.duplicate()
		
	if export_rects.is_empty():
		return

	var a_name := "default"
	if _anim_name_edit and _anim_name_edit.text.strip_edges() != "":
		a_name = _anim_name_edit.text.strip_edges()
		
	var custom_folder := ""
	if _export_folder_edit and _export_folder_edit.text.strip_edges() != "":
		custom_folder = _export_folder_edit.text.strip_edges()
		
	var custom_base := ""
	if _export_base_edit and _export_base_edit.text.strip_edges() != "":
		custom_base = _export_base_edit.text.strip_edges()
		
	var use_subfolder := _chk_subfolder.button_pressed if _chk_subfolder else true
	var auto_unique := _chk_auto_unique.button_pressed if _chk_auto_unique else true

	_Extractor.extract(_current_tex, export_rects,
		_chk_png.button_pressed,
		_chk_atlas.button_pressed,
		_chk_spriteframes.button_pressed,
		_current_tex_path, export_names,
		a_name,
		export_materials,
		custom_folder,
		custom_base,
		use_subfolder,
		auto_unique)

func _select_tool(tool_name: String) -> void:
	var wand_on := (tool_name == "wand")
	var brush_erase_on := (tool_name == "brush_erase")
	var recolor_on := (tool_name == "recolor")
	var paint_on := (tool_name == "paint")
	var stamp_on := (tool_name == "stamp")
	var text_on := (tool_name == "text")
	
	_wand_btn.set_pressed_no_signal(wand_on)
	_brush_erase_btn.set_pressed_no_signal(brush_erase_on)
	if _recolor_btn:
		_recolor_btn.set_pressed_no_signal(recolor_on)
	if _paint_btn:
		_paint_btn.set_pressed_no_signal(paint_on)
	if _stamp_btn:
		_stamp_btn.set_pressed_no_signal(stamp_on)
	if _text_btn:
		_text_btn.set_pressed_no_signal(text_on)
		
	_update_button_modulations()
		
	if _canvas:
		_canvas.erase_mode = wand_on
		_canvas.brush_erase_mode = brush_erase_on
		_canvas.recolor_mode = recolor_on
		_canvas.paint_mode = paint_on
		_canvas.frame_mode = (stamp_on or text_on)
		if not stamp_on and not text_on:
			_canvas.frame_tex = null
			_stamp_frames.clear()
			_stamp_frame_idx = 0
			if _stamp_frame_label:
				_stamp_frame_label.text = "-/-"
			if _stamp_prev_frame_btn:
				_stamp_prev_frame_btn.disabled = true
			if _stamp_next_frame_btn:
				_stamp_next_frame_btn.disabled = true
		_canvas.queue_redraw()
		
	if _stamp_props_box != null:
		_stamp_props_box.visible = stamp_on
	if _text_props_box != null:
		_text_props_box.visible = text_on
	if _props_box != null:
		_props_box.visible = not stamp_on and not text_on and not _canvas.selected_indices.is_empty() if _canvas else false

	if text_on:
		_canvas.frame_tex = null
		_stamp_frames.clear()
		_stamp_frame_idx = 0
		_update_text_preview()

func _update_button_modulations() -> void:
	var active_color := Color(0.3, 0.8, 1.0, 1.0)
	var normal_color := Color.WHITE
	
	_wand_btn.self_modulate = active_color if _wand_btn.button_pressed else normal_color
	_brush_erase_btn.self_modulate = active_color if _brush_erase_btn.button_pressed else normal_color
	if _recolor_btn:
		_recolor_btn.self_modulate = active_color if _recolor_btn.button_pressed else normal_color
	if _paint_btn:
		_paint_btn.self_modulate = active_color if _paint_btn.button_pressed else normal_color
	if _stamp_btn:
		_stamp_btn.self_modulate = active_color if _stamp_btn.button_pressed else normal_color
	if _text_btn:
		_text_btn.self_modulate = active_color if _text_btn.button_pressed else normal_color

func _on_wand_toggled(toggled: bool) -> void:
	_select_tool("wand" if toggled else "")

func _on_brush_toggled(toggled: bool) -> void:
	_select_tool("brush_erase" if toggled else "")

func _on_recolor_toggled(toggled: bool) -> void:
	_select_tool("recolor" if toggled else "")

func _on_paint_toggled(toggled: bool) -> void:
	_select_tool("paint" if toggled else "")

func _load_stamp_image(path: String) -> void:
	if not _canvas or not _current_tex:
		return
	var loaded_textures: Array[Texture2D] = []
	var res = load(path)
	if res is Texture2D:
		loaded_textures.append(res)
	elif res is SpriteFrames:
		var sf := res as SpriteFrames
		var anims := sf.get_animation_names()
		for anim in anims:
			var count := sf.get_frame_count(anim)
			for i in range(count):
				var tex := sf.get_frame_texture(anim, i)
				if tex:
					loaded_textures.append(tex)
	elif res is Image:
		loaded_textures.append(ImageTexture.create_from_image(res))
	elif res != null and res.has_method("get_image"):
		var img: Image = res.get_image()
		if img and not img.is_empty():
			loaded_textures.append(ImageTexture.create_from_image(img))

	if loaded_textures.is_empty():
		return

	for tex in loaded_textures:
		_stamp_frames.append(tex)

	_stamp_frame_idx = _stamp_frames.size() - 1
	var first_tex := loaded_textures[0]

	# First frame: set default transforms based on canvas center
	if _stamp_frames.size() == loaded_textures.size():
		var base_img: Image = _current_tex.get_image()
		if base_img:
			var center_x: float = base_img.get_width() / 2.0
			var center_y: float = base_img.get_height() / 2.0
			var pivot_x: float = first_tex.get_width() / 2.0
			var pivot_y: float = first_tex.get_height() / 2.0

			_canvas.frame_pos = Vector2(center_x, center_y)
			_canvas.frame_scale = Vector2.ONE
			_canvas.frame_rotation = 0.0
			_canvas.frame_pivot = Vector2(pivot_x, pivot_y)
			_canvas.frame_flip_h = false
			_canvas.frame_flip_v = false

			if _stamp_pos_x: _stamp_pos_x.set_value_no_signal(center_x)
			if _stamp_pos_y: _stamp_pos_y.set_value_no_signal(center_y)
			if _stamp_scale_x: _stamp_scale_x.set_value_no_signal(1.0)
			if _stamp_scale_y: _stamp_scale_y.set_value_no_signal(1.0)
			if _stamp_pivot_x: _stamp_pivot_x.set_value_no_signal(pivot_x)
			if _stamp_pivot_y: _stamp_pivot_y.set_value_no_signal(pivot_y)
			if _stamp_rot: _stamp_rot.set_value_no_signal(0.0)

	_update_stamp_frame()
	_select_tool("stamp")

func _update_stamp_frame() -> void:
	if _stamp_frames.is_empty() or not _canvas:
		return
	_stamp_frame_idx = clamp(_stamp_frame_idx, 0, _stamp_frames.size() - 1)
	var curr_tex: Texture2D = _stamp_frames[_stamp_frame_idx]
	_canvas.stamp_tex = curr_tex

	if curr_tex:
		var pivot_x: float = curr_tex.get_width() / 2.0
		var pivot_y: float = curr_tex.get_height() / 2.0
		_canvas.frame_pivot = Vector2(pivot_x, pivot_y)
		if _stamp_pivot_x: _stamp_pivot_x.set_value_no_signal(pivot_x)
		if _stamp_pivot_y: _stamp_pivot_y.set_value_no_signal(pivot_y)

	_canvas.queue_redraw()
	if _stamp_frame_label:
		_stamp_frame_label.text = "%d/%d" % [_stamp_frame_idx + 1, _stamp_frames.size()]
	if _stamp_prev_frame_btn:
		_stamp_prev_frame_btn.disabled = (_stamp_frame_idx == 0)
	if _stamp_next_frame_btn:
		_stamp_next_frame_btn.disabled = (_stamp_frame_idx >= _stamp_frames.size() - 1)

func _assign_material_to_selected(path: String) -> void:
	if not _canvas or _canvas.selected_indices.size() != 1:
		return
	var idx: int = _canvas.selected_indices[0]
	if idx < 0 or idx >= _canvas.rects.size():
		return
	
	_push_slices_state()
	while _canvas.slice_materials.size() <= idx:
		_canvas.slice_materials.append("")
	_canvas.slice_materials[idx] = path
	_update_props()
	_refresh_list()

func _on_canvas_stamp_pos_changed(pos: Vector2) -> void:
	if _stamp_pos_x: _stamp_pos_x.set_value_no_signal(pos.x)
	if _stamp_pos_y: _stamp_pos_y.set_value_no_signal(pos.y)

func _on_canvas_stamp_rotation_changed(deg: float) -> void:
	if _stamp_rot: _stamp_rot.set_value_no_signal(fmod(deg, 360.0))

func _on_canvas_stamp_scale_changed(sc: Vector2) -> void:
	if _stamp_scale_x: _stamp_scale_x.set_value_no_signal(sc.x)
	if _stamp_scale_y: _stamp_scale_y.set_value_no_signal(sc.y)

func _on_stamp_prop_changed() -> void:
	if not _canvas or not _canvas.stamp_tex:
		return
	_canvas.stamp_pos = Vector2(_stamp_pos_x.value, _stamp_pos_y.value)
	_canvas.stamp_scale = Vector2(_stamp_scale_x.value, _stamp_scale_y.value)
	_canvas.stamp_rotation = deg_to_rad(_stamp_rot.value)
	_canvas.stamp_pivot = Vector2(_stamp_pivot_x.value, _stamp_pivot_y.value)
	_canvas.queue_redraw()

func _apply_stamp() -> void:
	if not _current_tex or _current_tex_path.is_empty() or not _canvas or not _canvas.frame_tex:
		return
	_push_image_state()
	_ensure_edited_path()
	var base_img: Image = _current_tex.get_image()
	var frame_img: Image = _canvas.frame_tex.get_image()
	if not base_img or not frame_img:
		return
	
	var order_behind: bool = (_order_opt.selected == 1) if _order_opt else false

	var result := _BgRemover.paste_frame_transformed(
		base_img,
		frame_img,
		_canvas.frame_pos,
		_canvas.frame_scale,
		_canvas.frame_rotation,
		_canvas.frame_pivot,
		_canvas.frame_flip_h,
		_canvas.frame_flip_v,
		order_behind
	)
	
	if result == null or result.is_empty():
		return
		
	var new_tex := ImageTexture.create_from_image(result)
	_current_tex = new_tex
	_canvas.update_texture(new_tex)
	_save_edited_texture()
	
	_select_tool("")

func _cancel_stamp() -> void:
	_select_tool("")

func _on_brush_erase_clicked(img_pos: Vector2i) -> void:
	_push_image_state()
	_ensure_edited_path()
	_do_brush_erase(img_pos)

func _on_brush_erase_dragged(img_pos: Vector2i) -> void:
	_do_brush_erase(img_pos)

func _on_brush_erase_released() -> void:
	_save_edited_texture()

func _do_brush_erase(img_pos: Vector2i) -> void:
	if not _current_tex or _current_tex_path.is_empty():
		return
	var src_img: Image = _current_tex.get_image()
	if src_img == null or src_img.is_empty():
		return
	# Kopya üzerinde çalış — brush_erase in-place değiştirir
	var work_img := src_img.duplicate()
	var b_size: int = 8
	if _brush_size_spin != null:
		b_size = int(_brush_size_spin.value)
	var is_sq: bool = _canvas.brush_is_square if _canvas else false
	var result := _BgRemover.brush_erase(work_img, img_pos.x, img_pos.y, b_size, is_sq)
	if result == null or result.is_empty():
		return

	var new_tex := ImageTexture.create_from_image(result)
	_current_tex = new_tex
	_canvas.update_texture(new_tex)

func _on_brush_paint_clicked(img_pos: Vector2i) -> void:
	_push_image_state()
	_ensure_edited_path()
	_do_brush_paint(img_pos)

func _on_brush_paint_dragged(img_pos: Vector2i) -> void:
	_do_brush_paint(img_pos)

func _on_brush_paint_released() -> void:
	_save_edited_texture()

func _do_brush_paint(img_pos: Vector2i) -> void:
	if not _current_tex or _current_tex_path.is_empty():
		return
	var src_img: Image = _current_tex.get_image()
	if src_img == null or src_img.is_empty():
		return
	# Kopya üzerinde çalış — brush_paint in-place değiştirir
	var work_img := src_img.duplicate()
	var b_size: int = 8
	if _brush_size_spin != null:
		b_size = int(_brush_size_spin.value)
	var col := _color_picker.color if _color_picker else Color.WHITE
	var is_sq: bool = _canvas.brush_is_square if _canvas else false
	var order_behind: bool = (_order_opt.selected == 1) if _order_opt else false
	var result := _BgRemover.brush_paint(work_img, img_pos.x, img_pos.y, b_size, col, is_sq, order_behind)
	if result == null or result.is_empty():
		return

	var new_tex := ImageTexture.create_from_image(result)
	_current_tex = new_tex
	_canvas.update_texture(new_tex)

func _on_recolor_clicked(img_pos: Vector2i) -> void:
	if not _current_tex or _current_tex_path.is_empty():
		return
	var src_img: Image = _current_tex.get_image()
	if src_img == null or src_img.is_empty():
		return
	_push_image_state()
	_ensure_edited_path()
	var col := _color_picker.color if _color_picker else Color.WHITE
	var result := _BgRemover.magic_wand_recolor(src_img, img_pos.x, img_pos.y, col, _bg_tolerance)
	if result == null or result.is_empty():
		return
	var abs_out := ProjectSettings.globalize_path(_current_tex_path)
	var err := result.save_png(abs_out)
	if err != OK:
		push_error("SpriteSlicer: Could not save edited PNG: " + abs_out)
		return
	var new_tex := ImageTexture.create_from_image(result)
	_current_tex = new_tex
	_canvas.update_texture(new_tex)

func _on_erase_clicked(img_pos: Vector2i) -> void:
	if not _current_tex or _current_tex_path.is_empty():
		return
	var src_img: Image = _current_tex.get_image()
	if src_img == null or src_img.is_empty():
		return
	_push_image_state()
	_ensure_edited_path()
	var result := _BgRemover.magic_wand_erase(src_img, img_pos.x, img_pos.y, _bg_tolerance)
	if result == null or result.is_empty():
		return

	var abs_out := ProjectSettings.globalize_path(_current_tex_path)
	var err := result.save_png(abs_out)
	if err != OK:
		push_error("SpriteSlicer: Could not save edited PNG back to disk: " + abs_out)
		return

	var new_tex := ImageTexture.create_from_image(result)
	_current_tex = new_tex
	_canvas.update_texture(new_tex)

func _ensure_edited_path() -> void:
	if _current_tex_path.is_empty():
		return
	var base_dir := _current_tex_path.get_base_dir()
	var base_name := _current_tex_path.get_file().get_basename()
	if not (base_name.ends_with("_nobg") or base_name.ends_with("_edited")):
		_current_tex_path = base_dir + "/" + base_name + "_edited.png"
		_path_label.text = base_name + "_edited.png"

func _save_edited_texture() -> void:
	if not _current_tex or _current_tex_path.is_empty():
		return
	var abs_out := ProjectSettings.globalize_path(_current_tex_path)
	var err: Error = _current_tex.get_image().save_png(abs_out)
	if err != OK:
		push_error("SpriteSlicer: Could not save edited PNG back to disk: " + abs_out)

func _on_remove_bg() -> void:
	if _current_tex_path.is_empty():
		push_error("SpriteSlicer: No texture path available.")
		return
	_push_image_state()

	var abs_src: String = ProjectSettings.globalize_path(_current_tex_path)
	var src_img: Image = Image.load_from_file(abs_src)
	if src_img == null or src_img.is_empty():
		push_error("SpriteSlicer: Could not load file: " + abs_src)
		return

	var result: Image = _BgRemover.remove(src_img, _bg_tolerance, true)
	if result == null or result.is_empty():
		push_error("SpriteSlicer: Background removal returned empty image.")
		return

	var base_dir: String = _current_tex_path.get_base_dir()
	var base_name: String = _current_tex_path.get_file().get_basename()
	var res_out: String = base_dir + "/" + base_name + "_nobg.png"
	var abs_out: String = ProjectSettings.globalize_path(res_out)
	var err: Error = result.save_png(abs_out)
	if err != OK:
		push_error("SpriteSlicer: Could not save PNG: " + abs_out + " (error " + str(err) + ")")
		return

	var new_tex := ImageTexture.create_from_image(result)
	_current_tex      = new_tex
	_current_tex_path = res_out
	_path_label.text  = base_name + "_nobg.png"
	_canvas.update_texture(new_tex)
	_canvas.set_zoom(_zoom)
	_refresh_list()
	_update_props()
	if _preview_player:
		_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)

	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.update_file(res_out)

func _on_delete_selected() -> void:
	if _canvas.selected_indices.is_empty():
		return
	# No _push_slices_state() here - _delete_selected_rects() emits slice_action_started
	_canvas._delete_selected_rects()

func _on_lock_toggle() -> void:
	if not _canvas or _canvas.selected_indices.is_empty():
		return
	_push_slices_state()
	var any_unlocked := false
	for idx in _canvas.selected_indices:
		if idx < _canvas.locked_states.size() and not _canvas.locked_states[idx]:
			any_unlocked = true
			break
	for idx in _canvas.selected_indices:
		if idx < _canvas.locked_states.size():
			_canvas.locked_states[idx] = any_unlocked
	_canvas.queue_redraw()
	_refresh_list()
	_update_props()




# --- Signal connections ---

func _on_canvas_zoom_changed(z: float) -> void:
	_zoom = z
	_zoom_label.text = str(int(round(z * 100))) + "%"

func _on_canvas_selection_changed(indices: Array) -> void:
	_sync_list_highlight(indices)
	_update_props()
	if _preview_player:
		_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)

func _on_rects_changed() -> void:
	_refresh_list()
	_update_props()
	if _preview_player:
		_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)

func _on_rects_updated(indices: Array) -> void:
	for idx in indices:
		_update_list_item(idx)
	_update_props()
	if _preview_player:
		_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)

func _on_list_item_selected(_index: int) -> void:
	var selected: PackedInt32Array = _slice_list.get_selected_items()
	var canvas_selected: Array = []
	for idx in selected:
		canvas_selected.append(idx)
	_canvas.selected_indices = canvas_selected
	_canvas.queue_redraw()
	_update_props()
	if _preview_player:
		_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)

func _on_prop_changed() -> void:
	if _updating_props:
		return
	if _canvas.selected_indices.size() != 1:
		return
	var idx: int = _canvas.selected_indices[0]
	if idx < 0 or idx >= _canvas.rects.size():
		return
	_push_slices_state()
	_canvas.rects[idx] = Rect2(_spin_x.value, _spin_y.value, _spin_w.value, _spin_h.value)
	_canvas.queue_redraw()
	_update_list_item(idx)

func _sort_indices_spatially(indices: Array) -> Array:
	var sorted := indices.duplicate()
	sorted.sort_custom(func(a_idx: int, b_idx: int) -> bool:
		var a_rect: Rect2 = _canvas.rects[a_idx]
		var b_rect: Rect2 = _canvas.rects[b_idx]
		var y_diff := abs(a_rect.position.y - b_rect.position.y)
		if y_diff < 12.0:
			return a_rect.position.x < b_rect.position.x
		return a_rect.position.y < b_rect.position.y
	)
	return sorted

func _on_name_changed(new_text: String) -> void:
	if _updating_props:
		return
	if _canvas.selected_indices.is_empty():
		return
	if _canvas.selected_indices.size() == 1:
		var idx: int = _canvas.selected_indices[0]
		if idx < 0 or idx >= _canvas.slice_names.size():
			return
		_canvas.slice_names[idx] = new_text
		_update_list_item(idx)
	else:
		var sorted_sel := _sort_indices_spatially(_canvas.selected_indices)
		var num_selected := sorted_sel.size()
		var pad_len := 1
		if num_selected >= 100:
			pad_len = 3
		elif num_selected >= 10:
			pad_len = 2

		for i in range(num_selected):
			var idx: int = sorted_sel[i]
			if idx < 0 or idx >= _canvas.slice_names.size():
				continue
			var suffix := str(i)
			while suffix.length() < pad_len:
				suffix = "0" + suffix
			_canvas.slice_names[idx] = new_text + "_" + suffix
			_update_list_item(idx)


# --- Helper methods ---

func _refresh_list() -> void:
	_slice_list.clear()
	for i in range(_canvas.rects.size()):
		_slice_list.add_item(_item_text(i))
	_count_label.text = "SLICES (%d)" % _canvas.rects.size()

func _update_list_item(idx: int) -> void:
	if idx >= 0 and idx < _slice_list.item_count:
		_slice_list.set_item_text(idx, _item_text(idx))

func _item_text(i: int) -> String:
	var r: Rect2 = _canvas.rects[i]
	var custom_name = ""
	if i < _canvas.slice_names.size() and _canvas.slice_names[i] != "":
		custom_name = "[" + _canvas.slice_names[i] + "] "
	var prefix := ""
	if i < _canvas.locked_states.size() and _canvas.locked_states[i]:
		prefix = "🔒 "
	return "%s%sSlice %d  (%d,%d)  %dx%d" % [prefix, custom_name, i,
		int(r.position.x), int(r.position.y),
		int(r.size.x),     int(r.size.y)]

func _sync_list_highlight(indices: Array) -> void:
	for i in range(_slice_list.item_count):
		_slice_list.deselect(i)
	for idx in indices:
		if idx >= 0 and idx < _slice_list.item_count:
			_slice_list.select(idx)

func _update_props() -> void:
	if _canvas.selected_indices.is_empty():
		_props_box.visible = false
		return
	_props_box.visible = true
	_updating_props = true
	
	if _merge_btn:
		_merge_btn.disabled = _canvas.selected_indices.size() < 2

	if _lock_btn:
		var all_locked := true
		for idx in _canvas.selected_indices:
			if idx < _canvas.locked_states.size() and not _canvas.locked_states[idx]:
				all_locked = false
				break
		_lock_btn.text = "Unlock Slices" if all_locked else "Lock Slices"

	if _canvas.selected_indices.size() == 1:
		var idx: int = _canvas.selected_indices[0]
		if idx < 0 or idx >= _canvas.rects.size():
			_props_box.visible = false
			_updating_props = false
			return
		_props_grid.visible = true
		if _mat_box:
			_mat_box.visible = true
		var r: Rect2 = _canvas.rects[idx]
		var cname = ""
		if idx < _canvas.slice_names.size():
			cname = _canvas.slice_names[idx]
		_name_edit.text = cname
		_name_edit.placeholder_text = "Custom Name"
		
		var mat_path := ""
		if idx < _canvas.slice_materials.size():
			mat_path = _canvas.slice_materials[idx]
		if _mat_edit:
			_mat_edit.text = mat_path.get_file()
			_mat_edit.tooltip_text = mat_path if mat_path != "" else "No Material/Shader"
			
		_spin_x.value = r.position.x
		_spin_y.value = r.position.y
		_spin_w.value = r.size.x
		_spin_h.value = r.size.y
	else:
		_props_grid.visible = false
		if _mat_box:
			_mat_box.visible = false
		_name_edit.text = ""
		_name_edit.placeholder_text = "Seq Name (e.g. chest)"
	_updating_props = false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		var vp := get_viewport()
		var focus_owner: Control = vp.gui_get_focus_owner() if vp else null
		if focus_owner is LineEdit or focus_owner is TextEdit:
			return

		var is_mac: bool = OS.get_name() == "macOS"
		var is_ctrl: bool = key_event.ctrl_pressed or (is_mac and key_event.meta_pressed)

		if is_ctrl and key_event.keycode == KEY_Z:
			if key_event.shift_pressed:
				_redo()
			else:
				_undo()
			get_viewport().set_input_as_handled()
		elif is_ctrl and key_event.keycode == KEY_Y:
			_redo()
			get_viewport().set_input_as_handled()

func _push_history_state(state: Dictionary) -> void:
	if _history:
		_history.push_state(state)

func _push_image_state() -> void:
	if not _current_tex:
		return
	var img: Image = _current_tex.get_image()
	if img and not img.is_empty():
		var img_copy = Image.new()
		img_copy.copy_from(img)
		_push_history_state({
			"type": "image",
			"image": img_copy,
			"path": _current_tex_path,
			"rects": _canvas.rects.duplicate()
		})

func _push_slices_state() -> void:
	if not _canvas:
		return
	_push_history_state({
		"type": "slices",
		"rects": _canvas.rects.duplicate(),
		"slice_names": _canvas.slice_names.duplicate(),
		"slice_materials": _canvas.slice_materials.duplicate(),
		"selected_indices": _canvas.selected_indices.duplicate(),
		"locked_states": _canvas.locked_states.duplicate()
	})

func _on_history_changed(can_u: bool, can_r: bool) -> void:
	if _undo_btn: _undo_btn.disabled = not can_u
	if _redo_btn: _redo_btn.disabled = not can_r

func _undo() -> void:
	if _history:
		_history.undo(_apply_history_state)

func _redo() -> void:
	if _history:
		_history.redo(_apply_history_state)

func _apply_history_state(state: Dictionary) -> Dictionary:
	var current_state := {}

	if state["type"] == "image":
		var img: Image = _current_tex.get_image()
		if img and not img.is_empty():
			var img_copy := Image.new()
			img_copy.copy_from(img)
			current_state = {
				"type": "image",
				"image": img_copy,
				"path": _current_tex_path,
				"rects": _canvas.rects.duplicate()
			}

		var prev_img: Image = state["image"]
		var prev_path: String = state["path"]
		var abs_out := ProjectSettings.globalize_path(prev_path)
		var err = prev_img.save_png(abs_out)
		if err == OK:
			_current_tex_path = prev_path
			_path_label.text = prev_path.get_file()
			var new_tex := ImageTexture.create_from_image(prev_img)
			_current_tex = new_tex
			_canvas.load_texture(new_tex)
			if state.has("rects"):
				_canvas.rects = state["rects"].duplicate()
			_canvas.queue_redraw()
			if _preview_player:
				_preview_player.sync_preview(new_tex, _canvas.rects, _canvas.selected_indices)

	elif state["type"] == "slices":
		current_state = {
			"type": "slices",
			"rects": _canvas.rects.duplicate(),
			"slice_names": _canvas.slice_names.duplicate(),
			"slice_materials": _canvas.slice_materials.duplicate(),
			"selected_indices": _canvas.selected_indices.duplicate(),
			"locked_states": _canvas.locked_states.duplicate()
		}

		_canvas.rects = state["rects"].duplicate()
		_canvas.slice_names = state["slice_names"].duplicate()
		_canvas.slice_materials = state.get("slice_materials", []).duplicate()
		while _canvas.slice_materials.size() < _canvas.rects.size():
			_canvas.slice_materials.append("")
		while _canvas.slice_names.size() < _canvas.rects.size():
			_canvas.slice_names.append("")

		_canvas.selected_indices = state["selected_indices"].duplicate()
		_canvas.locked_states = state["locked_states"].duplicate()
		_canvas.queue_redraw()
		_refresh_list()
		_update_props()
		if _preview_player:
			_preview_player.sync_preview(_current_tex, _canvas.rects, _canvas.selected_indices)

	return current_state

func _load_font_file(path: String) -> void:
	var res = load(path)
	if res is Font:
		_current_font = res
		_current_font_path = path
	else:
		var ff := FontFile.new()
		var abs_p := ProjectSettings.globalize_path(path)
		var err := ff.load_dynamic_font(abs_p)
		if err == OK:
			_current_font = ff
			_current_font_path = path

	if _font_path_label:
		_font_path_label.text = path.get_file() if _current_font else "Default Font"
		_font_path_label.tooltip_text = path if _current_font else "Default Font"

	_update_text_preview()

func _update_text_preview() -> void:
	if not _canvas or not _current_tex:
		return
	var txt := _text_input.text if _text_input else ""
	if txt.strip_edges() == "":
		_canvas.frame_tex = null
		_canvas.queue_redraw()
		return

	var f_size := int(_text_font_size_spin.value) if _text_font_size_spin else 24
	var col := _text_color_picker.color if _text_color_picker else Color.WHITE

	var img: Image = await _render_text_image(txt, _current_font, f_size, col)
	if img and not img.is_empty():
		var tex := ImageTexture.create_from_image(img)
		var pivot_x: float = tex.get_width() / 2.0
		var pivot_y: float = tex.get_height() / 2.0

		var is_first_text_init: bool = (_canvas.frame_tex == null or not _canvas.frame_mode)
		if is_first_text_init:
			var base_img: Image = _current_tex.get_image()
			if base_img:
				var center_x: float = base_img.get_width() / 2.0
				var center_y: float = base_img.get_height() / 2.0

				_canvas.frame_pos = Vector2(center_x, center_y)
				_canvas.frame_scale = Vector2.ONE
				_canvas.frame_rotation = 0.0

				if _stamp_pos_x: _stamp_pos_x.set_value_no_signal(center_x)
				if _stamp_pos_y: _stamp_pos_y.set_value_no_signal(center_y)
				if _stamp_scale_x: _stamp_scale_x.set_value_no_signal(1.0)
				if _stamp_scale_y: _stamp_scale_y.set_value_no_signal(1.0)
				if _stamp_rot: _stamp_rot.set_value_no_signal(0.0)

		# ALWAYS keep frame_pivot aligned with the text texture center
		_canvas.frame_pivot = Vector2(pivot_x, pivot_y)
		if _stamp_pivot_x: _stamp_pivot_x.set_value_no_signal(pivot_x)
		if _stamp_pivot_y: _stamp_pivot_y.set_value_no_signal(pivot_y)

		_canvas.frame_tex = tex
		_canvas.frame_mode = true
		_canvas.queue_redraw()

## Renders text into an Image using TextLine (no SubViewport/await needed).
## Works in @tool context without a scene tree.
func _render_text_image(text: String, font: Font, font_size: int, color: Color) -> Image:
	if text.strip_edges() == "":
		return null

	var font_to_use: Font = font
	if font_to_use == null:
		font_to_use = ThemeDB.fallback_font
	if font_to_use == null:
		return null

	# Build a TextLine to measure the text precisely
	var tl := TextLine.new()
	tl.add_string(text, font_to_use, font_size)

	var text_w: float = tl.get_line_width()
	var ascent: float  = tl.get_line_ascent()
	var descent: float = tl.get_line_descent()
	var total_h: float = ascent + descent

	var pad := 8
	var w := int(ceil(text_w)) + pad * 2
	var h := int(ceil(total_h)) + pad * 2
	if w <= 4 or h <= 4:
		return null

	# Create a transparent image and draw the text onto it using a
	# temporary offscreen Control inside an editor SubViewport when available,
	# or fall back to a simple solid-color block when the scene tree is absent.
	var root: Window = get_tree().root if get_tree() else null
	if root == null:
		# Fallback: solid-color rectangle (no scene tree available)
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(color)
		return img

	# Full path: render via Label in a SubViewport
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font_to_use)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(w, h)
	label.size = Vector2(w, h)

	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.size = Vector2i(w, h)
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.add_child(label)
	root.add_child(vp)
	await RenderingServer.frame_post_draw

	var tex := vp.get_texture()
	var img: Image = null
	if tex:
		img = tex.get_image()
	root.remove_child(vp)
	vp.free()
	return img
