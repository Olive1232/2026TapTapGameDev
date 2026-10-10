extends SceneTree

## 新模型的实际行走、初始收入、商店、火焰门与场景生命周期。
var _passed := 0
var _failed := 0
var _room
var _player
var _camera
var _sword
var _grabber
var _shop
var _wallet
var _flow
var _capture_dir := ""
var _map_scale := 1.0


func _initialize() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func():
		push_error("MAP WORLD REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("MAP WORLD REGRESSION FAILED: " + message)


func _frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(int(ceil(seconds * Engine.physics_ticks_per_second)) + 1)


func _bind() -> void:
	_room = current_scene
	_player = _room.get_node("Player")
	_camera = _player.get_node("Camera3D")
	_sword = _camera.get_node("WeaponRig/WeaponPivot/Mount")
	_grabber = _camera.get_node("Grabber")
	_shop = _room.get_node("ShopRoom")
	_map_scale = _room.get_node("WorldGeometry").scale.x


## 地图点位随地形扩大；玩家站立高度仍使用原碰撞盒。
func _map_stance(original: Vector3) -> Vector3:
	var at := original * _map_scale
	var floor_hit := _floor_at(at)
	if not floor_hit.is_empty():
		at.y = floor_hit.position.y + _standing_height() + _player.safe_margin
	return at


func _capture(name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _wait(0.25)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_capture_dir.path_join(name + ".png"))


func _mouse(button: MouseButton) -> void:
	if button == MOUSE_BUTTON_RIGHT and DisplayServer.get_name() == "headless":
		if _grabber.is_holding():
			_grabber.drop()
		else:
			_grabber.try_grab()
	else:
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			event.pressed = pressed
			Input.parse_input_event(event)
		Input.flush_buffered_events()
	await _frames()


func _run() -> void:
	await process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_capture_dir = argument.trim_prefix("--capture-dir=")
	_wallet = root.get_node("Wallet")
	_flow = root.get_node("GameFlow")
	_flow.start_new_game()
	await scene_changed
	_bind()
	await _wait(0.6)
	_check(_room.scene_file_path == "res://scenes/rooms/map_world.tscn", "new game enters model world")
	_check(_wallet.total == 0 and _flow.is_in_game(), "new world starts from zero and supports pause")
	var spawn_floor := _floor_at(_player.global_position)
	_check(not spawn_floor.is_empty() and spawn_floor.collider.name == "MainFloor" and _player.is_on_floor() and absf(_player.global_position.y - spawn_floor.position.y - _standing_height()) < 0.03, "spawn settles safely on FBX floor")
	var shop_floor := _floor_at(_shop.global_position)
	_check(not shop_floor.is_empty() and shop_floor.collider.name == "ShopFloor" and absf(_shop.global_position.y - shop_floor.position.y) < 0.03, "shop fixtures share the model floor coordinate frame")
	_check(FileAccess.get_sha256("res://assets/prototypes/map/map_v2.fbx") == _room.get_node("WorldGeometry").get_meta("source_sha256"), "baked geometry matches unchanged source FBX")
	_check(_room.get_node("WorldGeometry/Collision").get_child_count() == 10, "model collision and both passage ramps are baked")
	_check(_room.get_node("WorldGeometry").scale.is_equal_approx(Vector3(2, 2, 2)), "map geometry and baked collision are twice their original size")
	_check(_player.scale.is_equal_approx(Vector3.ONE) and _shop.scale.is_equal_approx(Vector3.ONE), "player and shop fixtures retain their original size")
	_check(_room.get_node("Hole").swallow_radius == 4.0 and _room.get_node("Hole").player_fall_radius == 6.5 and _room.get_node("Hole").coin_landing_radius == 7.5, "pit fall and coin landing distances match actual opening")
	_check(_room.get_node("VineGate").scale.is_equal_approx(Vector3(2, 2, 2)), "vines cover the enlarged cleaning doorway")
	_check(not _shop.has_node("Geometry"), "shop uses fixture without old box building")
	_check(not _room.get_node("Hole/Rim").visible and _room.get_node("Hole/Bottom/Shape").disabled, "offering logic uses model pit without old pit geometry")
	_check(not _room.is_gate_open() and not _room.get_node("RatSpawner").enabled, "cleaning area is gated")
	_check_passage_geometry()
	await _capture("world-spawn")

	var routes := _routes(Vector2i(0, -15))
	_check(routes.has(Vector2i(-31, 16)), "player sized route reaches model shop")
	_check(not routes.has(Vector2i(20, 2)), "closed vines prevent reaching cleaning area")
	if routes.has(Vector2i(-31, 16)):
		_check(await _walk(routes[Vector2i(-31, 16)]), "WASD movement walks entire shop route over ramp")
		var reverse_route: Array = routes[Vector2i(-31, 16)].duplicate()
		reverse_route.reverse()
		reverse_route.append(Vector3(0, 0, -7.5) * _map_scale)
		_check(await _walk(reverse_route), "WASD movement returns uphill from shop")
	_player.set_physics_process(false)
	_player.rotation = Vector3.ZERO
	var starter = _room.get_node("StarterCleaningRoom/RatSpawner")
	await _wait(3.0)
	_check(starter.get_alive_count() > 0, "initial rats spawn on main floor before buying oil")
	for cycle in range(3):
		var rat
		for child in starter.get_children():
			if child.has_method("take_hit"):
				rat = child
				break
		_check(rat != null, "initial rat is available")
		if rat == null:
			break
		rat.set_physics_process(false)
		_player.position = _map_stance(Vector3(3, 0.417, -7))
		_camera.rotation = Vector3(deg_to_rad(-45), 0, 0)
		rat.global_position = _camera.global_transform * Vector3(0, -0.34, -1.4)
		var corpses: Array = []
		root.get_node("EventBus").corpse_spawned.connect(func(corpse): corpses.append(corpse), CONNECT_ONE_SHOT)
		await _frames()
		await _mouse(MOUSE_BUTTON_LEFT)
		await _wait(0.8)
		_check(not is_instance_valid(rat) and not corpses.is_empty(), "sword kills rat and creates corpse")
		if corpses.is_empty():
			break
		var corpse = corpses[0]
		corpse.freeze = true
		corpse.global_position = _camera.global_position - _camera.global_basis.z * 2.0
		await _frames()
		await _mouse(MOUSE_BUTTON_RIGHT)
		_check(_grabber.get_held() == corpse, "click picks up corpse")
		_player.position = _map_stance(Vector3(0, 0.417, -6))
		corpse.global_position = _room.get_node("Hole").global_position + Vector3(0, 1.8, 0)
		await _frames()
		_check(not is_instance_valid(corpse) and not _grabber.is_holding() and is_zero_approx(_player.carry_weight), "held corpse at 1.8 meters is offered and carrier cleared")
		await _wait(4.0)
		_check(await load("res://tests/helpers/coin_collection.gd").collect_all(self, _player), "coins land on model floor and walking contact collects them")
		_check(_wallet.total == (cycle + 1) * 2, "unchanged offering yields two coins")
	_check(_wallet.total == 6 and not _room.is_flow_complete(), "initial income covers price without completing gated route")

	await _at_shelf()
	await _mouse(MOUSE_BUTTON_RIGHT)
	var item = _shop.shelf.get_item()
	_check(_grabber.get_held() == item, "oil is reachable on shelf in rotated shop")
	item.global_position = _room.get_node("Hole").global_position + Vector3(0, 1.8, 0)
	await _frames(5)
	_check(is_instance_valid(item) and not _grabber.is_holding() and item.freeze, "held oil over pit returns instead of being destroyed")
	_check(item.global_position.is_equal_approx(_shop.shelf.get_node("ItemSpawn").global_position) and _wallet.total == 6, "oil returns to shelf without offering reward")
	await _at_shelf()
	await _mouse(MOUSE_BUTTON_RIGHT)
	await _at_counter()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_shop.counter.item == item, "counter accepts clicked oil in rotated fixture")
	await _capture("world-shop")
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.3)
	_check(_shop.busy and not _sword.visible and _wallet.total == 6, "hitting keeper starts forge before debit")
	await _wait(3.0)
	_check(_sword.oiled and _wallet.total == 1 and _shop.completed_purchases == 1, "physical shop delivers oil upgrade and spends five once")
	_check(_sword.visible and not _sword.interaction_locked and not _grabber.interaction_locked, "forge restores sword and grabber")

	var torch = _room.get_node("Torch")
	_player.position = torch.position + Vector3(0.55, 0.5, 1.5)
	_camera.look_at(torch.get_node("ElementComponent").global_position, Vector3.UP)
	var delta: Vector3 = torch.get_node("ElementComponent").global_position - _sword.element.global_position
	_player.position += Vector3(delta.x, 0, delta.z)
	await _wait(0.5)
	_check(_sword.is_burning() and _sword.fire_swings_remaining == 5, "actual torch contact ignites purchased oil")
	var vine = _room.get_node("VineGate/Vines2")
	_player.position = _map_stance(Vector3(7.55 - 1.75 / _map_scale, 0.417, 0))
	_camera.look_at(vine.get_hit_center(), Vector3.UP)
	await _frames()
	await _capture("world-gate")
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.6)
	_check(vine.element.burning, "burning sweep ignites model doorway vines")
	await _wait(10.8)
	_check(_room.is_gate_open() and _room.get_node("RatSpawner").enabled and _room.get_node("CockroachSpawner").enabled, "burned gate enables both cleaning spawners")
	_player.position = _map_stance(Vector3(0, 0.55, -7.5))
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(true)
	await _frames()
	routes = _routes(Vector2i(0, -15))
	_check(routes.has(Vector2i(20, 2)), "open gate route reaches cleaning area")
	if routes.has(Vector2i(20, 2)):
		_check(await _walk(routes[Vector2i(20, 2)]), "WASD movement passes burned doorway into cleaning area")
	_player.set_physics_process(false)
	_player.rotation = Vector3.ZERO
	var cleaning = _room.get_node("CockroachSpawner")
	_check(cleaning.get_alive_count() > 0 and cleaning.get_alive_count() <= cleaning.max_alive, "unlocked cleaning spawner produces capped monsters")
	var enemy
	for child in cleaning.get_children():
		if child.has_method("take_hit"):
			enemy = child
			break
	if enemy != null:
		enemy.set_physics_process(false)
		_player.position = _map_stance(Vector3(10, 0.515, 1))
		_camera.rotation = Vector3(deg_to_rad(-45), 0, 0)
		enemy.global_position = _camera.global_transform * Vector3(0, -0.34, -1.4)
		var corpses: Array = []
		root.get_node("EventBus").corpse_spawned.connect(func(corpse): corpses.append(corpse), CONNECT_ONE_SHOT)
		await _frames()
		await _mouse(MOUSE_BUTTON_LEFT)
		await _wait(0.8)
		_check(not is_instance_valid(enemy) and not corpses.is_empty(), "unlocked cleaning monster dies from sword sweep")
		if not corpses.is_empty():
			var corpse = corpses[0]
			corpse.freeze = true
			corpse.global_position = _camera.global_position - _camera.global_basis.z * 2.0
			await _frames()
			await _mouse(MOUSE_BUTTON_RIGHT)
			_check(_grabber.get_held() == corpse, "cleaning corpse can be carried back")
			_player.position = _map_stance(Vector3(0, 0.417, -6))
			corpse.global_position = _room.get_node("Hole").global_position + Vector3(0, 1.8, 0)
			await _wait(4.0)
			_check(await load("res://tests/helpers/coin_collection.gd").collect_all(self, _player), "cleaning offering coins collect by walking")
			_check(_room.is_flow_complete() and _wallet.total > 1, "post gate offering pays and completes migrated objective")
	var earned: int = _wallet.total
	var fall_position: Vector3 = _room.get_node("Hole").global_position + Vector3(0, -1, 0)
	_player.global_position = fall_position
	_player.velocity = Vector3(1, -5, 2)
	await _frames()
	_check(_player.global_position.is_equal_approx(fall_position) and _player.velocity.y == _room.get_node("Hole").player_eject_speed, "model pit gives upward velocity without teleporting")
	_check(_player.velocity.x == 1 and _player.velocity.z == 2, "pit ejection preserves horizontal velocity")
	_player.position = Vector3(30, -15, 30) * _map_scale
	await _frames()
	_check(_player.global_position.is_equal_approx(_room.get_node("ExitPoint").global_position), "out of bounds fall recovers player")
	_flow.pause_game()
	_check(paused and _flow.is_in_game(), "new world supports Esc pause lifecycle")
	_flow.resume_game()
	root.get_node("CoinPool").acquire()
	reload_current_scene()
	await scene_changed
	_bind()
	await _frames()
	_check(_wallet.total == earned and not _sword.oiled and not _room.is_gate_open(), "reload preserves only wallet and resets oil and world")
	_check(root.get_node("CoinPool").active_count() == 0, "reload clears old world coins")
	_flow.return_to_main_menu()
	await scene_changed
	await _frames()
	_check(current_scene.scene_file_path == _flow.MAIN_MENU and not paused, "new world returns to main menu")
	paused = false
	Engine.time_scale = 1.0
	print("MAP WORLD REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _at_shelf() -> void:
	# 在货架前留足墙面余量；高度按真实地板和玩家脚底计算。
	_check(_stand_in_shop(Vector3(-2.5, 0.5, 4.2)), "shelf stance is grounded and clear of world collision")
	_camera.look_at(_shop.shelf.get_item().global_position, Vector3.UP)
	_player.reset_physics_interpolation()
	await _frames()


func _floor_at(at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 2.0, 1)
	ray.exclude = [_player.get_rid()]
	return _room.get_world_3d().direct_space_state.intersect_ray(ray)


func _standing_height() -> float:
	var shape: CollisionShape3D = _player.get_node("CollisionShape3D")
	return (shape.shape as BoxShape3D).size.y * 0.5 - shape.position.y


func _stand_in_shop(local_position: Vector3) -> bool:
	var at: Vector3 = _shop.global_transform * local_position
	var floor_hit := _floor_at(at)
	if floor_hit.is_empty() or floor_hit.collider.name != "ShopFloor":
		return false
	at.y = floor_hit.position.y + _standing_height() + _player.safe_margin
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	var shape: CollisionShape3D = _player.get_node("CollisionShape3D")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.collision_mask = 1
	query.margin = 0.0
	return _room.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## 防止双面薄片留下开放边界、以及坡道覆盖后原地板再次共面闪烁。
func _check_passage_geometry() -> void:
	var geometry = _room.get_node("WorldGeometry")
	for name in ["Passage", "Ramp", "CleaningRamp"]:
		var mesh: Mesh = geometry.get_node(name).mesh
		var faces := mesh.get_faces()
		var edges := {}
		for i in range(0, faces.size(), 3):
			for j in range(3):
				var a := var_to_str(faces[i + j])
				var b := var_to_str(faces[i + (j + 1) % 3])
				var key := a + "|" + b if a < b else b + "|" + a
				edges[key] = int(edges.get(key, 0)) + 1
		var closed := true
		for count in edges.values():
			if count != 2:
				closed = false
		_check(closed, name + " has a closed shell without open mesh edges")
	var original_hidden := true
	for name in ["立方体", "商店区域", "清理区域"]:
		original_hidden = original_hidden and not geometry.get_node("Model/" + name).is_visible_in_tree()
	_check(original_hidden, "uncut source floors are not rendered over replacement floors")
	var samples := [Vector3(-9, -0.0834, 1.5), Vector3(-13.8, -0.4279, 3.6), Vector3(7.5, 0.0153, 0.3)]
	var overlaps := 0
	for floor_name in ["MainFloor", "ShopFloor", "CleaningFloor"]:
		var faces: PackedVector3Array = geometry.get_node(floor_name).mesh.get_faces()
		for point: Vector3 in samples:
			for i in range(0, faces.size(), 3):
				if Geometry3D.segment_intersects_triangle(point + Vector3.UP * 0.005, point - Vector3.UP * 0.005, faces[i], faces[i + 1], faces[i + 2]) != null:
					overlaps += 1
	_check(overlaps == 0, "passage and cleaning ramp samples have no competing room floor surface")


func _at_counter() -> void:
	_check(_stand_in_shop(Vector3(0, 0.5, -0.4)), "counter stance is grounded and clear of world collision")
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	_player.reset_physics_interpolation()
	await _frames()


## 用原玩家碰撞盒查路线；坡面预留 14cm 的脚底高度，再由真实移动验证。
func _routes(start: Vector2i) -> Dictionary:
	var space = _room.get_world_3d().direct_space_state
	var valid := {}
	for ix in range(-44, 29):
		for iz in range(-18, 32):
			var at := Vector2i(ix, iz)
			var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(ix * 0.5, 0.4, iz * 0.5) * _map_scale, Vector3(ix * 0.5, -1, iz * 0.5) * _map_scale, 1))
			if hit.is_empty() or not hit.collider.name in ["MainFloor", "ShopFloor", "CleaningFloor", "PassageRamp", "CleaningRamp"]:
				continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = _player.get_node("CollisionShape3D").shape
			query.transform = Transform3D(Basis.IDENTITY, hit.position + Vector3(0, 1.14, 0))
			query.collision_mask = 1
			query.margin = 0.001
			if space.intersect_shape(query, 1).is_empty():
				valid[at] = hit.position
	var todo := [start]
	var previous := {start: start}
	while not todo.is_empty():
		var at: Vector2i = todo.pop_front()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = at + step
			if valid.has(next) and not previous.has(next):
				# 放大后的封闭坡道侧面有台阶；路线应从坡道端口进入。
				var midpoint: Vector3 = (valid[at] + valid[next]) * 0.5
				var middle_floor := _floor_at(midpoint)
				if middle_floor.is_empty() or absf(middle_floor.position.y - midpoint.y) > 0.03:
					continue
				previous[next] = at
				todo.append(next)
	var result := {}
	for goal in [Vector2i(-31, 16), Vector2i(20, 2)]:
		if not previous.has(goal):
			continue
		var route: Array = []
		var at: Vector2i = goal
		while at != start:
			route.push_front(valid[at])
			at = previous[at]
		result[goal] = route
	return result


func _walk(route: Array) -> bool:
	_camera.rotation = Vector3.ZERO
	for point: Vector3 in route:
		var reached := false
		for frame in range(120):
			var offset: Vector3 = point - _player.global_position
			offset.y = 0
			if offset.length() < 0.12:
				reached = true
				break
			_player.rotation.y = atan2(-offset.x, -offset.z)
			Input.action_press("Up")
			await physics_frame
		Input.action_release("Up")
		await _frames(1)
		if not reached:
			push_error("Walk blocked at %s aiming for %s" % [_player.global_position, point])
			return false
	return _player.is_on_floor()
