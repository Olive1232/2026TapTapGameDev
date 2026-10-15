class_name Hole
extends Node3D

## 洞 —— 经济循环的中枢。
##
## 流程（对应策划需求）：
##   物品落入判定区 → 销毁并累加价值 → 2 秒内无新物品进入 → 结算
##   → 按「总价值 × 随机修正」喷出等价值的整数钱币 → 落地后玩家接触拾取
##
## 其它规则：
##   - 玩家掉进洞里获得向上速度，被喷出洞口
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
## 玩家喷出速度（米/秒）。保留水平方向的移动与空中操控。
@export_range(1.0, 30.0, 0.5) var player_eject_speed: float = 12.0
## 是否把调试状态打到控制台。
@export var debug_print: bool = false

## 关卡可按实际模型口径适配；旧场景保持原默认值与高度规则。
## 大坑需要更远的参考距离，使坑沿吸力足以克服地面摩擦。
@export_range(0.1, 40.0, 0.1) var attraction_reference_distance: float = ATTRACTION_REFERENCE_DISTANCE
@export_range(0.1, 10.0, 0.1) var swallow_radius: float = SWALLOW_RADIUS
@export_range(0.1, 10.0, 0.1) var player_fall_radius: float = PLAYER_FALL_RADIUS
## 喷币落点到洞心的距离；按实际地形配置，不能用吞噬半径代替洞口尺寸。
@export_range(1.0, 20.0, 0.1) var coin_landing_radius: float = 2.4
## 复杂白模可指定安全落币点；为空时沿用随机圆形喷射。
@export var coin_landing_points: Array[NodePath] = []
@export var corpse_return_outlet_path: NodePath
var upgrade_tags := PackedStringArray()
var _corpse_value_level := 0
var _golden_coin_level := 0

## 待结算的投入价值（已累加，尚未喷发）。
var pending_value: int = 0
## 距离结算还剩多少秒。<=0 表示没有待结算内容。
var time_until_erupt: float = 0.0

var _rng := RandomNumberGenerator.new()
var _player: Node3D = null
var _player_ejected := false


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
	# 钱币挂到场景根，便于随场景释放。
	var host := get_tree().current_scene
	CoinPool.set_host(host if host != null else get_parent())
	# 延迟一帧找玩家，确保场景已就绪。
	call_deferred("_find_player")


func _find_player() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
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


func _physics_process(delta: float) -> void:
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
		if body == null or body.is_queued_for_deletion() or body is CharacterBody3D:
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
	if horizontal > player_fall_radius or d.y > PLAYER_FALL_HEIGHT:
		_player_ejected = false
	elif _player is CharacterBody3D and _player.is_on_floor() and d.y >= 0.0 and _player.velocity.y <= 0.0:
		# 模型洞沿略低于主地板；正常站在洞沿时不触发喷出。
		_player_ejected = false
	elif not _player_ejected:
		_player_ejected = true
		_eject_player(_player)


# ---- 吸引力 --------------------------------------------------------------

## 非玩家物品受到与距离**成反比**的吸引力（越近越强）。
## 当前保留旧 N1 公式；新版正比弱吸力另行实施，见开发拆分中的差异记录。
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
		var to_hole := global_position - body.global_position
		var dist := to_hole.length()
		if dist < 0.001:
			continue
		# 越近吸力越大：scale = 参考距离 / 实际距离，并设上限。
		var scale := clampf(attraction_reference_distance / maxf(dist, 0.1), 0.0, ATTRACTION_MAX_SCALE)
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
		var base := maxi(0, int(body.value))
		# 在统一入口计算当前等级，已存在 / 新生成 / 转移的尸体都只加一次。
		if body is Corpse:
			var value := mini(base, ShopItemData.MAX_INT - _corpse_value_level) + _corpse_value_level
			# 镜子只复制本次尸体献祭的价值，不生成第二具尸体或修改原始价值。
			if has_upgrade("mirror"):
				return value + mini(value, ShopItemData.MAX_INT - value)
			return value
		return base
	return 0


func _consume(body: Node, value: int) -> void:
	if body.is_queued_for_deletion():
		return
	pending_value += value
	# 每有新物品进入就重置计时器（"停止进入的 2 秒内开始判定"）。
	time_until_erupt = SETTLE_DELAY
	_destroy(body, value)
	if debug_print:
		print("[Hole] 吞入价值 %d，累计 %d，%.1f 秒后结算" % [value, pending_value, time_until_erupt])


func _destroy(body: Node, offered_value: int = -1) -> void:
	if body.is_queued_for_deletion():
		return
	# 商品不献祭；由自己的返回接口处理引用、负重和货架位置。
	if body is ShopItem:
		body.call_deferred("return_home")
		return
	if body is Corpse:
		EventBus.corpse_offered.emit(body, _item_value(body) if offered_value < 0 else offered_value)
	if body is Node3D:
		(body as Node3D).queue_free()


func _eject_player(player: Node3D) -> void:
	if player is CharacterBody3D:
		var body := player as CharacterBody3D
		body.velocity.y = maxf(body.velocity.y, player_eject_speed)
	if debug_print:
		print("[Hole] 玩家掉入，向上喷出速度 %.1f" % player_eject_speed)


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
	var actual_total := _spawn_coins(values, weights, speed_min, speed_max, eject_time)
	EventBus.coins_erupted.emit(actual_total, values.size())
	if debug_print:
		print("[Hole] 结算：投入 %d → 喷出 %d 枚、总额 %d" % [total_needed, values.size(), actual_total])


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


