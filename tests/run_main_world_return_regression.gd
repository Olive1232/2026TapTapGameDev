extends SceneTree

## 当前原样地图：真实行走穿越开放入口，封闭岩壁不触发离房回收。
const ROOM_POINTS := {
	&"shop": Vector3(-86, 2.3, 2),
	&"main": Vector3(-53, 3.4, 8),
	&"entry": Vector3(0, 3.8, -15),
	&"cleaning": Vector3(45, 7.1, -20),
	&"deep": Vector3(91, 7.1, -23),
	&"gallery": Vector3(51, 3.8, 25),
}
var _passed := 0
var _failed := 0
var _world
var _player
var _hole
var _outlet
var _events: Array = []
var _transfers: Array = []


func _initialize() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func():
		push_error("MAIN WORLD RETURN TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("MAIN WORLD RETURN FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _fresh(enabled: bool) -> void:
	root.get_node("GameFlow").start_new_game()
	await scene_changed
	_world = current_scene
	_player = _world.get_node("Player")
	_player.set_physics_process(false)
	_hole = _world.get_node("Hole")
	_outlet = _world.get_node("CorpseReturnOutlet")
	_world.get_node("WorldDialogue").restore_progress({"shop_visited": true, "hole_introduced": true})
	# 只验证入口穿越，烧门与升降门解谜保持各自专项覆盖。
	for node in _world.get_children():
		if "enabled" in node:
			node.enabled = false
		if node.has_method("can_climb"):
			node.queue_free()
		if node.name == "LiftGate":
			for shape in node.find_children("*", "CollisionShape3D", true, false):
				shape.disabled = true
	_events.clear()
	_transfers.clear()
	for room in _outlet._rooms:
		room.room_left.connect(func(departed): _events.append(departed.name))
	_outlet.corpse_transferred.connect(func(corpse, room_id): _transfers.append({"id":corpse.get_instance_id(), "room":room_id, "value":corpse.value, "at":corpse.global_position}))
	await _frames()
	if enabled:
		_check(_hole.apply_upgrade("corpse_return"), "fixture enables connected soul egg")


func _corpses() -> Dictionary:
	var result := {}
	for id in ROOM_POINTS:
		var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
		corpse.setup(load("res://resources/enemies/monster_rat.tres"))
		corpse.position = ROOM_POINTS[id]
		corpse.freeze = true
		corpse.value = result.size() + 1
		_world.add_child(corpse)
		result[id] = corpse
	return result


func _ground(at: Vector3, floor_y: float) -> Variant:
	var space: PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(Vector3(at.x, floor_y + 1.3, at.z), Vector3(at.x, floor_y - 4.0, at.z), 1)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.71:
		return null
	var support: float = hit.position.y
	for corner in [Vector3(-0.5,0,-0.5), Vector3(-0.5,0,0.5), Vector3(0.5,0,-0.5), Vector3(0.5,0,0.5)]:
		var p: Vector3 = hit.position + corner
		var foot := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p - Vector3.UP * 0.6, 1))
		if foot.is_empty() or foot.normal.y < 0.71:
			return null
		support = maxf(support, foot.position.y)
	var position := Vector3(at.x, support + 0.503, at.z)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _player.get_node("CollisionShape3D").shape
	query.collision_mask = 1
	# 脚角射线会漏掉坡道接缝位于脚掌中间的凸点，整个人物形状下扫取得实际支撑高度。
	var lift: float = _player.max_step_height + 0.05
	query.transform = Transform3D(Basis.IDENTITY, position + Vector3.UP * (0.5 + lift))
	query.motion = Vector3.DOWN * (lift + 0.05)
	var fractions := space.cast_motion(query)
	if fractions[0] >= 1.0:
		return null
	query.transform.origin += query.motion * fractions[0] + Vector3.UP * 0.003
	query.motion = Vector3.ZERO
	return query.transform.origin - Vector3.UP * 0.5 if space.intersect_shape(query, 1).is_empty() else null


