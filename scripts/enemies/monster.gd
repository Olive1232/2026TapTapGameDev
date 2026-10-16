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
var _voice_delay := 0.0
## 与自主游走分开保存，避免僵直或下一帧游走覆盖受击冲量。
var _knockback_velocity: Vector3 = Vector3.ZERO

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Shape
@onready var _voice: AudioStreamPlayer3D = $Voice


func _ready() -> void:
	_rng.randomize()
	if data == null:
		data = MonsterData.new()
		push_warning("Monster「%s」没有设置 MonsterData，已用默认数值兜底。" % name)
	health = data.max_health
	if data.hole_ejectable:
		add_to_group("hole_ejectable")
	_voice.stream = data.voice_stream
	_voice_delay = _rng.randf_range(1.5, 6.0)
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
	_material.roughness = 0.92
	box.material = _material
	_mesh.mesh = box
	_mesh.material_override = _material
	# 网格抬高到半身高，让底面贴地。
	_mesh.position = Vector3(0, data.body_size.y * 0.5, 0)
	var previous := get_node_or_null("Model")
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	_mesh.visible = data.visual_scene == null
	if data.visual_scene != null:
		var model := data.visual_scene.instantiate() as Node3D
		model.name = "Model"
		if model.has_method("configure"):
			model.configure(data.body_size, _material, false)
		add_child(model)
	if _shape != null:
		var bs := BoxShape3D.new()
		bs.size = data.body_size
		_shape.shape = bs
		_shape.position = Vector3(0, data.body_size.y * 0.5, 0)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_update_voice(delta)

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
	var horizontal_velocity := walk_velocity + _knockback_velocity
	# 只保护贴地移动；出生下落、向上击飞与洞口喷飞仍使用真实重力。
	if data.avoid_ledges and velocity.y <= 0.0 and (is_on_floor() or _has_ground_at_feet()) and not _has_ground_ahead(horizontal_velocity, delta):
		_knockback_velocity = Vector3.ZERO
		horizontal_velocity = _turn_from_ledge(horizontal_velocity, delta) if _stun_timer <= 0.0 and _state == WanderState.WALK else Vector3.ZERO
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	# 重力（不设计跳跃，但需要贴地）。
	if not is_on_floor() or velocity.y > 0.0:
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity")) * delta
	else:
		velocity.y = 0.0

	move_and_slide()
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECELERATION * delta)
	_handle_wall_contact()


## 刷新点会把脚放在地面上方 0.05 米，首次落地前也要保护边缘。
func _has_ground_at_feet() -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.05, global_position - Vector3.UP * 0.1, CollisionLayers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.normal.dot(Vector3.UP) >= cos(floor_max_angle)


## 同时检查下一步的中心和身体前缘两侧，不把玩家、尸体或墙面当作地板。
func _has_ground_ahead(horizontal_velocity: Vector3, delta: float) -> bool:
	var distance := horizontal_velocity.length() * delta
	if distance <= 0.0001:
		return true
	var forward := horizontal_velocity.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	var half_x := global_basis.x * data.body_size.x * 0.5
	var half_z := global_basis.z * data.body_size.z * 0.5
	var reach := absf(half_x.dot(forward)) + absf(half_z.dot(forward)) + data.ledge_margin
	var width := (absf(half_x.dot(side)) + absf(half_z.dot(side))) * 0.8
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = CollisionLayers.WORLD
	query.collide_with_areas = false
	var space := get_world_3d().direct_space_state
	# 高速击退也逐段检查，不能一步跨过窄洞后只检测到另一侧地板。
	var steps := maxi(1, ceili(distance / 0.2))
	for step in range(1, steps + 1):
		var center := global_position + forward * distance * float(step) / float(steps)
		for offset in [Vector3.ZERO, forward * reach, forward * reach + side * width, forward * reach - side * width]:
			var at: Vector3 = center + offset
			query.from = at + Vector3.UP * 0.3
			query.to = at - Vector3.UP * data.ledge_max_drop
			var hit := space.intersect_ray(query)
			if hit.is_empty() or hit.normal.dot(Vector3.UP) < cos(floor_max_angle):
				return false
	return true


func _turn_from_ledge(blocked_velocity: Vector3, delta: float) -> Vector3:
	var blocked_direction := blocked_velocity.normalized()
	var turns := [PI, PI * 0.5, -PI * 0.5, PI * 0.75]
	for index in range(mini(data.max_turn_attempts, turns.size())):
		var direction := blocked_direction.rotated(Vector3.UP, turns[index])
		var candidate := direction * data.move_speed
		if not _has_ground_ahead(candidate, delta):
			continue
		_direction = direction
		rotation.y = atan2(-direction.x, -direction.z)
		_state_timer = _rng.randf_range(data.walk_duration_min, data.walk_duration_max)
		return candidate
	_state = WanderState.IDLE
	_state_timer = _rng.randf_range(data.idle_duration_min, data.idle_duration_max)
	return Vector3.ZERO


func _update_voice(delta: float) -> void:
	if _voice.stream == null:
		return
	_voice_delay -= delta
	if _voice_delay <= 0.0 and not _voice.playing:
		_voice.play()
		_voice_delay = _voice.stream.get_length() + _rng.randf_range(8.0, 16.0)


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
		_die(info.source)


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


func _die(by: Node3D = null) -> void:
	_dead = true
	remove_from_group("hole_ejectable")
	EventBus.enemy_died.emit(self)
	EventBus.enemy_killed.emit(self, by)
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
