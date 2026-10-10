extends RefCounted

## 收入回归使用真实移动与接触拾币，不直接修改钱包或调用 _collect。
static func collect_all(tree: SceneTree, player: CharacterBody3D) -> bool:
	var pool = tree.root.get_node("CoinPool")
	var original_position := player.global_position
	var original_velocity := player.velocity
	var original_physics := player.is_physics_processing()
	var success := true
	var hole := tree.current_scene.get_node("Hole") as Node3D
	var player_shape := player.get_node("CollisionShape3D") as CollisionShape3D
	var standing_height := (player_shape.shape as BoxShape3D).size.y * 0.5 - player_shape.position.y
	for coin in pool.get("_active").duplicate():
		# 走向一枚金币时可能同时拾取邻近金币；快照中的条目可能已回池。
		if coin.is_collected():
			continue
		for frame in range(180):
			if coin.is_grounded() or coin.is_collected():
				break
			await tree.physics_frame
		if coin.is_collected():
			continue
		if not coin.is_grounded():
			push_error("COIN WALK: not grounded at " + str(coin.global_position))
			success = false
			continue
		var radial: Vector3 = coin.global_position - hole.global_position
		radial.y = 0.0
		radial = radial.normalized() if radial.length() > 0.01 else Vector3.RIGHT
		var start := Vector3.ZERO
		var found_start := false
		for approach in [radial, -radial, Vector3(-radial.z, 0, radial.x), Vector3(radial.z, 0, -radial.x)]:
			start = coin.global_position + approach * 1.5
			var ray := PhysicsRayQueryParameters3D.create(start + Vector3.UP * 2.0, start - Vector3.UP * 2.0, 1)
			var floor_hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
			if floor_hit.is_empty() or absf(floor_hit.position.y - coin.global_position.y) > 0.5:
				continue
			start.y = floor_hit.position.y + standing_height + player.safe_margin
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = player_shape.shape
			query.transform = player.global_transform
			query.transform.origin = start + player_shape.position
			query.collision_mask = 1
			if player.get_world_3d().direct_space_state.intersect_shape(query).is_empty():
				found_start = true
				break
		if not found_start:
			push_error("COIN WALK: no clear start floor for " + str(coin.global_position))
			success = false
			continue
		player.global_position = start
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		player.set_physics_process(true)
		for frame in range(180):
			if coin.is_collected():
				break
			var direction: Vector3 = coin.global_position - player.global_position
			direction.y = 0.0
			direction = player.global_basis.inverse() * direction.normalized()
			Input.action_press("Right", maxf(direction.x, 0.0))
			Input.action_press("Left", maxf(-direction.x, 0.0))
			Input.action_press("Down", maxf(direction.z, 0.0))
			Input.action_press("Up", maxf(-direction.z, 0.0))
			await tree.physics_frame
		for action in ["Right", "Left", "Down", "Up"]:
			Input.action_release(action)
		if not coin.is_collected():
			push_error("COIN WALK: stuck player=%s coin=%s " % [player.global_position, coin.global_position])
			success = false
	player.global_position = original_position
	player.velocity = original_velocity
	player.reset_physics_interpolation()
	player.set_physics_process(original_physics)
	await tree.process_frame
	return success and pool.active_count() == 0
