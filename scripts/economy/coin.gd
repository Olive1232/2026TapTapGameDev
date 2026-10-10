class_name Coin
extends CharacterBody3D

## 钱币：喷出 → 与实际地形碰撞并停在地面 → 玩家接触拾取 → 回池。
## 只与 WORLD 碰撞，不阻挡玩家，也不接受抓取或洞的吸力。
enum Phase { EJECT, GROUND, COLLECTED }

var value: int = 1
const GOLDEN_COLOR := Color(1, 0.72, 0.08, 1)
var is_golden := false
var _phase: Phase = Phase.COLLECTED
var _age := 0.0
var _eject_min_time := 0.28
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var pickup: Area3D = $Pickup


func _ready() -> void:
	collision_layer = 0
	collision_mask = CollisionLayers.WORLD
	set_physics_process(false)


func launch(p_value: int, p_color: Color, p_velocity: Vector3, p_eject_min_time: float = 0.28, p_is_golden: bool = false) -> void:
	value = p_value
	is_golden = p_is_golden
	velocity = p_velocity
	_age = 0.0
	_eject_min_time = maxf(0.0, p_eject_min_time)
	_phase = Phase.EJECT
	visible = true
	pickup.set_deferred("monitoring", true)
	reset_physics_interpolation()
	set_physics_process(true)
	_apply_color(GOLDEN_COLOR if is_golden else p_color)


func _apply_color(color: Color) -> void:
	var mesh := $Mesh as MeshInstance3D
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh.material_override = mat
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2 if is_golden else 0.5
	mat.metallic = 0.8 if is_golden else 0.0
	mat.roughness = 0.25 if is_golden else 1.0


func _physics_process(delta: float) -> void:
	if _phase == Phase.COLLECTED:
		return
	_age += delta
	# 即使已经落地也沿地形保持接触，不能使用统一的世界高度贴地。
	velocity.y -= _gravity * delta
	move_and_slide()
	if is_on_floor():
		_phase = Phase.GROUND
		velocity = Vector3.ZERO
	else:
		_phase = Phase.EJECT
	if _phase != Phase.GROUND or _age < _eject_min_time:
		return
	# 落地前已经与玩家重叠时也能收取；不依赖只触发一次的 body_entered。
	for body in pickup.get_overlapping_bodies():
		if body is CharacterBody3D and body.has_method("set_carry_weight"):
			var ray := PhysicsRayQueryParameters3D.create(global_position, body.global_position + Vector3.UP * 0.5, CollisionLayers.WORLD)
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			_collect()
			break


func _collect() -> void:
	if _phase != Phase.GROUND:
		return
	_phase = Phase.COLLECTED
	Wallet.add(value)
	EventBus.coin_collected.emit(value)
	CoinPool.release(self)


func reset_for_pool() -> void:
	_phase = Phase.COLLECTED
	is_golden = false
	velocity = Vector3.ZERO
	_age = 0.0
	visible = false
	pickup.set_deferred("monitoring", false)
	set_physics_process(false)


func is_ejecting() -> bool:
	return _phase == Phase.EJECT


func is_grounded() -> bool:
	return _phase == Phase.GROUND


func is_collected() -> bool:
	return _phase == Phase.COLLECTED
