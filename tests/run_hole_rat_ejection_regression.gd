extends SceneTree

## 当前正式洞上的活鼠喷飞、独立触发、真实抛物线及死亡献祭回归。
var _passed := 0
var _failed := 0
var _world
var _hole
var _player
var _rat_data


func _initialize() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("RAT EJECTION TIMEOUT")
		quit(1))
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("RAT EJECTION FAILED: " + message)


func _frames(count: int = 4) -> void:
	for frame in count:
		await physics_frame
	await process_frame


func _spawn(at: Vector3, physics: bool = false):
	var rat = load("res://scenes/enemies/monster.tscn").instantiate()
	rat.data = _rat_data.duplicate()
	rat.data.move_speed = 0.0
	rat.position = at
	_world.add_child(rat)
	rat.set_physics_process(physics)
	return rat


func _run() -> void:
	await process_frame
	root.get_node("SaveGame").save_path = "/tmp/rat-ejection-regression-save.json"
	root.get_node("GameSettings").settings_path = "/tmp/rat-ejection-regression-settings.cfg"
	root.get_node("GameFlow").start_new_game()
	await scene_changed
	_world = current_scene
	# 本专项验证喷飞与常规喷币，首次对白由对话专项覆盖。
	var dialogue = _world.get_node_or_null("WorldDialogue")
	if dialogue != null:
		dialogue.restore_progress({"shop_visited": true, "hole_introduced": true})
	_hole = _world.get_node("Hole")
	_player = _world.get_node("Player")
	_player.set_physics_process(false)
	_world.get_node("RatSpawner").enabled = false
	_rat_data = load("res://resources/enemies/monster_rat.tres")
	var wallet = root.get_node("Wallet")
	var pool = root.get_node("CoinPool")
	var below: Vector3 = _hole.global_position + Vector3(_hole.player_fall_radius * 0.65, -1, 0)
	var rat = _spawn(below)
	rat.velocity = Vector3(2, -9, 3)
	await _frames()
	_check(rat.is_in_group("hole_ejectable") and rat.velocity.y == _hole.player_eject_speed, "rat receives same upward speed as player")
	_check(rat.global_position.is_equal_approx(below) and rat.velocity.x == 2 and rat.velocity.z == 3, "ejection does not teleport or change horizontal momentum")
	rat.velocity.y = 4.0
	await _frames(10)
	_check(rat.velocity.y == 4.0, "one fall does not continuously add upward speed")
	rat.global_position.y = _hole.global_position.y + 2.0
	await _frames()
	rat.global_position = below
	rat.velocity.y = -50.0
	await _frames()
	_check(rat.velocity.y == _hole.player_eject_speed, "another fast fall triggers a new ejection")
	rat.global_position.y = _hole.global_position.y + 2.0
	await _frames()
	rat.global_position = below
	rat.velocity.y = 20.0
	await _frames()
	_check(rat.velocity.y == 20.0, "stronger existing upward velocity is retained")

	var second = _spawn(below + Vector3(0, 0, 1))
	second.velocity.y = -5.0
	paused = true
	await _frames(10)
	_check(second.velocity.y == -5.0, "pause suspends hole ejection")
	paused = false
	await _frames()
	_check(second.velocity.y == _hole.player_eject_speed and rat.velocity.y == 20.0, "each rat has an independent one-fall latch")
	var second_id: int = second.get_instance_id()
	second.queue_free()
	await _frames()
	_check(not _hole.get("_ejected_characters").has(second_id), "deleted rat is removed from ejection tracking")

	var airborne = _spawn(_hole.global_position + Vector3(0, 1, 0), true)
	var highest: float = airborne.global_position.y
	var fastest_up := 0.0
	for frame in 150:
		await physics_frame
		highest = maxf(highest, airborne.global_position.y)
		fastest_up = maxf(fastest_up, airborne.velocity.y)
	_check(fastest_up > 11.0 and highest > _hole.global_position.y + 3.0, "normal monster physics rises out of actual pit after falling")
	_check(airborne.health == airborne.data.max_health and not airborne.get("_dead"), "ejection keeps rat alive without damage")
	_check(_hole.pending_value == 0 and wallet.total == 0 and pool.active_count() == 0, "living rats never create sacrifice value or coins")
	airborne.queue_free()

	for index in 8:
		var angle := TAU * index / 8.0
		var rim = _spawn(_hole.global_position + Vector3(cos(angle) * 10.5, 0.5, sin(angle) * 10.5), true)
		await _frames(60)
		_check(rim.is_on_floor() and absf(rim.velocity.y) < 0.1, "standing on rim does not eject rat, direction %d" % index)
		rim.queue_free()

	# 死亡后不再是可喷飞活体，生成的尸体仍通过真实洞判定献祭。
	var rat_id: int = rat.get_instance_id()
	var hit = load("res://scripts/weapons/hit_info.gd").new()
	hit.damage = 1000.0
	rat.take_hit(hit)
	_check(not rat.is_in_group("hole_ejectable"), "death immediately removes living ejection registration")
	await _frames()
	_check(not is_instance_valid(rat) and not _hole.get("_ejected_characters").has(rat_id), "death clears rat and weak tracking record")
	_check(_hole.pending_value == 1, "dead rat still offers corpse value exactly once")
	await _frames(360)
	_check(pool.active_count() > 0 and wallet.total == 0, "corpse produces physical coins without direct wallet credit")
	_check(await load("res://tests/helpers/coin_collection.gd").collect_all(self, _player), "corpse reward coins can be collected normally")
	_check(wallet.total == 2, "one rat corpse retains existing reward conversion")
	print("RAT EJECTION RESULT: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
