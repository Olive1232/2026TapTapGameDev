extends SceneTree

## 四项基础规则。使用历史 GLB 地图碰撞、现行火把与玩家组件。
var _passed := 0
var _failed := 0
var _room
var _player
var _wallet
var _pool
var _capture_dir := ""


func _initialize() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func():
		push_error("BASIC RULES REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("BASIC RULES REGRESSION FAILED: " + message)


func _frames(count: int = 3) -> void:
	for frame in range(count):
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await _frames(int(ceil(seconds * Engine.physics_ticks_per_second)))


func _floor(at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at - Vector3.UP * 3.0, 1)
	return _room.get_world_3d().direct_space_state.intersect_ray(ray)


func _corpse(at: Vector3, data = null, duration: float = 10.0):
	var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
	if data != null:
		corpse.setup(data)
	else:
		corpse.burn_duration = duration
	_room.add_child(corpse)
	corpse.global_position = at
	return corpse


func _capture(name: String, at: Vector3, target: Vector3) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var camera := Camera3D.new()
	_room.add_child(camera)
	camera.global_position = at
	camera.look_at(target)
	camera.make_current()
	await _frames()
	# 后台窗口会暂停常规绘制；主动画一帧，避免等待绘制信号时玩法继续计时。
	RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(_capture_dir.path_join(name + ".png"))
	camera.queue_free()
	_player.get_node("Camera3D").make_current()


func _run() -> void:
	await process_frame
	# 显式选择历史地图夹具；正式入口另由 run_main_world_* 验证。
	load("res://tests/helpers/legacy_world_fixture.gd").install(self)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_capture_dir = argument.trim_prefix("--capture-dir=")
	root.get_node("GameFlow").start_new_game()
	await scene_changed
	_room = current_scene
	_player = _room.get_node("Player")
	_wallet = root.get_node("Wallet")
	_pool = root.get_node("CoinPool")
	_player.set_physics_process(false)
	_player.global_position = _room.get_node("GameplayAnchors/Combat").global_position
	_player.rotation = Vector3.ZERO
	await _test_corpses()
	await _test_coins()
	await _test_ejection()
	print("BASIC RULES REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_corpses() -> void:
	var corpses: Array = []
	for species in ["rat", "cockroach"]:
		var data = load("res://resources/enemies/monster_" + species + ".tres")
		var corpse = _corpse(_room.get_node("GameplayAnchors/Entry").global_position + Vector3(corpses.size() * 2, 0.4, 0), data)
		corpses.append(corpse)
		_check(corpse.value == 1 and corpse.element.burn_duration == 10.0, species + " keeps value and configurable burn duration")
	await _wait(32.0)
	for corpse in corpses:
		_check(is_instance_valid(corpse) and not corpse.is_held and not corpse.element.burning, "ordinary corpse survives beyond former 30 second lifetime")
		_check(corpse.sleeping, "persistent corpse rests instead of remaining active")
	var torch = _room.get_node("Torch")
	var burning = _corpse(torch.get_node("ElementComponent").global_position + Vector3(0.3, 0, 0))
	burning.freeze = true
	await _wait(0.2)
	_check(burning.element.burning, "real torch contact ignites corpse")
	_check(is_equal_approx(burning.element.burn_duration, 10.0), "prototype n is 10 seconds")
	# 将已经点燃的尸体移到远离火把的藤蔓旁，确认火由尸体传播。
	burning.global_position = _room.get_node("GameplayAnchors/Entry").global_position + Vector3(1, 1, 1)
	var vine = load("res://scenes/elements/flammable_vines.tscn").instantiate()
	_room.add_child(vine)
	vine.global_position = burning.global_position + Vector3(0.7, -1.6, 0)
	await _wait(0.5)
	_check(vine.element.burning and vine.element.burn_duration == 10.0, "burning corpse ignites ten second vines away from torch")
	await _capture("burning-corpse", Vector3(7, 2.5, -9), burning.global_position)
	paused = true
	var remaining: float = burning.element.burn_remaining
	await _frames(30)
	_check(is_equal_approx(burning.element.burn_remaining, remaining), "pause freezes corpse burn timer")
	paused = false
	await _wait(8.0)
	_check(is_instance_valid(burning) and is_instance_valid(vine), "corpse and vine survive before ten seconds of burning")
	await _wait(2.0)
	_check(not is_instance_valid(burning) and not is_instance_valid(vine), "corpse and vines disappear after their burn duration")
	_check(_wallet.total == 0 and _room.get_node("Hole").pending_value == 0, "burnout alone never pays an offering reward")
	# 实际抓取后在手上烧毁，清除携带引用和负重。
	var camera = _player.get_node("Camera3D")
	camera.rotation = Vector3.ZERO
	var grabber = camera.get_node("Grabber")
	var held = _corpse(camera.global_position - camera.global_basis.z * 2.0, null, 0.5)
	held.freeze = true
	await _frames()
	_check(grabber.try_grab() and _player.carry_weight > 0.0, "burnable corpse uses actual grab and weight")
	var source = load("res://scenes/elements/torch.tscn").instantiate()
	_room.add_child(source)
	source.global_position = held.global_position - Vector3.UP * 1.45
	await _wait(0.15)
	_check(held.element.burning, "held corpse ignites on contact")
	await _wait(0.6)
	_check(not is_instance_valid(held) and not grabber.is_holding() and is_zero_approx(_player.carry_weight), "held burnout clears reference and weight")
	source.queue_free()
	for corpse in corpses:
		corpse.queue_free()
	await _frames()


func _test_coins() -> void:
	# 主厅与商店位于不同高度，必须各自按碰撞地面落地。
	for at in [_room.get_node("GameplayAnchors/Entry").global_position + Vector3.UP, _room.get_node("ShopRoom").global_transform * Vector3(0, 2, 3)]:
		var coin = _pool.acquire()
		coin.global_position = at
		coin.launch(7, Color(1, 0.84, 0.28), Vector3.ZERO)
		var before: int = _wallet.total
		await _wait(2.0)
		var floor_hit := _floor(coin.global_position)
		var half_height: float = coin.get_node("Shape").shape.size.y * 0.5
		_check(coin.is_grounded() and not floor_hit.is_empty() and absf(coin.global_position.y - floor_hit.position.y - half_height) < 0.015, "coin rests on actual floor at " + str(coin.global_position.y))
		var landed: Vector3 = coin.global_position
		await _wait(1.0)
		_check(coin.global_position.is_equal_approx(landed) and _wallet.total == before, "grounded coin stays still and does not seek player")
		await _capture("ground-coins" if at.x > 0 else "shop-coins", landed + Vector3(0, 1.2, 1.8), landed)
		_check(await load("res://tests/helpers/coin_collection.gd").collect_all(self, _player), "walking into coin collects on either floor")
		_check(_wallet.total == before + 7 and _pool.active_count() == 0, "ground contact credits value once and returns coin to pool")
		await _wait(0.3)
		_check(_wallet.total == before + 7, "pooled coin cannot pay twice")
	var coin = _pool.acquire()
	coin.global_position = _player.global_position + Vector3.UP
	coin.launch(3, Color.WHITE, Vector3.UP * 6.0)
	var before: int = _wallet.total
	await _wait(0.1)
	_check(coin.is_ejecting() and _wallet.total == before, "airborne coin overlapping player cannot be collected")
	await _wait(2.0)
	_check(coin.is_collected() and _wallet.total == before + 3, "coin already near player collects after landing")
	# 区域与距离兜底在同一物理帧命中时仍只献祭一次。
	var corpse = _corpse(_room.get_node("Hole").global_position + Vector3(0, -0.2, 0))
	await _frames()
	_check(not is_instance_valid(corpse) and _room.get_node("Hole").pending_value == 1, "ordinary offering is consumed once across both detection paths")
	await _wait(4.0)
	_check(_wallet.total == before + 3 and _pool.active_count() > 0, "erupted coins wait on ground before pickup")
	await _capture("pit-coins", Vector3(-1, 3.5, -10), _room.get_node("Hole").global_position)
	_check(await load("res://tests/helpers/coin_collection.gd").collect_all(self, _player), "all eruption coins land outside actual map opening and can be walked into")
	_check(_wallet.total == before + 5, "new pickup preserves offering conversion")


func _test_ejection() -> void:
	var hole = _room.get_node("Hole")
	_player.rotation = Vector3.ZERO
	var below: Vector3 = hole.global_position + Vector3(hole.player_fall_radius * 0.65, -1, 0)
	_player.global_position = below
	_player.velocity = Vector3(2, -9, 3)
	await _frames()
	_check(_player.global_position.is_equal_approx(below) and _player.velocity.y == hole.player_eject_speed, "pit gives upward speed at actual outer opening without teleport")
	_check(_player.velocity.x == 2 and _player.velocity.z == 3, "ejection preserves horizontal momentum")
	_player.velocity.y = 4.0
	await _frames(10)
	_check(_player.velocity.y == 4.0, "same fall does not repeatedly add upward speed")
	_player.global_position = hole.global_position + Vector3(hole.player_fall_radius * 0.65, 2, 0)
	await _frames()
	_player.global_position = below
	_player.velocity = Vector3(0, -8, 0)
	await _frames()
	_check(_player.velocity.y == hole.player_eject_speed, "new fall can trigger another ejection")
	_player.set_physics_process(true)
	Input.action_press("Right")
	await _wait(0.7)
	_check(_player.global_position.y > hole.global_position.y + 2.0, "physics moves player upward out of hole")
	await _capture("pit-ejection", hole.global_position + Vector3(12, 6, 8), _player.global_position)
	await _wait(1.6)
	Input.action_release("Right")
	await _wait(0.5)
	_check(_player.is_on_floor() and _player.global_position.x > hole.global_position.x + hole.player_fall_radius, "air controls steer player onto real ground outside pit")
	_check(_wallet.total == 19 and _pool.active_count() == 0, "pit ejection does not change money")
