extends Node3D

signal purchase_completed(data: ShopItemData)

@export var player_path: NodePath = NodePath("../Player")
var busy := false
var completed_purchases := 0
var _player: Node3D
var _sword: Sword
var _grabber: Grabber
var _transaction_item: ShopItem
var _result: SwordData
var _tween: Tween
var _message := ""
var _message_remaining := 0.0

@onready var counter: ShopCounter = $Counter
@onready var shelf: Node3D = $Shelf


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	if _player != null:
		_sword = _player.get_node_or_null("Camera3D/WeaponRig/WeaponPivot/Mount") as Sword
		_grabber = _player.get_node_or_null("Camera3D/Grabber") as Grabber
	$Shopkeeper.struck.connect(_on_struck)
	counter.item_placed.connect(func(_item): _show_message("商品已放到台面，左键挥剑命中店长进行强化。"))
	shelf.item_returned.connect(_on_item_returned)
	$Booth/PreviewSword.hide()
	_refresh_shelf()


func _process(delta: float) -> void:
	if _message_remaining > 0.0:
		_message_remaining -= delta
		if _message_remaining <= 0.0:
			_message = ""
	_refresh_shelf()


func _refresh_shelf() -> void:
	shelf.refresh_label(is_instance_valid(_sword) and _sword.oiled)


func _on_struck(source: Node3D) -> void:
	if busy or _sword == null or source != _player:
		return
	if counter.item == null:
		_show_message("台面上没有商品。先从货架拿油，放到小台子上。")
		return
	var product := counter.item.data
	if product == null or not product.is_supported():
		_show_message("这件物品无法用于强化。")
		return
	if _sword.oiled or _sword.data.upgrade_tags.has(product.upgrade_tag):
		_show_message("剑已涂油，无需重复购买。")
		return
	if not Wallet.can_afford(product.price):
		_show_message("金钱不足，需要 %d 金币。" % product.price)
		return
	_result = product.make_upgraded_sword(_sword.data)
	if _result == null:
		_show_message("无法强化这把剑。")
		return
	_transaction_item = counter.item
	busy = true
	counter.locked = true
	_transaction_item.locked = true
	$Shopkeeper.locked = true
	_sword.set_forge_locked(true)
	_grabber.interaction_locked = true
	_show_message("店长正在强化，请稍候。")
	EventBus.forge_started.emit(_transaction_item)
	_start_animation()


func _start_animation() -> void:
	var preview: Node3D = $Booth/PreviewSword
	preview.position = Vector3(0.7, 1.35, -2.95)
	var material := StandardMaterial3D.new()
	material.albedo_color = _result.tint
	material.metallic = 0.5
	$Booth/PreviewSword/Blade.material_override = material
	# Tween 绑定本商店，继承暂停；离开场景自动结束，不会留下异步交付。
	_tween = create_tween()
	_tween.tween_interval(0.3)
	_tween.tween_callback(preview.show)
	_tween.tween_interval(0.3)
	_tween.tween_property($Booth/Curtain, "scale:y", 1.0, 0.5)
	_tween.parallel().tween_property($Booth/Curtain, "position:y", 1.75, 0.5)
	_tween.tween_callback(preview.hide)
	_tween.tween_interval(0.6)
	_tween.tween_property($Booth/Curtain, "scale:y", 0.08, 0.5)
	_tween.parallel().tween_property($Booth/Curtain, "position:y", 3.05, 0.5)
	_tween.tween_callback(preview.show)
	_tween.tween_interval(0.25)
	_tween.tween_callback(_finish_purchase)


func _finish_purchase() -> void:
	if not is_instance_valid(_transaction_item) or counter.item != _transaction_item:
		_end_transaction()
		_show_message("强化已取消，未扣款。")
		return
	var product := _transaction_item.data
	# 交付时才扣款；保存 / 回菜单发生在动画中途时不会损失金币。
	if not Wallet.spend(product.price):
		_end_transaction()
		_show_message("金钱不足，需要 %d 金币。" % product.price)
		return
	_sword.set_sword_data(_result)
	EventBus.sword_granted.emit(_result)
	counter.consume_item()
	shelf.restock()
	completed_purchases += 1
	_end_transaction()
	_show_message("强化完成！剑已涂油，接触火把即可点燃。")
	purchase_completed.emit(product)


func _end_transaction() -> void:
	busy = false
	counter.locked = false
	if is_instance_valid(_transaction_item):
		_transaction_item.locked = false
	_transaction_item = null
	$Shopkeeper.locked = false
	$Booth/PreviewSword.hide()
	if is_instance_valid(_sword):
		_sword.set_forge_locked(false)
	if is_instance_valid(_grabber):
		_grabber.interaction_locked = false


func _exit_tree() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# player_path 对象也可能已退出，不能无条件访问失效引用。
	if is_instance_valid(_sword):
		_sword.set_forge_locked(false)
	if is_instance_valid(_grabber):
		_grabber.interaction_locked = false


func _on_item_returned(item: ShopItem) -> void:
	if is_instance_valid(_grabber) and _grabber.get_held() == item:
		_grabber.drop()
	_show_message("商品已退回货架。")


func _show_message(message: String) -> void:
	_message = message
	_message_remaining = 3.0


func get_status_message() -> String:
	return "店长正在强化，请稍候。" if busy else _message


func get_prompt() -> String:
	if _grabber == null or _sword == null:
		return ""
	if busy:
		return "正在强化"
	if _grabber.is_holding():
		if _grabber.get_held() is ShopItem and counter.can_place_from(_player.get_node("Camera3D")):
			return "右键放到台面，再左键挥剑命中店长"
		return ""
	if counter.item != null and _player.global_position.distance_to(counter.global_position) < 3.5:
		return "左键挥剑命中店长 · 右键可取回台面商品"
	if _player.global_position.distance_to(shelf.global_position) < 3.5:
		return "右键拿油 · %d 金币 · 拿到忏悔室前的小台子" % shelf.item_data.price
	return ""
