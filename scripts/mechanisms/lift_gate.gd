@tool
class_name LiftGate
extends Node3D

## 根节点原点是关闭门的底部中心；门扇与碰撞一起移动。
signal opened
signal closed
signal blocked_changed(blocked: bool)

@export_node_path("Node3D") var platform_path: NodePath
## 门扇可缩入这些固定岩壁 / 门框；玩家、怪物及尸体仍参与防夹检测。
@export var frame_collision_paths: Array[NodePath] = []
@export var leaf_size := Vector3(3.0, 3.0, 0.3):
	set(value):
		leaf_size = value.max(Vector3.ONE * 0.1)
		_update_geometry()
## 门根节点的局部坐标方向，随机关整体平移 / 旋转。
@export var open_offset := Vector3(0, 3.4, 0)
@export_range(0.1, 20.0, 0.1) var move_speed: float = 2.5
## 默认首次开门后保持开启，离房回收或烧毁尸体不会重新锁路。
@export var latch_open := true
## 同一扇门移植到新地图时保留此编号；留空则不写入存档。
@export var persistence_id: StringName
@export var show_placeholder := true:
	set(value):
		show_placeholder = value
		_update_geometry()

var _platform: WeightPlatform
var _requested_open := false
var _latched := false
var _blocked := false
var _at_open := false
var _at_closed := true
var _permanently_opened := false
var _restore_pending := false
var _sweep_shape: BoxShape3D


func _ready() -> void:
	_update_geometry()
	set_physics_process(not Engine.is_editor_hint())
	if Engine.is_editor_hint():
		return
	add_to_group(&"persistent_gates")
	if not platform_path.is_empty():
		_platform = get_node_or_null(platform_path) as WeightPlatform
		if _platform != null:
			_platform.pressed_changed.connect(set_open_requested)
			_platform.tree_exiting.connect(_on_platform_exiting)
			set_open_requested(_platform.is_pressed())
		else:
			push_warning("LiftGate: platform_path 未指向配重平台：" + str(platform_path))


func _update_geometry() -> void:
	if not is_node_ready():
		return
	var shape := BoxShape3D.new()
	shape.size = leaf_size
	$Leaf/Shape.shape = shape
	$Leaf/Shape.position.y = leaf_size.y * 0.5
	_sweep_shape = BoxShape3D.new()
	# 略收边，避免与门框 / 地板接触时被浮点误差卡住。
	_sweep_shape.size = leaf_size - Vector3.ONE * 0.04
	var mesh := BoxMesh.new()
	mesh.size = leaf_size
	$Leaf/Visuals/Placeholder.mesh = mesh
	$Leaf/Visuals/Placeholder.position.y = leaf_size.y * 0.5
	$Leaf/Visuals/Placeholder.visible = show_placeholder


func set_open_requested(value: bool) -> void:
	_requested_open = value
	if value and latch_open:
		_latched = true


func _on_platform_exiting() -> void:
	set_open_requested(false)


func _physics_process(delta: float) -> void:
	var target := open_offset if _requested_open or (latch_open and _latched) else Vector3.ZERO
	var leaf := $Leaf as AnimatableBody3D
	if _restore_pending:
		# AnimatableBody 暂时回退节点位置，下一物理帧才回传新位置。
		# 在确认回传前不运行普通渐进运动，避免覆盖载入时的目标。
		leaf.position = open_offset
		_at_open = leaf.position.is_equal_approx(open_offset)
		_at_closed = false
		_restore_pending = not _at_open
		if _at_open:
			leaf.reset_physics_interpolation()
		return
	var next := leaf.position.move_toward(target, move_speed * delta)
	var motion := global_basis * (next - leaf.position)
	var blocked := false
	if not motion.is_zero_approx():
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _sweep_shape
		query.transform = $Leaf/Shape.global_transform
		query.motion = motion
		query.margin = 0.005
		query.collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER | CollisionLayers.ENEMY | CollisionLayers.PICKUP
		var excluded: Array[RID] = [leaf.get_rid()]
		for path in frame_collision_paths:
			var frame := get_node_or_null(path) as StaticBody3D
			if frame != null:
				excluded.append(frame.get_rid())
		query.exclude = excluded
		var space := get_world_3d().direct_space_state
		# cast_motion 不报告起点已有的重叠，先覆盖出生 / 转移进门扇的情况。
		blocked = not space.intersect_shape(query, 1).is_empty()
		if not blocked:
			var fractions := space.cast_motion(query)
			blocked = fractions.size() == 2 and fractions[0] < 1.0
		if not blocked:
			leaf.position = next
	if blocked != _blocked:
		_blocked = blocked
		blocked_changed.emit(blocked)
	var at_open := leaf.position.is_equal_approx(open_offset)
	var at_closed := leaf.position.is_zero_approx()
	var just_opened := at_open and not _at_open
	var just_closed := at_closed and not _at_closed
	_at_open = at_open
	_at_closed = at_closed
	if just_opened:
		if latch_open and _latched:
			_permanently_opened = true
		opened.emit()
	if just_closed:
		closed.emit()


func is_open() -> bool:
	return _at_open


func is_closed() -> bool:
	return _at_closed


func is_blocked() -> bool:
	return _blocked


func get_persistence_id() -> StringName:
	return persistence_id if latch_open else &""


func is_persistently_open() -> bool:
	return latch_open and _permanently_opened


func can_restore_persistent_open() -> bool:
	return latch_open


func restore_persistent_open() -> void:
	var leaf := $Leaf as AnimatableBody3D
	_restore_pending = true
	leaf.position = open_offset
	_requested_open = false
	_latched = true
	_permanently_opened = true
	_at_open = false
	_at_closed = false
	_blocked = false
