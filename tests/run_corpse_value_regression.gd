extends "res://tests/run_upgrade_save_regression.gd"

## 复用真实拾取 / 台面 / 剑击 / 菜单夹具；--phase=write/read 在独立进程验收。
var _offered: Array = []
var _erupted: Array = []
var _transferred: Array = []


func _initialize() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func():
		push_error("CORPSE VALUE REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("CORPSE VALUE REGRESSION FAILED: " + message)


func _stock():
	return _shop.get_node("CorpseValueShelf")


func _verify_level(level: int, coins: int) -> void:
	var stock = _stock()
	var price: int = 10 + 5 * level
	_check(_wallet.total == coins, "wallet matches completed purchases or restored snapshot")
	_check(_shop.get_purchase_count(&"corpse_value") == level and _hole.get_corpse_value_level() == level, "paid count and effective hole level agree")
	_check(_flow.get_purchased_upgrade_levels() == {"corpse_value": level, "golden_coin": 0}, "snapshot records purchase level separately from boolean abilities")
	_check(not stock.sold_out and stock.get_item() != null, "repeatable stone remains in stock")
	_check(_shop.get_product_price(stock.item_data) == price and stock.get_item().purchase_count == level, "shop and actual stocked item use next level price")
	_check(stock.get_node("Sign").text.contains("等级 %d" % level) and stock.get_node("Sign").text.contains("%d 金币" % price) and stock.get_node("Sign").text.contains("可重复购买"), "shelf displays current level and dynamic price")
	_check(stock.get_item().get_node("Price").text.contains("%d 金币" % price), "loose item label uses current price")
	_check(stock.item_data.price == 10 and load("res://resources/shop/shop_item_corpse_value.tres").price == 10, "shared resource retains base price")
	_check(_sword.visible and not _sword.interaction_locked and not _grabber.interaction_locked, "hole purchase releases interactions and keeps sword")
	_stand(_shop.to_global(stock.position + Vector3(0, 0.5, 2.1)))
	_camera.look_at(stock.get_node("Sign").global_position - Vector3.UP * 0.4, Vector3.UP)
	_check(_shop.get_prompt().contains("不点金石头") and _shop.get_prompt().contains("%d 金币" % price), "facing stone shows its dynamic price instead of adjacent oil behind player")


func _new_corpse(base: int, at: Vector3):
	var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
	corpse.value = base
	corpse.freeze = true
	corpse.burn_duration = 30.0
	_world.add_child(corpse)
	corpse.global_position = at
	corpse.reset_physics_interpolation()
	return corpse


func _offer_and_collect(corpse, expected_value: int) -> void:
	var id: int = corpse.get_instance_id()
	var original: int = corpse.value
	var before: int = _wallet.total
	var eruption_count: int = _erupted.size()
	_stand(Vector3(7, 0.5, -14))
	corpse.freeze = false
	corpse.global_position = _hole.global_position + Vector3.UP * 0.25
	corpse.reset_physics_interpolation()
	await _frames()
	var entries: Array = _offered.filter(func(entry): return entry.id == id)
	_check(entries.size() == 1 and entries[0].value == expected_value and entries[0].base == original, "actual swallow adds current level once to base value")
	_check(_hole.pending_value == expected_value, "pending settlement uses upgraded value")
	await _wait(2.3)
	_check(_erupted.size() == eruption_count + 1 and not _hole.has_pending(), "upgraded corpse produces one normal settlement")
	var multiplier := 1.5 if expected_value < 30 else 1.6
	var adjusted: int = int(round(expected_value * multiplier))
	var total: int = _erupted[-1].total
	_check(total >= int(round(adjusted * 0.9)) and total <= int(round(adjusted * 1.15)), "existing economic table and random modifier apply after value upgrade")
	var collection = load("res://tests/helpers/coin_collection.gd")
	_check(await collection.collect_all(self, _player), "player physically collects upgraded revenue after landing")
	_check(_wallet.total == before + total, "landed coins credit exactly the upgraded settlement")


func _place_stone_and_strike() -> void:
	var stock = _stock()
	var item = stock.get_item()
	_stand(_shop.to_global(stock.position + Vector3(0, 0.5, 1.2)))
	_camera.look_at(item.global_position, Vector3.UP)
	await _frames()
	await _click_right()
	_check(_grabber.get_held() == item, "real ray picks up stone for refused transaction")
	_stand(_shop.to_global(Vector3(0, 0.5, -0.4)))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	await _frames()
	await _click_right()
	_check(_shop.counter.item == item, "stone docks before actual keeper strike")
	await _strike()


func _run() -> void:
	await process_frame
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
	root.get_node("EventBus").corpse_offered.connect(func(corpse, value): _offered.append({"id": corpse.get_instance_id(), "base": corpse.value, "value": value}))
	root.get_node("EventBus").coins_erupted.connect(func(total, count): _erupted.append({"total": total, "count": count}))
	if _phase == "read":
		await _enter(true)
		_verify_level(3, 950)
		_check(_shop.completed_purchases == 0 and _hole.has_upgrade("corpse_return") and _world.is_gate_open(), "fresh process restores other paid ability and permanent gate without transaction")
		_check(_shop.restore_purchased_upgrades(_save.read_save().upgrades, _save.read_save().upgrade_levels), "repeated restore succeeds")
		_verify_level(3, 950)
		await _offer_and_collect(_new_corpse(1, Vector3(7, 0.5, -14)), 4)
		_finish()
		return
	await _enter()
	_verify_level(0, 0)
	var product = _stock().item_data
	_check(product.display_name == "不点金石头" and product.description == "让尸体更贵" and product.is_supported() and product.purchase_limit == 0, "design product supports unlimited repeatable purchase")
	await _key(KEY_G)
	if _phase == "write":
		for level in range(1, 4):
			await _buy("CorpseValueShelf")
			_verify_level(level, 1000 - (10 * level + 5 * level * (level - 1) / 2))
		await _buy("CorpseReturnShelf")
		_world.get_node("VineGate").restore_persistent_open()
		await _save_from_pause()
		_check(_save.read_save().upgrade_levels == {"corpse_value": 3, "golden_coin": 0} and _save.read_save().coins == 950, "write process stores level with other upgrade and gate")
		_finish()
		return
	# 动画中保存和离场，不保存未交付的等级，不提前扣款。
	await _begin_purchase("CorpseValueShelf")
	await _save_from_pause()
	_check(_save.read_save().upgrade_levels == {"corpse_value": 0, "golden_coin": 0} and _save.read_save().coins == 1000, "mid-animation save excludes undelivered level")
	await _menu_load()
	_verify_level(0, 1000)
	var old_corpse = _new_corpse(7, Vector3(7, 0.5, -14))
	await _buy("CorpseValueShelf")
	_verify_level(1, 990)
	_check(_hole._item_value(old_corpse) == 8 and old_corpse.value == 7, "corpse that predates upgrade immediately benefits without base mutation")
	await _begin_purchase("CorpseValueShelf")
	_flow.pause_game()
	await _wait(1.0)
	_check(_shop.busy and _wallet.total == 990 and _hole.get_corpse_value_level() == 1, "pause freezes transaction and cannot advance level")
	_flow.resume_game()
	await _wait(3.0)
	_verify_level(2, 975)
	_wallet.set_total(19)
	await _place_stone_and_strike()
	_check(not _shop.busy and _wallet.total == 19 and _hole.get_corpse_value_level() == 2 and _shop.counter.item != null, "insufficient dynamic price keeps money, level and product")
	_check(_shop.get_status_message().contains("20 金币"), "refusal reports next actual price")
	_wallet.set_total(20)
	await _strike()
	_check(_shop.busy, "retry begins third level transaction")
	_wallet.set_total(0)
	await _wait(3.0)
	_check(not _shop.busy and _wallet.total == 0 and _hole.get_corpse_value_level() == 2 and _shop.counter.item != null, "funds lost during animation cancel delivery without upgrade")
	_wallet.set_total(20)
	await _strike()
	await _wait(3.0)
	_verify_level(3, 0)
	await _offer_and_collect(old_corpse, 10)
	await _offer_and_collect(_new_corpse(0, Vector3(7, 0.5, -14)), 3)
	_check(_hole._item_value(_stock().get_item()) == 0, "corpse bonus never adds value to shop products")
	# 与灵魂鸡蛋共存，并将等级加入同一手动存档。
	_wallet.set_total(1000)
	await _buy("CorpseReturnShelf")
	await _save_from_pause()
	var saved_text := FileAccess.get_file_as_string(_save.save_path)
	_check(JSON.parse_string(saved_text).version == _save.FORMAT_VERSION and JSON.parse_string(saved_text).upgrade_levels.corpse_value == "3", "current format saves exact level as canonical decimal string")
	await _menu_load()
	_verify_level(3, 995)
	_check(_hole.has_upgrade("corpse_return") and _outlet.is_enabled() and _shop.completed_purchases == 0, "load combines automatic return and value growth without replay")
	for repeat in range(3):
		_check(_shop.restore_purchased_upgrades(_save.read_save().upgrades, _save.read_save().upgrade_levels), "level restore is idempotent")
	_verify_level(3, 995)
	await _test_actual_return()
	_check(FileAccess.get_file_as_string(_save.save_path) == saved_text, "unsaved upgraded revenue leaves previous manual snapshot intact")
	await _enter()
	_verify_level(0, 0)
	_check(FileAccess.get_file_as_string(_save.save_path) == saved_text, "new game resets current level but keeps disk snapshot")
	DirAccess.make_dir_absolute(_save.save_path + ".tmp")
	_check(not _save.save_game().ok and FileAccess.get_file_as_string(_save.save_path) == saved_text, "failed atomic write preserves complete old level snapshot")
	DirAccess.remove_absolute(_save.save_path + ".tmp")
	await _test_migration_and_invalid()
	_finish()


func _test_actual_return() -> void:
	var corpse = _new_corpse(2, _shop.to_global(Vector3(2.5, 0.45, 1.5)))
	corpse.freeze = false
	corpse.element.ignite()
	var id: int = corpse.get_instance_id()
	_outlet.corpse_transferred.connect(func(candidate, room_id): _transferred.append({"id": candidate.get_instance_id(), "base": candidate.value, "burning": candidate.element.burning, "room": room_id}))
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
	_player.set_physics_process(false)
	_stand(Vector3(7, 0.5, -14))
	for frame in range(800):
		if _offered.any(func(entry): return entry.id == id):
			break
		await physics_frame
	var transfers: Array = _transferred.filter(func(entry): return entry.id == id)
	var offers: Array = _offered.filter(func(entry): return entry.id == id)
	_check(transfers.size() == 1 and transfers[0].base == 2 and transfers[0].burning and transfers[0].room == &"shop", "actual room exit returns burning corpse once and preserves base value")
	_check(offers.size() == 1 and offers[0].value == 5 and offers[0].base == 2, "returned burning corpse receives exactly current level bonus at intake")
	await _wait(2.3)
	_check(await load("res://tests/helpers/coin_collection.gd").collect_all(self, _player), "returned upgraded revenue lands and can be collected")
	_check(_hole.get_corpse_value_level() == 3, "automatic return never increments upgrade level")


func _test_migration_and_invalid() -> void:
	var previous_scene = current_scene
	var payload := {"version": 5, "coins": "123", "upgrades": _save.empty_upgrades(), "upgrade_levels": {"corpse_value": "3"}, "level": "world", "opened_gates": {}}
	for invalid in [null, [], {}, {"corpse_value": true}, {"corpse_value": 3}, {"corpse_value": 3.0}, {"corpse_value": "-1"}, {"corpse_value": "03"}, {"corpse_value": "3.0"}, {"corpse_value": "9223372036854775808"}, {"corpse_value": str(ShopItemData.MAX_CORPSE_VALUE_LEVEL + 1)}, {"unknown": "3"}, {"corpse_value": "3", "unknown": "0"}]:
		payload.upgrade_levels = invalid
		_write_raw(JSON.stringify(payload))
		_check(not _flow.load_game().ok and current_scene == previous_scene and _wallet.total == 0 and _hole.get_corpse_value_level() == 0, "invalid level data leaves live game intact")
	payload.upgrade_levels = {"corpse_value": "1"}
	payload.level = "mechanism_lab"
	_write_raw(JSON.stringify(payload))
	_check(not _flow.load_game().ok, "shopless lab rejects purchased level")
	for version in [1, 2, 3, 4]:
		var legacy := {"version": version, "coins": "9007199254740993"}
		if version == 2:
			legacy.upgrades = {"corpse_return": true, "charged_throw": true}
		elif version >= 3:
			legacy.upgrades = {"oil": true, "corpse_return": true, "charged_throw": true}
		if version == 4:
			legacy.level = "world"
			legacy.opened_gates = {"world.cleaning.vines": true}
		_write_raw(JSON.stringify(legacy))
		await _enter(true)
		_verify_level(0, 9007199254740993)
		_check(_world.is_gate_open() == (version == 4) and _hole.has_upgrade("corpse_return") == (version >= 2) and _sword.oiled == (version >= 3), "v%d preserves old paid abilities and gate snapshot" % version)
		_check(_save.save_game().ok and JSON.parse_string(FileAccess.get_file_as_string(_save.save_path)).upgrade_levels == {"corpse_value": "0", "golden_coin": "0"}, "old save migrates to level zero on manual save")
	payload.level = "world"
	payload.upgrade_levels = {"corpse_value": "9007199254740993"}
	_write_raw(JSON.stringify(payload))
	await _enter(true)
	_check(_hole.get_corpse_value_level() == 9007199254740993 and _shop.get_product_price(_stock().item_data) == 45035996273704975, "level and price retain integer precision beyond JSON floating range")
	_check(_save.save_game().ok and JSON.parse_string(FileAccess.get_file_as_string(_save.save_path)).upgrade_levels.corpse_value == "9007199254740993", "large valid level round-trips exactly")
	await _enter()
	# 免费直接授予能力不记作已购等级。
	_check(_hole.apply_upgrade("corpse_value") and _flow.get_purchased_upgrade_levels().corpse_value == 0, "free debug level is excluded from purchased progress")
	_check(_save.save_game().ok and _save.read_save().upgrade_levels.corpse_value == 0, "manual save records only completed paid level")
	await _enter(true)
	_verify_level(0, 0)


func _finish() -> void:
	paused = false
	print("CORPSE VALUE REGRESSION RESULT: phase=%s passed=%d failed=%d" % [_phase, _passed, _failed])
	quit(0 if _failed == 0 else 1)
