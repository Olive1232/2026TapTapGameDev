extends Node3D

## 两处裂缝共享一次黄屏复位，正常行走与中央献祭洞不参与此流程。
signal recovery_started(rift: Area3D)
signal player_returned(rift: Area3D, at: Vector3)
signal recovery_finished

enum Phase { IDLE, YELLOW_IN, HOLD, YELLOW_OUT }
@export var player_path: NodePath = NodePath("../Player")
@export_range(0.1, 3.0, 0.05) var yellow_in_time := 0.85
@export_range(0.0, 1.0, 0.05) var covered_time := 0.12
@export_range(0.1, 3.0, 0.05) var yellow_out_time := 1.1
@export var yellow_color := Color(1.0, 0.8, 0.08, 1.0)
var _phase := Phase.IDLE
var _elapsed := 0.0
var _active_rift: Area3D
var _return_position := Vector3.ZERO
var _last_safe_position := Vector3.ZERO
var _has_safe_position := false

@onready var _player: CharacterBody3D = get_node(player_path)
@onready var _yellow: ColorRect = $Screen/Yellow


func _ready() -> void:
	_set_yellow(0.0)


func is_recovering() -> bool:
	return _phase != Phase.IDLE


func get_yellow_amount() -> float:
	return _yellow.color.a


func _input(event: InputEvent) -> void:
	# 菜单照常可暂停；黄屏期间不推进对白、不挥剑或松开手持物。
	if is_recovering() and not get_tree().paused and not event.is_action("ui_cancel"):
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player) or _player.is_queued_for_deletion():
		return
	if _phase == Phase.IDLE:
		var feet: Vector3 = _player._feet_position()
		for rift in $Rifts.get_children():
			if rift.contains_fall(feet):
				_begin_recovery(rift)
				return
		# 记录留出身体余量的最后落脚点，优先把玩家放回掉落前所在的一侧。
		if _player.is_on_floor() and _away_from_edges(feet):
			_last_safe_position = _player.global_position
			_has_safe_position = true
		return
	_elapsed += delta
	match _phase:
		Phase.YELLOW_IN:
			_set_yellow(smoothstep(0.0, yellow_in_time, _elapsed))
			if _elapsed >= yellow_in_time:
				_player.recover_from_fall(_return_position)
				_phase = Phase.HOLD
				_elapsed = 0.0
				player_returned.emit(_active_rift, _return_position)
		Phase.HOLD:
			if _elapsed >= covered_time:
				_phase = Phase.YELLOW_OUT
				_elapsed = 0.0
		Phase.YELLOW_OUT:
			_set_yellow(1.0 - smoothstep(0.0, yellow_out_time, _elapsed))
			if _elapsed >= yellow_out_time:
				_set_yellow(0.0)
				_phase = Phase.IDLE
				_active_rift = null
				_player.set_rift_recovery_locked(false)
				recovery_finished.emit()


func _begin_recovery(rift: Area3D) -> void:
	var candidates: Array[Vector3] = rift.get_bank_points()
	var origin := _player.global_position
	candidates.sort_custom(func(a: Vector3, b: Vector3):
		return Vector2(a.x-origin.x, a.z-origin.z).length_squared() < Vector2(b.x-origin.x, b.z-origin.z).length_squared())
	if _has_safe_position and Vector2(_last_safe_position.x-origin.x, _last_safe_position.z-origin.z).length() < 10.0:
		candidates.push_front(_last_safe_position)
	for at in candidates:
		if not _is_safe_return(at):
			continue
		_return_position = at
		_active_rift = rift
		_phase = Phase.YELLOW_IN
		_elapsed = 0.0
		_player.set_rift_recovery_locked(true)
		_player.get_node("Camera3D/Grabber").cancel_throw_charge()
		recovery_started.emit(rift)
		return


func _away_from_edges(point: Vector3) -> bool:
	for rift in $Rifts.get_children():
		if rift.contains_footprint(point) or rift.edge_distance(point) < 1.5:
			return false
	return true


func _is_safe_return(at: Vector3) -> bool:
	if not _away_from_edges(at):
		return false
	var shape: CollisionShape3D = _player.get_node("CollisionShape3D")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = Transform3D(_player.global_basis, at) * shape.transform
	query.collision_mask = _player.collision_mask
	query.exclude = [_player.get_rid()]
	var space := _player.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return false
	var box := shape.shape as BoxShape3D
	var feet := query.transform * Vector3(0, -box.size.y * 0.5, 0)
	# 同时检查脚底四角，不能把身体一半悬空的位置当作安全落点。
	for corner in [Vector3.ZERO, Vector3(-0.5,0,-0.5), Vector3(-0.5,0,0.5), Vector3(0.5,0,-0.5), Vector3(0.5,0,0.5)]:
		var foot: Vector3 = feet + _player.global_basis * Vector3(corner.x * box.size.x, 0, corner.z * box.size.z)
		var ray := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 0.15, foot - Vector3.UP * 0.3, _player.collision_mask)
		ray.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < cos(_player.floor_max_angle):
			return false
	return true


func _set_yellow(amount: float) -> void:
	_yellow.color = Color(yellow_color, clampf(amount, 0.0, 1.0))
	_yellow.visible = amount > 0.0


func _exit_tree() -> void:
	if is_recovering() and is_instance_valid(_player):
		_player.set_rift_recovery_locked(false)
