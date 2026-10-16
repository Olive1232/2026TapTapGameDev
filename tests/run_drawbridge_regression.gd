extends SceneTree

## 正式地图的实体传火、桥面行走与真实存档；文件只写 /tmp。
var _passed := 0
var _failed := 0
var _world
var _player
var _bridges
var _flow
var _save
var _phase := "full"
var _directory := "/tmp/taptap-drawbridge-regression"


func _initialize() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func():
		push_error("DRAWBRIDGE TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("DRAWBRIDGE FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _bind() -> void:
	_world = current_scene
	_player = _world.get_node("Player")
	_player.set_physics_process(false)
	_bridges = _world.get_node("Drawbridges")
	_world.get_node("WorldDialogue").restore_progress({"shop_visited": true, "hole_introduced": true})
	for node in _world.get_children():
		if node.has_method("get_alive_count"):
			node.enabled = false
	await _frames()


func _new_game() -> void:
	_check(_flow.start_new_game().ok, "new game starts")
	await scene_changed
	await _bind()


func _load_game() -> void:
	_check(_flow.load_game().ok, "saved game loads")
	await scene_changed
	await _bind()


func _rope_present(bridge) -> bool:
	return bridge.has_node("Rope") and not bridge.is_rope_burned() and not bridge.is_lowered()


func _floor_at(at: Vector3) -> Dictionary:
	return _world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at - Vector3.UP * 0.6, 1))


func _walk_across(bridge) -> void:
	var start: Vector3 = bridge.to_global(Vector3(0, 0.503, 1.1))
	var target: Vector3 = bridge.to_global(Vector3(0, 0.503, -bridge.deck_size.z - 1.2))
	_player.recover_from_fall(start)
	_player.rotation = Vector3(0, -PI * 0.5, 0)
	_player.get_node("Camera3D").rotation = Vector3.ZERO
	_player.set_physics_process(true)
	await _frames(10)
	var reached := false
	var safe := true
	Input.action_press("Up")
	for frame in 160:
		await physics_frame
		safe = safe and not _player.is_rift_recovering()
		if _player.global_position.x >= target.x:
			reached = true
			break
	Input.action_release("Up")
	await _frames(10)
	_check(reached and safe and _player.is_on_floor(), str(bridge.name) + " actual WASD crosses lowered bridge without yellow recovery")
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO


func _test_bridge_geometry(bridge, rift_name: String) -> void:
	_check(_rope_present(bridge) and is_equal_approx(bridge.get_node("Hinge").rotation.x, PI * 0.5), str(bridge.name) + " initially stands raised with its ground rope intact")
	var rift = _world.get_node("RiftRecovery/Rifts/" + rift_name)
	var middle: Vector3 = bridge.to_global(Vector3(0, 0, -bridge.deck_size.z * 0.5))
	_check(rift.contains_footprint(middle) and _floor_at(middle).is_empty(), str(bridge.name) + " spans its actual open rift before lowering")
	for z in [0.6, -bridge.deck_size.z - 0.6]:
		var hit := _floor_at(bridge.to_global(Vector3(0, 0, z)))
		_check(not hit.is_empty() and hit.normal.y > 0.95, str(bridge.name) + " approach is supported by original bank terrain")


func _burn_with_sword(bridge) -> void:
	var rope = bridge.get_node("Rope")
	var target: Vector3 = rope.get_hit_center()
	_player.recover_from_fall(Vector3(target.x - 1.8, bridge.global_position.y + 0.503, target.z))
	var camera = _player.get_node("Camera3D")
	camera.look_at(target)
	var sword = camera.get_node("WeaponRig/WeaponPivot/Mount")
	await _frames()
	_check(sword.try_swing(), "ordinary sword swing starts")
	await _frames(40)
	_check(_rope_present(bridge) and not rope.element.burning, "ordinary sword does not cut the load-bearing rope")
	sword.apply_oil()
	# 在实际剑刃处点火，随后移走火把，绳索必须由剑而非火把点燃。
	var torch = load("res://scenes/elements/torch.tscn").instantiate()
	_world.add_child(torch)
	torch.global_position = sword.element.global_position - Vector3.UP * 1.45
	await _frames(8)
	_check(sword.is_burning(), "torch contact lights the oiled sword")
	torch.queue_free()
	await _frames(4)
	_check(sword.try_swing(), "burning sword swing starts")
	await _frames(40)
	_check(rope.element.burning and not bridge.is_rope_burned(), "actual burning sword ignites rope before it burns through")
	_check(_save.save_game().ok and not _save.read_save().opened_gates.has(str(bridge.persistence_id)), "unfinished rope burning is excluded from permanent progress")
	var remaining: float = rope.element.burn_remaining
	paused = true
	await _frames(30)
	_check(is_equal_approx(rope.element.burn_remaining, remaining) and not bridge.is_rope_burned(), "pause freezes rope burn countdown")
	paused = false
	for frame in 180:
		await physics_frame
		if bridge.is_rope_burned():
			break
	_check(bridge.is_rope_burned() and not bridge.is_lowered(), "rope burns through before the lowering animation finishes")
	await _frames(1)
	_check(not is_instance_valid(rope), "burned rope and its element collider are destroyed")
	paused = true
	var angle: float = bridge.get_node("Hinge").rotation.x
	await _frames(30)
	_check(is_equal_approx(angle, bridge.get_node("Hinge").rotation.x), "pause freezes bridge lowering")
	_check(_save.save_game().ok and _save.read_save().opened_gates.get(str(bridge.persistence_id), false), "saving during lowering records the irreversible burned rope state")
	paused = false


