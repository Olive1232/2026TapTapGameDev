class_name Grabber
extends Node3D

## 右键抓取 / 拖拽搬运。
##
## 挂在 Player/Camera3D/Grabber 下。它自己**不持有物体**——
## 被抓的东西（尸体等）由自己负责软跟随，本节点只负责：
##   1. 射线探测准星指向的可抓取物
##   2. 右键按下 → 抓住 / 松开
##   3. 告诉玩家"现在扛着多重"，让玩家自己算移速
##
## 一次只能抓一个（策划需求：主角一次只能抓取一个物品）。

## 抓取射线长度（米）。比剑的 range 略长，让"伸手能碰到"感觉合理。
##
## 注意：**"抓不中"的主因通常不是射程**，而是准星精度——见 grab_padding。
## 加大这个值只能让你够到更远的东西，不能让"瞄歪一点"也能抓到。
@export var grab_range: float = 3.2
## 抓取判定的**容错半径**（米）——把零宽度的射线换成有粗细的球体扫掠。
##
## 为什么必须要有：尸体是 0.5×0.15×0.7 的**薄片**躺在地上。纯射线要求
## 准星正中它，而 0.5 米宽在 2 米外只有约 ±4° 的水平容错、垂直方向更窄
## （薄片只有 0.15 米高），实际玩起来就是"经常抓不上"。
##
## 0.35 大致相当于玩家自身体宽的一半：足够宽容，又不会隔着老远吸到东西。
## 想更宽松可以调到 0.5；调到 0 就退回"纯射线"行为。
@export var grab_padding: float = 0.35
## 持有点相对相机的偏移（相机空间）。**x 为正 = 画面右侧。**
##
## 2026-10-03 手部调整：从正中（x=0）改到**右手边**。
##
## x 取 0.7（而不是 0.5）是算过的：尸体盒子长 0.7 米，挂在右前方时
## 它的**内侧边缘不能盖住屏幕中心**，否则扛着尸体就瞄不了准星。
## 设持有点在 (0.7, -0.35, -1.2)，则尸体内侧边缘相对视线约 24°——
## 远离中心，同时外缘仍在 80° FOV 的视野内（不会甩出画面）。
##
## 注意它只管"东西显示在哪"，**不管探测方向**——后者永远从屏幕中心发出，
## 见 ray_from_screen_center。
@export var hold_offset: Vector3 = Vector3(0.7, -0.35, -1.2)
## 探测射线是否从**屏幕中心**发出（而不是从持有点）。
##
## 为什么必须是 true（Q19 决策）：持有点移到右手后，如果射线也跟着走，
## 射线就不再从准星出发——2 米处会偏离准星约 14°，玩家会"看着准星却抓不到"，
## 正是之前抱怨的那类手感问题。所以这里把两件事解耦：
##   **探测方向** = 屏幕中心（看到哪就抓到哪）
##   **物品显示位置** = 右手边
##
## 设为 false 可退回"射线跟着手走"的旧行为，方便对比手感。
@export var ray_from_screen_center: bool = true

## 球体扫掠用的形状，**只建一次**并复用——每帧新建 Resource 会产生垃圾。
var _pad_shape: SphereShape3D = null

## 探测射线的起点（世界坐标）。由持有点或相机决定，见 _update_ray_origin()。
var _ray_origin: Vector3 = Vector3.ZERO

var _current: Node3D = null
var _hold_point: Node3D = null
var _player: Node3D = null
var _camera: Camera3D = null
var interaction_locked := false


func _ready() -> void:
	_hold_point = get_node_or_null("HoldPoint") as Node3D
	if _hold_point == null:
		_hold_point = Node3D.new()
		_hold_point.name = "HoldPoint"
		add_child(_hold_point)
	_hold_point.position = hold_offset
	# 找到玩家（沿父链向上找带搬运接口的节点）。
	_player = _find_carrier()
	if _player == null:
		push_warning("Grabber：没找到带 set_carry_weight 的玩家节点，负重伤速不会生效。")
	# 找到相机：探测射线从屏幕中心发出时要用它。
	# Grabber 通常就是 Camera3D 的子节点，找不到就退回用自身位置。
	_camera = _find_camera()
	if ray_from_screen_center and _camera == null:
		push_warning("Grabber：没找到 Camera3D，探测射线将退回从持有点发出（会偏离准星）。")
	_update_ray_origin()


## 沿父链向上找第一个 Camera3D。
func _find_camera() -> Camera3D:
	var node: Node = get_parent()
	while node != null:
		if node is Camera3D:
			return node as Camera3D
		node = node.get_parent()
	return null


## 刷新探测射线的起点。
##
## 注意**不能**用 project_ray_origin()：它返回的是**近裁剪面**上的点
## （Godot 里约在相机前方 0.05 米），而当前关卡里玩家自带的碰撞盒
## 正好覆盖那个位置，探测会打到玩家自己身上。摄像机在相机空间的原点
## 才是真正的"眼睛"，从那里出发既准确又不会自撞。
func _update_ray_origin() -> void:
	if ray_from_screen_center and _camera != null:
		_ray_origin = _camera.global_position
	elif _hold_point != null:
		_ray_origin = _hold_point.global_position
	else:
		_ray_origin = global_position


func _find_carrier() -> Node3D:
	var node: Node = get_parent()
	while node != null:
		if node is Node3D and node.has_method("set_carry_weight"):
			return node as Node3D
		node = node.get_parent()
	return null


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("Grab"):
		if is_holding():
			drop()
		else:
			try_grab()


