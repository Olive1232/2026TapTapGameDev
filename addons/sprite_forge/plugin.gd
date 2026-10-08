@tool
extends EditorPlugin

var dock

func _enter_tree():
	dock = preload("res://addons/sprite_forge/slicer_ui.tscn").instantiate()
	add_control_to_bottom_panel(dock, "SpriteForge")

func _exit_tree():
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
