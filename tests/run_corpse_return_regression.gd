extends SceneTree

## 正式地图：真实打怪收入、实体购买、通道往返、物理回收与落地拾币。
const CORPSE_SCENE := "res://scenes/enemies/corpse.tscn"
const PRODUCT := preload("res://resources/shop/shop_item_corpse_return.tres")
var _passed := 0
var _failed := 0
var _room
var _player
var _camera
var _sword
var _grabber
var _shop
var _stock
var _hole
var _outlet
var _exit
var _wallet
var _flow
var _bus
var _leaves := 0
var _transfers: Array = []
var _capture_dir := ""


func _initialize() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func():
		push_error("CORPSE RETURN REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("CORPSE RETURN REGRESSION FAILED: " + message)


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
	_stock = _shop.get_node("CorpseReturnShelf")
	_hole = _room.get_node("Hole")
	_outlet = _room.get_node("CorpseReturnOutlet")
	_exit = _room.get_node("CleaningRoomExit")
	_exit.room_left.connect(func(_source): _leaves += 1)
	_outlet.corpse_transferred.connect(func(corpse, room_id): _transfers.append({"id": corpse.get_instance_id(), "room": room_id, "at": corpse.global_position, "forward": -corpse.global_basis.z}))
	_player.set_physics_process(false)
	_player.rotation = Vector3.ZERO


func _floor_at(at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 2.0, 1)
	ray.exclude = [_player.get_rid()]
	return _room.get_world_3d().direct_space_state.intersect_ray(ray)


func _cleaning_transfers() -> Array:
	return _transfers.filter(func(entry): return entry.room == &"cleaning")


func _stand(at: Vector3) -> void:
	var hit := _floor_at(at)
	if not hit.is_empty():
		at.y = hit.position.y + 0.5 + _player.safe_margin
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


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


func _place_product(stock: Node3D):
	var item = stock.get_item()
	_stand(_shop.to_global(Vector3(stock.position.x, 0.5, 4.2)))
	_camera.look_at(item.global_position, Vector3.UP)
	await _frames()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_grabber.get_held() == item, "real shelf ray picks up " + item.data.display_name)
	_stand(_shop.to_global(Vector3(0, 0.5, -0.4)))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	await _frames()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_shop.counter.item == item and not _grabber.is_holding(), "right click docks product on actual counter")
	return item


func _walk_x(target: float) -> bool:
	_player.rotation = Vector3.ZERO
	_player.set_physics_process(true)
	var action := "Left" if target < _player.global_position.x else "Right"
	Input.action_press(action)
	for frame in range(400):
		if absf(_player.global_position.x - target) < 0.12:
			break
		await physics_frame
	Input.action_release(action)
	await _frames()
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	return absf(_player.global_position.x - target) < 0.2


func _new_corpse(data: MonsterData, at: Vector3):
	var corpse = load(CORPSE_SCENE).instantiate()
	corpse.setup(data)
	corpse.position = at
	_room.add_child(corpse)
	return corpse


func _capture(name: String, at := Vector3.INF, target := Vector3.ZERO) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var overview: Camera3D
	if at.is_finite():
		overview = Camera3D.new()
		_room.add_child(overview)
		overview.global_position = at
		overview.look_at(target, Vector3.UP)
		overview.make_current()
	await _frames()
	RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(_capture_dir.path_join(name + ".png"))
	if overview != null:
		_camera.make_current()
		overview.queue_free()


