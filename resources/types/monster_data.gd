class_name MonsterData
extends Resource

## 一种怪物的全部数据。策划改这里即可加新怪种，不需要改代码。
##
## 设计约束（来自策划需求）：
##   - 怪物**不会对玩家造成伤害**，所以这里没有任何攻击/伤害字段
##   - 怪物有血量和属性
##   - 怪物的尸体有**价值**，且**可被抓取**

@export var id: StringName = &""
@export var display_name: String = "怪物"

@export_group("生存")
@export var max_health: float = 5.0
## 受击僵直（秒），0 = 霸体不僵直。给个很小的值能让打击感更明显。
@export var hit_stun: float = 0.1

@export_group("运动（随机游走）")
## 游走速度（米/秒）。
@export var move_speed: float = 1.6
## 连续走动的时长范围（秒），到点停下来歇一会。
@export var walk_duration_min: float = 0.8
@export var walk_duration_max: float = 2.5
## 停下歇息的时长范围（秒）。
@export var idle_duration_min: float = 0.3
@export var idle_duration_max: float = 1.2
## 撞墙后重新选方向的次数上限（避免卡在角落抖动）。
@export var max_turn_attempts: int = 4

@export_group("尸体")
## 尸体的**价值**——洞据此决定喷多少钱。
@export var corpse_value: int = 1
## 尸体存在时长（秒）。<=0 表示永不超时。
@export var corpse_lifetime: float = 30.0
## 尸体重量，影响玩家扛着它时的移速。1.0 为基准。
@export var corpse_weight: float = 1.0

@export_group("表现（占位）")
## 怪物本体的占位胶囊尺寸（等美术白模）。
@export var body_size: Vector3 = Vector3(0.5, 0.35, 0.7)
@export var body_color: Color = Color(0.35, 0.25, 0.2)
## 尸体外观。留空则沿用 body_size / body_color。
@export var corpse_size: Vector3 = Vector3.ZERO
@export var corpse_color: Color = Color(0, 0, 0, 0)


## 尸体实际使用的尺寸（未单独配置则沿用本体）。
func get_corpse_size() -> Vector3:
	return corpse_size if corpse_size != Vector3.ZERO else body_size


## 尸体实际使用的颜色（未单独配置则沿用本体）。
func get_corpse_color() -> Color:
	return corpse_color if corpse_color.a > 0.0 else body_color
