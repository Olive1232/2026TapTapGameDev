class_name Coin
extends Area3D

## 一枚钱币。
##
## 生命周期：喷出（抛物线）→ 吸附（飞向玩家）→ 被收起（回池）。
##
## 为什么不用 RigidBody3D：洞一次会喷出几十上百枚币，每个都挂刚体的话
## 物理开销和节点数都太浪费。这里手动算速度即可，配合对象池复用。
##
## 钱币是 Area3D 而非物理体——它不需要和任何东西发生物理碰撞。

enum Phase {
	EJECT,   ## 从洞里喷出，走抛物线
	SEEK,    ## 飞向玩家
	COLLECTED, ## 已收进钱包，等待回池
}

## 单枚价值。由洞在喷出时按品质设置。
var value: int = 1
## 喷出初速度。**它同时是 EJECT 阶段的权威速度**——洞会改它来做"弹回"，
## 所以不能只在 launch 时读一次就丢开，否则洞那边设的反弹速度不会生效。
var eject_velocity: Vector3 = Vector3.ZERO
## 吸附阶段的目标（玩家的胸口位置）。
var seek_target: Node3D = null
## 吸附加速度。
var seek_accel: float = 34.0
## 吸附最大速度。
var seek_max_speed: float = 22.0
## 吸附阻尼（每秒衰减比例）。这是"金币绕着玩家永远飞"的**唯一根治项**。
##
## 为什么光有加速度和限速不够：吸附阶段原本只加速、从不耗能，所以
## "绕着玩家做圆周运动"是这个系统的一个**守恒解**——实测确认，币以
## v=sqrt(a·r) 的精确圆轨道速度进场后，跑 20 秒仍在转圈，既不进也不出
## （慢速和顶速两种都试过，都不收敛）。
##
## 限速（_limit_seek_speed）只在速度超过上限时才生效，而环绕速度往往
## **低于**上限，所以那时系统一点耗散都没有。凡是"只加约束、不加耗散"
## 的写法都治不了它——这是结构性的。
##
## 所以这里持续抽走能量：速度每帧乘以 (1 - damping*delta)。
## 轨道半径因此单调缩小，币自然螺旋收进去。0.5 约合每秒衰减 39%，
## 收敛很快又看不出"急停"。
var seek_damping: float = 0.5
## **拾取判定半径**（米）：钱币离玩家胸口多近就算被收走。
##
## 这个值直接决定"拾取判定范围"的手感，是全项目唯一的拾取半径开关。
## 参数依据：钱币本身只有 0.2 米宽，玩家碰撞盒半径约 0.4 米。取 0.6 时
## 钱币几乎要贴到脸才消失，视觉上像是"穿过去了却没收走"，所以放大到
## 玩家身位之外一圈。可用区间约 1.2 ~ 2.0；再大就会隔着墙壁收币。
@export var collect_radius: float = 1.5

var _phase: Phase = Phase.EJECT
## EJECT 阶段的工作速度。每次 launch / 洞改 eject_velocity 后同步。
var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
## 抛射阶段的最短时长，之后才允许转入吸附。
var _eject_min_time: float = 0.28
var _seek_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0


## 由对象池/洞调用：重置状态并喷出。
func launch(p_value: int, p_color: Color, p_velocity: Vector3, p_eject_min_time: float = 0.28) -> void:
	value = p_value
	eject_velocity = p_velocity
	_eject_min_time = p_eject_min_time
	_phase = Phase.EJECT
	_velocity = p_velocity
	_seek_velocity = Vector3.ZERO
	_age = 0.0
	visible = true
	set_process(true)
	_apply_color(p_color)


func _apply_color(color: Color) -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh.material_override = mat
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.5


func _process(delta: float) -> void:
	match _phase:
		Phase.EJECT:
			_tick_eject(delta)
		Phase.SEEK:
			_tick_seek(delta)
		Phase.COLLECTED:
			pass


func _tick_eject(delta: float) -> void:
	_age += delta
	# 每帧从 eject_velocity 取一次：洞会在钱币掉回洞口时改它来把币弹回去，
	# 只读一次的话那个反弹就丢了（钱币会被自己的洞销毁）。
	_velocity = eject_velocity
	_velocity.y -= 9.8 * delta
	global_position += _velocity * delta
	# 落在地上就停住并原地打转（简化：直接贴地）。
	if global_position.y < 0.08:
		global_position.y = 0.08
		_velocity.y = 0.0
		_velocity.x = move_toward(_velocity.x, 0.0, 6.0 * delta)
		_velocity.z = move_toward(_velocity.z, 0.0, 6.0 * delta)
	# 把这一帧算完的速度写回 eject_velocity，让洞看到的是真实速度。
	eject_velocity = _velocity
	# 过了最短抛射时间就转入吸附。
	if _age >= _eject_min_time:
		_phase = Phase.SEEK


