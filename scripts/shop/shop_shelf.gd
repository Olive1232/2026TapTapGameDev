extends Node3D

signal item_returned(item: ShopItem)
const ITEM_SCENE := preload("res://scenes/shop/shop_item.tscn")
@export var item_data: ShopItemData = preload("res://resources/shop/shop_item_oil.tres")
var item: ShopItem
var sold_out := false
var purchase_count := 0


func _ready() -> void:
	restock()


func restock() -> void:
	if sold_out:
		return
	if is_instance_valid(item) and not item.is_queued_for_deletion():
		return
	if item_data == null:
		return
	item = ITEM_SCENE.instantiate() as ShopItem
	item.data = item_data
	item.purchase_count = purchase_count
	item.transform = $ItemSpawn.transform
	add_child(item)
	item.returned_to_shelf.connect(func(candidate): item_returned.emit(candidate))


func set_purchase_count(count: int) -> void:
	purchase_count = count
	if is_instance_valid(item) and not item.is_queued_for_deletion():
		item.set_purchase_count(count)


func get_item() -> ShopItem:
	return item if is_instance_valid(item) and not item.is_queued_for_deletion() else null


## 新世界载入已购进度时，移除 _ready 中生成的占位商品。
func restore_purchase() -> void:
	sold_out = true
	if is_instance_valid(item):
		item.queue_free()
	item = null
	refresh_label(true)


func refresh_label(oiled: bool) -> void:
	if item_data == null:
		$Sign.text = "货架未配置"
		return
	var price := item_data.get_price(purchase_count)
	if item_data.is_repeatable() and sold_out:
		$Sign.text = "%s\n%s\n已满级 · 限购 %d 次" % [item_data.display_name, item_data.get_level_description(purchase_count), item_data.purchase_limit]
		_append_description()
		return
	if item_data.is_repeatable() and not sold_out:
		var state := "可以买得起" if Wallet.can_afford(price) else "金钱不足"
		$Sign.text = "%s · %d 金币\n%s\n%s · 可重复购买 · 右键拿起" % [item_data.display_name, price, item_data.get_level_description(purchase_count), state]
		_append_description()
		return
	if sold_out:
		$Sign.text = "%s · %d 金币\n已售罄 · 限购 %d 次" % [item_data.display_name, price, item_data.purchase_limit]
		_append_description()
		return
	var state := "已强化，无需重复购买" if oiled else ("可以买得起" if Wallet.can_afford(price) else "金钱不足")
	if item_data.upgrade_target != ShopItemData.UpgradeTarget.SWORD:
		state += " · 限购 %d 次" % item_data.purchase_limit
	$Sign.text = "%s · %d 金币\n%s · 右键拿起" % [item_data.display_name, price, state]
	_append_description()


func _append_description() -> void:
	if not item_data.description.is_empty():
		$Sign.text += "\n" + item_data.description
