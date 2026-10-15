extends SceneTree

## 原始坑口上的实际吸入、落币、玩家弹出和旧档能力；测试数据仅写 /tmp。
const CORPSE_PATH := "res://scenes/enemies/corpse.tscn"
var _rat
const COLLECT := preload("res://tests/helpers/coin_collection.gd")
var _passed := 0
var _failed := 0
var _world: Node3D
var _hole
var _player: CharacterBody3D
var _camera: Camera3D
var _grabber
var _offered: Array[int] = []
var _erupted := 0
var _capture_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("MAIN WORLD HOLE FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _spawn(at: Vector3) -> Node3D:
	var corpse: Node3D = load(CORPSE_PATH).instantiate()
	corpse.setup(_rat)
	_world.add_child(corpse)
	corpse.global_position = at
	corpse.reset_physics_interpolation()
	return corpse


func _place(at: Vector3) -> void:
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _capture(name: String) -> void:
	if _capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	for frame in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_capture_dir.path_join(name + ".png"))


func _settle_and_collect() -> void:
	_player.set_physics_process(false)
	_place(Vector3(-28.5, 3.44, -1.5))
	await _frames(360)
	var pool := root.get_node("CoinPool")
	_check(not _hole.has_pending() and pool.active_count() > 0, "two-second idle settlement emits coins")
	var outside_pit := true
	for coin in pool.get("_active"):
		var d: Vector3 = coin.global_position - _hole.global_position
		outside_pit = outside_pit and coin.is_grounded() and Vector2(d.x, d.z).length() > 10.0
	_check(outside_pit, "all emitted coins land outside the original pit on walkable ground")
	_check(await COLLECT.collect_all(self, _player), "walking contact collects every coin")
	_check(root.get_node("Wallet").total == _erupted, "wallet equals actual emitted value without loss or duplication")