func _burn_with_torch(bridge) -> void:
	var rope = bridge.get_node("Rope")
	var torch = load("res://scenes/elements/torch.tscn").instantiate()
	_world.add_child(torch)
	torch.global_position = rope.get_hit_center() - Vector3.UP * 1.45
	await _frames(8)
	_check(rope.element.burning, "ground-level torch contact ignites second bridge rope")
	torch.queue_free()
	await _frames(250)
	_check(bridge.is_rope_burned() and bridge.is_lowered() and not bridge.has_node("Rope"), "second rope burns away and bridge settles horizontally")


func _run() -> void:
	await process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			_phase = argument.trim_prefix("--phase=")
		elif argument.begins_with("--data-dir=/tmp/"):
			_directory = argument.trim_prefix("--data-dir=")
	DirAccess.make_dir_recursive_absolute(_directory)
	_flow = root.get_node("GameFlow")
	_save = root.get_node("SaveGame")
	_save.save_path = _directory.path_join("save.json")
	root.get_node("GameSettings").settings_path = _directory.path_join("settings.cfg")
	if _phase == "read":
		await _load_game()
		for bridge in _bridges.get_children():
			_check(bridge.is_lowered() and not bridge.has_node("Rope"), str(bridge.name) + " burned rope and usable bridge restore across a fresh process")
			await _walk_across(bridge)
		_finish()
		return
	await _new_game()
	_test_bridge_geometry(_bridges.get_node("UpperBridge"), "UpperRift")
	_test_bridge_geometry(_bridges.get_node("LowerBridge"), "LowerRift")
	_check(_save.save_game().ok and _save.read_save().opened_gates.is_empty(), "initial save records both ropes intact")
	await _burn_with_sword(_bridges.get_node("UpperBridge"))
	await _load_game()
	_check(_bridges.get_node("UpperBridge").is_lowered() and not _bridges.get_node("UpperBridge").has_node("Rope"), "load during lowering restores fully lowered first bridge without replaying burn")
	_check(_rope_present(_bridges.get_node("LowerBridge")), "other bridge retains its independent intact rope")
	await _walk_across(_bridges.get_node("UpperBridge"))
	await _burn_with_torch(_bridges.get_node("LowerBridge"))
	await _walk_across(_bridges.get_node("LowerBridge"))
	_check(_save.save_game().ok and _save.read_save().opened_gates == {"world.upper_rift.rope": true, "world.lower_rift.rope": true}, "save independently records both burned ropes")
	if _phase == "write":
		_finish()
		return
	await _load_game()
	_check(_bridges.get_children().all(func(bridge): return bridge.is_lowered() and not bridge.has_node("Rope")), "loading both burned ropes restores both bridges")
	var saved := FileAccess.get_file_as_string(_save.save_path)
	await _new_game()
	_check(_bridges.get_children().all(func(bridge): return _rope_present(bridge)), "new game resets both ropes and raises both bridges")
	_check(FileAccess.get_file_as_string(_save.save_path) == saved, "new game preserves the existing manual save")
	# v7 旧存档没有断绳编号时，两处吊桥从初始状态开始。
	var legacy: Dictionary = JSON.parse_string(saved)
	legacy.opened_gates = {"world.cleaning.vines": true}
	var file := FileAccess.open(_save.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	await _load_game()
	_check(_bridges.get_children().all(func(bridge): return _rope_present(bridge)), "older save without rope entries loads intact raised bridges")
	_check(_save.save_game().ok and _save.read_save().opened_gates == legacy.opened_gates, "legacy unmatched gate progress survives saving beside intact bridges")
	_finish()


func _finish() -> void:
	for action in ["Up", "Down", "Left", "Right"]:
		Input.action_release(action)
	paused = false
	print("DRAWBRIDGE RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
