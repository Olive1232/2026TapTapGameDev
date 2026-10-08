extends Node3D

## 初始清扫赚金币 → 商店买油 → 点剑烧路 → 后方清扫献祭。
@export var room_title := "清扫与商店"
@export var initial_task := "进入左侧初始清扫区，杀鼠并把尸体带到中央洞献祭，攒 %d 金币买油。"
@export var purchase_task := "金币已够，进入右侧商店，右键拿油并放到忏悔室前的小台子。"
var _gate_remaining := 0
var _kills := 0
var _offered := false
var _reward_received := false
var _ever_ignited := false

@onready var _player: CharacterBody3D = $Player
@onready var _sword: Sword = $Player/Camera3D/WeaponRig/WeaponPivot/Mount
@onready var _objective: Label = $HUD/Objective
@onready var _hint: Label = $HUD/Hint
@onready var _shop: Node3D = $ShopRoom


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
	if is_gate_open() and is_ancestor_of(enemy):
		_kills += 1


func _on_corpse_offered(_corpse: Node3D, _value: int) -> void:
	if is_gate_open():
		_offered = true


func _on_coin_collected(_value: int) -> void:
	if _offered:
		_reward_received = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R or event.keycode == KEY_R:
			get_tree().reload_current_scene()


func _process(_delta: float) -> void:
	_update_hud()


func _update_hud() -> void:
	var price: int = _shop.shelf.item_data.price
	var task := initial_task % price
	if Wallet.can_afford(price):
		task = purchase_task
	if _shop.counter.item != null:
		task = "商品已在台面，左键挥剑命中店长进行强化。"
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
	if _shop.busy:
		task = "店长正在强化；完成交剑时扣款。"
	_objective.text = room_title + "\n" + task
	var state := "未涂油"
	if _sword.is_burning():
		state = "燃烧中 · 剩余 %d 次挥砍" % _sword.fire_swings_remaining
	elif _sword.oiled:
		state = "已涂油 · 可接触火把重新点燃"
	_hint.text = "剑：%s\nWASD 移动 · 空格跳跃 · 左键挥剑 · 右键点按拿起/放下 · Esc 菜单 · R 重置房间" % state
	var prompt: String = _shop.get_prompt()
	$HUD/ShopMessage.text = _shop.get_status_message()
	if not prompt.is_empty():
		$HUD/ShopMessage.text += "\n" + prompt


func is_gate_open() -> bool:
	return _gate_remaining == 0


func is_flow_complete() -> bool:
	return _reward_received
