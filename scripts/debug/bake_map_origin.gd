extends "res://scripts/debug/bake_map_v2.gd"

## 只复用旧烘焙器的几何裁切算法，不引用旧地图资源。
## Godot --headless --path . --script res://scripts/debug/bake_map_origin.gd
const ORIGIN_SOURCE := "res://assets/map_origin.glb"
const ORIGIN_OUTPUT := "res://scenes/environment/map_origin_geometry.tscn"
const ORIGIN_RESOURCES := "res://resources/environment/map_origin"
const MODEL_SCALE := 5.0
## 局部门洞 / 家具占位清理。可见网格与碰撞共用同一份裁切结果。
const CLEARANCES := [
	AABB(Vector3(-34, 0.60, -4), Vector3(9, 12, 14)), # 商店占位及地面残留由完整平面替换，避免微小陡面卡脚。
	AABB(Vector3(-28, 0.45, -4), Vector3(9, 6, 7)), # 商店入口接到洞沿可行走区。
	AABB(Vector3(-11.6, 0.70, -7.5), Vector3(10.6, 5.5, 5)), # 主厅拱门，预留玩家盒体转身空间。
	AABB(Vector3(-11.6, 0.70, -2.6), Vector3(4.2, 5.5, 3.2)), # 出生区接主通路，清除放大后会卡脚的岩面切口。
	AABB(Vector3(-12.5, 0.65, -8), Vector3(3.5, 4.5, 3)), # 洞沿矮台阶。
	AABB(Vector3(9, 0.90, -9), Vector3(4, 5.8, 4)), # 第一清扫房门口。
	AABB(Vector3(21.5, 1.90, -9), Vector3(8, 12, 4)), # 升降门与门扇上升空间。
	AABB(Vector3(3, 0.90, -0.2), Vector3(5, 5.5, 4.2)), # 前厅至下方走廊。
	AABB(Vector3(16, 0.90, -1), Vector3(5, 5.5, 5)), # 清扫房至下方走廊。
	AABB(Vector3(4, 0.90, 4), Vector3(7, 5.5, 3)), # 走廊相连处的岩石占位。
]
## 两端坐标均是地板顶面；实体厚度、视觉与碰撞由共用算法产生。
const WALKWAYS := {
	"ShopInterior": [Vector3(-29.5, 0.605, -4), Vector3(-29.5, 0.605, 10), 4.5],
	"ShopRamp": [Vector3(-28, 0.605, 1), Vector3(-18.5, 0.766, -2), 2.0],
	"MainPassage": [Vector3(-11, 0.958, -5), Vector3(-1, 1.086, -5), 2.5],
	"MainApproach": [Vector3(-9.5, 0.958, 0.5), Vector3(-9.5, 0.958, -5), 1.8],
	"PitApproach": [Vector3(-12.5, 0.766, -6.5), Vector3(-11, 0.958, -6.5), 1.5],
	"CleaningRamp": [Vector3(9, 1.086, -7), Vector3(13, 2.197, -7), 2.0],
	"DeepPassage": [Vector3(21.5, 2.197, -7), Vector3(29.5, 2.197, -7), 2.0],
	"EntryGallery": [Vector3(5.5, 1.086, -0.2), Vector3(5.5, 1.086, 4), 2.5],
	"CleaningGallery": [Vector3(18.5, 2.197, -1), Vector3(18.5, 1.086, 4), 2.5],
	"GalleryPassage": [Vector3(4, 1.086, 5.5), Vector3(11, 1.086, 5.5), 1.5],
}
const REGIONS := {
	"ShopFloor": AABB(Vector3(-100, -50, -100), Vector3(74.5, 100, 200)),
	"MainFloor": AABB(Vector3(-25.5, -50, -100), Vector3(20, 100, 200)),
	"EntryFloor": AABB(Vector3(-5.5, -50, -100), Vector3(16.4, 100, 101.5)),
	"CleaningFloor": AABB(Vector3(10.9, -50, -100), Vector3(15.4, 100, 101.5)),
	"DeepFloor": AABB(Vector3(26.3, -50, -100), Vector3(73.7, 100, 101.5)),
	"GalleryFloor": AABB(Vector3(-5.5, -50, 1.5), Vector3(105.5, 100, 98.5)),
}
var _write_failed := false


