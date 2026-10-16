@tool
extends StaticBody3D

## 本地 Y 轴连接绳索两端，复用剑、火把与可燃物的实际传火逻辑。
@export_range(0.2, 30.0, 0.1) var length := 6.0:
	set(value):
		length = maxf(value, 0.2)
		_update_geometry()

@onready var element: ElementComponent = $ElementComponent
var _material: StandardMaterial3D


func _ready() -> void:
	_update_geometry()
	if not Engine.is_editor_hint():
		element.ignited.connect(func(): _material.albedo_color = Color(0.18, 0.09, 0.035))


func _update_geometry() -> void:
	if not is_node_ready():
		return
	var solid := CapsuleShape3D.new()
	solid.radius = 0.14
	solid.height = length
	$Shape.shape = solid
	var contact := CapsuleShape3D.new()
	contact.radius = 0.23
	contact.height = length
	$ElementComponent/Shape.shape = contact
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.095
	mesh.bottom_radius = 0.095
	mesh.height = length
	mesh.radial_segments = 12
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.67, 0.44, 0.21)
	_material.roughness = 1.0
	mesh.material = _material
	$Mesh.mesh = mesh
	if not Engine.is_editor_hint():
		element.set_flame_coverage(Vector3(0.24, length, 0.24))


func take_hit(info: HitInfo) -> void:
	if info.tags.has("fire"):
		var from := info.source.global_position + Vector3.UP if is_instance_valid(info.source) else get_hit_center()
		element.ignite_from(info.source, from)


func get_hit_center() -> Vector3:
	# 命中与火焰遮挡射线落在地锚附近，玩家不必瞄准高处绳索中心。
	return to_global(Vector3(0, -length * 0.5 + minf(1.1, length * 0.5), 0))
