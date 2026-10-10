extends Node3D

## 将整组藤蔓视为一扇门；全部烧毁后才成为永久关卡进度。
signal opened

@export var persistence_id: StringName
var _parts: Array[Node] = []
var _opened := false
var _restoring := false
var _leaving := false


func _ready() -> void:
	add_to_group(&"persistent_gates")
	tree_exiting.connect(func(): _leaving = true)
	for child in get_children():
		if child is FlammableProp:
			_parts.append(child)
			child.tree_exiting.connect(_on_part_removed.bind(child))
	_opened = _parts.is_empty()


func _on_part_removed(part: Node) -> void:
	_parts.erase(part)
	if _parts.is_empty() and not _opened:
		_opened = true
		if not _restoring and not _leaving and not is_queued_for_deletion():
			opened.emit()


func get_persistence_id() -> StringName:
	return persistence_id


func is_persistently_open() -> bool:
	return _opened


func can_restore_persistent_open() -> bool:
	return true


func restore_persistent_open() -> void:
	_restoring = true
	for part in _parts.duplicate():
		# 直接移除碰撞与外观，不重放燃烧、破坏或奖励事件。
		remove_child(part)
		part.queue_free()
	_opened = true
	_restoring = false
