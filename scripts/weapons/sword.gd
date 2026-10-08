class_name Sword
extends Node3D

## 第一人称剑。挂在 Player/Camera3D/WeaponRig/WeaponPivot 下。
##
## 负责三件事：
##   1. 程序化横扫动画（暂无美术动画，用旋转插值代替）
##   2. Area3D 伤害区域的开合与命中检测
##   3. 打击反馈：顿帧、击退、闪白、火花
##
## 命中检测用 Area3D（已决策）。为缓解高速挥砍的穿透漏判：
##   - 伤害区域做得比视觉剑身更长更厚（扫掠式放大）
##   - 每个物理帧主动轮询 get_overlapping_bodies()，不依赖 body_entered 信号
##   - 单次挥砍维护 _hit_this_swing 登记表，同时防止一刀多次伤害

## 当前这把剑的数据。可在编辑器里直接赋值换剑。
## 默认指向初始之剑；若被清空，_ensure_data() 会兜底生成一份默认数据，
## 保证剑永远可用（不因为漏配资源就变成"按左键没反应"）。
@export var data: SwordData = preload("res://resources/swords/sword_starter.tres")

## 自动挥砍（用于编辑器里预览手感，跑起来会自动停）。
@export var auto_swing_in_editor: bool = false

## 挥砍状态。
enum State { IDLE, WINDUP, ACTIVE, RECOVERY }

## 伤害区域的固定向下倾角（度）。
## 玩家相机在眼高，敌人中心在腰高，所以判定区要朝下一点才够得着。
const HITBOX_LEVEL_PITCH := -14.0

var _state: State = State.IDLE
var _t: float = 0.0
## 本次挥砍已伤害过的目标，防止一刀多次结算。
var _hit_this_swing: Dictionary = {}
## 顿帧期间的原始时间缩放。
var _time_scale_before_hitstop: float = 1.0
## 顿帧是否生效中（避免嵌套顿帧叠加）。
var _in_hitstop: bool = false
## 一次挥砍中是否已经产生过命中（用于判断"砍空了"）。
var _connected: bool = false

signal element_state_changed
const FIRE_SWINGS := 5
var oiled := false
var fire_swings_remaining := 0
var _fire_counted_this_swing := false
var _base_material: Material
var interaction_locked := false
@onready var element: ElementComponent = $Pivot/ElementComponent

# 动画分两个节点，避免 yaw 与 pitch 互相覆盖：
#   _yaw_node （子节点 Pivot） 负责水平横扫
#   self                       负责俯仰（rotation.x）与自转（rotation.z）
#
# 伤害区域不在剑的表现层级里：它挂在 WeaponPivot 下的 HitAnchor/HitRig，
# 只继承水平横扫。这样剑怎么摆姿势都不影响判定范围。
@onready var _yaw_node: Node3D = $Pivot
@onready var _mesh: MeshInstance3D = $Pivot/Mesh
@onready var _hit_anchor: Node3D = $"../HitAnchor"
@onready var _hit_rig: Node3D = $"../HitAnchor/HitRig"
@onready var _hitbox: Area3D = $"../HitAnchor/HitRig/Hitbox"
@onready var _hit_shape: CollisionShape3D = $"../HitAnchor/HitRig/Hitbox/Shape"

## 挂点位置（相机空间），来自场景里本节点的初始 position。
## 最终位置 = 挂点 + SwordData.view_offset，让策划能只靠数据调构图。
var _mount_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	# 必须在任何赋值之前记下场景里的挂点位置，之后 position 会被数据改写。
	_mount_position = position
	_ensure_data()
	_setup_hitbox()
	_apply_data()
	# 立刻套用静止姿态。否则要等第一次 _process 才摆正，
	# 编辑器里预览时会看到场景文件里那个过时的角度。
	_drive_animation(0.0)
	_base_material = _mesh.material_override
	element.ignited.connect(_on_ignited)
	element.extinguished.connect(_on_extinguished)
	_apply_upgrade_tags()


## 没配 SwordData 时兜底生成一份，避免整把剑变成哑巴。
## 同时接上「构图参数被改动」的信号，让编辑器里调 view_offset 能实时生效。
func _ensure_data() -> void:
	if data == null:
		data = SwordData.new()
		push_warning("Sword「%s」没有设置 SwordData，已用默认数值兜底。建议给它挂上资源。" % name)
	if not data.view_changed.is_connected(_on_data_view_changed):
		data.view_changed.connect(_on_data_view_changed)


## 资源里的构图参数（位置或角度）变了——立刻重算，不用重载场景。
func _on_data_view_changed() -> void:
	_apply_view_offset()
	# 重新套用静止姿态，让 rest_yaw / rest_pitch / rest_roll 实时生效。
	_drive_animation(0.0)


