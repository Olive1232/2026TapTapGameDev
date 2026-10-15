extends Node3D

## 尸体出口。离房时在本处重新出现，再通过物理速度移向中央洞。
signal corpse_transferred(corpse: Corpse, room_id: StringName)

@export var hole_path: NodePath = NodePath("../Hole")
@export var room_paths: Array[NodePath] = []
@export_range(0.1, 10.0, 0.1) var move_speed: float = 2.5
var _enabled := false
var _hole: Hole
var _rooms: Array[Node3D] = []
var _pending_rooms: Array[Node3D] = []
var _moving: Dictionary = {}


func _ready() -> void:
	_hole = get_node_or_null(hole_path) as Hole
	for path in room_paths:
		var room := get_node_or_null(path) as Node3D
		if room != null and room.has_signal("room_left") and room.has_method("contains_corpse"):
			_rooms.append(room)
			room.room_left.connect(_on_room_left)
	set_physics_process(false)
	_update_sign()


func can_enable() -> bool:
	return not _enabled and is_instance_valid(_hole) and not _hole.is_queued_for_deletion() and not _rooms.is_empty()


func enable() -> void:
	_enabled = true
	set_physics_process(true)
	_update_sign()


func is_enabled() -> bool:
	return _enabled


func _on_room_left(room: Node3D) -> void:
	# 信号回调仅排队，物理帧执行转移；暂停时保留请求但不移动。
	if _enabled and not _pending_rooms.has(room):
		_pending_rooms.append(room)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_hole) or _hole.is_queued_for_deletion():
		_stop_all()
		return
	for room in _pending_rooms:
		if is_instance_valid(room):
			_transfer_room(room)
	_pending_rooms.clear()
	for id in _moving.keys():
		var corpse := _moving[id] as Corpse
		if not is_instance_valid(corpse) or corpse.is_queued_for_deletion() or corpse.is_held:
			_moving.erase(id)
			continue
		if _hole.is_in_attraction_range(corpse):
			_moving.erase(id)
			continue
		var direction := _hole.global_position - corpse.global_position
		direction.y = 0.0
		direction = direction.normalized()
		corpse.sleeping = false
		corpse.linear_velocity.x = direction.x * move_speed
		corpse.linear_velocity.z = direction.z * move_speed


func _transfer_room(room: Node3D) -> void:
	for candidate in get_tree().get_nodes_in_group("corpses"):
		var corpse := candidate as Corpse
		if corpse == null or corpse.is_queued_for_deletion() or corpse.is_held or _moving.has(corpse.get_instance_id()) or _hole.is_in_attraction_range(corpse) or not room.contains_corpse(corpse):
			continue
		var at: Transform3D = $SpawnPoint.global_transform
		var target := Vector3(_hole.global_position.x, at.origin.y, _hole.global_position.z)
		at = at.looking_at(target, Vector3.UP)
		if not corpse.relocate_for_return(at):
			continue
		var id := corpse.get_instance_id()
		_moving[id] = corpse
		var callback := _on_corpse_exiting.bind(id)
		if not corpse.tree_exiting.is_connected(callback):
			corpse.tree_exiting.connect(callback)
		corpse_transferred.emit(corpse, room.room_id)


func _on_corpse_exiting(id: int) -> void:
	_moving.erase(id)


func _stop_all() -> void:
	for corpse in _moving.values():
		if is_instance_valid(corpse) and not corpse.is_held and not corpse.is_queued_for_deletion():
			corpse.linear_velocity.x = 0.0
			corpse.linear_velocity.z = 0.0
	_moving.clear()
	_pending_rooms.clear()
	set_physics_process(false)


func _exit_tree() -> void:
	_stop_all()


func moving_count() -> int:
	return _moving.size()


func _update_sign() -> void:
	$Sign.text = "尸体出口\n离开房间后自动回收" if _enabled else "尸体出口\n购买灵魂鸡蛋后启用"
