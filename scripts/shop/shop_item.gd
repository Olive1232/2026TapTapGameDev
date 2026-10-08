class_name ShopItem
extends RigidBody3D

## 商品搬运接口与尸体一致，但不使用尸体的价值 / 超时逻辑。
signal returned_to_shelf(item: ShopItem)

@export var data: ShopItemData = preload("res://resources/shop/shop_item_oil.tres")
var is_held := false
var locked := false
var counter: Node3D
var weight: float:
	get:
		return data.weight if data != null else 0.0

var _holder: Node3D
var _hold_point: Node3D
var _home: Transform3D
var _home_height := 0.0


func _ready() -> void:
	collision_layer = CollisionLayers.PICKUP
	collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER
	freeze = true
	_home = global_transform
	_home_height = global_position.y
	var material := StandardMaterial3D.new()
	material.albedo_color = data.tint if data != null else Color.YELLOW
	material.metallic = 0.35
	$Mesh.material_override = material
	$Price.text = "%s · %d 金币\n右键拿起" % [data.display_name, data.price] if data != null else "商品未配置"
	$Price.hide()


func can_be_grabbed() -> bool:
	return not locked and not is_held and data != null and (counter == null or not counter.locked)


func grab(holder: Node3D, hold_point: Node3D) -> void:
	if not can_be_grabbed():
		return
	if is_instance_valid(counter):
		counter.remove_item(self)
	counter = null
	is_held = true
	_holder = holder
	_hold_point = hold_point
	freeze = false
	gravity_scale = 0.0
	collision_mask = CollisionLayers.WORLD
	sleeping = false
	$Price.hide()
	EventBus.forge_item_grabbed.emit(self)


func release(throw_forward: bool = false) -> void:
	if not is_held:
		return
	is_held = false
	freeze = false
	gravity_scale = 1.0
	collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER
	linear_velocity = -_hold_point.global_basis.z * (2.5 if throw_forward else 0.5) if is_instance_valid(_hold_point) else Vector3.ZERO
	_holder = null
	_hold_point = null
	$Price.show()


## 台前放下时自动吸附；同样遵守距离、朝向与墙体遮挡。
func try_place_on_counter(camera: Camera3D) -> bool:
	if not is_held or locked or camera == null:
		return false
	for candidate in get_tree().get_nodes_in_group("shop_counters"):
		if candidate.can_place_from(camera) and candidate.place_item(self):
			return true
	return false


func dock(at: Node3D, socket: Node3D) -> void:
	is_held = false
	_holder = null
	_hold_point = null
	counter = at
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = socket.global_transform
	reset_physics_interpolation()
	$Price.hide()


func return_home() -> void:
	returned_to_shelf.emit(self)
	if is_instance_valid(counter):
		counter.remove_item(self)
	counter = null
	is_held = false
	_holder = null
	_hold_point = null
	freeze = true
	gravity_scale = 1.0
	collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _home
	reset_physics_interpolation()
	$Price.hide()


func _physics_process(_delta: float) -> void:
	if locked:
		return
	# 洞 / 关卡外的商品退回货架，台面上的商品不会超时。
	if counter == null and global_position.y < _home_height - 1.6:
		return_home()
		return
	if not is_held or not is_instance_valid(_hold_point):
		return
	var offset := _hold_point.global_position - global_position
	linear_velocity = Vector3.ZERO if offset.length() < 0.12 else (offset * 30.0).limit_length(12.0)
