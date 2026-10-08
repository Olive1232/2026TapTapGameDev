extends SceneTree

## 独立运行：Godot --headless --path . --fixed-fps 60 --script res://tests/run_gameplay_regression.gd
## 延迟加载玩法脚本，避免 SceneTree 脚本先于 autoload 注册而解析失败。
var _passed := 0
var _failed := 0
var _arena: Node


func _initialize() -> void:
	create_timer(20.0, true, false, true).timeout.connect(func():
		push_error("REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("REGRESSION FAILED: " + message)


func _new_monster(at: Vector3, automatic_physics: bool = true):
	var monster = load("res://scenes/enemies/monster.tscn").instantiate()
	monster.data = load("res://resources/enemies/monster_rat.tres").duplicate()
	monster.data.max_health = 100.0
	monster.data.move_speed = 0.0
	_arena.add_child(monster)
	monster.global_position = at
	monster.set_physics_process(automatic_physics)
	return monster


func _run() -> void:
	await process_frame
	_arena = load("res://scenes/debug/test_arena.tscn").instantiate()
	root.add_child(_arena)
	current_scene = _arena
	await process_frame
	await physics_frame
	var player = _arena.get_node("Player")
	player.set_physics_process(false)
	var camera = player.get_node("Camera3D")
	var sword = player.get_node("Camera3D/WeaponRig/WeaponPivot/Mount")
	var anchor = player.get_node("Camera3D/WeaponRig/WeaponPivot/HitAnchor")
	var rig = anchor.get_node("HitRig")
	var grabber = player.get_node("Camera3D/Grabber")
	var hole = _arena.get_node("Hole")
	var pool = root.get_node("CoinPool")
	var wallet = root.get_node("Wallet")

	# Geometry: yaw follows the model without inheriting pitch, roll or position.
	for yaw in [-48.0, 0.0, 52.0]:
		sword._apply_pose(yaw, 30.0)
		_check(is_equal_approx(anchor.rotation.y, deg_to_rad(yaw)), "damage anchor follows yaw")
		_check(is_equal_approx(sword.get_node("Pivot").rotation.y, anchor.rotation.y), "visual and damage yaw agree")
		var damage_transform: Transform3D = rig.global_transform
		sword._apply_pose(yaw, 90.0)
		_check(damage_transform.is_equal_approx(rig.global_transform), "visual pitch leaves damage transform unchanged")
	_check(is_zero_approx(sword.get_parent().rotation.y), "parent does not double the sweep")
	sword._drive_animation(0.0)
	var original_data = sword.data
	sword.set_sword_data(original_data.duplicate())
	sword._drive_animation(0.0)
	var original_damage_transform: Transform3D = rig.global_transform
	sword.data.rest_roll = 35.0
	_check(original_damage_transform.is_equal_approx(rig.global_transform), "visual roll leaves damage transform unchanged")
	sword.data.view_offset = Vector3(-0.8, -0.1, -0.7)
	_check(original_damage_transform.is_equal_approx(rig.global_transform), "view offset leaves damage transform unchanged")
	sword.set_sword_data(original_data)
	sword._drive_animation(0.0)

	# A real swing must hit both sides of the sweep and damage each target once.
	camera.rotation.x = deg_to_rad(-45.0)
	var targets: Array = []
	for yaw in [-45.0, 0.0, 45.0]:
		var angle := deg_to_rad(yaw)
		var offset := Vector3(-sin(angle) * 1.4, -0.34, -cos(angle) * 1.4)
		var target = _new_monster(camera.global_transform * offset, false)
		target.data.body_size = Vector3(0.2, 0.2, 0.2)
		target._apply_visual()
		target.global_position.y -= 0.1
		targets.append(target)
	await physics_frame
	await physics_frame
	_check(sword.try_swing(), "real swing starts")
	await create_timer(0.8).timeout
	for target in targets:
		_check(is_equal_approx(target.health, 100.0 - sword.data.damage), "sweep hits target exactly once at " + str(target.global_position))
		target.queue_free()
	_check(not sword.is_swinging(), "swing returns to idle")
	_check(is_equal_approx(Engine.time_scale, 1.0), "hitstop restores time scale")
	camera.rotation.x = 0.0
	await process_frame

	# Stun keeps knockback moving, decays it, and still applies gravity.
	var monster = _new_monster(Vector3(-8.0, 0.05, -8.0))
	monster.data.hit_stun = 0.25
	await create_timer(0.1).timeout
	var start: Vector3 = monster.global_position
	var hit = load("res://scripts/weapons/hit_info.gd").new()
	hit.damage = 1.0
	hit.knockback = Vector3(4.0, 0.0, 0.0)
	monster.take_hit(hit)
	await physics_frame
	await process_frame
	_check(monster.velocity.x > 0.0, "next physics frame keeps knockback")
	await create_timer(0.08).timeout
	_check(monster.global_position.x > start.x + 0.01, "stunned monster actually moves")
	await create_timer(0.4).timeout
	_check(is_zero_approx(monster.get("_knockback_velocity").length()), "knockback decays to rest")
	_check(is_zero_approx(monster.velocity.x), "stationary monster stops after knockback")
	monster.global_position.y = 2.0
	monster.velocity = Vector3.ZERO
	hit.knockback = Vector3.ZERO
	monster.take_hit(hit)
	await create_timer(0.1).timeout
	_check(monster.global_position.y < 1.99 and monster.velocity.y < 0.0, "stun still applies gravity")
	monster.queue_free()
	await process_frame

	# Keep grab/drop weight and held-corpse sacrifice unchanged.
	var corpse = load("res://scenes/enemies/corpse.tscn").instantiate()
	_arena.add_child(corpse)
	corpse.freeze = true
	corpse.global_position = camera.global_position - camera.global_basis.z * 2.0
	await physics_frame
	await physics_frame
	_check(grabber.try_grab(), "corpse can be grabbed")
	_check(grabber.is_holding() and player.carry_weight == 1.0, "grab applies weight")
	grabber.drop()
	_check(not grabber.is_holding() and player.carry_weight == 0.0, "drop clears weight")
	_check(grabber.try_grab(), "corpse can be grabbed again before sacrifice")
	corpse.global_position = hole.global_position + Vector3(0.0, 1.8, 0.0)
	wallet.reset()
	await create_timer(0.2).timeout
	_check(not is_instance_valid(corpse) and hole.pending_value == 1, "held corpse at height 1.8 is still sacrificed once")
	_check(not grabber.is_holding() and player.carry_weight == 0.0, "automatic sacrifice clears held reference and weight")
	await create_timer(4.0).timeout
	_check(wallet.total == 2 and pool.active_count() == 0, "one-value offering still pays and collects two coins")

	# Capacity/reuse and separately freed coins must keep the pool consistent.
	var previous_cap: int = pool.max_active
	pool.max_active = 3
	var oldest = pool.acquire()
	pool.acquire()
	pool.acquire()
	var reused = pool.acquire()
	_check(reused == oldest and pool.active_count() == 3, "pool reuses the oldest coin at capacity")
	pool.release_all()
	_check(pool.active_count() == 0 and pool.free_count() == 3, "all coins return to the pool")
	var removed = pool.acquire()
	removed.queue_free()
	await process_frame
	await process_frame
	_check(pool.active_count() == 0 and pool.free_count() == 2, "separately destroyed coin is removed from pool")
	pool.max_active = previous_cap

	# Reload with both active and free coins; verify payout after every reload.
	for iteration in range(3):
		var active = pool.acquire()
		active.launch(5, Color.WHITE, Vector3.ZERO, 100.0)
		var free_coin = pool.acquire()
		pool.release(free_coin)
		_check(pool.active_count() == 1 and pool.free_count() >= 1, "reload starts with active and free coins")
		_check(reload_current_scene() == OK, "arena reload succeeds")
		await process_frame
		await process_frame
		await physics_frame
		_arena = current_scene
		_arena.get_node("Player").set_physics_process(false)
		_check(not is_instance_valid(active) and not is_instance_valid(free_coin), "old scene coins are freed")
		_check(pool.active_count() == 0 and pool.free_count() == 0, "reload clears both pool lists")
		var coin = pool.acquire()
		_check(is_instance_valid(coin) and coin.get_parent() == _arena, "new coin belongs to reloaded arena")
		var previous_total: int = wallet.total
		coin.seek_target = _arena.get_node("Player")
		coin.global_position = coin.seek_target.global_position + Vector3(0.0, 0.0, 0.1)
		coin.launch(9, Color.WHITE, Vector3.ZERO, 0.0)
		await create_timer(0.3).timeout
		_check(wallet.total == previous_total + 9, "coin collects after reload " + str(iteration + 1))
		_check(pool.active_count() == 0 and pool.free_count() == 1, "coin returns to pool after reload")

	print("REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
