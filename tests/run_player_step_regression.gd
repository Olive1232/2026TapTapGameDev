extends SceneTree

## 使用真实玩家、输入和物理碰撞验证自动跨步；不加载或改写世界模型。
var _passed := 0
var _failed := 0
var _world: Node3D
var _player


func _initialize() -> void:
	create_timer(40.0, true, false, true).timeout.connect(func():
		push_error("PLAYER STEP TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("PLAYER STEP FAILED: " + message + " position=" + str(_player.global_position))


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_world.add_child(body)
	return body


func _step(x: float, height: float) -> void:
	_box(Vector3(x, height * 0.5, -3), Vector3(4, height, 6))


func _place(at: Vector3, yaw: float = 0.0) -> void:
	for action in ["Up", "Down", "Left", "Right"]:
		Input.action_release(action)
	_player.max_step_height = 0.4
	_player._stop_climbing()
	_player.set("_mount_remaining", 0.0)
	_player.set_carry_weight(0.0)
	_player.rotation = Vector3(0, yaw, 0)
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _frames(20)


func _walk(frames: int = 33, action: String = "Up") -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)


func _run() -> void:
	await process_frame
	root.get_node("SaveGame").save_path = "/tmp/taptap-player-step-save.json"
	root.get_node("GameSettings").settings_path = "/tmp/taptap-player-step-settings.cfg"
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_box(Vector3(70, -0.5, 0), Vector3(170, 1, 80))
	_player = load("res://scenes/player/player.tscn").instantiate()
	_world.add_child(_player)
	_step(0, 0.3)
	await _place(Vector3(0, 0.55, 2))
	_player.max_step_height = 0.0
	await _walk()
	_check(_player.global_position.z > 0.45, "original movement reproduces getting stuck against a small step")
	await _place(Vector3(0, 0.55, 2))
	await _walk()
	_check(_player.global_position.z < -3.0 and _player.is_on_floor(), "same step is traversable with automatic stepping")
	_check(absf(_player._feet_position().y - 0.3) < 0.01, "player rests on the actual step surface")

	for index in 4:
		var height: float = [0.03, 0.15, 0.39, 0.4][index]
		var x := 8.0 + index * 6.0
		_step(x, height)
		await _place(Vector3(x, 0.55, 2))
		await _walk()
		_check(_player.global_position.z < -3.0 and absf(_player._feet_position().y - height) < 0.01,
			"walks over small uneven surface %.2fm" % height)

	_step(32, 0.65)
	await _place(Vector3(32, 0.55, 2))
	await _walk()
	_check(_player.global_position.z > 0.45 and _player._feet_position().y < 0.02, "high obstacle still blocks without artificial climbing")
	_step(38, 0.3)
	_box(Vector3(38, 3.15, 0), Vector3(4, 2, 10))
	await _place(Vector3(38, 0.55, 2))
	await _walk()
	_check(_player.global_position.z > 0.45 and _player._feet_position().y < 0.02, "insufficient headroom prevents stepping into ceiling")
	_step(44, 0.1)
	_box(Vector3(44, 3.15, 0), Vector3(4, 2, 10))
	await _place(Vector3(44, 0.55, 2))
	await _walk()
	_check(_player.global_position.z < -3.0, "short step works when headroom allows only its actual height")

	await _place(Vector3(0, 0.85, -2))
	Input.action_press("Down")
	var stayed_grounded := true
	for frame in 28:
		await physics_frame
		stayed_grounded = stayed_grounded and _player.is_on_floor()
	Input.action_release("Down")
	await process_frame
	_check(stayed_grounded and _player.global_position.z > 2.0 and _player._feet_position().y < 0.01,
		"walking down a small step stays attached to ground")

	for index in 7:
		var height := (index + 1) * 0.2
		_box(Vector3(50, height * 0.5, -0.75 - index * 1.5), Vector3(4, height, 1.5))
	await _place(Vector3(50, 0.55, 2))
	await _walk(65)
	_check(_player.global_position.z < -8.0 and _player._feet_position().y > 1.19, "successive small steps can be climbed continuously")

	_step(60, 0.3)
	await _place(Vector3(61.5, 0.55, 2), PI / 8)
	await _walk(28)
	_check(_player.global_position.z < -2.0 and _player._feet_position().y > 0.29, "rotated body approaches and crosses a step diagonally")
	await _place(Vector3(0, 0.55, 2))
	_player.set_carry_weight(2.0)
	await _walk(52)
	_check(_player.global_position.z < -2.5 and _player.is_on_floor(), "carrying preserves automatic stepping at reduced speed")

	await _place(Vector3(70, 0.55, 2))
	var start: Vector3 = _player.global_position
	await _walk(30)
	_check(absf(_player.global_position.y - start.y) < 0.01 and absf(_player.global_position.z - start.z + 5.0) < 0.2,
		"flat ground keeps original height and movement speed")
	_player.global_position = Vector3(70, 5, 2)
	_player.velocity = Vector3(0, 6, 0)
	await _frames(1)
	_check(_player.velocity.y > 5.5 and _player.global_position.y > 5.0, "upward ejection remains airborne and is not snapped to floor")
	var ramp := _box(Vector3(80, 1.0, -3), Vector3(4, 0.2, 6))
	ramp.rotation.x = deg_to_rad(20)
	await _place(Vector3(80, 0.55, 2))
	await _walk()
	_check(_player.global_position.z < -2.7 and _player._feet_position().y > 1.0 and _player.is_on_floor(),
		"ordinary walkable slopes continue to work with stepping enabled")
	_box(Vector3(86, 0.025, 0), Vector3(4, 0.05, 0.06))
	await _place(Vector3(86, 0.55, 2))
	await _walk()
	_check(_player.global_position.z < -3.0 and _player._feet_position().y < 0.01,
		"thin raised ground seam can be crossed and settles back to floor")
	_step(92, 1.0)
	await _place(Vector3(92, 1.55, -2))
	await _walk(20, "Down")
	_check(not _player.is_on_floor() and _player.velocity.y < -0.5 and _player._feet_position().y > 0.5,
		"large drop retains natural falling instead of snapping down a cliff")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4, 0.3, 6)
	var mesh_step := _box(Vector3(98, 0.15, -3), mesh.size)
	mesh_step.get_child(0).shape = mesh.create_trimesh_shape()
	await _place(Vector3(98, 0.55, 2))
	await _walk()
	_check(_player.global_position.z < -3.0 and absf(_player._feet_position().y - 0.3) < 0.01,
		"triangulated static terrain uses the same stepping path as imported world collisions")
	await _place(Vector3(32, 0.55, 1.2))
	_player.global_position.y += 0.15
	_player.velocity = Vector3(0, 2, 0)
	await _walk(8)
	_check(_player.global_position.z > 0.45 and _player._feet_position().y < 0.65, "airborne motion cannot use auto step to climb a high obstacle")
	_check(not InputMap.has_action("Jump"), "automatic stepping does not restore a jump key")
	print("PLAYER STEP RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
