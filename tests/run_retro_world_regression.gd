extends SceneTree

## 渲染状态随窗口尺寸更新，暂停时仍生效，退出关卡或关闭效果时完整恢复。
const EFFECT := preload("res://scenes/environment/retro_world_effect.tscn")
var _passed := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("RETRO WORLD FAILED: " + message)


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = 0.8
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.use_taa = true
	viewport.use_debanding = true
	root.add_child(viewport)
	var effect := EFFECT.instantiate()
	viewport.add_child(effect)
	await process_frame
	_check(is_equal_approx(viewport.scaling_3d_scale, 0.5) and viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_NEAREST, "3D renders at 360 lines with nearest upscaling")
	_check(not viewport.use_taa and not viewport.use_debanding and viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "temporal and spatial smoothing leave pixels and dithering intact")
	_check(effect.layer < 0 and effect.get_node("Grade").mouse_filter == Control.MOUSE_FILTER_IGNORE, "grading precedes HUD and never captures mouse input")
	var material := effect.get_node("Grade").material as ShaderMaterial
	_check(material.get_shader_parameter("render_size") == Vector2(640, 360), "dither grid matches the low resolution framebuffer")
	viewport.size = Vector2i(960, 640)
	await process_frame
	_check(is_equal_approx(viewport.scaling_3d_scale, 0.5625) and material.get_shader_parameter("render_size") == Vector2(540, 360), "minimum window preserves aspect and 360 render lines")
	paused = true
	viewport.size = Vector2i(2048, 1152)
	await process_frame
	_check(is_equal_approx(viewport.scaling_3d_scale, 0.3125), "paused window resizing still updates render scale")
	paused = false
	effect.enabled = false
	_check(is_equal_approx(viewport.scaling_3d_scale, 0.8) and viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and not effect.visible, "disabling restores original resolution and hides grading")
	_check(viewport.use_taa and viewport.use_debanding and viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "disabling restores original antialiasing settings")
	effect.enabled = true
	viewport.size = Vector2i(320, 180)
	await process_frame
	_check(viewport.scaling_3d_scale == 1.0 and material.get_shader_parameter("render_size") == Vector2(320, 180), "small render targets are never supersampled")
	effect.queue_free()
	await process_frame
	await process_frame
	_check(is_equal_approx(viewport.scaling_3d_scale, 0.8) and viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and viewport.use_taa and viewport.use_debanding, "leaving world restores viewport settings for menus and next scenes")
	viewport.queue_free()
	await process_frame
	print("RETRO WORLD RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
