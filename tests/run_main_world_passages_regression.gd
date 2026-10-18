extends SceneTree

## 用当前正式地图与真实 WASD 检查清扫房入口三条走线的双向通行，包含实际手持尸体。
var _passed := 0
var _failed := 0
var _world: Node3D
var _player: CharacterBody3D
var _grabber


func _initialize() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func():
		push_error("MAIN WORLD PASSAGES TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("MAIN WORLD PASSAGES FAILED: " + message + " at " + str(_player.global_position))


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _place(x: float, z: float) -> void:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 8.5, z), Vector3(x, -5, z), 1)
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty(), "approach has ground")
	if hit.is_empty():
		return
	_player.recover_from_fall(hit.position + Vector3.UP * 0.503)
	await _frames(12)


func _walk(x: float, z: float) -> bool:
	for frame in 360:
		var offset := Vector3(x - _player.global_position.x, 0, z - _player.global_position.z)
		if offset.length() < 0.15:
			Input.action_release("Up")
			await _frames(24)
			return _player.is_on_floor() and not _player.is_rift_recovering()
		_player.rotation.y = atan2(-offset.x, -offset.z)
		Input.action_press("Up")
		await physics_frame
	Input.action_release("Up")
	return false


func _run() -> void:
	await process_frame
	root.get_node("SaveGame").save_path = "/tmp/taptap-main-world-passages-save.json"
	root.get_node("GameSettings").settings_path = "/tmp/taptap-main-world-passages-settings.cfg"
	root.get_node("GameFlow").start_new_game()
	await scene_changed
	_world = current_scene
	_world.get_node("WorldDialogue").restore_progress({"shop_visited": true, "hole_introduced": true})
	_player = _world.get_node("Player")
	_grabber = _player.get_node("Camera3D/Grabber")
	await _frames(30)
	for carrying in [false, true]:
		var corpse
		if carrying:
			await _place(41.3, -17.5)
			_player.rotation = Vector3.ZERO
			_player.get_node("Camera3D").rotation = Vector3.ZERO
			corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
			corpse.freeze = true
			_world.add_child(corpse)
			corpse.global_position = _player.get_node("Camera3D").global_position + Vector3.FORWARD * 1.6
			await _frames(4)
			_check(_grabber.try_grab() and _player.carry_weight > 0.0, "real corpse is carried before passage walks")
		for z in [-19.5, -17.5, -15.5]:
			await _place(41.3, z)
			_check(await _walk(35.5, z), "cleaning to entry lane %.1f carrying=%s" % [z, carrying])
			_check(await _walk(41.3, z), "entry to cleaning lane %.1f carrying=%s" % [z, carrying])
		if carrying:
			_check(is_instance_valid(corpse) and _grabber.get_held() == corpse and corpse.is_held, "all crossings preserve original carried corpse")
			_grabber.drop()
			corpse.queue_free()
	print("MAIN WORLD PASSAGES RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
