extends SceneTree

## 真实输入 / 物理 / 商品 / 动画 / 结算回归，位置布置仅用于稳定重现。
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


func _initialize() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func():
		push_error("SHOP REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("SHOP REGRESSION FAILED: " + message)


func _frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(int(ceil(seconds * Engine.physics_ticks_per_second)) + 1)


func _mouse(button: MouseButton) -> void:
	# Headless DisplayServer 不支持鼠标捕获；桌面输入另由 Godot AI 实测。
	if button == MOUSE_BUTTON_RIGHT and DisplayServer.get_name() == "headless":
		if _grabber.is_holding():
			_grabber.drop()
		else:
			_grabber.try_grab()
		await _frames()
		return
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames()


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames()


func _bind_room() -> void:
	_room = current_scene
	_player = _room.get_node("Player")
	_player.set_physics_process(false)
	_camera = _player.get_node("Camera3D")
	_sword = _camera.get_node("WeaponRig/WeaponPivot/Mount")
	_grabber = _camera.get_node("Grabber")
	_shop = _room.get_node("ShopRoom")


func _at_shelf() -> void:
	_player.global_position = _shop.shelf.global_position + Vector3(0, 0.5, 2)
	_camera.look_at(_shop.shelf.get_item().global_position, Vector3.UP)
	_player.reset_physics_interpolation()
	await _frames()


func _at_counter() -> void:
	_player.global_position = _shop.global_position + Vector3(0, 0.5, -0.4)
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	_player.reset_physics_interpolation()
	await _frames()


func _run() -> void:
	await process_frame
	_wallet = root.get_node("Wallet")
	_flow = root.get_node("GameFlow")
	_wallet.set_total(0)
	change_scene_to_file("res://scenes/rooms/element_test_room.tscn")
	await scene_changed
	_bind_room()
	await _frames()
	_check(_flow.is_in_game(), "main room participates in pause lifecycle")
	_check(not _room.has_node("OilStation") and not _sword.oiled, "main room has no free oil")
	_check(not _room.is_gate_open(), "main route starts blocked")
	_check(not _room.get_node("RatSpawner").enabled, "back spawner starts disabled")
	_check(_shop.shelf.item_data.price == 5, "oil price is five")
	var starter = _room.get_node("StarterCleaningRoom/RatSpawner")
	_check(starter.enabled and starter.max_alive == 3 and starter.spawn_interval == 3.0, "starter spawns before fire upgrade")
	# 连通口物理可通过，普通墙体仍挡路。
	_player.position = Vector3(4.8, 0.5, 3)
	_check(not _player.test_move(_player.global_transform, Vector3(3, 0, 0)), "east shop doorway physically passable")
	_player.position = Vector3(-4.8, 0.5, 3)
	_check(not _player.test_move(_player.global_transform, Vector3(-3, 0, 0)), "west starter doorway physically passable")
	_player.position = Vector3(4.8, 0.5, 7)
	_check(_player.test_move(_player.global_transform, Vector3(3, 0, 0)), "outer wall still blocks away from entrance")

	await _test_items()
	await _test_starter_income(starter)
	await _test_purchase()
	await _test_cancel()
	paused = false
	Engine.time_scale = 1.0
	print("SHOP REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_items() -> void:
	await _at_shelf()
	var item = _shop.shelf.get_item()
	_check(not item.get_node("Price").visible and _shop.shelf.get_node("Sign").text.contains("5"), "shelf has one clear price label")
	var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
	_room.add_child(corpse)
	corpse.freeze = true
	corpse.global_position = _camera.global_position - _camera.global_basis.z * 1.2
	await _frames()
	_check(_grabber.try_grab() and _grabber.get_held() == corpse, "corpse can share carrier in shop")
	_check(not _grabber.try_grab() and not item.is_held, "held corpse prevents grabbing oil")
	_grabber.drop()
	corpse.queue_free()
	await _frames()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_grabber.get_held() == item and item.is_held, "right click grabs shelf oil")
	_check(is_equal_approx(_player.carry_weight, item.data.weight), "oil uses same carrying weight interface")
	_check(not _grabber.try_grab(), "held oil prevents grabbing another object")
	await _frames(10)
	_check(item.is_held, "right release retains held oil")
	# 普通地面放下，不在台前就不会付款或吸附。
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(not _grabber.is_holding() and _shop.counter.item == null and _wallet.total == 0, "right click toggles floor drop")
	item.return_home()
	await _at_shelf()
	await _mouse(MOUSE_BUTTON_RIGHT)
	await _at_counter()
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 0.2)
	shape.shape = box
	wall.add_child(shape)
	_shop.add_child(wall)
	wall.global_position = (_camera.global_position + _shop.counter.get_node("Socket").global_position) * 0.5
	await _frames()
	_check(not _shop.counter.can_place_from(_camera), "world wall prevents placing product through wall")
	wall.queue_free()
	await _frames()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_shop.counter.item == item and item.freeze and not item.is_held, "right click at counter docks product")
	_check(not _grabber.is_holding() and is_zero_approx(_player.carry_weight), "docking clears held reference and weight")
	_check(item.global_position.is_equal_approx(_shop.counter.get_node("Socket").global_position), "product snaps to table socket")
	_check(not _shop.counter.can_place_from(_camera), "occupied counter cannot accept another")
	await _wait(4.0)
	_check(_shop.counter.item == item, "counter product has no timeout")
	_camera.look_at(item.global_position, Vector3.UP)
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(_grabber.get_held() == item and _shop.counter.item == null, "table oil can be taken back")
	var alternate = load("res://scenes/shop/shop_item.tscn").instantiate()
	_shop.add_child(alternate)
	await _at_counter()
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(not _shop.counter.place_item(alternate) and _shop.counter.item == item, "second physical product cannot replace occupied slot")
	alternate.queue_free()
	var original_product = item.data
	item.data = original_product.duplicate()
	item.data.upgrade_tag = "unsupported"
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.8)
	_check(not _shop.busy and _wallet.total == 0 and _shop.counter.item == item, "unsupported upgrade is rejected without charge or loss")
	_check(_shop.get_status_message().contains("无法用于强化"), "unsupported product gives feedback")
	item.data = original_product
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.8)
	_check(_wallet.total == 0 and not _sword.oiled and not _shop.busy, "insufficient funds do not charge or upgrade")
	_check(_shop.counter.item == item and is_instance_valid(_shop.get_node("Shopkeeper")), "insufficient funds retain item and living shopkeeper")
	_check(_shop.get_status_message().contains("金钱不足"), "insufficient feedback appears")
	await _wait(3.2)
	_check(_shop.get_status_message().is_empty(), "feedback expires after about three seconds")
	_camera.look_at(item.global_position, Vector3.UP)
	await _mouse(MOUSE_BUTTON_RIGHT)
	_player.position = Vector3(0, 0.5, 2.2)
	item.global_position = Vector3(0.1, -0.2, 0.1)
	await _frames()
	_check(not _grabber.is_holding() and is_zero_approx(_player.carry_weight), "goods falling in hole return and clear carrier")
	_check(item.freeze and item.global_position.is_equal_approx(_shop.shelf.get_node("ItemSpawn").global_position), "fallen goods return to shelf")
	_check(_room.get_node("Hole").pending_value == 0 and _wallet.total == 0, "oil is never a corpse offering")


