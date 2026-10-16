@tool
extends Node3D

## 共享低多边形网格；活体仅转动头、耳、腿与三段尾巴，尸体停止动画。
static var _meshes: Dictionary = {}
static var _palette: Array[StandardMaterial3D] = []
var _dimensions := Vector3(0.5, 0.34, 0.8)
var _fur: StandardMaterial3D
var _corpse := false
var _host: CharacterBody3D
var _time := 0.0
var _gait := 0.0
var _moving := 0.0
var _body: Node3D
var _head: Node3D
var _eyes: Node3D
var _ears: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _tail: Array[Node3D] = []


func configure(dimensions: Vector3, fur: StandardMaterial3D, corpse: bool = false) -> void:
	_dimensions = dimensions
	_fur = fur
	_corpse = corpse


func _ready() -> void:
	_ensure_meshes()
	if _fur == null:
		_fur = _palette[0]
	_fur.emission_enabled = true
	_fur.emission = _fur.albedo_color * 0.24
	scale = _dimensions / Vector3(0.5, 0.34, 0.8)
	_host = get_parent() as CharacterBody3D
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var body := _part("body", _body, Vector3.ZERO, true)
	var belly := _palette[1].duplicate() as StandardMaterial3D
	belly.albedo_color = _fur.albedo_color.lightened(0.16)
	body.set_surface_override_material(1, belly)
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 0.16, -0.16)
	_body.add_child(_head)
	_part("head", _head, Vector3.ZERO, true)
	_eyes = _part("closed_eyes" if _corpse else "eyes", _head, Vector3.ZERO)
	for side in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.position = Vector3(side * 0.105, 0.11, 0.01)
		ear.rotation.z = side * -0.18
		_head.add_child(ear)
		_part("ear", ear, Vector3.ZERO, true)
		_ears.append(ear)
	for index in 4:
		var leg := Node3D.new()
		leg.name = "Leg%d" % index
		leg.position = Vector3(-0.145 if index % 2 == 0 else 0.145, 0.105, -0.17 if index < 2 else 0.19)
		_body.add_child(leg)
		_part("front_leg" if index < 2 else "hind_leg", leg, Vector3.ZERO, true)
		_legs.append(leg)
	var tail_parent: Node3D = _body
	for index in 3:
		var segment := Node3D.new()
		segment.name = "Tail%d" % index
		segment.position = Vector3(0, 0.105, 0.31) if index == 0 else Vector3(0, -0.018, 0.21)
		tail_parent.add_child(segment)
		_part("tail%d" % index, segment, Vector3.ZERO)
		_tail.append(segment)
		tail_parent = segment
	if _corpse:
		_head.rotation = Vector3(0.08, -0.16, 0.22)
		for index in _legs.size():
			_legs[index].rotation.x = -0.32 if index < 2 else 0.28
		for index in _ears.size():
			_ears[index].rotation.z += -0.45 if index == 0 else 0.45
		_tail[0].rotation.y = 0.2
	set_process(not Engine.is_editor_hint() and not _corpse)


func _process(delta: float) -> void:
	_time += delta
	var speed := 0.0
	var grounded := false
	if is_instance_valid(_host):
		speed = Vector2(_host.velocity.x, _host.velocity.z).length()
		grounded = _host.is_on_floor()
	var movement := clampf(speed / 1.5, 0.0, 1.0) if grounded else 0.0
	_moving = lerpf(_moving, movement, 1.0 - exp(-delta * 14.0))
	_gait += delta * (8.0 + speed * 5.0)
	_body.position.y = sin(_time * 3.5) * 0.002 + absf(sin(_gait * 2.0)) * _moving * 0.006
	_body.rotation.z = sin(_gait) * _moving * 0.025
	_head.rotation.x = sin(_time * 3.2) * 0.035 * (1.0 - _moving * 0.7)
	_head.rotation.y = sin(_time * 1.4) * 0.035 * (1.0 - _moving)
	_eyes.scale.y = 0.06 if sin(_time * 1.3) > 0.995 else 1.0
	for index in _legs.size():
		var phase := _gait + (PI if index in [1, 2] else 0.0)
		_legs[index].rotation.x = sin(phase) * _moving * 0.42
	for index in _ears.size():
		var twitch := pow(maxf(0.0, sin(_time * 1.8 + index * 0.9)), 18.0)
		_ears[index].rotation.x = twitch * 0.18
	for index in _tail.size():
		_tail[index].rotation.y = sin(_time * (2.0 + _moving * 3.0) - index * 0.8) * (0.07 + _moving * 0.10)


func _part(key: String, parent: Node3D, at: Vector3, fur: bool = false) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = key.to_pascal_case()
	visual.mesh = _meshes[key]
	visual.position = at
	if fur:
		visual.set_surface_override_material(0, _fur)
	parent.add_child(visual)
	return visual


