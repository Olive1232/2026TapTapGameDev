extends SceneTree

## 正式地图四个离房方向；通过实际行走验证，按真实地板隔离各房间尸体。
const EXITS := ["MainRoomExitCleaning", "MainRoomExitShop", "ShopRoomExit", "CleaningRoomExit"]
var _passed := 0
var _failed := 0
var _world
var _player
var _camera
var _grabber
var _hole
var _outlet
var _flow
var _wallet
var _exits: Dictionary = {}
var _events: Array = []
var _transfers: Array = []


func _initialize() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func():
		push_error("ROOM CLEANUP REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("ROOM CLEANUP REGRESSION FAILED: " + message)


func _frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(int(ceil(seconds * Engine.physics_ticks_per_second)))


func _bind() -> void:
	_world = current_scene
	_player = _world.get_node("Player")
	_camera = _player.get_node("Camera3D")
	_grabber = _camera.get_node("Grabber")
	_hole = _world.get_node("Hole")
	_outlet = _world.get_node("CorpseReturnOutlet")
	_exits.clear()
	_events.clear()
	_transfers.clear()
	for name in EXITS:
		var trigger = _world.get_node(name)
		_exits[name] = trigger
		trigger.room_left.connect(_record_exit.bind(name))
	_outlet.corpse_transferred.connect(func(corpse, room_id): _transfers.append({"id": corpse.get_instance_id(), "room": room_id, "value": corpse.value, "at": corpse.global_position}))
	_player.set_physics_process(false)
	_player.rotation = Vector3.ZERO
	# 本测试只验证房间归属与离开；烧门及购买由自动入洞完整流程覆盖。
	for vine in _world.get_node("VineGate").get_children():
		vine.queue_free()


func _record_exit(room: Node3D, name: String) -> void:
	_events.append({"room": room.room_id, "exit": name})


func _fresh(enabled: bool) -> void:
	reload_current_scene()
	await scene_changed
	_bind()
	await _frames(5)
	if enabled:
		_check(_hole.apply_upgrade("corpse_return"), "fixture unlocks all room routes")
	_check(_outlet.room_paths.size() == 4 and _outlet._rooms.size() == 4, "all three rooms and both main hall exits are wired")


func _stand(at: Vector3) -> void:
	at.y = 0.0
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 2.0, 1)
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = _world.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty(), "walking fixture starts on real map floor")
	if not hit.is_empty():
		at.y = hit.position.y + 0.5 + _player.safe_margin
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _side_point(trigger: Node3D, distance: float, lateral: float = 0.0) -> Vector3:
	var point: Vector3 = trigger.global_position + trigger.global_basis * (trigger.room_direction.normalized() * distance + Vector3.BACK * lateral)
	point.y = 0.0
	return point


func _walk_to(target: Vector3) -> bool:
	_player.set_physics_process(true)
	var reached := false
	for frame in range(400):
		var offset: Vector3 = target - _player.global_position
		offset.y = 0.0
		if offset.length() < 0.12:
			reached = true
			break
		_player.rotation.y = atan2(-offset.x, -offset.z)
		Input.action_press("Up")
		await physics_frame
	Input.action_release("Up")
	await _frames()
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	return reached and _player.is_on_floor()


func _new_corpse(at: Vector3, value: int = 1):
	var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
	corpse.setup(load("res://resources/enemies/monster_rat.tres"))
	corpse.value = value
	corpse.position = at
	_world.add_child(corpse)
	return corpse


func _corpses() -> Dictionary:
	var shop = _world.get_node("ShopRoom")
	return {
		&"main": _new_corpse(Vector3(0, 0.4, -15), 2),
		&"cleaning": _new_corpse(Vector3(24, 0.4, 6), 3),
		&"shop": _new_corpse(shop.to_global(Vector3(2.5, 0.45, 1.5)), 4)
	}


func _test_unpurchased() -> void:
	await _fresh(false)
	var corpses := _corpses()
	await _wait(0.3)
	for name in EXITS:
		var trigger = _exits[name]
		_stand(_side_point(trigger, 3.0))
		await _frames()
		_check(await _walk_to(_side_point(trigger, -3.0)), name + " can be crossed before upgrade")
	_check(_events.size() == 4 and _transfers.is_empty() and not _outlet.is_enabled() and _wallet.total == 0, "all exits stay unpaid and do not clean before buying")
	_check(corpses.values().all(func(corpse): return is_instance_valid(corpse)), "ordinary corpses remain in all rooms before upgrade")


