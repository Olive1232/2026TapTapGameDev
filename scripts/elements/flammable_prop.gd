class_name FlammableProp
extends StaticBody3D

## 藤蔓 / 草占位实体。燃烧结束才移除碰撞，普通剑不能砍开。
@export var size := Vector3(1.2, 3.2, 0.35)
@export var tint := Color(0.13, 0.38, 0.16)
@export var blocks_movement := true

@onready var element: ElementComponent = $ElementComponent
var _material: StandardMaterial3D


func _ready() -> void:
	collision_layer = CollisionLayers.WORLD if blocks_movement else 0
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	$Shape.shape = shape
	$Shape.position.y = size.y * 0.5
	element.position.y = size.y * 0.5
	_material = StandardMaterial3D.new()
	_material.albedo_color = tint
	_material.roughness = 0.9
	# 交错藤条与叶片，碰撞仍是整片障碍。
	for i in range(5):
		var stem := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x * 0.095, size.y, size.z * 0.45)
		mesh.material = _material
		stem.mesh = mesh
		stem.position = Vector3((i - 2) * size.x * 0.2, size.y * 0.5, sin(i * 2.0) * size.z * 0.25)
		stem.rotation.z = (i - 2) * 0.045
		add_child(stem)
		for j in range(4):
			var leaf := MeshInstance3D.new()
			var leaf_mesh := BoxMesh.new()
			leaf_mesh.size = Vector3(size.x * 0.23, size.y * 0.065, size.z * 0.9)
			leaf_mesh.material = _material
			leaf.mesh = leaf_mesh
			leaf.position = Vector3(stem.position.x, size.y * (j + 0.6) / 4.0, stem.position.z)
			leaf.rotation.z = 0.4 if (i + j) % 2 == 0 else -0.4
			add_child(leaf)
	element.ignited.connect(_on_ignited)


func _on_ignited() -> void:
	_material.albedo_color = tint.darkened(0.55)


func take_hit(info: HitInfo) -> void:
	if info.tags.has("fire"):
		var at := global_position
		if is_instance_valid(info.source):
			at = info.source.global_position + Vector3.UP
		element.ignite_from(info.source, at)


func get_hit_center() -> Vector3:
	return global_position + Vector3.UP * size.y * 0.5
