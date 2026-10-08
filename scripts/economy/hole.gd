class_name Hole
extends Node3D

## 洞 —— 经济循环的中枢。
##
## 流程（对应策划需求）：
##   物品落入判定区 → 销毁并累加价值 → 2 秒内无新物品进入 → 结算
##   → 按「总价值 × 随机修正」喷出等价值的整数钱币 → 钱币飞向玩家并被收进钱包
##
## 其它规则：
##   - 玩家掉进洞里会被**踢出**（拉回出口点）
##   - 非玩家物品受到**与距离成反比的吸引力**（越近吸力越大，见文档 N1 决策）
##   - 洞的形态可随升级改变（M13-9，尚未做）

## 洞开始判定的等待时间（秒）——「物品停止进入的 2 秒内开始判定」。
const SETTLE_DELAY := 2.0

## 结算时总价值的随机修正范围（占位值，等策划给 N2 的正式数值）。
const RANDOM_MODIFIER_MIN := 0.9
const RANDOM_MODIFIER_MAX := 1.15

## 吸引力：物体在洞心这个距离内的吸力为 1.0，越近越强。
const ATTRACTION_REFERENCE_DISTANCE := 4.0
## 吸力上限倍率，避免贴脸时速度爆炸。
const ATTRACTION_MAX_SCALE := 6.0
## 吸引力加速度基准（米/秒²）。实际 = 本值 × 距离倍率。
## 太小的话物品会被摩擦力拖住、慢慢蹭很久才到洞口。
const ATTRACTION_ACCEL := 26.0
## 洞的吞噬半径。取得比洞口(1.35)略大：只要蹭到洞口边沿就算掉进去了。
## 早期取 0.85 太小——物品会被吸到洞口附近却掉进缝里，永远碰不到判定圈。
const SWALLOW_RADIUS := 1.5
## 吞噬的高度上限：物品在这个高度以下、水平距离够近，就判定入洞。
const SWALLOW_MAX_HEIGHT := 0.8
## 玩家掉入的判定半径。应与洞口实际大小匹配，太大会导致站在洞边就被踢。
const PLAYER_FALL_RADIUS := 1.3
## 玩家掉入的判定高度：低于这个高度且水平距离够近，就算掉进去了。
## 玩家碰撞盒中心在 y=1、脚底在 y=0，所以落到 0.35 以下就是真的陷进去了。
const PLAYER_FALL_HEIGHT := 0.35

## 献祭配置表。留空则用代码内置的占位规则。
@export var offering_table: OfferingTable
## 玩家掉进去后被拉回的出口点（NodePath，指向场景里的某个 Node3D）。
## 留空则使用本节点上方 1.6 米处。
@export var exit_point_path: NodePath
## 是否把调试状态打到控制台。
@export var debug_print: bool = false

## 关卡可按实际模型口径适配；旧场景保持原默认值与高度规则。
@export_range(0.1, 10.0, 0.1) var swallow_radius: float = SWALLOW_RADIUS
@export_range(0.1, 10.0, 0.1) var player_fall_radius: float = PLAYER_FALL_RADIUS

## 待结算的投入价值（已累加，尚未喷发）。
var pending_value: int = 0
## 距离结算还剩多少秒。<=0 表示没有待结算内容。
var time_until_erupt: float = 0.0

var _rng := RandomNumberGenerator.new()
var _player: Node3D = null
## 解析后的出口点。由 exit_point_path 在 _ready 里解析。
var _exit_point: Node3D = null


func _ready() -> void:
	_rng.randomize()
	if offering_table == null:
		offering_table = _default_table()
	# 碰撞层/掩码已在 hole.tscn 里设好，这里只做一件事：
	# 接上「物品进入吞噬区」的信号。
	# 注意：不要在这里写 collision_mask——那会覆盖场景里的配置，
	# 早期版本就因为这里写错值导致尸体探测不到。
	var swallow := get_node_or_null("SwallowZone") as Area3D
	if swallow != null and not swallow.body_entered.is_connected(_on_body_entered_swallow):
		swallow.body_entered.connect(_on_body_entered_swallow)
	if not exit_point_path.is_empty():
		_exit_point = get_node_or_null(exit_point_path) as Node3D
	# 钱币挂到场景根，便于随场景释放。
	var host := get_tree().current_scene
	CoinPool.set_host(host if host != null else get_parent())
	# 延迟一帧找玩家，确保场景已就绪。
	call_deferred("_find_player")