func _tick_seek(delta: float) -> void:
	if seek_target == null or not is_instance_valid(seek_target):
		# 没有目标就原地待着，等洞重新指派。
		return
	var to_target := seek_target.global_position - global_position

	# 1) 先算本帧的速度：加速 → 阻尼 → 距离限速。
	_seek_velocity += to_target.normalized() * seek_accel * delta
	# 阻尼必须在加速之后：否则会被加速度直接抵掉，起不到耗散作用。
	# 这一步是唯一能破坏"环绕守恒解"的机制，别删。
	_seek_velocity *= 1.0 - clampf(seek_damping * delta, 0.0, 1.0)
	_limit_seek_speed(to_target)

	# 2) 再拿"真正要走的那一步"做扫掠判定。
	#
	# 顺序很关键：早先版本先判定、后更新速度，于是判定用的是**上一帧**的
	# 速度，实际位移却用新速度——22 米/秒时单帧速度增量就有 2 米/秒，
	# 方向能偏出好几度。等于"检查的那条轨迹"和"真正走的那条轨迹"不是
	# 同一条，高速段会擦身而过却不收。必须先更新速度，再判定。
	var step := _seek_velocity * delta
	# 判定要在**移动前**做：否则单帧位移可能直接跨过整个判定圈，
	# 钱币会在判定圈边缘反复进出，看起来像在玩家身上蹭来蹭去。
	if _will_reach_target(step):
		_collect()
		return

	# 3) 判定没命中才真的移动。
	global_position += step


## 按距离收紧吸附速度：越靠近玩家，允许的速度越低。
##
## 这是"金币绕着玩家永远飞"的根治办法。原因是加速度不够转弯：
## 半径 r 处要以速度 v 绕行需要向心加速度 v²/r，而 22 米/秒、1.5 米处
## 高达 323 米/秒²，实际 seek_accel 只有 34 —— 差近 10 倍。金币一旦在
## 玩家附近转过头就再也拐不回来，只能保持高速一圈圈掠过、永远进不了拾取圈。
##
## 这里不让它去硬转弯，而是**限制速度**：取
##   v_max(d) = sqrt(2 · seek_accel · d)  ← "在 d 米内刚好刹得住"的临界速度
## 与 seek_max_speed 中的较小值。这个上限随距离连续变化，所以是平滑减速：
## 7 米外仍是全速 22（保住"啪一下吸过来"的手感），越近越慢，收到拾取圈收尾。
##
## 连续约束很关键。早先试过"进闸门就钳制径向分量"的断续写法，结果是
## 在闸门半径处形成极限环——钱币卡在边界上反复抖、既不进也不退。
func _limit_seek_speed(to_target: Vector3) -> void:
	var dist := to_target.length()
	# 距离几乎为 0 时会退化成 0 速，留一个下限保证还能走到判定圈。
	var safe_dist := maxf(dist, collect_radius * 0.5)
	# 1.0001 是浮点余量：限速后距离略微变化时，不会让上限在临界点上反复跳。
	var cap := minf(seek_max_speed, sqrt(2.0 * seek_accel * safe_dist) * 1.0001)
	if _seek_velocity.length_squared() > cap * cap:
		_seek_velocity = _seek_velocity.normalized() * cap


## 判断本帧的这段位移会不会进入拾取判定圈。
##
## 只比"帧末位置到目标的距离"是不够的：帧率一低（或钱币飞得够快），
## 单帧位移可能直接跨过整个判定圈，钱币就会**从玩家身上穿过去**而不被
## 收走，下一帧再被吸回来，来回抖动。
##
## 所以这里对"本帧的整段轨迹"做扫掠判定：把轨迹写成
##   pos(s) = pos + step * s   （s ∈ [0,1] 是本帧走过的部分）
## 再求这一段轨迹与目标的最近距离。这样无论帧率多低都不会漏判；也不会像
## "只比帧末"那样两头出错——既有穿过却不收，也有帧末刚好落进圈内、
## 但这一段其实从旁边擦过去的误收。
##
## 两个容易写错的地方（都踩过）：
##   1. 符号。step 是**沿运动方向**的位移，所以最近点参数是
##      s = to_target·step / |step|²，**没有负号**。写成 -to_target·step
##      会把"朝目标飞"整类情形全判成不可达。
##   2. 不要把它当成无限长的射线去求最近点。钱币是朝前走的，越过了目标
##      之后就到不了了；只看 [0,1] 这一段，才既不会漏判也不会隔着距离误收。
func _will_reach_target(step: Vector3) -> bool:
	var to_target := seek_target.global_position - global_position
	# 当前已经在圈内：直接收，不用管这一帧怎么走。
	if to_target.length_squared() <= collect_radius * collect_radius:
		return true
	var step_len_sq := step.length_squared()
	if step_len_sq <= 0.000001:
		# 本帧几乎没动（刚转型出来速度还是 0），那就没机会进入圈内。
		return false
	# 本帧轨迹上离目标最近的那一点：s 夹在 [0,1]，只看这一帧真正走过的部分。
	var s := clampf(to_target.dot(step) / step_len_sq, 0.0, 1.0)
	# 用平方比较，省一次开方。
	var closest := to_target - step * s
	return closest.length_squared() <= collect_radius * collect_radius


func _collect() -> void:
	if _phase == Phase.COLLECTED:
		return
	_phase = Phase.COLLECTED
	Wallet.add(value)
	EventBus.coin_collected.emit(value)
	# 由池负责回收。
	if CoinPool != null:
		CoinPool.release(self)
	else:
		queue_free()


## 池回收时调用：彻底停下，等下次 launch。
func reset_for_pool() -> void:
	_phase = Phase.COLLECTED
	_velocity = Vector3.ZERO
	_seek_velocity = Vector3.ZERO
	seek_target = null
	visible = false
	set_process(false)


## 是否还在喷出阶段（尚未被吸附）。
func is_ejecting() -> bool:
	return _phase == Phase.EJECT


## 是否已被收走（等待回池）。
func is_collected() -> bool:
	return _phase == Phase.COLLECTED