func _spawn_coins(values: PackedInt32Array, weights: PackedFloat32Array, speed_min: float, speed_max: float, eject_time: float) -> int:
	# 出生点必须**高于吞噬区**（吞噬区在 y≈-0.1~0.3）。
	# 早期版本在 y=0.1 喷币，结果钱币刚出生就被自己的洞判定销毁，一个都收不到。
	var origin := global_position + Vector3(0, 0.75, 0)
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var actual_total := 0
	for v in values:
		# 普通结算已完成；每枚币独立抽签，1—20 级对应 5%—100%。
		var golden := _golden_coin_level > 0 and _rng.randi_range(0, ShopItemData.MAX_GOLDEN_COIN_LEVEL - 1) < _golden_coin_level
		var coin_value: int = v * 10 if golden else v
		actual_total += coin_value
		var coin := CoinPool.acquire()
		# 洞自己指定面额，所以品质抽签这里只用来决定"颜色倾向"。
		# 抽到的品质若面额与 v 不符，则按 v 找对应颜色。
		var q := _quality_for_value(v)
		if q == null:
			q = offering_table.pick_quality(_rng, weights) if offering_table != null else null
		var color := q.color if q != null else Color(0.76, 0.48, 0.22)
		coin.global_position = origin
		var angle := _rng.randf_range(0.0, TAU)
		var radial := Vector3(cos(angle), 0, sin(angle))
		var landing := origin + radial * coin_landing_radius
		var authored: Node3D = null
		if not coin_landing_points.is_empty():
			authored = get_node_or_null(coin_landing_points[_rng.randi_range(0, coin_landing_points.size() - 1)]) as Node3D
		# 旧测试场地也有非圆形开口，选择有实际地面的喷射方向。
		for attempt in range(16):
			landing = authored.global_position if authored != null else origin + radial * coin_landing_radius
			var ray := PhysicsRayQueryParameters3D.create(landing + Vector3.UP * 0.5, landing - Vector3.UP * 4.0, CollisionLayers.WORLD)
			var floor_hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if not floor_hit.is_empty() and floor_hit.normal.y > 0.7:
				landing.y = floor_hit.position.y + 0.03
				break
			angle += TAU / 16.0
			radial = Vector3(cos(angle), 0, sin(angle))
		var horizontal := Vector3(landing.x - origin.x, 0, landing.z - origin.z)
		radial = horizontal.normalized()
		var speed := _rng.randf_range(speed_min, speed_max)
		var up_speed := maxf(3.0, speed * 0.85)
		var drop_height := maxf(0.0, origin.y - landing.y)
		var flight_time := (up_speed + sqrt(up_speed * up_speed + 2.0 * gravity * drop_height)) / gravity
		# 抛物线按落点高度与距离计算，钱币仍通过自身的真实碰撞落地。
		var outward_speed := horizontal.length() / flight_time
		coin.launch(coin_value, color, radial * outward_speed + Vector3.UP * up_speed, eject_time, golden)
	return actual_total


# ---- 调试/外部查询 --------------------------------------------------------

func has_upgrade(tag: String) -> bool:
	if ShopItemData.get_level_limit(tag) >= 0:
		return get_upgrade_level(tag) > 0
	return upgrade_tags.has(tag)


func can_apply_upgrade(tag: String) -> bool:
	var limit := ShopItemData.get_level_limit(tag)
	if limit >= 0:
		return get_upgrade_level(tag) < limit
	if tag == "mirror":
		return not has_upgrade(tag)
	if tag != "corpse_return" or has_upgrade(tag) or corpse_return_outlet_path.is_empty():
		return false
	var outlet := get_node_or_null(corpse_return_outlet_path)
	return outlet != null and outlet.has_method("can_enable") and outlet.can_enable()


func apply_upgrade(tag: String) -> bool:
	if not can_apply_upgrade(tag):
		return false
	if ShopItemData.get_level_limit(tag) >= 0:
		return restore_upgrade_level(tag, get_upgrade_level(tag) + 1)
	if tag == "corpse_return":
		var outlet := get_node(corpse_return_outlet_path)
		outlet.enable()
	upgrade_tags.append(tag)
	return true


func get_corpse_value_level() -> int:
	return _corpse_value_level


func get_golden_coin_level() -> int:
	return _golden_coin_level


func get_upgrade_level(tag: String) -> int:
	match tag:
		"corpse_value":
			return _corpse_value_level
		"golden_coin":
			return _golden_coin_level
	return 0


## 直接设置载入等级，不重复执行购买或叠加已有加成。
func restore_corpse_value_level(level: int) -> bool:
	return restore_upgrade_level("corpse_value", level)


func restore_upgrade_level(tag: String, level: int) -> bool:
	var limit := ShopItemData.get_level_limit(tag)
	if limit < 0 or level < 0 or level > limit:
		return false
	match tag:
		"corpse_value":
			_corpse_value_level = level
		"golden_coin":
			_golden_coin_level = level
	return true


## 自动移动只持续到真实吸力区域，随后由既有吸力与献祭流程接管。
func is_in_attraction_range(body: PhysicsBody3D) -> bool:
	var area := get_node_or_null("AttractZone") as Area3D
	return area != null and area.overlaps_body(body)

## 当前是否有待结算内容。
func has_pending() -> bool:
	return pending_value > 0


## 立刻结算（调试用，跳过 2 秒等待）。
func force_erupt() -> void:
	if pending_value > 0:
		_erupt()
