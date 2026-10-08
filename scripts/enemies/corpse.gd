class_name Corpse
extends RigidBody3D

## 怪物尸体。可被玩家抓取（物品属性），带价值。
##
## 抓取方式：**软跟随**，不是把它 parent 到相机上。
## 每物理帧把它推向相机前方的持有点——这样它会自然撞墙、被门框挡住，
## 而不是硬穿墙。硬 parent 会导致尸体穿过几何体，也会让物理引擎报警告。
##
## 持有期间关掉与玩家层的碰撞，避免尸体系在玩家身上把玩家顶飞。

## 尸体价值——洞据此决定喷多少钱。由 MonsterData.corpse_value 填入。
@export var value: int = 1
## 重量——影响玩家扛着它时的移速。
@export var weight: float = 1.0
## 存在时长（秒）。<=0 表示永不超时。
@export var lifetime: float = 30.0

## 被抓住时，多远算"拿在手上"（用于判断是否已到位）。
const HOLD_ARRIVE_EPSILON := 0.15
## 软跟随的跟随强度（越大越贴身，越小越"拖沓"）。
@export var follow_stiffness: float = 30.0
## 跟随速度上限（米/秒），避免瞬间弹到手上。
@export var follow_max_speed: float = 12.0

## 正在被玩家持有。
var is_held: bool = false

var _holder: Node3D = null
var _hold_point: Node3D = null
var _age: float = 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	# 尸体属于 PICKUP 层（供抓取射线探测），与地形和玩家碰撞。
	# 不与武器层（ENEMY）碰撞——尸体不该被剑砍。
	collision_layer = CollisionLayers.PICKUP
	collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER
	gravity_scale = 1.0
	# 静置后休眠，省性能；被抓住时唤醒。
	can_sleep = true
	_apply_visual()


## 由生成方（Monster）调用，把美术/数值填进来。
func setup(data: MonsterData) -> void:
	value = data.corpse_value
	weight = data.corpse_weight
	lifetime = data.corpse_lifetime
	_pending_data = data
	if is_inside_tree():
		_apply_visual()


var _pending_data: MonsterData = null


func _apply_visual() -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var size := Vector3(0.5, 0.25, 0.7)
	var color := Color(0.45, 0.3, 0.25)
	if _pending_data != null:
		size = _pending_data.get_corpse_size()
		color = _pending_data.get_corpse_color()
	# 尸体是"躺在地上的"——把高度压扁一点，看起来像倒了。
	var box := BoxMesh.new()
	box.size = Vector3(size.x, maxf(size.y * 0.6, 0.08), size.z)
	mesh.mesh = box
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	mesh.material_override = _material
	# 碰撞体跟着走，这样尸体能被地形挡住。
	var shape := get_node_or_null("Shape") as CollisionShape3D
	if shape != null:
		var bs := BoxShape3D.new()
		bs.size = box.size
		shape.shape = bs


func _physics_process(delta: float) -> void:
	if not is_held:
		if lifetime > 0.0:
			_age += delta
			if _age >= lifetime:
				_expire()
		return

	if _hold_point == null:
		return

	# 软跟随：朝相机前方的持有点推进。
	var target := _hold_point.global_position
	var to_target := target - global_position
	# 到位后不再推，避免抖动。
	if to_target.length() < HOLD_ARRIVE_EPSILON:
		linear_velocity = Vector3.ZERO
		return
	# 限速，避免瞬间弹到手上（看起来像瞬移）。
	linear_velocity = (to_target * follow_stiffness).limit_length(follow_max_speed)


# ---- 抓取 ----------------------------------------------------------------

## 被抓住。holder = 玩家，hold_point = 相机前方的持有点。
func grab(holder: Node3D, hold_point: Node3D) -> void:
	if is_held:
		return
	is_held = true
	_holder = holder
	_hold_point = hold_point
	_age = 0.0
	# 持有期间不与玩家碰撞，否则会把玩家顶飞/卡住。
	collision_mask = CollisionLayers.WORLD
	# 关掉重力，否则它会被拽在地上"拖行"，而不是被提起来。
	# 仍与 WORLD 碰撞，所以撞墙会被正常挡住。
	gravity_scale = 0.0
	sleeping = false
	EventBus.corpse_grabbed.emit(self)


## 放下。throw_forward 为 true 时向前抛一点。
func release(throw_forward: bool = false) -> void:
	if not is_held:
		return
	is_held = false
	# 恢复重力与玩家碰撞，让它正常落回地面。
	gravity_scale = 1.0
	collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER
	var push := Vector3.ZERO
	if _hold_point != null:
		push = -_hold_point.global_transform.basis.z * (2.5 if throw_forward else 0.5)
	linear_velocity = push + _holder_velocity()
	_holder = null
	_hold_point = null
	EventBus.corpse_released.emit(self)


func _holder_velocity() -> Vector3:
	if _holder is CharacterBody3D:
		return (_holder as CharacterBody3D).velocity * 0.5
	return Vector3.ZERO


## 供抓取射线判断"是不是能拿的东西"。
func can_be_grabbed() -> bool:
	return not is_held


func _expire() -> void:
	# 超时回收。持有引用的系统必须借此释放。
	EventBus.corpse_expired.emit(self)
	if is_held:
		release()
	queue_free()
