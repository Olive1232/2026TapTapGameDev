extends Control


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	%NewGameButton.pressed.connect(func(): _show_result(GameFlow.start_new_game()))
	%LoadGameButton.pressed.connect(func(): _show_result(GameFlow.load_game()))
	%SettingsButton.pressed.connect(_open_settings)
	%AboutButton.pressed.connect(_open_about)
	%QuitButton.pressed.connect(GameFlow.quit_game)
	%AboutBackButton.pressed.connect(_close_about)
	%Settings.closed.connect(_close_settings)
	%LoadGameButton.disabled = not SaveGame.has_save()
	%SaveInfo.text = "已有金币存档" if SaveGame.has_save() else "暂无存档 · 新建游戏开始旅程"
	%NewGameButton.grab_focus()


func _show_result(result: Dictionary) -> void:
	if not result.ok:
		%SaveInfo.text = result.message


func _open_settings() -> void:
	%Menu.hide()
	%Settings.open()


func _close_settings() -> void:
	%Menu.show()
	%SettingsButton.grab_focus()


func _open_about() -> void:
	%Menu.hide()
	%About.show()
	%AboutBackButton.grab_focus()


func _close_about() -> void:
	%About.hide()
	%Menu.show()
	%AboutButton.grab_focus()


func handle_escape() -> void:
	if %Settings.visible:
		%Settings.close()
	elif %About.visible:
		_close_about()
