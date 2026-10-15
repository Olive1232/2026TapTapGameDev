extends RefCounted

## 根据真实地形、玩家碰撞尺寸采样，不复用地图设计坐标来假定通路存在。
const STEP := 0.5

static func sample(world: Node3D, player: CharacterBody3D) -> Dictionary:
	var space := world.get_world_3d().direct_space_state
	var shape_node := player.get_node("CollisionShape3D") as CollisionShape3D
	var shape := BoxShape3D.new()
	shape.size = shape_node.shape.size + Vector3(0.04, 0, 0.04)
	# 玩家转弯时方盒占地增大；同时覆盖所有朝向，避免绕货架时擦角。
	var turn_width := Vector2(shape.size.x, shape.size.z).length()
	shape.size.x = turn_width
	shape.size.z = turn_width
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var hole: Node3D = world.get_node("Hole")
	var nodes := {}
	var world_scale: float = world.get_node("WorldGeometry").scale.x
	# 家具和角色没有放大，采样间距也保持原尺寸，不能跨过小型障碍。
	var spacing := STEP
	for z in range(int(-42 * world_scale), int(38 * world_scale) + 1):
		for x in range(int(-79 * world_scale), int(82 * world_scale) + 1):
			# 从玩家头顶附近采样地板，不能把更高的屋顶或门楣当成地面。
			var at := Vector3(x * spacing, 4.6 * world_scale, z * spacing)
			if Vector2(at.x - hole.position.x, at.z - hole.position.z).length() < hole.player_fall_radius + 0.7:
				continue
			var ray := PhysicsRayQueryParameters3D.create(at, Vector3(at.x, -world_scale, at.z), 1)
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or hit.position.y > 3.5 * world_scale or hit.normal.y < 0.72:
				continue
			# 平地与坡道交接时，中心射线尚在平地，前脚已在坡上。
			# 同时采样四个脚底角，避开切口旁的陡岩，并按最高支撑点检查身体。
			var support_y: float = hit.position.y
			var supported := true
			for corner in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
				var foot: Vector3 = hit.position + Vector3(corner.x * shape.size.x * 0.5, 0, corner.y * shape.size.z * 0.5)
				var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 0.5, foot - Vector3.UP, 1))
				if ground.is_empty() or ground.normal.y < 0.72 or absf(ground.position.y - hit.position.y) > 0.4:
					supported = false
					break
				support_y = maxf(support_y, ground.position.y)
			if not supported:
				continue
			var slope_lift: float = support_y - hit.position.y
			query.transform = Transform3D(Basis.IDENTITY, hit.position + Vector3(0, shape.size.y * 0.5 + slope_lift + 0.03, 0))
			if space.intersect_shape(query, 1).is_empty():
				nodes[Vector2i(x, z)] = hit.position + Vector3.UP * (shape.size.y * 0.5 - shape_node.position.y + slope_lift + player.safe_margin)
	return nodes


static func find_path(nodes: Dictionary, start: Vector3, goal: Vector3, world_scale: float = 1.0) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if nodes.is_empty():
		return result
	var first: Vector2i = nodes.keys()[0]
	var last := first
	for key: Vector2i in nodes:
		if Vector2(nodes[key].x - start.x, nodes[key].z - start.z).length_squared() < Vector2(nodes[first].x - start.x, nodes[first].z - start.z).length_squared():
			first = key
		if Vector2(nodes[key].x - goal.x, nodes[key].z - goal.z).length_squared() < Vector2(nodes[last].x - goal.x, nodes[last].z - goal.z).length_squared():
			last = key
	if Vector2(nodes[last].x - goal.x, nodes[last].z - goal.z).length() > 1.0:
		return result
	var todo: Array[Vector2i] = [first]
	var previous := {first: first}
	var index := 0
	while index < todo.size() and not previous.has(last):
		var at := todo[index]
		index += 1
		for step in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = at + step
			if nodes.has(next) and not previous.has(next) and absf(nodes[next].y - nodes[at].y) < 0.32:
				previous[next] = at
				todo.append(next)
	if not previous.has(last):
		return result
	var key := last
	while key != first:
		result.push_front(nodes[key])
		key = previous[key]
	result.push_front(nodes[first])
	return result


static func walk(tree: SceneTree, player: CharacterBody3D, route: Array[Vector3]) -> bool:
	if route.is_empty():
		return false
	player.get_node("Camera3D").rotation = Vector3.ZERO
	player.set_physics_process(true)
	for point in route:
		var reached := false
		for frame in 100:
			var offset := point - player.global_position
			offset.y = 0
			if offset.length() < 0.18:
				reached = true
				break
			player.rotation.y = atan2(-offset.x, -offset.z)
			Input.action_press("Up")
			await tree.physics_frame
		Input.action_release("Up")
		if not reached:
			push_error("WORLD WALK: blocked at %s towards %s" % [player.global_position, point])
			return false
	for frame in 4:
		await tree.physics_frame
	return player.is_on_floor()
