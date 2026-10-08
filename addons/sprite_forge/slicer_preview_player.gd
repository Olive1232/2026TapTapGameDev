@tool
extends VBoxContainer

var current_tex: Texture2D = null
var rects: Array[Rect2] = []
var selected_indices: Array = []

var _preview_playing: bool = false
var _preview_fps: float = 8.0
var _preview_frame_time: float = 0.0
var _preview_frame_idx: int = 0
var _preview_indices: Array = []

# UI references
var _preview_rect: TextureRect
var _preview_atlas: AtlasTexture
var _preview_play_btn: Button
var _preview_fps_spin: SpinBox
var _preview_label: Label

var _preview_bg_color: ColorRect
var _preview_bg_checker: TextureRect

func _ready() -> void:
	set_process(false)
	add_theme_constant_override("separation", 4)
	
	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 5)
	add_child(title_hbox)
	
	var title := Label.new()
	title.text = "Animation Preview"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title)
	
	var bg_option := OptionButton.new()
	bg_option.add_item("BG: Trans")
	bg_option.add_item("BG: Black")
	bg_option.add_item("BG: White")
	bg_option.selected = 0
	bg_option.item_selected.connect(_on_bg_selected)
	title_hbox.add_child(bg_option)
	
	var bg_panel := PanelContainer.new()
	bg_panel.custom_minimum_size = Vector2(0, 120)
	bg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_panel.size_flags_vertical = Control.SIZE_FILL
	add_child(bg_panel)
	
	# 1. Color background (Black/White)
	_preview_bg_color = ColorRect.new()
	_preview_bg_color.color = Color.BLACK
	_preview_bg_color.visible = false
	bg_panel.add_child(_preview_bg_color)
	
	# 2. Checkerboard background (Transparent)
	_preview_bg_checker = TextureRect.new()
	_preview_bg_checker.stretch_mode = TextureRect.STRETCH_TILE
	_preview_bg_checker.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	
	# Create checkerboard pattern
	var cell := 6
	var img := Image.create(cell * 2, cell * 2, false, Image.FORMAT_RGB8)
	var c0 := Color(0.18, 0.18, 0.18)
	var c1 := Color(0.24, 0.24, 0.24)
	for y in range(cell * 2):
		for x in range(cell * 2):
			var is_c0 = ((x < cell) and (y < cell)) or ((x >= cell) and (y >= cell))
			img.set_pixel(x, y, c0 if is_c0 else c1)
	_preview_bg_checker.texture = ImageTexture.create_from_image(img)
	bg_panel.add_child(_preview_bg_checker)
	
	# 3. Actual sprite rect
	_preview_rect = TextureRect.new()
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bg_panel.add_child(_preview_rect)
	
	_preview_atlas = AtlasTexture.new()
	_preview_rect.texture = _preview_atlas
	
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 5)
	add_child(controls)
	
	_preview_play_btn = Button.new()
	_preview_play_btn.text = "Play"
	_preview_play_btn.pressed.connect(_on_preview_play_pressed)
	controls.add_child(_preview_play_btn)
	
	var fps_lbl := Label.new()
	fps_lbl.text = "FPS:"
	controls.add_child(fps_lbl)
	
	_preview_fps_spin = SpinBox.new()
	_preview_fps_spin.min_value = 1
	_preview_fps_spin.max_value = 60
	_preview_fps_spin.value = 8
	_preview_fps_spin.step = 1
	_preview_fps_spin.custom_minimum_size = Vector2(55, 0)
	_preview_fps_spin.value_changed.connect(func(v: float): _preview_fps = v)
	controls.add_child(_preview_fps_spin)
	
	_preview_label = Label.new()
	_preview_label.text = "Frame: -"
	_preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.add_child(_preview_label)

func _on_bg_selected(index: int) -> void:
	match index:
		0: # Transparent (checkerboard)
			_preview_bg_color.visible = false
			_preview_bg_checker.visible = true
		1: # Black
			_preview_bg_color.visible = true
			_preview_bg_color.color = Color.BLACK
			_preview_bg_checker.visible = false
		2: # White
			_preview_bg_color.visible = true
			_preview_bg_color.color = Color.WHITE
			_preview_bg_checker.visible = false

func sync_preview(tex: Texture2D, list_rects: Array[Rect2], sel_indices: Array) -> void:
	current_tex = tex
	rects = list_rects
	selected_indices = sel_indices
	_update_preview_indices()

func _process(delta: float) -> void:
	if not _preview_playing or _preview_indices.is_empty():
		set_process(false)
		return
	_preview_frame_time += delta
	var interval: float = 1.0 / max(1.0, _preview_fps)
	if _preview_frame_time >= interval:
		_preview_frame_time = 0.0
		_preview_frame_idx = (_preview_frame_idx + 1) % _preview_indices.size()
		_update_preview_texture()

func _on_preview_play_pressed() -> void:
	_preview_playing = !_preview_playing
	_preview_play_btn.text = "Pause" if _preview_playing else "Play"
	set_process(_preview_playing)
	if _preview_playing:
		_update_preview_indices()

func _update_preview_indices() -> void:
	var selected: Array = selected_indices.duplicate()
	if selected.is_empty():
		_preview_indices = []
		for i in range(rects.size()):
			_preview_indices.append(i)
	else:
		_preview_indices = _sort_indices_spatially(selected)
	
	if _preview_frame_idx >= _preview_indices.size():
		_preview_frame_idx = 0
	
	_update_preview_texture()

func _update_preview_texture() -> void:
	if not current_tex or _preview_indices.is_empty():
		_preview_atlas.atlas = null
		_preview_label.text = "Frame: -"
		return
		
	var idx: int = _preview_indices[_preview_frame_idx]
	if idx < 0 or idx >= rects.size():
		return
		
	var r: Rect2 = rects[idx]
	_preview_atlas.atlas = current_tex
	_preview_atlas.region = r
	_preview_label.text = "Frame: %d" % idx

func _sort_indices_spatially(indices: Array) -> Array:
	# Filter valid indices first, then sort directly — no intermediate Dictionary allocations
	var valid: Array[int] = []
	for idx in indices:
		if idx >= 0 and idx < rects.size():
			valid.append(idx)

	valid.sort_custom(func(a: int, b: int) -> bool:
		var ra: Rect2 = rects[a]
		var rb: Rect2 = rects[b]
		if abs(ra.position.y - rb.position.y) > 4:
			return ra.position.y < rb.position.y
		return ra.position.x < rb.position.x
	)
	return valid
