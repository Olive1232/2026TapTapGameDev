extends SceneTree

## 验证迁移后的资源加载、大小写、导入引用与公共类型注册。
var _passed := 0
var _failed := 0
var _paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("STRUCTURE REGRESSION FAILED: " + message)

func _collect(path: String) -> void:
	var directory := DirAccess.open(path)
	for name in directory.get_files():
		_paths.append(path.path_join(name))
	for name in directory.get_directories():
		_collect(path.path_join(name))

func _run() -> void:
	await process_frame
	for branch in ["scripts", "scenes", "resources", "assets", "shaders", "tests"]:
		_collect("res://" + branch)
	var exact_paths := {}
	for path in _paths:
		exact_paths[path] = true
	for path in _paths:
		var extension := path.get_extension()
		if extension in ["gd", "tscn", "tres", "res", "gdshader", "meshlib", "png", "ttf", "otf"]:
			var resource := load(path)
			_check(resource != null, "load " + path)
			if resource is PackedScene:
				var scene: Node = (resource as PackedScene).instantiate()
				_check(scene != null, "instantiate " + path)
				scene.free()
			for dependency in ResourceLoader.get_dependencies(path):
				var referenced: String = dependency.get_slice("::", dependency.get_slice_count("::") - 1)
				_check(exact_paths.has(referenced), "dependency exists with exact case: " + referenced)
		if extension == "import":
			var config := ConfigFile.new()
			_check(config.load(path) == OK, "read import " + path)
			_check(config.get_value("deps", "source_file", "") == path.trim_suffix(".import"), "import points at own source " + path)
	for info in ProjectSettings.get_global_class_list():
		if info.class == "CollisionLayers":
			_check(info.path == "res://scripts/shared/collision_layers.gd", "CollisionLayers registered at new path")
		if info.class == "MonsterData":
			_check(info.path == "res://resources/types/monster_data.gd", "MonsterData registered at new path")
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/ui/main_menu.tscn", "entry uses new path")
	print("STRUCTURE REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