func _route(trigger) -> Array:
	var inward: Vector3 = trigger.room_direction.normalized()
	var lateral := inward.cross(Vector3.UP)
	var size: Vector3 = trigger.get_node("Shape").shape.size
	var width := size.z if absf(inward.x) > 0.5 else size.x
	var floor_y: float = {&"shop":1.815, &"main":2.873, &"entry":3.257, &"cleaning":6.593, &"deep":6.593, &"gallery":3.257}[trigger.room_id]
	var offsets := [0.0]
	for index in range(1, int(width)):
		offsets.append(index * 0.5)
		offsets.append(index * -0.5)
	for offset in offsets:
		if absf(offset) > width * 0.5 - 0.8:
			continue
		var inside = _ground(trigger.global_position + inward * 2.4 + lateral * offset, floor_y)
		var outside = _ground(trigger.global_position - inward * 2.4 + lateral * offset, floor_y)
		var middle = _ground(trigger.global_position + lateral * offset, floor_y)
		if inside != null and outside != null and middle != null:
			var clear := true
			for index in range(1, 16):
				var point: Vector3 = trigger.global_position + inward * lerpf(2.4, -2.4, index / 16.0) + lateral * offset
				if _ground(point, floor_y) == null:
					clear = false
					break
			if clear:
				return [inside, middle, outside]
	return []


func _walk_to(target: Vector3) -> bool:
	_player.set_physics_process(true)
	var reached := false
	for frame in 150:
		var offset: Vector3 = target - _player.global_position
		offset.y = 0.0
		if offset.length() < 0.13:
			reached = true
			break
		_player.rotation.y = atan2(-offset.x, -offset.z)
		Input.action_press("Up")
		await physics_frame
	Input.action_release("Up")
	await _frames()
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	if not reached:
		push_error("RETURN WALK blocked at %s towards %s" % [_player.global_position,target])
	return reached and _player.is_on_floor()


func _test_exit(name: String, enabled: bool) -> void:
	await _fresh(enabled)
	var trigger = _world.get_node("SoulEggZones/" + name)
	var route := _route(trigger)
	_check(not route.is_empty(), name + " has a clear route across its real doorway")
	if route.is_empty():
		return
	var corpses := _corpses()
	for room in corpses:
		_check(trigger.contains_corpse(corpses[room]) == (room == trigger.room_id), name + " selects only departing room " + str(room))
	_player.global_position = route[0]
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _frames()
	_check(await _walk_to(route[1]) and await _walk_to(route[0]), name + " permits same side turnaround")
	_check(_events.is_empty() and _transfers.is_empty(), name + " turnaround does not clean")
	_check(await _walk_to(route[2]), name + " actual WASD fully crosses entrance")
	_check(_events.size() == 1 and _events[0] == name, name + " emits only one departing event")
	if not enabled:
		_check(_transfers.is_empty() and corpses.values().all(func(corpse): return is_instance_valid(corpse)), "unpaid soul egg does not transfer any corpse")
		return
	var selected = corpses[trigger.room_id]
	_check(_transfers.size() == 1 and _transfers[0].id == selected.get_instance_id() and _transfers[0].room == trigger.room_id and _transfers[0].value == selected.value,
		name + " moves the original corpse and preserves its value")
	_check(not _transfers.is_empty() and _transfers[0].at.distance_to(_outlet.get_node("SpawnPoint").global_position) < 0.01, name + " reappears at the visible outlet")
	_check(root.get_node("Wallet").total == 0, name + " never grants money before coin pickup")
	_check(await _walk_to(route[0]) and await _walk_to(route[2]), name + " permits reentry and another departure")
	_check(_transfers.size() == 1, name + " does not duplicate returning or attracted corpse")
	if name == "ShopExit":
		await _frames(1200)
		_check(not is_instance_valid(selected) and _outlet.moving_count() == 0 and root.get_node("CoinPool").active_count() > 0, "outlet corpse reaches original hole and settles into physical coins")
		_check(root.get_node("Wallet").total == 0, "settled coins still require contact pickup")


func _test_closed_exit(name: String) -> void:
	await _fresh(true)
	var trigger = _world.get_node("SoulEggZones/" + name)
	_check(not trigger.monitoring, name + " is inactive at the original closed wall")
	var corpses := _corpses()
	var from_gallery := name == "GalleryExitCleaning"
	var start := Vector3(51, 3.76, 10) if from_gallery else Vector3(51, 7.1, -10)
	_player.recover_from_fall(start)
	_player.rotation.y = 0.0 if from_gallery else PI
	_player.set_physics_process(true)
	await _frames(30)
	Input.action_press("Up")
	await _frames(120)
	Input.action_release("Up")
	await _frames(20)
	var blocked: bool = _player.global_position.z > 5.8 if from_gallery else _player.global_position.z < 5.0
	_check(blocked and _player.is_on_floor(), name + " original wall blocks real WASD movement")
	_check(_events.is_empty() and _transfers.is_empty(), name + " approaching the closed wall never returns corpses")
	_check(corpses.values().all(func(corpse): return is_instance_valid(corpse)), name + " preserves all room corpses")


