extends "res://tests/run_corpse_value_regression.gd"

## 真实购买、逐币点金、落地接触拾取及跨进程等级存档；全部写入隔离目录。

func _initialize() -> void:
	create_timer(300.0, true, false, true).timeout.connect(func():
		push_error("GOLDEN COIN REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("GOLDEN COIN REGRESSION FAILED: " + message)


func _stock():
	return _shop.get_node("GoldenCoinShelf")


func _verify_gold(level: int, coins: int) -> void:
	var stock = _stock()
	_check(_wallet.total == coins, "wallet matches completed gold purchase")
	_check(_shop.get_purchase_count(&"golden_coin") == level and _hole.get_golden_coin_level() == level, "gold purchase count and effective level agree")
	_check(_flow.get_purchased_upgrade_levels().golden_coin == level, "snapshot includes paid golden level")
	_check(_hole.has_upgrade("golden_coin") == (level > 0), "gold ownership follows level")
	_check(stock.get_node("Sign").text.contains("等级 %d/20" % level) and stock.get_node("Sign").text.contains("%d%%" % (level * 5)), "shelf shows current level and probability")
	if level == 20:
		_check(stock.sold_out and stock.get_item() == null and not _hole.can_apply_upgrade("golden_coin"), "twentieth purchase removes product and caps upgrade")
		_check(stock.get_node("Sign").text.contains("已满级") and not stock.get_node("Sign").text.contains("110 金币"), "max level shows completion instead of nonexistent next purchase")
	else:
		var price: int = 10 + 5 * level
		_check(not stock.sold_out and stock.get_item() != null and stock.get_item().purchase_count == level, "nonmax golden stone restocks with current level")
		_check(_shop.get_product_price(stock.item_data) == price and stock.get_item().get_node("Price").text.contains("%d 金币" % price), "loose product and shop have dynamic next price")
	_check(stock.item_data.price == 10 and stock.item_data.purchase_limit == 20, "shared product config remains base 10 and cap 20")
	_check(_sword.visible and not _sword.interaction_locked and not _grabber.interaction_locked, "gold delivery unlocks player and keeps sword")
	_stand(_shop.to_global(stock.position + Vector3(0, 0.5, 1.6)))
	_camera.look_at(stock.get_node("Sign").global_position - Vector3.UP * 0.4, Vector3.UP)
	_check(_shop.get_prompt().contains("点金石头"), "facing gold shelf shows its own product prompt")
	if level == 20:
		_check(_shop.get_prompt().contains("已满级") and _shop.get_prompt().contains("100%"), "max shelf prompt has probability and cap")


func _offer_gold(base: int, gold_level: int, bonus: int = 0) -> void:
	var before: int = _wallet.total
	var events: int = _erupted.size()
	# 固定普通结算随机数，使实际金币数量与断言数跨帧率 / 进程可复现。
	_hole._rng.seed = 98765
	_stand(Vector3(7, 0.5, -14))
	var corpse = _new_corpse(base, _hole.global_position + Vector3.UP * 0.25)
	var id: int = corpse.get_instance_id()
	corpse.freeze = false
	await _frames()
	_check(_offered.any(func(entry): return entry.id == id and entry.base == base and entry.value == base + bonus), "intake applies corpse bonus before golden settlement")
	await _wait(2.3)
	var pool = root.get_node("CoinPool")
	var coins: Array = pool.get("_active").duplicate()
	var ordinary := 0
	var actual := 0
	var golden := 0
	for coin in coins:
		actual += coin.value
		@warning_ignore("integer_division")
		ordinary += coin.value / 10 if coin.is_golden else coin.value
		if coin.is_golden:
			golden += 1
			_check(coin.value % 10 == 0 and coin.get_node("Mesh").material_override.albedo_color == coin.GOLDEN_COLOR, "hit coin has tenfold value and gold appearance")
		else:
			_check(coin.get_node("Mesh").material_override.emission_energy_multiplier == 0.5, "ordinary reused coin resets emission")
	_check(not coins.is_empty() and _erupted.size() == events + 1, "one actual intake produces one eruption")
	_check(_erupted[-1].total == actual and _erupted[-1].count == coins.size(), "event reports actual post-gold physical value and count")
	var adjusted := int(round((base + bonus) * (1.5 if base + bonus < 30 else 1.6)))
	_check(ordinary >= int(round(adjusted * 0.9)) and ordinary <= int(round(adjusted * 1.15)), "normal offering multiplier and random correction precede gold rolls")
	_check(golden == 0 if gold_level == 0 else (golden == coins.size() if gold_level == 20 else true), "zero percent never hits and max always hits")
	_check(actual == ordinary * 10 if gold_level == 20 else actual >= ordinary, "tenfold reward stacks after ordinary settlement")
	_check(await load("res://tests/helpers/coin_collection.gd").collect_all(self, _player), "golden coins physically land and player walks to collect")
	_check(_wallet.total == before + actual and pool.active_count() == 0, "wallet receives exactly post-gold value after contact")
	for coin in coins:
		_check(not coin.is_golden and coin.is_collected(), "pool release clears golden state")


func _test_probability_and_pool() -> void:
	var pool = root.get_node("CoinPool")
	var totals := {}
	var base_values := PackedInt32Array([1, 5, 25, 1, 5, 25, 1, 5, 25, 1, 5, 25, 1, 5, 25, 1, 5, 25, 1, 5])
	# 固定随机种子的大样本；检查逐枚判定、5% / 50% 分布与普通币价值不变。
	for level in [0, 1, 10, 20]:
		_check(_hole.restore_upgrade_level("golden_coin", level), "set probability sample level")
		_hole._rng.seed = 54321
		var hits := 0
		for batch in range(25):
			var spawned: int = _hole._spawn_coins(base_values, PackedFloat32Array([1.0]), 3.0, 7.5, 0.3)
			var physical := 0
			var correct_values := true
			var active: Array = pool.get("_active")
			for index in active.size():
				var coin = active[index]
				physical += coin.value
				correct_values = correct_values and coin.value == base_values[index] * (10 if coin.is_golden else 1)
				if coin.is_golden:
					hits += 1
			_check(spawned == physical and pool.active_count() == 20, "each rolled batch retains count and physical sum")
			_check(correct_values, "each coin multiplies its own ordinary denomination only on a hit")
			pool.release_all()
		totals[level] = hits
		_check(hits == 0 if level == 0 else (hits == 500 if level == 20 else hits > 0 and hits < 500), "endpoint and intermediate rolls are per coin")
	_check(totals[1] >= 8 and totals[1] <= 45 and totals[10] >= 200 and totals[10] <= 300, "seeded samples agree with 5 percent and 50 percent probabilities")
	print("GOLDEN PROBABILITY SAMPLE: " + str(totals) + " of 500 per level")
	_check(pool.free_count() <= 20, "probability test reuses pool instead of accumulating coins")
	var reused = pool.acquire()
	reused.launch(5, Color(0.76, 0.48, 0.22), Vector3.ZERO, 0.3)
	_check(not reused.is_golden and reused.value == 5 and reused.get_node("Mesh").material_override.metallic == 0.0 and reused.get_node("Mesh").material_override.albedo_color == Color(0.76, 0.48, 0.22), "pooled gold restores ordinary value and visual on next launch")
	pool.release(reused)
	_check(not _hole.restore_upgrade_level("golden_coin", -1) and not _hole.restore_upgrade_level("golden_coin", 21) and not _hole.apply_upgrade("golden_coin"), "out of range levels and further max upgrade fail")
	_hole.restore_upgrade_level("golden_coin", _shop.get_purchase_count(&"golden_coin"))


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
		_verify_gold(20, 800)
		_check(_hole.get_corpse_value_level() == 3 and _hole.has_upgrade("corpse_return") and _world.is_gate_open() and _shop.completed_purchases == 0, "fresh process restores stacked levels, egg and gate without transaction")
		_check(_shop.restore_purchased_upgrades(_save.read_save().upgrades, _save.read_save().upgrade_levels), "max restore is idempotent")
		_verify_gold(20, 800)
		await _offer_gold(1, 20, 3)
		await _reject_max()
		_finish()
		return
	await _enter()
	_verify_gold(0, 0)
	_check(_stock().item_data.display_name == "点金石头" and _stock().item_data.description == "可能...也许...有效果吧" and _stock().item_data.is_supported(), "gold product matches design")
	_wallet.set_total(2000)
	if _phase == "write":
		for level in range(1, 21):
			await _buy("GoldenCoinShelf")
			_verify_gold(level, 2000 - (10 * level + 5 * level * (level - 1) / 2))
		for level in range(3):
			await _buy("CorpseValueShelf")
		await _buy("CorpseReturnShelf")
		_world.get_node("VineGate").restore_persistent_open()
		await _save_from_pause()
		_check(_save.read_save().upgrade_levels == {"corpse_value": 3, "golden_coin": 20} and _save.read_save().coins == 800, "write process saves both purchased levels and existing progress")
		_finish()
		return
	await _test_probability_and_pool()
	await _offer_gold(1, 0)
	_wallet.set_total(2000)
	await _begin_purchase("GoldenCoinShelf")
	await _save_from_pause()
	_check(_save.read_save().upgrade_levels.golden_coin == 0 and _save.read_save().coins == 2000, "mid-animation save excludes undelivered gold level")
	await _menu_load()
	_verify_gold(0, 2000)
	await _buy("GoldenCoinShelf")
	_verify_gold(1, 1990)
	await _begin_purchase("GoldenCoinShelf")
	_flow.pause_game()
	await _wait(1.0)
	_check(_shop.busy and _wallet.total == 1990 and _hole.get_golden_coin_level() == 1, "pause freezes gold delivery")
	_flow.resume_game()
	await _wait(3.0)
	_verify_gold(2, 1975)
	_wallet.set_total(19)
	await _place_stone_and_strike()
	_check(not _shop.busy and _wallet.total == 19 and _hole.get_golden_coin_level() == 2 and _shop.counter.item != null and _shop.get_status_message().contains("20 金币"), "insufficient money retains product and reports dynamic price")
	_wallet.set_total(20)
	await _strike()
	_wallet.set_total(0)
	await _wait(3.0)
	_check(not _shop.busy and _wallet.total == 0 and _hole.get_golden_coin_level() == 2 and _shop.counter.item != null, "losing funds during animation cancels gold purchase")
	_wallet.set_total(1975)
	await _strike()
	await _wait(3.0)
	_verify_gold(3, 1955)
	for level in range(3):
		await _buy("CorpseValueShelf")
	await _buy("CorpseReturnShelf")
	_world.get_node("VineGate").restore_persistent_open()
	await _save_from_pause()
	var snapshot := FileAccess.get_file_as_string(_save.save_path)
	_check(JSON.parse_string(snapshot).version == _save.FORMAT_VERSION and JSON.parse_string(snapshot).upgrade_levels == {"corpse_value": "3", "golden_coin": "3"}, "current format stores independent levels as exact decimal strings")
	await _menu_load()
	_verify_gold(3, 1905)
	_check(_hole.get_corpse_value_level() == 3 and _hole.has_upgrade("corpse_return") and _world.is_gate_open(), "loading gold retains existing upgrades and opened gate")
	for repeat in range(3):
		_check(_shop.restore_purchased_upgrades(_save.read_save().upgrades, _save.read_save().upgrade_levels), "restoring gold level repeatedly does not stack")
	_verify_gold(3, 1905)
	for level in range(4, 21):
		var before: int = _wallet.total
		await _buy("GoldenCoinShelf")
		_verify_gold(level, before - (10 + 5 * (level - 1)))
	_check(_wallet.total == 800, "twenty gold levels total 1150 plus other paid upgrades")
	await _reject_max()
	await _offer_gold(1, 20, 3)
	_check(FileAccess.get_file_as_string(_save.save_path) == snapshot, "unsaved purchases and gold revenue preserve manual snapshot")
	await _save_from_pause()
	var max_coins: int = _wallet.total
	await _menu_load()
	_verify_gold(20, max_coins)
	_check(_shop.completed_purchases == 0, "max load restores sold-out shelf without replay")
	await _enter()
	_verify_gold(0, 0)
	var saved_max := FileAccess.get_file_as_string(_save.save_path)
	DirAccess.make_dir_absolute(_save.save_path + ".tmp")
	_check(not _save.save_game().ok and FileAccess.get_file_as_string(_save.save_path) == saved_max, "failed atomic write preserves purchased max levels")
	DirAccess.remove_absolute(_save.save_path + ".tmp")
	await _test_gold_migration()
	_finish()


func _reject_max() -> void:
	var before: int = _wallet.total
	var duplicate = load("res://scenes/shop/shop_item.tscn").instantiate()
	duplicate.data = _stock().item_data
	_world.add_child(duplicate)
	_check(_shop.counter.place_item(duplicate), "duplicate max product placed on counter")
	_stand(_shop.to_global(Vector3(0, 0.5, -0.4)))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	await _frames()
	await _strike()
	_check(not _shop.busy and _wallet.total == before and _hole.get_golden_coin_level() == 20 and _shop.counter.item == duplicate, "max level rejects duplicate transaction without debit")
	duplicate.return_home()
	duplicate.queue_free()
	await _frames()


func _test_gold_migration() -> void:
	var payload := {"version": 6, "coins": "123", "upgrades": {"oil": false, "corpse_return": false, "charged_throw": false}, "upgrade_levels": {"corpse_value": "3", "golden_coin": "3"}, "level": "world", "opened_gates": {}}
	var previous_scene = current_scene
	for invalid in [null, [], {}, {"corpse_value": "0"}, {"corpse_value": "0", "golden_coin": true}, {"corpse_value": "0", "golden_coin": 3}, {"corpse_value": "0", "golden_coin": "-1"}, {"corpse_value": "0", "golden_coin": "21"}, {"corpse_value": "0", "golden_coin": "03"}, {"corpse_value": "0", "golden_coin": "3.0"}, {"corpse_value": "0", "golden_coin": "9223372036854775808"}, {"corpse_value": "0", "golden_coin": "3", "unknown": "0"}]:
		payload.upgrade_levels = invalid
		_write_raw(JSON.stringify(payload))
		_check(not _flow.load_game().ok and current_scene == previous_scene and _wallet.total == 0 and _hole.get_golden_coin_level() == 0, "malformed or out of range gold level leaves current game intact")
	payload.upgrade_levels = {"corpse_value": "0", "golden_coin": "1"}
	payload.level = "mechanism_lab"
	_write_raw(JSON.stringify(payload))
	_check(not _flow.load_game().ok, "shopless lab rejects gold purchase")
	for version in range(1, 6):
		var legacy := {"version": version, "coins": "9007199254740993"}
		if version == 2:
			legacy.upgrades = {"corpse_return": true, "charged_throw": true}
		elif version >= 3:
			legacy.upgrades = {"oil": true, "corpse_return": true, "charged_throw": true}
		if version >= 4:
			legacy.level = "world"
			legacy.opened_gates = {"world.cleaning.vines": true}
		if version == 5:
			legacy.upgrade_levels = {"corpse_value": "3"}
		_write_raw(JSON.stringify(legacy))
		await _enter(true)
		_verify_gold(0, 9007199254740993)
		_check(_hole.get_corpse_value_level() == (3 if version == 5 else 0) and _world.is_gate_open() == (version >= 4) and _sword.oiled == (version >= 3), "v%d keeps previous level, capabilities and gates" % version)
		_check(_save.save_game().ok and _save.read_save().upgrade_levels.golden_coin == 0 and JSON.parse_string(FileAccess.get_file_as_string(_save.save_path)).version == _save.FORMAT_VERSION, "legacy upgrades on manual save without free gold")
	await _enter()
	_check(_hole.apply_upgrade("golden_coin") and _flow.get_purchased_upgrade_levels().golden_coin == 0, "free gold debug grant is excluded from purchases")
	_check(_save.save_game().ok and _save.read_save().upgrade_levels.golden_coin == 0, "save only counts completed paid gold levels")
	await _enter(true)
	_verify_gold(0, 0)


func _finish() -> void:
	paused = false
	print("GOLDEN COIN REGRESSION RESULT: phase=%s passed=%d failed=%d" % [_phase, _passed, _failed])
	quit(0 if _failed == 0 else 1)
