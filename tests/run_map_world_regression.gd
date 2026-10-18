extends SceneTree

## 历史完整 GLB 白模：真实碰撞通行、经济循环、火门、配重门与回收。
const Navigation := preload("res://tests/helpers/world_navigation.gd")
var _passed := 0
var _failed := 0
var _directory := "/tmp/map-origin-world-regression"
var _capture_dir := ""
var _room
var _player
var _camera
var _sword
var _grabber
var _shop
var _wallet
var _flow
var _save


func _initialize() -> void:
	create_timer(360.0, true, false, true).timeout.connect(func():
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
	for frame in count:
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(ceili(seconds * Engine.physics_ticks_per_second) + 1)


func _bind() -> void:
	_room = current_scene
	_player = _room.get_node("Player")
	_camera = _player.get_node("Camera3D")
	_sword = _camera.get_node("WeaponRig/WeaponPivot/Mount")
	_grabber = _camera.get_node("Grabber")
	_shop = _room.get_node("ShopRoom")


func _anchor(id: String) -> Vector3:
	return _room.get_node("GameplayAnchors/" + id).global_position


func _scale() -> float:
	return _room.get_node("WorldGeometry").scale.x


func _place(id: String) -> void:
	_player.set_physics_process(false)
	_player.global_position = _anchor(id)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _capture(name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames()
	if name == "02_shop":
		_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	elif name == "03_gallery":
		_camera.look_at(Vector3(16, 3.8, 1.5) * _scale(), Vector3.UP)
	elif name == "04_deep_room":
		_camera.look_at(Vector3(26.3, 4.2, -7) * _scale(), Vector3.UP)
	RenderingServer.force_draw(true)
	_check(root.get_texture().get_image().save_png(_capture_dir.path_join(name + ".png")) == OK, "capture " + name)


func _mouse(button: MouseButton) -> void:
	if button == MOUSE_BUTTON_RIGHT and DisplayServer.get_name() == "headless":
		_grabber.handle_grab_input(true)
		_grabber.handle_grab_input(false)
	else:
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			event.pressed = pressed
			Input.parse_input_event(event)
		Input.flush_buffered_events()
	await _frames()


func _route(goal: String) -> bool:
	var nodes := Navigation.sample(_room, _player)
	var path := Navigation.find_path(nodes, _player.global_position, _anchor(goal), _scale())
	_check(not path.is_empty(), "sampled route exists to " + goal)
	return await Navigation.walk(self, _player, path)


func _run() -> void:
	await process_frame
	# 显式选择历史地图夹具；正式入口另由 run_main_world_* 验证。
	load("res://tests/helpers/legacy_world_fixture.gd").install(self)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_capture_dir = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--data-dir="):
			_directory = argument.trim_prefix("--data-dir=")
	if not _directory.begins_with("/tmp/"):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	if _capture_dir.begins_with("/tmp/"):
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	else:
		_capture_dir = ""
	_wallet = root.get_node("Wallet")
	_flow = root.get_node("GameFlow")
	_save = root.get_node("SaveGame")
	_save.save_path = _directory.path_join("savegame.json")
	root.get_node("GameSettings").settings_path = _directory.path_join("settings.cfg")
	_check(_flow.start_new_game().ok, "new game uses formal world entry")
	await scene_changed
	_bind()
	await _wait(0.5)
	await _test_environment()
	await _test_income()
	await _test_shop_and_vines()
	await _test_weight_gate()
	await _test_room_returns()
	await _test_persistence()
	print("MAP WORLD REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_environment() -> void:
	var geometry: Node3D = _room.get_node("WorldGeometry")
	_check(geometry.get_meta("source_sha256") == FileAccess.get_sha256("res://assets/map_origin.glb"), "baked geometry matches original GLB digest")
	_check(geometry.scale.is_equal_approx(Vector3.ONE * 3.0) and geometry.get_meta("source_scale") == 5.0 and _player.scale.is_equal_approx(Vector3.ONE), "current complete world is enlarged three times while player keeps original size")
	_check(geometry.get_node("Collision").get_child_count() == 6, "six room collisions include connecting ramps for accurate room ownership")
	_check((geometry.global_transform * geometry.get_node("Model").mesh.get_aabb()).size.x > 240, "complete world geometry spans the enlarged dimensions")
	_check(_player.is_on_floor() and _player.global_position.y > 1.0, "player spawns and settles on actual cave floor")
	_check(not _room.is_gate_open() and _room.get_node("WeightPuzzle/Gate").is_closed(), "new world starts with both progression gates closed")
	_check(_room.get_node("HUD/OnboardingHints").get_stage() == "controls", "new player receives existing onboarding")
	await _capture("01_spawn")
	_check(await _route("Shop"), "real WASD walks from cave to shop across new entrance")
	await _capture("02_shop")
	_check(await _route("Main"), "real WASD returns from shop to cave")
	var before := _anchor("VineBefore")
	_place("VineBefore")
	_player.velocity = Vector3(5, 0, 0)
	for frame in int(60 * _scale()):
		_player.move_and_slide()
		await physics_frame
	_check(_player.position.x < _room.get_node("VineGate").position.x - 0.4 and _player.position.x > before.x, "closed vines block the actual new main doorway")


func _test_income() -> void:
	var starter = _room.get_node("StarterCleaningRoom/RatSpawner")
	await _wait(3.2)
	_check(starter.get_alive_count() > 0, "starter rats spawn on new cave floor")
	for cycle in 3:
		await _wait(3.1)
		var rats: Array = starter.get_spawned_monsters()
		_check(not rats.is_empty(), "starter provides rat for income cycle")
		if rats.is_empty():
			return
		var rat = rats[0]
		rat.set_physics_process(false)
		_place("Combat")
		_player.rotation = Vector3.ZERO
		_camera.rotation = Vector3(deg_to_rad(-45), 0, 0)
		rat.global_position = _camera.global_transform * Vector3(0, -0.34, -1.4)
		var corpses: Array = []
		root.get_node("EventBus").corpse_spawned.connect(func(corpse): corpses.append(corpse), CONNECT_ONE_SHOT)
		await _frames()
		await _mouse(MOUSE_BUTTON_LEFT)
		await _wait(0.8)
		_check(not is_instance_valid(rat) and not corpses.is_empty(), "actual sword kills rat and creates corpse in new map")
		if corpses.is_empty():
			return
		var corpse = corpses[0]
		corpse.freeze = true
		corpse.global_position = _camera.global_position - _camera.global_basis.z * 1.6
		await _frames()
		await _mouse(MOUSE_BUTTON_RIGHT)
		_check(_grabber.get_held() == corpse, "real right click picks up rat in new map")
		var hole = _room.get_node("Hole")
		corpse.global_position = hole.global_position + Vector3(0, 0.4, 0)
		await _frames(5)
		_check(not is_instance_valid(corpse) and not _grabber.is_holding(), "model pit receives offering and clears carrying")
		await _wait(4.0)
		_check(await load("res://tests/helpers/coin_collection.gd").collect_all(self, _player), "coins land on real pit rim and are picked up by walking contact")
	_check(_wallet.total >= _shop.shelf.item_data.price, "unchanged rat income can fund first oil purchase")
	_check(_room.get_node("HUD/OnboardingHints").get_stage() == "complete", "first kill and pickup complete onboarding")


func _test_shop_and_vines() -> void:
	var stock = _shop.shelf
	_player.set_physics_process(false)
	_player.global_position = stock.global_position + Vector3(0, 0.5, 1.3)
	_camera.look_at(stock.get_item().global_position, Vector3.UP)
	await _frames()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_grabber.get_held() == stock.get_item(), "new shop shelf is reachable and stocked")
	_player.global_position = _shop.to_global(Vector3(0, 0.5, -0.4))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	await _frames()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_shop.counter.item != null, "new shop counter accepts actual carried oil")
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(3.5)
	_check(_sword.oiled and _shop.get_purchase_count(&"oil") == 1, "actual shopkeeper interaction buys oil once")
	var torch = _room.get_node("Torch")
	_player.global_position = torch.global_position + Vector3(0.55, 0.5, 1.5)
	_camera.look_at(torch.get_node("ElementComponent").global_position, Vector3.UP)
	var offset: Vector3 = torch.get_node("ElementComponent").global_position - _sword.element.global_position
	_player.global_position += Vector3(offset.x, 0, offset.z)
	await _wait(0.5)
	_check(_sword.is_burning(), "migrated main torch ignites purchased sword")
	for vine in _room.get_node("VineGate").get_children():
		_player.global_position = vine.global_position + Vector3(-1.2, 0.5, 0)
		_camera.look_at(vine.element.global_position, Vector3.UP)
		var delta: Vector3 = vine.element.global_position - _sword.element.global_position
		_player.global_position += delta
		await _wait(0.2)
	await _wait(10.5)
	_check(_room.is_gate_open(), "real fire contact burns full main doorway open")
	_place("VineBefore")
	_check(await _route("Entry"), "player walks through burned opening into entry room")
	_check(await _route("Cleaning"), "player walks new ramp into first cleaning room")
	_check(await _route("Gallery"), "player walks between cleaning room and gallery")
	await _wait(5.5)
	for name in ["EntryRatSpawner", "RatSpawner", "GalleryRatSpawner"]:
		_check(_room.get_node(name).get_alive_count() > 0, "unlocked " + name + " actually spawns rats")
	await _capture("03_gallery")


func _test_weight_gate() -> void:
	var platform = _room.get_node("WeightPuzzle/Platform")
	var gate = _room.get_node("WeightPuzzle/Gate")
	_place("WeightBefore")
	_player.velocity = Vector3(5, 0, 0)
	for frame in int(60 * _scale()):
		_player.move_and_slide()
		await physics_frame
	_check(_player.position.x < gate.position.x - 0.5, "closed lift gate blocks deep room")
	var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
	corpse.setup(load("res://resources/enemies/monster_rat.tres"))
	_room.add_child(corpse)
	_place("PlatformThrow")
	_player.rotation = Vector3.ZERO
	_camera.rotation = Vector3(deg_to_rad(45 if _scale() > 1.0 else 28), 0, 0)
	_grabber.apply_upgrade("charged_throw")
	corpse.freeze = true
	corpse.global_position = _camera.global_position - _camera.global_basis.z * 1.6
	await _frames()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_grabber.get_held() == corpse, "real right click grabs rat for high platform")
	corpse.freeze = false
	await _frames(30)
	_grabber.handle_grab_input(true)
	await _frames(92 if _scale() > 1.0 else 21)
	var predicted: Vector3 = _grabber._trajectory.points[-1]
	_check(_grabber._trajectory.collided and absf(predicted.x - platform.position.x) < platform.platform_size.x * 0.5 and absf(predicted.z - platform.position.z) < platform.platform_size.z * 0.5 and predicted.y > platform.position.y, "charged trajectory predicts actual high platform landing")
	await _capture("04_platform_throw")
	_grabber.handle_grab_input(false)
	await _wait(4.0)
	_check(platform.is_pressed() and gate.is_open() and corpse.position.y > platform.position.y, "actual charged throw lands and opens formal high platform gate")
	_check(gate.is_persistently_open() and not gate.is_blocked(), "gate has unobstructed upward clearance and latches")
	_place("Cleaning")
	_check(await _route("Deep"), "real WASD traverses open lift doorway into deep room")
	await _capture("04_deep_room")
	_check(_room.get_node("DeepRatSpawner").enabled, "opening lift gate enables deep room rats")
	await _wait(5.5)
	_check(_room.get_node("DeepRatSpawner").get_alive_count() > 0, "deep room actually spawns rats after gate opens")