func _test_outlet_handoff() -> void:
	await _fresh(true)
	var corpses: Array = []
	for monster_id in ["rat", "cockroach"]:
		var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
		corpse.setup(load("res://resources/enemies/monster_" + monster_id + ".tres"))
		corpse.position = ROOM_POINTS[&"cleaning"] + Vector3.RIGHT * corpses.size() * 2.0
		_world.add_child(corpse)
		corpses.append(corpse)
	await _frames(120)
	_check(corpses.all(func(corpse): return corpse.sleeping and not corpse.freeze), "real room corpses settle before return without freezing the fixture")
	corpses[0].sleeping = false
	corpses[0].linear_velocity = Vector3.RIGHT
	var ids := corpses.map(func(corpse): return corpse.get_instance_id())
	var values := corpses.map(func(corpse): return corpse.value)
	_outlet._on_room_left(_world.get_node("SoulEggZones/CleaningExitEntry"))
	await _frames(1)
	_check(_transfers.size() == 2 and _transfers.all(func(entry): return ids.has(entry.id)), "awake and sleeping corpses both transfer without cloning")
	# 不只检查信号发出瞬间的坐标：等物理引擎更新重叠后仍应先从小洞移出。
	await _frames(30)
	var spawn: Vector3 = _outlet.get_node("SpawnPoint").global_position
	_check(corpses.all(func(corpse): return is_instance_valid(corpse) and corpse.global_position.distance_to(spawn) < 2.0), "returned corpses remain visibly near the small outlet for the first half second")
	_check(_outlet.moving_count() == 2 and corpses.all(func(corpse): return not _hole.is_in_attraction_range(corpse)), "outlet drives corpses before handing them to main hole attraction")
	_check(not _hole.has_pending() and root.get_node("CoinPool").active_count() == 0, "return does not immediately offer corpses or produce coins")
	for index in corpses.size():
		if is_instance_valid(corpses[index]):
			_check(corpses[index].get_instance_id() == ids[index] and corpses[index].value == values[index], "physical outlet movement preserves original corpse identity and value")
	await _frames(600)
	_check(corpses.all(func(corpse): return not is_instance_valid(corpse)) and _outlet.moving_count() == 0 and root.get_node("CoinPool").active_count() > 0, "outlet movement subsequently hands off to attraction, offering and physical coins")
	_check(root.get_node("Wallet").total == 0, "automatic return still requires coin pickup")


func _run() -> void:
	await process_frame
	root.get_node("SaveGame").save_path = "/tmp/taptap-main-world-return-save.json"
	root.get_node("GameSettings").settings_path = "/tmp/taptap-main-world-return-settings.cfg"
	await _fresh(false)
	_check(_outlet._rooms.size() == 12 and _outlet.room_paths.size() == 12, "all twelve authored room entrance references remain")
	_check(_outlet._rooms.filter(func(room): return room.monitoring).size() == 10, "ten entrances are active while the restored gallery wall has two inactive exits")
	_check(not _outlet.is_enabled() and _hole.can_apply_upgrade("corpse_return"), "outlet is initially disabled and soul egg can be purchased")
	var distance: float = Vector2(_outlet.global_position.x - _hole.global_position.x, _outlet.global_position.z - _hole.global_position.z).length()
	var attraction_radius: float = _hole.get_node("AttractZone/Shape").shape.radius
	_check(distance > attraction_radius + _outlet.move_speed and distance < attraction_radius + 6.0, "small outlet leaves at least one second of movement before main hole attraction")
	await _test_outlet_handoff()
	await _test_exit("ShopExit", false)
	var names: Array[String] = []
	for room in _outlet._rooms:
		names.append(room.name)
	for name in names:
		if name in ["CleaningExitGallery", "GalleryExitCleaning"]:
			await _test_closed_exit(name)
		else:
			await _test_exit(name, true)
	root.get_node("GameFlow").return_to_main_menu()
	await scene_changed
	await _frames()
	_check(root.get_node("CoinPool").active_count() == 0, "scene exit clears outlet and coin references")
	print("MAIN WORLD RETURN RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
