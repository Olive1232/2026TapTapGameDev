extends Control

## 屏幕中心准星。
##
## 为什么用 _draw() 而不是贴一张 TextureRect：
## 现阶段项目里全是占位白模，没有准星贴图；用矢量画出来的准星
## ①不依赖美术资源 ②任意分辨率下都清晰 ③颜色粗细随时能调。
##
## 双色描边（先粗画深色、再细画浅色）是为了让准星在**明暗背景上都可见**
## —— 场景是暗色调 + 火光，纯白准星在火光上会糊掉，纯黑在地面阴影里会糊掉。

## 准星的每条线臂长（像素，从中心向外）。
@export var arm_length: float = 11.0
## 中心留空的半径（像素）。>0 时空出中心，准星不会挡住瞄准点。
@export var gap: float = 4.0
## 线宽（像素）。
@export var thickness: float = 2.0
## 中心小点半径（像素）。0 表示不画点。
@export var dot_radius: float = 1.0
## 描边宽度（像素）——加在线宽之外，形成深色轮廓。
@export var outline: float = 3.0
## 准星颜色。
@export var color: Color = Color(1.0, 0.97, 0.9, 0.95)
## 描边颜色。
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.75)


func _ready() -> void:
	# 准星不该吃掉任何输入。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 覆盖整个屏幕，中心即屏幕中心。
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 窗口尺寸变化时重画，保证始终居中。
	get_viewport().size_changed.connect(queue_redraw)


func _draw() -> void:
	var c := size * 0.5

	# 四条臂：上下左右。先画描边（更粗），再画本体。
	for pass_index in 2:
		var is_outline := pass_index == 0
		var w := thickness + (outline if is_outline else 0.0)
		var col := outline_color if is_outline else color
		var inner := maxf(gap, 0.0)
		var outer := inner + arm_length
		# 水平两段
		draw_line(Vector2(c.x - outer, c.y), Vector2(c.x - inner, c.y), col, w)
		draw_line(Vector2(c.x + inner, c.y), Vector2(c.x + outer, c.y), col, w)
		# 垂直两段
		draw_line(Vector2(c.x, c.y - outer), Vector2(c.x, c.y - inner), col, w)
		draw_line(Vector2(c.x, c.y + inner), Vector2(c.x, c.y + outer), col, w)
		# 中心点
		if dot_radius > 0.0:
			var r := dot_radius + (outline * 0.5 if is_outline else 0.0)
			draw_circle(c, r, col)
