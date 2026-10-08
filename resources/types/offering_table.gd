class_name OfferingTable
extends Resource

## 献祭 → 涌现 的配置表。
##
## 策划需要提供的数据形状：给定投入洞里的价值总额，洞应该喷出多少枚币、
## 价值放大多少倍、币的品质如何分布。
##
## 数值尚未定稿（见文档 N2/Q5），所以先用占位值把链路跑通：
## 改这张表不需要改任何代码。

## 一条涌现规则。
class Rule extends Resource:
	## 投入价值区间 [min, max)，命中则采用本条规则。
	@export var value_min: int = 0
	@export var value_max: int = 999999
	## 总价值倍率——喷出来的钱总和 = 投入价值 × 本倍率（再随机修正）。
	@export var value_multiplier: float = 1.5
	## 最少 / 最多喷出的币数。
	@export var coin_count_min: int = 5
	@export var coin_count_max: int = 14
	## 品质抽签权重，与 qualities 数组一一对应。
	## 长度不足时自动补 1.0，所以短数组也能用（例如只写「金币占 20%」）。
	@export var quality_weights: PackedFloat32Array = PackedFloat32Array([1.0, 0.4, 0.15])
	## 向外抛射的初速度范围（米/秒）。
	@export var eject_speed_min: float = 3.0
	@export var eject_speed_max: float = 7.5
	## 抛射阶段最短时长（秒），之后才转入吸附。
	@export var eject_min_time: float = 0.3


## 可选品质列表，索引与 Rule.quality_weights 对应。
## 留空则用 CoinPool 内置的三档默认品质（铜/银/金）。
@export var qualities: Array[CoinQuality] = []
## 规则列表，按顺序匹配，第一条命中即用。
@export var rules: Array[Rule] = []


## 查询：给定投入价值，返回应该采用的规则。找不到则返回 null。
func resolve_rule(value: int) -> Rule:
	for rule in rules:
		if value >= rule.value_min and value < rule.value_max:
			return rule
	return null


## 按权重从 qualities 里抽一个品质。qualities 为空时返回 null。
func pick_quality(rng: RandomNumberGenerator, weights: PackedFloat32Array) -> CoinQuality:
	if qualities.is_empty():
		return null
	var total := 0.0
	for i in range(qualities.size()):
		total += _weight_at(weights, i)
	if total <= 0.0:
		return qualities[0]
	var roll := rng.randf() * total
	var acc := 0.0
	for i in range(qualities.size()):
		acc += _weight_at(weights, i)
		if roll <= acc:
			return qualities[i]
	return qualities[qualities.size() - 1]


## 权重数组长度不足时，越界部分按 1.0 处理。
static func _weight_at(weights: PackedFloat32Array, index: int) -> float:
	if index < weights.size():
		return maxf(0.0, weights[index])
	return 1.0