func _test_starter_income(starter) -> void:
	await _wait(3.2)
	_check(starter.get_alive_count() > 0, "initial rat spawns without opening gate")
	# 每个真实刷新点老鼠由实际剑横扫击杀，再从准星拿尸体献祭。
	for cycle in range(3):
		var rat
		for child in starter.get_children():
			if child.has_method("take_hit"):
				rat = child
				break
		_check(rat != null, "starter rat available for income cycle")
		if rat == null:
			return
		rat.set_physics_process(false)
		_player.global_position = Vector3(-12, 0.5, 3)
		_camera.rotation = Vector3(deg_to_rad(-45), 0, 0)
		rat.global_position = _camera.global_transform * Vector3(0, -0.34, -1.4)
		var corpses: Array = []
		root.get_node("EventBus").corpse_spawned.connect(func(corpse): corpses.append(corpse), CONNECT_ONE_SHOT)
		await _frames()
		await _mouse(MOUSE_BUTTON_LEFT)
		await _wait(0.8)
		_check(not is_instance_valid(rat) and not corpses.is_empty(), "real sword kills starter rat and spawns corpse")
		if corpses.is_empty():
			return
		var corpse = corpses[0]
		corpse.freeze = true
		corpse.global_position = _camera.global_position - _camera.global_basis.z * 2.0
		await _frames()
		await _mouse(MOUSE_BUTTON_RIGHT)
		_check(_grabber.get_held() == corpse, "real right click grabs starter corpse")
		_player.position = Vector3(0, 0.5, 2.2)
		corpse.global_position = Vector3(0.1, 1.8, 0.1)
		await _frames()
		_check(not is_instance_valid(corpse) and not _grabber.is_holding(), "held corpse at hole height 1.8 remains offered")
		await _wait(4.0)
		_check(_wallet.total == (cycle + 1) * 2, "starter corpse yields unchanged two coins")
	_check(_wallet.total == 6 and not _room.is_flow_complete(), "zero gold can earn oil price without prematurely completing back route")