func _find_player() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	_player = _search_player(root)


func _search_player(node: Node) -> Node3D:
	for child in node.get_children():
		if child is Node3D and child.has_method("set_carry_weight"):
			return child as Node3D
		var found := _search_player(child)
		if found != null:
			return found
	return null


## 代码内置的占位规则（策划表未到位时使用）。
func _default_table() -> OfferingTable:
	var t := OfferingTable.new()
	t.qualities = _default_qualities()

	var r1 := OfferingTable.Rule.new()
	r1.value_min = 0
	r1.value_max = 6
	r1.value_multiplier = 1.5
	r1.coin_count_min = 4
	r1.coin_count_max = 8
	r1.quality_weights = PackedFloat32Array([1.0, 0.2, 0.0])
	t.rules.append(r1)

	var r2 := OfferingTable.Rule.new()
	r2.value_min = 6
	r2.value_max = 30
	r2.value_multiplier = 1.5
	r2.coin_count_min = 8
	r2.coin_count_max = 18
	r2.quality_weights = PackedFloat32Array([1.0, 0.45, 0.1])
	t.rules.append(r2)

	var r3 := OfferingTable.Rule.new()
	r3.value_min = 30
	r3.value_max = 999999
	r3.value_multiplier = 1.6
	r3.coin_count_min = 16
	r3.coin_count_max = 34
	r3.quality_weights = PackedFloat32Array([1.0, 0.6, 0.3])
	t.rules.append(r3)
	return t


## 三档占位品质：铜 1 / 银 5 / 金 25（进制刚好，便于凑出任意总额）。
func _default_qualities() -> Array[CoinQuality]:
	var list: Array[CoinQuality] = []
	list.append(CoinQuality.make(&"copper", "铜币", 1, Color(0.76, 0.48, 0.22), 0))
	list.append(CoinQuality.make(&"silver", "银币", 5, Color(0.80, 0.83, 0.88), 1))
	list.append(CoinQuality.make(&"gold", "金币", 25, Color(1.0, 0.84, 0.28), 2))
	return list


## 把子节点的 Area3D 收尾（碰撞层在场景文件里设，这里只确保行为正确）。
func _setup_areas() -> void:
	for area_name in ["SwallowZone", "AttractZone"]:
		var area := get_node_or_null(area_name) as Area3D
		if area == null:
			continue
		area.collision_layer = 0
		area.collision_mask = CollisionLayers.PICKUP | CollisionLayers.PLAYER
		area.monitoring = true
		area.monitorable = false
	var swallow := get_node_or_null("SwallowZone") as Area3D
	if swallow != null and not swallow.body_entered.is_connected(_on_body_entered_swallow):
		swallow.body_entered.connect(_on_body_entered_swallow)


func _process(delta: float) -> void:
	_attract_items(delta)
	_swallow_items()
	_check_player_fall()
	if pending_value > 0:
		time_until_erupt -= delta
		if time_until_erupt <= 0.0:
			_erupt()


## 每帧按距离判定物品是否入洞。
##
## 为什么不用 SwallowZone 的 body_entered：那个区域只有 0.4 米高，
## 下落的物品会**一帧穿过**（穿透漏判），于是掉进洞里却不被吞噬，
## 最后落到洞底卡住（早期版本的 bug）。距离判定不依赖物理检测时机。
func _swallow_items() -> void:
	var attract := get_node_or_null("AttractZone") as Area3D
	if attract == null:
		return
	for body in attract.get_overlapping_bodies():
		if body == null or body is CharacterBody3D or body is Coin:
			continue
		var d := body.global_position - global_position
		var horizontal := Vector2(d.x, d.z).length()
		if horizontal <= swallow_radius and d.y <= SWALLOW_MAX_HEIGHT:
			var value := _item_value(body)
			if value > 0:
				_consume(body, value)
			else:
				_destroy(body)


## 每帧直接按距离判断玩家是否掉进洞里。
##
## 为什么不靠 SwallowZone 的 body_entered：那个区域很薄，
## 玩家高速下落时会**一帧穿过**（穿透漏判），于是永远不被踢出，
## 直接掉到地底（早期版本的 bug）。距离判定不依赖物理检测时机。
func _check_player_fall() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var d := _player.global_position - global_position
	# 水平距离够近，且已经陷进洞口平面以下。
	var horizontal := Vector2(d.x, d.z).length()
	if horizontal <= player_fall_radius and d.y <= PLAYER_FALL_HEIGHT:
		_eject_player(_player)