func _test_exit(name: String) -> void:
	await _fresh(true)
	var trigger = _exits[name]
	var corpses := _corpses()
	await _wait(0.3)
	# 包围盒在原模型里重叠；真实地板应只把尸体归到一间房。
	for key in corpses:
		_check(trigger.contains_corpse(corpses[key]) == (key == trigger.room_id), name + " selects only its room floor: " + str(key))
	var selected = corpses[trigger.room_id]
	var original_id: int = selected.get_instance_id()
	_stand(_side_point(trigger, 3.0))
	await _frames()
	var held = _new_corpse(_camera.global_position - _camera.global_basis.z * 2.0)
	held.freeze = true
	_camera.rotation = Vector3.ZERO
	held.global_position = _camera.global_position - _camera.global_basis.z * 2.0
	await _frames()
	_grabber.try_grab()
	_check(_grabber.get_held() == held, name + " fixture carries actual corpse")
	# 进入判定区后从原侧返回，不应发出任何离开事件。
	_check(await _walk_to(_side_point(trigger, 0.3)) and await _walk_to(_side_point(trigger, 3.0)), name + " allows same side turnaround")
	_check(_events.is_empty() and _transfers.is_empty(), name + " turnaround never cleans either room")
	_check(await _walk_to(_side_point(trigger, -3.0)), name + " actual movement fully leaves room")
	_check(_events.size() == 1 and _events[0].exit == name and _events[0].room == trigger.room_id, name + " emits only departing side exactly once")
	_check(_transfers.size() == 1 and _transfers[0].id == original_id and _transfers[0].room == trigger.room_id and _transfers[0].value == selected.value and _transfers[0].at.distance_to(_outlet.get_node("SpawnPoint").global_position) < 0.01, name + " same valued corpse reappears at outlet")
	_check(_grabber.get_held() == held and is_equal_approx(_player.carry_weight, held.weight), name + " never cleans carried corpse")
	for key in corpses:
		if key != trigger.room_id:
			_check(is_instance_valid(corpses[key]) and not _transfers.any(func(entry): return entry.id == corpses[key].get_instance_id()), name + " leaves other room untouched: " + str(key))
	_check(_wallet.total == 0, name + " teleport never directly gives money")
	# 回收中和吸力接管后的同一具尸体不能被主厅另一个离开事件拉回出口。
	if trigger.room_id == &"main":
		await _walk_to(_side_point(trigger, 3.0))
		await _walk_to(_side_point(trigger, -3.0))
		_check(_transfers.filter(func(entry): return entry.id == original_id).size() == 1, name + " repeated exit cannot restart moving or attracted corpse")
		var destination: StringName = &"cleaning" if name == "MainRoomExitCleaning" else &"shop"
		_check(_transfers.any(func(entry): return entry.room == destination), name + " returning from destination also cleans that departing room")
	_grabber.drop()
	held.queue_free()
	await _wait(18.0)
	_check(not is_instance_valid(selected) and _outlet.moving_count() == 0 and root.get_node("CoinPool").active_count() > 0, name + " continues normal attraction offering and coin eruption")
	_check(_wallet.total == 0, name + " coins still wait for physical pickup")


func _test_floor_overlap() -> void:
	await _fresh(true)
	var overlap = _new_corpse(Vector3(17, 0.4, 4))
	await _wait(0.3)
	_check(_exits.CleaningRoomExit.contains_corpse(overlap) and not _exits.MainRoomExitCleaning.contains_corpse(overlap), "overlapping main and cleaning floor bounds resolve to actual upper floor")
	var on_counter = _new_corpse(_world.get_node("ShopRoom").to_global(Vector3(0, 1.7, -2)))
	await _wait(0.3)
	_check(_exits.ShopRoomExit.contains_corpse(on_counter) and not _exits.MainRoomExitShop.contains_corpse(on_counter), "corpse on shop furniture still belongs to shop floor")


func _run() -> void:
	await process_frame
	_flow = root.get_node("GameFlow")
	_wallet = root.get_node("Wallet")
	_flow.start_new_game()
	await scene_changed
	await _test_unpurchased()
	for name in EXITS:
		await _test_exit(name)
	await _test_floor_overlap()
	_flow.return_to_main_menu()
	await scene_changed
	await _frames()
	_check(root.get_node("CoinPool").active_count() == 0 and not paused, "scene exit clears returning bodies and coins")
	print("ROOM CLEANUP REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