func _run() -> void:
	var packed := load(ORIGIN_SOURCE) as PackedScene
	if packed == null:
		push_error("无法读取完整世界白模 map_origin.glb")
		quit(1)
		return
	var source: Node3D = packed.instantiate()
	root.add_child(source)
	source.scale = Vector3.ONE * MODEL_SCALE
	DirAccess.make_dir_recursive_absolute(ORIGIN_RESOURCES)
	var cuts: Array = []
	for box: AABB in CLEARANCES:
		cuts.append(_box_cut(box))
	var visual := ArrayMesh.new()
	var all_faces := PackedVector3Array()
	for child in source.get_children():
		if not child is MeshInstance3D:
			continue
		for surface in child.mesh.get_surface_count():
			var faces := _surface_faces(child, surface)
			faces = _subtract_cuts(faces, cuts)
			if faces.is_empty():
				continue
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for vertex in faces:
				tool.add_vertex(vertex)
			tool.generate_normals()
			tool.commit(visual)
			var material: Material = child.mesh.surface_get_material(surface)
			if material != null:
				material = material.duplicate()
				if material is BaseMaterial3D:
					material.cull_mode = BaseMaterial3D.CULL_DISABLED
			visual.surface_set_material(visual.get_surface_count() - 1, material)
			all_faces.append_array(faces)
	var geometry := Node3D.new()
	geometry.name = "MapOriginGeometry"
	geometry.set_meta("source_file", ORIGIN_SOURCE)
	geometry.set_meta("source_sha256", FileAccess.get_sha256(ORIGIN_SOURCE))
	geometry.set_meta("source_scale", MODEL_SCALE)
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Model"
	mesh_node.mesh = visual
	geometry.add_child(mesh_node)
	mesh_node.owner = geometry
	_save_resource(visual, "world_mesh.res")
	var collisions := Node3D.new()
	collisions.name = "Collision"
	geometry.add_child(collisions)
	collisions.owner = geometry
	var walkways := Node3D.new()
	walkways.name = "Walkways"
	geometry.add_child(walkways)
	walkways.owner = geometry
	for id: String in WALKWAYS:
		var spec: Array = WALKWAYS[id]
		var a: Vector3 = spec[0]
		var b: Vector3 = spec[1]
		var lateral := (b - a).normalized().cross(Vector3.UP).normalized()
		var mesh := _floor_mesh([a, b], lateral, spec[2])
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.66, 0.66, 0.66)
		material.roughness = 0.95
		mesh.surface_set_material(0, material)
		_save_resource(mesh, id.to_snake_case() + "_mesh.res")
		var node := MeshInstance3D.new()
		node.name = id
		node.mesh = mesh
		walkways.add_child(node)
		node.owner = geometry
		all_faces.append_array(mesh.get_faces())
	# 坡道也按房间切分到同一碰撞体，离房回收不会漏掉通道上的尸体。
	for region: String in REGIONS:
		var faces := _inside_box(all_faces, REGIONS[region])
		_add_collision(collisions, geometry, region, faces)
	var scene := PackedScene.new()
	if _write_failed or scene.pack(geometry) != OK or ResourceSaver.save(scene, ORIGIN_OUTPUT) != OK:
		push_error("无法保存完整世界环境")
		quit(1)
		return
	print("MAP ORIGIN BAKE: source=%s scale=%s triangles=%d collision_bodies=%d" % [FileAccess.get_sha256(ORIGIN_SOURCE), MODEL_SCALE, all_faces.size() / 3, collisions.get_child_count()])
	geometry.free()
	source.queue_free()
	quit(0)


func _surface_faces(node: MeshInstance3D, surface: int) -> PackedVector3Array:
	var arrays := node.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var result := PackedVector3Array()
	if indices.is_empty():
		for vertex in vertices:
			result.append(node.global_transform * vertex)
	else:
		for index in indices:
			result.append(node.global_transform * vertices[index])
	return result


func _box_cut(box: AABB) -> Dictionary:
	return {"bounds": box.grow(0.002), "planes": [
		Plane(Vector3.RIGHT, box.position.x), Plane(Vector3.LEFT, -box.end.x),
		Plane(Vector3.UP, box.position.y), Plane(Vector3.DOWN, -box.end.y),
		Plane(Vector3.BACK, box.position.z), Plane(Vector3.FORWARD, -box.end.z),
	]}


func _inside_box(faces: PackedVector3Array, box: AABB) -> PackedVector3Array:
	var planes: Array = _box_cut(box).planes
	var result := PackedVector3Array()
	for index in range(0, faces.size(), 3):
		var polygon := PackedVector3Array([faces[index], faces[index + 1], faces[index + 2]])
		for plane: Plane in planes:
			polygon = _clip(polygon, plane.normal, plane.d)
			if polygon.size() < 3:
				break
		for corner in range(1, polygon.size() - 1):
			result.append_array(PackedVector3Array([polygon[0], polygon[corner], polygon[corner + 1]]))
	return result


func _add_collision(parent: Node3D, scene: Node3D, id: String, faces: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	_save_resource(shape, id.to_snake_case() + ".res")
	var body := StaticBody3D.new()
	body.name = id
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	body.owner = scene
	var node := CollisionShape3D.new()
	node.name = "Shape"
	node.shape = shape
	body.add_child(node)
	node.owner = scene


func _save_resource(resource: Resource, filename: String) -> void:
	var path := ORIGIN_RESOURCES.path_join(filename)
	if ResourceSaver.save(resource, path, ResourceSaver.FLAG_COMPRESS) != OK:
		_write_failed = true
		push_error("环境资源写入失败：" + path)
