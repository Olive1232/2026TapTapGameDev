extends Node

## 单存档位，保存金币、已购升级、重复购买等级与永久通路；兼容 v1—v6。
const FORMAT_VERSION := 7
## 保存、校验、读取与商店恢复共用清单，新增已实现升级时在此注册。
const UPGRADE_IDS := ["oil", "corpse_return", "charged_throw", "mirror"]
const VERSION_2_UPGRADE_IDS := ["corpse_return", "charged_throw"]
const VERSION_3_TO_6_UPGRADE_IDS := ["oil", "corpse_return", "charged_throw"]
const LEVEL_UPGRADE_IDS := ["corpse_value", "golden_coin"]
const VERSION_5_LEVEL_UPGRADE_IDS := ["corpse_value"]
const AtomicFile := preload("res://scripts/persistence/atomic_file.gd")
const LevelProgress := preload("res://scripts/persistence/level_progress.gd")
var save_path: String = "user://savegame.json"


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func empty_upgrades() -> Dictionary:
	var upgrades := {}
	for product_id in UPGRADE_IDS:
		upgrades[product_id] = false
	return upgrades


func empty_upgrade_levels() -> Dictionary:
	var levels := {}
	for product_id in LEVEL_UPGRADE_IDS:
		levels[product_id] = 0
	return levels


func is_valid_upgrade_levels(levels: Variant) -> bool:
	if not levels is Dictionary or levels.size() != LEVEL_UPGRADE_IDS.size():
		return false
	for product_id in LEVEL_UPGRADE_IDS:
		var count: Variant = levels.get(product_id)
		if not count is int or count < 0 or count > ShopItemData.get_level_limit(product_id):
			return false
	return true


func save_game() -> Dictionary:
	var progress := GameFlow.get_level_snapshot()
	if not progress.ok:
		return progress
	var levels := GameFlow.get_purchased_upgrade_levels()
	if not is_valid_upgrade_levels(levels):
		return {"ok": false, "message": "升级等级无效，未覆盖上次存档。"}
	var saved_levels := {}
	for product_id in LEVEL_UPGRADE_IDS:
		saved_levels[product_id] = str(levels[product_id])
	var data := {
		"version": FORMAT_VERSION,
		"coins": str(Wallet.total),
		"upgrades": GameFlow.get_purchased_upgrades(),
		"upgrade_levels": saved_levels,
		"level": progress.level,
		"opened_gates": progress.opened_gates,
	}
	var error := AtomicFile.write_text(save_path, JSON.stringify(data, "\t"))
	if error != OK:
		return {"ok": false, "message": "存档失败，未覆盖上次存档。请检查磁盘空间与写入权限。"}
	return {"ok": true, "message": "存档成功 · 已保存 %d 金币、已购升级与关卡进度" % Wallet.total}


func read_save() -> Dictionary:
	if not has_save():
		return {"ok": false, "message": "暂无存档，请先新建游戏。"}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "无法读取存档。"}
	# 单存档记录很小，拒绝异常的大文件。
	if file.get_length() > 4096:
		return _invalid_save()
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return _invalid_save()
	var data: Dictionary = json.data
	var version: Variant = data.get("version")
	if not (version is int or version is float) or (version != 1 and version != 2 and version != 3 and version != 4 and version != 5 and version != 6 and version != FORMAT_VERSION):
		return {"ok": false, "message": "存档版本不兼容。"}
	var coins: Variant = data.get("coins")
	# 十进制字符串保留 int64 精度；往返校验也拒绝溢出和负值。
	if not coins is String or not coins.is_valid_int():
		return _invalid_save()
	var amount: int = coins.to_int()
	if amount < 0 or str(amount) != coins:
		return _invalid_save()
	var upgrades := empty_upgrades()
	if version != 1:
		var expected_ids: Array = UPGRADE_IDS
		if version == 2:
			expected_ids = VERSION_2_UPGRADE_IDS
		elif version != FORMAT_VERSION:
			expected_ids = VERSION_3_TO_6_UPGRADE_IDS
		var saved_upgrades: Variant = data.get("upgrades")
		if not saved_upgrades is Dictionary or saved_upgrades.size() != expected_ids.size():
			return _invalid_save()
		for product_id in expected_ids:
			if not saved_upgrades.get(product_id) is bool:
				return _invalid_save()
			upgrades[product_id] = saved_upgrades[product_id]
	var level := "world"
	var opened_gates := {}
	var upgrade_levels := empty_upgrade_levels()
	if version == 5 or version == 6 or version == FORMAT_VERSION:
		var expected_ids: Array = VERSION_5_LEVEL_UPGRADE_IDS if version == 5 else LEVEL_UPGRADE_IDS
		var saved_levels: Variant = data.get("upgrade_levels")
		if not saved_levels is Dictionary or saved_levels.size() != expected_ids.size():
			return _invalid_save()
		for product_id in expected_ids:
			var count: Variant = saved_levels.get(product_id)
			if not count is String or not count.is_valid_int() or str(count.to_int()) != count:
				return _invalid_save()
			upgrade_levels[product_id] = count.to_int()
		if not is_valid_upgrade_levels(upgrade_levels):
			return _invalid_save()
	if version == 4 or version == 5 or version == 6 or version == FORMAT_VERSION:
		var saved_level: Variant = data.get("level")
		var saved_gates: Variant = data.get("opened_gates")
		if not saved_level is String or not GameFlow.SAVE_LEVELS.has(saved_level) or not LevelProgress.is_valid_progress(saved_gates):
			return _invalid_save()
		# 白模没有商店，不接受无法在该入口恢复的购买记录。
		if saved_level == "mechanism_lab" and (true in upgrades.values() or upgrade_levels.values().any(func(count): return count > 0)):
			return _invalid_save()
		level = saved_level
		opened_gates = saved_gates
	return {"ok": true, "coins": amount, "upgrades": upgrades, "upgrade_levels": upgrade_levels, "level": level, "opened_gates": opened_gates, "message": "载入成功"}


func _invalid_save() -> Dictionary:
	return {"ok": false, "message": "存档已损坏，无法载入。可以新建游戏。"}
