extends Node3D

## 自发光锥体与灯光组成的占位火焰，不需要外部美术资源。
var _tongues: Array[MeshInstance3D] = []
var _time := 0.0
var _light: OmniLight3D
var _coverage := Vector3.ZERO
var _field: MultiMeshInstance3D
var _base_transforms: Array[Transform3D] = []
var _material: StandardMaterial3D


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.34, 0.035)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.22, 0.02)
	material.emission_energy_multiplier = 2.5
	_material = material
	for i in range(3):
		var tongue := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.015
		mesh.bottom_radius = 0.16 - i * 0.025
		mesh.height = 0.65 - i * 0.08
		mesh.radial_segments = 8
		mesh.material = material
		tongue.mesh = mesh
		tongue.position = Vector3((i - 1) * 0.1, 0.22, 0.0)
		add_child(tongue)
		_tongues.append(tongue)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.48, 0.14)
	_light.light_energy = 1.1
	_light.omni_range = 4.5
	add_child(_light)
	if _coverage != Vector3.ZERO:
		_build_coverage()


## 大面积可燃物按局部宽高铺开火舌；所有实例共用网格、材质和一盏灯。
## 普通火把 / 剑 / 尸体不设置覆盖范围，继续使用原来的三簇火焰。
func set_coverage(size: Vector3) -> void:
	if _coverage.is_equal_approx(size):
		return
	_coverage = size
	if is_node_ready() and _coverage != Vector3.ZERO:
		_build_coverage()


func _build_coverage() -> void:
	for tongue in _tongues:
		tongue.free()
	_tongues.clear()
	if not is_instance_valid(_field):
		_field = MultiMeshInstance3D.new()
		_field.name = "FlameCoverage"
		_field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_field)
	var columns := clampi(ceili(_coverage.x / 0.75), 1, 12)
	var rows := clampi(ceili(_coverage.y / 0.75), 1, 10)
	var faces := 2 if _coverage.z > 0.15 else 1
	var cell := Vector2(_coverage.x / columns, _coverage.y / rows)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.025
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.material = _material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = columns * rows * faces * 3
	_base_transforms.clear()
	for face in faces:
		var z := (float(face) - 0.5) * _coverage.z if faces == 2 else 0.0
		for row in rows:
			for column in columns:
				for tongue in 3:
					var width := cell.x * (0.65 - tongue * 0.1)
					var height := cell.y * (1.25 - tongue * 0.15)
					var at := Vector3((column + 0.5) * cell.x - _coverage.x * 0.5 + (tongue - 1) * cell.x * 0.22, (row + 0.5) * cell.y - _coverage.y * 0.5, z)
					var transform := Transform3D(Basis.from_scale(Vector3(width, height, minf(width, 0.5))), at)
					instances.set_instance_transform(_base_transforms.size(), transform)
					_base_transforms.append(transform)
	_field.multimesh = instances
	_light.omni_range = maxf(4.5, _coverage.length() * 0.6)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	for i in range(_tongues.size()):
		var tongue := _tongues[i]
		tongue.scale.y = 0.9 + sin(_time * 9.0 + i * 2.1) * 0.2
		tongue.rotation.z = sin(_time * 6.0 + i) * 0.15
	if is_instance_valid(_field):
		for i in _base_transforms.size():
			var transform := _base_transforms[i]
			var flicker := 0.9 + sin(_time * 9.0 + i * 2.1) * 0.2
			transform.basis = Basis(Vector3.FORWARD, sin(_time * 6.0 + i) * 0.12) * transform.basis.scaled(Vector3(1.0, flicker, 1.0))
			_field.multimesh.set_instance_transform(i, transform)
	_light.light_energy = 1.0 + sin(_time * 11.0) * 0.15