func _run() -> void:
	await process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir=/tmp/"):
			_capture_dir = argument.trim_prefix("--capture-dir=")
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	root.get_node("SaveGame").save_path = "/tmp/main-world-hole-regression-save.json"
	root.get_node("GameSettings").settings_path = "/tmp/main-world-hole-regression-settings.cfg"
	root.get_node("GameFlow").start_new_game()
	await scene_changed
	_rat = load("res://resources/enemies/monster_rat.tres")
	_world = current_scene
	_hole = _world.get_node("Hole")
	_player = _world.get_node("Player")
	_camera = _player.get_node("Camera3D")
	_grabber = _camera.get_node("Grabber")
	root.get_node("EventBus").corpse_offered.connect(func(_body, value): _offered.append(value))
	root.get_node("EventBus").coins_erupted.connect(func(value, _count): _erupted += value)
	_hole._rng.seed = 20261015
	await _frames(60)
	_check(_player.is_on_floor(), "new-game player stands on original floor")
	_check(FileAccess.get_sha256("res://assets/map_origin.glb") == "677077df7b4eb9fbce3c73c83f7aeff59c15d7abf93078ea76091862e345c94d", "original model is unchanged")
	_check(_hole.get_node("Bottom/Shape").disabled, "prefab bottom does not add a second ground collider")

	# 从坑沿抓起实体并放下，随后完全交给真实重力和吸力。
	_player.set_physics_process(false)
	_place(_hole.global_position + Vector3(12, 0.51, 0))
	_player.rotation = Vector3(0, PI / 2, 0)
	_camera.look_at(_hole.global_position + Vector3.UP * 0.5)
	await _capture("01_hole")
	var held := _spawn(_camera.global_position - _camera.global_basis.z * 1.6)
	await _frames(1)
	_check(_grabber.try_grab() and _grabber.get_held() == held, "camera ray grabs an actual rat corpse at pit rim")
	await _frames(12)
	_grabber.drop(true)
	await _frames(180)
	_check(not is_instance_valid(held) and _offered.size() == 1, "released corpse is physically pulled into the pit and offered once")
	_check(not _grabber.is_holding() and is_zero_approx(_player.carry_weight), "offering clears held reference and carrying weight")
	await _settle_and_collect()

	# 每个方位从坑外进入，检查吸力与扩大后的判定区无遗漏。
	var before := _offered.size()
	for index in 8:
		var angle := TAU * index / 8.0
		_spawn(_hole.global_position + Vector3(cos(angle) * 13.0, 0.5, sin(angle) * 13.0))
	await _frames(240)
	if _offered.size() != before + 8:
		print("RIM DEBUG offered=", _offered, " before=", before, " pending=", _hole.pending_value)
		for body in get_nodes_in_group("corpses"):
			print("RIM BODY ", body.global_position, " velocity=", body.linear_velocity, " overlap=", _hole.is_in_attraction_range(body))
	_check(_offered.size() == before + 8, "all eight rim approaches reach the hole without getting stuck")
	await _settle_and_collect()

	# 正常站坑沿不弹出；落入最外圈也能喷回可移动高度。
	_player.set_physics_process(true)
	for index in 8:
		var angle := TAU * index / 8.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		_place(_hole.global_position + radial * 10.5 + Vector3.UP * 0.6)
		await _frames(30)
		_check(_player.is_on_floor() and absf(_player.velocity.y) < 0.1, "standing on rim does not eject player, direction %d" % index)
		_place(_hole.global_position + radial * 8.2 + Vector3.UP * 0.51)
		var ejected := false
		for frame in 60:
			await physics_frame
			if _player.velocity.y > 8.0:
				ejected = true
				break
		_check(ejected, "falling at outer pit edge ejects player, direction %d" % index)
	_player.set_physics_process(false)
	_place(Vector3(-28.5, 3.44, -1.5))

	# 镜子与价值等级作用于真实献祭，满级金钱币作用于真实喷币。
	var save := root.get_node("SaveGame")
	var upgrades: Dictionary = save.empty_upgrades()
	upgrades.mirror = true
	var levels := {"corpse_value": 3, "golden_coin": 20}
	_check(_world.restore_purchased_upgrades(upgrades, levels), "restore migrated hole upgrades")
	_check(_world.restore_purchased_upgrades(upgrades, levels), "restoring hole upgrades is idempotent")
	_spawn(_hole.global_position + Vector3.UP * 0.5)
	await _frames(5)
	_check(_offered.back() == (_rat.corpse_value + 3) * 2, "mirror and corpse-value level apply exactly once to physical offering")
	var remaining: float = _hole.time_until_erupt
	root.get_node("GameFlow").pause_game()
	await _frames(60)
	_check(is_equal_approx(_hole.time_until_erupt, remaining), "pause stops hole settlement timer")
	root.get_node("GameFlow").resume_game()
	await _frames(300)
	var coins: Array = root.get_node("CoinPool").get("_active")
	_check(not coins.is_empty() and coins.all(func(coin): return coin.is_golden and coin.value % 10 == 0), "level 20 turns every emitted coin golden")
	_place(_hole.global_position + Vector3(15.5, 0.6, 0))
	_camera.look_at(_hole.global_position + Vector3(8, 0, 0))
	await _capture("02_hole_reward")
	_check(await COLLECT.collect_all(self, _player), "upgraded coins remain physically collectible")
	_check(root.get_node("Wallet").total == _erupted, "upgraded reward has exact wallet accounting")
	_check(save.save_game().ok, "hole reward and upgrade state save successfully")
	var snapshot: Dictionary = save.read_save()
	_check(snapshot.coins == _erupted and snapshot.upgrades.mirror and snapshot.upgrade_levels == levels, "saved reward and hole upgrades match current state")
	_world.queue_free()
	await _frames()
	_check(root.get_node("CoinPool").active_count() == 0 and root.get_node("CoinPool").free_count() == 0, "leaving world clears all hole coin references")
	print("MAIN WORLD HOLE RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