# ---- 吸引力 --------------------------------------------------------------

## 非玩家物品受到与距离**成反比**的吸引力（越近越强）。
## 注意：需求原文写"与距离成正比"，经确认按物理直觉取反比（见文档 N1）。
func _attract_items(delta: float) -> void:
	var attract := get_node_or_null("AttractZone") as Area3D
	if attract == null:
		return
	for body in attract.get_overlapping_bodies():
		if body == null:
			continue
		# 玩家**绝不能**被吸引。早期版本没排除玩家，结果把玩家一路吸到地底。
		if body is CharacterBody3D:
			continue
		# 钱币有自己的吸附逻辑，交给它自己处理。
		if body is Coin:
			continue
		var to_hole := global_position - body.global_position
		var dist := to_hole.length()
		if dist < 0.001:
			continue
		# 越近吸力越大：scale = 参考距离 / 实际距离，并设上限。
		var scale := clampf(ATTRACTION_REFERENCE_DISTANCE / maxf(dist, 0.1), 0.0, ATTRACTION_MAX_SCALE)
		var pull := to_hole.normalized() * scale
		if body is RigidBody3D:
			# 必须用速度而不是 global_position：给 RigidBody 直接赋 global_position
			# 会让它进入睡眠，反而**卡在半空掉不下去**（早期版本的 bug）。
			# 乘以 delta 是因为这里改的是速度增量。
			var rb := body as RigidBody3D
			rb.sleeping = false
			rb.linear_velocity += pull * ATTRACTION_ACCEL * delta


# ---- 判定入洞 ------------------------------------------------------------

func _on_body_entered_swallow(body: Node) -> void:
	if body == null:
		return
	# 玩家掉入**不在这里处理**——这里只处理物品。
	# 玩家的掉入判定统一走 _check_player_fall() 的距离检查：
	# 早先把踢出也写在这里，导致玩家只要碰到 Area 就被瞬移（哪怕还在洞上方）。
	if body is CharacterBody3D:
		return
	# 钱币掉回洞里：正在喷出的就把它重新抛出去（否则它刚出生就会被自己销毁），
	# 已经收进钱包的就忽略。
	if body is Coin:
		var coin := body as Coin
		if coin.is_ejecting():
			coin.eject_velocity = Vector3(
				coin.eject_velocity.x,
				absf(coin.eject_velocity.y) + 4.0,
				coin.eject_velocity.z
			)
		return
	# 其余视为"物品"，取它的价值。
	var value := _item_value(body)
	if value > 0:
		_consume(body, value)
	else:
		# 有价值为 0 的物品（或没写价值的），也销毁但不多喷钱。
		_destroy(body)


## 从物体上取价值。约定属性名 value；将来锻造物品也复用这个约定。
func _item_value(body: Node) -> int:
	if "value" in body:
		return maxi(0, int(body.value))
	return 0


func _consume(body: Node, value: int) -> void:
	pending_value += value
	# 每有新物品进入就重置计时器（"停止进入的 2 秒内开始判定"）。
	time_until_erupt = SETTLE_DELAY
	_destroy(body)
	if debug_print:
		print("[Hole] 吞入价值 %d，累计 %d，%.1f 秒后结算" % [value, pending_value, time_until_erupt])


func _destroy(body: Node) -> void:
	# 商品不献祭；由自己的返回接口处理引用、负重和货架位置。
	if body is ShopItem:
		body.call_deferred("return_home")
		return
	if body is Corpse:
		EventBus.corpse_offered.emit(body, _item_value(body))
	if body is Node3D:
		(body as Node3D).queue_free()


func _eject_player(player: Node3D) -> void:
	var target := global_position + Vector3(0, 1.6, 0)
	if _exit_point != null:
		target = _exit_point.global_position
	player.global_position = target
	if player is CharacterBody3D:
		# 清掉速度，免得落地瞬间被弹飞。
		(player as CharacterBody3D).velocity = Vector3.ZERO
	if debug_print:
		print("[Hole] 玩家掉入，已踢出到 %s" % str(target))


# ---- 涌现 ----------------------------------------------------------------

