class_name ShopCounter
extends StaticBody3D

signal item_placed(item: ShopItem)
signal item_removed
var locked := false
var item: ShopItem


func _ready() -> void:
	add_to_group("shop_counters")


func can_place_from(camera: Camera3D) -> bool:
	if locked or item != null:
		return false
	var at: Vector3 = $Socket.global_position
	var offset := at - camera.global_position
	if offset.length() > 3.2 or offset.normalized().dot(-camera.global_basis.z) < 0.35:
		return false
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, at, CollisionLayers.WORLD)
	var carrier: Node = camera.get_parent()
	if carrier is PhysicsBody3D:
		ray.exclude = [carrier.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.get("collider") == self


func place_item(candidate: ShopItem) -> bool:
	if locked or item != null or candidate == null or candidate.locked:
		return false
	item = candidate
	item.dock(self, $Socket)
	item.tree_exiting.connect(_on_item_exiting)
	item_placed.emit(item)
	EventBus.forge_item_placed.emit(item)
	return true


func remove_item(candidate: ShopItem) -> void:
	if item != candidate or locked:
		return
	_disconnect_item()
	item = null
	item_removed.emit()


func consume_item() -> void:
	var consumed := item
	_disconnect_item()
	item = null
	if is_instance_valid(consumed):
		consumed.queue_free()
	item_removed.emit()


func _disconnect_item() -> void:
	if is_instance_valid(item) and item.tree_exiting.is_connected(_on_item_exiting):
		item.tree_exiting.disconnect(_on_item_exiting)


func _on_item_exiting() -> void:
	item = null
	item_removed.emit()
