extends Node

## 单存档位，仅保存钱包。读取和校验成功后才允许 GameFlow 修改钱包。
const FORMAT_VERSION := 1
const AtomicFile := preload("res://scripts/persistence/atomic_file.gd")
var save_path: String = "user://savegame.json"


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func save_game() -> Dictionary:
	var data := {"version": FORMAT_VERSION, "coins": str(Wallet.total)}
	var error := AtomicFile.write_text(save_path, JSON.stringify(data, "\t"))
	if error != OK:
		return {"ok": false, "message": "存档失败，未覆盖上次存档。请检查磁盘空间与写入权限。"}
	return {"ok": true, "message": "存档成功 · 已保存 %d 金币" % Wallet.total}


func read_save() -> Dictionary:
	if not has_save():
		return {"ok": false, "message": "暂无存档，请先新建游戏。"}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "无法读取存档。"}
	# 本阶段只有两个字段，拒绝异常的大文件。
	if file.get_length() > 4096:
		return _invalid_save()
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return _invalid_save()
	var data: Dictionary = json.data
	var version: Variant = data.get("version")
	if not (version is int or version is float) or version != FORMAT_VERSION:
		return {"ok": false, "message": "存档版本不兼容。"}
	var coins: Variant = data.get("coins")
	# 十进制字符串保留 int64 精度；往返校验也拒绝溢出和负值。
	if not coins is String or not coins.is_valid_int():
		return _invalid_save()
	var amount: int = coins.to_int()
	if amount < 0 or str(amount) != coins:
		return _invalid_save()
	return {"ok": true, "coins": amount, "message": "载入成功"}


func _invalid_save() -> Dictionary:
	return {"ok": false, "message": "存档已损坏，无法载入。可以新建游戏。"}
