extends SceneTree

## 使用 --data-dir=<隔离目录>；--phase=write_world/read_world/write_lab/read_lab 跨进程验证。
var _passed := 0
var _failed := 0
var _directory := ""
var _phase := "full"
var _save
var _flow
var _wallet
var _progress
var _room
var _player
var _gate
var _events: Array = []


func _initialize() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func():
		push_error("LEVEL PROGRESS REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("LEVEL PROGRESS REGRESSION FAILED: " + message)


func _frames(count: int = 3) -> void:
	for frame in range(count):
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(int(ceil(seconds * Engine.physics_ticks_per_second)) + 1)


func _bind() -> void:
	_room = current_scene
	_player = _room.get_node("Player")
	_player.set_physics_process(false)
	_gate = _room.get_node("LiftGate" if _room.scene_file_path == _flow.MECHANISM_LAB else "VineGate")


func _enter(load_saved: bool = false) -> void:
	_check((_flow.load_game() if load_saved else _flow.start_new_game()).ok, "load save" if load_saved else "new game")
	await scene_changed
	await _frames()
	_bind()


func _lab() -> void:
	change_scene_to_file(_flow.MECHANISM_LAB)
	await scene_changed
	await _frames()
	_bind()


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames()


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


func _manual_save() -> void:
	await _key(KEY_ESCAPE)
	_check(paused, "Esc pauses before save")
	var menu = _flow.get_node("PauseMenu")
	_check(menu.get_node("%SaveStatus").text.contains("关卡进度"), "pause explains permanent progress")
	await _click(menu.get_node("%SaveButton"))
	_check(menu.get_node("%SaveStatus").text.contains("存档成功"), "actual manual save succeeds")
	await _key(KEY_ESCAPE)


func _menu_load() -> void:
	await _key(KEY_ESCAPE)
	await _click(_flow.get_node("PauseMenu").get_node("%MainMenuButton"))
	_check(current_scene.scene_file_path == _flow.MAIN_MENU and not paused, "pause returns to main menu")
	_events.clear()
	await _click(current_scene.get_node("%LoadGameButton"))
	_bind()
	await _frames()


func _burn_vines() -> void:
	for part in _gate.get_children():
		_check(part.element.ignite(), "actual vine burn starts")
	await _wait(10.5)
	_check(_gate.is_persistently_open() and _room.is_gate_open(), "all vines burn down before progress opens")


func _open_lab() -> void:
	var platform = _room.get_node("WeightPlatform")
	var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
	_room.add_child(corpse)
	corpse.global_position = platform.global_position + Vector3.UP * 0.5
	corpse.reset_physics_interpolation()
	await _wait(3.0)
	_check(platform.is_pressed() and _gate.is_open(), "real supported corpse raises physical gate")
	_check(_gate.is_persistently_open(), "fully raised latched gate is permanent")


func _verify_world() -> void:
	_check(_room.scene_file_path == load("res://tests/helpers/legacy_world_fixture.gd").SCENE, "world save restores safe world entrance")
	_check(_gate.get_child_count() == 0 and _gate.is_persistently_open() and _room.is_gate_open(), "loaded vine bodies and visuals removed")
	_check(_room.get_node("RatSpawner").enabled and _room.get_node("EntryRatSpawner").enabled and _room.get_node("HUD/Objective").text.contains("东侧房间"), "loaded world updates spawners and gate hint")
	_check(_events.is_empty() and not _room.is_flow_complete(), "restore does not replay break or reward events")
	_check(_wallet.total == 12345 and _flow.get_purchased_upgrades() == {"oil": true, "corpse_return": true, "charged_throw": true, "mirror": false}, "coins and all purchased upgrades restore with gate progress")
	var world_scale: float = _room.get_node("WorldGeometry").scale.x
	_player.global_position = _room.get_node("GameplayAnchors/VineBefore").global_position + Vector3.UP * 0.05
	_player.velocity = Vector3(5, 0, 0)
	_player.reset_physics_interpolation()
	await _frames()
	for frame in range(int(Engine.physics_ticks_per_second * world_scale)):
		_player.move_and_slide()
		await physics_frame
	_check(_player.position.x > -3.5 * world_scale, "real player moves through restored vine doorway")


func _verify_lab() -> void:
	_check(_room.scene_file_path == _flow.MECHANISM_LAB, "lab save restores lab entrance")
	_check(_wallet.total == 54321 and _gate.is_open() and _gate.is_persistently_open(), "lab wallet and permanent opening restore")
	_check(not _room.get_node("WeightPlatform").is_pressed() and not _room.get_node("Player/Camera3D/Grabber").charged_throw_enabled, "load resets temporary weights and free debug ability")
	await _wait(1.0)
	_check(_gate.get_node("Leaf").position.is_equal_approx(_gate.open_offset), "restored physical leaf remains at configured local open position")
	_player.position = Vector3(2.4, 0.5, -3)
	_player.velocity = Vector3(0, 0, -5)
	_player.reset_physics_interpolation()
	await _frames()
	for frame in range(Engine.physics_ticks_per_second):
		_player.move_and_slide()
		await physics_frame
	await _frames()
	_check(_player.position.z < -7 and _room.is_completed(), "real player passes restored lift gate and reaches goal")


func _write_raw(data: Dictionary) -> void:
	var file := FileAccess.open(_save.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _run() -> void:
	await process_frame
	# 显式选择历史地图夹具；正式入口另由 run_main_world_* 验证。
	load("res://tests/helpers/legacy_world_fixture.gd").install(self)
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
	_flow = root.get_node("GameFlow")
	_wallet = root.get_node("Wallet")
	_progress = load("res://scripts/persistence/level_progress.gd")
	_save.save_path = _directory.path_join("savegame.json")
	root.get_node("GameSettings").settings_path = _directory.path_join("settings.cfg")
	root.get_node("EventBus").obstacle_broken.connect(func(_obstacle, _source): _events.append("broken"))
	if _phase.begins_with("read_"):
		await _enter(true)
		if _phase == "read_world":
			await _verify_world()
		else:
			await _verify_lab()
		_finish()
		return
	if _phase != "write_lab":
		await _enter()
		if _phase == "full":
			_check(_save.save_game().ok and _save.read_save().opened_gates.is_empty(), "closed gate saves no opening")
			_gate.get_child(0).element.burn_duration = 0.3
			_gate.get_child(0).element.ignite()
			await _wait(0.6)
			_check(_gate.get_child_count() == 2 and not _gate.is_persistently_open(), "partially burned gate remains closed progress")
			_check(_save.save_game().ok and _save.read_save().opened_gates.is_empty(), "partial burn and remaining timer are excluded")
			await _enter(true)
			_check(_gate.get_child_count() == 3 and not _gate.get_child(0).element.burning, "partial burn load restores complete unburned gate")
		await _burn_vines()
		_wallet.set_total(12345)
		_check(_room.get_node("ShopRoom").restore_purchased_upgrades({"oil": true, "corpse_return": true, "charged_throw": true}), "combined upgrade fixture applies")
		await _manual_save()
		_check(_save.read_save().opened_gates == {"world.cleaning.vines": true}, "world snapshot uses stable gate ID")
		if _phase == "write_world":
			_finish()
			return
		await _menu_load()
		await _verify_world()
		var previous := FileAccess.get_file_as_string(_save.save_path)
		await _enter()
		_check(not _gate.is_persistently_open() and _gate.get_child_count() == 3 and FileAccess.get_file_as_string(_save.save_path) == previous, "new game resets live gate and preserves old save")
		DirAccess.make_dir_absolute(_save.save_path + ".tmp")
		_check(not _save.save_game().ok and FileAccess.get_file_as_string(_save.save_path) == previous, "atomic write failure preserves full previous progress")
		DirAccess.remove_absolute(_save.save_path + ".tmp")
	await _lab()
	if _phase == "full":
		_gate.set_open_requested(true)
		await _wait(0.3)
		_check(not _gate.is_open() and not _gate.is_persistently_open(), "moving gate does not become permanent early")
		_check(_save.save_game().ok and _save.read_save().opened_gates.is_empty(), "partial lift motion excluded")
		await _enter(true)
		_check(_gate.is_closed(), "partial lift load starts closed")
		_gate.latch_open = false
		_gate.set_open_requested(true)
		await _wait(2.0)
		_check(_gate.is_open() and not _gate.is_persistently_open(), "momentary gate is never permanent")
		_check(_save.save_game().ok and _save.read_save().opened_gates.is_empty(), "momentary opening excluded from save")
		await _enter(true)
	await _key(KEY_E)
	await _open_lab()
	_wallet.set_total(54321)
	await _manual_save()
	_check(_save.read_save().level == "mechanism_lab" and _save.read_save().opened_gates == {"lab.weight_gate": true}, "lab snapshot includes entrance and stable ID")
	if _phase == "write_lab":
		_finish()
		return
	await _menu_load()
	await _verify_lab()
	var lab_save := FileAccess.get_file_as_string(_save.save_path)
	await _key(KEY_R)
	_bind()
	_check(_gate.is_closed() and FileAccess.get_file_as_string(_save.save_path) == lab_save, "R resets lab without auto-load or overwriting disk")
	await _test_ids_and_validation()
	_finish()


func _test_ids_and_validation() -> void:
	# 同一编号配新位置、旋转、节点名与行程，仍按新地图配置恢复。
	var relocated = Node3D.new()
	relocated.position = Vector3(40, 0, 25)
	relocated.rotation.y = PI * 0.5
	_room.add_child(relocated)
	var moved = load("res://scenes/mechanisms/lift_gate.tscn").instantiate()
	moved.name = "RenamedArtGate"
	moved.persistence_id = &"lab.weight_gate"
	moved.open_offset = Vector3(0, 4.5, 0)
	_gate.persistence_id = &""
	relocated.add_child(moved)
	var signals: Array = []
	moved.opened.connect(func(): signals.append("opened"))
	_check(_progress.restore(_room, {"lab.weight_gate": true, "future.map.gate": true}), "stable ID restores moved gate and preserves unmatched ID")
	await _frames()
	_check(moved.is_open() and moved.get_node("Leaf").position.is_equal_approx(Vector3(0, 4.5, 0)) and signals.is_empty(), "restore follows new local geometry without replaying opened signal")
	_check(_save.save_game().ok and _save.read_save().opened_gates == {"lab.weight_gate": true, "future.map.gate": true}, "unmatched map progress survives manual resave")
	var previous := FileAccess.get_file_as_string(_save.save_path)
	_gate.persistence_id = &"lab.weight_gate"
	_check(not _save.save_game().ok and FileAccess.get_file_as_string(_save.save_path) == previous, "duplicate gate IDs reject snapshot without replacing prior save")
	_gate.persistence_id = &"bad/id"
	_check(not _save.save_game().ok and FileAccess.get_file_as_string(_save.save_path) == previous, "invalid map ID rejects snapshot safely")
	_gate.persistence_id = &""
	await _enter()
	var previous_scene = current_scene
	var payload := {"version": 4, "coins": "100", "upgrades": {"oil": false, "corpse_return": false, "charged_throw": false}, "level": "world", "opened_gates": {}}
	for invalid in [null, [], {"world.cleaning.vines": false}, {"world.cleaning.vines": 1}, {"world.cleaning.vines": "true"}, {"": true}, {"bad/id": true}, {"x".repeat(65): true}]:
		payload.opened_gates = invalid
		_write_raw(payload)
		_check(not _flow.load_game().ok and current_scene == previous_scene and _wallet.total == 0, "malformed gate snapshot cannot mutate current game")
	payload.opened_gates = {}
	for invalid in [null, 1, "res://scenes/debug/mechanism_lab.tscn", "unknown"]:
		payload.level = invalid
		_write_raw(payload)
		_check(not _flow.load_game().ok and current_scene == previous_scene, "invalid entrance cannot load arbitrary scene")
	payload.level = "mechanism_lab"
	payload.upgrades.oil = true
	_write_raw(payload)
	_check(not _flow.load_game().ok, "lab rejects paid upgrades with no shop to restore")
	for version in [1, 2, 3]:
		var legacy := {"version": version, "coins": "9007199254740993"}
		if version == 2:
			legacy.upgrades = {"corpse_return": true, "charged_throw": true}
		elif version == 3:
			legacy.upgrades = {"oil": true, "corpse_return": true, "charged_throw": true}
		_write_raw(legacy)
		await _enter(true)
		_check(_room.scene_file_path == load("res://tests/helpers/legacy_world_fixture.gd").SCENE and not _room.is_gate_open() and _wallet.total == 9007199254740993, "legacy v%d keeps exact coins and starts gate closed" % version)
		_check(_flow.get_purchased_upgrades() == {"oil": version == 3, "corpse_return": version >= 2, "charged_throw": version >= 2, "mirror": false}, "legacy v%d retains recorded upgrades" % version)
		_check(_save.save_game().ok and _save.read_save().opened_gates.is_empty(), "legacy migrates only on manual save")


func _finish() -> void:
	paused = false
	print("LEVEL PROGRESS REGRESSION RESULT: passed=%d failed=%d phase=%s" % [_passed, _failed, _phase])
	quit(0 if _failed == 0 else 1)
