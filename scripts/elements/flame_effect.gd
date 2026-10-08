extends Node3D

## 自发光锥体与灯光组成的占位火焰，不需要外部美术资源。
var _tongues: Array[MeshInstance3D] = []
var _time := 0.0
var _light: OmniLight3D


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.34, 0.035)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.22, 0.02)
	material.emission_energy_multiplier = 2.5
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


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	for i in range(_tongues.size()):
		var tongue := _tongues[i]
		tongue.scale.y = 0.9 + sin(_time * 9.0 + i * 2.1) * 0.2
		tongue.rotation.z = sin(_time * 6.0 + i) * 0.15
	_light.light_energy = 1.0 + sin(_time * 11.0) * 0.15
