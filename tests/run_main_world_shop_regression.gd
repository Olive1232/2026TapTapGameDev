extends SceneTree

## 在用户已摆放的商店上，用真实抓取、台面吸附和剑命中验证结算。
## 只调整测试玩家站位；所有商店模型的变换必须保持。
const PLACED_NODES := ["MapScale", "Hole", "Torch", "FlammableVines", "RatSpawner", "Shopkeeper", "Booth", "Counter", "Shelf", "CorpseValueShelf", "GoldenCoinShelf", "MirrorShelf", "CorpseReturnShelf", "ChargedThrowShelf"]
var _passed := 0
var _failed := 0
var _world
var _shop
var _player
var _camera
var _sword
var _grabber
var _wallet
var _flow
var _placements := {}


func _initialize() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func():
		push_error("MAIN WORLD SHOP TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("MAIN WORLD SHOP FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _bind() -> void:
	_world = current_scene
	# 首次剧情与点击拦截由 run_dialogue_regression 覆盖，本专项专注真实交易。
	_world.get_node("WorldDialogue").restore_progress({"shop_visited": true, "hole_introduced": true})
	_shop = _world.get_node("ShopController")
	_player = _world.get_node("Player")
	_player.set_physics_process(false)
	_camera = _player.get_node("Camera3D")
	_sword = _camera.get_node("WeaponRig/WeaponPivot/Mount")
	_grabber = _camera.get_node("Grabber")
	_world.get_node("RatSpawner").enabled = false


func _stand(at: Vector3, target: Vector3) -> void:
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_camera.look_at(target)
	_player.reset_physics_interpolation()
	await _frames()


func _strike() -> void:
	var keeper = _world.get_node("Shopkeeper")
	var counter = _world.get_node("Counter")
	var approach: Vector3 = counter.global_position - keeper.global_position
	approach.y = 0.0
	await _stand(counter.global_position + approach.normalized() * 1.5 + Vector3.UP * 0.5, keeper.get_hit_center())
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames(45)


func _place(shelf_name: String) -> bool:
	var stock = _world.get_node(shelf_name)
	var item = stock.get_item()
	if item == null:
		_check(false, "stock exists: " + shelf_name)
		return false
	var grabbed := false
	for direction in [stock.global_basis.z, -stock.global_basis.z, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		await _stand(stock.global_position + direction * 1.9 + Vector3.UP * 0.5, item.global_position)
		_grabber.try_grab()
		if _grabber.get_held() == item:
			grabbed = true
			break
		if _grabber.is_holding():
			var other = _grabber.get_held()
			_grabber.drop()
			other.return_home()
	_check(grabbed, "camera picks up placed shelf product: " + shelf_name)
	if not grabbed:
		return false
	var counter = _world.get_node("Counter")
	var keeper = _world.get_node("Shopkeeper")
	var approach: Vector3 = counter.global_position - keeper.global_position
	approach.y = 0.0
	await _stand(counter.global_position + approach.normalized() * 1.5 + Vector3.UP * 0.5, counter.get_node("Socket").global_position)
	_grabber.drop()
	await _frames()
	var placed: bool = counter.item == item and not _grabber.is_holding()
	_check(placed, "right-click drop docks into placed counter: " + shelf_name)
	return placed


func _buy(shelf_name: String) -> void:
	var stock = _world.get_node(shelf_name)
	var id: StringName = stock.item_data.id
	var count: int = _shop.get_purchase_count(id)
	var price: int = _shop.get_product_price(stock.item_data)
	var before: int = _wallet.total
	if not await _place(shelf_name):
		return
	await _strike()
	_check(_shop.busy and _wallet.total == before, "actual sword hit starts transaction without early payment: " + shelf_name)
	await _frames(180)
	_check(not _shop.busy and _wallet.total == before - price and _shop.counter.item == null, "animation delivers and charges exactly once: " + shelf_name)
	_check(_shop.get_purchase_count(id) == count + 1, "completed purchase is recorded: " + shelf_name)


func _run() -> void:
	await process_frame
	var save = root.get_node("SaveGame")
	save.save_path = "/tmp/main-world-shop-regression-save.json"
	root.get_node("GameSettings").settings_path = "/tmp/main-world-shop-regression-settings.cfg"
	_flow = root.get_node("GameFlow")
	_wallet = root.get_node("Wallet")
	_flow.start_new_game()
	await scene_changed
	_bind()
	await _frames()
	for node_name in PLACED_NODES:
		_placements[node_name] = _world.get_node(node_name).global_transform
	_check(_shop.counter == _world.get_node("Counter") and _shop.get("_shelves").size() == 6, "controller binds independent placed parts")
	await _strike()
	_check(not _shop.busy and _shop.get_status_message().contains("没有商品"), "empty counter gives feedback after sword hit")
	_check(_world.get_node("HUD/BottomText").get_displayed_text().contains("没有商品"), "shop feedback reaches bottom HUD")
	if await _place("Shelf"):
		await _strike()
		_check(not _shop.busy and _wallet.total == 0 and not _sword.oiled and _shop.counter.item != null, "insufficient funds retain product without effect or debit")
		_check(_world.get_node("HUD/BottomText").get_displayed_text().contains("金钱不足"), "insufficient funds are visible in HUD")
		_shop.counter.item.return_home()
	_wallet.set_total(1000)
	for shelf_name in ["Shelf", "CorpseValueShelf", "CorpseValueShelf", "GoldenCoinShelf", "MirrorShelf", "ChargedThrowShelf", "CorpseReturnShelf"]:
		await _buy(shelf_name)
	_check(_sword.oiled and _grabber.charged_throw_enabled and _world.get_node("Hole").has_upgrade("mirror"), "sword, grabber and mirror effects are delivered")
	_check(_world.get_node("Hole").get_corpse_value_level() == 2 and _world.get_node("Hole").get_golden_coin_level() == 1, "repeatable upgrades reach purchased levels")
	_check(_wallet.total == 555 and _shop.completed_purchases == 7, "all seven transactions have exact accounting")
	_check(_flow.get_purchased_upgrades() == {"oil": true, "mirror": true, "charged_throw": true, "corpse_return": true}, "world snapshot records completed purchases")
	_check(_flow.get_purchased_upgrade_levels() == {"corpse_value": 2, "golden_coin": 1}, "world snapshot records repeated levels")
	_check(_world.get_node("Hole").has_upgrade("corpse_return") and _world.get_node("CorpseReturnOutlet").is_enabled(), "soul egg activates the placed outlet")
	_check(_world.get_node("CorpseReturnShelf").sold_out and _world.get_node("CorpseReturnShelf").get_item() == null, "soul egg is delivered once and its shelf becomes empty")
	for node_name in _placements:
		_check(_placements[node_name].is_equal_approx(_world.get_node(node_name).global_transform), "placed model remains fixed: " + node_name)
	_check(save.save_game().ok, "completed purchases save")
	_flow.load_game()
	await scene_changed
	_bind()
	await _frames()
	_check(_wallet.total == 555 and _sword.oiled and _grabber.charged_throw_enabled, "reload restores money and player upgrades")
	_check(_world.get_node("CorpseReturnOutlet").is_enabled() and _world.get_node("CorpseReturnShelf").sold_out, "reload restores soul egg outlet without another purchase")
	_check(_shop.get_purchase_count(&"corpse_value") == 2 and _shop.get_product_price(_world.get_node("CorpseValueShelf").item_data) == 20, "reload restores repeat count and next price")
	_check(_world.get_node("MirrorShelf").sold_out and _world.get_node("MirrorShelf").get_item() == null, "reload restores single purchase stock")
	_check(_shop.completed_purchases == 0 and not _shop.busy, "reload does not replay transaction or payment")
	for node_name in _placements:
		_check(_placements[node_name].is_equal_approx(_world.get_node(node_name).global_transform), "reload preserves placed model: " + node_name)
	print("MAIN WORLD SHOP RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