static func _ensure_meshes() -> void:
	if not _meshes.is_empty():
		return
	for color in [Color(0.45, 0.44, 0.46), Color(0.57, 0.55, 0.52), Color(0.62, 0.41, 0.36), Color(0.018, 0.012, 0.012), Color(0.68, 0.65, 0.59), Color(0.9, 0.91, 0.88)]:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		material.emission_enabled = true
		material.emission = color * 0.06
		_palette.append(material)
	_palette[3].roughness = 0.16
	_palette[5].emission_enabled = true
	_palette[5].emission = Color(0.3, 0.32, 0.28)
	var groups := _groups([0, 1])
	_ellipsoid(groups[0], Vector3(0, 0.17, 0.07), Vector3(0.20, 0.145, 0.28))
	_ellipsoid(groups[0], Vector3(0, 0.16, -0.105), Vector3(0.15, 0.122, 0.17))
	_ellipsoid(groups[1], Vector3(0, 0.09, -0.025), Vector3(0.156, 0.061, 0.235))
	_meshes.body = _finish(groups)
	groups = _groups([0, 2, 4])
	_ellipsoid(groups[0], Vector3(0, 0.015, -0.04), Vector3(0.131, 0.107, 0.142))
	_tube(groups[0], Vector3(0, -0.025, -0.07), Vector3(0, -0.037, -0.274), 0.093, 0.027)
	_ellipsoid(groups[1], Vector3(0, -0.035, -0.274), Vector3(0.033, 0.024, 0.021))
	for side in [-1.0, 1.0]:
		for index in 3:
			_tube(groups[2], Vector3(side * 0.032, -0.032, -0.24), Vector3(side * (0.155 + index * 0.012), -0.028 + (index - 1) * 0.026, -0.28 + index * 0.044), 0.0025, 0.0008)
	_meshes.head = _finish(groups)
	groups = _groups([0, 2])
	_ellipsoid(groups[0], Vector3.ZERO, Vector3(0.065, 0.080, 0.025))
	_ellipsoid(groups[1], Vector3(0, 0.002, -0.021), Vector3(0.046, 0.060, 0.009))
	_meshes.ear = _finish(groups)
	groups = _groups([3, 5])
	for side in [-1.0, 1.0]:
		_ellipsoid(groups[0], Vector3(side * 0.104, 0.043, -0.126), Vector3(0.020, 0.024, 0.016))
		_ellipsoid(groups[1], Vector3(side * 0.110, 0.051, -0.139), Vector3.ONE * 0.0055)
	_meshes.eyes = _finish(groups)
	groups = _groups([3])
	for side in [-1.0, 1.0]:
		_tube(groups[0], Vector3(side * 0.088, 0.046, -0.14), Vector3(side * 0.119, 0.034, -0.124), 0.004, 0.003)
	_meshes.closed_eyes = _finish(groups)
	for hind in [false, true]:
		groups = _groups([0, 2])
		_ellipsoid(groups[0], Vector3(0, -0.02, 0), Vector3(0.059 if hind else 0.037, 0.072, 0.073 if hind else 0.042))
		_ellipsoid(groups[1], Vector3(0, -0.083, -0.028), Vector3(0.044, 0.019, 0.075))
		for index in 3:
			_tube(groups[1], Vector3((index - 1) * 0.022, -0.081, -0.068), Vector3((index - 1) * 0.025, -0.084, -0.109), 0.008, 0.004)
		_meshes["hind_leg" if hind else "front_leg"] = _finish(groups)
	for segment in 3:
		groups = _groups([2])
		for index in 4:
			var a := Vector3(sin((segment * 4 + index) * 0.38) * 0.012, -index * 0.0045, index * 0.0525)
			var b := Vector3(sin((segment * 4 + index + 1) * 0.38) * 0.012, -(index + 1) * 0.0045, (index + 1) * 0.0525)
			var radius := lerpf(0.025, 0.003, (segment * 4 + index) / 12.0)
			_tube(groups[0], a, b, radius, maxf(0.002, radius - 0.002))
		_meshes["tail%d" % segment] = _finish(groups)


static func _groups(materials: Array) -> Array[SurfaceTool]:
	var result: Array[SurfaceTool] = []
	for index in materials:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(_palette[index])
		result.append(surface)
	return result


static func _finish(groups: Array[SurfaceTool]) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in groups:
		surface.commit(result)
	return result


static func _ellipsoid(surface: SurfaceTool, at: Vector3, radii: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	surface.append_from(mesh, 0, Transform3D(Basis.from_scale(radii), at))


static func _tube(surface: SurfaceTool, a: Vector3, b: Vector3, bottom: float, top: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 8
	var basis := Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	surface.append_from(mesh, 0, Transform3D(basis, (a + b) * 0.5))
