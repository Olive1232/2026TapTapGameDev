extends SceneTree

## Godot --headless --path . --fixed-fps 60 --script res://tests/run_element_regression.gd
## 使用真实 Area3D、碰撞、输入、剑横扫和房间，不以直接调用伤害替代游玩流程。
var _passed := 0
var _failed := 0
var _stage: Node3D

class HitRecorder extends StaticBody3D:
	var hits := 0
	var tags := PackedStringArray()
	func take_hit(info) -> void:
		hits += 1
		tags = info.tags
	func get_hit_center() -> Vector3:
		return global_position


func _initialize() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("ELEMENT REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("ELEMENT REGRESSION FAILED: " + message)


func _frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(int(ceil(seconds * Engine.physics_ticks_per_second)) + 1)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames()


func _attack() -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames()


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_stage.add_child(body)
	body.position = at
	return body


func _new_prop(at: Vector3, duration: float = 0.95):
	var prop = load("res://scenes/elements/flammable_vines.tscn").instantiate()
	prop.get_node("ElementComponent").burn_duration = duration
	prop.get_node("ElementComponent").spread_interval = 0.15
	_stage.add_child(prop)
	prop.global_position = at
	return prop


func _run() -> void:
	await process_frame
	_stage = Node3D.new()
	root.add_child(_stage)
	current_scene = _stage
	_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	await _test_sword()
	await _test_spread()
	_stage.queue_free()
	await process_frame
	await _test_room()
	paused = false
	print("ELEMENT REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_sword() -> void:
	var player = load("res://scenes/player/player.tscn").instantiate()
	_stage.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(5, 0.5, 5)
	var camera = player.get_node("Camera3D")
	var sword = player.get_node("Camera3D/WeaponRig/WeaponPivot/Mount")
	var original_tags: PackedStringArray = sword.data.damage_tags.duplicate()
	var torch = load("res://scenes/elements/torch.tscn").instantiate()
	_stage.add_child(torch)
	torch.global_position = sword.element.global_position - Vector3(0, 1.45, 0)
	await _wait(0.4)
	_check(not sword.is_burning(), "un-oiled sword touching torch does not ignite")
	sword.apply_oil()
	_check(sword.oiled and not sword.is_burning(), "oil grants flammability without directly igniting")
	await _wait(0.4)
	_check(sword.is_burning() and sword.fire_swings_remaining == 5, "real blade contact ignites oiled sword")
	_check(sword.element.get_parent() == sword.get_node("Pivot"), "fire contact follows visual blade pivot")
	_check(sword.get_damage_tags().has("fire"), "burning sword contributes runtime fire damage tag")
	_check(sword.data.damage_tags == original_tags, "ignition leaves shared SwordData untouched")
	torch.position = Vector3(18, 0, 18)
	await _frames()
	sword.apply_oil()
	_check(sword.fire_swings_remaining == 5, "repeat oil does not change current fire budget")
	for i in range(4):
		_check(sword.try_swing(), "burning swing accepted " + str(i + 1))
		_check(not sword.try_swing(), "rejected rapid click does not start another swing")
		_check(sword.fire_swings_remaining == 4 - i, "only successful swing consumes fire budget")
		await _wait(0.55)
		_check(sword.is_burning(), "first four swings retain flame")
	var recorder := HitRecorder.new()
	recorder.collision_layer = 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, 0.45, 0.45)
	shape.shape = box
	recorder.add_child(shape)
	_stage.add_child(recorder)
	recorder.global_position = camera.global_transform * Vector3(0, -0.34, -1.4)
	await _frames()
	_check(sword.try_swing(), "fifth swing accepted")
	_check(sword.is_burning() and sword.fire_swings_remaining == 0, "fifth swing stays lit while attacking")
	await _wait(0.65)
	_check(recorder.hits == 1 and recorder.tags.has("fire"), "actual fifth hit delivers fire exactly once")
	_check(not sword.is_burning() and sword.oiled, "fifth completed swing extinguishes but keeps oil")
	_check(not sword.get_damage_tags().has("fire"), "extinguished sword loses only temporary fire tag")
	_check(is_instance_valid(sword) and sword.data.damage_tags == original_tags, "sword survives five swings without resource mutation")
	recorder.queue_free()
	torch.global_position = sword.element.global_position - Vector3(0, 1.45, 0)
	await _wait(0.4)
	_check(sword.is_burning() and sword.fire_swings_remaining == 5, "oiled sword can be re-ignited for five more swings")
	torch.position = Vector3(18, 0, 18)
	await _frames()
	sword.try_swing()
	sword.apply_oil()
	_check(sword.fire_swings_remaining == 4, "repeat oil during burning does not refill swings")
	await _wait(0.6)
	sword.set_sword_data(sword.data)
	_check(not sword.is_burning() and not sword.oiled, "changing sword resets temporary oil and fire")
	player.queue_free()
	torch.queue_free()
	await _frames()


func _test_spread() -> void:
	var first = _new_prop(Vector3(-9, 0, -5))
	var second = _new_prop(Vector3(-7.8, 0, -5))
	var third = _new_prop(Vector3(-6.6, 0, -5))
	var behind_wall = _new_prop(Vector3(-5.4, 0, -5))
	var wall := _box(Vector3(-6.0, 1.6, -5), Vector3(0.12, 3.2, 3))
	var torch = load("res://scenes/elements/torch.tscn").instantiate()
	_stage.add_child(torch)
	torch.position = Vector3(-9.9, 0.15, -5)
	await _wait(0.05)
	_check(first.element.burning, "torch contact ignites first vine")
	_check(not third.element.burning, "fire takes time to propagate through chain")
	var burn_time: float = first.element.burn_remaining
	paused = true
	await create_timer(0.12, true, false, true).timeout
	_check(is_equal_approx(first.element.burn_remaining, burn_time), "pause freezes burning countdown")
	_check(not third.element.burning, "pause freezes fire propagation")
	paused = false
	await _wait(0.5)
	_check(second.element.burning and third.element.burning, "burning vines propagate beyond torch reach")
	_check(not behind_wall.element.burning, "wall blocks propagation between overlapping contact areas")
	await _wait(1.0)
	_check(not is_instance_valid(first) and not is_instance_valid(second) and not is_instance_valid(third), "burned vines are destroyed")
	_check(is_instance_valid(behind_wall), "protected vine survives")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(-10.5, 1.6, -5), Vector3(-6.15, 1.6, -5), 1)
	_check(_stage.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "burn-down removes obstacle collision")
	_check(is_instance_valid(torch) and torch.get_node("ElementComponent").is_fire_source(), "torch remains a permanent fire source")
	var protected = _new_prop(Vector3(-2, 0, -5), 0.2)
	protected.element.tags.append("indestructible")
	protected.element.ignite()
	await _wait(0.3)
	_check(is_instance_valid(protected) and not protected.element.burning, "indestructible target extinguishes without being destroyed")
	var grass = load("res://scenes/elements/flammable_grass.tscn").instantiate()
	grass.get_node("ElementComponent").burn_duration = 0.2
	_stage.add_child(grass)
	grass.position = Vector3(-2, 0, 0)
	grass.element.ignite()
	await _wait(0.3)
	_check(not is_instance_valid(grass), "flammable grass also burns down")
	behind_wall.queue_free()
	wall.queue_free()
	protected.queue_free()
	torch.queue_free()
	await _frames()