func _test_purchase() -> void:
	await _at_counter()
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.8)
	_check(not _shop.busy and _wallet.total == 6 and _shop.get_status_message().contains("没有商品"), "empty table hit gives feedback without payment")
	await _at_shelf()
	await _mouse(MOUSE_BUTTON_RIGHT)
	await _at_counter()
	await _mouse(MOUSE_BUTTON_RIGHT)
	var original_data = _sword.data
	var bought_item = _shop.counter.item
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.3)
	_check(_shop.busy and not _sword.visible and _sword.interaction_locked, "real shopkeeper hit starts animation and hides hand sword")
	_check(_shop.counter.locked and bought_item.locked and _grabber.interaction_locked, "busy transaction locks counter and grabbing")
	_check(_wallet.total == 6 and not _sword.oiled, "no debit before delivery")
	_check(not _sword.try_swing() and not bought_item.can_be_grabbed(), "busy repeat attack and grab rejected")
	# Esc 暂停时帘幕、商品、钱包全部保持，再按 Esc 恢复。
	await _key(KEY_ESCAPE)
	_check(paused, "Esc opens pause during forge")
	var curtain_transform: Transform3D = _shop.get_node("Booth/Curtain").transform
	await _wait(1.0)
	_check(curtain_transform.is_equal_approx(_shop.get_node("Booth/Curtain").transform), "pause freezes curtain tween")
	_check(_wallet.total == 6 and _shop.busy, "pause cannot finish or debit transaction")
	await _key(KEY_ESCAPE)
	_check(not paused, "Esc resumes forge")
	for i in range(120):
		await _frames(1)
		if _shop.get_node("Booth/Curtain").scale.y >= 0.99 and not _shop.get_node("Booth/PreviewSword").visible:
			break
	_check(_shop.get_node("Booth/Curtain").scale.y >= 0.99 and not _shop.get_node("Booth/PreviewSword").visible, "curtain closes over replacement sword before delivery")
	await _wait(2.0)
	_check(_wallet.total == 1 and _shop.completed_purchases == 1, "delivery spends exactly five once")
	_check(_sword.oiled and not _sword.is_burning() and _sword.data.upgrade_tags.has("oil"), "new sword data grants oil without auto ignition")
	_check(_sword.data != original_data and not original_data.upgrade_tags.has("oil"), "upgrade copies data and leaves shared base resource unchanged")
	_check(is_equal_approx(_sword.data.damage, original_data.damage) and _sword.data.view_offset == original_data.view_offset, "oil preserves combat and view configuration")
	_check(not is_instance_valid(bought_item) and _shop.counter.item == null, "successful purchase consumes counter item")
	_check(is_instance_valid(_shop.shelf.get_item()) and _shop.shelf.get_item().freeze, "successful purchase restocks shelf")
	_check(_sword.visible and not _sword.interaction_locked and not _grabber.interaction_locked and not _shop.busy, "delivery restores normal interactions")
	_check(not _shop.get_node("Booth/PreviewSword").visible, "display sword removed after handoff")
	await _at_shelf()
	await _mouse(MOUSE_BUTTON_RIGHT)
	await _at_counter()
	await _mouse(MOUSE_BUTTON_RIGHT)
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.8)
	_check(_wallet.total == 1 and _shop.completed_purchases == 1 and _shop.counter.item != null, "already oiled rejects duplicate purchase and retains product")
	_check(_shop.get_status_message().contains("无需重复"), "duplicate upgrade gives feedback")

	# 购买后的真实剑仍能接触火把、烧开整扇藤蔓门。
	var torch = _room.get_node("Torch")
	_player.position = torch.position + Vector3(0.55, 0.5, 1.5)
	_camera.look_at(torch.get_node("ElementComponent").global_position, Vector3.UP)
	var delta: Vector3 = torch.get_node("ElementComponent").global_position - _sword.element.global_position
	_player.position += Vector3(delta.x, 0, delta.z)
	await _wait(0.5)
	_check(_sword.is_burning() and _sword.fire_swings_remaining == 5, "purchased oil enables actual torch ignition")
	var vine = _room.get_node("VineGate/Vines1")
	_player.position = Vector3(-1.2, 0.5, -4.2)
	_camera.look_at(vine.get_hit_center(), Vector3.UP)
	await _frames()
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.6)
	_check(vine.element.burning, "purchased burning sword ignites actual gate")
	await _wait(4.8)
	_check(_room.is_gate_open() and _room.get_node("RatSpawner").enabled, "purchased oil unlocks original back route")
	await _key(KEY_R)
	_bind_room()
	await _frames()
	_check(_wallet.total == 1 and not _sword.oiled and not _room.is_gate_open(), "reload preserves only gold and resets oil and world")
	_check(not _shop.busy and _sword.visible and not _grabber.interaction_locked, "reload clears all forge references and locks")


