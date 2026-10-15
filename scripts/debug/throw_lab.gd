extends Node3D

## 独立试玩场景，不向正式地图免费授予升级或金币。
@onready var grabber: Grabber = $Player/Camera3D/Grabber


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.keycode == KEY_E:
			grabber.apply_upgrade("charged_throw")
		elif event.physical_keycode == KEY_R or event.keycode == KEY_R:
			get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	$HUD/Hint.text = "WASD 移动 / 攀爬 · 右键点按拿放 · R 重置\n" + (grabber.get_throw_prompt() if grabber.charged_throw_enabled else "E 解锁投掷（仅本调试场景）；正式地图商店售价 200 金币")
