extends SceneTree

## FBX 更新后运行：Godot --headless --path . --script res://scripts/debug/bake_map_v2.gd
## 保留原模型；生成静态三角网格碰撞，避免凸包堵住门洞和中央洞。
const SOURCE := "res://assets/prototypes/map/map_v2.fbx"
const OUTPUT := "res://scenes/environment/map_v2_geometry.tscn"
const SHAPES := "res://resources/environment/map_v2_collisions"
## 白模的墙面碎片与商店门洞交叠；包装层留出通道，原 FBX 不变。
const PASSAGE_START := Vector3(-8, 0, 1)
const PASSAGE_END := Vector3(-14, 0, 3.6)
const PASSAGE_RADIUS := 1.4
const PASSAGE_SPRING := 1.6
const PASSAGE_WALL := 0.3
const ARCH_SEGMENTS := 12
const FLOOR_DEPTH := 0.2
const FLOOR_START := -0.0834
const FLOOR_END := -0.4279
const SECTIONS := [0.0, 0.55, 0.85, 1.0]
const PARTS := {
	"立方体": "main_floor",
	"清理区域": "cleaning_floor",
	"洞": "pit",
	"商店区域": "shop_floor",
	"优化墙": "main_walls",
	"圆环": "shop_walls",
	"联通门": "shop_passage",
	"门_001": "cleaning_door_frame",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SOURCE) as PackedScene
	if packed == null:
		push_error("无法读取 map_v2.fbx")
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHAPES))
	var header := "[gd_scene format=3]\n\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"model\"]\n" % SOURCE
	var bodies := ""
	var triangle_count := 0
	var generated := {}
	var floor_parts := []
	var wall_cuts := _wall_cuts()
	var floor_cuts := [_rectangle_cut(PASSAGE_START, PASSAGE_END, PASSAGE_RADIUS + PASSAGE_WALL), _rectangle_cut(Vector3(5.8, 0, 0), Vector3(8, 0, 0), 1.2)]
	for imported_name: String in PARTS:
		var mesh_node := model.get_node_or_null(NodePath(imported_name)) as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			push_error("模型部件缺失：" + imported_name)
			model.free()
			quit(1)
			return
		var id: String = PARTS[imported_name]
		var faces := mesh_node.mesh.get_faces()
		for i in range(faces.size()):
			faces[i] = mesh_node.transform * faces[i]
		if imported_name in ["优化墙", "圆环"]:
			faces = _subtract_cuts(faces, wall_cuts)
		elif imported_name in ["立方体", "商店区域", "清理区域"]:
			faces = _subtract_cuts(faces, floor_cuts)
			var mesh_id := id + "_mesh"
			generated[mesh_id] = _mesh_from_faces(faces)
			floor_parts.append(imported_name)
			header += "[ext_resource type=\"Mesh\" path=\"%s/%s.res\" id=\"%s\"]\n" % [SHAPES, mesh_id, mesh_id]
		elif imported_name == "联通门":
			faces = _passage_mesh(false).get_faces()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var path := SHAPES.path_join(id + ".res")
		if ResourceSaver.save(shape, path, ResourceSaver.FLAG_COMPRESS) != OK:
			push_error("碰撞保存失败：" + path)
			model.free()
			quit(1)
			return
		header += "[ext_resource type=\"Shape3D\" path=\"%s\" id=\"%s\"]\n" % [path, id]
		var body_name := id.to_pascal_case()
		bodies += "[node name=\"%s\" type=\"StaticBody3D\" parent=\"Collision\"]\n" % body_name
		bodies += "collision_layer = 1\ncollision_mask = 0\n\n"
		bodies += "[node name=\"Shape\" type=\"CollisionShape3D\" parent=\"Collision/%s\"]\nshape = ExtResource(\"%s\")\n\n" % [body_name, id]
		triangle_count += shape.get_faces().size() / 3
	var passage := _passage_mesh(false)
	var ramp := _passage_mesh(true)
	var ramp_shape := ConcavePolygonShape3D.new()
	ramp_shape.set_faces(ramp.get_faces())
	ramp_shape.backface_collision = true
	var cleaning_ramp := _cleaning_ramp()
	var cleaning_shape := ConcavePolygonShape3D.new()
	cleaning_shape.set_faces(cleaning_ramp.get_faces())
	cleaning_shape.backface_collision = true
	var additions := {"passage_mesh": passage, "ramp_mesh": ramp, "passage_ramp": ramp_shape, "cleaning_ramp_mesh": cleaning_ramp, "cleaning_ramp": cleaning_shape}
	additions.merge(generated)
	for id: String in additions:
		var path := SHAPES.path_join(id + ".res")
		if ResourceSaver.save(additions[id], path, ResourceSaver.FLAG_COMPRESS) != OK:
			push_error("通道资源保存失败：" + path)
			model.free()
			quit(1)
			return
	header += "[ext_resource type=\"Mesh\" path=\"%s/passage_mesh.res\" id=\"passage_mesh\"]\n" % SHAPES
	header += "[ext_resource type=\"Mesh\" path=\"%s/ramp_mesh.res\" id=\"ramp_mesh\"]\n" % SHAPES
	header += "[ext_resource type=\"Shape3D\" path=\"%s/passage_ramp.res\" id=\"ramp\"]\n" % SHAPES
	header += "[ext_resource type=\"Mesh\" path=\"%s/cleaning_ramp_mesh.res\" id=\"cleaning_ramp_mesh\"]\n" % SHAPES
	header += "[ext_resource type=\"Shape3D\" path=\"%s/cleaning_ramp.res\" id=\"cleaning_ramp\"]\n" % SHAPES
	header += "[ext_resource type=\"Shader\" path=\"res://shaders/map_passage_cut.gdshader\" id=\"cut_shader\"]\n"
	for part: String in ["优化墙", "圆环"]:
		header += "\n[sub_resource type=\"ShaderMaterial\" id=\"cut_%s\"]\nshader = ExtResource(\"cut_shader\")\n" % PARTS[part]
		header += "shader_parameter/mesh_to_map = %s\n" % var_to_str(model.get_node(NodePath(part)).transform)
		header += "shader_parameter/passage_start = %s\nshader_parameter/passage_end = %s\n" % [var_to_str(PASSAGE_START), var_to_str(PASSAGE_END)]
		header += "shader_parameter/radius = %s\nshader_parameter/spring_height = %s\nshader_parameter/arch_segments = %d\n" % [PASSAGE_RADIUS, PASSAGE_SPRING, ARCH_SEGMENTS]
		header += "shader_parameter/floor_start = %s\nshader_parameter/floor_end = %s\n" % [FLOOR_START, FLOOR_END]
		header += "shader_parameter/floor_transition = %s\n" % var_to_str(Vector2(SECTIONS[1], SECTIONS[2]))
	header += "\n[sub_resource type=\"StandardMaterial3D\" id=\"passage_mat\"]\nalbedo_color = Color(0.48, 0.43, 0.39, 1)\ncull_mode = 2\nroughness = 0.9\n"
	header += "\n[sub_resource type=\"StandardMaterial3D\" id=\"floor_mat\"]\nalbedo_color = Color(1, 1, 1, 1)\ncull_mode = 2\nroughness = 0.9\n"
	var content := header + "\n[node name=\"MapV2Geometry\" type=\"Node3D\"]\n"
	content += "metadata/source_sha256 = \"%s\"\n\n" % FileAccess.get_sha256(SOURCE)
	content += "[node name=\"Model\" parent=\".\" instance=ExtResource(\"model\")]\n\n"
	for part in ["优化墙", "圆环"]:
		content += "[node name=\"%s\" parent=\"Model\" index=\"%d\"]\nmaterial_override = SubResource(\"cut_%s\")\n\n" % [part, model.get_node(NodePath(part)).get_index(), PARTS[part]]
	content += "[node name=\"联通门\" parent=\"Model\" index=\"%d\"]\nvisible = false\n\n" % model.get_node("联通门").get_index()
	for part: String in floor_parts:
		content += "[node name=\"%s\" parent=\"Model\" index=\"%d\"]\nvisible = false\n\n" % [part, model.get_node(NodePath(part)).get_index()]
	for part: String in floor_parts:
		content += "[node name=\"%s\" type=\"MeshInstance3D\" parent=\".\"]\nmesh = ExtResource(\"%s_mesh\")\nmaterial_override = SubResource(\"floor_mat\")\n\n" % [String(PARTS[part]).to_pascal_case(), PARTS[part]]
	content += "[node name=\"Passage\" type=\"MeshInstance3D\" parent=\".\"]\nmesh = ExtResource(\"passage_mesh\")\nmaterial_override = SubResource(\"passage_mat\")\n\n"
	content += "[node name=\"Ramp\" type=\"MeshInstance3D\" parent=\".\"]\nmesh = ExtResource(\"ramp_mesh\")\nmaterial_override = SubResource(\"passage_mat\")\n\n"
	content += "[node name=\"CleaningRamp\" type=\"MeshInstance3D\" parent=\".\"]\nmesh = ExtResource(\"cleaning_ramp_mesh\")\nmaterial_override = SubResource(\"passage_mat\")\n\n"
	content += "[node name=\"Collision\" type=\"Node3D\" parent=\".\"]\n\n" + bodies
	content += "[node name=\"PassageRamp\" type=\"StaticBody3D\" parent=\"Collision\"]\ncollision_mask = 0\n\n"
	content += "[node name=\"Shape\" type=\"CollisionShape3D\" parent=\"Collision/PassageRamp\"]\nshape = ExtResource(\"ramp\")\n\n"
	content += "[node name=\"CleaningRamp\" type=\"StaticBody3D\" parent=\"Collision\"]\ncollision_mask = 0\n\n"
	content += "[node name=\"Shape\" type=\"CollisionShape3D\" parent=\"Collision/CleaningRamp\"]\nshape = ExtResource(\"cleaning_ramp\")\n\n"
	content += "[editable path=\"Model\"]\n"
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("场景保存失败：" + OUTPUT)
		model.free()
		quit(1)
		return
	file.store_string(content)
	file.close()
	model.free()
	print("MAP V2 BAKE: bodies=%d triangles=%d source=%s" % [PARTS.size() + 2, triangle_count + ramp.get_faces().size() / 3 + cleaning_ramp.get_faces().size() / 3, FileAccess.get_sha256(SOURCE)])
	quit(0)


