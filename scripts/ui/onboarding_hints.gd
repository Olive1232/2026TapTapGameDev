extends Control

## 仅由新游戏启用；阶段随手动存档保存，旧存档默认已完成。
const CONTROLS := "controls"
const PICKUP := "pickup"
const COMPLETE := "complete"
const FONT := preload("res://resources/ui/game_font.tres")
const INK := Color(0.95, 0.95, 0.88)
const ACCENT := Color(1.0, 0.82, 0.42)
const PANEL_SIZE := Vector2(496, 156)
@export_range(0.5, 3.0, 0.1) var blink_period := 1.4
var _stage := COMPLETE
var _elapsed := 0.0
var _pulse := 1.0


func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.corpse_grabbed.connect(_on_corpse_grabbed)
	resized.connect(queue_redraw)
	_refresh_visibility()


func restore_stage(stage: String) -> void:
	_stage = stage if stage in [CONTROLS, PICKUP, COMPLETE] else COMPLETE
	_elapsed = 0.0
	_pulse = 1.0
	_refresh_visibility()
	queue_redraw()


func get_stage() -> String:
	return _stage


func _process(delta: float) -> void:
	_refresh_visibility()
	if not visible:
		return
	_elapsed = fmod(_elapsed + delta, blink_period)
	# 平滑明暗闪烁，最暗时仍能辨认按键；不使用 Tween，暂停不推进。
	_pulse = 0.35 + 0.65 * (0.5 + 0.5 * cos(TAU * _elapsed / blink_period))
	queue_redraw()


func _refresh_visibility() -> void:
	visible = _stage != COMPLETE and not get_tree().paused


func _belongs_to_world(node: Node) -> bool:
	var scene := get_tree().current_scene
	return is_instance_valid(node) and scene != null and scene.is_ancestor_of(self) and scene.is_ancestor_of(node)


func _on_enemy_killed(enemy: Node3D, by: Node3D) -> void:
	if _stage != CONTROLS or get_tree().paused:
		return
	if not enemy is Monster or enemy.data == null or enemy.data.id != &"rat":
		return
	if _belongs_to_world(enemy) and _belongs_to_world(by) and by.has_method("set_carry_weight"):
		restore_stage(PICKUP)


func _on_corpse_grabbed(corpse: Node3D) -> void:
	if _stage != PICKUP or get_tree().paused:
		return
	if corpse is Corpse and corpse.get_monster_id() == &"rat" and corpse.is_held and _belongs_to_world(corpse):
		restore_stage(COMPLETE)


## 位于底部文字上方，不覆盖准星、任务或金币；最小窗口仍完整显示。
func get_panel_rect() -> Rect2:
	var width := PANEL_SIZE.x if _stage == CONTROLS else 216.0
	return Rect2(Vector2(floorf((size.x - width) * 0.5), size.y - 270.0), Vector2(width, PANEL_SIZE.y))


func _draw() -> void:
	if _stage == COMPLETE:
		return
	var panel := get_panel_rect()
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.04, 0.045, 0.88)
	background.border_color = Color(0.72, 0.75, 0.65, 0.28)
	background.set_border_width_all(1)
	background.set_corner_radius_all(10)
	draw_style_box(background, panel)
	var origin := panel.position
	if _stage == CONTROLS:
		_draw_wasd(origin + Vector2(38, 17))
		_draw_key(Rect2(origin + Vector2(204, 48), Vector2(100, 34)), "空格", 19)
		_draw_mouse(origin + Vector2(388, 16), false)
		_draw_caption("移动", origin + Vector2(92, 136))
		_draw_caption("跳跃", origin + Vector2(254, 136))
		_draw_caption("攻击", origin + Vector2(414, 136))
	else:
		_draw_mouse(origin + Vector2(82, 16), true)
		_draw_caption("捡起老鼠", origin + Vector2(108, 136))


func _draw_wasd(origin: Vector2) -> void:
	var key_size := Vector2(32, 32)
	_draw_key(Rect2(origin + Vector2(36, 0), key_size), "W")
	for index in 3:
		_draw_key(Rect2(origin + Vector2(index * 36, 36), key_size), ["A", "S", "D"][index])


func _draw_key(rect: Rect2, text: String, font_size: int = 20) -> void:
	var key := StyleBoxFlat.new()
	key.bg_color = Color(0.12, 0.15, 0.15, _pulse)
	key.border_color = Color(INK, _pulse)
	key.set_border_width_all(2)
	key.border_width_bottom = 4
	key.set_corner_radius_all(4)
	draw_style_box(key, rect)
	var text_size := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := rect.position + Vector2((rect.size.x - text_size.x) * 0.5, (rect.size.y - FONT.get_height(font_size)) * 0.5 + FONT.get_ascent(font_size) - 1)
	draw_string(FONT, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(INK, _pulse))


func _draw_mouse(origin: Vector2, right_button: bool) -> void:
	var body := StyleBoxFlat.new()
	body.bg_color = Color(0.12, 0.15, 0.15, _pulse)
	body.border_color = Color(INK, _pulse)
	body.set_border_width_all(2)
	body.set_corner_radius_all(22)
	draw_style_box(body, Rect2(origin, Vector2(52, 64)))
	var button := StyleBoxFlat.new()
	button.bg_color = Color(ACCENT, _pulse)
	button.corner_radius_top_left = 15 if not right_button else 2
	button.corner_radius_top_right = 15 if right_button else 2
	button.set_corner_radius(CORNER_BOTTOM_LEFT, 2)
	button.set_corner_radius(CORNER_BOTTOM_RIGHT, 2)
	draw_style_box(button, Rect2(origin + Vector2(28 if right_button else 5, 5), Vector2(19, 27)))
	draw_line(origin + Vector2(26, 2), origin + Vector2(26, 35), Color(INK, _pulse), 2, true)
	draw_line(origin + Vector2(2, 35), origin + Vector2(50, 35), Color(INK, _pulse), 2, true)
	_draw_caption("右键" if right_button else "左键", origin + Vector2(26, 86), 16, Color(INK, _pulse))


func _draw_caption(text: String, center_baseline: Vector2, font_size: int = 20, color: Color = INK) -> void:
	var text_width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(FONT, center_baseline - Vector2(text_width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