## 换剑：整把换数据并重算伤害区域。
func set_sword_data(new_data: SwordData) -> void:
	if data != null and data.view_changed.is_connected(_on_data_view_changed):
		data.view_changed.disconnect(_on_data_view_changed)
	data = new_data
	# 换剑重置本把剑的临时状态，不污染共享资源。
	element.extinguish()
	oiled = false
	element.tags = PackedStringArray(["indestructible"])
	fire_swings_remaining = 0
	_ensure_data()
	_mesh.material_override = null
	_apply_data()
	_base_material = _mesh.material_override
	_apply_upgrade_tags()
	element_state_changed.emit()


func _apply_data() -> void:
	if data == null:
		return
	_apply_view_offset()
	if _hit_shape and _hit_shape.shape is BoxShape3D:
		var box := _hit_shape.shape as BoxShape3D
		# 伤害区域比视觉剑身更厚（1.4 宽）也更长（前后各留余量），
		# 用来缓解 Area3D 在高速挥砍时的穿透漏判。
		# 中心取 -range_m*0.39 而不是 -range_m*0.5：让盒子对齐"从握把往前的剑身"，
		# 而不是从相机原点开始，否则剑柄附近会有一块看不见的判定区。
		box.size = Vector3(1.4, 1.0, data.range_m * 0.78)
		_hit_shape.position = Vector3(0.0, 0.0, -data.range_m * 0.39)
	if _mesh and data.tint != Color.WHITE:
		_tint_mesh(data.tint)


## 把 SwordData.view_offset 应用到挂点上。
## 位置 = 场景挂点 + 数据偏移。策划改 .tres 的 view_offset 就能调剑在画面里的位置，
## 不用进场景动 Transform。
func _apply_view_offset() -> void:
	position = _mount_position + data.view_offset


func _setup_hitbox() -> void:
	if _hitbox == null:
		return
	# 伤害区域属于 WEAPON 层，开窗时监听敌人和静态障碍；
	# 命中判定由下面的 _poll_hits() 主动轮询完成。
	# 注意：Area3D 没有 max_contacts_reported（那是 RigidBody 的属性）。
	_hitbox.collision_layer = CollisionLayers.WEAPON
	_hitbox.collision_mask = CollisionLayers.ENEMY | CollisionLayers.WORLD
	_hitbox.monitoring = false
	_hitbox.monitorable = false


func _process(delta: float) -> void:
	if auto_swing_in_editor and Engine.is_editor_hint():
		_tick(delta)
		return
	if _state != State.IDLE:
		_tick(delta)
	else:
		_drive_animation(0.0)


func _physics_process(_delta: float) -> void:
	if _state == State.ACTIVE:
		_poll_hits()


func _unhandled_input(event: InputEvent) -> void:
	# 只在游戏里响应，编辑器里不抢输入。
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("Attack"):
		try_swing()


func _tick(delta: float) -> void:
	if data == null:
		_state = State.IDLE
		return
	_t += delta
	match _state:
		State.WINDUP:
			var p := _phase_ratio(_t, data.windup)
			_drive_animation_windup(p)
			if _t >= data.windup:
				_enter_active()
		State.ACTIVE:
			# 判定期间持续扫过，动画在前摇基础上继续往收势角走。
			var p2 := _phase_ratio(_t, data.active_time)
			_drive_animation_swing(p2)
			if _t >= data.active_time:
				_state = State.RECOVERY
				_t = 0.0
				_close_hitbox()
		State.RECOVERY:
			# 收招：从收势角平滑回静止角。
			var p3 := _phase_ratio(_t, data.recovery)
			_drive_animation_recover(p3)
			if _t >= data.recovery:
				_state = State.IDLE
				_t = 0.0
				if element.burning and fire_swings_remaining == 0:
					element.extinguish()
				_drive_animation(0.0)


