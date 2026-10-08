class_name Monster
extends CharacterBody3D

## 怪物基类。
##
## 需求约束（重要，决定了本类为什么没有攻击逻辑）：
##   - 怪物**不会对玩家造成伤害** → 没有攻击状态、没有伤害输出
##   - 有**血量**和属性
##   - 有**随机的运动方式** → 走-停-换方向的随机游走
##   - 死亡后掉落**有价值的尸体**，可被抓取
##
## 所以本类比常规敌人简单得多：只有"游走 / 受击 / 死亡"三件事。

## 怪物数据。策划改 .tres 即可加新怪种。
@export var data: MonsterData

## 随机游走状态。
enum WanderState { IDLE, WALK }

const CORPSE_SCENE := preload("res://scenes/enemies/corpse.tscn")
## 水平击退每秒衰减的速度（米/秒²）。
const KNOCKBACK_DECELERATION := 12.0

var health: float = 0.0
var _state: WanderState = WanderState.IDLE
var _state_timer: float = 0.0
var _stun_timer: float = 0.0
var _direction: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _material: StandardMaterial3D
var _dead: bool = false
## 与自主游走分开保存，避免僵直或下一帧游走覆盖受击冲量。
var _knockback_velocity: Vector3 = Vector3.ZERO

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Shape


func _ready() -> void:
	_rng.randomize()
	if data == null:
		data = MonsterData.new()
		push_warning("Monster「%s」没有设置 MonsterData，已用默认数值兜底。" % name)
	health = data.max_health
	# 生物属于 ENEMY 层，被剑的伤害区域探测；与地形碰撞。
	collision_layer = CollisionLayers.ENEMY
	collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER
	_apply_visual()
	_pick_new_state()


func _apply_visual() -> void:
	if _mesh == null:
		return
	var box := BoxMesh.new()
	box.size = data.body_size
	_material = StandardMaterial3D.new()
	_material.albedo_color = data.body_color
	box.material = _material
	_mesh.mesh = box
	_mesh.material_override = _material
	# 网格抬高到半身高，让底面贴地。
	_mesh.position = Vector3(0, data.body_size.y * 0.5, 0)
	if _shape != null:
		var bs := BoxShape3D.new()
		bs.size = data.body_size
		_shape.shape = bs
		_shape.position = Vector3(0, data.body_size.y * 0.5, 0)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	# 僵直只暂停自主游走；击退、重力与碰撞仍由物理帧处理。
	var walk_velocity := Vector3.ZERO
	if _stun_timer > 0.0:
		_stun_timer = maxf(0.0, _stun_timer - delta)
	else:
		_state_timer -= delta
		if _state_timer <= 0.0:
			_pick_new_state()
		if _state == WanderState.WALK:
			walk_velocity = _direction * data.move_speed
	velocity.x = walk_velocity.x + _knockback_velocity.x
	velocity.z = walk_velocity.z + _knockback_velocity.z

	# 重力（不设计跳跃，但需要贴地）。
	if not is_on_floor() or velocity.y > 0.0:
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity")) * delta
	else:
		velocity.y = 0.0

	move_and_slide()
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECELERATION * delta)
	_handle_wall_contact()


## 撞墙就换方向。没有这个的话怪物会一直顶着墙抖。
func _handle_wall_contact() -> void:
	if get_slide_collision_count() == 0:
		return
	if _state != WanderState.WALK:
		return
	for i in range(mini(get_slide_collision_count(), data.max_turn_attempts)):
		var col := get_slide_collision(i)
		var normal := col.get_normal()
		# 只处理"墙面"（法线接近水平）的碰撞，忽略地面。
		if absf(normal.y) > 0.7:
			continue
		# 沿墙面反射出一个新方向。
		_direction = (_direction - 2.0 * _direction.dot(normal) * normal).normalized()
		_direction.y = 0.0
		_direction = _direction.normalized()
		_state_timer = _rng.randf_range(data.walk_duration_min, data.walk_duration_max)
		return


func _pick_new_state() -> void:
	if _state == WanderState.WALK:
		_state = WanderState.IDLE
		_state_timer = _rng.randf_range(data.idle_duration_min, data.idle_duration_max)
	else:
		_state = WanderState.WALK
		_state_timer = _rng.randf_range(data.walk_duration_min, data.walk_duration_max)
		_direction = _random_direction()
		# 立刻转向新方向，避免"平移"的怪感。
		if _direction.length_squared() > 0.0001:
			var target_yaw := atan2(-_direction.x, -_direction.z)
			rotation.y = target_yaw


func _random_direction() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	return Vector3(sin(angle), 0.0, cos(angle)).normalized()


# ---- 受击与死亡 ----------------------------------------------------------

## 剑的伤害入口（与 TargetDummy 同一约定）。
func take_hit(info: HitInfo) -> void:
	if _dead:
		return
	health -= info.damage
	_flash()
	_stun_timer = data.hit_stun
	# 水平冲量独立保留并衰减；竖直冲量继续由重力和碰撞处理。
	var impulse := info.knockback * 0.4
	_knockback_velocity += Vector3(impulse.x, 0.0, impulse.z)
	velocity += impulse
	if health <= 0.0:
		_die()


func get_hit_center() -> Vector3:
	return global_position + Vector3(0, data.body_size.y * 0.5, 0)


func get_health_ratio() -> float:
	if data.max_health <= 0.0:
		return 1.0
	return clampf(health / data.max_health, 0.0, 1.0)


func _flash() -> void:
	if _material == null:
		return
	var base := _material.albedo_color
	_material.albedo_color = Color(1, 1, 1)
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color", base, 0.12)


func _die() -> void:
	_dead = true
	EventBus.enemy_died.emit(self)
	_spawn_corpse()
	queue_free()


func _spawn_corpse() -> void:
	var corpse := CORPSE_SCENE.instantiate() as Corpse
	if corpse == null:
		return
	corpse.setup(data)
	# 挂到场景根而不是本节点下——本节点马上要被释放。
	var host := get_parent()
	if host == null:
		return
	host.add_child(corpse)
	corpse.global_position = global_position + Vector3(0, data.body_size.y * 0.5, 0)
	EventBus.corpse_spawned.emit(corpse)
