class_name BottomText
extends Control

## 场景内共用的文字入口；每个来源只更新 / 清除自己的消息。
## duration = 0 持续显示，正数按游戏时间到期；暂停不消耗剩余时间。
const GUIDANCE := 0
const DESCRIPTION := 10
const FEEDBACK := 20
@export var maximum_width := 1120.0
@export var side_margin := 32.0
@export var bottom_margin := 28.0
var _messages: Dictionary = {}
var _sequence := 0
var _displayed_source: StringName = &""

@onready var _box: VBoxContainer = $TextBox
@onready var _label: Label = $TextBox/Text


func _ready() -> void:
	resized.connect(_update_layout)
	_label.minimum_size_changed.connect(_fit_height)
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
	_refresh()


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
	if _label.text != text:
		_label.text = text
	visible = not text.is_empty() and not get_tree().paused


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
