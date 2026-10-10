extends Node3D

signal purchase_completed(data: ShopItemData)

@export var player_path: NodePath = NodePath("../Player")
@export var hole_path: NodePath = NodePath("../Hole")
var busy := false
var completed_purchases := 0
var _player: Node3D
var _sword: Sword
var _grabber: Grabber
var _transaction_item: ShopItem
var _result: SwordData
var _hole: Hole
var _shelves: Array[Node3D] = []
var _purchase_counts: Dictionary = {}
var _forging_sword := false
var _transaction_price := 0
var _tween: Tween
var _message := ""
var _message_remaining := 0.0

@onready var counter: ShopCounter = $Counter
@onready var shelf: Node3D = $Shelf


func _ready() -> void:
	_hole = get_node_or_null(hole_path) as Hole
	_player = get_node_or_null(player_path) as Node3D
	if _player != null:
		_sword = _player.get_node_or_null("Camera3D/WeaponRig/WeaponPivot/Mount") as Sword
		_grabber = _player.get_node_or_null("Camera3D/Grabber") as Grabber
	$Shopkeeper.struck.connect(_on_struck)
	counter.item_placed.connect(func(_item): _show_message("商品已放到台面，左键挥剑命中店长进行强化。"))
	for child in get_children():
		if child.has_method("refresh_label") and child.has_method("restock"):
			_shelves.append(child)
			child.item_returned.connect(_on_item_returned)
	$Booth/PreviewSword.hide()
	_refresh_shelf()


func _process(delta: float) -> void:
	if _message_remaining > 0.0:
		_message_remaining -= delta
		if _message_remaining <= 0.0:
			_message = ""
	_refresh_shelf()


func _refresh_shelf() -> void:
	for stock in _shelves:
		var product: ShopItemData = stock.item_data
		var owned := _owns_upgrade(product)
		var count := get_purchase_count(product.id) if product != null else 0
		stock.set_purchase_count(count)
		if product != null and product.upgrade_target != ShopItemData.UpgradeTarget.SWORD:
			stock.sold_out = (owned and not product.is_repeatable()) or (product.purchase_limit > 0 and count >= product.purchase_limit) or product.get_price(count) < 0
		stock.refresh_label(owned)


func get_purchase_count(product_id: StringName) -> int:
	return _purchase_counts.get(product_id, 0)


func get_purchased_upgrades() -> Dictionary:
	# 以完成交付的购买记录为准，调试场景免费解锁不进入存档。
	var upgrades := SaveGame.empty_upgrades()
	for product_id in SaveGame.UPGRADE_IDS:
		upgrades[product_id] = get_purchase_count(StringName(product_id)) > 0
	return upgrades


func get_purchased_upgrade_levels() -> Dictionary:
	var levels := SaveGame.empty_upgrade_levels()
	for product_id in SaveGame.LEVEL_UPGRADE_IDS:
		levels[product_id] = get_purchase_count(StringName(product_id))
	return levels


func get_product_price(product: ShopItemData) -> int:
	return product.get_price(get_purchase_count(product.id)) if product != null else -1