func _test_room_returns() -> void:
	var hole = _room.get_node("Hole")
	var outlet = _room.get_node("CorpseReturnOutlet")
	_check(hole.apply_upgrade("corpse_return"), "formal outlet can enable existing corpse-return upgrade")
	var transfers: Array = []
	outlet.corpse_transferred.connect(func(corpse, room_id): transfers.append([corpse.get_instance_id(), room_id]))
	for spec in [["Main", "MainRoomExitCleaning", "main"], ["Shop", "ShopRoomExit", "shop"], ["Entry", "EntryExitMain", "entry"], ["Cleaning", "CleaningRoomExit", "cleaning"], ["Deep", "DeepRoomExit", "deep"], ["Gallery", "GalleryExitEntry", "gallery"]]:
		var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
		corpse.setup(load("res://resources/enemies/monster_rat.tres"))
		_room.add_child(corpse)
		corpse.position = _anchor(spec[0]) + Vector3.UP * 0.2
		var id: int = corpse.get_instance_id()
		await _wait(0.5)
		var trigger = _room.get_node(spec[1])
		_check(trigger.contains_corpse(corpse), "corpse belongs to actual " + spec[2] + " room floor")
		trigger.room_left.emit(trigger)
		await _frames()
		_check(transfers.any(func(entry): return entry[0] == id and str(entry[1]) == spec[2]), "leaving " + spec[2] + " transfers its rat corpse")
		if is_instance_valid(corpse):
			corpse.queue_free()
		await _frames()


