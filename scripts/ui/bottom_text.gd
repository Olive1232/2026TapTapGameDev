class_name BottomText
extends Control

## 场景内共用的文字入口；每个来源只更新 / 清除自己的消息。
## duration = 0 持续显示，正数按游戏时间到期；暂停不消耗剩余时间。
const GUIDANCE := 0
const DESCRIPTION := 10
const FEEDBACK := 20
signal dialogue_line_changed(source: StringName, index: int, text: String)
signal dialogue_finished(source: StringName)
@export var maximum_width := 1120.0
@export var side_margin := 32.0
@export var bottom_margin := 28.0
var _messages: Dictionary = {}
var _sequence := 0
var _displayed_source: StringName = &""
var _dialogue: Dictionary = {}
var _dialogue_queue: Array[Dictionary] = []

@onready var _box: VBoxContainer = $TextBox
@onready var _label: Label = $TextBox/Text
@onready var _speaker: Label = $TextBox/Speaker
@onready var _continue_hint: Label = $TextBox/Continue


func _ready() -> void:
	resized.connect(_update_layout)
	_label.minimum_size_changed.connect(_fit_height)
	_box.minimum_size_changed.connect(_fit_height)
	_update_layout()
	_refresh()


func set_message(source: StringName, text: String, priority: int = GUIDANCE, duration: float = 0.0) -> void:
	if text.strip_edges().is_empty():
		clear_message(source)
		return
	# 关卡每帧更新持续提示时，不重新排版或改变同优先级排序。
	var previous: Dictionary = _messages.get(source, {})
	if duration <= 0.0 and previous.get("text") == text and previous.get("priority") == priority and previous.get("remaining") == -1.0:
		return
	_sequence += 1
	_messages[source] = {"text": text, "priority": priority, "order": _sequence, "remaining": duration if duration > 0.0 else -1.0}
	_refresh()


func clear_message(source: StringName) -> void:
	if _messages.erase(source):
		_refresh()


func clear_all() -> void:
	_messages.clear()
	_dialogue.clear()
	_dialogue_queue.clear()
	_refresh()


## 剧情对白始终优先于商品说明；新对白排队，不打断正在阅读的一句。
func play_dialogue(source: StringName, speaker: String, lines: PackedStringArray) -> bool:
	if source == &"" or lines.is_empty() or _dialogue.get("source") == source:
		return false
	for queued in _dialogue_queue:
		if queued.source == source:
			return false
	var valid_lines := PackedStringArray()
	for line in lines:
		if not line.strip_edges().is_empty():
			valid_lines.append(line)
	if valid_lines.is_empty():
		return false
	_dialogue_queue.append({"source": source, "speaker": speaker, "lines": valid_lines, "index": 0})
	if _dialogue.is_empty():
		_start_next_dialogue()
	return true


func is_dialogue_active() -> bool:
	return not _dialogue.is_empty()


func get_dialogue_source() -> StringName:
	return _dialogue.get("source", &"")


func advance_dialogue() -> void:
	if not is_dialogue_active() or get_tree().paused:
		return
	_dialogue.index += 1
	if _dialogue.index >= _dialogue.lines.size():
		var finished: StringName = _dialogue.source
		_dialogue = {}
		_start_next_dialogue()
		dialogue_finished.emit(finished)
	else:
		_show_dialogue_line()


func _start_next_dialogue() -> void:
	if not _dialogue_queue.is_empty():
		_dialogue = _dialogue_queue.pop_front()
		_show_dialogue_line()
	else:
		_refresh()


func _show_dialogue_line() -> void:
	_refresh()
	dialogue_line_changed.emit(_dialogue.source, _dialogue.index, _dialogue.lines[_dialogue.index])


func _input(event: InputEvent) -> void:
	if not is_dialogue_active() or get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# 在 _unhandled_input 挥剑之前消费，包括结束对白的最后一次点击。
		get_viewport().set_input_as_handled()
		advance_dialogue()


func get_displayed_source() -> StringName:
	return _displayed_source


func get_displayed_text() -> String:
	return _label.text if is_instance_valid(_label) else ""


func _process(delta: float) -> void:
	if get_tree().paused:
		hide()
		return
	var expired: Array[StringName] = []
	for source in _messages:
		if _messages[source].remaining < 0.0:
			continue
		_messages[source].remaining -= delta
		if _messages[source].remaining <= 0.0:
			expired.append(source)
	for source in expired:
		_messages.erase(source)
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	var selected: Dictionary = {}
	_displayed_source = &""
	for source in _messages:
		var candidate: Dictionary = _messages[source]
		if selected.is_empty() or candidate.priority > selected.priority or (candidate.priority == selected.priority and candidate.order > selected.order):
			selected = candidate
			_displayed_source = source
	var text: String = selected.get("text", "")
	if is_dialogue_active():
		_displayed_source = _dialogue.source
		text = _dialogue.lines[_dialogue.index]
		_speaker.text = _dialogue.speaker
		_continue_hint.text = "左键 · %s  %d / %d" % ["结束" if _dialogue.index == _dialogue.lines.size() - 1 else "继续", _dialogue.index + 1, _dialogue.lines.size()]
	_speaker.visible = is_dialogue_active()
	_continue_hint.visible = is_dialogue_active()
	if _label.text != text:
		_label.text = text
	visible = not text.is_empty() and not get_tree().paused
	queue_redraw()


func _update_layout() -> void:
	if not is_instance_valid(_box):
		return
	var width := floorf(maxf(1.0, minf(maximum_width, size.x - side_margin * 2.0)))
	_box.offset_left = -floorf(width / 2.0)
	_box.offset_right = ceilf(width / 2.0)
	_box.offset_top = -bottom_margin
	_box.offset_bottom = -bottom_margin
	_fit_height.call_deferred()


func _fit_height() -> void:
	# 文本变短时也收回高度，保持最后一行距底边一致。
	_box.offset_top = -bottom_margin - _box.get_combined_minimum_size().y
	_box.offset_bottom = -bottom_margin
	queue_redraw()


func get_panel_rect() -> Rect2:
	return Rect2(_box.position - Vector2(20, 14), _box.size + Vector2(40, 28))


func _draw() -> void:
	if not is_instance_valid(_box):
		return
	var panel := get_panel_rect()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.045, 0.94)
	style.border_color = Color(0.65, 0.64, 0.54, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	draw_style_box(style, panel)
	if is_dialogue_active():
		draw_line(panel.position + Vector2(2, 2), panel.position + Vector2(2, panel.size.y - 2), Color(0.96, 0.76, 0.4), 4)
