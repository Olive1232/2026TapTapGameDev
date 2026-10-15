class_name WorldSound
extends RefCounted

## 让销毁反馈挂在场景下，发声实体消失后仍能播完整个音效。
static func play_one_shot(source: Node3D, stream: AudioStream, volume_db: float = -12.0) -> AudioStreamPlayer3D:
	var host: Node = source.get_tree().current_scene
	if host == null:
		host = source.get_tree().root
	var audio := AudioStreamPlayer3D.new()
	audio.name = "WorldSound"
	audio.top_level = true
	audio.process_mode = Node.PROCESS_MODE_PAUSABLE
	audio.stream = stream
	audio.bus = &"SFX"
	audio.volume_db = volume_db
	audio.unit_size = 3.0
	audio.max_distance = 16.0
	host.add_child(audio)
	audio.global_position = source.global_position
	audio.finished.connect(audio.queue_free)
	audio.play()
	return audio
