@tool
class_name FlammableProp
extends StaticBody3D

## 藤蔓 / 草占位实体。燃烧结束才移除碰撞，普通剑不能砍开。
@export var size := Vector3(1.2, 3.2, 0.35):
	set(value):
		size = value.max(Vector3.ONE * 0.01)
		_update_geometry()
@export var tint := Color(0.13, 0.38, 0.16):
	set(value):
		tint = value
		_update_geometry()
@export var blocks_movement := true:
	set(value):
		blocks_movement = value
		_update_geometry()
@export var climbable := true
## 燃烧销毁后等待多少秒在原位刷新；0 秒表示永不刷新。
@export_range(0.0, 3600.0, 0.1, "or_greater", "suffix:s") var respawn_delay: float = 0.0

@onready var element: ElementComponent = $ElementComponent
var _material: StandardMaterial3D
var _waiting_for_respawn := false
var _respawn_remaining := 0.0


func _ready() -> void:
	_update_geometry()
	set_physics_process(false)
	if not Engine.is_editor_hint():
		element.destroy_parent_on_burn_down = false
		element.ignited.connect(_on_ignited)
		element.burned_down.connect(_on_burned_down)


func _on_burned_down() -> void:
	if respawn_delay <= 0.0:
		queue_free()
		return
	_waiting_for_respawn = true
	_respawn_remaining = respawn_delay
	element.extinguish()
	# 禁用元素节点会一并移出物理检测，等待期间不能传火或被重新点燃。
	element.process_mode = Node.PROCESS_MODE_DISABLED
	$Shape.set_deferred("disabled", true)
	hide()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_respawn_remaining -= delta
	if _respawn_remaining > 0.0:
		return
	_respawn_remaining = 0.0
	_waiting_for_respawn = false
	set_physics_process(false)
	_material.albedo_color = tint
	$Shape.set_deferred("disabled", false)
	element.process_mode = Node.PROCESS_MODE_INHERIT
	show()


## 编辑器和运行时共用外形，拖入地图即可预览尺寸；生成节点不写入场景文件。
func _update_geometry() -> void:
	if not is_node_ready():
		return
	collision_layer = CollisionLayers.WORLD if blocks_movement else 0
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	$Shape.shape = shape
	$Shape.position.y = size.y * 0.5
	$ElementComponent.position.y = size.y * 0.5
	if not Engine.is_editor_hint():
		element.set_flame_coverage(size)
	_material = StandardMaterial3D.new()
	_material.albedo_color = tint
	_material.roughness = 0.9
	var previous := get_node_or_null("GeneratedVisuals")
	if previous != null:
		previous.free()
	var visuals := Node3D.new()
	visuals.name = "GeneratedVisuals"
	add_child(visuals)
	# 交错藤条与叶片，碰撞仍是整片障碍。
	for i in range(5):
		var stem := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x * 0.095, size.y, size.z * 0.45)
		mesh.material = _material
		stem.mesh = mesh
		stem.position = Vector3((i - 2) * size.x * 0.2, size.y * 0.5, sin(i * 2.0) * size.z * 0.25)
		stem.rotation.z = (i - 2) * 0.045
		visuals.add_child(stem)
		for j in range(4):
			var leaf := MeshInstance3D.new()
			var leaf_mesh := BoxMesh.new()
			leaf_mesh.size = Vector3(size.x * 0.23, size.y * 0.065, size.z * 0.9)
			leaf_mesh.material = _material
			leaf.mesh = leaf_mesh
			leaf.position = Vector3(stem.position.x, size.y * (j + 0.6) / 4.0, stem.position.z)
			leaf.rotation.z = 0.4 if (i + j) % 2 == 0 else -0.4
			visuals.add_child(leaf)
	if not Engine.is_editor_hint() and element.burning:
		_on_ignited()


func _on_ignited() -> void:
	_material.albedo_color = tint.darkened(0.55)


func take_hit(info: HitInfo) -> void:
	if _waiting_for_respawn:
		return
	if info.tags.has("fire"):
		var at := global_position
		if is_instance_valid(info.source):
			at = info.source.global_position + Vector3.UP
		element.ignite_from(info.source, at)


func get_hit_center() -> Vector3:
	return global_position + Vector3.UP * size.y * 0.5


func can_climb() -> bool:
	return climbable and blocks_movement and not _waiting_for_respawn and not is_queued_for_deletion()


func get_climb_top() -> Vector3:
	# 倾斜或旋转后，顶沿的角点会高于中心；脚部越过整个顶沿才能安全跨上去。
	var top := to_global(Vector3(0, size.y, 0))
	for x in [-0.5, 0.5]:
		for z in [-0.5, 0.5]:
			var corner := to_global(Vector3(size.x * x, size.y, size.z * z))
			if corner.y > top.y:
				top = corner
	return top
