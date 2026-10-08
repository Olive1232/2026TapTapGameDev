extends "res://scripts/rooms/element_test_room.gd"

## FBX 世界复用既有房间流程，只补模型世界的边界恢复。
## 出生、玩法位置与各模块参数在 map_world.tscn 编辑。
func _physics_process(_delta: float) -> void:
	if _player.global_position.y < -28.0:
		_player.global_transform = $ExitPoint.global_transform
		_player.velocity = Vector3.ZERO
		_player.reset_physics_interpolation()
