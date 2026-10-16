extends SceneTree

## 实际刚体投掷、开门通行与地图迁移；夹具不修改正式商品或钱包。
const LAB := "res://scenes/debug/mechanism_lab.tscn"
const CORPSE := "res://scenes/enemies/corpse.tscn"
const PLATFORM := "res://scenes/mechanisms/weight_platform.tscn"
const GATE := "res://scenes/mechanisms/lift_gate.tscn"
var _passed := 0
var _failed := 0
var _room: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _grabber
var _platform
var _gate
var _capture_dir := ""


func _initialize() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func():
		push_error("MECHANISM REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("MECHANISM REGRESSION FAILED: " + message)


func _frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(int(ceil(seconds * Engine.physics_ticks_per_second)) + 1)


func _load_lab() -> void:
	paused = false
	Engine.time_scale = 1.0
	change_scene_to_file(LAB)
	await scene_changed
	_room = current_scene
	_player = _room.get_node("Player")
	_camera = _player.get_node("Camera3D")
	_grabber = _camera.get_node("Grabber")
	_platform = _room.get_node("WeightPlatform")
	_gate = _room.get_node("LiftGate")
	_player.set_physics_process(false)
	await _wait(0.3)


func _right(pressed: bool) -> void:
	if DisplayServer.get_name() == "headless":
		_grabber.handle_grab_input(pressed)
	else:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _new_corpse(at: Vector3):
	var corpse = load(CORPSE).instantiate()
	_room.add_child(corpse)
	corpse.global_position = at
	corpse.reset_physics_interpolation()
	return corpse


func _capture(name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames()
	RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(_capture_dir.path_join(name + ".png"))


func _run() -> void:
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			_capture_dir = arg.trim_prefix("--capture-dir=")
	await _test_real_throw_and_passage()
	await _test_supported_loads()
	await _test_momentary_and_obstruction()
	await _test_early_goal_arrival()
	await _test_portability()
	await _test_placed_world()
	paused = false
	Engine.time_scale = 1.0
	print("MECHANISM REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_placed_world() -> void:
	root.get_node("GameFlow").start_new_game()
	await scene_changed
	_room = current_scene
	_player = _room.get_node("Player")
	_player.set_physics_process(false)
	_room.get_node("WorldDialogue").restore_progress({"shop_visited": true, "hole_introduced": true})
	for node in _room.get_children():
		if node.has_method("get_alive_count"):
			node.enabled = false
	_platform = _room.get_node("WeightPlatform")
	_gate = _room.get_node("LiftGate")
	await _frames(10)
	_check(_gate.get_node_or_null(_gate.platform_path) == _platform and _gate.is_closed() and not _platform.is_pressed(), "placed world gate is linked to its empty weight platform")
	var obstruction = _new_corpse(_gate.get_node("Leaf/Shape").global_position)
	obstruction.freeze = true
	var corpse = _new_corpse(_platform.global_position + Vector3.UP * 0.5)
	await _wait(1.0)
	_check(_platform.is_pressed() and _platform.get_corpse_count() == 1, "real corpse settles on the placed world platform")
	_check(_gate.is_blocked() and _gate.is_closed(), "configured rock frame exclusion still protects a corpse inside the gate")
	obstruction.queue_free()
	await _wait(3.0)
	_check(_gate.is_open() and not _gate.is_blocked() and _gate.get_node("Leaf").position.is_equal_approx(_gate.open_offset), "placed gate retracts into its rock frame after obstruction clears")
	corpse.queue_free()
	await _wait(0.5)
	_check(not _platform.is_pressed() and _platform.get_corpse_count() == 0 and _gate.is_open(), "placed gate keeps its default open latch after platform load is removed")


func _test_real_throw_and_passage() -> void:
	await _load_lab()
	var flow := root.get_node("GameFlow")
	_check(flow.is_in_game(), "lab participates in existing Esc pause flow")
	_check(not _grabber.charged_throw_enabled, "lab starts locked until debug E unlock")
	_check(not _platform.is_pressed() and _gate.is_closed(), "empty high platform starts with physical gate closed")
	_player.position = Vector3(2.4, 0.5, -3)
	_player.velocity = Vector3(0, 0, -5)
	for i in range(int(Engine.physics_ticks_per_second * 0.8)):
		_player.move_and_slide()
		await physics_frame
	_check(_player.position.z > -4.5, "closed gate blocks real player movement")
	_player.position = Vector3(-3.2, 0.5, 5.5)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_camera.rotation = Vector3(deg_to_rad(35), 0, 0)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	_room._unhandled_input(key)
	_check(_grabber.charged_throw_enabled, "lab E enables throw through local debug handler")
	var corpse = _new_corpse(_camera.global_position - _camera.global_basis.z * 1.6)
	corpse.freeze = true
	await _frames()
	_right(true)
	_right(false)
	_check(_grabber.get_held() == corpse and corpse.is_held, "actual grab ray picks up throwable corpse")
	corpse.freeze = false
	await _wait(0.35)
	_right(true)
	await _wait(0.4)
	var predicted: Vector3 = _grabber._trajectory.points[-1]
	var contacts: Array = []
	corpse.contact_monitor = true
	corpse.max_contacts_reported = 4
	corpse.body_entered.connect(func(body): contacts.append({"body": str(body.get_path()), "at": corpse.global_position}))
	_check(_grabber._trajectory.collided and predicted.y > 2.4 and absf(predicted.x + 2.5) < 1.6 and absf(predicted.z + 2.5) < 1.4, "throw arc predicts landing on high weight platform")
	await _capture("platform-throw-arc")
	_right(false)
	await _wait(3.5)
	_check(not contacts.is_empty() and contacts[0].body == str(_platform.get_node("Body").get_path()) and contacts[0].at.distance_to(predicted) < 0.5, "actual first platform contact matches predicted landing")
	_check(corpse.position.y > 2.4 and corpse.linear_velocity.length() < 0.3, "actual thrown rigid body rests on high platform")
	_check(_platform.is_pressed() and _platform.get_corpse_count() == 1, "landed corpse triggers platform once settled")
	_check(_gate.is_open(), "connected gate opens via platform signal")
	_check(not _grabber.is_holding() and is_zero_approx(_player.carry_weight), "successful throw clears carried weight")
	_camera.rotation = Vector3.ZERO
	_player.position = Vector3(2.4, 0.5, -3)
	_player.reset_physics_interpolation()
	await _capture("gate-open")
	_player.velocity = Vector3(0, 0, -5)
	for i in range(int(Engine.physics_ticks_per_second * 1.0)):
		_player.move_and_slide()
		await physics_frame
	_player.velocity = Vector3.ZERO
	await _frames()
	_check(_player.position.z < -7.0 and _room.is_completed(), "player physically passes open gate and reaches goal")
	# 与离房自动回收相同的尸体转移 API；默认锁定门保持通行。
	corpse.relocate_for_return(Transform3D(Basis.IDENTITY, Vector3(5, 0.3, 5)))
	await _wait(0.5)
	_check(not _platform.is_pressed() and _platform.get_corpse_count() == 0, "corpse transfer removes platform load without stale overlap")
	_check(_gate.is_open(), "default latched gate stays open after corpse return")
	await _capture("goal-complete")
	await _load_lab()
	_check(_gate.is_closed() and not _platform.is_pressed() and not _room.is_completed(), "scene reload resets mechanisms and goal")
	_check(not _grabber.charged_throw_enabled, "debug throw unlock does not persist across worlds")
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/ui/main_menu.tscn", "main game entry remains menu")


func _test_supported_loads() -> void:
	_player.global_position = _platform.global_position + Vector3(0, 0.5, 0)
	_player.reset_physics_interpolation()
	await _wait(0.5)
	_check(not _platform.is_pressed(), "player standing on platform does not count as a corpse")
	_player.position = Vector3(5.5, 0.5, 3)
	# 近台面悬空、飞过和手持均不得触发一次性门。
	var corpse = _new_corpse(_platform.global_position + Vector3(0, 0.6, 0))
	corpse.freeze = true
	await _wait(0.6)
	_check(not _platform.is_pressed(), "hovering corpse inside sensor does not count as supported")
	corpse.global_position = _platform.global_position + Vector3(0, 0.075, 0)
	corpse.is_held = true
	await _wait(0.5)
	_check(not _platform.is_pressed(), "held corpse touching platform cannot activate it")
	corpse.is_held = false
	corpse.freeze = false
	corpse.linear_velocity = Vector3(0, 4, 0)
	await _wait(0.1)
	_check(not _platform.is_pressed(), "airborne rising corpse does not latch gate")
	corpse.queue_free()
	await _frames()
	# 同一 PICKUP 层的商店商品不参加配重。
	var item := load("res://scenes/shop/shop_item.tscn").instantiate() as RigidBody3D
	_room.add_child(item)
	item.global_position = _platform.global_position + Vector3(0, 0.3, 0)
	await _wait(0.6)
	_check(not _platform.is_pressed(), "shop goods on platform are ignored")
	item.queue_free()
	corpse = _new_corpse(_platform.global_position + Vector3(0, 0.3, 0))
	await _wait(0.7)
	_check(_platform.is_pressed() and _platform.get_corpse_count() == 1, "released corpse resting on top is counted")
	var extra = _new_corpse(_platform.global_position + Vector3(0.8, 0.3, 0))
	await _wait(0.7)
	_check(_platform.get_corpse_count() == 2, "two distinct corpses are counted without duplicate events")
	corpse.queue_free()
	await _wait(0.3)
	_check(_platform.is_pressed() and _platform.get_corpse_count() == 1, "removing one of two corpses keeps platform pressed")
	extra.element.ignite()
	extra.element.burn_remaining = 0.15
	await _wait(1.5)
	_check(not is_instance_valid(extra) and not _platform.is_pressed(), "burnout removes platform load cleanly")
	_check(_gate.is_open(), "latched gate remains open after last corpse burns out")


func _test_momentary_and_obstruction() -> void:
	await _load_lab()
	_gate.latch_open = false
	var opened_states: Array = []
	var closed_states: Array = []
	_gate.opened.connect(func(): opened_states.append(_gate.is_open()))
	_gate.closed.connect(func(): closed_states.append(_gate.is_closed()))
	var corpse = _new_corpse(_platform.global_position + Vector3(0, 0.3, 0))
	await _wait(0.6)
	_check(_platform.is_pressed() and not _gate.is_open(), "momentary gate begins animated opening")
	var flow := root.get_node("GameFlow")
	flow.pause_game()
	var paused_at: Vector3 = _gate.get_node("Leaf").position
	await create_timer(0.3, true, false, true).timeout
	_check(paused and _gate.get_node("Leaf").position == paused_at, "Esc pause freezes physical gate motion")
	flow.resume_game()
	await _wait(1.5)
	_check(_gate.is_open(), "resume continues opening from same position")
	_check(opened_states == [true], "opened signal observers see updated open state once")
	_player.position = Vector3(2.4, 0.5, -5)
	_player.reset_physics_interpolation()
	corpse.queue_free()
	await _wait(1.5)
	_check(_gate.is_blocked() and not _gate.is_closed(), "closing gate stops before crushing player in doorway")
	var blocked_at: Vector3 = _gate.get_node("Leaf").position
	await _wait(0.5)
	_check(_gate.get_node("Leaf").position == blocked_at, "blocked gate stays stationary while player remains")
	_check(is_equal_approx(_player.position.y, 0.5), "closing gate does not push or teleport player")
	_player.position = Vector3(5.5, 0.5, 3)
	_player.reset_physics_interpolation()
	await _wait(1.5)
	_check(_gate.is_closed() and not _gate.is_blocked(), "gate resumes closing after player leaves")
	_check(closed_states == [true], "closed signal observers see updated closed state once")
	# 快速关门仍需沿整段运动扫掠，而非只检查终点。
	corpse = _new_corpse(_platform.global_position + Vector3(0, 0.3, 0))
	await _wait(2.0)
	_check(_gate.is_open(), "platform can reopen momentary gate")
	var blocker = _new_corpse(Vector3(2.4, 0.3, -5))
	await _wait(0.4)
	_gate.move_speed = 20.0
	corpse.queue_free()
	await _wait(0.7)
	_check(_gate.is_blocked() and not _gate.is_closed() and is_instance_valid(blocker), "fast closing sweep protects corpse in doorway")
	blocker.queue_free()
	await _wait(0.4)
	_check(_gate.is_closed(), "destroyed obstruction does not leave gate permanently blocked")
	corpse = _new_corpse(_platform.global_position + Vector3(0, 0.3, 0))
	await _wait(0.7)
	_check(_gate.is_open(), "load signal remains usable after obstruction")
	_room.set_process(false)
	_platform.queue_free()
	await _wait(0.7)
	_check(_gate.is_closed(), "deleting source platform clears momentary gate request")


func _test_early_goal_arrival() -> void:
	await _load_lab()
	_player.position = Vector3(2.4, 0.5, -8)
	_player.reset_physics_interpolation()
	await _frames()
	_check(not _room.is_completed(), "entering goal before gate opens does not complete puzzle")
	var corpse = _new_corpse(_platform.global_position + Vector3(0, 0.3, 0))
	await _wait(2.0)
	_check(_gate.is_open() and _room.is_completed(), "goal entered during opening still completes when gate finishes")
	corpse.queue_free()


func _test_portability() -> void:
	await _load_lab()
	var fixture := Node3D.new()
	fixture.name = "RelocatedMechanism"
	fixture.position = Vector3(4, 1, -11)
	fixture.rotation.y = deg_to_rad(90)
	_room.add_child(fixture)
	var platform = load(PLATFORM).instantiate()
	platform.name = "Platform"
	platform.position = Vector3(-1, 0.6, 0)
	platform.platform_size = Vector3(1.8, 0.3, 1.8)
	platform.required_corpse_count = 2
	fixture.add_child(platform)
	var gate = load(GATE).instantiate()
	gate.name = "Gate"
	gate.position = Vector3(0, 0, -2)
	gate.platform_path = NodePath("../Platform")
	gate.leaf_size = Vector3(1.6, 1.5, 0.2)
	gate.open_offset = Vector3(1.7, 0.3, 0)
	gate.move_speed = 3.0
	fixture.add_child(gate)
	var original_size: Vector3 = _platform.get_node("Body/Shape").shape.size
	_check(platform.get_node("Body/Shape").shape.size == Vector3(1.8, 0.3, 1.8) and original_size == Vector3(3.2, 0.4, 2.6), "independent platform dimensions do not mutate other instances")
	_check(gate.get_node("Leaf/Shape").shape.size == Vector3(1.6, 1.5, 0.2), "custom gate collision matches configured leaf")
	var corpse = _new_corpse(platform.to_global(Vector3(-0.4, 0.3, 0)))
	await _wait(0.7)
	_check(platform.get_corpse_count() == 1 and not platform.is_pressed() and gate.is_closed(), "configured two-corpse threshold works after translation and rotation")
	var extra = _new_corpse(platform.to_global(Vector3(0.4, 0.3, 0)))
	await _wait(1.5)
	_check(platform.is_pressed() and gate.is_open(), "relocated pair links using relative node path")
	var expected: Vector3 = gate.to_global(gate.open_offset)
	_check(gate.get_node("Leaf").global_position.distance_to(expected) < 0.01, "gate travel uses local offset after parent rotation")
	platform.show_placeholder = false
	gate.show_placeholder = false
	_check(not platform.get_node("Visuals/Placeholder").visible and not gate.get_node("Leaf/Visuals/Placeholder").visible, "placeholder appearance can be hidden for art replacement")
	_check(platform.is_pressed() and gate.is_open() and not gate.get_node("Leaf/Shape").disabled, "replacing visuals leaves mechanism and collision active")
	corpse.queue_free()
	extra.queue_free()
	fixture.queue_free()
	await _frames()
