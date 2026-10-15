extends Node3D

## 正式入口保留原样 GLB；游戏流程与存档由场景自身管理。
const OIL := preload("res://resources/shop/shop_item_oil.tres")
var _purchased_upgrades := {}
var _upgrade_levels := {}

@onready var _sword: Sword = $Player/Camera3D/WeaponRig/WeaponPivot/Mount
@onready var _grabber: Grabber = $Player/Camera3D/Grabber
@onready var _bottom_text: BottomText = $HUD/BottomText


func _ready() -> void:
	_purchased_upgrades = SaveGame.empty_upgrades()
	_upgrade_levels = SaveGame.empty_upgrade_levels()
	CoinPool.set_host(self)
	_update_guidance()


func _process(_delta: float) -> void:
	_update_guidance()


func _update_guidance() -> void:
	var message := "WASD 移动 · 空格跳跃 · 左键挥剑 · 右键拿放 · Esc 暂停菜单"
	var throw_prompt := _grabber.get_throw_prompt()
	if not throw_prompt.is_empty():
		message += "\n" + throw_prompt
	_bottom_text.set_message(&"guidance", message, BottomText.GUIDANCE)


func get_purchased_upgrades() -> Dictionary:
	return _purchased_upgrades.duplicate()


func get_purchased_upgrade_levels() -> Dictionary:
	return _upgrade_levels.duplicate()


## 商店 / 洞尚未放置时仍完整保留旧档记录，不因换地图抹掉已购能力。
func restore_purchased_upgrades(upgrades: Dictionary, levels: Dictionary = {}) -> bool:
	var next_upgrades := SaveGame.empty_upgrades()
	for id in upgrades:
		if not next_upgrades.has(id) or not upgrades[id] is bool:
			return false
		next_upgrades[id] = upgrades[id]
	var next_levels := SaveGame.empty_upgrade_levels()
	for id in levels:
		if not next_levels.has(id):
			return false
		next_levels[id] = levels[id]
	if not SaveGame.is_valid_upgrade_levels(next_levels):
		return false
	var oiled_sword: SwordData
	if next_upgrades.oil and not _sword.oiled:
		oiled_sword = OIL.make_upgraded_sword(_sword.data)
		if oiled_sword == null:
			return false
	if oiled_sword != null:
		_sword.set_sword_data(oiled_sword)
	if next_upgrades.charged_throw and not _grabber.charged_throw_enabled:
		_grabber.apply_upgrade("charged_throw")
	_purchased_upgrades = next_upgrades
	_upgrade_levels = next_levels
	return true
