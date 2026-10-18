extends CanvasLayer

## 低分辨率 3D 与复古调色位于 HUD 之前；退出关卡时恢复视口。
@export var enabled := true:
	set(value):
		enabled = value
		if is_node_ready():
			_apply_state()
@export_range(180, 720, 1) var render_height := 360:
	set(value):
		render_height = value
		if is_node_ready():
			_apply_state()

var _viewport: Viewport
var _previous := {}


func _ready() -> void:
	_viewport = get_viewport()
	for property in ["scaling_3d_scale", "scaling_3d_mode", "msaa_3d", "screen_space_aa", "use_taa", "use_debanding"]:
		_previous[property] = _viewport.get(property)
	_viewport.size_changed.connect(_apply_state)
	_apply_state()


func _apply_state() -> void:
	visible = enabled
	if not enabled:
		_restore_viewport()
		return
	# Root size is the rendered framebuffer; the visible rect can be UI-scaled.
	var height := maxf(_viewport.size.y, 1.0)
	var scale := clampf(float(render_height) / height, 0.1, 1.0)
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_NEAREST
	_viewport.scaling_3d_scale = scale
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	_viewport.use_debanding = false
	var size := Vector2(_viewport.size) * scale
	var screen_material := $Grade.material as ShaderMaterial
	screen_material.set_shader_parameter("render_size", Vector2(maxf(floor(size.x), 1.0), maxf(floor(size.y), 1.0)))


func _restore_viewport() -> void:
	if not is_instance_valid(_viewport):
		return
	for property in _previous:
		_viewport.set(property, _previous[property])


func _exit_tree() -> void:
	_restore_viewport()
