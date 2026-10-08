class_name TargetDummy
extends StaticBody3D

## 假人靶子：能掉血、闪白、被击退、复活。纯测试用。
##
## 它故意只实现 `take_hit(HitInfo)` 这一个约定方法——
## 将来的真敌人在接口上长得一样，剑不需要区分"砍的是靶子还是生物"。
## 这是 sword.gd 里用 has_method("take_hit") 做鸭子类型判断的原因。

signal died

## 最大血量。设为 0 或负数表示打不死（用来测连击手感）。
@export var max_health: float = 50.0
## 被击退后回位的速度（越大回得越快）。
@export var return_speed: float = 2.5
## 受击后多久开始回位（秒）。
@export var return_delay: float = 0.6
## 击退位移上限（米），避免被打飞太远。
@export var max_knockback_offset: float = 1.8

var health: float = 0.0
var _home_position: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _since_hit: float = 999.0
## 本实例独立的材质，闪白时不会影响其他靶子。
var _material: StandardMaterial3D
var _rng := RandomNumberGenerator.new()

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	health = max_health
	_home_position = position
	_rng.randomize()
	var source := _mesh.get_active_material(0) if _mesh else null
	if source is StandardMaterial3D:
		_material = (source as StandardMaterial3D).duplicate()
		_mesh.material_override = _material


func _physics_process(delta: float) -> void:
	_since_hit += delta
	# 击退位移用指数衰减，然后慢慢回到原位。
	if _velocity.length_squared() > 0.0001:
		position += _velocity * delta
		_velocity = _velocity.lerp(Vector3.ZERO, clampf(delta * 10.0, 0.0, 1.0))
		var offset := position - _home_position
		if offset.length() > max_knockback_offset:
			position = _home_position + offset.normalized() * max_knockback_offset
	if _since_hit > return_delay:
		position = position.lerp(_home_position, clampf(delta * return_speed, 0.0, 1.0))


## 剑的伤害入口。参数类型是 HitInfo，但用无类型声明以便外部鸭子类型调用。
func take_hit(info: HitInfo) -> void:
	if max_health > 0.0:
		health -= info.damage
	_flash()
	# 0.3 是刻意压低的系数：靶子是给人试手感的，被砍一下飞太远反而看不清命中。
	_velocity += info.knockback * 0.3
	_since_hit = 0.0
	if max_health > 0.0 and health <= 0.0:
		_die()


## 供剑计算命中点用。
func get_hit_center() -> Vector3:
	return global_position + Vector3(0.0, 0.8, 0.0)


func get_health_ratio() -> float:
	if max_health <= 0.0:
		return 1.0
	return clampf(health / max_health, 0.0, 1.0)


func _flash() -> void:
	if _material == null:
		return
	var base := _material.albedo_color
	_material.albedo_color = Color(1, 1, 1)
	_material.emission_enabled = true
	_material.emission = Color(1, 1, 1)
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color", base, 0.12)
	tween.tween_callback(func() -> void: _material.emission_enabled = false)


func _die() -> void:
	died.emit()
	# 不销毁，而是原地复活——测试时能连续砍。
	respawn()


func respawn() -> void:
	health = max_health
	# 回到"出生点"，而不是"当前位置"。
	# 早期版本这里写的是 _home_position = position，会导致被打飞后
	# 把新位置当成家，于是永远回不到原位。
	position = _home_position
	_velocity = Vector3.ZERO
	_since_hit = 999.0
