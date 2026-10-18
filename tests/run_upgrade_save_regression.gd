extends SceneTree

## --headless --path . --script res://tests/run_upgrade_save_regression.gd -- --data-dir=<隔离目录>
## --phase=write / read 在两次独立进程中验证真实购买与升级持久化。
var _passed := 0
var _failed := 0
var _directory := ""
var _phase := "full"
var _save
var _flow
var _wallet
var _world
var _player
var _camera
var _grabber
var _sword
var _shop
var _hole
var _outlet


func _initialize() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func():
		push_error("UPGRADE SAVE REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("UPGRADE SAVE REGRESSION FAILED: " + message)


func _frames(count: int = 3) -> void:
	for frame in range(count):
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(int(ceil(seconds * Engine.physics_ticks_per_second)) + 1)


func _bind() -> void:
	_world = current_scene
	_player = _world.get_node("Player")
	_camera = _player.get_node("Camera3D")
	_grabber = _camera.get_node("Grabber")
	_sword = _camera.get_node("WeaponRig/WeaponPivot/Mount")
	_shop = _world.get_node("ShopRoom")
	_hole = _world.get_node("Hole")
	_outlet = _world.get_node("CorpseReturnOutlet")
	_player.set_physics_process(false)
	_player.rotation = Vector3.ZERO


func _enter(load_saved: bool = false) -> void:
	var result: Dictionary = _flow.load_game() if load_saved else _flow.start_new_game()
	_check(result.ok, "load save" if load_saved else "start new game")
	await scene_changed
	_bind()
	await _frames()


func _stand(at: Vector3) -> void:
	var world_scale: float = _world.get_node("WorldGeometry").scale.y
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 12.0 * world_scale, 1)
	var hit: Dictionary = _world.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		at.y = hit.position.y + 0.5 + _player.safe_margin
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames()


func _right(pressed: bool) -> void:
	if DisplayServer.get_name() == "headless":
		_grabber.handle_grab_input(pressed)
	else:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _click_right() -> void:
	_right(true)
	_right(false)
	await _frames()


func _strike() -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _wait(0.8)


func _click(button: Control) -> void:
	var at := root.get_final_transform() * button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames()


func _save_from_pause() -> void:
	await _key(KEY_ESCAPE)
	_check(paused, "escape opens paused save menu")
	var menu = _flow.get_node("PauseMenu")
	_check(menu.get_node("%SaveStatus").text.contains("已购升级"), "pause menu explains upgrade persistence")
	await _click(menu.get_node("%SaveButton"))
	_check(menu.get_node("%SaveStatus").text.contains("存档成功"), "actual save button saves the snapshot")
	await _key(KEY_ESCAPE)


func _menu_load() -> void:
	await _key(KEY_ESCAPE)
	await _click(_flow.get_node("PauseMenu").get_node("%MainMenuButton"))
	_check(current_scene.scene_file_path == _flow.MAIN_MENU and not paused, "actual pause button returns to main menu")
	_check(not current_scene.get_node("%LoadGameButton").disabled, "saved game is available in main menu")
	await _click(current_scene.get_node("%LoadGameButton"))
	_bind()
	await _frames()


func _begin_purchase(shelf_name: String) -> void:
	var stock = _shop.get_node(shelf_name)
	var item = stock.get_item()
	_check(item != null, shelf_name + " has stock")
	if item == null:
		return
	_stand(_shop.to_global(stock.position + Vector3(0, 0.5, 1.2)))
	_camera.look_at(item.global_position, Vector3.UP)
	await _frames()
	await _click_right()
	_check(_grabber.get_held() == item, shelf_name + " ray grabs actual product")
	_stand(_shop.to_global(Vector3(0, 0.5, -0.4)))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	await _frames()
	await _click_right()
	_check(_shop.counter.item == item and not _grabber.is_holding(), "product docks on counter")
	await _strike()
	_check(_shop.busy and _grabber.interaction_locked, "actual sword hit begins purchase")


func _buy(shelf_name: String) -> void:
	await _begin_purchase(shelf_name)
	await _wait(3.0)
	_check(not _shop.busy and _shop.counter.item == null, "completed purchase consumes product and releases transaction")