## 必须在整个世界 ready 后调用：洞的出口与离房触发器也是世界的子节点。
func restore_purchased_upgrades(upgrades: Dictionary, levels: Dictionary = {}) -> bool:
	var purchased: Array[Node3D] = []
	if not levels.is_empty() and (not SaveGame.is_valid_upgrade_levels(levels) or not is_instance_valid(_hole)):
		return false
	for product_id in levels:
		if levels[product_id] == 0:
			continue
		var matching: Node3D = _find_shelf(StringName(product_id))
		if matching == null or not matching.item_data.is_supported() or not matching.item_data.is_repeatable() or not is_instance_valid(_hole):
			return false
		if matching.item_data.purchase_limit > 0 and levels[product_id] > matching.item_data.purchase_limit:
			return false
	for product_id in SaveGame.UPGRADE_IDS:
		if not upgrades.get(product_id, false):
			continue
		var matching: Node3D
		for stock in _shelves:
			if stock.item_data != null and stock.item_data.id == StringName(product_id):
				matching = stock
				break
		if matching == null or not matching.item_data.is_supported():
			return false
		var product: ShopItemData = matching.item_data
		if not _owns_upgrade(product):
			if product.upgrade_target == ShopItemData.UpgradeTarget.SWORD:
				if not is_instance_valid(_sword) or product.make_upgraded_sword(_sword.data) == null:
					return false
			else:
				var target: Node3D = _hole if product.upgrade_target == ShopItemData.UpgradeTarget.HOLE else _grabber
				if not is_instance_valid(target) or not target.can_apply_upgrade(product.upgrade_tag):
					return false
		purchased.append(matching)
	# 先验证全部目标，再交付；恢复不扣款、不发出交易事件、不播放购买动画。
	for stock in purchased:
		var product: ShopItemData = stock.item_data
		if not _owns_upgrade(product):
			if product.upgrade_target == ShopItemData.UpgradeTarget.SWORD:
				_sword.set_sword_data(product.make_upgraded_sword(_sword.data))
			else:
				var target: Node3D = _hole if product.upgrade_target == ShopItemData.UpgradeTarget.HOLE else _grabber
				if not target.apply_upgrade(product.upgrade_tag):
					return false
		_purchase_counts[product.id] = 1
		# 油沿用成交后补货、已强化拒绝再次购买的规则；另外两件售罄移除。
		if product.upgrade_target != ShopItemData.UpgradeTarget.SWORD:
			stock.restore_purchase()
	for product_id in levels:
		if not is_instance_valid(_hole) or not _hole.restore_upgrade_level(product_id, levels[product_id]):
			return false
		_purchase_counts[StringName(product_id)] = levels[product_id]
		var stock := _find_shelf(StringName(product_id))
		if stock != null and stock.item_data.purchase_limit > 0 and levels[product_id] >= stock.item_data.purchase_limit:
			stock.set_purchase_count(levels[product_id])
			stock.restore_purchase()
	_refresh_shelf()
	for product_id in levels:
		var stock := _find_shelf(StringName(product_id))
		if stock != null:
			stock.restock()
	return true


func _find_shelf(product_id: StringName) -> Node3D:
	for stock in _shelves:
		if stock.item_data != null and stock.item_data.id == product_id:
			return stock
	return null


func _owns_upgrade(product: ShopItemData) -> bool:
	if product == null:
		return false
	if product.upgrade_target == ShopItemData.UpgradeTarget.HOLE:
		return is_instance_valid(_hole) and _hole.has_upgrade(product.upgrade_tag)
	if product.upgrade_target == ShopItemData.UpgradeTarget.GRABBER:
		return is_instance_valid(_grabber) and _grabber.has_upgrade(product.upgrade_tag)
	return is_instance_valid(_sword) and (_sword.oiled or (_sword.data != null and _sword.data.upgrade_tags.has(product.upgrade_tag)))


func _purchase_error(product: ShopItemData) -> String:
	if product == null or not product.is_supported():
		return "这件物品无法用于强化。"
	var count := get_purchase_count(product.id)
	if (_owns_upgrade(product) and not product.is_repeatable()) or (product.purchase_limit > 0 and count >= product.purchase_limit):
		return "剑已涂油，无需重复购买。" if product.upgrade_target == ShopItemData.UpgradeTarget.SWORD else "%s已启用，限购 %d 次。" % [product.display_name, product.purchase_limit]
	if product.upgrade_target == ShopItemData.UpgradeTarget.HOLE and (not is_instance_valid(_hole) or not _hole.can_apply_upgrade(product.upgrade_tag)):
		return "洞无法继续强化此升级。" if product.is_repeatable() else "尸体出口尚未配置，无法购买此升级。"
	if product.upgrade_target == ShopItemData.UpgradeTarget.GRABBER and (not is_instance_valid(_grabber) or not _grabber.can_apply_upgrade(product.upgrade_tag)):
		return "搬运能力尚未就绪，无法购买此升级。"
	var price := get_product_price(product)
	if price < 0:
		return "此升级已达到可计算范围。"
	if not Wallet.can_afford(price):
		return "金钱不足，需要 %d 金币。" % price
	return ""


