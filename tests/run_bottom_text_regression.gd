extends SceneTree

## 消息覆盖 / 到期 / 暂停，以及真实地图商品、遮挡、搬运与交易反馈。
var _passed := 0
var _failed := 0
var _ui: BottomText
var _room: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _shop: Node3D
var _grabber
var _directory := ""
var _capture_directory := ""


func _initialize() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func():
		push_error("BOTTOM TEXT REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("BOTTOM TEXT REGRESSION FAILED: " + message)


func _frames(count: int = 4) -> void:
	for index in count:
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(ceili(seconds * Engine.physics_ticks_per_second) + 1)


func _run() -> void:
	await process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data-dir="):
			_directory = argument.trim_prefix("--data-dir=")
		elif argument.begins_with("--capture-dir="):
			_capture_directory = argument.trim_prefix("--capture-dir=")
	if not _directory.begins_with("/tmp/"):
		push_error("Use an isolated /tmp/ data directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	if _capture_directory.begins_with("/tmp/"):
		DirAccess.make_dir_recursive_absolute(_capture_directory)
	else:
		_capture_directory = ""
	root.get_node("SaveGame").save_path = _directory.path_join("savegame.json")
	root.get_node("GameSettings").settings_path = _directory.path_join("settings.cfg")
	await _test_messages()
	await _test_world()
	await _test_lifecycle()
	paused = false
	print("BOTTOM TEXT REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_messages() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	current_scene = layer
	_ui = load("res://scenes/ui/bottom_text.tscn").instantiate()
	# 允许后续剧情组件在 ready 前提交文字。
	_ui.set_message(&"guide", "基本操作指引")
	layer.add_child(_ui)
	await _frames()
	_check(_ui.visible and _ui.get_displayed_text() == "基本操作指引", "message submitted before ready is shown")
	_ui.set_message(&"description", "镜子 · 200 金币\n尸体入洞价值 ×2", BottomText.DESCRIPTION)
	_ui.set_message(&"feedback", "购买完成", BottomText.FEEDBACK, 0.3)
	_check(_ui.get_displayed_source() == &"feedback", "feedback overrides description and guidance")
	_ui.set_message(&"guide", "已更新的操作指引")
	_ui.clear_message(&"description")
	_check(_ui.get_displayed_text() == "购买完成", "clearing older source cannot erase current feedback")
	_ui.set_message(&"description", "镜子说明", BottomText.DESCRIPTION)
	await _wait(0.4)
	_check(_ui.get_displayed_text() == "镜子说明", "expiry restores latest description")
	_ui.clear_message(&"description")
	_check(_ui.get_displayed_text() == "已更新的操作指引", "clearing target restores updated guidance")
	_ui.set_message(&"timed", "暂停后继续显示", BottomText.FEEDBACK, 0.4)
	paused = true
	await _wait(0.6)
	_check(not _ui.visible and _ui.get_displayed_text() == "暂停后继续显示", "pause hides text and preserves timed message")
	paused = false
	await _frames()
	_check(_ui.visible and _ui.get_displayed_text() == "暂停后继续显示", "resume restores unexpired message")
	await _wait(0.5)
	_check(_ui.get_displayed_source() == &"guide", "timer continues after resume")
	_ui.set_message(&"a", "同优先级旧消息", BottomText.DESCRIPTION)
	_ui.set_message(&"b", "同优先级新消息", BottomText.DESCRIPTION)
	_ui.set_message(&"a", "同优先级旧消息", BottomText.DESCRIPTION)
	_check(_ui.get_displayed_source() == &"b", "unchanged persistent updates do not steal priority")
	_ui.clear_all()
	_check(not _ui.visible and _ui.get_displayed_text().is_empty(), "clear all hides empty component")
	_ui.set_message(&"blank", "   \n")
	_check(not _ui.visible, "whitespace-only message is cleared")
	_ui.set_message(&"long", "这是用于测试底部像素文字换行的长说明。".repeat(5))
	await _frames()
	await _check_layout()
	_ui.set_message(&"long", "短说明")
	await _frames()
	await _check_layout()
	_ui.set_message(&"long", "这是用于检查窗口换行的长指引。".repeat(6))
	for dimensions in [Vector2i(960, 640), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		root.size = dimensions
		await _frames()
		await _check_layout()
		await _capture("window_%dx%d" % [dimensions.x, dimensions.y])
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_FULLSCREEN
		await _frames()
		await _check_layout()
		await _capture("fullscreen")
		root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	await _frames()
	layer.queue_free()
	await _frames()


func _check_layout() -> void:
	var label: Label = _ui.get_node("TextBox/Text")
	var rect := label.get_global_rect()
	_check(absf(rect.get_center().x - _ui.size.x / 2.0) <= 1.0, "text is horizontally centered")
	_check(absf(rect.end.y - (_ui.size.y - _ui.bottom_margin)) <= 1.0, "last line keeps its bottom margin")
	_check(rect.position.x >= _ui.side_margin and rect.end.x <= _ui.size.x - _ui.side_margin, "text width respects side margins")
	_check(rect.position.y >= 0.0 and rect.end.y <= _ui.size.y, "wrapped text stays in screen")
	_check(label.get_theme_font("font") == load("res://resources/ui/pixel_font.tres"), "actual label uses bundled pixel font")
	_check(_ui.mouse_filter == Control.MOUSE_FILTER_IGNORE and label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "overlay cannot consume mouse interaction")


func _capture(name: String) -> void:
	if _capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(_capture_directory.path_join(name + ".png")) == OK, "capture actual rendered " + name)


func _bind_world() -> void:
	_room = current_scene
	_player = _room.get_node("Player")
	_player.set_physics_process(false)
	_camera = _player.get_node("Camera3D")
	_shop = _room.get_node("ShopRoom")
	_grabber = _camera.get_node("Grabber")
	_ui = _room.get_node("HUD/BottomText")
	for node in get_nodes_in_group("monster_spawners"):
		node.enabled = false


func _at_stock(stock: Node3D) -> void:
	_player.global_position = stock.global_position + Vector3(0, 0.5, 1.5)
	_camera.look_at(stock.get_node("ItemSpawn").global_position, Vector3.UP)
	_player.reset_physics_interpolation()
	await _frames()


func _at_counter() -> void:
	_player.global_position = _shop.to_global(Vector3(0, 0.5, -0.4))
	_camera.look_at(_shop.get_node("Shopkeeper").get_hit_center(), Vector3.UP)
	_player.reset_physics_interpolation()
	await _frames()


func _test_world() -> void:
	root.get_node("Wallet").set_total(0)
	change_scene_to_file("res://scenes/rooms/map_world.tscn")
	await scene_changed
	_bind_world()
	await _frames()
	_check(not _room.has_node("HUD/Hint") and not _room.has_node("HUD/ShopMessage"), "legacy bottom labels removed to prevent overlap")
	_check(_ui.get_displayed_source() == &"guidance", "world starts with operation guidance")
	for stock in _shop._shelves:
		await _at_stock(stock)
		var product: ShopItemData = stock.item_data
		_check(_ui.get_displayed_source() == &"shop_description", "looking at " + product.display_name + " selects description")
		_check(_ui.get_displayed_text().contains(product.description), "actual resource description displayed for " + product.display_name)
		_check(_ui.get_displayed_text().contains("%d 金币" % _shop.get_product_price(product)), "current price displayed for " + product.display_name)
		# 新商店的对面也有货架；看向空处，明确验证离开所有商品焦点。
		_camera.rotation.x = deg_to_rad(80)
		await _frames()
		_check(_ui.get_displayed_source() == &"guidance", "looking away clears " + product.display_name + " description")
	var stock: Node3D = _shop.shelf
	await _at_stock(stock)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 5, 0.2)
	shape.shape = box
	wall.add_child(shape)
	_room.add_child(wall)
	wall.global_position = (_camera.global_position + stock.get_node("ItemSpawn").global_position) * 0.5
	await _frames()
	_check(_shop.get_context_text().is_empty() and _ui.get_displayed_source() == &"guidance", "world wall blocks product description")
	wall.queue_free()
	await _frames()
	_check(_ui.get_displayed_source() == &"shop_description", "description returns after blocker disappears")
	_check(_grabber.try_grab(), "real carrier grabs described product")
	_player.global_position = Vector3(0, 0.5, 7)
	_camera.rotation = Vector3.ZERO
	await _frames()
	_check(_ui.get_displayed_text().contains(stock.item_data.description), "held product retains description away from shop")
	await _at_counter()
	_grabber.drop()
	await _frames()
	_check(_shop.counter.item != null and _ui.get_displayed_text().contains("商品已放到台面"), "real docking feedback overrides description")
	await _wait(3.3)
	var sword = _camera.get_node("WeaponRig/WeaponPivot/Mount")
	_check(sword.try_swing(), "real sword starts empty-wallet purchase attempt")
	await _wait(0.8)
	_check(_ui.get_displayed_source() == &"shop_feedback" and _ui.get_displayed_text().contains("金钱不足"), "failed real purchase gives bottom feedback")
	var flow = root.get_node("GameFlow")
	flow.pause_game()
	await _wait(3.5)
	_check(not _ui.visible and _shop.get_status_message().contains("金钱不足"), "pause preserves real shop feedback lifetime")
	flow.resume_game()
	await _frames()
	_check(_ui.visible and _ui.get_displayed_text().contains("金钱不足"), "resume restores shop feedback")
	await _wait(3.3)
	_check(_ui.get_displayed_source() != &"shop_feedback", "shop feedback expires and restores current context")
	root.get_node("Wallet").set_total(5)
	_check(sword.try_swing(), "real sword retries funded purchase")
	await _wait(0.5)
	_check(_shop.busy and _ui.get_displayed_text().contains("请稍候"), "busy transaction feedback remains visible")
	await _wait(2.8)
	_check(sword.oiled and root.get_node("Wallet").total == 0, "actual purchase delivers and spends once")
	_check(_ui.get_displayed_text().contains("强化完成"), "successful real purchase uses bottom feedback")
	await _at_stock(stock)
	await _wait(3.3)
	_check(_ui.get_displayed_source() == &"shop_description" and _ui.get_displayed_text().contains("已启用"), "feedback restores updated purchased product context")
	await _check_layout()
	await _capture("purchased_product")


func _test_lifecycle() -> void:
	var old_id := _ui.get_instance_id()
	change_scene_to_file("res://scenes/debug/mechanism_lab.tscn")
	await scene_changed
	await _frames()
	_ui = current_scene.get_node("HUD/BottomText")
	_check(not is_instance_id_valid(old_id), "scene exit destroys old messages and display")
	_check(_ui.get_displayed_source() == &"guidance" and _ui.get_displayed_text().contains("E 解锁投掷"), "mechanism map reuses component with own guidance")
	_ui.set_message(&"story", "后续剧情可通过共用入口显示对白", 30)
	await _frames()
	_check(_ui.get_displayed_source() == &"story", "future dialogue can supply its own source")
	_check(not current_scene.get_node("Player/Camera3D/Grabber").interaction_locked, "text alone does not lock gameplay input")
	_ui.clear_message(&"story")
	_check(_ui.get_displayed_source() == &"guidance", "clearing custom source restores level guidance")
	change_scene_to_file("res://scenes/rooms/element_test_room.tscn")
	await scene_changed
	_bind_world()
	await _frames()
	await _at_stock(_shop.shelf)
	_check(_ui.get_displayed_text().contains("剑身涂油"), "shop test room reuses product descriptions")
	root.get_node("GameFlow").return_to_main_menu()
	await scene_changed
	await _frames()
	_check(get_nodes_in_group("bottom_text_ui").is_empty(), "main menu has no residual gameplay text")