func _verify_owned(egg: bool, glove: bool, coins: int, oil: bool = false) -> void:
	_check(_wallet.total == coins, "restore preserves exact saved coins without charging")
	_check(_sword.oiled == oil and _sword.data.upgrade_tags.has("oil") == oil and _sword.element.tags.has("flammable") == oil, "restored oil restores sword data and ignitable ability together")
	_check(_shop.get_purchase_count(&"oil") == (1 if oil else 0), "restored oil purchase count matches saved progress")
	_check(not _shop.shelf.sold_out and _shop.shelf.get_item() != null and _shop.shelf.get_node("Sign").text.contains("无需重复购买") == oil, "oil retains stocked shelf and shows owned upgrade after restore")
	_check(not load("res://resources/swords/sword_starter.tres").upgrade_tags.has("oil"), "oil restore never mutates shared starter sword resource")
	_check(_hole.has_upgrade("corpse_return") == egg and _outlet.is_enabled() == egg, "restored hole ability enables its ready outlet")
	_check(_grabber.has_upgrade("charged_throw") == glove, "restored glove ability matches saved purchase")
	for entry in [["CorpseReturnShelf", "corpse_return", egg], ["ChargedThrowShelf", "charged_throw", glove]]:
		var stock = _shop.get_node(entry[0])
		_check(_shop.get_purchase_count(StringName(entry[1])) == (1 if entry[2] else 0), "restored purchase limit for " + entry[1])
		_check(stock.sold_out == entry[2] and (stock.get_item() == null) == entry[2], "restored shelf removes only purchased stock: " + entry[1])
		_check(stock.get_node("Sign").text.contains("已售罄") == entry[2], "restored sold-out sign for " + entry[1])
	_check(not _shop.busy and not _shop.counter.locked and not _grabber.interaction_locked and not _sword.interaction_locked, "restore leaves interactions unlocked")


func _verify_oil_ignition() -> void:
	var torch = _world.get_node("Torch")
	_player.position = torch.position + Vector3(0.55, 0.5, 1.5)
	_camera.look_at(torch.get_node("ElementComponent").global_position, Vector3.UP)
	var delta: Vector3 = torch.get_node("ElementComponent").global_position - _sword.element.global_position
	_player.position += Vector3(delta.x, 0, delta.z)
	await _wait(0.5)
	_check(_sword.is_burning() and _sword.fire_swings_remaining == 5, "loaded oil sword ignites through real torch contact")


func _verify_effects() -> void:
	# 载入后真实抓取、蓄力、轨迹与刚体速度，无再次手动授予能力。
	_stand(_world.get_node("GameplayAnchors/Combat").global_position)
	_camera.rotation = Vector3.ZERO
	var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
	corpse.freeze = true
	_world.add_child(corpse)
	corpse.global_position = _camera.global_position - _camera.global_basis.z * 1.6
	await _frames()
	await _click_right()
	_check(_grabber.get_held() == corpse, "loaded glove can pick up real corpse")
	corpse.freeze = false
	_right(true)
	await _wait(0.6)
	_check(_grabber._trajectory.visible and _grabber._trajectory.points.size() > 2, "loaded glove shows charged throw arc")
	_right(false)
	_check(not corpse.is_held and corpse.linear_velocity.length() > 7.0, "loaded glove launches actual corpse")
	corpse.queue_free()
	await _frames()
	# 从商店实际走出，验证载入的出口与离房信号已连接。
	corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
	corpse.position = _shop.to_global(Vector3(2.5, 0.45, 1.5))
	_world.add_child(corpse)
	var corpse_id: int = corpse.get_instance_id()
	var transfers: Array = []
	_outlet.corpse_transferred.connect(func(candidate, room_id): transfers.append({"id": candidate.get_instance_id(), "room": room_id}))
	var trigger = _world.get_node("ShopRoomExit")
	var direction: Vector3 = trigger.global_basis * trigger.room_direction.normalized()
	_stand(trigger.global_position + direction * 3.0)
	await _frames()
	_player.set_physics_process(true)
	var target: Vector3 = trigger.global_position - direction * 3.0
	for frame in range(400):
		var offset: Vector3 = target - _player.global_position
		offset.y = 0.0
		if offset.length() < 0.12:
			break
		_player.rotation.y = atan2(-offset.x, -offset.z)
		Input.action_press("Up")
		await physics_frame
	Input.action_release("Up")
	await _frames()
	_player.set_physics_process(false)
	_check(transfers.any(func(entry): return entry.id == corpse_id and entry.room == &"shop"), "loaded egg transfers corpse on actual shop exit")
	if is_instance_valid(corpse):
		corpse.queue_free()