func _on_struck(source: Node3D) -> void:
	if busy or _sword == null or source != _player:
		return
	if counter.item == null:
		_show_message("台面上没有商品。先从货架拿商品，放到小台子上。")
		return
	var product := counter.item.data
	var error := _purchase_error(product)
	if not error.is_empty():
		_show_message(error)
		return
	_forging_sword = product.upgrade_target == ShopItemData.UpgradeTarget.SWORD
	_result = product.make_upgraded_sword(_sword.data) if _forging_sword else null
	if _forging_sword and _result == null:
		_show_message("无法强化这把剑。")
		return
	_transaction_item = counter.item
	_transaction_price = get_product_price(product)
	busy = true
	counter.locked = true
	_transaction_item.locked = true
	$Shopkeeper.locked = true
	if _forging_sword:
		_sword.set_forge_locked(true)
	else:
		_sword.set_interaction_locked(true)
	_grabber.interaction_locked = true
	_show_message(_working_message())
	EventBus.forge_started.emit(_transaction_item)
	_start_animation()


func _start_animation() -> void:
	var preview: Node3D = $Booth/PreviewSword
	preview.position = Vector3(0.7, 1.35, -2.95)
	if _forging_sword:
		var material := StandardMaterial3D.new()
		material.albedo_color = _result.tint
		material.metallic = 0.5
		$Booth/PreviewSword/Blade.material_override = material
	# Tween 绑定本商店，继承暂停；离开场景自动结束，不会留下异步交付。
	_tween = create_tween()
	_tween.tween_interval(0.3)
	if _forging_sword:
		_tween.tween_callback(preview.show)
	_tween.tween_interval(0.3)
	_tween.tween_property($Booth/Curtain, "scale:y", 1.0, 0.5)
	_tween.parallel().tween_property($Booth/Curtain, "position:y", 1.75, 0.5)
	_tween.tween_callback(preview.hide)
	_tween.tween_interval(0.6)
	_tween.tween_property($Booth/Curtain, "scale:y", 0.08, 0.5)
	_tween.parallel().tween_property($Booth/Curtain, "position:y", 3.05, 0.5)
	if _forging_sword:
		_tween.tween_callback(preview.show)
	_tween.tween_interval(0.25)
	_tween.tween_callback(_finish_purchase)