func _earn_income() -> void:
	var starter = _room.get_node("StarterCleaningRoom/RatSpawner")
	await _wait(3.0)
	for cycle in range(5):
		var rat
		for child in starter.get_children():
			if child.has_method("take_hit"):
				rat = child
				break
		_check(rat != null, "starter rat exists for earned income")
		if rat == null:
			return
		rat.set_physics_process(false)
		_stand(Vector3(6, 0.5, -14))
		_camera.rotation = Vector3(deg_to_rad(-45), 0, 0)
		rat.global_position = _camera.global_transform * Vector3(0, -0.34, -1.4)
		var corpses: Array = []
		_bus.corpse_spawned.connect(func(corpse): corpses.append(corpse), CONNECT_ONE_SHOT)
		await _frames()
		await _mouse(MOUSE_BUTTON_LEFT)
		await _wait(0.8)
		_check(not is_instance_valid(rat) and not corpses.is_empty(), "real sword kill produces valued corpse")
		if corpses.is_empty():
			return
		var corpse = corpses[0]
		corpse.freeze = true
		corpse.global_position = _camera.global_position - _camera.global_basis.z * 2.0
		await _frames()
		await _mouse(MOUSE_BUTTON_RIGHT)
		_check(_grabber.get_held() == corpse, "earned corpse can be held")
		_stand(Vector3(0, 0.5, -12))
		corpse.global_position = _hole.global_position + Vector3.UP * 1.8
		await _frames(5)
		await _wait(4.0)
		_check(await load("res://tests/helpers/coin_collection.gd").collect_all(self, _player), "earned coins collected by walking contact")
	_check(_wallet.total == 10, "five actual kills and offerings fund both five coin products")


func _open_gate() -> void:
	await _place_product(_shop.shelf)
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(3.0)
	_check(_sword.oiled and _wallet.total == 5, "ordinary oil product still works beside hole product")
	var torch = _room.get_node("Torch")
	_player.position = torch.position + Vector3(0.55, 0.5, 1.5)
	_camera.look_at(torch.get_node("ElementComponent").global_position, Vector3.UP)
	var offset: Vector3 = torch.get_node("ElementComponent").global_position - _sword.element.global_position
	_player.position += Vector3(offset.x, 0, offset.z)
	await _wait(0.5)
	var vine = _room.get_node("VineGate/Vines2")
	_stand(Vector3(13.35, 0.5, 0))
	_camera.look_at(vine.get_hit_center(), Vector3.UP)
	await _frames()
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(11.5)
	_check(_room.is_gate_open(), "physical torch and sword burn cleaning entrance")


func _check_coin_landings() -> void:
	# 固定随机种子覆盖多方向、低 / 高初速度，检查实际落地。
	var values := PackedInt32Array()
	values.resize(64)
	values.fill(1)
	var old_state: int = _hole._rng.state
	_hole._rng.seed = 29
	for speed in [3.5, 7.0]:
		_hole._spawn_coins(values, PackedFloat32Array([1]), speed, speed, 0.28)
		await _wait(4.0)
		var pool = root.get_node("CoinPool")
		var coins: Array = pool._active.duplicate()
		_check(coins.size() == 64 and coins.all(func(coin): return coin.is_grounded()), "64 deterministic coin directions physically land at speed " + str(speed))
		for coin in coins:
			pool.release(coin)
		await _frames()
	_hole._rng.state = old_state