func _on_held_tree_exiting() -> void:
	# 在引用被引擎清为 null 之前处理献祭 / 销毁，负重不能残留。
	_clear_current()


# ---- 抓 / 放 -------------------------------------------------------------

## 尝试抓起准星指向的东西。返回是否成功。
func try_grab() -> bool:
	if interaction_locked or is_holding():
		return false
	var target := _raycast_target()
	if target == null:
		return false
	if not target.has_method("grab"):
		return false
	# 有些可抓物会自己声明"现在不能被拿"（例如已被别人拿着）。
	if target.has_method("can_be_grabbed") and not target.can_be_grabbed():
		return false
	_current = target
	_current.tree_exiting.connect(_on_held_tree_exiting)
	target.grab(_player, _hold_point)
	_apply_weight()
	return true


## 放下当前持有的东西。throw_forward = true 会向前抛。
func drop(throw_forward: bool = false) -> void:
	if interaction_locked or _current == null:
		return
	if not throw_forward and _current.has_method("try_place_on_counter") and _current.try_place_on_counter(_camera):
		_clear_current()
		return
	if _current.has_method("release"):
		_current.release(throw_forward)
	_clear_current()


func is_holding() -> bool:
	return _current != null and is_instance_valid(_current)


## 当前持有的物体（可能为 null）。
func get_held() -> Node3D:
	return _current if is_holding() else null


func _clear_current() -> void:
	if is_instance_valid(_current) and _current.tree_exiting.is_connected(_on_held_tree_exiting):
		_current.tree_exiting.disconnect(_on_held_tree_exiting)
	_current = null
	_apply_weight()


## 把负重告诉玩家。玩家自己决定移速怎么降——Grabber 不碰移速逻辑。
func _apply_weight() -> void:
	if _player == null:
		return
	var w := 0.0
	if is_holding() and "weight" in _current:
		w = float(_current.weight)
	_player.set_carry_weight(w)


## 从相机前方做一次**带容错的**探测，返回第一个可抓取的目标。
##
## 为什么用"沿射线等距采样球体"而不是球体扫掠：
## **`PhysicsDirectSpaceState3D.intersect_shape()` 不接受 `motion`，它不扫掠**
## ——只在给定位置查一次。实测证据：把球放在相机位置、给 3.2 米的 motion，
## 命中数为 0；而把同一个球直接放在目标位置就命中 1。所以想覆盖整条射线，
## 只能自己在沿途多点采样。
##
## 采样间距取得比半径小（0.32 < 0.35），保证相邻两个球**必然重叠**，
## 物体不可能从采样之间漏掉。
##
## 采样点从近到远推进；每个候选物还会做地形遮挡检查，避免隔墙抓取。
func _raycast_target() -> Node3D:
	# 起点与方向**分开取**：起点可以是屏幕中心或持有点，方向永远沿视线。
	# 手部调整（2026-10-03）后这两者不再重合，见 ray_from_screen_center。
	_update_ray_origin()
	var dir := -global_transform.basis.z
	if ray_from_screen_center and _camera != null:
		# 用相机自身的朝向，保证射线精确穿过屏幕正中的准星。
		dir = -_camera.global_transform.basis.z
	var from := _ray_origin
	var to := from + dir.normalized() * grab_range

	# 只探测 PICKUP 层（尸体、钱币、锻造物品），不误抓地形、玩家和怪物。
	# collide_with_areas=false：钱币等是 Area3D，但那些靠碰到玩家自动收取，
	# 不需要右键抓。
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = CollisionLayers.PICKUP
	query.collide_with_areas = false
	query.collide_with_bodies = true
	# 球心沿射线推进，所以 transform 每步都要重设；形状只建一次复用。
	if _pad_shape == null:
		_pad_shape = SphereShape3D.new()
	query.shape = _pad_shape

	var space := get_world_3d().direct_space_state

	# padding 为 0 时退回纯射线（单次查询，最省）。
	if grab_padding <= 0.0:
		var ray := PhysicsRayQueryParameters3D.create(from, to)
		ray.collision_mask = CollisionLayers.PICKUP
		ray.collide_with_areas = false
		ray.collide_with_bodies = true
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			return null
		var target := hit.get("collider") as Node3D
		return target if _clear_grab_path(target) else null

	_pad_shape.radius = grab_padding
	# 采样点数 = ceil(射程 / 间距) + 1；间距 = 半径 × 0.92，保证相邻球重叠。
	var spacing := grab_padding * 0.92
	var steps := int(ceil(grab_range / spacing))
	steps = clampi(steps, 1, 16)
	for i in range(steps + 1):
		var at := from.lerp(to, float(i) / float(steps))
		query.transform = Transform3D(Basis.IDENTITY, at)
		var hits: Array = space.intersect_shape(query, 4)
		for h in hits:
			var collider: Variant = (h as Dictionary).get("collider")
			if collider is Node3D and _clear_grab_path(collider):
				return collider as Node3D
	return null


## 房间墙体 / 未烧完的藤蔓遮挡搬运，不能隔墙抓尸体。
func _clear_grab_path(target: Node3D) -> bool:
	if target == null:
		return false
	var ray := PhysicsRayQueryParameters3D.create(_ray_origin, target.global_position, CollisionLayers.WORLD)
	if _player is PhysicsBody3D:
		ray.exclude = [_player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
