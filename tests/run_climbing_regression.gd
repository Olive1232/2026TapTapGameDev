extends SceneTree

## 真实输入、碰撞和角色移动验证藤蔓攀爬；测试配置仅写 /tmp。
var _passed := 0
var _failed := 0
var _world: Node3D
var _player
var _ui: BottomText


func _initialize() -> void:
	create_timer(40.0, true, false, true).timeout.connect(func():
		push_error("CLIMBING TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("CLIMBING FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _box(at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_world.add_child(body)
	return body


func _vine(at: Vector3, dimensions: Vector3 = Vector3(3, 6, 0.35)):
	var vine = load("res://scenes/prefabs/flammable_vines.tscn").instantiate()
	vine.position = at
	vine.size = dimensions
	_world.add_child(vine)
	return vine


func _place(at: Vector3, outward: Vector3 = Vector3.BACK) -> void:
	for action in ["Up", "Down", "Left", "Right"]:
		Input.action_release(action)
	_player._stop_climbing()
	_player.set("_mount_remaining", 0.0)
	_player.set_carry_weight(0.0)
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.look_at(at - outward)
	_player.get_node("Camera3D").rotation = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _frames(20)


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _run() -> void:
	await process_frame
	root.get_node("SaveGame").save_path = "/tmp/taptap-climb-save.json"
	root.get_node("GameSettings").settings_path = "/tmp/taptap-climb-settings.cfg"
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_box(Vector3(0, -0.5, 0), Vector3(160, 1, 80))
	var hud := CanvasLayer.new()
	_world.add_child(hud)
	_ui = load("res://scenes/ui/bottom_text.tscn").instantiate()
	hud.add_child(_ui)
	_player = load("res://scenes/player/player.tscn").instantiate()
	_world.add_child(_player)
	await _place(Vector3(0, 0.55, 4))
	_check(not InputMap.has_action("Jump") and InputMap.has_action("ClimbRelease"), "jump action removed and climb release configured")
	_key(KEY_SPACE)
	await _frames(15)
	_check(_player.is_on_floor() and _player.velocity.y <= 0.01 and _player.global_position.y < 0.55, "space cannot jump on normal ground")
	var vine = _vine(Vector3.ZERO)
	await _place(Vector3(0, 0.55, 0.9))
	var start_y: float = _player.global_position.y
	Input.action_press("Up")
	await _frames(35)
	_check(_player.is_climbing() and _player.global_position.y > start_y + 1.5, "W starts climbing actual vine collider and moves upward")
	_check(_ui.get_displayed_source() == &"climbing" and _ui.get_displayed_text().contains("E 松开"), "shared bottom panel explains climb controls")
	Input.action_release("Up")
	var held_y: float = _player.global_position.y
	await _frames(20)
	_check(absf(_player.global_position.y - held_y) < 0.02 and _player.is_climbing(), "releasing movement holds height without falling")
	_check(not _player.get_node("Footsteps").playing, "climbing does not play walking footsteps")
	paused = true
	Input.action_press("Up")
	await _frames(12)
	_check(is_equal_approx(_player.global_position.y, held_y) and not _ui.visible, "pause freezes climbing and hides controls")
	paused = false
	Input.action_release("Up")
	Input.action_press("Down")
	await _frames(16)
	_check(_player.is_climbing() and _player.global_position.y < held_y - 0.6, "S descends the vine")
	Input.action_release("Down")
	Input.action_press("Right")
	var start_x: float = _player.global_position.x
	await _frames(10)
	_check(_player.is_climbing() and _player.global_position.x > start_x + 0.35, "D traverses the vine sideways")
	Input.action_release("Right")
	Input.action_press("Up")
	_key(KEY_E)
	await _frames(12)
	_check(not _player.is_climbing() and _player.velocity.y < 0.0, "E releases into gravity instead of jumping")
	await _frames(15)
	_check(not _player.is_climbing(), "holding W after release does not immediately reattach")
	Input.action_release("Up")
	_check(_ui.get_displayed_source() != &"climbing", "release clears contextual climbing hint")

	await _place(Vector3(0, 0.55, 0.9))
	_player.set_carry_weight(2.0)
	start_y = _player.global_position.y
	Input.action_press("Up")
	await _frames(30)
	var loaded_height: float = _player.global_position.y - start_y
	_check(_player.is_climbing() and loaded_height > 0.65 and loaded_height < 1.1, "carrying slows climbing while preserving movement")
	Input.action_release("Up")
	_player.set_carry_weight(0.0)
	# 烧毁正在攀爬的藤蔓，引用和提示必须随之清理。
	vine.element.burn_duration = 0.1
	vine.element.ignite()
	var burn_start: float = _player.global_position.y
	await _frames(20)
	_check(not is_instance_valid(vine) and not _player.is_climbing() and _player.global_position.y < burn_start, "burn down detaches safely and restores gravity")
	_check(_ui.get_displayed_source() != &"climbing", "burn down clears climb hint")

	# 顶部有落脚平台：持续 W 应物理越过顶沿，不能卡住或穿过台面。
	var short_vine = _vine(Vector3(10, 0, 0), Vector3(3, 3.2, 0.35))
	_box(Vector3(10, 1.6, -2.5), Vector3(4, 3.2, 4))
	await _place(Vector3(10, 0.55, 0.9))
	Input.action_press("Up")
	var mounted := false
	for frame in 150:
		await physics_frame
		if _player.is_on_floor() and _player.global_position.z < -0.6 and _player._feet_position().y > 3.15:
			mounted = true
			break
	Input.action_release("Up")
	await _frames()
	_check(mounted and not _player.is_climbing(), "climbing over top reaches real platform without jump or teleport")
	_check(_player._feet_position().y >= short_vine.get_climb_top().y - 0.02, "player stands on platform surface after mantle")
	var ceiling_vine = _vine(Vector3(20, 0, 0))
	_box(Vector3(20, 3.0, 0), Vector3(5, 0.4, 4))
	await _place(Vector3(20, 0.55, 0.9))
	Input.action_press("Up")
	await _frames(65)
	_check(_player.is_climbing() and _player.global_position.y < 1.32, "ceiling collision blocks climbing without passing through geometry")
	Input.action_release("Up")
	ceiling_vine.queue_free()
	var blocked = _vine(Vector3(30, 0, 0))
	_box(Vector3(30, 1.6, 0.5), Vector3(4, 3.2, 0.1))
	await _place(Vector3(30, 0.55, 1.1))
	Input.action_press("Up")
	await _frames(30)
	_check(not _player.is_climbing() and _player.global_position.y < 0.55, "solid wall occludes vines and prevents climbing through it")
	Input.action_release("Up")
	blocked.queue_free()
	var rotated = _vine(Vector3(40, 0, 0))
	rotated.rotation.y = PI / 2
	rotated.scale = Vector3.ONE * 2
	await _place(Vector3(41.0, 0.55, 0), Vector3.RIGHT)
	Input.action_press("Up")
	await _frames(30)
	_check(_player.is_climbing() and _player.global_position.y > 1.8, "rotated and scaled vine remains climbable")
	Input.action_release("Up")
	rotated.climbable = false
	await _frames(8)
	_check(not _player.is_climbing(), "turning off climbable detaches an existing climber")
	# 前倾与后倾都会改变身体碰撞距离，单一胸前射线不能稳定抓附。
	for index in 2:
		var x := 52.0 + index * 10.0
		var inclined = _vine(Vector3(x, 0, 0))
		inclined.rotation.x = deg_to_rad(-30.0 if index == 0 else 30.0)
		await _place(Vector3(x, 0.55, 2.2))
		Input.action_press("Up")
		await _frames(60)
		_check(_player.is_climbing() and _player.global_position.y > 1.6, "inclined vine attaches and climbs, direction %d" % index)
		Input.action_release("Up")
		var height: float = _player.global_position.y
		await _frames(20)
		_check(_player.is_climbing() and absf(_player.global_position.y - height) < 0.03, "inclined vine holds height without drifting, direction %d" % index)
		Input.action_press("Down")
		await _frames(16)
		Input.action_release("Down")
		_check(_player.is_climbing() and _player.global_position.y < height - 0.4, "inclined vine supports descent, direction %d" % index)
		_key(KEY_E)
		await _frames(12)
		_check(not _player.is_climbing() and _player.velocity.y < 0.0, "inclined vine releases into gravity, direction %d" % index)
	for action in ["Up", "Down", "Left", "Right"]:
		Input.action_release(action)
	var grass = load("res://scenes/elements/flammable_grass.tscn").instantiate()
	_world.add_child(grass)
	_check(not grass.can_climb(), "grass does not inherit climbable behavior")
	_check(not InputMap.has_action("Jump"), "no jump action is recreated during gameplay")
	print("CLIMBING RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
