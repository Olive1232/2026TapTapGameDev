extends CanvasLayer


func _ready() -> void:
	%ResumeButton.pressed.connect(GameFlow.resume_game)
	%SaveButton.pressed.connect(func(): %SaveStatus.text = SaveGame.save_game().message)
	%MainMenuButton.pressed.connect(func():
		var result := GameFlow.return_to_main_menu()
		if not result.ok:
			%SaveStatus.text = result.message)
	%SettingsButton.pressed.connect(_open_settings)
	%QuitButton.pressed.connect(GameFlow.quit_game)
	%Settings.closed.connect(_close_settings)
	close()


func open() -> void:
	%Root.show()
	%Card.show()
	%Settings.hide()
	%SaveStatus.text = "手动保存金币、已购升级与关卡进度；载入后回到出生点。"
	%ResumeButton.grab_focus()


func close() -> void:
	%Root.hide()


func _open_settings() -> void:
	%Card.hide()
	%Settings.open()


func _close_settings() -> void:
	%Card.show()
	%SettingsButton.grab_focus()


## 返回 true 表示仅退出子页面，应继续保持暂停。
func handle_escape() -> bool:
	if %Settings.visible:
		%Settings.close()
		return true
	return false
