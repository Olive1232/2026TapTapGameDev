@tool
class_name WeightPlatform
extends Node3D

## 根节点原点是平台顶面中心；外观放在 Visuals 下，逻辑不依赖地图。
signal pressed_changed(pressed: bool)
signal load_changed(corpse_count: int)

@export var platform_size := Vector3(3.2, 0.4, 2.6):
	set(value):
		platform_size = value.max(Vector3.ONE * 0.1)
		_update_geometry()
@export_range(1, 20, 1) var required_corpse_count: int = 1
## 连续接触后才计入，防止飞过平台的尸体误触发一次性门。
@export_range(0.05, 2.0, 0.05) var settle_time: float = 0.2
@export var enabled := true
@export var show_placeholder := true:
	set(value):
		show_placeholder = value
		_update_geometry()

var _contact_time: Dictionary = {}
var _corpse_count := 0
var _pressed := false


func _ready() -> void:
	_update_geometry()
	set_physics_process(not Engine.is_editor_hint())


func _update_geometry() -> void:
	if not is_node_ready():
		return
	var solid := BoxShape3D.new()
	solid.size = platform_size
	$Body/Shape.shape = solid
	$Body/Shape.position.y = -platform_size.y * 0.5
	var sensor := BoxShape3D.new()
	sensor.size = Vector3(platform_size.x, 0.8, platform_size.z)
	$Sensor/Shape.shape = sensor
	$Sensor/Shape.position.y = 0.4
	var mesh := BoxMesh.new()
	mesh.size = platform_size
	$Visuals/Placeholder.mesh = mesh
	$Visuals/Placeholder.position.y = -platform_size.y * 0.5
	$Visuals/Placeholder.visible = show_placeholder
	_update_color()


func _physics_process(delta: float) -> void:
	var contacts: Dictionary = {}
	var count := 0
	if enabled:
		for body in $Sensor.get_overlapping_bodies():
			var corpse := body as Corpse
			if not _is_supported(corpse):
				continue
			var id := corpse.get_instance_id()
			var elapsed: float = _contact_time.get(id, 0.0) + delta
			contacts[id] = elapsed
			if elapsed >= settle_time:
				count += 1
	_contact_time = contacts
	if count != _corpse_count:
		_corpse_count = count
		load_changed.emit(count)
	var next_pressed := count >= required_corpse_count
	if next_pressed != _pressed:
		_pressed = next_pressed
		_update_color()
		pressed_changed.emit(_pressed)


func _is_supported(corpse: Corpse) -> bool:
	if corpse == null or corpse.is_queued_for_deletion() or corpse.is_held:
		return false
	var up := global_basis.y.normalized()
	if absf(corpse.linear_velocity.dot(up)) > 0.35:
		return false
	var shape := corpse.get_node_or_null("Shape") as CollisionShape3D
	if shape == null or not shape.shape is BoxShape3D:
		return false
	# 按当前旋转与尺寸计算尸体向下的支撑距离，不依赖老鼠模型大小。
	var half: Vector3 = (shape.shape as BoxShape3D).size * 0.5
	var basis := shape.global_basis
	var extent := absf(up.dot(basis.x)) * half.x + absf(up.dot(basis.y)) * half.y + absf(up.dot(basis.z)) * half.z
	var center := shape.global_position
	var ray := PhysicsRayQueryParameters3D.create(center + up * 0.02, center - up * (extent + 0.08), CollisionLayers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.collider == $Body and hit.normal.dot(up) > 0.7


func _update_color() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.72, 0.44) if _pressed else Color(0.22, 0.46, 0.62)
	$Visuals/Placeholder.material_override = material


func is_pressed() -> bool:
	return _pressed


func get_corpse_count() -> int:
	return _corpse_count
