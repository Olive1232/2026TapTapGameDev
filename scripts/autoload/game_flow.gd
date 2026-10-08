extends Node

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const GAME_SCENE := "res://scenes/rooms/map_world.tscn"
const SHOP_LAB := "res://scenes/rooms/element_test_room.tscn"
const DEBUG_SCENE := "res://scenes/debug/test_arena.tscn"
const ELEMENT_LAB := "res://scenes/debug/element_lab.tscn"
var _pause_menu: CanvasLayer
var _transitioning := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu = load("res://scenes/ui/pause_menu.tscn").instantiate()
	add_child(_pause_menu)


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
	return scene != null and scene.scene_file_path in [GAME_SCENE, DEBUG_SCENE, ELEMENT_LAB, SHOP_LAB]


func start_new_game() -> Dictionary:
	return _enter_game(0)


func load_game() -> Dictionary:
	var result := SaveGame.read_save()
	if not result.ok:
		return result
	return _enter_game(result.coins)


func _enter_game(coins: int) -> Dictionary:
	if _transitioning:
		return {"ok": false, "message": "正在进入游戏..."}
	var previous := Wallet.total
	Wallet.set_total(coins)
	var result := _change_scene(GAME_SCENE)
	if not result.ok:
		Wallet.set_total(previous)
	return result


func return_to_main_menu() -> Dictionary:
	return _change_scene(MAIN_MENU)


func _change_scene(path: String) -> Dictionary:
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
	_finish_transition()
	return {"ok": true, "message": ""}


func _finish_transition() -> void:
	await get_tree().scene_changed
	_transitioning = false


func pause_game() -> void:
	if not is_in_game() or _transitioning:
		return
	_reset_player_look()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_pause_menu.open()


func resume_game() -> void:
	_reset_player_look()
	_pause_menu.close()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _reset_player_look() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		var player := scene.get_node_or_null("Player")
		if player != null and player.has_method("reset_look_input"):
			player.reset_look_input()


func quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()
