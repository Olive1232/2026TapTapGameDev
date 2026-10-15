extends SceneTree

## 真实 Area 进店、物理投尸、左键消费、对白排队及存档首次标记。
var _story_script
const COLLECT := preload("res://tests/helpers/coin_collection.gd")
var _passed := 0
var _failed := 0
var _flow
var _save
var _wallet
var _world: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _ui: BottomText
var _story: Node
var _hole
var _grabber
var _sword
var _eruptions: Array[int] = []
var _capture_dir := ""


func _initialize() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func():
		push_error("DIALOGUE REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("DIALOGUE REGRESSION FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _mouse(button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = Vector2(8, 8)
		event.global_position = event.position
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _enter(load_saved: bool = false) -> void:
	_check((_flow.load_game() if load_saved else _flow.start_new_game()).ok, "enter world")
	await scene_changed
	_world = current_scene
	_player = _world.get_node("Player")
	_player.set_physics_process(false)
	_camera = _player.get_node("Camera3D")
	_grabber = _camera.get_node("Grabber")
	_sword = _camera.get_node("WeaponRig/WeaponPivot/Mount")
	_ui = _world.get_node("HUD/BottomText")
	_story = _world.get_node("WorldDialogue")
	_hole = _world.get_node("Hole")
	for node in _world.get_children():
		if "enabled" in node and node.scene_file_path == "res://scenes/enemies/monster_spawner.tscn":
			node.enabled = false
	await _frames()


func _stand(at: Vector3) -> void:
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _frames(8)


func _capture(name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(_capture_dir.path_join(name + ".png")) == OK, "capture " + name)


func _spawn_corpse(at: Vector3):
	var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
	corpse.setup(load("res://resources/enemies/monster_rat.tres"))
	_world.add_child(corpse)
	corpse.global_position = at
	corpse.reset_physics_interpolation()
	return corpse


func _test_bootstrap() -> void:
	var fixture: Node3D = load("res://scenes/rooms/main_world.tscn").instantiate()
	# 模拟旧场景 / 编辑器重新保存后，两个剧情节点都未序列化的情况。
	for node_name in ["WorldDialogue", "ShopDialogueZone"]:
		var stale := fixture.get_node_or_null(NodePath(node_name))
		if stale != null:
			stale.free()
	root.add_child(fixture)
	current_scene = fixture
	await _frames()
	_check(fixture.has_node("WorldDialogue") and fixture.has_node("ShopDialogueZone"), "world startup recreates missing dialogue controller and trigger")
	var zone := fixture.get_node("ShopDialogueZone") as Area3D
	_check(zone.collision_layer == 0 and zone.collision_mask == 2, "generated shop trigger detects only the player")
	var box := zone.get_node("Shape").shape as BoxShape3D
	var keeper := fixture.get_node("Shopkeeper") as Node3D
	_check(AABB(zone.position - box.size * 0.5, box.size).has_point(keeper.position + Vector3.UP), "generated trigger follows current shop placement")
	_check(fixture.get_node("Hole").corpse_received.get_connections().size() == 1, "startup connects hole to exactly one dialogue controller")
	fixture.queue_free()
	await _frames()
	# 控制器保留在场景里、只有触发区丢失时，也要在父节点就绪后正常补齐。
	fixture = load("res://scenes/rooms/main_world.tscn").instantiate()
	for node_name in ["WorldDialogue", "ShopDialogueZone"]:
		var stale := fixture.get_node_or_null(NodePath(node_name))
		if stale != null:
			stale.free()
	var retained_controller: Node = _story_script.new()
	retained_controller.name = "WorldDialogue"
	fixture.add_child(retained_controller)
	root.add_child(fixture)
	current_scene = fixture
	await _frames()
	_check(fixture.has_node("ShopDialogueZone") and fixture.get_node("WorldDialogue") == retained_controller, "authored controller recreates only its missing trigger")
	_check(fixture.get_node("Hole").corpse_received.get_connections().size() == 1, "retained controller connects once after parent ready")
	fixture.queue_free()
	await _frames()
	# 显式摆放的触发器必须被复用，不能被默认尺寸覆盖或重复接线。
	fixture = load("res://scenes/rooms/main_world.tscn").instantiate()
	for node_name in ["WorldDialogue", "ShopDialogueZone"]:
		var stale := fixture.get_node_or_null(NodePath(node_name))
		if stale != null:
			stale.free()
	var authored_zone := Area3D.new()
	authored_zone.name = "ShopDialogueZone"
	authored_zone.position = Vector3(-86, 4, 3)
	fixture.add_child(authored_zone)
	var authored_controller: Node = _story_script.new()
	authored_controller.name = "WorldDialogue"
	fixture.add_child(authored_controller)
	root.add_child(fixture)
	current_scene = fixture
	_check(fixture.get_node("WorldDialogue") == authored_controller and fixture.get_node("ShopDialogueZone") == authored_zone, "startup reuses authored dialogue nodes")
	_check(authored_zone.position == Vector3(-86, 4, 3) and authored_zone.get_child_count() == 0, "authored trigger configuration is preserved")
	_check(fixture.get_node("Hole").corpse_received.get_connections().size() == 1, "authored controller is not duplicated")
	fixture.queue_free()
	await _frames()


func _run() -> void:
	await process_frame
	_story_script = load("res://scripts/dialogue/world_dialogue.gd")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=/tmp/"):
			_capture_dir = argument.trim_prefix("--capture-dir=")
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	_save = root.get_node("SaveGame")
	_flow = root.get_node("GameFlow")
	_wallet = root.get_node("Wallet")
	_save.save_path = "/tmp/taptap-dialogue-regression/savegame.json"
	DirAccess.make_dir_recursive_absolute("/tmp/taptap-dialogue-regression")
	root.get_node("GameSettings").settings_path = "/tmp/taptap-dialogue-regression/settings.cfg"
	root.get_node("EventBus").coins_erupted.connect(func(value, _count): _eruptions.append(value))
	await _test_bootstrap()
	await _enter()
	_check(not _ui.is_dialogue_active(), "no conversation at spawn")
	await _stand(Vector3(-85.5, 2.9, 4))
	_camera.look_at(_world.get_node("Shopkeeper").get_hit_center())
	_check(_story.get_progress().shop_visited and _ui.get_dialogue_source() == &"shop_intro", "actual empty-handed first shop entry starts keeper")
	_check(_ui.get_node("TextBox/Speaker").text == "店长" and _ui.get_node("TextBox/Continue").visible, "speaker and click hint are visible")
	_check(not _world.get_node("HUD/OnboardingHints").visible, "conversation hides onboarding without changing its progress")
	await _capture("01_shop_intro")
	var first := _ui.get_displayed_text()
	_mouse(MOUSE_BUTTON_RIGHT)
	await _frames()
	_check(_ui.get_displayed_text() == first, "right click cannot advance conversation")
	_flow.pause_game()
	await _frames()
	_mouse()
	await _frames()
	_check(not _ui.visible and _ui.get_displayed_text() == first, "paused dialogue cannot advance")
	_flow.resume_game()
	_ui.set_message(&"shop_description", "商品说明保持更新", BottomText.DESCRIPTION)
	# 世界每帧会刷新商品来源，用独立来源验证对白覆盖与还原。
	_ui.set_message(&"test_description", "排队后最新的商品说明", BottomText.DESCRIPTION)
	_check(_ui.play_dialogue(&"queued", "朋友", PackedStringArray(["排队的一句"])), "second conversation can queue")
	_check(not _ui.play_dialogue(&"queued", "朋友", PackedStringArray(["重复"])), "queued source cannot duplicate")
	_check(not _ui.play_dialogue(&"blank", "朋友", PackedStringArray(["  "])), "empty conversation rejected")
	for index in _story_script.SHOP_LINES.size():
		_check(_ui.get_displayed_text() == _story_script.SHOP_LINES[index], "keeper line %d matches authored text" % index)
		_mouse()
		await _frames(1)
		_check(_sword._state == 0, "advancing or closing dialogue never swings")
	_check(_ui.get_dialogue_source() == &"queued", "queued dialogue follows keeper")
	_mouse()
	await _frames()
	_check(not _ui.is_dialogue_active() and _ui.get_displayed_text() == "排队后最新的商品说明", "latest description restores after final click")
	_check(not _ui.get_node("TextBox/Continue").visible, "descriptions have no click hint")
	_check(_world.get_node("HUD/OnboardingHints").visible, "onboarding returns when conversation ends")
	_ui.clear_message(&"test_description")
	await _stand(Vector3(-28.5, 3.44, -1.5))
	await _stand(Vector3(-85.5, 2.9, 4))
	_check(not _ui.is_dialogue_active(), "keeper intro never repeats on reentry")
	var stock := _world.get_node("GoldenCoinShelf")
	await _stand(stock.global_position + stock.global_basis.z * 1.9 + Vector3.UP * 0.5)
	_camera.look_at(stock.get_node("ItemSpawn").global_position)
	await _frames()
	_check(_ui.get_displayed_source() == &"shop_description" and _ui.get_displayed_text().contains(stock.item_data.description), "real aimed product description appears in shared panel")
	_check(_world.get_node("HUD/OnboardingHints").get_panel_rect().end.y < _ui.get_panel_rect().position.y, "onboarding stays above the description panel")
	await _capture("01b_product_description")
	_mouse()
	await _frames(1)
	_check(_ui.get_displayed_source() == &"shop_description" and _sword._state != 0, "description needs no advance and does not consume normal attack")
	await _frames(60)

	# 从坑边真实抓起并释放，等待吸力和吞入，不能直接调用剧情回调。
	await _stand(_hole.global_position + Vector3(12, 0.51, 0))
	_player.rotation = Vector3(0, PI / 2, 0)
	_camera.look_at(_hole.global_position + Vector3.UP * 0.5)
	var corpse = _spawn_corpse(_camera.global_position - _camera.global_basis.z * 1.6)
	await _frames(1)
	_check(_grabber.try_grab() and _grabber.get_held() == corpse, "real grab holds rat corpse")
	await _frames(12)
	_grabber.drop(true)
	await _frames(240)
	_check(not is_instance_valid(corpse) and not _grabber.is_holding() and is_zero_approx(_player.carry_weight), "offering destroys corpse and clears held weight")
	_check(_ui.get_dialogue_source() == &"hole_intro" and _ui.get_node("TextBox/Speaker").text == "洞", "first physical offering starts hole dialogue")
	_check(_hole.has_pending() and _eruptions.is_empty(), "first settlement waits beyond normal two seconds for dialogue")
	await _capture("02_hole_intro")
	for index in _story_script.HOLE_LINES.size():
		_check(_ui.get_displayed_text() == _story_script.HOLE_LINES[index], "hole line %d matches authored text" % index)
		if index == 7:
			for dimensions in [Vector2i(960, 640), Vector2i(1280, 720), Vector2i(2560, 1080)]:
				root.size = dimensions
				await _frames()
				var panel := _ui.get_panel_rect()
				_check(panel.position.x >= 0 and panel.position.y >= 0 and panel.end.x <= _ui.size.x and panel.end.y <= _ui.size.y, "longest line panel fits %s" % dimensions)
				await _capture("03_long_line_%dx%d" % [dimensions.x, dimensions.y])
		if index < _story_script.HOLE_LINES.size() - 1:
			_check(_eruptions.is_empty(), "no reward before last line")
		_mouse()
		await _frames(1)
	_check(_eruptions.size() == 1 and not _hole.has_pending() and _wallet.total == 0, "last line erupts once; wallet still requires collection")
	root.size = Vector2i(1280, 720)
	await _frames(300)
	_check(await COLLECT.collect_all(self, _player), "intro reward physically lands and can be collected")
	_check(_wallet.total == _eruptions[0], "collected money equals real first eruption")
	_spawn_corpse(_hole.global_position + Vector3.UP * 0.5)
	await _frames(180)
	_check(not _ui.is_dialogue_active() and _eruptions.size() == 2, "later offering settles normally without intro")
	_check(_save.save_game().ok, "save dialogue progress")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_save.save_path))
	_check(_save.read_save().dialogue_progress == {"shop_visited": true, "hole_introduced": true}, "save includes both first-event flags")
	await _enter(true)
	await _stand(Vector3(-85.5, 2.9, 4))
	_spawn_corpse(_hole.global_position + Vector3.UP * 0.5)
	await _frames(180)
	_check(not _ui.is_dialogue_active() and _eruptions.size() == 3, "load does not replay either intro")
	_check(_flow.reset_current_game().ok, "debug reset accepted")
	await scene_changed
	await _frames()
	_check(_flow.get_dialogue_progress() == {"shop_visited": true, "hole_introduced": true}, "debug reset preserves first-event flags")

	# 钱包不能代替空手条件；有金币但未持物的首访仍然播放。
	await _enter()
	_wallet.add(1)
	await _stand(Vector3(-85.5, 2.9, 4))
	_check(_ui.get_dialogue_source() == &"shop_intro" and _story.get_progress().shop_visited, "empty-handed first visitor with coins still hears keeper")
	for index in _story_script.SHOP_LINES.size():
		_mouse()
		await _frames(1)
	_wallet.reset()
	await _stand(Vector3(-28.5, 3.44, -1.5))
	await _stand(Vector3(-85.5, 2.9, 4))
	_check(not _ui.is_dialogue_active(), "becoming poor later does not replay first-entry event")
	await _enter()
	_grabber.grab_range = 5
	var carried = _spawn_corpse(_camera.global_position - _camera.global_basis.z * 1.6)
	await _frames(1)
	_check(_grabber.try_grab() and _grabber.get_held() == carried, "grab object before first shop visit")
	await _stand(Vector3(-85.5, 2.9, 4))
	_check(not _ui.is_dialogue_active() and _story.get_progress().shop_visited, "carrying first visitor skips intro")
	for invalid in [null, [], {}, {"shop_visited": 1, "hole_introduced": false}, {"shop_visited": false, "hole_introduced": false, "other": true}]:
		var payload := saved.duplicate(true)
		payload.dialogue_progress = invalid
		_write(payload)
		_check(not _save.read_save().ok and not _flow.load_game().ok, "invalid dialogue state rejected before changing scene")
	saved.erase("dialogue_progress")
	_write(saved)
	_check(_save.read_save().ok and _save.read_save().dialogue_progress == _save.empty_dialogue_progress(), "older saves remain compatible")
	var old_ui := _ui.get_instance_id()
	_flow.return_to_main_menu()
	await scene_changed
	await _frames()
	_check(not is_instance_id_valid(old_ui) and get_nodes_in_group("bottom_text_ui").is_empty(), "leaving scene removes conversation UI and signals")
	print("DIALOGUE REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _write(payload: Dictionary) -> void:
	var file := FileAccess.open(_save.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
