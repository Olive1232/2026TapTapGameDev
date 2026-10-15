extends Node3D

## 正式入口保留原样 GLB；游戏流程与存档由场景自身管理。
const OIL := preload("res://resources/shop/shop_item_oil.tres")
const SHOP_CONTROLLER := preload("res://scripts/shop/shop_room.gd")
const WORLD_DIALOGUE := preload("res://scripts/dialogue/world_dialogue.gd")
var _purchased_upgrades := {}
var _upgrade_levels := {}
var _shop: Node3D

@onready var _sword: Sword = $Player/Camera3D/WeaponRig/WeaponPivot/Mount
@onready var _grabber: Grabber = $Player/Camera3D/Grabber
@onready var _bottom_text: BottomText = $HUD/BottomText
@onready var _hole: Hole = $Hole


func _ready() -> void:
	_purchased_upgrades = SaveGame.empty_upgrades()
	_upgrade_levels = SaveGame.empty_upgrade_levels()
	CoinPool.set_host(self)
	# 部件沿用关卡里的原节点与变换，只在运行时补上交易控制器。
	_shop = SHOP_CONTROLLER.new()
	_shop.name = "ShopController"
	_shop.counter_path = NodePath("../Counter")
	_shop.shopkeeper_path = NodePath("../Shopkeeper")
	_shop.booth_path = NodePath("../Booth")
	_shop.shelf_path = NodePath("../Shelf")
	_shop.shelf_paths.assign([NodePath("../Shelf"), NodePath("../CorpseValueShelf"), NodePath("../GoldenCoinShelf"), NodePath("../MirrorShelf"), NodePath("../CorpseReturnShelf"), NodePath("../ChargedThrowShelf")])
	add_child(_shop)
	_shop.purchase_completed.connect(_on_shop_purchase_completed)
	# 与商店控制器一样由入口负责接线，避免场景保存丢失临时添加的剧情节点。
	if not has_node("WorldDialogue"):
		var dialogue := WORLD_DIALOGUE.new()
		dialogue.name = "WorldDialogue"
		add_child(dialogue)
	_update_guidance()


func _process(_delta: float) -> void:
	_update_guidance()


func _update_guidance() -> void:
	var message := "WASD 移动 / 攀爬 · 左键挥剑 · 右键拿放 · Esc 暂停菜单"
	var throw_prompt := _grabber.get_throw_prompt()
	if not throw_prompt.is_empty():
		message += "\n" + throw_prompt
	_bottom_text.set_message(&"guidance", message, BottomText.GUIDANCE)
	_bottom_text.set_message(&"shop_description", _shop.get_context_text(), BottomText.DESCRIPTION)
	_bottom_text.set_message(&"shop_feedback", _shop.get_status_message(), BottomText.FEEDBACK)


func _on_shop_purchase_completed(product: ShopItemData) -> void:
	var id := str(product.id)
	if product.is_repeatable():
		_upgrade_levels[id] = _shop.get_purchase_count(product.id)
	else:
		_purchased_upgrades[id] = true


func get_purchased_upgrades() -> Dictionary:
	return _purchased_upgrades.duplicate()


func get_purchased_upgrade_levels() -> Dictionary:
	return _upgrade_levels.duplicate()


## 恢复当前实体的能力和各货架购买记录。
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
	if next_upgrades.mirror and not _hole.has_upgrade("mirror"):
		_hole.apply_upgrade("mirror")
	elif not next_upgrades.mirror:
		_hole.upgrade_tags.erase("mirror")
	_hole.restore_upgrade_level("corpse_value", next_levels.corpse_value)
	_hole.restore_upgrade_level("golden_coin", next_levels.golden_coin)
	# 编辑关卡时若暂时移除出口，仍保留旧购买记录；正常配置恢复出口能力。
	var available_upgrades := next_upgrades.duplicate()
	if not _hole.has_upgrade("corpse_return") and not _hole.can_apply_upgrade("corpse_return"):
		available_upgrades.corpse_return = false
	if not _shop.restore_purchased_upgrades(available_upgrades, next_levels):
		return false
	_purchased_upgrades = next_upgrades
	_upgrade_levels = next_levels
	return true
