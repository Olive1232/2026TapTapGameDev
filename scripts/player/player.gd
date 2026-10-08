extends CharacterBody3D

## 第一人称玩家控制器。
##
## 缩进规范：本工程统一使用 **Tab**（对齐 Godot 官方风格）。
##
## 搬运契约（见 docs/开发拆分.md 第 4 节）：
##   外部通过 set_carry_weight() / set_carry_speed_multiplier() 影响移速，
##   玩家自身不关心"扛的是尸体还是锻造物品"。

## 鼠标灵敏度。
@export var mouse_sensitivity: float = 0.1
## 基础移动速度（米/秒）。
@export var move_speed: float = 5.0
## 跳跃初速度。
@export var jump_velocity: float = 4.5

## 当前负重（任何 >0 的值都会按比例减速）。由搬运系统写入。
var carry_weight: float = 0.0
## 负重减速系数：移速倍率 = 1 / (1 + weight * 本值)。
var carry_slow_factor: float = 0.35

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## 本帧累积的鼠标位移量，由 _unhandled_input 收集、_process 消费。
##
## 为什么不在 _unhandled_input 里直接转视角：
## 工程启用了 physics/common/physics_interpolation（让位移在 60Hz 物理帧之间平滑），
## 但视角旋转是按渲染帧来的。如果旋转也写在输入回调里，两条路径的时间基准不一致，
## 画面会抖动。所以统一在渲染帧 _process 里按累积量应用一次。
var _look_delta: Vector2 = Vector2.ZERO

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()


func _apply_settings() -> void:
	mouse_sensitivity = GameSettings.mouse_sensitivity
	reset_look_input()


func reset_look_input() -> void:
	_look_delta = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	# 只累积，不直接转（见 _look_delta 的说明）。
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# 屏幕原始位移不随窗口 / UI 缩放，避免切全屏后灵敏度变化。
		_look_delta += event.screen_relative


func _process(_delta: float) -> void:
	if _look_delta == Vector2.ZERO:
		return
	# 渲染帧应用视角：与物理插值后的位移保持同一时间基准。
	rotate_y(deg_to_rad(-_look_delta.x * mouse_sensitivity))
	camera.rotate_x(deg_to_rad(-_look_delta.y * mouse_sensitivity))
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	_look_delta = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("Left", "Right", "Up", "Down")

	# 把输入方向转换为基于当前视角的3D方向
	# 注意：get_vector 返回 Vector2，所以纵向分量是 .y（不能用 .z）
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var speed := get_current_move_speed()
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()


# ---- 搬运契约（第 4 节冻结的公开 API）------------------------------------

## 设置负重。扛起尸体时传入尸体重量，放下时传 0。
func set_carry_weight(weight: float) -> void:
	carry_weight = maxf(0.0, weight)


## 当前是否有负重（一次只扛 1 件，所以是布尔语义）。
func is_carrying() -> bool:
	return carry_weight > 0.0


## 覆盖负重减速系数（不同搬运物可以有不同的拖慢程度）。
func set_carry_slow_factor(factor: float) -> void:
	carry_slow_factor = maxf(0.0, factor)


## 计入负重后的实际移动速度。
func get_current_move_speed() -> float:
	return move_speed / (1.0 + carry_weight * carry_slow_factor)