## 结算并喷出钱币。
func _erupt() -> void:
	var total_needed := pending_value
	pending_value = 0
	time_until_erupt = 0.0
	if total_needed <= 0:
		return

	var rule := offering_table.resolve_rule(total_needed) if offering_table != null else null
	var value_total := total_needed
	var count := 6
	var speed_min := 3.0
	var speed_max := 7.5
	var eject_time := 0.3
	var weights := PackedFloat32Array([1.0])
	if rule != null:
		value_total = int(round(float(total_needed) * rule.value_multiplier))
		count = _rng.randi_range(rule.coin_count_min, rule.coin_count_max)
		speed_min = rule.eject_speed_min
		speed_max = rule.eject_speed_max
		eject_time = rule.eject_min_time
		weights = rule.quality_weights
	# 随机修正（占位：0.9 ~ 1.15）。
	value_total = maxi(1, int(round(float(value_total) * _rng.randf_range(RANDOM_MODIFIER_MIN, RANDOM_MODIFIER_MAX))))
	count = maxi(1, count)

	var values := _split_value(value_total, count)
	_spawn_coins(values, weights, speed_min, speed_max, eject_time)
	EventBus.coins_erupted.emit(value_total, values.size())
	if debug_print:
		print("[Hole] 结算：投入 %d → 喷出 %d 枚、总额 %d" % [total_needed, values.size(), value_total])


## 把钱拆成若干枚的面额，尽量先用大面额，保证**总和精确等于总额**。
## 剩余的零头用最小面额补，所以可能多出几枚。
func _split_value(total: int, desired_count: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var denoms := _denominations()
	if denoms.is_empty():
		denoms = PackedInt32Array([1])
	var remaining := total
	# 先用最大面额拆 desired_count-2 枚，留余量给后面的小额。
	var big: int = denoms[denoms.size() - 1]
	for _i in range(maxi(0, desired_count - 2)):
		if remaining < big:
			break
		result.append(big)
		remaining -= big
	# 余下的从大到小尽量用大面额。
	for i in range(denoms.size() - 1, -1, -1):
		var d := denoms[i]
		while remaining >= d and result.size() < desired_count + 4:
			result.append(d)
			remaining -= d
	# 还有零头就用最小面额补齐（1 元，必定能补完）。
	while remaining > 0:
		result.append(1)
		remaining -= 1
	if result.is_empty():
		result.append(1)
	return result


## 品质面额列表（升序）。
func _denominations() -> PackedInt32Array:
	var out := PackedInt32Array()
	if offering_table != null and not offering_table.qualities.is_empty():
		for q in offering_table.qualities:
			out.append(maxi(1, q.value))
	else:
		out = PackedInt32Array([1, 5, 25])
	return out


## 找面额恰好等于 value 的品质，用于上色。
func _quality_for_value(value: int) -> CoinQuality:
	if offering_table == null:
		return null
	for q in offering_table.qualities:
		if q.value == value:
			return q
	return null


func _spawn_coins(values: PackedInt32Array, weights: PackedFloat32Array, speed_min: float, speed_max: float, eject_time: float) -> void:
	# 出生点必须**高于吞噬区**（吞噬区在 y≈-0.1~0.3）。
	# 早期版本在 y=0.1 喷币，结果钱币刚出生就被自己的洞判定销毁，一个都收不到。
	var origin := global_position + Vector3(0, 0.75, 0)
	for v in values:
		var coin := CoinPool.acquire()
		# 洞自己指定面额，所以品质抽签这里只用来决定"颜色倾向"。
		# 抽到的品质若面额与 v 不符，则按 v 找对应颜色。
		var q := _quality_for_value(v)
		if q == null:
			q = offering_table.pick_quality(_rng, weights) if offering_table != null else null
		var color := q.color if q != null else Color(0.76, 0.48, 0.22)
		coin.global_position = origin
		coin.seek_target = _player
		var dir := Vector3(_rng.randf_range(-1.0, 1.0), 1.0, _rng.randf_range(-1.0, 1.0)).normalized()
		var speed := _rng.randf_range(speed_min, speed_max)
		coin.launch(v, color, dir * speed, eject_time)


# ---- 调试/外部查询 --------------------------------------------------------

## 当前是否有待结算内容。
func has_pending() -> bool:
	return pending_value > 0


## 立刻结算（调试用，跳过 2 秒等待）。
func force_erupt() -> void:
	if pending_value > 0:
		_erupt()
