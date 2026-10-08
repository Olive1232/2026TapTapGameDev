class_name ElementComponent
extends Area3D

## 火元素接触与燃烧。挂在实体下，用 Shape 指定接触范围。
## 火把配置 fire，可燃物配置 flammable；burning 是运行时状态。
signal ignited
signal extinguished
signal burned_down

const FLAME_SCENE := preload("res://scenes/elements/flame_effect.tscn")

@export var tags: PackedStringArray = PackedStringArray(["flammable"])
## 0 表示不按时间熄灭，由宿主决定（例如剑的挥砍次数）。
@export_range(0.0, 60.0, 0.1) var burn_duration: float = 4.0
@export_range(0.05, 5.0, 0.05) var spread_interval: float = 0.35
@export_range(0.1, 3.0, 0.1) var flame_scale: float = 1.0

var burning := false
var burn_remaining := 0.0
var _spread_remaining := 0.0
var _flame: Node3D


func _ready() -> void:
	collision_layer = CollisionLayers.ELEMENT
	collision_mask = CollisionLayers.ELEMENT
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)
	_flame = FLAME_SCENE.instantiate() as Node3D
	_flame.scale = Vector3.ONE * flame_scale
	add_child(_flame)
	_update_flame()


func is_fire_source() -> bool:
	return tags.has("fire") or burning


func has_tag(tag: String) -> bool:
	return burning if tag == "burning" else tags.has(tag)


func _on_area_entered(area: Area3D) -> void:
	# 首次接触即时传火；周期轮询还会覆盖接触后才涂油的情况。
	if is_fire_source() and area is ElementComponent:
		area.ignite_from(self, global_position)


func ignite() -> bool:
	if burning or not tags.has("flammable") or is_queued_for_deletion():
		return false
	burning = true
	burn_remaining = burn_duration
	_spread_remaining = maxf(spread_interval, 0.05)
	_update_flame()
	ignited.emit()
	return true


## 射线挡住传火，排除接触双方自己的实体碰撞。
func ignite_from(source: Node3D, at: Vector3) -> bool:
	if not _clear_path(source, at):
		return false
	return ignite()


func extinguish() -> void:
	if not burning:
		return
	burning = false
	burn_remaining = 0.0
	_update_flame()
	extinguished.emit()


func _physics_process(delta: float) -> void:
	if not is_fire_source():
		return
	# 先传播再销毁，让燃烧的最后一个物理帧仍能传火。
	_spread_remaining -= delta
	if _spread_remaining <= 0.0:
		_spread_remaining = maxf(spread_interval, 0.05)
		for area in get_overlapping_areas():
			if area is ElementComponent and area != self and not area.is_queued_for_deletion():
				area.ignite_from(self, global_position)
	if burning and burn_duration > 0.0:
		burn_remaining -= delta
		if burn_remaining <= 0.0:
			if tags.has("indestructible"):
				extinguish()
			else:
				burned_down.emit()
				get_parent().queue_free()


func _clear_path(source: Node3D, from: Vector3) -> bool:
	var to := global_position
	if from.is_equal_approx(to):
		return true
	var ray := PhysicsRayQueryParameters3D.create(from, to, CollisionLayers.WORLD)
	var excluded: Array[RID] = []
	for node in [source, self]:
		var ancestor: Node = node
		while ancestor != null:
			if ancestor is PhysicsBody3D:
				excluded.append(ancestor.get_rid())
				break
			ancestor = ancestor.get_parent()
	ray.exclude = excluded
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _update_flame() -> void:
	if _flame != null:
		_flame.visible = is_fire_source()