func _test_persistence() -> void:
	_check(_save.save_game().ok, "manual save records formal map state")
	var saved: Dictionary = _save.read_save()
	_check(saved.level == "world" and saved.opened_gates.has("world.cleaning.vines") and saved.opened_gates.has("world.cleaning.weight_gate"), "stable world ID saves both permanent gates")
	_check(_flow.load_game().ok, "formal save reloads through existing menu flow")
	await scene_changed
	_bind()
	await _wait(0.4)
	_check(_room.is_gate_open() and _room.get_node("WeightPuzzle/Gate").is_open(), "load restores physical vine and lift passage")
	_check(_sword.oiled and _room.get_node("HUD/OnboardingHints").get_stage() == "complete", "load restores purchased oil and tutorial completion")
	_place("Main")
	_player.global_position.y = -40 * _scale()
	await _frames()
	_check(_player.global_position.distance_to(_room.get_node("ExitPoint").global_position) < 0.1, "out of bounds returns player to new spawn")
	_check(_flow.reset_current_game().ok, "development reset uses managed scene transition")
	await scene_changed
	_bind()
	await _frames()
	_check(not _room.is_gate_open() and _room.get_node("WeightPuzzle/Gate").is_closed(), "reset clears temporary world state without changing saved gate snapshot")
	_check(_save.read_save().opened_gates.has("world.cleaning.weight_gate"), "development reset leaves disk progress untouched")
