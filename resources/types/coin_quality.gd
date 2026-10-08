class_name CoinQuality
extends Resource

## 钱币的"品质"。
##
## 已确认设计：品质**只影响价值**，不影响用途、不参与任何逻辑判断。
## 因此本资源纯粹是「外观 + 面额」的组合，Wallet 里只累加 int，
## 不分类存储，也不需要按品质查可用商品。
##
## 若将来品质要影响用途，需要改 Wallet 的存储结构与商店的购买判定。

## 唯一 id，如 &"copper"。
@export var id: StringName = &"copper"
## 显示名。
@export var display_name: String = "铜币"
## 单枚价值。
@export var value: int = 1
## 用于占位方块的颜色 / 材质着色。
@export var color: Color = Color(0.72, 0.45, 0.20)
## 外观等级 0..2，供表现层选择模型与粒子（0 最朴素）。
@export_range(0, 2) var visual_tier: int = 0
## 拾取音效（留空表示沿用默认）。
@export var pickup_sound: AudioStream = null


## 造一份品质数据。用于代码生成默认档次（策划尚未给 .tres 时占位）。
static func make(p_id: StringName, p_name: String, p_value: int, p_color: Color, p_tier: int) -> CoinQuality:
	var q := CoinQuality.new()
	q.id = p_id
	q.display_name = p_name
	q.value = p_value
	q.color = p_color
	q.visual_tier = p_tier
	return q
