class_name ThrowTrajectory
extends MeshInstance3D

## 自由飞行轨迹预览：复用尸体碰撞形状，遇到首个 WORLD 碰撞停止。
## 洞吸力及碰撞后的反弹不在预览范围内。
var points := PackedVector3Array()
var collided := false
var hit_time := 0.0
var _mesh := ImmediateMesh.new()
var _marker: MeshInstance3D
var _material := StandardMaterial3D.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color(0.2, 0.9, 1.0)
	_marker = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.09
	ball.height = 0.18
	_marker.mesh = ball
	_marker.material_override = _material
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)


func predict(corpse: Corpse, initial_velocity: Vector3) -> void:
	points = PackedVector3Array([corpse.global_position])
	collided = false
	hit_time = 0.0
	var shape := corpse.get_node("Shape") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.collision_mask = CollisionLayers.WORLD
	query.exclude = [corpse.get_rid()]
	query.margin = 0.002
	var offset := shape.global_position - corpse.global_position
	var shape_basis := shape.global_basis
	var flight_position := corpse.global_position
	var velocity := initial_velocity
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var damping := corpse.linear_damp
	if corpse.linear_damp_mode == RigidBody3D.DAMP_MODE_COMBINE:
		damping += float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1))
	var space := corpse.get_world_3d().direct_space_state
	# cast_motion 忽略起始重叠，因此先检查手持实体是否已经贴住墙或地面。
	# https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html
	query.transform = Transform3D(shape_basis, flight_position + offset)
	if not space.intersect_shape(query, 1).is_empty():
		collided = true
	else:
		for step in range(int(ceil(4.0 / dt))):
			velocity *= maxf(1.0 - damping * dt, 0.0)
			velocity += Vector3.DOWN * gravity * dt
			query.transform = Transform3D(shape_basis, flight_position + offset)
			query.motion = velocity * dt
			var fractions := space.cast_motion(query)
			var fraction := fractions[0] if fractions.size() == 2 else 1.0
			flight_position += query.motion * fraction
			points.append(flight_position)
			hit_time = (step + fraction) * dt
			if fraction < 1.0:
				collided = true
				break
	_draw_path()


func _draw_path() -> void:
	_mesh.clear_surfaces()
	_marker.position = points[points.size() - 1]
	_marker.visible = collided
	if points.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var direction := (b - a).normalized()
		var side := direction.cross(Vector3.UP).normalized()
		if side.is_zero_approx():
			side = Vector3.RIGHT
		for axis in [side, direction.cross(side).normalized()]:
			var half: Vector3 = axis * 0.018
			for vertex in [a - half, a + half, b + half, a - half, b + half, b - half]:
				_mesh.surface_add_vertex(vertex)
	_mesh.surface_end()
