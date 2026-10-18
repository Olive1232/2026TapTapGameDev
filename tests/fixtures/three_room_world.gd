extends "res://scripts/rooms/element_test_room.gd"

## 历史三房间地图夹具：复用现行组件，保留对应测试的地形与边界。
## 不注册为生产入口。
func _physics_process(_delta: float) -> void:
	if _player.global_position.y < -28.0:
		_player.global_transform = $ExitPoint.global_transform
		_player.velocity = Vector3.ZERO
		_player.reset_physics_interpolation()
