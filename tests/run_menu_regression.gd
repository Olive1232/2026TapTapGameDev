extends SceneTree

## --headless --path . --script res://tests/run_menu_regression.gd -- --data-dir=<临时目录>
## --phase=write / read 两次独立进程验证跨启动持久化；默认验证完整菜单流程。
var _passed := 0
var _failed := 0
var _save
var _settings
var _flow
var _wallet
var _directory := ""
var _phase := "full"


func _initialize() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("MENU REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("MENU REGRESSION FAILED: " + message)


func _frames() -> void:
	await process_frame
	await process_frame


func _click(button: Control) -> void:
	var at := root.get_final_transform() * button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames()


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames()


func _write_raw(text: String) -> void:
	var file := FileAccess.open(_save.save_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _run() -> void:
	await process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data-dir="):
			_directory = argument.trim_prefix("--data-dir=")
		elif argument.begins_with("--phase="):
			_phase = argument.trim_prefix("--phase=")
	if _directory.is_empty():
		push_error("Use --data-dir pointing to an isolated test directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	_save = root.get_node("SaveGame")
	_settings = root.get_node("GameSettings")
	_flow = root.get_node("GameFlow")
	_wallet = root.get_node("Wallet")
	_save.save_path = _directory.path_join("savegame.json")
	_settings.settings_path = _directory.path_join("settings.cfg")
	if _phase == "write":
		_wallet.set_total(9007199254740993)
		_check(_save.save_game().ok, "persist exact large integer")
		_check(_settings.set_fullscreen(true) == OK, "persist fullscreen")
		_check(_settings.set_mouse_sensitivity(0.23) == OK, "persist sensitivity")
		_finish()
		return
	if _phase == "read":
		_settings.load_settings()
		_check(_settings.fullscreen, "fullscreen survives fresh process")
		_check(is_equal_approx(_settings.mouse_sensitivity, 0.23), "sensitivity survives fresh process")
		_check(_save.read_save().coins == 9007199254740993, "coins retain precision across process")
		_check(_flow.load_game().ok, "fresh process loads into game")
		await _frames()
		_check(_wallet.total == 9007199254740993, "loaded wallet retains exact integer")
		_check(is_equal_approx(current_scene.get_node("Player").mouse_sensitivity, 0.23), "new player reads persisted setting")
		_finish()
		return
	if _phase in ["quit_main", "quit_pause"]:
		_wallet.set_total(17)
		_check(_save.save_game().ok, "seed save before quit")
		_check(_flow.return_to_main_menu().ok, "open menu before quit")
		await _frames()
		var quit_button = current_scene.get_node("%QuitButton")
		if _phase == "quit_pause":
			_check(_flow.start_new_game().ok, "enter game before paused quit")
			await _frames()
			await _key(KEY_ESCAPE)
			_check(paused, "paused quit is available")
			quit_button = _flow.get_node("PauseMenu").get_node("%QuitButton")
		_wallet.set_total(53)
		_check(_save.read_save().coins == 17, "unsaved progress remains separate")
		print("QUIT BUTTON CHECK: phase=%s passed=%d failed=%d" % [_phase, _passed, _failed])
		_click(quit_button)
		await _frames()
		_check(false, "quit button should terminate the process")
		_finish()
		return

	# This suite only deletes files in its explicitly supplied test directory.
	for filename in ["savegame.json", "savegame.json.tmp", "settings.cfg"]:
		var path := _directory.path_join(filename)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_settings.load_settings()
	_check(not _settings.fullscreen and is_equal_approx(_settings.mouse_sensitivity, 0.1), "missing settings use defaults")
	_check(not _save.has_save() and not _save.read_save().ok, "missing save handled")
	_check(ProjectSettings.get_setting("application/run/main_scene") == _flow.MAIN_MENU, "project starts at menu")
	_check(_flow.return_to_main_menu().ok, "open main menu")
	await _frames()
	var menu = current_scene
	_check(menu.get_node("%LoadGameButton").disabled, "no save disables load")
	_check(Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "menu releases mouse")
	for button_name in ["NewGameButton", "LoadGameButton", "SettingsButton", "AboutButton", "QuitButton"]:
		_check(menu.get_node("%" + button_name) is Button, "main menu has " + button_name)
	# Check small-window containment; the actual render is also inspected in editor.
	root.size = Vector2i(960, 640)
	await _frames()
	_check(menu.get_node("%QuitButton").get_global_rect().end.y <= root.size.y, "all options fit minimum window")
	root.size = Vector2i(1280, 720)
	await _frames()
	await _click(menu.get_node("%AboutButton"))
	_check(menu.get_node("%About").visible and menu.get_node("%AboutText").text == "开发中...", "about placeholder")
	await _key(KEY_ESCAPE)
	_check(not menu.get_node("%About").visible and menu.get_node("%Menu").visible, "escape returns from about")
	await _click(menu.get_node("%SettingsButton"))
	var settings_ui = menu.get_node("%Settings")
	_check(settings_ui.visible, "main menu opens settings")
	settings_ui.get_node("%WindowMode").select(1)
	settings_ui.get_node("%WindowMode").item_selected.emit(1)
	await _frames()
	_check(_settings.fullscreen, "fullscreen option reaches settings")
	if DisplayServer.get_name() != "headless":
		_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "native fullscreen applied")
	settings_ui.get_node("%WindowMode").select(0)
	settings_ui.get_node("%WindowMode").item_selected.emit(0)
	await _frames()
	_check(not _settings.fullscreen, "windowed option reaches settings")
	if DisplayServer.get_name() != "headless":
		_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "native windowed applied")
		_check(not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS), "native window border restored")
	settings_ui.get_node("%Sensitivity").value = 2.5
	_check(is_equal_approx(_settings.mouse_sensitivity, 0.25), "slider applies sensitivity")
	_check(settings_ui.get_node("%SensitivityValue").text == "2.50×", "slider label updates")
	await _key(KEY_ESCAPE)
	_check(not settings_ui.visible and menu.get_node("%Menu").visible, "settings escape returns to main menu")

	# Malformed/unsupported values never alter the wallet or enter gameplay.
	_wallet.set_total(73)
	for text in ["not json", "[]", '{"version":2,"coins":"3"}', '{"version":true,"coins":"3"}', '{"version":1,"coins":"-1"}', '{"version":1,"coins":3}', '{"version":1,"coins":"9223372036854775808"}', '{"version":1,"coins":"001"}']:
		_write_raw(text)
		_check(not _flow.load_game().ok, "reject invalid save " + text)
		_check(_wallet.total == 73 and current_scene == menu, "bad save preserves current state")
	_wallet.set_total(17)
	_check(_save.save_game().ok, "replace corrupt save with valid save")
	_wallet.set_total(24)
	DirAccess.make_dir_absolute(_save.save_path + ".tmp")
	_check(not _save.save_game().ok, "write failure reported")
	_check(_save.read_save().coins == 17, "failed write keeps previous save")
	DirAccess.remove_absolute(_save.save_path + ".tmp")
	await _click(menu.get_node("%NewGameButton"))
	_check(_flow.is_in_game() and _wallet.total == 0, "new game starts from zero")
	_check(_save.read_save().coins == 17, "new game preserves disk save")
	if DisplayServer.get_name() != "headless":
		_check(Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED, "game captures mouse")
	var player = current_scene.get_node("Player")
	_check(is_equal_approx(player.mouse_sensitivity, 0.25), "player uses menu sensitivity")
	var sword = player.get_node("Camera3D/WeaponRig/WeaponPivot/Mount")
	var pose: Vector3 = player.rotation
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20, 0)
	motion.screen_relative = Vector2(20, 0)
	if DisplayServer.get_name() == "headless":
		# Headless 驱动不支持捕获鼠标；真实鼠标事件另在编辑器现场验证。
		player._look_delta = motion.relative
	else:
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
	await _frames()
	_check(is_equal_approx(angle_difference(pose.y, player.rotation.y), deg_to_rad(-5.0)), "sensitivity affects actual mouse look")
	player._look_delta = Vector2(100, 100)
	await _key(KEY_ESCAPE)
	_check(paused and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "escape pauses and releases mouse")
	_check(player._look_delta == Vector2.ZERO, "pause clears pending look input")
	var pause_menu = _flow.get_node("PauseMenu")
	_check(pause_menu.get_node("%Root").visible, "pause menu visible")
	for button_name in ["SaveButton", "MainMenuButton", "SettingsButton", "QuitButton"]:
		_check(pause_menu.get_node("%" + button_name) is Button, "pause menu has " + button_name)
	var before: Vector3 = player.global_position
	var scene_id: int = current_scene.get_instance_id()
	var old_sword_state: int = sword._state
	await _key(KEY_3)
	await _key(KEY_R)
	Input.action_press("Up")
	await create_timer(0.15, true, false, true).timeout
	Input.action_release("Up")
	_check(player.global_position.is_equal_approx(before), "pause stops movement and physics")
	_check(_wallet.total == 0 and current_scene.get_instance_id() == scene_id, "pause blocks wallet debug and reload")
	_wallet.add(481)
	await _click(pause_menu.get_node("%SaveButton"))
	_check(paused and _save.read_save().coins == 481, "save works while paused")
	_check(pause_menu.get_node("%SaveStatus").text.contains("存档成功"), "successful save feedback")
	_check(sword._state == old_sword_state, "menu click does not swing sword")
	await _click(pause_menu.get_node("%SettingsButton"))
	settings_ui = pause_menu.get_node("%Settings")
	_check(paused and settings_ui.visible, "pause settings keep game paused")
	settings_ui.get_node("%Sensitivity").value = 1.5
	_check(is_equal_approx(player.mouse_sensitivity, 0.15), "pause slider changes existing player")
	await _key(KEY_ESCAPE)
	_check(paused and not settings_ui.visible and pause_menu.get_node("%Card").visible, "escape from settings preserves pause")
	await _key(KEY_ESCAPE)
	_check(not paused and not pause_menu.get_node("%Root").visible, "second escape resumes game")
	if DisplayServer.get_name() != "headless":
		_check(Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED, "resume recaptures mouse")
	_check(player._look_delta == Vector2.ZERO, "resume avoids stale look input")

	var pool = root.get_node("CoinPool")
	pool.acquire()
	await _key(KEY_ESCAPE)
	await _click(pause_menu.get_node("%MainMenuButton"))
	_check(not paused and current_scene.scene_file_path == _flow.MAIN_MENU, "return from paused game to menu")
	_check(pool.active_count() == 0 and pool.free_count() == 0, "menu return clears scene coin references")
	_check(not current_scene.get_node("%LoadGameButton").disabled, "saved game enables load")
	_wallet.add(10)
	await _click(current_scene.get_node("%LoadGameButton"))
	_check(_flow.is_in_game() and _wallet.total == 481, "load button restores saved coins")
	_check(current_scene.get_node("HUD/MoneyUI")._label.text == "481", "loaded amount immediately appears on HUD")
	var coin = pool.acquire()
	_check(coin.get_parent() == current_scene, "coin pool works in loaded scene")
	_settings.load_settings()
	_check(is_equal_approx(_settings.mouse_sensitivity, 0.15), "settings persist independently from save")
	_finish()


func _finish() -> void:
	paused = false
	print("MENU REGRESSION RESULT: phase=%s passed=%d failed=%d" % [_phase, _passed, _failed])
	quit(0 if _failed == 0 else 1)
