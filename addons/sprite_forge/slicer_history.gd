@tool
extends RefCounted

signal history_changed(can_undo: bool, can_redo: bool)

var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
const MAX_STACK_SIZE: int = 35

func clear() -> void:
	undo_stack.clear()
	redo_stack.clear()
	history_changed.emit(false, false)

func can_undo() -> bool:
	return not undo_stack.is_empty()

func can_redo() -> bool:
	return not redo_stack.is_empty()

func push_state(state: Dictionary) -> void:
	undo_stack.append(state)
	redo_stack.clear()
	if undo_stack.size() > MAX_STACK_SIZE:
		undo_stack.remove_at(0)
	history_changed.emit(can_undo(), can_redo())

func undo(apply_callback: Callable) -> void:
	if undo_stack.is_empty():
		return
	var state: Dictionary = undo_stack.pop_back()
	var current_state: Dictionary = apply_callback.call(state)
	if not current_state.is_empty():
		redo_stack.append(current_state)
	history_changed.emit(can_undo(), can_redo())

func redo(apply_callback: Callable) -> void:
	if redo_stack.is_empty():
		return
	var state: Dictionary = redo_stack.pop_back()
	var current_state: Dictionary = apply_callback.call(state)
	if not current_state.is_empty():
		undo_stack.append(current_state)
	history_changed.emit(can_undo(), can_redo())
