extends CanvasLayer


func _ready() -> void:
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
	%SaveStatus.text = "金币仅在手动存档时保存"
	%SaveButton.grab_focus()


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