func _write_raw(text: String) -> void:
	var file := FileAccess.open(_save.save_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _run() -> void:
	await process_frame
	# 显式选择历史地图夹具；正式入口另由 run_main_world_* 验证。
	load("res://tests/helpers/legacy_world_fixture.gd").install(self, "res://tests/fixtures/three_room_world.tscn")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data-dir="):
			_directory = argument.trim_prefix("--data-dir=")
		elif argument.begins_with("--phase="):
			_phase = argument.trim_prefix("--phase=")
	if _directory.is_empty():
		push_error("Use --data-dir pointing to an isolated test directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	_save = root.get_node("SaveGame")
	_flow = root.get_node("GameFlow")
	_wallet = root.get_node("Wallet")
	_save.save_path = _directory.path_join("savegame.json")
	root.get_node("GameSettings").settings_path = _directory.path_join("settings.cfg")
	if _phase == "read":
		await _enter(true)
		_verify_owned(true, true, 790, true)
		_check(_shop.completed_purchases == 0, "fresh process restore does not replay purchases")
		await _verify_effects()
		await _verify_oil_ignition()
		_finish()
		return
	await _enter()
	_verify_owned(false, false, 0)
	for entry in [["CorpseReturnShelf", "灵魂鸡蛋", "对死掉的东西有无与伦比的吸引力"], ["ChargedThrowShelf", "棒球手套", "现在你的右手更有力气了"]]:
		var stock = _shop.get_node(entry[0])
		_check(stock.item_data.display_name == entry[1] and stock.item_data.description == entry[2], "product uses design name and description")
		_check(stock.get_node("Sign").text.contains(entry[2]) and stock.get_item().get_node("Price").text.contains(entry[2]), "world labels include product description")
	_wallet.set_total(1000)
	_check(_wallet.total == 1000, "test setup supplies purchase budget")
	await _begin_purchase("CorpseReturnShelf")
	if _phase == "full":
		await _save_from_pause()
		var in_flight: Dictionary = _save.read_save()
		_check(in_flight.ok and in_flight.coins == 1000 and in_flight.upgrades == {"oil": false, "corpse_return": false, "charged_throw": false, "mirror": false}, "in-flight save neither charges nor records incomplete purchase")
	await _wait(3.0)
	_check(_wallet.total == 995 and _hole.has_upgrade("corpse_return"), "completed egg purchase charges five")
	if _phase == "full":
		await _save_from_pause()
	await _buy("ChargedThrowShelf")
	_check(_wallet.total == 795 and _grabber.has_upgrade("charged_throw"), "completed glove purchase charges two hundred")
	if _phase == "write":
		await _buy("Shelf")
		await _save_from_pause()
		_check(_wallet.total == 790 and _save.read_save().upgrades == {"oil": true, "corpse_return": true, "charged_throw": true, "mirror": false}, "write process stores all three completed purchases")
		_finish()
		return
	_check(_save.read_save().coins == 995 and not _save.read_save().upgrades.charged_throw, "unsaved glove purchase leaves previous snapshot intact")
	await _menu_load()
	_verify_owned(true, false, 995)
	_check(_shop.completed_purchases == 0, "partial restore does not replay purchase animation")
	await _buy("ChargedThrowShelf")
	await _save_from_pause()
	var saved_text := FileAccess.get_file_as_string(_save.save_path)
	await _menu_load()
	_verify_owned(true, true, 795)
	_check(_shop.completed_purchases == 0 and _shop.restore_purchased_upgrades(_save.read_save().upgrades), "restoration is idempotent without transactions")
	_verify_owned(true, true, 795)
	await _verify_effects()
	# 复制出来的已售商品也不能再次扣款。
	var duplicate = load("res://scenes/shop/shop_item.tscn").instantiate()
	duplicate.data = _shop.get_node("ChargedThrowShelf").item_data
	_world.add_child(duplicate)
	_shop.counter.place_item(duplicate)
	_stand(_shop.to_global(Vector3(0, 0.5, -0.4)))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	await _frames()
	await _strike()
	_check(not _shop.busy and _wallet.total == 795 and _shop.counter.item == duplicate and _shop.get_purchase_count(&"charged_throw") == 1, "restored one-time product rejects duplicate purchase without debit")
	await _enter()
	_verify_owned(false, false, 0)
	_check(FileAccess.get_file_as_string(_save.save_path) == saved_text, "new game clears live progress and preserves saved purchases")
	DirAccess.make_dir_absolute(_save.save_path + ".tmp")
	_check(not _save.save_game().ok and FileAccess.get_file_as_string(_save.save_path) == saved_text, "failed atomic write keeps complete previous upgrade snapshot")
	DirAccess.remove_absolute(_save.save_path + ".tmp")
	# 调试免费能力不是一次购买。
	change_scene_to_file(_flow.MECHANISM_LAB)
	await scene_changed
	await _frames()
	await _key(KEY_E)
	_check(current_scene.get_node("Player/Camera3D/Grabber").has_upgrade("charged_throw"), "lab E grants free debug ability")
	_check(_save.save_game().ok and _save.read_save().upgrades == {"oil": false, "corpse_return": false, "charged_throw": false, "mirror": false}, "free debug ability is excluded from purchased progress")
	_check(_flow.load_game().ok, "load lab save")
	await scene_changed
	await _frames()
	_check(current_scene.scene_file_path == _flow.MECHANISM_LAB and not current_scene.get_node("Player/Camera3D/Grabber").has_upgrade("charged_throw"), "lab save restores entrance without free debug ability")
	await _enter()
	_verify_owned(false, false, 0)
	# v1 精确金币迁移，不凭空解锁；下一次手动保存升级为最新格式。
	_write_raw('{"version":1,"coins":"9007199254740993"}')
	await _enter(true)
	_verify_owned(false, false, 9007199254740993)
	_check(_save.save_game().ok and JSON.parse_string(FileAccess.get_file_as_string(_save.save_path)).version == _save.FORMAT_VERSION, "old save migrates on next manual save with exact coins")
	var previous_scene = current_scene
	for invalid in [null, [], {}, {"corpse_return": true}, {"corpse_return": 1, "charged_throw": false}, {"corpse_return": true, "charged_throw": "true"}, {"corpse_return": false, "charged_throw": null}, {"corpse_return": false, "unknown": false}, {"corpse_return": false, "charged_throw": false, "unknown": true}]:
		_write_raw(JSON.stringify({"version": 2, "coins": "123", "upgrades": invalid}))
		_check(not _flow.load_game().ok and current_scene == previous_scene and _wallet.total == 9007199254740993, "malformed upgrade data leaves live world and wallet intact")
	for invalid in [null, {}, {"corpse_return": true, "charged_throw": true}, {"oil": 1, "corpse_return": true, "charged_throw": true}, {"oil": "true", "corpse_return": true, "charged_throw": false}, {"oil": true, "corpse_return": false, "charged_throw": null}, {"oil": false, "corpse_return": false, "unknown": true}, {"oil": false, "corpse_return": false, "charged_throw": false, "unknown": true}]:
		_write_raw(JSON.stringify({"version": 3, "coins": "123", "upgrades": invalid}))
		_check(not _flow.load_game().ok and current_scene == previous_scene and _wallet.total == 9007199254740993, "malformed v3 oil data cannot change wallet or world")
	# v2 保留原有两件升级；原格式没有油，不推测未记录的购买。
	for flags in [{"corpse_return": false, "charged_throw": false}, {"corpse_return": true, "charged_throw": false}, {"corpse_return": false, "charged_throw": true}, {"corpse_return": true, "charged_throw": true}]:
		_write_raw(JSON.stringify({"version": 2, "coins": "9007199254740993", "upgrades": flags}))
		await _enter(true)
		_verify_owned(flags.corpse_return, flags.charged_throw, 9007199254740993)
		_check(_shop.completed_purchases == 0 and _save.save_game().ok and JSON.parse_string(FileAccess.get_file_as_string(_save.save_path)).version == _save.FORMAT_VERSION, "v2 migrates both old upgrades without replay or oil grant")
	await _test_oil_save()
	_finish()


func _test_oil_save() -> void:
	await _enter()
	_wallet.set_total(1000)
	await _begin_purchase("Shelf")
	await _save_from_pause()
	_check(_save.read_save().coins == 1000 and not _save.read_save().upgrades.oil, "mid-forge save keeps money and excludes undelivered oil")
	await _menu_load()
	_verify_owned(false, false, 1000)
	_check(_sword.visible and not _sword.is_burning(), "cancelled oil forge restores visible unupgraded sword")
	await _buy("Shelf")
	_check(_wallet.total == 995 and _sword.oiled and not _save.read_save().upgrades.oil, "oil purchase completes once without overwriting unsaved progress")
	await _save_from_pause()
	_check(_save.read_save().upgrades == {"oil": true, "corpse_return": false, "charged_throw": false, "mirror": false}, "oil-only snapshot records purchased sword upgrade")
	await _menu_load()
	_verify_owned(false, false, 995, true)
	_check(_shop.completed_purchases == 0 and not _sword.is_burning() and _sword.data.id == &"starter_oil", "oil-only load restores sword data without replay or auto ignition")
	var restored_data = _sword.data
	_check(_shop.restore_purchased_upgrades(_save.read_save().upgrades) and _sword.data == restored_data, "restoring owned oil is idempotent and does not duplicate sword data")
	var duplicate = load("res://scenes/shop/shop_item.tscn").instantiate()
	duplicate.data = _shop.shelf.item_data
	_world.add_child(duplicate)
	_shop.counter.place_item(duplicate)
	_stand(_shop.to_global(Vector3(0, 0.5, -0.4)))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	await _frames()
	await _strike()
	_check(not _shop.busy and _wallet.total == 995 and _shop.counter.item == duplicate and _shop.get_status_message().contains("无需重复"), "loaded oil rejects real keeper strike with no duplicate debit")
	_shop.counter.consume_item()
	await _frames()
	await _verify_oil_ignition()
	await _save_from_pause()
	await _menu_load()
	_verify_owned(false, false, 995, true)
	_check(not _sword.is_burning() and _sword.fire_swings_remaining == 0, "save while burning retains permanent oil and resets temporary fire")
	await _buy("CorpseReturnShelf")
	await _buy("ChargedThrowShelf")
	await _save_from_pause()
	var saved_text := FileAccess.get_file_as_string(_save.save_path)
	_check(_save.read_save().upgrades == {"oil": true, "corpse_return": true, "charged_throw": true, "mirror": false}, "all implemented paid upgrades share one complete snapshot")
	await _menu_load()
	_verify_owned(true, true, 790, true)
	_check(_shop.completed_purchases == 0, "all-upgrade load restores without repeating purchases")
	await _enter()
	_verify_owned(false, false, 0)
	_check(FileAccess.get_file_as_string(_save.save_path) == saved_text, "new game clears all three upgrades without deleting old save")
	DirAccess.make_dir_absolute(_save.save_path + ".tmp")
	_check(not _save.save_game().ok and FileAccess.get_file_as_string(_save.save_path) == saved_text, "failed write preserves saved oil and both other upgrades together")
	DirAccess.remove_absolute(_save.save_path + ".tmp")
	_sword.apply_oil()
	_check(_sword.oiled and _save.save_game().ok and not _save.read_save().upgrades.oil, "free debug oil has no purchase record and is excluded from paid progress")
	await _enter(true)
	_verify_owned(false, false, 0)


func _finish() -> void:
	paused = false
	Engine.time_scale = 1.0
	print("UPGRADE SAVE REGRESSION RESULT: phase=%s passed=%d failed=%d" % [_phase, _passed, _failed])
	quit(0 if _failed == 0 else 1)
