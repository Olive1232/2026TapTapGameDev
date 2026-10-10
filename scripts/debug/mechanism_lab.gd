extends Node3D

## 白模机关试验场；调试解锁只作用于此场景。
@onready var grabber: Grabber = $Player/Camera3D/Grabber
@onready var platform: WeightPlatform = $WeightPlatform
@onready var gate: LiftGate = $LiftGate
var _completed := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.keycode == KEY_E:
			grabber.apply_upgrade("charged_throw")
		elif event.physical_keycode == KEY_R or event.keycode == KEY_R:
			get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	# 玩家可能在门完全升起前进入终点；持续检查，避免漏掉一次 entered。
	if not _completed and gate.is_open() and $Goal.overlaps_body($Player):
		_completed = true
	var status := "完成！已通过升降门。R 可重置再试。" if _completed else "将尸体投上左侧高处平台，再穿过右侧升降门。"
	if not _completed and gate.is_open():
		status = "升降门已开启，走进门后的绿色区域。"
	elif not _completed and platform.is_pressed():
		status = "平台已触发，升降门正在升起。"
	if gate.is_blocked():
		status = "门的移动路径被挡住，移开障碍后会继续。"
	$HUD/Objective.text = "配重平台与升降门\n" + status
	$HUD/Hint.text = "WASD 移动 · 空格跳跃 · 右键点按拿放 · Esc 暂停 · R 重置\n" + (grabber.get_throw_prompt() if grabber.charged_throw_enabled else "E 解锁投掷（仅本试验场）· 拿起尸体后长按右键，松开投出")
	$PlatformSign.text = "高处配重平台\n落稳尸体：%d · %s" % [platform.get_corpse_count(), "已触发" if platform.is_pressed() else "等待投掷"]
	$GateSign.text = "升降门\n" + ("已开启" if gate.is_open() else "由左侧平台控制")
	if $Player.position.y < -10.0:
		$Player.position = $SpawnPoint.position
		$Player.velocity = Vector3.ZERO
		$Player.reset_physics_interpolation()


func is_completed() -> bool:
	return _completed
