extends Area3D

## 以原裂缝的轮廓和地面高度判断下落，不依赖可能被高速下落穿过的 enter 信号。
@export var surface_height := 0.0
@export_range(0.2, 3.0, 0.05) var trigger_drop := 0.8

@onready var _shape: CollisionPolygon3D = $Shape


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false


func contains_footprint(world_point: Vector3) -> bool:
	var local := to_local(world_point)
	return Geometry2D.is_point_in_polygon(Vector2(local.x, local.z), _shape.polygon)


func contains_fall(feet: Vector3) -> bool:
	return to_local(feet).y < surface_height - trigger_drop and contains_footprint(feet)


func edge_distance(world_point: Vector3) -> float:
	var local := to_local(world_point)
	var at := Vector2(local.x, local.z)
	var polygon := _shape.polygon
	var nearest := INF
	for index in polygon.size():
		var closest := Geometry2D.get_closest_point_to_segment(at, polygon[index], polygon[(index + 1) % polygon.size()])
		nearest = minf(nearest, at.distance_to(closest))
	return nearest


func get_bank_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for point in $Banks.get_children():
		if point is Marker3D:
			points.append(point.global_position)
	return points
