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
@export var move_speed: float = 10.0
## 自动跨过的小台阶高度（米）；仅在贴地行走时生效。
@export_range(0.0, 2.0, 0.01) var max_step_height := 0.4
## 藤蔓攀爬速度（米/秒），负重减速同样生效。
@export_range(0.5, 8.0, 0.1) var climb_speed := 3.0
@export_range(0.6, 1.5, 0.05) var climb_reach := 1.0

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
var _climb_surface: Node3D
var _climb_normal := Vector3.ZERO
var _release_climb := false
var _climb_wait_release := false
var _climb_cooldown := 0.0
var _mount_remaining := 0.0
var _mount_direction := Vector3.ZERO
var _bottom_text: BottomText

@onready var camera: Camera3D = $Camera3D
@onready var _footsteps: AudioStreamPlayer = $Footsteps
@onready var _body_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# 下台阶时保持贴地；上台阶另做完整角色碰撞体的空间检查。
	floor_snap_length = maxf(floor_snap_length, max_step_height + 0.05)
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()


func _apply_settings() -> void:
	mouse_sensitivity = GameSettings.mouse_sensitivity
	reset_look_input()


func reset_look_input() -> void:
	_look_delta = Vector2.ZERO


func reset_gameplay_input() -> void:
	reset_look_input()
	_release_climb = false


func _unhandled_input(event: InputEvent) -> void:
	if is_climbing() and event.is_action_pressed("ClimbRelease") and not event.is_echo():
		_release_climb = true
		get_viewport().set_input_as_handled()
		return
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
	_climb_cooldown = maxf(0.0, _climb_cooldown - delta)
	if not Input.is_action_pressed("Up"):
		_climb_wait_release = false
	if _process_climbing(delta):
		_update_climb_hint()
		return
	_update_climb_hint()
	if not is_on_floor() or velocity.y > 0.0:
		velocity.y -= gravity * delta

	var input_dir := Input.get_vector("Left", "Right", "Up", "Down")

	# 把输入方向转换为基于当前视角的3D方向
	# 注意：get_vector 返回 Vector2，所以纵向分量是 .y（不能用 .z）
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var speed := get_current_move_speed()
	if _mount_remaining > 0.0:
		_mount_remaining = maxf(0.0, _mount_remaining - delta)
		direction = _mount_direction
		speed = climb_speed / (1.0 + carry_weight * carry_slow_factor)
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	var was_grounded := is_on_floor() and velocity.y <= 0.0
	if was_grounded:
		_try_step_up(Vector3(velocity.x, 0.0, velocity.z) * delta)
	move_and_slide()
	if was_grounded and velocity.y <= 0.0:
		apply_floor_snap()
	_update_footsteps(direction != Vector3.ZERO)


func _try_step_up(motion: Vector3) -> void:
	if max_step_height <= 0.0 or motion.length_squared() < 0.000001:
		return
	var collision := KinematicCollision3D.new()
	if not test_move(global_transform, motion, collision, safe_margin, false, 4):
		return
	var floor_dot := cos(floor_max_angle)
	var blocked_by_step := false
	for index in collision.get_collision_count():
		var normal := collision.get_normal(index)
		if collision.get_collider(index) is StaticBody3D and normal.dot(up_direction) < floor_dot and normal.dot(motion.normalized()) < -0.01:
			blocked_by_step = true
			break
	if not blocked_by_step:
		return
	# 先检查头顶，再从抬高的位置向前扫掠，最后确认脚下确有可站立的台面。
	# 整个过程使用真实角色形状，避免中心射线漏掉门框、斜角或低矮天花板。
	var clearance := safe_margin * 2.0
	var lift := max_step_height + clearance
	if test_move(global_transform, up_direction * lift, collision, safe_margin):
		lift = collision.get_travel().dot(up_direction) - clearance
	if lift <= clearance:
		return
	var raised := global_transform
	raised.origin += up_direction * lift
	if test_move(raised, motion, null, safe_margin):
		return
	raised.origin += motion
	if not test_move(raised, -up_direction * (lift + clearance), collision, safe_margin):
		return
	if not collision.get_collider() is StaticBody3D or collision.get_normal().dot(up_direction) < floor_dot:
		return
	var rise := lift + collision.get_travel().dot(up_direction)
	if rise <= clearance or rise > max_step_height + clearance:
		return
	# 只抬高到实际台面，水平位移仍由本帧原有速度完成，不额外向前推送。
	move_and_collide(up_direction * rise, false, safe_margin)


