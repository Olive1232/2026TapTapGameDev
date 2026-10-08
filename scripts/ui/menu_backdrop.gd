extends Control

## 用原生绘制做聚光灯与洞的剪影，随窗口缩放，不依赖贴图。
func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b141a"))
	var center := Vector2(size.x * 0.73, size.y * 0.75)
	var source := Vector2(size.x * 0.73, -size.y * 0.1)
	var radius := size.x * 0.19
	for i in range(12, 0, -1):
		var spread := radius * (0.75 + float(i) * 0.035)
		var beam := PackedVector2Array([source, center + Vector2(-spread, 0), center + Vector2(spread, 0)])
		draw_colored_polygon(beam, Color(0.68, 0.64, 0.4, 0.012))
	for i in range(1, 8):
		var y := center.y + float(i) * size.y * 0.045
		draw_line(Vector2(size.x * 0.4, y), Vector2(size.x, y), Color(0.5, 0.56, 0.52, 0.05), 1.0)
	var ellipse := Transform2D(0.0, Vector2(1.0, 0.22), 0.0, center)
	draw_set_transform_matrix(ellipse)
	draw_circle(Vector2.ZERO, radius, Color(0.15, 0.17, 0.15, 1))
	draw_circle(Vector2.ZERO, radius * 0.86, Color(0.018, 0.026, 0.03, 1))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 96, Color(0.58, 0.55, 0.36, 0.75), 2.0, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_circle(Vector2(source.x, size.y * 0.07), 3.0, Color(0.98, 0.87, 0.6, 1))
