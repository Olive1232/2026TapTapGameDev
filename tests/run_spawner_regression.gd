extends SceneTree

## --headless --path . --fixed-fps 60 --script res://tests/run_spawner_regression.gd
var _passed := 0
var _failed := 0
var _world: Node3D
var _spawn_events: Array = []
var _bus
var _spawner_scene: PackedScene
var _rat
var _cockroach


func _initialize() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("SPAWNER REGRESSION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("SPAWNER REGRESSION FAILED: " + message)


func _wait(seconds: float) -> void:
	# 按物理帧等待，避免 --fixed-fps 与真实时钟计时器的时间基准不同。
	for _frame in range(ceili(seconds * Engine.physics_ticks_per_second)):
		await physics_frame
	await process_frame


func _new_spawner(at: Vector3, data, maximum: int = 3, interval: float = 0.4, radius: float = 2.5):
	var spawner = _spawner_scene.instantiate()
	spawner.position = at
	spawner.monster_data = data
	spawner.max_alive = maximum
	spawner.spawn_interval = interval
	spawner.spawn_radius = radius
	_world.add_child(spawner)
	return spawner


func _on_spawned(monster: Node3D) -> void:
	_spawn_events.append(monster)
	# 固定测试夹具不移动，方便测计数与空间占用。
	monster.set_physics_process(false)


func _run() -> void:
	await process_frame
	_bus = root.get_node("EventBus")
	_spawner_scene = load("res://scenes/enemies/monster_spawner.tscn")
	_rat = load("res://resources/enemies/monster_rat.tres")
	_cockroach = load("res://resources/enemies/monster_cockroach.tres")
	var baseline: int = _bus.enemy_died.get_connections().size()
	_bus.enemy_spawned.connect(_on_spawned)
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 40)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	_world.add_child(floor_body)
	var first = _new_spawner(Vector3(4, 0, 0), _rat)
	_check(first.monster_data == _rat, "selected MonsterData is assigned")
	_check(first.get_alive_count() == 0, "wait before first spawn")
	await _wait(0.15)
	_check(first.get_alive_count() == 0, "no spawn before interval")
	await _wait(0.3)
	_check(first.get_alive_count() == 1, "one spawn at first interval")
	var monster = first.get_spawned_monsters()[0]
	_check(monster.data == _rat and monster.health == _rat.max_health, "spawned monster has selected type and health")
	_check(monster.get_parent() == first, "spawned monster belongs to its point")
	_check(Vector2(monster.global_position.x - 4, monster.global_position.z).length() <= first.spawn_radius, "position inside configured radius")
	_check(is_equal_approx(monster.global_position.y, 0.05), "feet spawn just above ground")
	_check(monster.get_node("Mesh").mesh.size.is_equal_approx(_rat.body_size), "selected type body size applied")
	_check(monster.get_node("Mesh").get_active_material(0).albedo_color.is_equal_approx(_rat.body_color), "selected type color applied")
	_check(_spawn_events.size() == 1, "enemy_spawned emitted once")
	await _wait(0.45)
	_check(first.get_alive_count() == 2, "one more at next interval")
	await _wait(0.45)
	_check(first.get_alive_count() == 3, "fills configured cap")
	await _wait(0.7)
	_check(first.get_alive_count() == 3 and _spawn_events.size() == 3, "full point does not exceed cap or accumulate spawns")
	var info = load("res://scripts/weapons/hit_info.gd").new()
	info.damage = 1000
	first.get_spawned_monsters()[0].take_hit(info)
	_check(first.get_alive_count() == 2, "death releases slot immediately")
	var corpses := 0
	for child in first.get_children():
		if child is RigidBody3D:
			corpses += 1
	_check(corpses == 1, "death still produces corpse")
	await _wait(0.15)
	_check(first.get_alive_count() == 2, "no immediate backlog refill after death")
	await _wait(0.35)
	_check(first.get_alive_count() == 3, "refills one after interval even with corpse present")
	first.get_spawned_monsters()[0].queue_free()
	await process_frame
	await process_frame
	_check(first.get_alive_count() == 2, "manual deletion releases slot")
	await _wait(0.5)
	_check(first.get_alive_count() == 3, "manual deletion also refills")

	var second = _new_spawner(Vector3(14, 0, 0), _cockroach, 2, 0.2)
	await _wait(0.55)
	_check(second.get_alive_count() == 2 and first.get_alive_count() == 3, "points have independent caps")
	_check(second.get_spawned_monsters()[0].data == _cockroach, "second point selects other monster type")
	_check(second.get_spawned_monsters()[0].get_node("Mesh").get_active_material(0).albedo_color.is_equal_approx(_cockroach.body_color), "other type color applied")
	second.get_spawned_monsters()[0].take_hit(info)
	_check(first.get_alive_count() == 3 and second.get_alive_count() == 1, "death only affects owning point")
	await _wait(0.3)
	_check(second.get_alive_count() == 2, "second point refills at its own interval")
	first.max_alive = 4
	first.monster_data = _cockroach
	await _wait(0.5)
	_check(first.get_alive_count() == 4, "raising cap permits additional spawn")
	var cockroaches := 0
	for candidate in first.get_spawned_monsters():
		if candidate.data == _cockroach:
			cockroaches += 1
	_check(cockroaches == 1, "runtime type switch affects new monsters only")
	first.max_alive = 1
	await _wait(0.6)
	_check(first.get_alive_count() == 4, "lower cap stops generation without deleting live monsters")
	first.monster_data = null
	_check(not first._get_configuration_warnings().is_empty(), "missing data has editor warning")
	first.max_alive = 8
	await _wait(0.5)
	_check(first.get_alive_count() == 4, "missing data does not spawn fallback type")
	first.enabled = false

	var blocked = _new_spawner(Vector3(30, 0, 0), _rat, 2, 0.2, 0.0)
	var blocker := StaticBody3D.new()
	var blocker_shape := CollisionShape3D.new()
	box = BoxShape3D.new()
	box.size = Vector3(3, 3, 3)
	blocker_shape.shape = box
	blocker.add_child(blocker_shape)
	blocker.position = Vector3(30, 1.5, 0)
	_world.add_child(blocker)
	await _wait(0.5)
	_check(blocked.get_alive_count() == 0, "blocked location skips spawn")
	blocker.queue_free()
	await _wait(0.3)
	_check(blocked.get_alive_count() == 1, "later interval retries after obstruction removed")
	await _wait(0.5)
	_check(blocked.get_alive_count() == 1, "occupied center does not stack monsters")
	blocked.get_spawned_monsters()[0].global_position.z = -3
	await _wait(0.3)
	_check(blocked.get_alive_count() == 2, "vacated center allows next spawn")
	_check(Vector2(blocked.get_spawned_monsters()[1].global_position.x - 30, blocked.get_spawned_monsters()[1].global_position.z).is_zero_approx(), "zero radius uses point center")

	var paused_point = _new_spawner(Vector3(50, 0, 0), _rat, 1)
	await _wait(0.12)
	var elapsed: float = paused_point._elapsed
	paused = true
	await _wait(0.6)
	_check(paused_point.get_alive_count() == 0 and is_equal_approx(paused_point._elapsed, elapsed), "pause freezes refresh countdown")
	paused = false
	await _wait(0.12)
	_check(paused_point.get_alive_count() == 0, "resume retains remaining interval")
	await _wait(0.3)
	_check(paused_point.get_alive_count() == 1, "resume eventually spawns once")
	paused_point.enabled = false
	paused_point.get_spawned_monsters()[0].queue_free()
	await _wait(0.6)
	_check(paused_point.get_alive_count() == 0, "disabled point does not refill")
	paused_point.enabled = true
	await _wait(0.12)
	_check(paused_point.get_alive_count() == 0, "reenabling starts fresh interval")
	await _wait(0.35)
	_check(paused_point.get_alive_count() == 1, "reenabling resumes refresh")
	paused_point.max_alive = 0
	paused_point.get_spawned_monsters()[0].queue_free()
	await _wait(0.6)
	_check(paused_point.get_alive_count() == 0, "zero cap disables spawning")
	paused_point.spawn_interval = 0.0
	paused_point.spawn_radius = -1.0
	paused_point.max_alive = -1
	_check(is_equal_approx(paused_point.spawn_interval, 0.1) and is_zero_approx(paused_point.spawn_radius) and paused_point.max_alive == 0, "invalid scalar settings clamped")
	_world.queue_free()
	await process_frame
	await process_frame
	_check(_bus.enemy_died.get_connections().size() == baseline, "removed points disconnect global death listeners")
	_spawn_events.clear()

	# Actual arena configuration, reload and menu exit also exercise lifecycle.
	var arena = load("res://scenes/debug/test_arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	var roaches = arena.get_node("CockroachSpawner")
	var rats = arena.get_node("RatSpawner")
	_check(roaches.max_alive == 3 and is_equal_approx(roaches.spawn_interval, 4.0) and roaches.monster_data.id == &"cockroach", "arena cockroach point configured")
	_check(rats.max_alive == 2 and is_equal_approx(rats.spawn_interval, 6.0) and rats.monster_data.id == &"rat", "arena rat point configured")
	roaches.spawn_interval = 0.1
	rats.spawn_interval = 0.1
	await _wait(0.6)
	_check(roaches.get_alive_count() == 3 and rats.get_alive_count() == 2, "arena points actually fill their caps")
	_check(arena._monster_count == 5, "debug UI counts automated spawn events")
	var old_monster = roaches.get_spawned_monsters()[0]
	_check(reload_current_scene() == OK, "reload arena")
	await process_frame
	await process_frame
	_check(not is_instance_valid(roaches) and not is_instance_valid(old_monster), "reload frees points and their monsters")
	_check(current_scene.get_node("CockroachSpawner").get_alive_count() == 0, "reloaded point starts fresh")
	_check(_bus.enemy_died.get_connections().size() == baseline + 2, "reload leaves only new listeners")
	_check(root.get_node("GameFlow").return_to_main_menu().ok, "return to menu after spawning")
	await process_frame
	await process_frame
	_check(_bus.enemy_died.get_connections().size() == baseline, "menu exit cleans spawner listeners")
	_bus.enemy_spawned.disconnect(_on_spawned)
	print("SPAWNER REGRESSION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