func is_climbing() -> bool:
	return is_instance_valid(_climb_surface) and not _climb_surface.is_queued_for_deletion()


func get_climb_prompt() -> String:
	return "藤蔓攀爬：W 向上 · S 向下 · A / D 横移 · E 松开" if is_climbing() else ""


func _feet_position() -> Vector3:
	var box := _body_shape.shape as BoxShape3D
	return _body_shape.to_global(Vector3(0, -box.size.y * 0.5, 0))


func _probe_vine(from: Vector3, direction: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(from, from + direction * climb_reach, CollisionLayers.WORLD)
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var surface := hit.get("collider") as Node3D
	if surface == null or not surface.has_method("can_climb") or not surface.can_climb():
		return {}
	if absf(hit.normal.y) > 0.4:
		return {}
	return hit


func _stop_climbing(wait_for_release: bool = false) -> void:
	_climb_surface = null
	_release_climb = false
	_climb_wait_release = wait_for_release
	_climb_cooldown = 0.25
	if velocity.y <= climb_speed + 0.01:
		velocity.y = minf(velocity.y, 0.0)


func _process_climbing(delta: float) -> bool:
	var input_dir := Input.get_vector("Left", "Right", "Up", "Down")
	if _climb_surface != null and (not is_climbing() or not _climb_surface.can_climb()):
		_stop_climbing()
	if is_climbing():
		if velocity.y > climb_speed + 0.01:
			_stop_climbing()
			return false
		if _release_climb or (input_dir.y > 0.0 and is_on_floor()):
			_stop_climbing(true)
			return false
		# 脚高于顶端后沿表面方向跨上去，始终通过碰撞移动，不传送穿过障碍。
		if input_dir.y < 0.0 and _feet_position().y >= _climb_surface.get_climb_top().y + safe_margin * 2.0:
			_mount_direction = -_climb_normal
			_mount_remaining = 0.3
			_stop_climbing()
			return false
		var support := _probe_vine(_feet_position() + Vector3.UP * 1.1, -_climb_normal)
		if support.is_empty():
			support = _probe_vine(_feet_position() - Vector3.UP * 0.15, -_climb_normal)
		if support.is_empty():
			_stop_climbing()
			return false
		_climb_surface = support.collider
		_climb_normal = support.normal
	elif input_dir.y < 0.0 and not _climb_wait_release and _climb_cooldown <= 0.0 and velocity.y <= climb_speed:
		var facing := -global_basis.z
		facing.y = 0.0
		var hit := _probe_vine(_feet_position() + Vector3.UP * 1.1, facing.normalized())
		if not hit.is_empty():
			_climb_surface = hit.collider
			_climb_normal = hit.normal
	if not is_climbing():
		return false
	var up := Vector3.UP.slide(_climb_normal).normalized()
	var right := up.cross(_climb_normal).normalized()
	var movement := right * input_dir.x - up * input_dir.y
	var speed := climb_speed / (1.0 + carry_weight * carry_slow_factor)
	velocity = movement * speed - _climb_normal * 0.6
	move_and_slide()
	_footsteps.stop()
	return true


func _update_climb_hint() -> void:
	if not is_instance_valid(_bottom_text):
		_bottom_text = get_tree().get_first_node_in_group("bottom_text_ui") as BottomText
	if _bottom_text != null:
		_bottom_text.set_message(&"climbing", get_climb_prompt(), BottomText.DESCRIPTION + 1)


func _update_footsteps(has_move_input: bool) -> void:
	# 用碰撞后的实际速度判断，顶墙、原地转向和腾空时不播放脚步。
	var actual_velocity := get_real_velocity()
	var horizontal_speed := Vector2(actual_velocity.x, actual_velocity.z).length()
	if not has_move_input or not is_on_floor() or horizontal_speed < 0.15:
		_footsteps.stop()
		return
	# 负重降速时脚步节奏也放慢。
	_footsteps.pitch_scale = clampf(horizontal_speed / maxf(move_speed, 0.01), 0.65, 1.15)
	if not _footsteps.playing:
		_footsteps.play()


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
