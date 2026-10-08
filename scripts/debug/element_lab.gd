extends Node3D

## 一条可玩的验证流程：涂油 → 点剑 → 烧路 → 战斗 → 搬运 → 献祭。
var _gate_remaining := 0
var _kills := 0
var _offered := false
var _reward_received := false
var _ever_ignited := false

@onready var _player: CharacterBody3D = $Player
@onready var _sword: Sword = $Player/Camera3D/WeaponRig/WeaponPivot/Mount
@onready var _objective: Label = $HUD/Objective
@onready var _hint: Label = $HUD/Hint


func _ready() -> void:
	_gate_remaining = $VineGate.get_child_count()
	for vine in $VineGate.get_children():
		vine.tree_exiting.connect(_on_gate_part_removed)
		vine.element.burned_down.connect(func(): EventBus.obstacle_broken.emit(vine, &"fire"))
	_sword.element.ignited.connect(func(): _ever_ignited = true)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.corpse_offered.connect(_on_corpse_offered)
	EventBus.coin_collected.connect(_on_coin_collected)
	_update_hud()


func _on_gate_part_removed() -> void:
	if get_tree().current_scene != self or is_queued_for_deletion():
		return
	_gate_remaining = maxi(0, _gate_remaining - 1)
	if _gate_remaining == 0:
		$CockroachSpawner.enabled = true
		$RatSpawner.enabled = true
		$GateSign.text = "通路已打开"


func _on_enemy_died(enemy: Node3D) -> void:
	if is_ancestor_of(enemy):
		_kills += 1


func _on_corpse_offered(_corpse: Node3D, _value: int) -> void:
	_offered = true


func _on_coin_collected(_value: int) -> void:
	if _offered:
		_reward_received = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.keycode == KEY_E:
			var station := _aimed_oil_station()
			if station != null:
				station.apply_to(_sword)
		elif event.physical_keycode == KEY_R or event.keycode == KEY_R:
			get_tree().reload_current_scene()


func _aimed_oil_station() -> Node3D:
	var camera: Camera3D = _player.get_node("Camera3D")
	var from := camera.global_position
	var ray := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * 3.2, CollisionLayers.WORLD)
	ray.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var collider: Node3D = hit.get("collider") as Node3D
	return collider if collider != null and collider.has_method("apply_to") else null


func _process(_delta: float) -> void:
	_update_hud()


func _update_hud() -> void:
	var task := "瞄准入口涂油台，按 E 为剑涂油。"
	if _reward_received:
		task = "流程完成！继续战斗献祭，或按 Esc 手动存档。"
	elif _offered:
		task = "献祭完成，稍等洞喷出钱币并收取。"
	elif _kills > 0:
		task = "右键点一下拿尸体，带回主房间中央的洞。"
	elif _gate_remaining == 0:
		task = "通路已打开，进入后方房间，左键攻击怪物。"
	elif _ever_ignited:
		task = "用燃烧的剑接触或挥砍门口藤蔓，等待烧开通路。" if _sword.is_burning() else "火焰已熄灭，回火把重新点燃，再烧开藤蔓。"
	elif _sword.oiled:
		task = "走到火把旁，让剑身接触火焰。"
	_objective.text = "元素测试房间\n" + task
	var state := "未涂油"
	if _sword.is_burning():
		state = "燃烧中 · 剩余 %d 次挥砍" % _sword.fire_swings_remaining
	elif _sword.oiled:
		state = "已涂油 · 可接触火把重新点燃"
	_hint.text = "剑：%s\nWASD 移动 · 空格跳跃 · 左键挥剑 · 右键点按拿起/放下 · Esc 菜单 · R 重置房间" % state
	if _aimed_oil_station() != null:
		_hint.text += "\n[E] 免费测试涂油"


func is_gate_open() -> bool:
	return _gate_remaining == 0


func is_flow_complete() -> bool:
	return _reward_received
