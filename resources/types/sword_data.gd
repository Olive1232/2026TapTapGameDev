class_name SwordData
extends Resource

## 一把剑的全部数据。策划改这里的字段即可造新剑，不需要改代码。
##
## 破除障碍靠 break_tags 与障碍的 required_break_tag 做标签匹配——
## 不要在这里加 `is_fire_sword` 这类布尔量。
##
## 手感相关的字段都标了「手感」分组。想调"挥起来轻/重"就动这几个。

## 构图参数被改动时发出，让正在使用的剑**立刻**重算位置/外观，
## 这样编辑器里改 view_offset 能实时看到效果，不用重载场景。
signal view_changed

## 唯一 id（用于存档、锻造配方查表）。留空则退回资源路径。
@export var id: StringName = &""
## 显示名。
@export var display_name: String = "剑"

@export_group("数值")
## 单次挥击伤害。
@export var damage: float = 10.0
## 有效距离（米）—— 伤害区域从握把往前伸多远。
## 必须够长以覆盖视觉剑身，否则会出现"剑尖看得见却砍不到"。
## 当前剑身长 1.8 米、剑尖到 z=-2.0，所以取 3.0 留出余量。
@export var range_m: float = 3.0
## 挥砍扇形角度（度）。横扫一次扫过的水平角度，360 表示转一圈。
@export_range(1.0, 360.0) var arc_degrees: float = 120.0
## 击退力度。
@export var knockback_force: float = 6.0

@export_group("手感")
## 前摇（秒）——按键到判定生效的时间，越长越"重"。
@export var windup: float = 0.14
## 判定持续时间（秒）——伤害区域张开多久。
@export var active_time: float = 0.10
## 恢复（秒）——判定结束到能再挥的收招时间。
@export var recovery: float = 0.18
## 冷却（秒）——两次挥击的最小间隔（0 表示只受前摇+判定+恢复限制）。
@export var cooldown: float = 0.0

@export_group("动画（程序化横扫）")
## 静止时剑的水平朝向（yaw，度）——**"初始角度"调整项之一**。
## 0 = 剑身正对前方；**负值 = 剑尖偏向画面右侧**；正值 = 偏向左侧。（已实测确认）
@export var rest_yaw: float = -10.0:
	set(value):
		rest_yaw = value
		view_changed.emit()
## 蓄力角度（度）——向右后方拉开。
@export var windup_yaw: float = -52.0
## 收势角度（度）——向左前方扫过。
@export var followthrough_yaw: float = 58.0
## 挥砍时额外压下的俯仰（度）——在 rest_pitch 基础上叠加。
@export var swing_pitch: float = -14.0
## 静止时剑身的俯仰（pitch，度）——**"初始角度"的主要调整项**。
## **正值 = 剑尖朝上抬，负值 = 朝下压。** 0 = 完全水平。（已实测确认）
##
## 注意：抬高角不等于本值。yaw 不为 0 时俯仰会被"摊薄"，
## 实际抬高的正弦 = sin(本值) × cos(yaw)。例如 yaw=-28、本值=46 时，
## 实际抬高约 39 度。要精确控制抬高角，就用这个换算反推。
@export var rest_pitch: float = 0.0:
	set(value):
		rest_pitch = value
		view_changed.emit()
## 剑身自转（roll，度）——绕剑身长轴转，决定"刃朝哪边"。
## 0 = 剑刃朝上下（竖直的刀身）；90 = 剑刃朝左右（平躺的刀身）。
## 目前全程恒定（挥砍过程中不变化）。
@export var rest_roll: float = 0.0:
	set(value):
		rest_roll = value
		view_changed.emit()

@export_group("标签")
## 这把剑造成的伤害标签，如 ["physical", "fire"]。
@export var damage_tags: PackedStringArray = PackedStringArray(["physical"])
## 这把剑能破除的障碍标签。障碍的 required_break_tag 在此列表内才可破坏。
@export var break_tags: PackedStringArray = PackedStringArray()
## 已获得的能力升级。油只提供可点燃能力，不直接添加 fire 伤害。
@export var upgrade_tags: PackedStringArray = PackedStringArray()

@export_group("表现")
## 第一人称手部模型。留空则用场景里的占位方块（见 scenes/player/player.tscn 的 Mount/Pivot/Mesh）。
@export var swing_mesh: Mesh = null
## 模型相对**挂点**的位置偏移。位置 = 场景挂点 + 本偏移。
## 调剑在画面里的构图只用改这里，不用进场景改 Transform。
##   x 负值 = 往左（画面内侧）   正 = 往右
##   y 负值 = 往下               正 = 往上
##   z 负值 = 往前（离相机更远）  正 = 往后（怼到脸上）
## 这是**最主要**的构图调整项，改完游戏里立刻生效。
@export var view_offset: Vector3 = Vector3(-0.27, 0.0, 0.0):
	set(value):
		view_offset = value
		view_changed.emit()
## 主色调——神剑靠换色就能一眼区分。
@export var tint: Color = Color.WHITE


## 资源 id：显式 id 优先，否则退回资源路径。
func get_id() -> StringName:
	if not id.is_empty():
		return id
	return StringName(resource_path)