## 保留凸切割体外侧的面，内轮廓与 shader 一致，外壳可嵌入完整墙面。
func _subtract_cuts(faces: PackedVector3Array, cuts: Array) -> PackedVector3Array:
	for cut: Dictionary in cuts:
		var result := PackedVector3Array()
		for i in range(0, faces.size(), 3):
			var polygon := PackedVector3Array([faces[i], faces[i + 1], faces[i + 2]])
			var bounds := AABB(polygon[0], Vector3.ZERO).expand(polygon[1]).expand(polygon[2]).grow(0.001)
			if not bounds.intersects(cut.bounds):
				result.append_array(polygon)
				continue
			for plane: Plane in cut.planes:
				var outside := _clip(polygon, -plane.normal, -plane.d)
				for j in range(1, outside.size() - 1):
					result.append_array(PackedVector3Array([outside[0], outside[j], outside[j + 1]]))
				polygon = _clip(polygon, plane.normal, plane.d)
				if polygon.is_empty():
					break
		faces = result
	return faces


func _clip(polygon: PackedVector3Array, normal: Vector3, distance: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	if polygon.is_empty():
		return result
	var previous := polygon[-1]
	var previous_distance := previous.dot(normal) - distance
	for point in polygon:
		var current_distance := point.dot(normal) - distance
		if (current_distance >= 0) != (previous_distance >= 0):
			result.append(previous.lerp(point, previous_distance / (previous_distance - current_distance)))
		if current_distance >= 0:
			result.append(point)
		previous = point
		previous_distance = current_distance
	return result


## 内外拱面、底边和端口封边组成完整墙壳，不再用双面薄片代替外侧。
func _passage_mesh(floor_only: bool) -> ArrayMesh:
	var centers: Array[Vector3] = []
	for t: float in SECTIONS:
		centers.append(_passage_center(t))
	var lateral := (PASSAGE_END - PASSAGE_START).normalized().cross(Vector3.UP)
	if floor_only:
		return _floor_mesh(centers, lateral, PASSAGE_RADIUS + PASSAGE_WALL)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: Array[PackedVector3Array] = []
	var outer: Array[PackedVector3Array] = []
	for t: float in SECTIONS:
		inner.append(_ring(t, PASSAGE_RADIUS))
		outer.append(_ring(t, PASSAGE_RADIUS + PASSAGE_WALL))
	for i in range(inner.size() - 1):
		for j in range(inner[i].size() - 1):
			_quad(tool, inner[i][j], inner[i + 1][j], inner[i + 1][j + 1], inner[i][j + 1])
			_quad(tool, outer[i][j + 1], outer[i + 1][j + 1], outer[i + 1][j], outer[i][j])
		_quad(tool, outer[i][0], outer[i + 1][0], inner[i + 1][0], inner[i][0])
		_quad(tool, inner[i][-1], inner[i + 1][-1], outer[i + 1][-1], outer[i][-1])
	for j in range(inner[0].size() - 1):
		_quad(tool, inner[0][j + 1], outer[0][j + 1], outer[0][j], inner[0][j])
		_quad(tool, inner[-1][j], outer[-1][j], outer[-1][j + 1], inner[-1][j + 1])
	tool.generate_normals()
	return tool.commit()


## 清扫地板比主厅高约 10cm；提前抬升脚底，避免玩家碰撞盒卡在地板侧面。
func _cleaning_ramp() -> ArrayMesh:
	return _floor_mesh([Vector3(5.8, FLOOR_START, 0), Vector3(6.6, 0.0153, 0), Vector3(8.0, 0.0153, 0)], Vector3.FORWARD, 1.2)


func _passage_center(t: float) -> Vector3:
	var center := PASSAGE_START.lerp(PASSAGE_END, t)
	center.y = lerpf(FLOOR_START, FLOOR_END, clampf((t - SECTIONS[1]) / (SECTIONS[2] - SECTIONS[1]), 0, 1))
	return center


func _ring(t: float, radius: float) -> PackedVector3Array:
	var center := _passage_center(t)
	var lateral := (PASSAGE_END - PASSAGE_START).normalized().cross(Vector3.UP)
	var ring := PackedVector3Array([center - lateral * radius - Vector3.UP * 0.1])
	for segment in range(ARCH_SEGMENTS + 1):
		var angle := PI - float(segment) * PI / ARCH_SEGMENTS
		ring.append(center + lateral * (cos(angle) * radius) + Vector3.UP * (PASSAGE_SPRING + sin(angle) * radius))
	ring.append(center + lateral * radius - Vector3.UP * 0.1)
	return ring


func _wall_cuts() -> Array:
	var cuts := []
	for i in range(SECTIONS.size() - 1):
		cuts.append(_prism(_ring(SECTIONS[i], PASSAGE_RADIUS), _ring(SECTIONS[i + 1], PASSAGE_RADIUS)))
	return cuts


func _rectangle_cut(start: Vector3, end: Vector3, half_width: float) -> Dictionary:
	var lateral := (end - start).normalized().cross(Vector3.UP) * half_width
	var a := PackedVector3Array([start - lateral - Vector3.UP * 4, start - lateral + Vector3.UP * 4, start + lateral + Vector3.UP * 4, start + lateral - Vector3.UP * 4])
	var b := PackedVector3Array([end - lateral - Vector3.UP * 4, end - lateral + Vector3.UP * 4, end + lateral + Vector3.UP * 4, end + lateral - Vector3.UP * 4])
	return _prism(a, b)


func _prism(a: PackedVector3Array, b: PackedVector3Array) -> Dictionary:
	var planes: Array[Plane] = []
	var bounds := AABB(a[0], Vector3.ZERO)
	var inside := Vector3.ZERO
	for point in a + b:
		bounds = bounds.expand(point)
		inside += point
	inside /= a.size() + b.size()
	planes.append(Plane(a[0], a[1], a[2]))
	planes.append(Plane(b[0], b[1], b[2]))
	for i in range(a.size()):
		planes.append(Plane(a[i], b[i], a[(i + 1) % a.size()]))
	for i in range(planes.size()):
		if planes[i].distance_to(inside) < 0:
			planes[i] = Plane(-planes[i].normal, -planes[i].d)
	return {"planes": planes, "bounds": bounds.grow(0.002)}


## 上表面、底面、侧边与端头封闭；原地板裁掉覆盖区域，只有一层可见地面。
func _floor_mesh(centers: Array[Vector3], lateral: Vector3, half_width: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var down := Vector3.DOWN * FLOOR_DEPTH
	for i in range(centers.size() - 1):
		var a := centers[i] - lateral * half_width
		var b := centers[i] + lateral * half_width
		var c := centers[i + 1] + lateral * half_width
		var d := centers[i + 1] - lateral * half_width
		_quad(tool, a, b, c, d)
		_quad(tool, d + down, c + down, b + down, a + down)
		_quad(tool, a, d, d + down, a + down)
		_quad(tool, c, b, b + down, c + down)
	for edge in [0, centers.size() - 1]:
		var a := centers[edge] - lateral * half_width
		var b := centers[edge] + lateral * half_width
		_quad(tool, b, a, a + down, b + down)
	tool.generate_normals()
	return tool.commit()


func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for vertex in [a, b, c, a, c, d]:
		tool.add_vertex(vertex)


func _mesh_from_faces(faces: PackedVector3Array) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in faces:
		tool.add_vertex(point)
	tool.generate_normals()
	return tool.commit()