func _phase_ratio(elapsed: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(elapsed / duration, 0.0, 1.0)


# ---- 状态切换 -------------------------------------------------------------

## 尝试挥砍。返回是否真的挥出去了（冷却中或已在挥砍中会返回 false）。
func try_swing() -> bool:
	if interaction_locked or data == null or _state != State.IDLE:
		return false
	_hit_this_swing.clear()
	_connected = false
	_state = State.WINDUP
	_t = 0.0
	_fire_counted_this_swing = false
	_count_fire_swing()
	return true


func _enter_active() -> void:
	_state = State.ACTIVE
	_t = 0.0
	_open_hitbox()


func _open_hitbox() -> void:
	if _hitbox:
		_hitbox.monitoring = true


func _close_hitbox() -> void:
	if _hitbox:
		_hitbox.monitoring = false


# ---- 程序化横扫动画 -------------------------------------------------------
# 两个节点分工，互不干扰：
#   Pivot 的 rotation.y  = 水平横扫角度（yaw）
#   Sword 的 rotation.x  = 挥砍前倾角度（pitch）
# 将来美术给了动画，把 AnimationPlayer 挂在 WeaponRig 上做同样的旋转即可，
# 命中判定不受影响。

func _drive_animation(_rest_ratio: float) -> void:
	# 静止姿态：yaw=rest_yaw，pitch=rest_pitch。
	# rest_pitch 之前被硬编码成 0.0，导致"初始旋转角度"怎么调都没反应——
	# swing_pitch 只在挥砍那一瞬用得上，调不到待机姿态。
	_apply_pose(data.rest_yaw if data else -10.0, data.rest_pitch if data else 0.0)


func _drive_animation_windup(p: float) -> void:
	# 静止角 → 蓄力角，用 ease out 让起手干脆。
	var e := ease(p, 0.4)
	_apply_pose(lerpf(data.rest_yaw, data.windup_yaw, e), data.rest_pitch)


func _drive_animation_swing(p: float) -> void:
	# 蓄力角 → 收势角，用 ease out 做出"唰"地扫过去的加速感。
	var e := ease_out_cubic(p)
	_apply_pose(
		lerpf(data.windup_yaw, data.followthrough_yaw, e),
		data.rest_pitch + data.swing_pitch * e
	)


func _drive_animation_recover(p: float) -> void:
	var e := ease(p, 0.6)
	_apply_pose(
		lerpf(data.followthrough_yaw, data.rest_yaw, e),
		data.rest_pitch + data.swing_pitch * (1.0 - e)
	)


func _apply_pose(yaw_deg: float, pitch_deg: float) -> void:
	if data == null:
		return
	# 三个轴分别写在不同节点上，互不覆盖：
	#   _yaw_node.rotation.y = 水平朝向（yaw，横扫）
	#   self.rotation.x      = 俯仰（pitch）
	#   self.rotation.z      = 自转（roll，刃朝哪边）
	if _yaw_node != null:
		_yaw_node.rotation.y = deg_to_rad(yaw_deg)
	# 单独同步锚点，不转 WeaponPivot，否则模型会叠加两次 yaw。
	if _hit_anchor != null:
		_hit_anchor.rotation.y = deg_to_rad(yaw_deg)
	rotation.x = deg_to_rad(pitch_deg)
	rotation.z = deg_to_rad(data.rest_roll)
	# 伤害区域继承 HitAnchor 的横扫，只额外加固定下倾角。
	# 剑的俯仰、自转、构图位置仍不影响判定范围。
	if _hit_rig != null:
		_hit_rig.rotation.x = deg_to_rad(HITBOX_LEVEL_PITCH)


static func ease_out_cubic(x: float) -> float:
	var inv := 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - inv * inv * inv


# ---- 命中检测 -------------------------------------------------------------

## 每个物理帧轮询伤害区域内的目标。
## 用主动轮询而不是 body_entered 信号：信号只在"进入的那一帧"触发，
## 高速挥砍时可能整段判定都错过；轮询则只要目标在区域内就一定被发现。
func _poll_hits() -> void:
	if _hitbox == null:
		return
	for body in _hitbox.get_overlapping_bodies():
		if body == null or _hit_this_swing.has(body):
			continue
		if not body.has_method("take_hit"):
			continue
		if not _clear_hit_path(body):
			continue
		_hit_this_swing[body] = true
		_connected = true
		_deliver_hit(body)
		if interaction_locked:
			break


func _deliver_hit(body: Node3D) -> void:
	var info := HitInfo.new()
	info.damage = data.damage
	info.source = _owner_of_swing()
	info.tags = get_damage_tags()
	info.hit_position = _hit_position_towards(body)
	info.knockback = _knockback_towards(body)

	body.take_hit(info)
	_spawn_sparks(info.hit_position)
	_apply_hitstop()


## 房间出现墙体后，命中与抓取都需要遵守遮挡。
func _clear_hit_path(body: Node3D) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(_hit_anchor.global_position, _hit_position_towards(body), CollisionLayers.WORLD)
	var excluded: Array[RID] = []
	var carrier := _owner_of_swing()
	if carrier is PhysicsBody3D:
		excluded.append(carrier.get_rid())
	if body is PhysicsBody3D:
		excluded.append(body.get_rid())
	ray.exclude = excluded
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


## 找出挥剑的人（沿父链往上找带 set_carry_weight 的节点，通常是 Player）。
func _owner_of_swing() -> Node3D:
	var node: Node = self
	while node != null:
		if node is Node3D and node.has_method("set_carry_weight"):
			return node as Node3D
		node = node.get_parent()
	return null


func _hit_position_towards(body: Node3D) -> Vector3:
	var from := global_position
	if body.has_method("get_hit_center"):
		return body.get_hit_center()
	return (from + body.global_position) * 0.5


func _knockback_towards(body: Node3D) -> Vector3:
	var origin := _owner_of_swing()
	var from := origin.global_position if origin else global_position
	var dir := body.global_position - from
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	dir = dir.normalized()
	# 上抬分量刻意很小（0.25 → 0.12）：横向击退更利于"砍进人堆"，
	# 太大的上抬会让目标直接飞起来，看起来像打保龄球。
	return (dir + Vector3.UP * 0.12).normalized() * data.knockback_force


# ---- 打击反馈 -------------------------------------------------------------

## 顿帧：命中瞬间把时间几乎冻住一瞬，是"打到了"最直接的体感来源。
func _apply_hitstop() -> void:
	if _in_hitstop:
		return
	_in_hitstop = true
	_time_scale_before_hitstop = Engine.time_scale
	Engine.time_scale = 0.05
	# 用真实时间等待，否则 time_scale 会把自己也拖慢。
	await get_tree().create_timer(0.055, true, false, true).timeout
	Engine.time_scale = _time_scale_before_hitstop
	_in_hitstop = false


## 命中火花：一个自发光小方块炸开并淡出。占位表现，等美术给粒子。
func _spawn_sparks(at: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.92, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mesh.material = mat
	spark.mesh = mesh

	# 注意：必须先入树再设 global_position。Node3D 不在场景树里时
	# 访问 global_position / top_level 会报 "Condition !is_inside_tree() is true"。
	var holder := get_tree().current_scene
	if holder == null:
		return
	spark.top_level = true
	holder.add_child(spark)
	spark.global_position = at
	spark.scale = Vector3.ONE * 0.4

	var tween := spark.create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark, "scale", Vector3(1.8, 1.8, 1.8), 0.18)
	tween.tween_property(spark, "position:y", spark.position.y + 0.25, 0.18)
	tween.chain().tween_callback(spark.queue_free)


func _tint_mesh(color: Color) -> void:
	if _mesh == null or _mesh.mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35
	_mesh.material_override = mat


# ---- 给外部查询的状态 -----------------------------------------------------

func is_swinging() -> bool:
	return _state != State.IDLE


func get_state_name() -> String:
	return State.keys()[_state]


## 只赋予可点燃状态；重复涂油不直接点火，也不补充燃烧次数。
func apply_oil() -> void:
	oiled = true
	if not element.tags.has("flammable"):
		element.tags.append("flammable")
	if not element.tags.has("oil"):
		element.tags.append("oil")
	element_state_changed.emit()


func _apply_upgrade_tags() -> void:
	if data.upgrade_tags.has("oil"):
		apply_oil()


## 强化时收起剑，伤害与火焰接触暂停，避免隐藏剑仍产生交互。
func set_forge_locked(value: bool) -> void:
	interaction_locked = value
	visible = not value
	if not is_instance_valid(element) or not element.is_inside_tree():
		return
	if value:
		_state = State.IDLE
		_t = 0.0
		_close_hitbox()
		element.extinguish()
		element.set_physics_process(false)
		element.set_deferred("monitorable", false)
		element.set_deferred("monitoring", false)
	else:
		element.set_physics_process(true)
		element.set_deferred("monitorable", true)
		element.set_deferred("monitoring", true)


func is_burning() -> bool:
	return element.burning


func get_damage_tags() -> PackedStringArray:
	var result := data.damage_tags.duplicate()
	if is_burning() and not result.has("fire"):
		result.append("fire")
	return result


func _on_ignited() -> void:
	fire_swings_remaining = FIRE_SWINGS
	_count_fire_swing()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.55, 0.12)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.24, 0.02)
	material.emission_energy_multiplier = 1.8
	_mesh.material_override = material
	element_state_changed.emit()


func _count_fire_swing() -> void:
	if not is_burning() or _state == State.IDLE or _fire_counted_this_swing:
		return
	_fire_counted_this_swing = true
	fire_swings_remaining = maxi(0, fire_swings_remaining - 1)
	element_state_changed.emit()


func _on_extinguished() -> void:
	fire_swings_remaining = 0
	_mesh.material_override = _base_material
	element_state_changed.emit()
