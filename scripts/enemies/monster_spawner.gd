@tool
class_name MonsterSpawner
extends Marker3D

## 可摆放的怪物刷新点。只统计本点生成的存活怪物，尸体不占名额。
const MONSTER_SCENE := preload("res://scenes/enemies/monster.tscn")
const PLACEMENT_ATTEMPTS := 12

@export_group("怪物种类")
## 拖入 MonsterData 资源，例如 monster_cockroach.tres / monster_rat.tres。
@export var monster_data: MonsterData = preload("res://resources/enemies/monster_cockroach.tres"):
	set(value):
		monster_data = value
		_elapsed = 0.0
		if is_inside_tree():
			update_configuration_warnings()

@export_group("刷新规则")
## 关闭时停止计时；重新启用后等待一个完整间隔。
@export var enabled: bool = true:
	set(value):
		enabled = value
		_elapsed = 0.0
## 本点的存活上限。0 = 不生成；降低上限不会销毁已有怪物。
@export_range(0, 100, 1, "or_greater") var max_alive: int = 5:
	set(value):
		max_alive = maxi(0, value)
## 秒。每个间隔最多生成一只，不在满额 / 暂停期间积累补刷。
@export_range(0.1, 60.0, 0.1, "or_greater") var spawn_interval: float = 3.0:
	set(value):
		spawn_interval = maxf(0.1, value) if is_finite(value) else 0.1
		_elapsed = 0.0

@export_group("生成位置")
## 在点周围的 XZ 圆盘内随机生成；0 = 只在点中心尝试。
@export_range(0.0, 20.0, 0.1, "or_greater") var spawn_radius: float = 2.0:
	set(value):
		spawn_radius = maxf(0.0, value) if is_finite(value) else 0.0

var _elapsed: float = 0.0
var _alive: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rng.randomize()
	EventBus.enemy_died.connect(_on_enemy_died)


func _exit_tree() -> void:
	if not Engine.is_editor_hint() and EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.disconnect(_on_enemy_died)
	_alive.clear()


func _get_configuration_warnings() -> PackedStringArray:
	if monster_data == null:
		return PackedStringArray(["请选择 Monster Data；未设置怪物数据时不会刷新。"])
	return PackedStringArray()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not enabled or monster_data == null or get_alive_count() >= max_alive:
		_elapsed = 0.0
		return
	_elapsed += delta
	if _elapsed + 0.000001 < spawn_interval:
		return
	# 卡顿时也只生成一只，不一次补齐之前错过的间隔。
	_elapsed = 0.0
	_spawn_one()


func _spawn_one() -> void:
	var shape := CylinderShape3D.new()
	# 圆柱覆盖身体任意 yaw 的占地，避免出生后随机转向造成重叠。
	shape.radius = Vector2(monster_data.body_size.x, monster_data.body_size.z).length() * 0.5 + 0.1
	shape.height = maxf(0.05, monster_data.body_size.y)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER | CollisionLayers.ENEMY
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.margin = 0.01
	var attempts := 1 if is_zero_approx(spawn_radius) else PLACEMENT_ATTEMPTS
	for _attempt in range(attempts):
		var angle := _rng.randf_range(0.0, TAU)
		var radius := sqrt(_rng.randf()) * spawn_radius
		var at := global_position + Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
		query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * shape.height * 0.5)
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		var monster := MONSTER_SCENE.instantiate() as Monster
		monster.data = monster_data
		# 先配置本地出生变换，再进树，避免在原点短暂出现碰撞体。
		monster.position = to_local(at)
		var id := monster.get_instance_id()
		_alive[id] = monster
		monster.tree_exiting.connect(_on_monster_tree_exiting.bind(id))
		add_child(monster)
		EventBus.enemy_spawned.emit(monster)
		return


func _on_enemy_died(monster: Node3D) -> void:
	_alive.erase(monster.get_instance_id())


func _on_monster_tree_exiting(id: int) -> void:
	_alive.erase(id)


func get_alive_count() -> int:
	return _alive.size()


## 调试和关卡逻辑可读取本点怪物；调用方不应持久保存这些节点引用。
func get_spawned_monsters() -> Array[Monster]:
	var monsters: Array[Monster] = []
	for candidate: Variant in _alive.values():
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			monsters.append(candidate)
	return monsters
