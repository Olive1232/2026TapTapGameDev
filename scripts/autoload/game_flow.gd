extends Node

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const GAME_SCENE := "res://scenes/rooms/main_world.tscn"
const SHOP_LAB := "res://scenes/rooms/element_test_room.tscn"
const DEBUG_SCENE := "res://scenes/debug/test_arena.tscn"
const ELEMENT_LAB := "res://scenes/debug/element_lab.tscn"
const THROW_LAB := "res://scenes/debug/throw_lab.tscn"
const MECHANISM_LAB := "res://scenes/debug/mechanism_lab.tscn"
## 存档使用固定入口代号，不执行存档文件提供的任意场景路径。
const SAVE_LEVELS := {"world": GAME_SCENE, "mechanism_lab": MECHANISM_LAB}
const LevelProgress := preload("res://scripts/persistence/level_progress.gd")
const DEBUG_COIN_AMOUNT := 1000
var _pause_menu: CanvasLayer
var _transitioning := false
var _debug_coin_hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu = load("res://scenes/ui/pause_menu.tscn").instantiate()
	add_child(_pause_menu)
	if OS.is_debug_build():
		var overlay := CanvasLayer.new()
		overlay.name = "DebugCoins"
		add_child(overlay)
		_debug_coin_hint = Label.new()
		_debug_coin_hint.name = "Hint"
		_debug_coin_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(_debug_coin_hint)
		_debug_coin_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_debug_coin_hint.offset_left = -300.0
		_debug_coin_hint.offset_right = -20.0
		_debug_coin_hint.offset_top = 56.0
		_debug_coin_hint.offset_bottom = 104.0
		_debug_coin_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_debug_coin_hint.add_theme_font_size_override("font_size", 16)
		_debug_coin_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.48))
		_debug_coin_hint.add_theme_color_override("font_outline_color", Color.BLACK)
		_debug_coin_hint.add_theme_constant_override("outline_size", 3)
		_debug_coin_hint.hide()
		EventBus.wallet_changed.connect(_update_debug_coin_hint)
		_update_debug_coin_hint(Wallet.total, 0)


func _process(_delta: float) -> void:
	if _debug_coin_hint != null:
		_debug_coin_hint.visible = is_in_game() and not get_tree().paused and not _transitioning


func _update_debug_coin_hint(total: int, _delta: int) -> void:
	_debug_coin_hint.text = "测试：[G] +%d 金币\n当前金币：%d" % [DEBUG_COIN_AMOUNT, total]


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or _transitioning or get_tree().paused or not is_in_game():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_G or event.keycode == KEY_G:
			Wallet.add(DEBUG_COIN_AMOUNT)
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _transitioning or not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if is_in_game():
		if get_tree().paused:
			if not _pause_menu.handle_escape():
				resume_game()
		else:
			pause_game()
	else:
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("handle_escape"):
			scene.handle_escape()


func is_in_game() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path in [GAME_SCENE, DEBUG_SCENE, ELEMENT_LAB, THROW_LAB, MECHANISM_LAB, SHOP_LAB]


func start_new_game() -> Dictionary:
	return _enter_game(0, {}, "world", {}, {}, "controls")


func load_game() -> Dictionary:
	var result := SaveGame.read_save()
	if not result.ok:
		return result
	return _enter_game(result.coins, result.upgrades, result.level, result.opened_gates, result.upgrade_levels, result.tutorial_stage, result.dialogue_progress)


func get_purchased_upgrades() -> Dictionary:
	var owner := _get_upgrade_owner(get_tree().current_scene)
	if owner != null:
		return owner.get_purchased_upgrades()
	return SaveGame.empty_upgrades()


func get_level_snapshot() -> Dictionary:
	var scene := get_tree().current_scene
	var level := "mechanism_lab" if scene != null and scene.scene_file_path == MECHANISM_LAB else "world"
	var result := LevelProgress.collect(scene)
	if result.ok:
		result["level"] = level
	return result


func get_purchased_upgrade_levels() -> Dictionary:
	var owner := _get_upgrade_owner(get_tree().current_scene)
	if owner != null:
		return owner.get_purchased_upgrade_levels()
	return SaveGame.empty_upgrade_levels()


