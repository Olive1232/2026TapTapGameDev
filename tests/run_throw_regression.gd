extends SceneTree

## 正式商店交易与真实刚体投掷。金币赋值仅用于交易边界夹具。
const PRODUCT := preload("res://resources/shop/shop_item_charged_throw.tres")
const CORPSE := "res://scenes/enemies/corpse.tscn"
var _passed := 0
var _failed := 0
var _room
var _player
var _camera
var _grabber
var _sword
var _shop
var _wallet
var _flow
var _capture_dir := ""


func _initialize() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func():
		push_error("THROW REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("THROW REGRESSION FAILED: " + message)


func _frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(int(ceil(seconds * Engine.physics_ticks_per_second)) + 1)


func _load_scene(path: String) -> void:
	Engine.time_scale = 1.0
	change_scene_to_file(path)
	await scene_changed
	_room = current_scene
	_player = _room.get_node("Player")
	_camera = _player.get_node("Camera3D")
	_grabber = _camera.get_node("Grabber")
	_sword = _camera.get_node("WeaponRig/WeaponPivot/Mount")
	_shop = _room.get_node_or_null("ShopRoom")
	_player.set_physics_process(false)
	_player.rotation = Vector3.ZERO
	await _frames()


func _stand(at: Vector3) -> void:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 2.0, 1)
	var hit: Dictionary = _room.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		at.y = hit.position.y + 0.5 + _player.safe_margin
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


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


func _hold_new(value: int = 7, weight: float = 1.5):
	if _grabber.is_holding():
		_grabber.drop()
	var corpse = load(CORPSE).instantiate()
	corpse.value = value
	corpse.weight = weight
	corpse.freeze = true
	_room.add_child(corpse)
	corpse.global_position = _camera.global_position - _camera.global_basis.z * 1.6
	await _frames()
	await _click_right()
	_check(_grabber.get_held() == corpse and corpse.is_held, "right click grabs one actual corpse")
	corpse.freeze = false
	await _wait(0.35)
	return corpse


func _place_product():
	var stock = _shop.get_node("ChargedThrowShelf")
	var item = stock.get_item()
	_stand(_shop.to_global(stock.position + Vector3(0, 0.5, 1.2)))
	_camera.look_at(item.global_position, Vector3.UP)
	await _frames()
	await _click_right()
	_check(_grabber.get_held() == item, "real third shelf ray grabs throw product")
	_stand(_shop.to_global(Vector3(0, 0.5, -0.4)))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	await _frames()
	await _click_right()
	_check(_shop.counter.item == item and not _grabber.is_holding(), "throw product docks on original counter")
	return item


