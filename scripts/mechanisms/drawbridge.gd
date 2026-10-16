@tool
extends Node3D

## 地锚绳索烧断后，桥板绕近岸铰链从竖直转为水平。
signal rope_burned
signal lowered

@export var persistence_id: StringName
@export var deck_size := Vector3(3.4, 0.22, 8.0):
	set(value):
		deck_size = value.max(Vector3(0.5, 0.1, 1.0))
		_update_geometry()
@export_range(0.2, 6.0, 0.1, "suffix:s") var lower_duration := 1.6
@export_range(0.5, 5.0, 0.1) var anchor_distance := 1.8:
	set(value):
		anchor_distance = maxf(value, 0.5)
		_update_geometry()

var _rope_burned := false
var _dropping := false
var _elapsed := 0.0


func _ready() -> void:
	_update_geometry()
	set_physics_process(false)
	if Engine.is_editor_hint():
		return
	add_to_group(&"persistent_gates")
	$Rope/ElementComponent.burned_down.connect(_on_rope_burned_down)


func _update_geometry() -> void:
	if not is_node_ready():
		return
	var shape := BoxShape3D.new()
	shape.size = deck_size
	$Hinge/Shape.shape = shape
	$Hinge/Shape.position = Vector3(0, -deck_size.y * 0.5, -deck_size.z * 0.5)
	if not _rope_burned:
		$Hinge.rotation.x = PI * 0.5
	var old_deck := get_node_or_null("Hinge/GeneratedDeck")
	if old_deck != null:
		old_deck.free()
	var deck := Node3D.new()
	deck.name = "GeneratedDeck"
	$Hinge.add_child(deck)
	var wood := _material(Color(0.37, 0.20, 0.095))
	var light_wood := _material(Color(0.49, 0.30, 0.14))
	var iron := _material(Color(0.16, 0.18, 0.20), 0.65)
	var count := ceili(deck_size.z / 0.36)
	var step := deck_size.z / count
	for index in count:
		_box(deck, Vector3(deck_size.x, deck_size.y, step - 0.015), Vector3(0, -deck_size.y * 0.5, -(index + 0.5) * step), wood if index % 2 == 0 else light_wood)
	for side in [-1.0, 1.0]:
		_box(deck, Vector3(0.17, 0.2, deck_size.z), Vector3(side * (deck_size.x * 0.5 - 0.25), -deck_size.y - 0.1, -deck_size.z * 0.5), iron)
		_box(deck, Vector3(0.12, 0.12, deck_size.z), Vector3(side * (deck_size.x * 0.5 - 0.08), 0.95, -deck_size.z * 0.5), light_wood)
		for index in range(ceili(deck_size.z / 2.0) + 1):
			_box(deck, Vector3(0.13, 1.0, 0.13), Vector3(side * (deck_size.x * 0.5 - 0.08), 0.5, -minf(index * 2.0, deck_size.z)), wood)
	var old_frame := get_node_or_null("GeneratedFrame")
	if old_frame != null:
		old_frame.free()
	var frame := Node3D.new()
	frame.name = "GeneratedFrame"
	add_child(frame)
	for side in [-1.0, 1.0]:
		_box(frame, Vector3(0.36, 0.65, 0.5), Vector3(side * (deck_size.x * 0.5 + 0.12), 0.2, 0.15), iron)
	_box(frame, Vector3(0.55, 0.22, 0.55), Vector3(0, 0.04, anchor_distance), iron)
	_box(frame, Vector3(0.15, 0.65, 0.15), Vector3(0, 0.27, anchor_distance), wood)
	var anchor := Vector3(0, 0.55, anchor_distance)
	if has_node("Rope"):
		var end: Vector3 = $Hinge.transform * Vector3(0, 0.06, -deck_size.z + 0.15)
		var offset := end - anchor
		$Rope.position = (anchor + end) * 0.5
		$Rope.basis = Basis(Quaternion(Vector3.UP, offset.normalized()))
		$Rope.length = offset.length()
	$Sign.position = Vector3(0, 1.7, anchor_distance + 0.35)


func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.85
	result.metallic = metallic
	return result


func _box(parent: Node3D, size: Vector3, at: Vector3, material: StandardMaterial3D) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	visual.mesh = mesh
	visual.position = at
	parent.add_child(visual)


func _on_rope_burned_down() -> void:
	if _rope_burned:
		return
	_rope_burned = true
	_dropping = true
	_elapsed = 0.0
	$Sign.hide()
	# 转动期间关闭桥板碰撞，避免把岸上的玩家夹住或甩进裂隙。
	$Hinge/Shape.set_deferred("disabled", true)
	set_physics_process(true)
	rope_burned.emit()


func _physics_process(delta: float) -> void:
	_elapsed = minf(_elapsed + delta, lower_duration)
	var progress := _elapsed / lower_duration
	# 从静止加速下落，再减速落稳。
	$Hinge.rotation.x = lerpf(PI * 0.5, 0.0, smoothstep(0.0, 1.0, progress))
	if _elapsed >= lower_duration:
		_dropping = false
		$Hinge/Shape.set_deferred("disabled", false)
		set_physics_process(false)
		lowered.emit()


func is_rope_burned() -> bool:
	return _rope_burned


func is_lowered() -> bool:
	return _rope_burned and not _dropping


func get_persistence_id() -> StringName:
	return persistence_id


func is_persistently_open() -> bool:
	# 保存的是不可逆的断绳状态，桥板尚在下落时也不能丢失该进度。
	return _rope_burned


func can_restore_persistent_open() -> bool:
	return true


func restore_persistent_open() -> void:
	_rope_burned = true
	_dropping = false
	_elapsed = lower_duration
	set_physics_process(false)
	var rope := get_node_or_null("Rope")
	if rope != null:
		rope.process_mode = Node.PROCESS_MODE_DISABLED
		rope.hide()
		rope.queue_free()
	$Sign.hide()
	$Hinge.rotation.x = 0.0
	$Hinge.reset_physics_interpolation()
	$Hinge/Shape.set_deferred("disabled", false)
