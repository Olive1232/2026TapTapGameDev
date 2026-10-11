extends "res://tests/run_corpse_value_regression.gd"

## 镜子实体交易、单次尸体价值复制、两石叠加与 v1—v7 / 跨进程存档。
func _initialize() -> void:
	create_timer(300.0, true, false, true).timeout.connect(func():
		push_error("MIRROR REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("MIRROR REGRESSION FAILED: " + message)


func _stock():
	return _shop.get_node("MirrorShelf")


func _verify_mirror(owned: bool, coins: int) -> void:
	var stock = _stock()
	_check(_wallet.total == coins and _hole.has_upgrade("mirror") == owned, "mirror ownership and wallet match completed purchase")
	_check(_shop.get_purchase_count(&"mirror") == (1 if owned else 0) and _flow.get_purchased_upgrades().mirror == owned, "snapshot records paid mirror once")
	_check(stock.sold_out == owned and (stock.get_item() == null) == owned, "mirror stock disappears only after purchase")
	_check(stock.get_node("Sign").text.contains("镜子") and stock.get_node("Sign").text.contains("200 金币") and stock.get_node("Sign").text.contains("限购 1 次"), "mirror shelf displays price and limit")
	_check(stock.get_node("Sign").text.contains("已售罄") == owned, "mirror sold-out label follows ownership")
	_check(_hole.can_apply_upgrade("mirror") != owned, "mirror cannot be applied twice")
	_stand(_shop.to_global(stock.position + Vector3(0, 0.5, 1.2)))
	_camera.look_at(stock.get_node("ItemSpawn").global_position, Vector3.UP)
	_check(_shop.get_prompt().contains("镜子") and _shop.get_prompt().contains("已售罄" if owned else "200 金币"), "facing mirror shows correct product prompt")
	_check(_sword.visible and not _sword.interaction_locked and not _grabber.interaction_locked, "mirror leaves sword and player interactions available")


func _offer_mirror(corpse, expected_value: int, golden: bool = false, held: bool = false) -> void:
	var id: int = corpse.get_instance_id()
	var base: int = corpse.value
	var before: int = _wallet.total
	var events: int = _erupted.size()
	_hole._rng.seed = 98765
	_stand(Vector3(7, 0.5, -14))
	if held:
		corpse.global_position = _camera.global_position - _camera.global_basis.z * 1.6
		await _frames()
		await _click_right()
		_check(_grabber.get_held() == corpse and _player.carry_weight > 0.0, "real pickup holds corpse before mirrored sacrifice")
	corpse.freeze = false
	corpse.global_position = _hole.global_position + Vector3.UP * (1.8 if held else 0.25)
	corpse.reset_physics_interpolation()
	await _frames()
	var offered: Array = _offered.filter(func(entry): return entry.id == id)
	_check(offered.size() == 1 and offered[0].base == base and offered[0].value == expected_value, "one actual corpse intake copies effective value once without mutating base")
	_check(not is_instance_valid(corpse) and _hole.pending_value == expected_value, "original corpse is removed and only copied value remains pending")
	if held:
		_check(not _grabber.is_holding() and is_zero_approx(_player.carry_weight), "held sacrifice clears grab reference and carry weight")
	await _wait(2.3)
	var pool = root.get_node("CoinPool")
	var coins: Array = pool.get("_active").duplicate()
	var actual := 0
	var ordinary := 0
	for coin in coins:
		actual += coin.value
		@warning_ignore("integer_division")
		ordinary += coin.value / 10 if coin.is_golden else coin.value
		_check(coin.is_golden == golden, "gold roll follows stone level after mirror settlement")
		if golden:
			_check(coin.get_node("Mesh").material_override.albedo_color == coin.GOLDEN_COLOR, "copied revenue has golden appearance on a hit")
	var adjusted := int(round(expected_value * (1.5 if expected_value < 30 else 1.6)))
	_check(ordinary >= int(round(adjusted * 0.9)) and ordinary <= int(round(adjusted * 1.15)), "offering table and randomness run after copied intake")
	_check(_erupted.size() == events + 1 and _erupted[-1].total == actual and _erupted[-1].count == coins.size(), "one corpse produces one eruption reporting real coin total")
	_check(actual == ordinary * (10 if golden else 1), "gold multiplies each ordinary denomination after mirror")
	_check(await load("res://tests/helpers/coin_collection.gd").collect_all(self, _player), "player walks to collect physically landed mirrored revenue")
	_check(_wallet.total == before + actual and pool.active_count() == 0, "wallet receives mirrored revenue only on pickup")
	await _wait(2.3)
	_check(_erupted.size() == events + 1, "mirror does not repeat settlement after copied coins launch")


func _reject_duplicate() -> void:
	var before: int = _wallet.total
	var duplicate = load("res://scenes/shop/shop_item.tscn").instantiate()
	duplicate.data = _stock().item_data
	_world.add_child(duplicate)
	_check(_shop.counter.place_item(duplicate), "duplicate mirror docks on actual counter")
	_stand(_shop.to_global(Vector3(0, 0.5, -0.4)))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	await _frames()
	await _strike()
	_check(not _shop.busy and _wallet.total == before and _shop.counter.item == duplicate and _shop.get_purchase_count(&"mirror") == 1, "owned mirror rejects real duplicate transaction without debit")
	_check(not _hole.apply_upgrade("mirror"), "duplicate effect application is rejected")
	duplicate.return_home()
	duplicate.queue_free()
	await _frames()


func _buy_other_upgrades() -> void:
	for level in range(3):
		await _buy("CorpseValueShelf")
	for level in range(20):
		await _buy("GoldenCoinShelf")
	await _buy("CorpseReturnShelf")
	await _buy("ChargedThrowShelf")
	await _buy("Shelf")
	_world.get_node("VineGate").restore_persistent_open()


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
		_verify_mirror(true, 395)
		_check(_hole.get_corpse_value_level() == 3 and _hole.get_golden_coin_level() == 20 and _hole.has_upgrade("corpse_return") and _grabber.has_upgrade("charged_throw") and _sword.oiled and _world.is_gate_open(), "fresh process restores all six paid products and permanent gate")
		_check(_shop.completed_purchases == 0 and _shop.restore_purchased_upgrades(_save.read_save().upgrades, _save.read_save().upgrade_levels), "fresh restore is idempotent and replays no transaction")
		_verify_mirror(true, 395)
		await _offer_mirror(_new_corpse(1, Vector3(7, 0.5, -14)), 8, true)
		await _reject_duplicate()
		_finish()
		return
	await _enter()
	_verify_mirror(false, 0)
	_check(_stock().item_data.is_supported() and not _stock().item_data.is_repeatable() and _stock().item_data.purchase_limit == 1, "mirror is supported as a single hole purchase")
	var standalone = load("res://scenes/economy/hole.tscn").instantiate()
	_check(standalone.corpse_return_outlet_path.is_empty() and standalone.apply_upgrade("mirror") and not standalone.apply_upgrade("mirror") and not standalone.can_apply_upgrade("unknown"), "mirror works independently of corpse return outlet")
	standalone.free()
	await _key(KEY_G)
	await _key(KEY_G)
	if _phase == "write":
		await _buy("MirrorShelf")
		await _buy_other_upgrades()
		_verify_mirror(true, 395)
		await _save_from_pause()
		_check(_save.read_save().upgrades == {"oil": true, "corpse_return": true, "charged_throw": true, "mirror": true} and _save.read_save().upgrade_levels == {"corpse_value": 3, "golden_coin": 20}, "write process stores mirror together with all previous upgrades")
		_finish()
		return
	await _begin_purchase("MirrorShelf")
	_check(_shop.get_status_message().contains("镜子"), "mirror has its own transaction message")
	await _save_from_pause()
	_check(_save.read_save().coins == 2000 and not _save.read_save().upgrades.mirror, "mid-animation save excludes unpaid mirror and keeps money")
	await _menu_load()
	_verify_mirror(false, 2000)
	var old_corpse = _new_corpse(1, Vector3(7, 0.5, -14))
	await _begin_purchase("MirrorShelf")
	_flow.pause_game()
	await _wait(1.0)
	_check(_shop.busy and _wallet.total == 2000 and not _hole.has_upgrade("mirror"), "pause freezes mirror delivery")
	_flow.resume_game()
	_wallet.set_total(199)
	await _wait(3.0)
	_check(not _shop.busy and _wallet.total == 199 and not _hole.has_upgrade("mirror") and _shop.counter.item != null, "losing funds cancels delivery and retains product")
	await _strike()
	_check(not _shop.busy and _shop.get_status_message().contains("200 金币"), "insufficient funds reports mirror price without beginning transaction")
	_wallet.set_total(2000)
	await _strike()
	await _wait(3.0)
	_verify_mirror(true, 1800)
	_check(_shop.get_status_message().contains("每具只复制一次"), "mirror completion explains its actual effect")
	_check(_hole._item_value(old_corpse) == 2 and _hole._item_value(old_corpse) == 2 and old_corpse.value == 1, "old corpse immediately benefits and repeated queries do not compound")
	await _offer_mirror(old_corpse, 2)
	var zero = _new_corpse(0, Vector3(7, 0.5, -14))
	_check(_hole._item_value(zero) == 0, "zero value stays zero without stone bonus")
	zero.queue_free()
	await _frames()
	await _reject_duplicate()
	# Actual paid purchases verify independent levels, capped gold and coexistence of all products.
	_wallet.set_total(1800)
	await _buy_other_upgrades()
	_verify_mirror(true, 395)
	_check(_hole._item_value(_shop.shelf.get_item()) == 0, "shop goods never gain copied value")
	var large = _new_corpse(ShopItemData.MAX_INT, Vector3(7, 0.5, -14))
	_check(_hole._item_value(large) == ShopItemData.MAX_INT, "mirror value calculation does not overflow int64")
	large.queue_free()
	await _frames()
	await _save_from_pause()
	var snapshot := FileAccess.get_file_as_string(_save.save_path)
	_check(JSON.parse_string(snapshot).version == 7 and JSON.parse_string(snapshot).upgrades.mirror == true, "v7 stores explicit paid mirror flag")
	await _menu_load()
	_verify_mirror(true, 395)
	for repeat in range(3):
		_check(_shop.restore_purchased_upgrades(_save.read_save().upgrades, _save.read_save().upgrade_levels), "repeated mirror restore succeeds without duplication")
	_check(_shop.completed_purchases == 0 and _hole.upgrade_tags.count("mirror") == 1, "restoring mirror never replays purchase or repeats tag")
	await _offer_mirror(_new_corpse(1, Vector3(7, 0.5, -14)), 8, true)
	await _offer_mirror(_new_corpse(0, Vector3(7, 0.5, -14)), 6, true)
	await _offer_mirror(_new_corpse(1, Vector3(7, 0.5, -14)), 8, true, true)
	await _test_actual_return(10)
	_check(FileAccess.get_file_as_string(_save.save_path) == snapshot, "unsaved mirrored revenue preserves manual snapshot")
	await _enter()
	_verify_mirror(false, 0)
	_check(FileAccess.get_file_as_string(_save.save_path) == snapshot, "new game resets mirror but keeps disk save")
	DirAccess.make_dir_absolute(_save.save_path + ".tmp")
	_check(not _save.save_game().ok and FileAccess.get_file_as_string(_save.save_path) == snapshot, "failed atomic write preserves mirror snapshot")
	DirAccess.remove_absolute(_save.save_path + ".tmp")
	await _test_mirror_migration()
	_finish()


func _test_mirror_migration() -> void:
	var previous_scene = current_scene
	var payload := {"version": 7, "coins": "123", "upgrades": _save.empty_upgrades(), "upgrade_levels": {"corpse_value": "3", "golden_coin": "20"}, "level": "world", "opened_gates": {}}
	for invalid in [null, {}, {"oil": false, "corpse_return": false, "charged_throw": false}, {"oil": false, "corpse_return": false, "charged_throw": false, "mirror": 1}, {"oil": false, "corpse_return": false, "charged_throw": false, "mirror": "true"}, {"oil": false, "corpse_return": false, "charged_throw": false, "mirror": null}, {"oil": false, "corpse_return": false, "charged_throw": false, "mirror": true, "unknown": false}]:
		payload.upgrades = invalid
		_write_raw(JSON.stringify(payload))
		_check(not _flow.load_game().ok and current_scene == previous_scene and _wallet.total == 0 and not _hole.has_upgrade("mirror"), "malformed mirror save leaves live game intact")
	payload.upgrades = _save.empty_upgrades()
	payload.upgrades.mirror = true
	payload.upgrade_levels = {"corpse_value": "0", "golden_coin": "0"}
	payload.level = "mechanism_lab"
	_write_raw(JSON.stringify(payload))
	_check(not _flow.load_game().ok, "shopless lab rejects a mirror purchase record")
	for version in range(1, 7):
		var legacy := {"version": version, "coins": "9007199254740993"}
		if version == 2:
			legacy.upgrades = {"corpse_return": true, "charged_throw": true}
		elif version >= 3:
			legacy.upgrades = {"oil": true, "corpse_return": true, "charged_throw": true}
		if version >= 4:
			legacy.level = "world"
			legacy.opened_gates = {"world.cleaning.vines": true}
		if version >= 5:
			legacy.upgrade_levels = {"corpse_value": "9007199254740993"}
		if version == 6:
			legacy.upgrade_levels.golden_coin = "20"
		_write_raw(JSON.stringify(legacy))
		await _enter(true)
		_verify_mirror(false, 9007199254740993)
		_check(_hole.get_corpse_value_level() == (9007199254740993 if version >= 5 else 0) and _hole.get_golden_coin_level() == (20 if version == 6 else 0), "legacy preserves exact independent stone levels")
		_check(_world.is_gate_open() == (version >= 4) and _sword.oiled == (version >= 3) and _hole.has_upgrade("corpse_return") == (version >= 2) and _grabber.has_upgrade("charged_throw") == (version >= 2), "legacy preserves paid abilities and gate progress")
		_check(_save.save_game().ok and not _save.read_save().upgrades.mirror and JSON.parse_string(FileAccess.get_file_as_string(_save.save_path)).version == 7, "legacy migrates only on manual save without granting mirror")
	await _enter()
	_check(_hole.apply_upgrade("mirror") and not _flow.get_purchased_upgrades().mirror, "free mirror grant is excluded from paid progress")
	_check(_save.save_game().ok and not _save.read_save().upgrades.mirror, "manual save does not persist free debug mirror")
	await _enter(true)
	_verify_mirror(false, 0)


func _finish() -> void:
	paused = false
	print("MIRROR REGRESSION RESULT: phase=%s passed=%d failed=%d" % [_phase, _passed, _failed])
	quit(0 if _failed == 0 else 1)
