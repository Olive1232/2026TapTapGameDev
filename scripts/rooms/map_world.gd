extends Node3D

## 正式白模世界入口。玩法坐标见场景内 GameplayAnchors；不依赖旧试验房。
@export var room_title := "洞穴主厅"
var _offered := false
var _reward_received := false

@onready var _player: CharacterBody3D = $Player
@onready var _sword: Sword = $Player/Camera3D/WeaponRig/WeaponPivot/Mount
@onready var _shop: Node3D = $ShopRoom
@onready var _bottom_text: BottomText = $HUD/BottomText
@onready var _objective: Label = $HUD/Objective


func _ready() -> void:
	EventBus.corpse_offered.connect(_on_corpse_offered)
	EventBus.coin_collected.connect(_on_coin_collected)
	_update_hud()


func _physics_process(_delta: float) -> void:
	if _player.global_position.y < -24.0 * $WorldGeometry.scale.y:
		_player.global_transform = $ExitPoint.global_transform
		_player.velocity = Vector3.ZERO
		_player.reset_physics_interpolation()


func _process(_delta: float) -> void:
	# 载入永久通路也会按实际开通状态恢复刷怪，不重放奖励或机关动画。
	var opened := is_gate_open()
	$EntryRatSpawner.enabled = opened
	$RatSpawner.enabled = opened
	$GalleryRatSpawner.enabled = opened
	$DeepRatSpawner.enabled = $WeightPuzzle/Gate.is_open()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R or event.keycode == KEY_R:
			GameFlow.reset_current_game()


func _on_corpse_offered(_corpse: Node3D, _value: int) -> void:
	_offered = true


func _on_coin_collected(_value: int) -> void:
	if _offered:
		_reward_received = true


func is_gate_open() -> bool:
	return $VineGate.is_persistently_open()


func is_flow_complete() -> bool:
	return is_gate_open() and $WeightPuzzle/Gate.is_open() and _reward_received


func _update_hud() -> void:
	var task := "在主厅击杀老鼠，将尸体投入洞中献祭。"
	var price: int = _shop.shelf.item_data.price
	if Wallet.can_afford(price):
		task = "前往西侧商店购买油，把商品放到台面后挥剑敲店长。"
	if _sword.oiled:
		task = "在火把处点燃剑，烧开主厅东侧门口的藤蔓。"
	if is_gate_open():
		task = "探索东侧房间；把鼠尸体放上高处配重平台，开启深处的门。"
	if $WeightPuzzle/Gate.is_open():
		task = "升降门已开启，进入深处清扫区。"
	if _shop.counter.item != null:
		task = "商品已在台面，左键挥剑命中店长进行强化。"
	if _shop.busy:
		task = "店长正在处理商品，请稍候。"
	_objective.text = room_title + "\n" + task
	var state := "未涂油"
	if _sword.is_burning():
		state = "燃烧中 · 剩余 %d 次挥砍" % _sword.fire_swings_remaining
	elif _sword.oiled:
		state = "已涂油 · 可接触火把重新点燃"
	var guidance := "剑：%s\nWASD 移动 · 空格跳跃 · 左键挥剑 · 右键拿放 · Esc 菜单" % state
	if OS.is_debug_build():
		guidance += " · R 重置"
	var grabber := _player.get_node("Camera3D/Grabber") as Grabber
	var throw_prompt := grabber.get_throw_prompt()
	if not throw_prompt.is_empty():
		guidance += "\n" + throw_prompt
	if $Hole.has_upgrade("corpse_return"):
		guidance += "\n灵魂鸡蛋：离开房间后回收遗留尸体"
	_bottom_text.set_message(&"guidance", guidance, BottomText.GUIDANCE)
	_bottom_text.set_message(&"shop_description", _shop.get_context_text(), BottomText.DESCRIPTION)
	_bottom_text.set_message(&"shop_feedback", _shop.get_status_message(), BottomText.FEEDBACK)
