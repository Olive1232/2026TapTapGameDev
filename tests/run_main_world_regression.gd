extends SceneTree

## 当前正式入口、原样模型及旧档迁移；菜单按钮的实际输入另由菜单专项验证。
var _passed := 0
var _failed := 0
var _directory := "/tmp/main-world-regression"
var _save
var _flow
var _wallet


func _initialize() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("MAIN WORLD REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("MAIN WORLD REGRESSION FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _write_legacy(version: int) -> void:
	var payload := {"version": version, "coins": "9007199254740993"}
	if version >= 2:
		payload.upgrades = {"corpse_return": true, "charged_throw": true}
	if version >= 3:
		payload.upgrades.oil = true
	if version >= 4:
		payload.level = "world"
		payload.opened_gates = {"world.cleaning.vines": true, "world.cleaning.weight_gate": true}
	if version >= 5:
		payload.upgrade_levels = {"corpse_value": "3"}
	if version >= 6:
		payload.upgrade_levels.golden_coin = "20"
	if version >= 7:
		payload.upgrades.mirror = true
		payload.tutorial_stage = "pickup"
	var file := FileAccess.open(_save.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()


func _run() -> void:
	await process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data-dir="):
			_directory = argument.trim_prefix("--data-dir=")
	if not _directory.begins_with("/tmp/"):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	_save = root.get_node("SaveGame")
	_flow = root.get_node("GameFlow")
	_wallet = root.get_node("Wallet")
	_save.save_path = _directory.path_join("savegame.json")
	root.get_node("GameSettings").settings_path = _directory.path_join("settings.cfg")
	_check(_flow.GAME_SCENE == "res://scenes/rooms/main_world.tscn" and _flow.SAVE_LEVELS.world == _flow.GAME_SCENE, "all world entrances target main_world")
	_check(_flow.start_new_game().ok, "new game starts")
	await scene_changed
	await _frames(60)
	var scene := current_scene
	var player := scene.get_node("Player") as CharacterBody3D
	_check(_flow.is_in_game() and player.is_on_floor(), "main_world is playable and player rests on original floor")
	_check(player.scale.is_equal_approx(Vector3.ONE) and player.get_parent() == scene, "player retains original size")
	var model := scene.get_node("MapScale/MapOrigin")
	_check(model.scene_file_path == "res://assets/main_world_v3.glb", "formal world references v3 GLB")
	_check(FileAccess.get_sha256("res://assets/main_world_v3.glb") == "84ace4df0d9234594f9b8e4675e3967334824e7aa07935c8de454e86f856df07", "v3 source geometry has not changed")
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var original_model := (load("res://assets/main_world_v3.glb") as PackedScene).instantiate()
	var collisions := scene.get_node("MapScale/Collision")
	_check(collisions.get_child_count() == 4 and meshes.size() == 4, "all four v3 meshes have collisions")
	for body: StaticBody3D in collisions.get_children():
		var mesh := model.get_node_or_null(NodePath(body.get_meta("source_mesh"))) as MeshInstance3D
		_check(mesh != null, "v3 collision identifies an imported source mesh: " + str(body.name))
		if mesh == null:
			continue
		var original_mesh := original_model.get_node(NodePath(body.get_meta("source_mesh"))) as MeshInstance3D
		_check(mesh.mesh.get_faces() == original_mesh.mesh.get_faces(), "scene preserves original imported geometry: " + str(mesh.name))
		var shape := body.get_node("Shape").shape as ConcavePolygonShape3D
		_check(body.transform.is_equal_approx(mesh.transform), "v3 collision matches imported transform: " + str(mesh.name))
		_check(shape.backface_collision and shape.get_faces() == mesh.mesh.get_faces(), "v3 mesh has matching double-sided triangle collision: " + str(mesh.name))
	original_model.free()
	_check(not scene.has_node("PassageRepairs/GalleryRamp"), "gallery has no added ramp")
	var wall_ray := PhysicsRayQueryParameters3D.create(Vector3(51, 4.8, 10), Vector3(51, 4.8, 0), 1)
	var wall_hit := player.get_world_3d().direct_space_state.intersect_ray(wall_ray)
	_check(not wall_hit.is_empty() and wall_hit.collider == collisions.get_node("Mesh01"), "gallery wall uses the original model collision")
	_check(scene.get_node("HUD/OnboardingHints").get_stage() == "controls", "new main_world keeps onboarding")
	_check(not scene.get_node("HUD/BottomText").visible and scene.get_node("HUD/BottomText").get_displayed_text().is_empty(), "main world has no persistent instruction panel")
	for version in range(1, 8):
		_write_legacy(version)
		var expected: Dictionary = _save.read_save()
		_check(expected.ok and _flow.load_game().ok, "load legacy v%d" % version)
		await scene_changed
		await _frames()
		scene = current_scene
		_check(scene.scene_file_path == "res://scenes/rooms/main_world.tscn", "legacy v%d enters new world" % version)
		_check(_wallet.total == 9007199254740993 and scene.get_node("HUD/MoneyUI")._label.text == "9007199254740993", "legacy v%d retains exact coins and HUD" % version)
		_check(_flow.get_purchased_upgrades() == expected.upgrades and _flow.get_purchased_upgrade_levels() == expected.upgrade_levels, "legacy v%d retains all purchases and levels" % version)
		_check(_flow.get_level_snapshot().opened_gates == expected.opened_gates, "legacy v%d retains unplaced mechanism progress" % version)
		_check(scene.get_node("Player/Camera3D/WeaponRig/WeaponPivot/Mount").oiled == expected.upgrades.oil and scene.get_node("Player/Camera3D/Grabber").charged_throw_enabled == expected.upgrades.charged_throw, "legacy v%d restores available player abilities" % version)
		var hole = scene.get_node("Hole")
		_check(hole.has_upgrade("mirror") == expected.upgrades.mirror and hole.get_corpse_value_level() == expected.upgrade_levels.corpse_value and hole.get_golden_coin_level() == expected.upgrade_levels.golden_coin, "legacy v%d restores migrated hole upgrades" % version)
		_check(hole.has_upgrade("corpse_return") == expected.upgrades.corpse_return and scene.get_node("CorpseReturnOutlet").is_enabled() == expected.upgrades.corpse_return, "legacy v%d restores soul egg on the placed outlet" % version)
		_check(_flow.get_tutorial_stage() == expected.tutorial_stage, "legacy v%d retains tutorial stage" % version)
		_flow.pause_game()
		_check(paused and _save.save_game().ok, "legacy v%d can save while paused in new world" % version)
		var rewritten: Dictionary = _save.read_save()
		_check(rewritten.upgrades == expected.upgrades and rewritten.upgrade_levels == expected.upgrade_levels and rewritten.opened_gates == expected.opened_gates and rewritten.tutorial_stage == expected.tutorial_stage, "legacy v%d survives a v7 save round trip" % version)
		_flow.resume_game()
	var upgrades: Dictionary = _flow.get_purchased_upgrades()
	upgrades.mirror = false
	_check(_flow.get_purchased_upgrades().mirror, "snapshot dictionaries do not alias live purchase records")
	var invalid_upgrades: Dictionary = _flow.get_purchased_upgrades()
	invalid_upgrades.oil = "invalid"
	_check(not current_scene.restore_purchased_upgrades(invalid_upgrades) and _flow.get_purchased_upgrades().oil, "invalid restore preserves current upgrade snapshot")
	var snapshot := FileAccess.get_file_as_string(_save.save_path)
	var pool := root.get_node("CoinPool")
	var coin = pool.acquire()
	_check(coin.get_parent() == current_scene, "coin pool belongs to new world")
	var old_scene: WeakRef = weakref(current_scene)
	_flow.pause_game()
	_check(_flow.return_to_main_menu().ok, "return to main menu from paused new world")
	await scene_changed
	await _frames()
	_check(not paused and current_scene.scene_file_path == _flow.MAIN_MENU and not _flow.is_in_game(), "menu transition releases pause state")
	_check(old_scene.get_ref() == null and pool.active_count() == 0 and pool.free_count() == 0, "world transition removes old scene and pooled references")
	_check(FileAccess.get_file_as_string(_save.save_path) == snapshot, "return to menu does not overwrite save")
	_check(_flow.start_new_game().ok, "start another new game")
	await scene_changed
	await _frames()
	_check(_wallet.total == 0 and _flow.get_purchased_upgrades() == _save.empty_upgrades() and _flow.get_purchased_upgrade_levels() == _save.empty_upgrade_levels(), "new game resets coins and purchase records")
	_check(not current_scene.get_node("Player/Camera3D/WeaponRig/WeaponPivot/Mount").oiled and not current_scene.get_node("Player/Camera3D/Grabber").charged_throw_enabled, "new player does not inherit legacy abilities")
	var new_hole = current_scene.get_node("Hole")
	_check(not new_hole.has_upgrade("mirror") and new_hole.get_corpse_value_level() == 0 and new_hole.get_golden_coin_level() == 0, "new hole does not inherit legacy upgrades")
	_check(_flow.get_level_snapshot().opened_gates.is_empty() and _flow.get_tutorial_stage() == "controls", "new game resets gate and tutorial state")
	_check(FileAccess.get_file_as_string(_save.save_path) == snapshot, "new game preserves existing disk save")
	print("MAIN WORLD REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
