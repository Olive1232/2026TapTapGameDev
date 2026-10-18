extends SceneTree

## 截图所示的倾斜藤蔓：在正式地图按真实 W/S 攀爬并站到顶端平台，包含实际搬运。
var _passed := 0
var _failed := 0
var _world: Node3D
var _player
var _vine
var _grabber


func _initialize() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func():
		push_error("MAIN WORLD CLIMBING TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("MAIN WORLD CLIMBING FAILED: " + message + " at " + str(_player.global_position))


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _case(lane: float, carrying: bool) -> void:
	var label := "lane=%.1f carrying=%s" % [lane, carrying]
	var outward: Vector3 = _vine.global_basis.z
	outward.y = 0.0
	outward = outward.normalized()
	var start: Vector3 = _vine.to_global(Vector3(lane, 0, 0)) + outward * 2.0
	var ray := PhysicsRayQueryParameters3D.create(start + Vector3.UP * 0.2, start - Vector3.UP * 5.0, 1)
	ray.exclude = [_vine.get_rid()]
	var floor_hit := _world.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not floor_hit.is_empty(), "approach has ground " + label)
	if floor_hit.is_empty():
		return
	_player.recover_from_fall(floor_hit.position + Vector3.UP * 0.503)
	_player.look_at(_player.global_position - outward)
	_player.get_node("Camera3D").rotation = Vector3.ZERO
	await _frames(20)
	var corpse
	if carrying:
		corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
		corpse.setup(load("res://resources/enemies/monster_rat.tres"))
		corpse.freeze = true
		_world.add_child(corpse)
		var camera: Camera3D = _player.get_node("Camera3D")
		corpse.global_position = camera.global_position - camera.global_basis.z * 1.2
		await _frames(3)
		_check(_grabber.try_grab() and _grabber.get_held() == corpse, "actual rat corpse is grabbed " + label)
		corpse.freeze = false
	var start_y: float = _player._feet_position().y
	Input.action_press("Up")
	var attached := false
	for frame in 150:
		await physics_frame
		if _player.is_climbing() and _player._feet_position().y > start_y + 0.8:
			attached = true
			break
	_check(attached, "walking into inclined vine starts ascent " + label)
	Input.action_release("Up")
	await _frames(3)
	var held_y: float = _player.global_position.y
	await _frames(20)
	_check(_player.is_climbing() and absf(_player.global_position.y - held_y) < 0.03, "release W holds position on incline " + label)
	Input.action_press("Down")
	await _frames(16)
	Input.action_release("Down")
	_check(_player.is_climbing() and _player.global_position.y < held_y - 0.25, "S descends actual incline " + label)
	Input.action_press("Up")
	var mounted := false
	var top_center: Vector3 = _vine.to_global(Vector3(0, _vine.size.y, 0))
	for frame in 300:
		await physics_frame
		if not _player.is_climbing() and _player.is_on_floor() and _player._feet_position().y > start_y + 2.5 and (_player.global_position - top_center).dot(-outward) > 0.35:
			mounted = true
			break
	Input.action_release("Up")
	await _frames(40)
	_check(mounted and _player.is_on_floor() and not _player.is_climbing(), "continuous W clears complete top edge and lands on real ledge " + label)
	_check(_player._feet_position().y > start_y + 2.5 and not _player.is_rift_recovering(), "player remains safely on upper platform " + label)
	if carrying:
		_check(is_instance_valid(corpse) and _grabber.get_held() == corpse and corpse.is_held and _player.carry_weight > 0.0, "climb preserves original held corpse and weight " + label)
		_grabber.drop()
		corpse.queue_free()
		await _frames(4)


func _run() -> void:
	await process_frame
	root.get_node("SaveGame").save_path = "/tmp/taptap-main-world-climbing-save.json"
	root.get_node("GameSettings").settings_path = "/tmp/taptap-main-world-climbing-settings.cfg"
	root.get_node("GameFlow").start_new_game()
	await scene_changed
	_world = current_scene
	_player = _world.get_node("Player")
	_vine = _world.get_node("FlammableVines")
	_grabber = _player.get_node("Camera3D/Grabber")
	_world.get_node("WorldDialogue").restore_progress({"shop_visited": true, "hole_introduced": true})
	var placement: Transform3D = _vine.global_transform
	_check(absf(_vine.global_basis.z.normalized().y) > 0.4, "regression uses the inclined vine previously rejected by the angle limit")
	var maximum_y := -INF
	for x in [-0.5, 0.5]:
		for z in [-0.5, 0.5]:
			maximum_y = maxf(maximum_y, _vine.to_global(Vector3(_vine.size.x * x, _vine.size.y, _vine.size.z * z)).y)
	_check(is_equal_approx(_vine.get_climb_top().y, maximum_y), "climb top clears the highest transformed collider corner")
	for carrying in [false, true]:
		for lane in [-0.8, 0.0, 0.8]:
			await _case(lane, carrying)
	_check(_vine.global_transform.is_equal_approx(placement), "repair preserves authored vine placement")
	print("MAIN WORLD CLIMBING RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
