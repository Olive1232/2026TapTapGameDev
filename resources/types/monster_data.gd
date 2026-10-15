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
## 活体掉入洞后使用与玩家相同的喷飞规则；尸体仍按献祭规则处理。
@export var hole_ejectable: bool = false
## 移动前检查脚下及前方支撑，避免自主游走或水平击退越过悬崖。
@export var avoid_ledges: bool = false
## 可通过的小落差；超过此高度视为边缘，正常缓坡不受影响。
@export_range(0.05, 1.0, 0.05) var ledge_max_drop: float = 0.4
## 身体前缘额外保留的距离（米）。
@export_range(0.0, 0.5, 0.01) var ledge_margin: float = 0.12
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
## 尸体点燃后烧毁的时长。未点燃的尸体永久保留；10 秒为试玩值。
@export_range(0.1, 60.0, 0.1) var corpse_burn_duration: float = 10.0
## 尸体重量，影响玩家扛着它时的移速。1.0 为基准。
@export var corpse_weight: float = 1.0

@export_group("表现（占位）")
## 怪物本体的占位胶囊尺寸（等美术白模）。
@export var body_size: Vector3 = Vector3(0.5, 0.35, 0.7)
@export var body_color: Color = Color(0.35, 0.25, 0.2)
## 尸体外观。留空则沿用 body_size / body_color。
@export var corpse_size: Vector3 = Vector3.ZERO
@export var corpse_color: Color = Color(0, 0, 0, 0)

@export_group("声音")
## 留空的怪种保持安静；播放完整叫声后随机间隔再叫。
@export var voice_stream: AudioStream


## 尸体实际使用的尺寸（未单独配置则沿用本体）。
func get_corpse_size() -> Vector3:
	return corpse_size if corpse_size != Vector3.ZERO else body_size


## 尸体实际使用的颜色（未单独配置则沿用本体）。
func get_corpse_color() -> Color:
	return corpse_color if corpse_color.a > 0.0 else body_color
