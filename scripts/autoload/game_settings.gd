extends Node

signal changed

const AtomicFile := preload("res://scripts/persistence/atomic_file.gd")
const DEFAULT_SENSITIVITY := 0.1
const MIN_SENSITIVITY := 0.02
const MAX_SENSITIVITY := 0.5

var settings_path: String = "user://settings.cfg"
var fullscreen: bool = false
var mouse_sensitivity: float = DEFAULT_SENSITIVITY


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	fullscreen = false
	mouse_sensitivity = DEFAULT_SENSITIVITY
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		var saved_fullscreen: Variant = config.get_value("display", "fullscreen", false)
		if saved_fullscreen is bool:
			fullscreen = saved_fullscreen
		var saved_sensitivity: Variant = config.get_value("input", "mouse_sensitivity", DEFAULT_SENSITIVITY)
		if (saved_sensitivity is float or saved_sensitivity is int) and is_finite(float(saved_sensitivity)):
			mouse_sensitivity = clampf(float(saved_sensitivity), MIN_SENSITIVITY, MAX_SENSITIVITY)
	_apply_window_mode()
	changed.emit()


func set_fullscreen(value: bool) -> Error:
	fullscreen = value
	_apply_window_mode()
	changed.emit()
	return save_settings()


func set_mouse_sensitivity(value: float) -> Error:
	if not is_finite(value):
		return ERR_INVALID_PARAMETER
	mouse_sensitivity = clampf(value, MIN_SENSITIVITY, MAX_SENSITIVITY)
	changed.emit()
	return save_settings()


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	return AtomicFile.write_text(settings_path, config.encode_to_text())


func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not fullscreen:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