func _run() -> void:
	await process_frame
	# 显式选择历史地图夹具；正式入口另由 run_main_world_* 验证。
	load("res://tests/helpers/legacy_world_fixture.gd").install(self, "res://tests/fixtures/three_room_world.tscn")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_capture_dir = argument.trim_prefix("--capture-dir=")
	_wallet = root.get_node("Wallet")
	_flow = root.get_node("GameFlow")
	_bus = root.get_node("EventBus")
	_flow.start_new_game()
	await scene_changed
	_bind()
	await _frames()
	_check(PRODUCT.is_supported() and PRODUCT.price == 5 and PRODUCT.purchase_limit == 1 and PRODUCT.upgrade_target == ShopItemData.UpgradeTarget.HOLE, "hole product is configured for five coins and one purchase")
	_check(PRODUCT.make_upgraded_sword(_sword.data) == null, "hole product cannot accidentally forge sword data")
	_check(not _outlet.is_enabled() and not _hole.has_upgrade("corpse_return") and _hole.can_apply_upgrade("corpse_return"), "wired outlet starts disabled and can be unlocked")
	var floor_hit := _floor_at(_outlet.global_position)
	_check(not floor_hit.is_empty() and floor_hit.collider.name == "MainFloor" and absf(floor_hit.position.y - _outlet.global_position.y) < 0.03, "small outlet sits on actual main floor outside pit")
	await _place_product(_stock)
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.8)
	_check(_wallet.total == 0 and not _shop.busy and _shop.counter.item != null and not _outlet.is_enabled(), "insufficient funds retain product without unlocking or debit")
	_shop.counter.item.return_home()
	await _frames()
	await _earn_income()
	await _check_coin_landings()
	await _open_gate()
	var rat_data: MonsterData = load("res://resources/enemies/monster_rat.tres")
	var roach_data: MonsterData = load("res://resources/enemies/monster_cockroach.tres")
	var leftover = _new_corpse(rat_data, Vector3(20, 0.4, 2))
	await _wait(0.3)
	_stand(Vector3(19, 0.5, 0))
	await _frames()
	_check(await _walk_x(12.5), "walking leaves cleaning room across whole corridor")
	_check(_leaves == 1 and _transfers.is_empty() and leftover.global_position.x > 18, "leaving before purchase never transfers corpse")

	var sword_data: SwordData = _sword.data
	var bought = await _place_product(_stock)
	await _capture("shop-products", _shop.to_global(Vector3(0, 3.8, 7)), _shop.to_global(Vector3(0, 1, 1)))
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.3)
	_check(_shop.busy and _wallet.total == 5 and not _outlet.is_enabled(), "keeper hit starts hole transaction without early debit or effect")
	_check(_sword.visible and _sword.interaction_locked and _sword.data == sword_data and not _shop.get_node("Booth/PreviewSword").visible, "hole purchase keeps original sword model and data")
	_check(_sword._state == 0 and not _sword._hitbox.monitoring, "starting hole transaction closes current damage window")
	_check(not _sword.try_swing() and _grabber.interaction_locked and bought.locked, "busy transaction blocks duplicate hits and product removal")
	_flow.pause_game()
	var curtain: Transform3D = _shop.get_node("Booth/Curtain").transform
	await _wait(1.0)
	_check(_shop.busy and _wallet.total == 5 and not _outlet.is_enabled() and curtain.is_equal_approx(_shop.get_node("Booth/Curtain").transform), "pause freezes transaction and effect")
	_flow.resume_game()
	await _wait(3.0)
	_check(_wallet.total == 0 and _hole.has_upgrade("corpse_return") and _outlet.is_enabled() and _shop.get_purchase_count(&"corpse_return") == 1, "delivery debits five exactly once and activates outlet")
	_check(not is_instance_valid(bought) and _stock.get_item() == null and _stock.sold_out and _stock.get_node("Sign").text.contains("已售罄"), "limited product consumed without restocking")
	_check(_sword.data == sword_data and _sword.visible and not _sword.interaction_locked and not _grabber.interaction_locked, "hole delivery restores interactions without replacing sword")
	_check(not _hole.apply_upgrade("corpse_return") and not _hole.apply_upgrade("unknown"), "duplicate and unsupported upgrades rejected")
	_check(_transfers.is_empty() and leftover.global_position.x > 18, "buying alone does not transfer earlier room leftovers")

	# 使用真实 WASD 穿越与两侧折返，不能直接调用离房回调。
	_stand(Vector3(12.5, 0.5, 0))
	await _frames()
	_check(await _walk_x(19) and _leaves == 1 and _cleaning_transfers().is_empty(), "entering cleaning room does not clean that room while main hall can clean")
	_check(await _walk_x(15.3) and await _walk_x(19) and _leaves == 1, "room side turnaround inside trigger does not count")
	var main_corpse = _new_corpse(roach_data, Vector3(0, 0.4, -14))
	var held = _new_corpse(roach_data, _camera.global_position - _camera.global_basis.z * 2.0)
	held.freeze = true
	_camera.rotation = Vector3.ZERO
	held.global_position = _camera.global_position - _camera.global_basis.z * 2.0
	await _frames()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_grabber.get_held() == held and not held.relocate_for_return(_outlet.global_transform), "held corpse cannot be relocated")
	var burning = _new_corpse(roach_data, Vector3(23, 0.4, 5))
	burning.value = 7
	burning.weight = 2.25
	burning.element.ignite()
	await _wait(1.0)
	var remaining: float = burning.element.burn_remaining
	var original_id: int = burning.get_instance_id()
	_check(await _walk_x(12.5), "carrying player physically crosses room exit")
	_check(_leaves == 2 and _cleaning_transfers().size() == 2, "one leave transfers exactly two unheld cleaning room corpses")
	_check(_transfers.any(func(entry): return entry.id == original_id and entry.room == &"cleaning" and entry.at.distance_to(_outlet.get_node("SpawnPoint").global_position) < 0.01), "same burning corpse reappears at small outlet")
	var direction: Vector3 = _hole.global_position - _outlet.get_node("SpawnPoint").global_position
	direction.y = 0.0
	_check(_transfers.all(func(entry): return entry.forward.dot(direction.normalized()) > 0.99), "outlet corpses face central hole when they appear")
	_check(burning.value == 7 and burning.weight == 2.25 and burning._pending_data == roach_data and burning.element.burning and burning.element.burn_remaining < remaining and burning.element.burn_remaining > 3.0, "transfer preserves type value weight and running burn timer")
	_check(_grabber.get_held() == held and is_equal_approx(_player.carry_weight, held.weight) and main_corpse.global_position.x < 5, "held corpse and main hall corpse remain untouched")
	main_corpse.queue_free() # 本段只验证清扫区；主厅两出口与商店由多房间专项覆盖。
	_check(_wallet.total == 0 and _outlet.moving_count() == 2 and not _hole.is_in_attraction_range(burning), "outlet starts movement outside actual attraction without direct income")
	# 暂停冻结移动与燃烧。其余用真实洞吸力、2 秒结算与落地金币接管。
	var before: Vector3 = burning.global_position
	var burn_before: float = burning.element.burn_remaining
	_stand(Vector3(-12, 0.5, -13))
	_camera.look_at(_outlet.get_node("SpawnPoint").global_position, Vector3.UP)
	await _capture("corpse-outlet")
	_flow.pause_game()
	before = burning.global_position
	burn_before = burning.element.burn_remaining
	await _wait(1.0)
	_check(before.is_equal_approx(burning.global_position) and is_equal_approx(burn_before, burning.element.burn_remaining), "pause freezes return physics and original burn countdown")
	_flow.resume_game()
	# 隔离燃烧销毁校验，普通尸体继续自动入洞；不把烧毁当献祭。
	var rewards: Array = []
	_bus.coins_erupted.connect(func(total, _count): rewards.append(total))
	var offered: Array = []
	_bus.corpse_offered.connect(func(corpse, value): offered.append({"id": corpse.get_instance_id(), "value": value}))
	await _wait(0.5)
	_check(is_instance_valid(leftover) and leftover.global_position.distance_to(_hole.global_position) < before.distance_to(_hole.global_position), "outlet moves corpse toward central hole")
	_camera.look_at(leftover.global_position, Vector3.UP)
	await _capture("returning-corpses")
	await _wait(18.0)
	_check(not is_instance_valid(leftover) and _outlet.moving_count() == 0 and offered.any(func(entry): return entry.value == 1), "ordinary corpse hands off to actual attraction and offering")
	_check(not is_instance_valid(burning), "burning corpse follows normal burning and offering lifecycle")
	_check(_wallet.total == 0 and not rewards.is_empty() and root.get_node("CoinPool").active_count() > 0, "automatic offering produces physical coins without crediting distant player")
	_check(await load("res://tests/helpers/coin_collection.gd").collect_all(self, _player), "walking collects automatic offering coins after ground contact")
	var reward_sum := 0
	for amount in rewards:
		reward_sum += amount
	_check(_wallet.total == reward_sum and reward_sum > 0, "wallet receives only actual eruption value after pickup")
	# 主厅侧折返、无新尸体再次离房都不会复制上次的回收。
	_grabber.drop()
	held.queue_free()
	await _frames()
	_stand(Vector3(12.5, 0.5, 0))
	await _frames()
	var leave_count := _leaves
	_check(await _walk_x(14.4) and await _walk_x(12.5) and _leaves == leave_count, "main side turnaround does not count as leaving")
	_check(await _walk_x(19) and await _walk_x(12.5) and _cleaning_transfers().size() == 2, "second cleaning exit without room corpses cannot repeat transfer")
	# 另一侧靠墙的通行也经过判定；回收中的尸体仍可被玩家截取。
	var next_corpse = _new_corpse(rat_data, Vector3(24, 0.4, 7))
	_stand(Vector3(19, 0.5, 1.8))
	await _frames()
	_check(await _walk_x(12.5) and _cleaning_transfers().size() == 3, "edge of corridor still detects leave and new corpse")
	var returning_id: int = next_corpse.get_instance_id()
	# 在出口点燃截取前的尸体，设置短倒计时验证烧毁不会变成献祭。
	var short_burn = _new_corpse(roach_data, Vector3(24, 0.4, 6))
	short_burn.element.burn_duration = 0.4
	short_burn.relocate_for_return(_outlet.get_node("SpawnPoint").global_transform)
	var short_id: int = short_burn.get_instance_id()
	short_burn.element.ignite()
	_stand(next_corpse.global_position + Vector3(0, 0.5, 1.5))
	_camera.look_at(next_corpse.global_position, Vector3.UP)
	await _frames()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_grabber.get_held() == next_corpse and _outlet.moving_count() == 0 and next_corpse.get_instance_id() == returning_id, "real grab interrupts automatic movement without cloning")
	await _wait(0.6)
	_check(not is_instance_valid(short_burn) and not offered.any(func(entry): return entry.id == short_id), "burnout at outlet never emits offering or creates value")
	# 复制出来的商品也必须遵守限购，失败时留在台面。
	_grabber.drop()
	next_corpse.queue_free()
	var duplicate = load("res://scenes/shop/shop_item.tscn").instantiate()
	duplicate.data = PRODUCT
	_room.add_child(duplicate)
	_shop.counter.place_item(duplicate)
	_stand(_shop.to_global(Vector3(0, 0.5, -0.4)))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	await _wait(0.8)
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.8)
	_check(not _shop.busy and _wallet.total == reward_sum and _shop.counter.item == duplicate and _shop.get_purchase_count(&"corpse_return") == 1, "duplicate product cannot debit or activate twice")
	# 直接重载不读取手动存档，重置商品 / 升级 / 移动引用。
	reload_current_scene()
	await scene_changed
	_bind()
	await _frames()
	_check(_wallet.total == reward_sum and not _outlet.is_enabled() and not _hole.has_upgrade("corpse_return") and _stock.get_item() != null and _shop.get_purchase_count(&"corpse_return") == 0, "reload preserves money and resets world upgrade and shelf stock")
	_wallet.set_total(5) # 以下仅作取消交易边界测试，主流程资金全来自实际献祭。
	await _place_product(_stock)
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.3)
	_check(_shop.busy, "cancellation fixture starts actual hole purchase")
	_hole.queue_free()
	await _wait(3.0)
	_check(_wallet.total == 5 and not _shop.busy and _shop.counter.item != null and not _outlet.is_enabled() and not _grabber.interaction_locked and _sword.visible, "target removed during animation cancels without debit or lost product")
	reload_current_scene()
	await scene_changed
	_bind()
	await _frames()
	await _place_product(_stock)
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.3)
	reload_current_scene()
	await scene_changed
	_bind()
	await _wait(3.0)
	_check(_wallet.total == 5 and not _outlet.is_enabled() and not _shop.busy and not _grabber.interaction_locked, "mid animation reload prevents delayed debit and activation")
	_flow.return_to_main_menu()
	await scene_changed
	await _frames()
	_check(root.get_node("CoinPool").active_count() == 0 and not paused, "scene exit clears coin pool and pause")
	print("CORPSE RETURN REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
