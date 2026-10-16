@tool
extends Node3D

## 左手短护手剑：分面开刃、剑槽、缠皮握柄和手套均使用原生网格。
func _ready() -> void:
	_build_model()


func _build_model() -> void:
	var steel := _material(Color(0.66, 0.75, 0.81), 0.78, 0.28)
	var edge := _material(Color(0.91, 0.94, 0.96), 0.85, 0.18)
	var fuller := _material(Color(0.24, 0.32, 0.38), 0.7, 0.36)
	var brass := _material(Color(0.48, 0.34, 0.17), 0.72, 0.34)
	var leather := _material(Color(0.19, 0.105, 0.06), 0.0, 0.85)
	var wrap := _material(Color(0.28, 0.17, 0.09), 0.0, 0.9)
	var glove := _material(Color(0.15, 0.17, 0.18), 0.05, 0.86)
	var cuff := _material(Color(0.27, 0.29, 0.29), 0.4, 0.48)
	$Mesh.mesh = _blade([steel, edge, fuller])
	$Guard.mesh = _guard(brass)
	$Mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	$Guard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	$Mesh.layers = 2
	$Guard.layers = 2
	var previous := get_node_or_null("Details")
	if previous != null:
		previous.free()
	var details := Node3D.new()
	details.name = "Details"
	add_child(details)
	_cylinder(details, Vector3(0, 0, -0.16), Vector3(0, 0, 0.13), 0.045, leather)
	for index in 10:
		var band := TorusMesh.new()
		band.inner_radius = 0.039
		band.outer_radius = 0.049
		band.rings = 12
		band.ring_segments = 6
		band.material = wrap
		var visual := _visual(details, band, Vector3(0, 0, -0.135 + index * 0.026))
		visual.rotation.x = PI * 0.5
	for z in [-0.17, 0.14]:
		_cylinder(details, Vector3(0, 0, z - 0.012), Vector3(0, 0, z + 0.012), 0.053, brass)
	_sphere(details, Vector3(0, 0, 0.2), Vector3(0.065, 0.065, 0.047), brass)
	_cylinder(details, Vector3(0, 0, -0.24), Vector3(0, 0, -0.17), 0.057, steel)
	# 左手掌在握柄左侧，四指包住前侧；腕部向左下方自然退出画面。
	_sphere(details, Vector3(-0.047, -0.046, -0.012), Vector3(0.071, 0.063, 0.112), glove)
	for index in 4:
		var z := -0.105 + index * 0.051
		_cylinder(details, Vector3(-0.042, 0.012, z), Vector3(0.034, 0.016, z), 0.023, glove)
		_cylinder(details, Vector3(0.034, 0.016, z), Vector3(0.043, -0.035, z + 0.009), 0.022, glove)
	_cylinder(details, Vector3(-0.082, -0.013, 0.07), Vector3(-0.016, 0.042, -0.025), 0.027, glove)
	_cylinder(details, Vector3(-0.06, -0.06, 0.09), Vector3(-0.17, -0.16, 0.37), 0.073, leather)
	_cylinder(details, Vector3(-0.085, -0.08, 0.16), Vector3(-0.11, -0.103, 0.22), 0.08, cuff)
	_cylinder(details, Vector3(-0.146, -0.138, 0.31), Vector3(-0.167, -0.157, 0.363), 0.08, cuff)
	_cylinder(details, Vector3(-0.17, -0.16, 0.37), Vector3(-0.34, -0.3, 0.72), 0.075, glove)


func _material(color: Color, metal: float, roughness: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metal
	result.roughness = roughness
	# 小幅补光保证洞内的剑刃与握持轮廓可读。
	result.emission_enabled = true
	result.emission = color * 0.12
	result.emission_energy_multiplier = 0.55
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	return result


func _blade(materials: Array) -> ArrayMesh:
	var surfaces: Array[SurfaceTool] = []
	for material in materials:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(material)
		surfaces.append(surface)
	var rings: Array[PackedVector3Array] = []
	for parameters in [Vector2(0.92, 0.095), Vector2(0.77, 0.145), Vector2(-0.49, 0.105), Vector2(-0.72, 0.065)]:
		var ring := PackedVector3Array()
		var w: float = parameters.y
		var h := 0.024
		for xy in [Vector2(-0.5, 0), Vector2(-0.39, 0.6), Vector2(-0.16, 1), Vector2(-0.10, 0.65), Vector2(0.10, 0.65), Vector2(0.16, 1), Vector2(0.39, 0.6), Vector2(0.5, 0), Vector2(0.39, -0.6), Vector2(0.16, -1), Vector2(0.10, -0.65), Vector2(-0.10, -0.65), Vector2(-0.16, -1), Vector2(-0.39, -0.6)]:
			ring.append(Vector3(xy.x * w, xy.y * h, parameters.x))
		rings.append(ring)
	for index in 14:
		var next := (index + 1) % 14
		var surface: SurfaceTool = surfaces[2 if index in [3, 10] else (1 if index in [0, 6, 7, 13] else 0)]
		for row in range(rings.size() - 1):
			_triangle(surface, rings[row][index], rings[row + 1][index], rings[row + 1][next])
			_triangle(surface, rings[row][index], rings[row + 1][next], rings[row][next])
		_triangle(surface, rings[-1][index], Vector3(0, 0, -0.9), rings[-1][next])
	var result := ArrayMesh.new()
	for surface in surfaces:
		surface.commit(result)
	return result


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var center := (a + b + c) / 3.0
	if normal.dot(Vector3(center.x, center.y, 0)) < 0.0:
		normal = -normal
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(point)


func _guard(material: StandardMaterial3D) -> ArrayMesh:
	var outline := PackedVector2Array([Vector2(-0.23, -0.08), Vector2(-0.18, -0.02), Vector2(-0.065, 0.025), Vector2(0.065, 0.025), Vector2(0.18, -0.02), Vector2(0.23, -0.08), Vector2(0.21, -0.11), Vector2(0.16, -0.065), Vector2(0.05, -0.025), Vector2(-0.05, -0.025), Vector2(-0.16, -0.065), Vector2(-0.21, -0.11)])
	for index in outline.size():
		outline[index].x *= 0.72
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	var triangles := Geometry2D.triangulate_polygon(outline)
	for side in [-1.0, 1.0]:
		for index in triangles:
			surface.set_normal(Vector3.UP * side)
			var point := outline[index]
			surface.add_vertex(Vector3(point.x, side * 0.025, point.y))
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		_triangle(surface, Vector3(a.x, -0.025, a.y), Vector3(b.x, -0.025, b.y), Vector3(b.x, 0.025, b.y))
		_triangle(surface, Vector3(a.x, -0.025, a.y), Vector3(b.x, 0.025, b.y), Vector3(a.x, 0.025, a.y))
	return surface.commit()


func _visual(parent: Node3D, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.position = at
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	result.layers = 2
	parent.add_child(result)
	return result


func _cylinder(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: StandardMaterial3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 10
	mesh.material = material
	var visual := _visual(parent, mesh, (a + b) * 0.5)
	visual.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))


func _sphere(parent: Node3D, at: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	mesh.material = material
	_visual(parent, mesh, at).scale = size
