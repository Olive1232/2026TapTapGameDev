extends SceneTree

## 新档开局、真实挥剑首杀 / 抓取、暂停、布局及手动存档兼容。
var _passed := 0
var _failed := 0
var _directory := ""
var _capture_directory := ""
var _phase := "full"
var _flow
var _save
var _room: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _hints: Control
var _grabber


func _initialize() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func():
		push_error("ONBOARDING REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("ONBOARDING REGRESSION FAILED: " + message)


func _frames(count: int = 4) -> void:
	for index in count:
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(ceili(seconds * Engine.physics_ticks_per_second) + 1)


func _bind_world() -> void:
	_room = current_scene
	_player = _room.get_node("Player")
	_player.set_physics_process(false)
	_camera = _player.get_node("Camera3D")
	_grabber = _camera.get_node("Grabber")
	_hints = _room.get_node("HUD/OnboardingHints")
	for spawner in get_nodes_in_group("monster_spawners"):
		spawner.enabled = false


func _enter(load_saved: bool = false) -> void:
	_check((_flow.load_game() if load_saved else _flow.start_new_game()).ok, "enter requested game")
	await scene_changed
	_bind_world()
	await _frames()


func _write_raw(payload: Dictionary) -> void:
	var file := FileAccess.open(_save.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()


func _spawn_monster(species: String = "rat"):
	var enemy = load("res://scenes/enemies/monster.tscn").instantiate()
	enemy.data = load("res://resources/enemies/monster_" + species + ".tres")
	_room.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = _room.get_node("GameplayAnchors/Combat").global_position + Vector3(0, -0.8, -1)
	return enemy


func _kill(species: String, by: Node3D):
	var enemy = _spawn_monster(species)
	var corpses: Array = []
	root.get_node("EventBus").corpse_spawned.connect(func(corpse): corpses.append(corpse), CONNECT_ONE_SHOT)
	var hit = load("res://scripts/weapons/hit_info.gd").new()
	hit.damage = enemy.data.max_health
	hit.source = by
	enemy.take_hit(hit)
	return corpses[0] if not corpses.is_empty() else null


func _mouse(button: MouseButton) -> void:
	# headless 不保留捕获鼠标模式；使用与右键输入共用的游戏入口。
	if button == MOUSE_BUTTON_RIGHT and DisplayServer.get_name() == "headless":
		_grabber.handle_grab_input(true)
		_grabber.handle_grab_input(false)
	else:
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			event.pressed = pressed
			Input.parse_input_event(event)
		Input.flush_buffered_events()
	await _frames()


func _capture(name: String) -> void:
	if _capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw(true)
	_check(root.get_texture().get_image().save_png(_capture_directory.path_join(name + ".png")) == OK, "capture " + name)


func _check_layout() -> void:
	var panel: Rect2 = _hints.get_panel_rect()
	var bottom: Label = _room.get_node("HUD/BottomText/TextBox/Text")
	_check(Rect2(Vector2.ZERO, _hints.size).encloses(panel), "icons remain inside viewport")
	_check(absf(panel.get_center().x - _hints.size.x * 0.5) <= 1.0, "icons remain centered")
	_check(panel.end.y < bottom.get_global_rect().position.y, "icons stay above bottom guidance")
	_check(panel.position.y > _hints.size.y * 0.5, "icons leave crosshair unobstructed")


func _run() -> void:
	await process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data-dir="):
			_directory = argument.trim_prefix("--data-dir=")
		elif argument.begins_with("--capture-dir="):
			_capture_directory = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--phase="):
			_phase = argument.trim_prefix("--phase=")
	if not _directory.begins_with("/tmp/"):
		push_error("Use an isolated /tmp/ data directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	if _capture_directory.begins_with("/tmp/"):
		DirAccess.make_dir_recursive_absolute(_capture_directory)
	else:
		_capture_directory = ""
	_flow = root.get_node("GameFlow")
	_save = root.get_node("SaveGame")
	_save.save_path = _directory.path_join("savegame.json")
	root.get_node("GameSettings").settings_path = _directory.path_join("settings.cfg")
	if _phase == "write":
		await _enter()
		_kill("rat", _player)
		_check(_hints.get_stage() == "pickup" and _save.save_game().ok, "write pickup progress in fresh process")
		_finish()
		return
	if _phase == "read":
		await _enter(true)
		_check(_hints.get_stage() == "pickup" and _hints.visible, "fresh process resumes pickup instead of restarting tutorial")
		_finish()
		return
	# 直接打开调试世界不会意外启动新档引导。
	change_scene_to_file(_flow.GAME_SCENE)
	await scene_changed
	_bind_world()
	_check(_hints.get_stage() == "complete" and not _hints.visible, "direct world entry has no tutorial")
	await _enter()
	_check(_hints.visible and _hints.get_stage() == "controls", "new game starts with movement, jump and attack icons")
	_check(_hints.mouse_filter == Control.MOUSE_FILTER_IGNORE and _hints.get_child_count() == 0, "overlay has no input-blocking children")
	for dimensions in [Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		root.size = dimensions
		await _frames()
		_check_layout()
		await _capture("controls_%dx%d" % [dimensions.x, dimensions.y])
	root.size = Vector2i(1280, 720)
	await _frames()
	var pulse: float = _hints._pulse
	await _wait(0.35)
	_check(not is_equal_approx(pulse, _hints._pulse) and _hints._pulse >= 0.35, "icons visibly pulse without fully losing legibility")
	_flow.pause_game()
	await _frames()
	var elapsed: float = _hints._elapsed
	await _wait(0.3)
	_check(not _hints.visible and is_equal_approx(elapsed, _hints._elapsed), "pause hides icons and freezes blink phase")
	_flow.resume_game()
	await _frames()
	_check(_hints.visible and _hints.get_stage() == "controls", "resume restores the same tutorial")
	_check(_save.save_game().ok and _save.read_save().tutorial_stage == "controls", "save records unfinished initial instructions")
	await _enter(true)
	_check(_hints.get_stage() == "controls", "loading unfinished opening resumes basic controls")
	# 其他怪种 / 无玩家来源的死亡都不能冒充玩家首次击杀老鼠。
	var other = _kill("cockroach", _player)
	_check(_hints.get_stage() == "controls", "cockroach kill does not trigger rat pickup")
	other.queue_free()
	var uncredited = _kill("rat", null)
	_check(_hints.get_stage() == "controls", "uncredited rat death does not trigger first player kill")
	uncredited.queue_free()
	await _frames()
	# 使用真实左键、挥剑判定、Monster 死亡和尸体生成。
	_player.global_position = _room.get_node("GameplayAnchors/Combat").global_position
	_player.rotation = Vector3.ZERO
	_camera.rotation = Vector3(deg_to_rad(-45), 0, 0)
	var rat = _spawn_monster()
	rat.global_position = _camera.global_transform * Vector3(0, -0.34, -1.4)
	var corpses: Array = []
	root.get_node("EventBus").corpse_spawned.connect(func(corpse): corpses.append(corpse), CONNECT_ONE_SHOT)
	await _frames()
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.8)
	_check(not is_instance_valid(rat) and not corpses.is_empty(), "real left click kills rat and creates corpse")
	_check(_hints.get_stage() == "pickup" and _hints.visible, "first real player rat kill switches to right mouse icon")
	await _capture("pickup_after_first_kill")
	_check_layout()
	_check(_save.save_game().ok and _save.read_save().tutorial_stage == "pickup", "pickup stage is saved")
	await _enter(true)
	_check(_hints.get_stage() == "pickup", "load after first kill keeps pickup instruction")
	_camera.rotation = Vector3.ZERO
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_hints.get_stage() == "pickup", "empty right click does not complete pickup")
	var wrong_corpse = _kill("cockroach", _player)
	wrong_corpse.freeze = true
	wrong_corpse.global_position = _camera.global_position - _camera.global_basis.z * 2.0
	await _frames()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_grabber.get_held() == wrong_corpse and _hints.get_stage() == "pickup", "picking up another species does not complete rat guide")
	_grabber.drop()
	wrong_corpse.queue_free()
	await _frames()
	var corpse = _kill("rat", _player)
	_check(_hints.get_stage() == "pickup", "subsequent kills do not restart initial instructions")
	corpse.freeze = true
	corpse.global_position = _camera.global_position - _camera.global_basis.z * 2.0
	await _frames()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_grabber.get_held() == corpse and _player.carry_weight > 0.0, "real right click grabs rat and applies carry weight")
	_check(_hints.get_stage() == "complete" and not _hints.visible, "successful rat pickup dismisses tutorial")
	_check(_save.save_game().ok and _save.read_save().tutorial_stage == "complete", "completion is persisted")
	await _enter(true)
	_check(not _hints.visible and _hints.get_stage() == "complete", "completed tutorial never replays on load")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_save.save_path))
	for invalid in [null, true, 1, {}, [], "unknown"]:
		var payload := saved.duplicate(true)
		payload.tutorial_stage = invalid
		_write_raw(payload)
		_check(not _flow.load_game().ok and current_scene == _room, "invalid tutorial state is rejected without scene change")
	# 既有 v7 和最早 v1 存档均默认完成，不向老玩家补播。
	saved.erase("tutorial_stage")
	_write_raw(saved)
	await _enter(true)
	_check(not _hints.visible and _save.read_save().tutorial_stage == "complete", "legacy v7 without tutorial field stays quiet")
	_write_raw({"version": 1, "coins": "23"})
	await _enter(true)
	_check(not _hints.visible and root.get_node("Wallet").total == 23, "legacy v1 keeps money and does not replay tutorial")
	var previous_save := FileAccess.get_file_as_string(_save.save_path)
	await _enter()
	_check(_hints.get_stage() == "controls" and FileAccess.get_file_as_string(_save.save_path) == previous_save, "new game restarts tutorial without overwriting disk save")
	var old_hints: WeakRef = weakref(_hints)
	_check(_flow.return_to_main_menu().ok, "return to menu")
	await scene_changed
	await _frames()
	_check(old_hints.get_ref() == null and _flow.get_tutorial_stage() == "complete", "leaving world removes tutorial and signal connections")
	_finish()


func _finish() -> void:
	paused = false
	print("ONBOARDING REGRESSION RESULT: phase=%s passed=%d failed=%d" % [_phase, _passed, _failed])
	quit(0 if _failed == 0 else 1)