func _finish_purchase() -> void:
	if not is_instance_valid(_transaction_item) or counter.item != _transaction_item:
		_end_transaction()
		_show_message("强化已取消，未扣款。")
		return
	var product := _transaction_item.data
	var error := _purchase_error(product)
	if not error.is_empty():
		_end_transaction()
		_show_message(error)
		return
	# 交付时才扣款；保存 / 回菜单发生在动画中途时不会损失金币。
	if get_product_price(product) != _transaction_price:
		_end_transaction()
		_show_message("商品价格已变化，请重新交付。")
		return
	var paid_price := _transaction_price
	if not Wallet.spend(paid_price):
		_end_transaction()
		_show_message("金钱不足，需要 %d 金币。" % paid_price)
		return
	if _forging_sword:
		_sword.set_sword_data(_result)
		EventBus.sword_granted.emit(_result)
	else:
		var delivered := _hole.apply_upgrade(product.upgrade_tag) if product.upgrade_target == ShopItemData.UpgradeTarget.HOLE else _grabber.apply_upgrade(product.upgrade_tag)
		if not delivered:
			Wallet.add(paid_price)
			_end_transaction()
			_show_message("升级已取消，未扣款。")
			return
	_purchase_counts[product.id] = get_purchase_count(product.id) + 1
	counter.consume_item()
	_refresh_shelf()
	for stock in _shelves:
		if stock.item_data != null and stock.item_data.id == product.id:
			stock.restock()
	completed_purchases += 1
	_end_transaction()
	match product.upgrade_target:
		ShopItemData.UpgradeTarget.SWORD:
			_show_message("强化完成！剑已涂油，接触火把即可点燃。")
		ShopItemData.UpgradeTarget.HOLE:
			if product.upgrade_tag == "golden_coin":
				var level := get_purchase_count(product.id)
				var next := "已满级。" if level >= product.purchase_limit else "下次购买 %d 金币。" % get_product_price(product)
				_show_message("点金石头升至 %d 级！点金概率 %d%%，命中金币价值 ×10，%s" % [level, level * 5, next])
			elif product.is_repeatable():
				var level := get_purchase_count(product.id)
				_show_message("不点金石头升至 %d 级！每具尸体价值 +%d，下次购买 %d 金币。" % [level, level, get_product_price(product)])
			else:
				_show_message("灵魂鸡蛋已启用！离开任一房间，该房间遗留尸体将自动入洞。")
		ShopItemData.UpgradeTarget.GRABBER:
			_show_message("棒球手套已启用！拿起尸体后长按右键，松开投出。")
	purchase_completed.emit(product)


func _end_transaction() -> void:
	busy = false
	counter.locked = false
	if is_instance_valid(_transaction_item):
		_transaction_item.locked = false
	_transaction_item = null
	_transaction_price = 0
	$Shopkeeper.locked = false
	$Booth/PreviewSword.hide()
	if is_instance_valid(_sword):
		if _forging_sword:
			_sword.set_forge_locked(false)
		else:
			_sword.set_interaction_locked(false)
	_forging_sword = false
	_result = null
	if is_instance_valid(_grabber):
		_grabber.interaction_locked = false


func _exit_tree() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# player_path 对象也可能已退出，不能无条件访问失效引用。
	if is_instance_valid(_sword):
		if _forging_sword:
			_sword.set_forge_locked(false)
		else:
			_sword.set_interaction_locked(false)
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
	return _working_message() if busy else _message


func _working_message() -> String:
	if _forging_sword:
		return "店长正在强化，请稍候。"
	if is_instance_valid(_transaction_item) and _transaction_item.data.upgrade_target == ShopItemData.UpgradeTarget.GRABBER:
		return "店长正在配置投掷能力，请稍候。"
	if is_instance_valid(_transaction_item) and _transaction_item.data.is_repeatable():
		return "店长正在强化点金概率，请稍候。" if _transaction_item.data.upgrade_tag == "golden_coin" else "店长正在强化尸体价值，请稍候。"
	return "店长正在开启尸体出口，请稍候。"


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
	var nearest: Node3D
	var distance := 3.5
	var camera := _player.get_node("Camera3D") as Camera3D
	for stock in _shelves:
		# 相邻货架不能让身后的商品抢走当前朝向的操作提示。
		var offset: Vector3 = stock.get_node("ItemSpawn").global_position - camera.global_position
		if offset.dot(-camera.global_basis.z) <= 0.0:
			continue
		var candidate := _player.global_position.distance_to(stock.global_position)
		if candidate < distance:
			nearest = stock
			distance = candidate
	if nearest != null and nearest.item_data != null:
		if nearest.sold_out:
			if nearest.item_data.is_repeatable():
				return "%s已满级 · %s" % [nearest.item_data.display_name, nearest.item_data.get_level_description(nearest.purchase_count)]
			return "%s已售罄 · 限购 %d 次" % [nearest.item_data.display_name, nearest.item_data.purchase_limit]
		return "右键拿%s · %d 金币 · 拿到忏悔室前的小台子" % [nearest.item_data.display_name, get_product_price(nearest.item_data)]
	return ""
