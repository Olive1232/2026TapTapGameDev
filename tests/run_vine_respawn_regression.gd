extends SceneTree

## 实际传火、碰撞、暂停和重复烧毁；不修改关卡实例的默认刷新时间。
var _passed := 0
var _failed := 0
var _world: Node3D


func _initialize() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("VINE RESPAWN TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("VINE RESPAWN FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _vine(at: Vector3, delay: float = 0.0, parent: Node3D = null):
	var vine = load("res://scenes/prefabs/flammable_vines.tscn").instantiate()
	vine.position = at
	vine.size = Vector3(2.4, 4.6, 0.6)
	vine.respawn_delay = delay
	vine.get_node("ElementComponent").burn_duration = 0.4
	(parent if parent != null else _world).add_child(vine)
	return vine


func _blocked(vine) -> bool:
	var middle: Vector3 = Vector3.UP * vine.size.y * 0.5
	var ray := PhysicsRayQueryParameters3D.create(vine.to_global(middle + Vector3.BACK * 2.0), vine.to_global(middle + Vector3.FORWARD * 2.0), 1)
	return _world.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == vine


func _burned(vine) -> void:
	for frame in 90:
		if not vine.visible:
			return
		await _frames(1)
	_check(false, "vine completes configured burn duration")


func _run() -> void:
	await process_frame
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	var parent := Node3D.new()
	parent.position = Vector3(8, 2, -3)
	parent.rotation.y = 0.4
	parent.scale = Vector3.ONE * 1.5
	_world.add_child(parent)
	var vine = _vine(Vector3(1, 0, 2), 0.75, parent)
	var original: Transform3D = vine.global_transform
	var original_id: int = vine.get_instance_id()
	var events := {"burned": 0}
	vine.element.burned_down.connect(func(): events.burned += 1)
	await _frames()
	_check(_blocked(vine) and vine.can_climb(), "configured vine initially blocks movement and allows climbing")
	var torch = load("res://scenes/elements/torch.tscn").instantiate()
	_world.add_child(torch)
	torch.global_position = vine.element.global_position - Vector3.UP * 1.45
	await _frames(6)
	_check(vine.element.burning and vine.visible and _blocked(vine), "real torch contact ignites vine without clearing it before burn completes")
	torch.queue_free()
	await _frames(6)
	_check(vine.visible and vine.can_climb(), "respawn delay begins after complete burn rather than ignition")
	await _burned(vine)
	await _frames()
	_check(not vine.visible and not _blocked(vine) and not vine.can_climb(), "burn down removes visuals, physical obstruction and climbing")
	_check(not vine.element.burning and not vine.element.get("_flame").visible and not vine.element.ignite(), "waiting vine has no flame and rejects ignition")
	_check(events.burned == 1, "burn down emits one destruction event")
	# 等待时真实火把与藤蔓仍处于同一空间，但不能提前重新点燃。
	torch = load("res://scenes/elements/torch.tscn").instantiate()
	_world.add_child(torch)
	torch.global_position = vine.element.global_position - Vector3.UP * 1.45
	await _frames(6)
	_check(not torch.get_node("ElementComponent").overlaps_area(vine.element) and not vine.element.burning, "waiting vine is removed from element contact detection")
	torch.queue_free()
	paused = true
	await _frames(90)
	_check(not vine.visible and not _blocked(vine) and events.burned == 1, "pause longer than respawn delay leaves vine absent")
	paused = false
	await _frames(12)
	_check(not vine.visible, "unpausing continues the remaining delay without an immediate respawn")
	await _frames(60)
	_check(vine.visible and _blocked(vine) and vine.can_climb(), "elapsed delay restores visuals, physical obstruction and climbing")
	_check(vine.get_instance_id() == original_id and vine.global_transform.is_equal_approx(original) and vine.size == Vector3(2.4, 4.6, 0.6), "respawn preserves instance, dimensions and transformed parent placement")
	_check(vine.get("_material").albedo_color == vine.tint and not vine.element.burning and is_zero_approx(vine.element.burn_remaining), "respawn restores original color and unburned state")
	_check(vine.element.ignite(), "refreshed vine can burn again")
	await _burned(vine)
	await _frames(60)
	_check(vine.visible and _blocked(vine) and events.burned == 2, "second complete burn respawns normally and emits one event per cycle")
	# 默认值与显式 0 都沿用永久销毁；草和尸体的公共燃烧行为不受影响。
	var permanent = _vine(Vector3(-10, 0, 0))
	_check(permanent.respawn_delay == 0.0, "default respawn delay is zero")
	permanent.element.ignite()
	await _frames(90)
	_check(not is_instance_valid(permanent), "zero delay permanently frees burned vine")
	# 等待中的节点随场景释放，不应有挂在树根的计时器重新生成藤蔓。
	vine.element.ignite()
	await _burned(vine)
	_world.queue_free()
	await _frames(90)
	_check(not is_instance_valid(vine) and root.find_children("FlammableVines*", "StaticBody3D", true, false).is_empty(), "scene removal cancels pending respawn without orphan instances")
	print("VINE RESPAWN RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