func _test_room() -> void:
	var room = load("res://scenes/debug/element_lab.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await _frames()
	var player = room.get_node("Player")
	player.set_physics_process(false)
	var camera = player.get_node("Camera3D")
	var sword = player.get_node("Camera3D/WeaponRig/WeaponPivot/Mount")
	var grabber = camera.get_node("Grabber")
	var flow = root.get_node("GameFlow")
	var wallet = root.get_node("Wallet")
	wallet.set_total(0)
	_check(flow.is_in_game(), "new room participates in game pause lifecycle")
	_check(not room.is_gate_open(), "room starts with blocked route")
	_check(not room.get_node("CockroachSpawner").enabled and not room.get_node("RatSpawner").enabled, "room spawners wait for route to open")
	player.position = Vector3(0, 0.5, -4.5)
	_check(player.test_move(player.global_transform, Vector3(0, 0, -3)), "vine collision physically blocks doorway")
	player.position = Vector3(-1.5, 0.5, 6.2)
	camera.look_at(room.get_node("OilStation").global_position + Vector3(0, 0.65, 0), Vector3.UP)
	await _key(KEY_E)
	_check(sword.oiled, "real E input applies oil at aimed station")
	var torch = room.get_node("Torch")
	player.position = torch.position + Vector3(0.55, 0.5, 1.5)
	camera.look_at(torch.get_node("ElementComponent").global_position, Vector3.UP)
	# 将玩家平移到剑身与火焰接触，保留落地高度与实际模型姿态。
	var contact_delta: Vector3 = torch.get_node("ElementComponent").global_position - sword.element.global_position
	player.position += Vector3(contact_delta.x, 0, contact_delta.z)
	await _wait(0.5)
	_check(sword.is_burning(), "room torch physically ignites the actual sword")
	var remaining: int = sword.fire_swings_remaining
	flow.pause_game()
	await _key(KEY_E)
	await _attack()
	await _key(KEY_R)
	_check(current_scene == room and sword.fire_swings_remaining == remaining, "paused E/attack/reload do not affect room")
	flow.resume_game()
	var vine = room.get_node("VineGate/Vines1")
	player.position = Vector3(-1.2, 0.5, -4.2)
	camera.look_at(vine.get_hit_center(), Vector3.UP)
	await _frames()
	await _attack()
	await _wait(0.6)
	_check(vine.element.burning, "actual burning sword ignites doorway vines")
	await _wait(4.8)
	_check(room.is_gate_open() and room.get_node("VineGate").get_child_count() == 0, "fire opens entire vine gate")
	player.position = Vector3(0, 0.5, -4.5)
	_check(not player.test_move(player.global_transform, Vector3(0, 0, -3)), "cleared doorway is physically passable")
	_check(room.get_node("CockroachSpawner").enabled and room.get_node("RatSpawner").enabled, "opened route enables both configured spawners")
	await _wait(6.2)
	_check(room.get_node("CockroachSpawner").get_alive_count() > 0, "cockroach point generates after unlock")
	_check(room.get_node("RatSpawner").get_alive_count() > 0, "rat point generates selected monster")
	var rat: Node3D
	for child in room.get_node("RatSpawner").get_children():
		if child.has_method("take_hit"):
			rat = child
			break
	if rat == null:
		_check(false, "rat available for room combat")
		return
	rat.set_physics_process(false)
	player.position = Vector3(0, 0.5, -11)
	camera.rotation = Vector3(deg_to_rad(-45), 0, 0)
	rat.global_position = camera.global_transform * Vector3(0, -0.34, -1.4)
	var corpses: Array = []
	root.get_node("EventBus").corpse_spawned.connect(func(corpse): corpses.append(corpse), CONNECT_ONE_SHOT)
	await _frames()
	await _attack()
	await _wait(0.7)
	_check(not is_instance_valid(rat) and not corpses.is_empty(), "real room sword attack kills rat and creates corpse")
	if corpses.is_empty():
		return
	var corpse = corpses[0]
	corpse.freeze = true
	corpse.global_position = camera.global_position - camera.global_basis.z * 2.0
	await _frames()
	_check(grabber.try_grab() and corpse.is_held, "room corpse can be grabbed from screen center")
	# 位于墙后时不能隔墙抓取；清理前一次持有再测试。
	grabber.drop()
	player.position = Vector3(4, 0.5, -4.8)
	camera.rotation = Vector3.ZERO
	corpse.global_position = Vector3(4, 2.05, -7.2)
	await _frames()
	_check(not grabber.try_grab(), "partition wall prevents grabbing corpse through wall")
	player.position = Vector3(0, 0.5, -10)
	corpse.global_position = camera.global_position - camera.global_basis.z * 2.0
	await _frames()
	_check(grabber.try_grab(), "corpse can be picked up again in clear space")
	player.position = Vector3(0, 0.5, 2.2)
	corpse.global_position = Vector3(0.1, 1.8, 0.1)
	await _frames()
	_check(not is_instance_valid(corpse) and not grabber.is_holding() and is_zero_approx(player.carry_weight), "held corpse at hole height 1.8 is sacrificed and weight clears")
	await _wait(4.0)
	_check(wallet.total == 2 and room.is_flow_complete(), "room sacrifice erupts coins and completes flow with unchanged value")
	reload_current_scene()
	await scene_changed
	await _frames()
	room = current_scene
	sword = room.get_node("Player/Camera3D/WeaponRig/WeaponPivot/Mount")
	_check(not room.is_gate_open() and not sword.oiled and not sword.is_burning(), "reload resets barrier, oil and fire")
	_check(wallet.total == 2, "room reload preserves current wallet")
	_check(root.get_node("CoinPool").active_count() == 0, "reload leaves no stale active coins")
