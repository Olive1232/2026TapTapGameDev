extends SceneTree

## 按实际渲染几何检查 Size、Transform 缩放、父级缩放和燃烧中的尺寸变化。
var _passed := 0
var _failed := 0
var _world: Node3D


func _initialize() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("FLAME COVERAGE TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("FLAME COVERAGE FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _prop(dimensions: Vector3, at: Vector3, parent: Node3D = null, visual_scale_only: bool = false):
	var prop = load("res://scenes/prefabs/flammable_vines.tscn").instantiate()
	prop.size = dimensions
	prop.position = at
	prop.get_node("ElementComponent").burn_duration = 0.0
	# Jolt 不支持非均匀缩放的球；本组只测表现，真实传火另用默认缩放验证。
	prop.get_node("ElementComponent/Shape").disabled = visual_scale_only
	(parent if parent != null else _world).add_child(prop)
	return prop


func _bounds(node: Node3D, relative_to: Node3D = null) -> AABB:
	var found := false
	var result := AABB()
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D or current is MultiMeshInstance3D:
			var transform: Transform3D = current.global_transform
			if relative_to != null:
				transform = relative_to.global_transform.affine_inverse() * transform
			var local_box: AABB = current.mesh.get_aabb() if current is MeshInstance3D else current.get_aabb()
			if current is MultiMeshInstance3D:
				# dummy 渲染器既不保留实例变换，也不计算 AABB；用提交渲染的基础几何。
				var instances: MultiMesh = current.multimesh
				for index in instances.instance_count:
					var pose: Transform3D = current.get_parent().get("_base_transforms")[index] if DisplayServer.get_name() == "headless" else instances.get_instance_transform(index)
					var instance_box: AABB = pose * instances.mesh.get_aabb()
					local_box = instance_box if index == 0 else local_box.merge(instance_box)
			var box: AABB = transform * local_box
			result = result.merge(box) if found else box
			found = true
		for child in current.get_children():
			stack.append(child)
	return result


func _check_coverage(prop, label: String) -> void:
	var flame: Node3D = prop.element.get("_flame")
	var box := _bounds(flame, prop)
	_check(box.size.x >= prop.size.x * 0.9 and box.size.y >= prop.size.y * 0.85, label + " flame spans full local width and height")
	_check(box.size.x <= prop.size.x * 1.5 and box.size.y <= prop.size.y * 1.5, label + " flame is not scaled twice")
	_check(absf(box.get_center().x) < prop.size.x * 0.15 and absf(box.get_center().y - prop.size.y * 0.5) < prop.size.y * 0.15, label + " flame stays centered on vine")
	_check(flame.visible == prop.element.is_fire_source(), label + " flame visibility follows burning")


func _run() -> void:
	await process_frame
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	var small = _prop(Vector3(1.2, 3.2, 0.35), Vector3.ZERO)
	var large = _prop(Vector3(10, 8, 1.2), Vector3(20, 0, 0), null, true)
	_check(not small.element.burning and not large.element.get("_flame").visible, "unlit scaled vines do not display flames")
	small.element.ignite()
	large.element.ignite()
	await _frames()
	_check_coverage(small, "default")
	_check_coverage(large, "large Size")
	var before: float = large.element.burn_remaining
	large.size = Vector3(4, 9, 0.8)
	await _frames()
	_check_coverage(large, "resized while burning")
	_check(large.element.burning and large.element.burn_remaining == before, "resizing keeps existing burn state and timer")
	large.size = Vector3(1.2, 1.0, 0.35)
	await _frames()
	_check_coverage(large, "shrunk while burning")
	_check_coverage(small, "independent instance")
	var flame: Node3D = large.element.get("_flame")
	flame.set_process(false)
	var original := _bounds(flame)
	large.scale = Vector3(3, 2, 4)
	var scaled := _bounds(flame)
	_check(scaled.size.is_equal_approx(original.size * Vector3(3, 2, 4)), "nonuniform Transform scale is inherited exactly once")
	var parent := Node3D.new()
	parent.position = Vector3(40, 0, 0)
	parent.rotation.y = 0.6
	parent.scale = Vector3(2, 3, 1.5)
	_world.add_child(parent)
	var nested = _prop(Vector3(3, 5, 0.4), Vector3.ZERO, parent, true)
	nested.scale = Vector3(0.75, 2, 1.3)
	nested.element.ignite()
	await _frames()
	_check_coverage(nested, "rotated scaled parent")
	var grass = load("res://scenes/elements/flammable_grass.tscn").instantiate()
	grass.position = Vector3(60, 0, 0)
	grass.get_node("ElementComponent").burn_duration = 0.0
	_world.add_child(grass)
	grass.element.ignite()
	await _frames()
	_check_coverage(grass, "grass flame_scale override")
	var huge = _prop(Vector3(120, 80, 12), Vector3(200, 0, 0))
	huge.element.ignite()
	await _frames()
	_check_coverage(huge, "very large Size")
	var huge_flame: Node3D = huge.element.get("_flame")
	var field := huge_flame.get_node("FlameCoverage") as MultiMeshInstance3D
	_check(field.multimesh.instance_count <= 720 and huge_flame.get_child_count() == 2, "large coverage keeps bounded geometry and a single light")
	var torch = load("res://scenes/elements/torch.tscn").instantiate()
	torch.position = Vector3(80, 0, 0)
	_world.add_child(torch)
	var torch_flame: Node3D = torch.get_node("ElementComponent").get("_flame")
	var torch_bounds := _bounds(torch_flame, torch)
	_check(torch_flame.visible and torch_bounds.size.x < 1 and torch_bounds.size.y < 1, "ordinary torch retains its original small flame")
	# 用真实火把接触点燃大型藤蔓，检查暂停和烧毁仍清理全部表现及碰撞。
	var burning = _prop(Vector3(8, 6, 0.5), Vector3(100, 0, 0))
	burning.element.burn_duration = 0.4
	torch.position = burning.element.global_position + Vector3(0, -1.45, 0.9)
	await _frames(6)
	_check(burning.element.burning, "real torch contact ignites enlarged vine")
	_check_coverage(burning, "real contact")
	var burning_flame: WeakRef = weakref(burning.element.get("_flame"))
	var collider: WeakRef = weakref(burning.get_node("Shape"))
	var remaining: float = burning.element.burn_remaining
	paused = true
	await _frames(15)
	_check(is_equal_approx(burning.element.burn_remaining, remaining), "pause preserves burn duration")
	paused = false
	await _frames(35)
	_check(not is_instance_valid(burning) and burning_flame.get_ref() == null and collider.get_ref() == null, "burn down removes enlarged flame, light and solid collision")
	print("FLAME COVERAGE RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
