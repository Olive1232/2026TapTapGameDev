extends Area3D

## 在连接通道两端之间穿过才算离房；同侧折返和进房不会触发。
signal room_left(room: Node3D)

@export var room_id: StringName = &"cleaning"
## 通道节点的本地坐标；方向指向房间内部，判定平面经过节点原点。
@export var room_direction := Vector3.RIGHT
@export var room_bounds := AABB(Vector3(0, -5, -12), Vector3(18, 14, 24))
## 有真实地图地板时按脚下地板划分房间，避免包围盒重叠误收另一房间。
@export var room_floor_path: NodePath
## 原始模型共用地板碰撞时，使用独立房间体积划分回收归属。
@export var room_volume_path: NodePath
var _room_floor: StaticBody3D
var _room_volume: CollisionShape3D
var _entered_from_room: Dictionary = {}


func _ready() -> void:
	if not room_floor_path.is_empty():
		_room_floor = get_node_or_null(room_floor_path) as StaticBody3D
	if not room_volume_path.is_empty():
		_room_volume = get_node_or_null(room_volume_path) as CollisionShape3D
	collision_layer = 0
	collision_mask = CollisionLayers.PLAYER
	monitorable = false
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)


func _side(body: Node3D) -> float:
	return to_local(body.global_position).dot(room_direction.normalized())


func _on_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.has_method("set_carry_weight"):
		_entered_from_room[body.get_instance_id()] = _side(body) > 0.0


func _on_exited(body: Node3D) -> void:
	var id := body.get_instance_id()
	var from_room: bool = _entered_from_room.get(id, false)
	_entered_from_room.erase(id)
	if from_room and not body.is_queued_for_deletion() and _side(body) < 0.0:
		room_left.emit(self)


func contains_corpse(corpse: Corpse) -> bool:
	if not room_volume_path.is_empty():
		if not is_instance_valid(_room_volume) or _room_volume.disabled or not _room_volume.shape is BoxShape3D:
			return false
		var size: Vector3 = _room_volume.shape.size
		return AABB(-size * 0.5, size).has_point(_room_volume.to_local(corpse.global_position))
	if room_floor_path.is_empty():
		return room_bounds.has_point(to_local(corpse.global_position))
	if not is_instance_valid(_room_floor):
		return false
	var ray := PhysicsRayQueryParameters3D.create(corpse.global_position + Vector3.UP * 0.2, corpse.global_position - Vector3.UP * 64.0, CollisionLayers.WORLD)
	# 货架、台面等室内物体不改变房间归属，继续查它们下方的地图地板。
	for attempt in range(8):
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			return false
		var body := hit.collider as PhysicsBody3D
		if body == _room_floor:
			return true
		if body == null or body.get_parent() == _room_floor.get_parent():
			return false
		var excluded := ray.exclude
		excluded.append(body.get_rid())
		ray.exclude = excluded
	return false
