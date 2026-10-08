extends Control

signal closed

@onready var _mode: OptionButton = %WindowMode
@onready var _sensitivity: HSlider = %Sensitivity
@onready var _value: Label = %SensitivityValue
@onready var _status: Label = %SettingsStatus


func _ready() -> void:
	_mode.item_selected.connect(_on_mode_selected)
	_sensitivity.value_changed.connect(_on_sensitivity_changed)
	%BackButton.pressed.connect(close)


func open() -> void:
	_mode.select(1 if GameSettings.fullscreen else 0)
	_sensitivity.set_value_no_signal(GameSettings.mouse_sensitivity / GameSettings.DEFAULT_SENSITIVITY)
	_update_value()
	_status.text = "设置会自动保存"
	show()
	_mode.grab_focus()


func close() -> void:
	hide()
	closed.emit()


func _on_mode_selected(index: int) -> void:
	_show_save_result(GameSettings.set_fullscreen(index == 1))


func _on_sensitivity_changed(value: float) -> void:
	_show_save_result(GameSettings.set_mouse_sensitivity(value * GameSettings.DEFAULT_SENSITIVITY))
	_update_value()


func _update_value() -> void:
	_value.text = "%.2f×" % _sensitivity.value


func _show_save_result(error: Error) -> void:
	_status.text = "设置已保存" if error == OK else "设置已生效，但保存失败"
	if error == OK and GameSettings.fullscreen and DisplayServer.get_name() != "headless" and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		_status.text = "全屏设置已保存，请在独立窗口运行"
