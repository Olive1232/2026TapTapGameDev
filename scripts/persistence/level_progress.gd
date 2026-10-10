extends RefCounted

## 只记录已经永久开通的机关；编号不依赖节点名、路径或地图坐标。
const GROUP := &"persistent_gates"
const UNMATCHED_META := &"unmatched_gate_progress"
const MAX_GATES := 32
const MAX_ID_LENGTH := 64


static func is_valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_ID_LENGTH:
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_.-":
			return false
	return true


static func is_valid_progress(value: Variant) -> bool:
	if not value is Dictionary or value.size() > MAX_GATES:
		return false
	for id in value:
		if not id is String or not is_valid_id(id) or not value[id] is bool or not value[id]:
			return false
	return true


static func _find_gates(scene: Node) -> Dictionary:
	var gates := {}
	if scene == null:
		return {"ok": true, "gates": gates}
	for node in scene.get_tree().get_nodes_in_group(GROUP):
		if not scene.is_ancestor_of(node) or node.is_queued_for_deletion():
			continue
		var id := str(node.get_persistence_id())
		if id.is_empty():
			continue
		if not is_valid_id(id) or gates.has(id):
			return {"ok": false, "message": "机关存档编号无效或重复，未覆盖上次存档。"}
		gates[id] = node
	return {"ok": true, "gates": gates}


static func collect(scene: Node) -> Dictionary:
	var found := _find_gates(scene)
	if not found.ok:
		return found
	var progress: Dictionary = scene.get_meta(UNMATCHED_META, {}).duplicate() if scene != null else {}
	for id in found.gates:
		if found.gates[id].is_persistently_open():
			progress[id] = true
		else:
			progress.erase(id)
	if not is_valid_progress(progress):
		return {"ok": false, "message": "关卡进度超出存档范围，未覆盖上次存档。"}
	return {"ok": true, "opened_gates": progress}


static func restore(scene: Node, progress: Dictionary) -> bool:
	if scene == null or not is_valid_progress(progress):
		return false
	var found := _find_gates(scene)
	if not found.ok:
		return false
	# 先检查全部目标，再恢复，避免只恢复一部分。
	for id in progress:
		if found.gates.has(id) and not found.gates[id].can_restore_persistent_open():
			return false
	var unmatched := progress.duplicate()
	for id in progress:
		if found.gates.has(id):
			found.gates[id].restore_persistent_open()
			unmatched.erase(id)
	# 新地图暂未放置的机关保留原记录，下次手动存档不会丢失。
	scene.set_meta(UNMATCHED_META, unmatched)
	return true