func _get_upgrade_owner(scene: Node) -> Node:
	if scene == null:
		return null
	if scene.scene_file_path == GAME_SCENE:
		return scene
	if scene.scene_file_path == SHOP_LAB:
		return scene.get_node_or_null("ShopRoom")
	return null


func get_tutorial_stage() -> String:
	var scene := get_tree().current_scene
	var hints := scene.get_node_or_null("HUD/OnboardingHints") if scene != null else null
	return hints.get_stage() if hints != null else "complete"


func get_dialogue_progress() -> Dictionary:
	var scene := get_tree().current_scene
	var dialogue := scene.get_node_or_null("WorldDialogue") if scene != null else null
	return dialogue.get_progress() if dialogue != null else SaveGame.empty_dialogue_progress()


func _enter_game(coins: int, upgrades: Dictionary = {}, level: String = "world", opened_gates: Dictionary = {}, upgrade_levels: Dictionary = {}, tutorial_stage: String = "complete", dialogue_progress: Dictionary = {}) -> Dictionary:
	if _transitioning:
		return {"ok": false, "message": "正在进入游戏..."}
	var previous := Wallet.total
	Wallet.set_total(coins)
	var result := _change_scene(SAVE_LEVELS[level], upgrades, opened_gates, upgrade_levels, tutorial_stage, dialogue_progress)
	if not result.ok:
		Wallet.set_total(previous)
	return result


func return_to_main_menu() -> Dictionary:
	return _change_scene(MAIN_MENU)


## 开发重置只重建场景，保留本轮新手引导阶段，不读写磁盘存档。
func reset_current_game() -> Dictionary:
	if not is_in_game():
		return {"ok": false, "message": "当前不在游戏中。"}
	return _change_scene(get_tree().current_scene.scene_file_path, {}, {}, {}, get_tutorial_stage(), get_dialogue_progress())


func _change_scene(path: String, upgrades: Dictionary = {}, opened_gates: Dictionary = {}, upgrade_levels: Dictionary = {}, tutorial_stage: String = "complete", dialogue_progress: Dictionary = {}) -> Dictionary:
	if _transitioning:
		return {"ok": false, "message": "正在切换场景..."}
	_transitioning = true
	var was_paused := get_tree().paused
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_transitioning = false
		get_tree().paused = was_paused
		return {"ok": false, "message": "场景加载失败。"}
	get_tree().paused = false
	_pause_menu.close()
	# 场景离开时可能正在顿帧，避免把慢速状态带到主菜单或新游戏。
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_finish_transition(upgrades.duplicate(), opened_gates.duplicate(), upgrade_levels.duplicate(), tutorial_stage, dialogue_progress.duplicate())
	return {"ok": true, "message": ""}


func _finish_transition(upgrades: Dictionary, opened_gates: Dictionary, upgrade_levels: Dictionary, tutorial_stage: String, dialogue_progress: Dictionary) -> void:
	await get_tree().scene_changed
	var scene := get_tree().current_scene
	var hints := scene.get_node_or_null("HUD/OnboardingHints")
	if hints != null:
		hints.restore_stage(tutorial_stage)
	var dialogue := scene.get_node_or_null("WorldDialogue")
	if dialogue != null:
		dialogue.restore_progress(dialogue_progress)
	if not LevelProgress.restore(scene, opened_gates):
		push_error("无法恢复关卡进度，请检查机关的固定存档编号与配置。")
	if not upgrades.is_empty() or not upgrade_levels.is_empty():
		var owner := _get_upgrade_owner(scene)
		if (owner == null and (true in upgrades.values() or upgrade_levels.values().any(func(count): return count > 0))) or (owner != null and not owner.restore_purchased_upgrades(upgrades, upgrade_levels)):
			push_error("无法恢复已购升级，请检查当前场景的升级存档配置。")
	_transitioning = false


func pause_game() -> void:
	if not is_in_game() or _transitioning:
		return
	_reset_player_input()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_pause_menu.open()


func resume_game() -> void:
	_reset_player_input()
	_pause_menu.close()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _reset_player_input() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		var player := scene.get_node_or_null("Player")
		if player != null:
			if player.has_method("reset_gameplay_input"):
				player.reset_gameplay_input()
			elif player.has_method("reset_look_input"):
				player.reset_look_input()


func quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()
