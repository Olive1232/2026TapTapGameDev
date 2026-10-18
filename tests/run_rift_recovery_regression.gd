extends SceneTree

## 原地图两处真实裂缝：行走跌落、黄屏时序、安全复位、暂停及手持物。
var _passed := 0
var _failed := 0
var _world
var _player
var _recovery
var _grabber
var _starts := 0
var _returns: Array = []
var _finishes := 0


func _initialize() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func():
		push_error("RIFT RECOVERY TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("RIFT RECOVERY FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _place(at: Vector3, yaw: float = 0.0) -> void:
	for action in ["Up", "Down", "Left", "Right"]:
		Input.action_release(action)
	_player.recover_from_fall(at)
	_player.rotation = Vector3(0, yaw, 0)
	_player.get_node("Camera3D").rotation = Vector3.ZERO
	await _frames(12)


func _escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _click(button: MouseButton) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _await_start() -> bool:
	for frame in 120:
		await physics_frame
		if _recovery.is_recovering():
			return true
	return false


func _await_finish() -> bool:
	for frame in 200:
		await physics_frame
		if not _recovery.is_recovering():
			await _frames()
			return true
	return false


func _walk_off(bank: Vector3, yaw: float, name: String, pause_midway: bool) -> void:
	await _place(bank, yaw)
	var count := _starts
	var return_count := _returns.size()
	Input.action_press("Up")
	var started := await _await_start()
	Input.action_release("Up")
	_check(started and _starts == count + 1, name + " actual walking off the original ledge starts one recovery")
	if not started:
		return
	_check(_returns.size() == return_count and is_zero_approx(_recovery.get_yellow_amount()), name + " does not teleport before yellow begins")
	var fall_position: Vector3 = _player.global_position
	var rotation: Vector3 = _player.rotation
	await _frames(10)
	var first: float = _recovery.get_yellow_amount()
	_check(first > 0.01 and first < 0.5, name + " yellow fades in gradually")
	Input.action_press("Right")
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(120, 30)
	Input.parse_input_event(motion)
	_click(MOUSE_BUTTON_LEFT)
	await _frames(12)
	Input.action_release("Right")
	_check(_player.global_position.is_equal_approx(fall_position) and _player.rotation.is_equal_approx(rotation), name + " movement and look are held during recovery")
	_check(_recovery.get_yellow_amount() > first and _returns.size() == return_count, name + " scene remains in place while yellow increases")
	if pause_midway:
		_escape()
		_check(paused, "Esc can pause during yellow recovery")
		var amount: float = _recovery.get_yellow_amount()
		await _frames(30)
		_check(is_equal_approx(_recovery.get_yellow_amount(), amount) and _returns.size() == return_count, "pause freezes fade and teleport timing")
		_escape()
		_check(not paused and _player.is_rift_recovering(), "resume continues existing recovery")
	for frame in 90:
		await physics_frame
		if _returns.size() > return_count:
			break
	_check(_returns.size() == return_count + 1 and _returns[-1].amount == 1.0, name + " teleports exactly once under fully yellow coverage")
	_check(_returns[-1].rift == name and _player.velocity.is_zero_approx(), name + " clears falling velocity on correct rift")
	_check(_recovery._is_safe_return(_player.global_position), name + " returns whole body to supported ground beyond edge")
	_check(_player.rotation.is_equal_approx(rotation), name + " keeps view direction")
	_check(Vector2(_player.global_position.x-bank.x, _player.global_position.z-bank.z).length() < 8.0, name + " prefers the bank the player fell from")
	await _frames(22)
	_check(_recovery.get_yellow_amount() > 0.1 and _recovery.get_yellow_amount() < 1.0 and _player.is_rift_recovering(), name + " yellow slowly fades out after teleport")
	_check(await _await_finish(), name + " fade finishes")
	_check(is_zero_approx(_recovery.get_yellow_amount()) and not _recovery.get_node("Screen/Yellow").visible and not _player.is_rift_recovering(), name + " clears overlay and restores controls")
	_check(_player.is_on_floor() and _player.global_position.y > bank.y - 0.05, name + " remains safely grounded after recovery")
	await _frames(30)
	_check(_starts == count + 1, name + " does not loop on the safe return point")


func _test_held(scene_path: String, label: String) -> void:
	var bank := Vector3(56, 3.7595, 30)
	await _place(bank)
	var held = load(scene_path).instantiate()
	if label == "corpse":
		held.setup(load("res://resources/enemies/monster_rat.tres"))
		held.value = 7
	held.position = _player.get_node("Camera3D").global_position + Vector3.FORWARD * 1.5
	_world.add_child(held)
	held.freeze = true
	await _frames()
	_check(_grabber.try_grab() and _grabber.get_held() == held, label + " fixture picks up actual rigid body")
	await _frames(12)
	var weight: float = _player.carry_weight
	var id: int = held.get_instance_id()
	var count := _returns.size()
	# 直接落到很深的位置，验证高速越过薄区域也能检测，商品不会自动退架。
	_player.global_position = Vector3(64, -45, 30)
	_player.velocity = Vector3(0, -120, 0)
	_check(await _await_start(), label + " deep fall starts recovery without Area enter dependency")
	_click(MOUSE_BUTTON_RIGHT)
	await _frames(35)
	_check(_grabber.get_held() == held and held.is_held, label + " cannot be dropped or returned home during yellow")
	_check(await _await_finish(), label + " carried recovery finishes")
	_check(is_instance_valid(held) and held.get_instance_id() == id and _grabber.get_held() == held and held.is_held, label + " keeps original held entity")
	_check(is_equal_approx(_player.carry_weight, weight) and weight > 0.0, label + " preserves carry weight")
	_check(_returns.size() == count + 1 and _returns[-1].held_distance < 0.01, label + " held body snaps to hand with player teleport")
	_check(held.global_position.distance_to(_grabber.get_node("HoldPoint").global_position) < 0.2, label + " stays beside player instead of remaining underground")
	if label == "corpse":
		_check(held.value == 7, "corpse recovery preserves value")
	_grabber.drop()
	held.queue_free()
	await _frames()


func _run() -> void:
	await process_frame
	root.get_node("SaveGame").save_path = "/tmp/taptap-rift-recovery-save.json"
	root.get_node("GameSettings").settings_path = "/tmp/taptap-rift-recovery-settings.cfg"
	root.get_node("GameFlow").start_new_game()
	await scene_changed
	_world = current_scene
	_player = _world.get_node("Player")
	_recovery = _world.get_node("RiftRecovery")
	_grabber = _player.get_node("Camera3D/Grabber")
	_world.get_node("WorldDialogue").restore_progress({"shop_visited":true,"hole_introduced":true})
	for node in _world.get_children():
		if "enabled" in node:
			node.enabled = false
	_recovery.recovery_started.connect(func(_rift): _starts += 1)
	_recovery.player_returned.connect(func(rift, at):
		var held = _grabber.get_held()
		_returns.append({"rift":rift.name,"at":at,"amount":_recovery.get_yellow_amount(),"held_distance":held.global_position.distance_to(_grabber.get_node("HoldPoint").global_position) if held != null else 0.0}))
	_recovery.recovery_finished.connect(func(): _finishes += 1)
	await _frames(15)
	_check(not _recovery.is_recovering() and _starts == 0, "normal spawn and walking ground do not activate yellow")
	_check(_recovery.get_node("Rifts").get_child_count() == 2, "exactly the two existing cracks are configured")
	for rift in _recovery.get_node("Rifts").get_children():
		for point in rift.get_bank_points():
			var valid := true
			for angle in [0.0, PI/4.0, PI/2.0]:
				_player.rotation.y = angle
				valid = valid and _recovery._is_safe_return(point)
			_check(valid, str(rift.name) + " bank supports player at all body orientations: " + str(point))
		_check(not rift.contains_fall(_world.get_node("Hole").global_position - Vector3.UP * 3), "central offering hole does not use crack recovery")
		var inside := Vector3(67,rift.surface_height,-28) if rift.name == "UpperRift" else Vector3(64,rift.surface_height,20)
		_check(rift.contains_footprint(inside) and not rift.contains_fall(inside), str(rift.name) + " only triggers below ledge height")
		_check(rift.contains_fall(inside-Vector3.UP*100), str(rift.name) + " detects deep fast fall")
	await _walk_off(_recovery.get_node("Rifts/UpperRift/Banks/Bank2").global_position, -PI/2.0, "UpperRift", true)
	await _walk_off(Vector3(72.5,3.7595,21), PI/2.0, "LowerRift", false)
	await _test_held("res://scenes/enemies/corpse.tscn", "corpse")
	await _test_held("res://scenes/shop/shop_item.tscn", "product")
	_check(root.get_node("Wallet").total == 0 and not InputMap.has_action("Jump"), "recovery preserves money and does not restore jumping")
	_check(_finishes == _returns.size(), "each completed return has one finish event")
	_player.global_position = Vector3(67,-20,-28)
	_player.velocity = Vector3.ZERO
	_check(await _await_start(), "another fall can start after prior recovery")
	var old: WeakRef = weakref(_recovery)
	root.get_node("GameFlow").return_to_main_menu()
	await scene_changed
	await _frames()
	_check(old.get_ref() == null and not paused, "leaving scene mid fade frees overlay and transition state")
	print("RIFT RECOVERY RESULT: passed=%d failed=%d" % [_passed,_failed])
	quit(0 if _failed == 0 else 1)
