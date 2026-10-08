extends Node3D

signal item_returned(item: ShopItem)
const ITEM_SCENE := preload("res://scenes/shop/shop_item.tscn")
@export var item_data: ShopItemData = preload("res://resources/shop/shop_item_oil.tres")
var item: ShopItem


func _ready() -> void:
	restock()


func restock() -> void:
	if is_instance_valid(item) and not item.is_queued_for_deletion():
		return
	if item_data == null:
		return
	item = ITEM_SCENE.instantiate() as ShopItem
	item.data = item_data
	item.transform = $ItemSpawn.transform
	add_child(item)
	item.returned_to_shelf.connect(func(candidate): item_returned.emit(candidate))


func get_item() -> ShopItem:
	return item if is_instance_valid(item) and not item.is_queued_for_deletion() else null


func refresh_label(oiled: bool) -> void:
	if item_data == null:
		$Sign.text = "货架未配置"
		return
	var state := "已强化，无需重复购买" if oiled else ("可以买得起" if Wallet.can_afford(item_data.price) else "金钱不足")
	$Sign.text = "%s · %d 金币\n%s · 右键拿起" % [item_data.display_name, item_data.price, state]