func _test_cancel() -> void:
	# 交付前余额变化也不能透支、消费商品或升级。
	_wallet.set_total(10)
	await _at_shelf()
	await _mouse(MOUSE_BUTTON_RIGHT)
	await _at_counter()
	await _mouse(MOUSE_BUTTON_RIGHT)
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.2)
	_wallet.set_total(0)
	await _wait(3.0)
	_check(_wallet.total == 0 and not _sword.oiled and _shop.counter.item != null, "changed balance at delivery retains product and rejects upgrade")
	_check(not _shop.busy and _sword.visible and not _grabber.interaction_locked, "failed delivery unlocks interaction")
	_wallet.set_total(10)
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.2)
	_check(_shop.busy, "cancellation fixture starts real transaction")
	await _key(KEY_R)
	_bind_room()
	await _frames()
	_check(_wallet.total == 10 and not _shop.busy and not _sword.oiled, "mid animation reload leaves money intact and no delayed delivery")
	await _wait(3.0)
	_check(_wallet.total == 10 and not _sword.oiled, "cancelled tween cannot deliver to new scene")
	await _at_shelf()
	await _mouse(MOUSE_BUTTON_RIGHT)
	await _at_counter()
	await _mouse(MOUSE_BUTTON_RIGHT)
	await _mouse(MOUSE_BUTTON_LEFT)
	await _wait(0.2)
	_check(_shop.busy, "return menu fixture starts transaction")
	_flow.return_to_main_menu()
	await scene_changed
	await _frames()
	_check(current_scene.scene_file_path == _flow.MAIN_MENU and _wallet.total == 10, "return to menu cancels without debit")
	await _wait(3.0)
	_check(_wallet.total == 10 and root.get_node("CoinPool").active_count() == 0, "menu has no pending transaction or stale coins")
