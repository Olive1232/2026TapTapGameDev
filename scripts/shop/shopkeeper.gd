extends StaticBody3D

signal struck(source: Node3D)
var locked := false


## 店长可被实际剑命中，不参与怪物血量 / 死亡 / 刷新计数。
func take_hit(info: HitInfo) -> void:
	if locked:
		return
	EventBus.shopkeeper_struck.emit(info.source)
	struck.emit(info.source)


func get_hit_center() -> Vector3:
	return global_position + Vector3(0, 1.25, 0)
