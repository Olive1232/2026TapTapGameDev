extends SceneTree

## 检查真实 UI 使用的字体与项目现有中文字符，不依赖设备安装的字体。
var _passed := 0
var _failed := 0
var _font: FontVariation
var _characters := {}
var _chinese := RegEx.new()


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("UI FONT REGRESSION FAILED: " + message)


func _collect_characters(path: String) -> void:
	var directory := DirAccess.open(path)
	for name in directory.get_files():
		if name.get_extension() not in ["gd", "tscn", "tres"]:
			continue
		for result in _chinese.search_all(FileAccess.get_file_as_string(path.path_join(name))):
			_characters[result.get_string().unicode_at(0)] = true
	for name in directory.get_directories():
		_collect_characters(path.path_join(name))


func _missing(font: Font, text: String) -> String:
	var missing := ""
	for index in text.length():
		var code := text.unicode_at(index)
		if code > 32 and not font.has_char(code) and not missing.contains(text[index]):
			missing += text[index]
	return missing


func _check_text_nodes(node: Node) -> void:
	var font: Font
	var text := ""
	if node is Label or node is Button:
		font = node.get_theme_font("font")
		text = node.text
		if node is OptionButton:
			for index in node.item_count:
				text += node.get_item_text(index)
	elif node is Label3D:
		font = node.font if node.font != null else ThemeDB.fallback_font
		text = node.text
	if not text.is_empty():
		_check(font == _font, "bundled font used by " + str(node.get_path()))
		if font != null:
			var missing := _missing(font, text)
			_check(missing.is_empty(), "no missing glyphs in %s: %s" % [node.get_path(), missing])
	for child in node.get_children():
		_check_text_nodes(child)


func _run() -> void:
	await process_frame
	_font = load("res://resources/ui/game_font.tres")
	_check(_font != null and _font.base_font is FontFile, "bundled font loads")
	_check(not _font.base_font.allow_system_fallback, "glyph coverage is independent of system fonts")
	var server := TextServerManager.get_primary_interface()
	var weight_axis := server.name_to_tag("wght")
	for rid in _font.get_rids():
		_check(server.font_get_variation_coordinates(rid).get(weight_axis) == 400.0, "rendered font resolves Regular weight")
	_check(ThemeDB.fallback_font == _font, "unthemed HUD and 3D labels inherit bundled font")
	_chinese.compile("[㐀-鿿　-〿！-～×·…—]")
	for branch in ["scripts", "scenes", "resources"]:
		_collect_characters("res://" + branch)
	var missing := ""
	for code in _characters:
		if not _font.has_char(code):
			missing += String.chr(code)
	_check(_characters.size() > 100 and missing.is_empty(), "project Chinese glyph coverage: " + missing)
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	menu.get_node("%Settings").open()
	await process_frame
	_check_text_nodes(menu)
	var flow = root.get_node("GameFlow")
	flow.start_new_game()
	await scene_changed
	await process_frame
	await process_frame
	_check_text_nodes(current_scene)
	flow.pause_game()
	_check_text_nodes(flow)
	print("UI FONT REGRESSION RESULT: passed=%d failed=%d covered_characters=%d" % [_passed, _failed, _characters.size()])
	quit(0 if _failed == 0 else 1)