func _capture(name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames()
	RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(_capture_dir.path_join(name + ".png"))


func _run() -> void:
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			_capture_dir = arg.trim_prefix("--capture-dir=")
	_wallet = root.get_node("Wallet")
	_flow = root.get_node("GameFlow")
	await _test_shop()
	await _test_cancel_purchase()
	await _test_input_and_lifecycle()
	await _test_physics()
	paused = false
	Engine.time_scale = 1.0
	print("THROW REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_shop() -> void:
	_wallet.set_total(199)
	await _load_scene("res://scenes/rooms/map_world.tscn")
	_check(PRODUCT.is_supported() and PRODUCT.price == 200 and PRODUCT.purchase_limit == 1, "throw product costs 200 and is limited to one")
	_check(PRODUCT.upgrade_target == ShopItemData.UpgradeTarget.GRABBER, "throw upgrades grabber independently of sword and hole")
	_check(not _grabber.charged_throw_enabled, "new world starts with throw locked")
	_check(_shop.shelf.get_item() != null and _shop.get_node("CorpseReturnShelf").get_item() != null, "three independent shelves coexist")
	_stand(Vector3(6, 0.5, -14))
	_camera.rotation = Vector3.ZERO
	var legacy = await _hold_new()
	_right(true)
	_check(not legacy.is_held and not _grabber.is_holding(), "without upgrade right press still drops immediately")
	await _wait(0.7)
	_right(false)
	_check(not _grabber._trajectory.visible and not _grabber.is_holding(), "unowned long press neither previews nor regrabs on release")
	legacy.queue_free()
	var product = await _place_product()
	await _strike()
	_check(not _shop.busy and _wallet.total == 199 and not _grabber.charged_throw_enabled, "199 coins rejects 200 coin purchase")
	_check(_shop.counter.item == product and _shop.get_status_message().contains("金钱不足"), "insufficient balance retains product with feedback")
	_wallet.set_total(200)
	# 剑状态夹具：验证购买搬运能力不会覆盖涂油剑或熄灭火焰。
	var oil: ShopItemData = load("res://resources/shop/shop_item_oil.tres")
	_sword.set_sword_data(oil.make_upgraded_sword(_sword.data))
	_sword.element.ignite()
	var sword_data = _sword.data
	var fire_swings = _sword.fire_swings_remaining
	await _wait(0.8)
	await _strike()
	_check(_shop.busy and _grabber.interaction_locked, "actual keeper hit starts locked throw transaction")
	_check(_wallet.total == 200 and not _grabber.charged_throw_enabled, "animation has not charged or granted early")
	_check(_sword.get_node("Pivot").visible and _sword.data == sword_data and _sword.is_burning(), "throw transaction retains current sword model data and flame")
	_flow.pause_game()
	await create_timer(0.4, true, false, true).timeout
	_check(paused and _shop.busy and _wallet.total == 200, "pause freezes throw purchase animation")
	_flow.resume_game()
	await _wait(3.0)
	_check(_wallet.total == 0 and _grabber.has_upgrade("charged_throw"), "delivery charges 200 once and unlocks throw")
	_check(_shop.get_purchase_count(PRODUCT.id) == 1 and _shop.completed_purchases == 1, "one completion records one purchase")
	_check(_shop.get_node("ChargedThrowShelf").sold_out and _shop.get_node("ChargedThrowShelf").get_item() == null, "single purchase shelf sells out without restocking")
	_check(_sword.data == sword_data and _sword.is_burning() and _sword.fire_swings_remaining == fire_swings - 1, "sword state remains intact after non-sword delivery")
	_check(not _shop.busy and not _grabber.interaction_locked, "delivery releases transaction locks")
	await _strike()
	_check(_wallet.total == 0 and _shop.completed_purchases == 1, "repeat keeper strike never duplicates charge")
	_check(not _grabber.apply_upgrade("charged_throw"), "ability cannot be granted twice")
	# 购买后商品仍在按下时正常放置，不进入尸体蓄力。
	var stock = _shop.get_node("CorpseReturnShelf")
	_stand(_shop.to_global(stock.position + Vector3(0, 0.5, 1.2)))
	_camera.look_at(stock.get_item().global_position, Vector3.UP)
	await _frames()
	await _click_right()
	_check(_grabber.get_held() == stock.get_item(), "unlocked throw still grabs ordinary shop goods")
	_stand(_shop.to_global(Vector3(0, 0.5, -0.4)))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	await _frames()
	_right(true)
	_check(_shop.counter.item == stock.get_item() and not _grabber._throw_pressed, "goods dock on press with no throw charge")
	_right(false)
	_check(not _grabber.is_holding(), "product release does not pick it back up")
	if not _capture_dir.is_empty():
		_stand(_shop.to_global(Vector3(0, 0.5, 8.5)))
		_camera.look_at(_shop.to_global(Vector3(0, 1.4, 3.4)), Vector3.UP)
		await _capture("throw-shop")


func _test_cancel_purchase() -> void:
	_wallet.set_total(200)
	await _load_scene("res://scenes/rooms/map_world.tscn")
	_check(not _grabber.charged_throw_enabled, "scene reload resets current-world throw upgrade")
	var item = await _place_product()
	await _strike()
	_check(_shop.busy, "cancel fixture starts actual transaction")
	var data = item.data
	item.data = data.duplicate()
	item.data.upgrade_tag = "unsupported"
	await _wait(3.0)
	_check(_wallet.total == 200 and not _grabber.charged_throw_enabled, "delivery revalidates effect and cancels invalid product without charge")
	_check(_shop.counter.item == item and not _grabber.interaction_locked, "cancelled delivery retains product and unlocks carrier")
	item.data = data
	await _strike()
	await _wait(0.3)
	_check(_shop.busy and _wallet.total == 200, "new animation defers charge")
	await _load_scene("res://scenes/rooms/map_world.tscn")
	await _wait(3.0)
	_check(_wallet.total == 200 and not _grabber.charged_throw_enabled, "reload during animation cancels late grant and payment")
	_check(_shop.get_node("ChargedThrowShelf").get_item() != null and not _grabber.interaction_locked, "new world restores stock without stale locks")


func _test_input_and_lifecycle() -> void:
	await _load_scene("res://scenes/debug/throw_lab.tscn")
	_check(_flow.is_in_game(), "throw lab supports normal pause lifecycle")
	_check(not _grabber.charged_throw_enabled and _wallet.total == 200, "test room neither grants automatically nor changes wallet")
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_E
		event.physical_keycode = KEY_E
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames()
	_check(_grabber.charged_throw_enabled, "debug E unlock uses actual input only in lab")
	_stand(Vector3(8, 0.5, 7))
	_camera.rotation = Vector3.ZERO
	var corpse = await _hold_new()
	_check(is_equal_approx(_player.carry_weight, 1.5), "held corpse supplies original carry weight")
	_right(true)
	await _wait(0.08)
	_check(not _grabber._trajectory.visible, "short click never shows arc")
	_right(false)
	_check(not corpse.is_held and not _grabber.is_holding() and is_zero_approx(_player.carry_weight), "quick release drops normally and clears weight")
	_check(corpse.linear_velocity.length() < 2.0, "short release keeps ordinary drop strength")
	corpse.queue_free()
	corpse = await _hold_new()
	_right(true)
	await _wait(0.5)
	_check(_grabber.is_charging_throw() and _grabber._trajectory.visible, "held right input reaches charge threshold and shows arc")
	_check(_grabber.get_throw_prompt().contains("蓄力") and _grabber.get_throw_charge() > 0.0, "HUD reports current charge")
	var charge: float = _grabber.get_throw_charge()
	_right(true)
	_check(is_equal_approx(charge, _grabber.get_throw_charge()), "duplicate press does not reset charge")
	corpse.element.ignite()
	var remaining: float = corpse.element.burn_remaining
	_flow.pause_game()
	await create_timer(0.3, true, false, true).timeout
	_check(not _grabber._throw_pressed and not _grabber._trajectory.visible, "pause cancels active charge and hides trajectory")
	_check(corpse.is_held and is_equal_approx(corpse.element.burn_remaining, remaining), "pause retains held burning corpse and freezes its timer")
	_flow.resume_game()
	_right(false)
	_check(_grabber.get_held() == corpse, "release after resume neither launches nor drops cancelled charge")
	_right(true)
	await _wait(0.5)
	_grabber.interaction_locked = true
	_check(not _grabber._throw_pressed and not _grabber._trajectory.visible, "transaction lock cancels charge")
	_right(false)
	_check(corpse.is_held, "locked release cannot throw held corpse")
	_grabber.interaction_locked = false
	_right(true)
	await _wait(0.5)
	_grabber.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_right(false)
	_check(corpse.is_held and not _grabber._trajectory.visible, "focus loss cancels charge without an accidental throw")
	_right(true)
	await _wait(1.8)
	_check(is_equal_approx(_grabber.get_throw_charge(), 1.0), "long hold caps charge at 100 percent")
	var velocity: Vector3 = _grabber.get_throw_velocity()
	var before: float = corpse.element.burn_remaining
	var id: int = corpse.get_instance_id()
	_right(false)
	_check(corpse.get_instance_id() == id and corpse.value == 7 and corpse.weight == 1.5, "launch reuses identical corpse with value and weight intact")
	_check(corpse.element.burning and is_equal_approx(corpse.element.burn_remaining, before), "launch preserves fire state and remaining duration")
	_check(corpse.linear_velocity.distance_to(velocity) < 0.01 and velocity.length() <= _grabber.throw_max_speed + 0.01, "release applies previewed velocity with capped strength")
	_check(not corpse.is_held and corpse.gravity_scale == 1.0 and corpse.continuous_cd, "launch restores rigid body gravity with continuous collision")
	_check(not _grabber.is_holding() and is_zero_approx(_player.carry_weight) and not _grabber._trajectory.visible, "launch clears hold weight and preview")
	corpse.queue_free()
	corpse = await _hold_new()
	corpse.element.ignite()
	corpse.element.burn_remaining = 0.08
	_right(true)
	await _wait(0.4)
	_check(not is_instance_valid(corpse) and not _grabber.is_holding() and is_zero_approx(_player.carry_weight), "burnout during charge removes corpse and stale weight")
	_check(not _grabber._throw_pressed and not _grabber._trajectory.visible, "burnout cancels pending input and arc")
	_right(false)
	corpse = await _hold_new()
	_check(_grabber.get_held() == corpse and not _grabber._throw_pressed, "carrier works again after burnout")
	corpse.queue_free()
	await _frames()


func _charge_full() -> void:
	_right(true)
	await _wait(_grabber.throw_hold_threshold + _grabber.throw_charge_duration + 0.1)


func _test_physics() -> void:
	# 高处：实际轨迹应落到平台顶部，而不是穿透平台。
	_stand(Vector3(0, 0.5, 4.2))
	_camera.rotation = Vector3(deg_to_rad(35), 0, 0)
	var corpse = await _hold_new()
	_right(true)
	await _wait(0.4)
	var predicted: Vector3 = _grabber._trajectory.points[-1]
	_check(_grabber._trajectory.collided and predicted.y > 2.5 and absf(predicted.x) < 2.1, "arc predicts elevated platform contact")
	await _capture("high-platform-arc")
	predicted = _grabber._trajectory.points[-1]
	var path: PackedVector3Array = _grabber._trajectory.points.duplicate()
	var contacts: Array = []
	corpse.contact_monitor = true
	corpse.max_contacts_reported = 4
	corpse.body_entered.connect(func(body): contacts.append({"body": body, "at": corpse.global_position}))
	_right(false)
	await _frames(18)
	var nearest := INF
	for point in path:
		nearest = minf(nearest, point.distance_to(corpse.global_position))
	_check(nearest < 0.25, "real rigid body flight follows preview within quarter meter")
	await _wait(2.0)
	_check(corpse.global_position.y > 2.5 and corpse.global_position.y < 2.8 and corpse.linear_velocity.length() < 0.3, "thrown corpse actually rests on high platform")
	_check(not contacts.is_empty() and contacts[0].body == _room.get_node("HighPlatform") and contacts[0].at.distance_to(predicted) < 0.5, "actual first platform contact matches preview")
	await _capture("high-platform-landed")
	corpse.queue_free()

	# 水平远抛，地面截断轨迹，实际落点保持永久普通尸体。
	_stand(Vector3(10, 0.5, 7))
	_camera.rotation = Vector3.ZERO
	corpse = await _hold_new()
	await _charge_full()
	predicted = _grabber._trajectory.points[-1]
	_check(_grabber._trajectory.collided and predicted.y < 0.2, "arc stops at real ground using corpse shape")
	var start: Vector3 = corpse.global_position
	var floor_contacts: Array = []
	corpse.contact_monitor = true
	corpse.max_contacts_reported = 4
	corpse.body_entered.connect(func(body): floor_contacts.append({"body": body, "at": corpse.global_position}))
	_player.velocity = Vector3(2, 0, 0)
	_check(is_equal_approx(_grabber.get_throw_velocity().x, 1.0), "prediction includes half of carrier horizontal velocity")
	_player.velocity = Vector3.ZERO
	_right(false)
	await _wait(2.0)
	_check(corpse.global_position.distance_to(start) > 6.0 and corpse.global_position.y > 0.0, "charged corpse flies farther than drop and remains above floor")
	_check(not floor_contacts.is_empty() and floor_contacts[0].body == _room.get_node("Floor") and floor_contacts[0].at.distance_to(predicted) < 0.5, "actual first ground contact agrees with trajectory before sliding")
	corpse.queue_free()

	# 中间墙：预览与实体均不能穿越。
	_stand(Vector3(-5.7, 0.5, 5))
	_camera.rotation = Vector3(deg_to_rad(4), 0, 0)
	corpse = await _hold_new()
	await _charge_full()
	predicted = _grabber._trajectory.points[-1]
	_check(_grabber._trajectory.collided and predicted.z > -3.7 and predicted.y > 0.3, "arc truncates at blocking wall before ground")
	_right(false)
	await _wait(1.0)
	_check(corpse.global_position.z > -3.8, "continuous collision prevents high speed throw through wall")
	corpse.queue_free()

	# 使用场景火把接触点燃手持尸体，再真正投到远端目标传火。
	_stand(Vector3(-2.7, 0.5, 7.2))
	_camera.rotation = Vector3.ZERO
	corpse = await _hold_new()
	await _wait(0.5)
	_check(corpse.element.burning, "actual torch contact ignites held corpse")
	_stand(Vector3(4.3, 0.5, 5))
	_camera.rotation = Vector3(deg_to_rad(4), 0, 0)
	await _wait(0.5)
	await _charge_full()
	var target = _room.get_node("RemoteTarget")
	var target_element = target.get_node("ElementComponent")
	_check(not target_element.burning, "distant target stays unlit before throw")
	predicted = _grabber._trajectory.points[-1]
	_check(_grabber._trajectory.collided and absf(predicted.x - 5.0) < 0.8 and predicted.z > -3.8 and predicted.z < -3.3, "preview terminates at remote flammable target")
	await _capture("burning-corpse-arc")
	var before: float = corpse.element.burn_remaining
	_right(false)
	_check(corpse.element.burn_remaining == before, "throw does not restart corpse burn timer")
	await _wait(0.9)
	_check(target_element.burning, "actual burning projectile ignites remote target on contact")
	_check(corpse.value == 7 and corpse.element.burn_remaining < before, "projectile continues original value and burn countdown")
	await _capture("remote-target-burning")
	await _wait(10.5)
	_check(not is_instance_valid(target) and not is_instance_valid(corpse), "target and corpse disappear after their own burn timers")
	_check(not _grabber._trajectory.visible and is_zero_approx(_player.carry_weight), "completed flight leaves no stale preview or carry state")
