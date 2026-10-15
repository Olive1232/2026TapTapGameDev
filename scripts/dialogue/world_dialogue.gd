extends Node

## 首次事件属于当前游戏进度；存档只记录是否触发，不保存临时物体。
const SHOP_INTRO := &"shop_intro"
const HOLE_INTRO := &"hole_intro"
const SHOP_LINES := [
	"你想要买东西嘛？",
	"不买就出去。",
	"没钱的话，可以去山洞里面杀几只老鼠。",
	"丢到门口的洞里面。会有人给你回报。",
]
const HOLE_LINES := [
	"额，有点恶心。",
	"你就没有更好的东西了嘛？",
	"啊。不是店长啊。",
	"你好啊朋友。",
	"我是洞。",
	"总之，如你所见，我现在有点饥肠辘辘，饥不择食，前胸贴后背....",
	"额，反正是要用点美妙的生物组织去维持我美丽的红色。",
	"你知道的。就像口红。如果你选择一个太浅的色号，谁会注意到它呢？",
	"总之，帮我再搞点老鼠来。",
	"我会用一次涌现来回报你。真的。",
	"比如现在。",
]
var _shop_visited := false
var _hole_introduced := false

@onready var _player: CharacterBody3D = $"../Player"
@onready var _grabber: Grabber = $"../Player/Camera3D/Grabber"
@onready var _ui: BottomText = $"../HUD/BottomText"
@onready var _hole: Hole = $"../Hole"
@onready var _shop_zone: Area3D = get_node_or_null("../ShopDialogueZone") as Area3D


func _ready() -> void:
	if _shop_zone == null:
		_shop_zone = _create_shop_zone()
	_shop_zone.body_entered.connect(_on_shop_entered)
	_hole.corpse_received.connect(_on_corpse_received)
	_ui.dialogue_line_changed.connect(_on_dialogue_line_changed)
	_ui.dialogue_finished.connect(_on_dialogue_finished)


## 显式摆放的触发区优先；旧场景缺少时按现有商店部件生成，不移动模型。
func _create_shop_zone() -> Area3D:
	var world := get_parent() as Node3D
	var bounds := AABB((world.get_node("Counter") as Node3D).position, Vector3.ZERO)
	for node_name in ["Shopkeeper", "Booth", "Shelf", "CorpseValueShelf", "GoldenCoinShelf", "MirrorShelf", "CorpseReturnShelf", "ChargedThrowShelf"]:
		var part := world.get_node_or_null(NodePath(node_name)) as Node3D
		if part != null:
			bounds = bounds.expand(part.position)
	var area := Area3D.new()
	area.name = "ShopDialogueZone"
	area.position = bounds.get_center() + Vector3.UP * 2.0
	area.collision_layer = 0
	area.collision_mask = CollisionLayers.PLAYER
	area.monitorable = false
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(12.0, bounds.size.x + 8.0), 7.0, maxf(12.0, bounds.size.z + 8.0))
	shape.shape = box
	area.add_child(shape)
	# 场景内已摆放的控制器会先于父关卡 ready；此时不能同步添加兄弟节点。
	if world.is_node_ready():
		world.add_child(area)
	else:
		world.add_child.call_deferred(area)
	return area


func get_progress() -> Dictionary:
	return {"shop_visited": _shop_visited, "hole_introduced": _hole_introduced}


func restore_progress(progress: Dictionary) -> void:
	_shop_visited = progress.get("shop_visited", false)
	_hole_introduced = progress.get("hole_introduced", false)


func _on_shop_entered(body: Node3D) -> void:
	if body != _player or _shop_visited:
		return
	_shop_visited = true
	# 空手指没有搬运尸体或商品；初始剑和钱包余额不影响这次指引。
	if _grabber.is_holding():
		return
	_ui.play_dialogue(SHOP_INTRO, "店长", PackedStringArray(SHOP_LINES))
	_ui.set_message(&"rat_task", "赚点钱：去山洞杀两只老鼠，把尸体丢进门口的洞里。", BottomText.GUIDANCE + 1)


func _on_corpse_received(_corpse: Corpse) -> void:
	if _hole_introduced:
		return
	_hole_introduced = true
	_hole.set_settlement_paused(true)
	if not _ui.play_dialogue(HOLE_INTRO, "洞", PackedStringArray(HOLE_LINES)):
		_hole.set_settlement_paused(false)


func _on_dialogue_line_changed(source: StringName, index: int, _text: String) -> void:
	if source == HOLE_INTRO and index == HOLE_LINES.size() - 1:
		_hole.set_settlement_paused(false)
		_hole.force_erupt()
		_ui.clear_message(&"rat_task")


func _on_dialogue_finished(source: StringName) -> void:
	if source == HOLE_INTRO:
		_hole.set_settlement_paused(false)
