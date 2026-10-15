extends SceneTree

## 真实角色物理：八方向悬崖、出生边缘、窄路、缓坡、击退和正式洞沿。
var _passed := 0
var _failed := 0
var _world: Node3D
var _rat_data


func _initialize() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func():
		push_error("RAT LEDGE TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("RAT LEDGE FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _floor(at: Vector3, dimensions: Vector3, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	body.position = at
	return body


func _rat(at: Vector3):
	var rat = load("res://scenes/enemies/monster.tscn").instantiate()
	rat.data = _rat_data.duplicate()
	rat.data.voice_stream = null
	rat.data.move_speed = 0.0
	rat.position = at
	_world.add_child(rat)
	return rat


func _walk(rat, direction: Vector3, speed: float = 3.0) -> void:
	rat.data.move_speed = speed
	rat.set("_state", 1)
	rat.set("_state_timer", 100.0)
	rat.set("_direction", direction.normalized())
	rat.rotation.y = atan2(-direction.x, -direction.z)


func _run() -> void:
	await process_frame
	root.get_node("SaveGame").save_path = "/tmp/rat-ledge-save.json"
	root.get_node("GameSettings").settings_path = "/tmp/rat-ledge-settings.cfg"
	_rat_data = load("res://resources/enemies/monster_rat.tres")
	_check(_rat_data.avoid_ledges and not load("res://resources/enemies/monster_cockroach.tres").avoid_ledges, "rat opts into edge protection without changing other species")
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	_floor(Vector3(0, -0.5, 0), Vector3(8, 1, 8))
	# 四米以下还有地板，也必须被当作断崖，而不是安全的地面。
	_floor(Vector3(0, -4.5, 0), Vector3(20, 1, 20))
	var rats: Array = []
	for index in 8:
		var direction := Vector3(cos(TAU * index / 8.0), 0, sin(TAU * index / 8.0))
		var rat = _rat(direction * 2.5 + Vector3.UP * 0.05)
		rats.append(rat)
	await _frames(20)
	for index in rats.size():
		_walk(rats[index], Vector3(cos(TAU * index / 8.0), 0, sin(TAU * index / 8.0)))
	var lowest := 100.0
	for frame in 240:
		await physics_frame
		for rat in rats:
			lowest = minf(lowest, rat.global_position.y)
	_check(lowest > -0.05, "all eight directions remain on top platform throughout wandering")
	for index in rats.size():
		_check(rats[index].is_on_floor() and absf(rats[index].global_position.x) < 4 and absf(rats[index].global_position.z) < 4, "rat turns away from edge in direction %d" % index)
		rats[index].queue_free()
	# 出生时尚未 is_on_floor，脚下有支撑也必须及时停住。
	var fresh = _rat(Vector3(3.85, 0.05, 0))
	_walk(fresh, Vector3.RIGHT)
	await _frames(90)
	_check(fresh.global_position.y > -0.05 and fresh.global_position.x < 4, "spawn near edge is protected before first floor collision")
	fresh.queue_free()

	_floor(Vector3(30, -0.5, 0), Vector3(12, 1, 0.7))
	var bridge = _rat(Vector3(30, 0.05, 0))
	bridge.rotation.y = -PI / 2
	await _frames(20)
	_walk(bridge, Vector3.RIGHT)
	await _frames(40)
	_check(bridge.global_position.x > 31.5 and bridge.is_on_floor(), "rat can walk along a narrow supported bridge")
	bridge.queue_free()
	var ramp := _floor(Vector3(50, -0.5, 0), Vector3(18, 1, 8))
	ramp.rotation.z = deg_to_rad(-12.0)
	var slope = _rat(Vector3(50, 0.1, 0))
	await _frames(25)
	var start_y: float = slope.global_position.y
	_walk(slope, Vector3.RIGHT)
	await _frames(40)
	_check(slope.global_position.x > 51.5 and slope.global_position.y < start_y - 0.2 and slope.is_on_floor(), "gentle descending ramp remains traversable")
	slope.queue_free()

	# 高速冲量前方存在另一块地板，中间窄缝仍须被检测到。
	_floor(Vector3(70, -0.5, 0), Vector3(8, 1, 8))
	_floor(Vector3(78.6, -0.5, 0), Vector3(8, 1, 8))
	var pushed = _rat(Vector3(73.2, 0.05, 0))
	await _frames(20)
	var hit = load("res://scripts/weapons/hit_info.gd").new()
	hit.damage = 0.1
	hit.knockback = Vector3(100, 0, 0)
	pushed.take_hit(hit)
	await _frames(30)
	_check(pushed.global_position.x < 74 and pushed.global_position.y > -0.05 and pushed.is_on_floor(), "horizontal knockback cannot push grounded rat over a gap")
	# 玩家层和拾取层的假地板不能充当地形支撑。
	_floor(Vector3(74.3, -0.5, 0), Vector3(0.6, 1, 8), 2 | 8)
	await _frames()
	pushed.global_position = Vector3(73.8, 0, 0)
	_check(not pushed._has_ground_ahead(Vector3.RIGHT * 3, 1.0 / 60.0), "player and pickup layers do not hide an unsupported ledge")
	pushed.queue_free()
	_floor(Vector3(100, -0.5, 0), Vector3(0.3, 1, 0.3))
	var trapped = _rat(Vector3(100, 0.05, 0))
	await _frames(20)
	_walk(trapped, Vector3.RIGHT)
	await _frames(10)
	_check(trapped.global_position.y > -0.05 and trapped.get("_state") == 0 and is_zero_approx(trapped.velocity.x), "no safe direction makes rat stop rather than step off tiny platform")
	trapped.queue_free()

	# 正式地图的大洞有独立喷飞规则，不能靠掉下去再喷回来伪装防坠落。
	var flow = root.get_node("GameFlow")
	flow.start_new_game()
	await scene_changed
	_world = current_scene
	_world.get_node("Player").set_physics_process(false)
	for node in _world.get_children():
		if "enabled" in node:
			node.enabled = false
	var hole = _world.get_node("Hole")
	rats.clear()
	for index in 8:
		var radial := Vector3(cos(TAU * index / 8.0), 0, sin(TAU * index / 8.0))
		var rat = _rat(hole.global_position + radial * 11.5 + Vector3.UP * 0.5)
		rats.append(rat)
	await _frames(30)
	for index in rats.size():
		_walk(rats[index], -Vector3(cos(TAU * index / 8.0), 0, sin(TAU * index / 8.0)))
	var entered_pit := false
	var ejected := false
	for frame in 180:
		await physics_frame
		for rat in rats:
			var relative: Vector3 = rat.global_position - hole.global_position
			entered_pit = entered_pit or Vector2(relative.x, relative.z).length() < hole.player_fall_radius
			ejected = ejected or rat.velocity.y > 8.0
	_check(not entered_pit and not ejected, "all eight actual pit approaches avoid falling and never require ejection")
	for index in rats.size():
		_check(rats[index].is_on_floor() and rats[index].health == rats[index].data.max_health, "actual rim rat remains safely grounded in direction %d" % index)
	print("RAT LEDGE RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
