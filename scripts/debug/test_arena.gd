extends Node3D

## 测试场地控制器。验证剑 / 钱包 / 怪物 / 尸体拖拽，不是正式关卡。
##
## 快捷键：
##   R  重新加载场地
##   T  生成假人靶子（静止，测剑）
##   F1 切换调试信息
##   1  加 5 元          2  尝试花 3 元
##   3  加 100 元        4  钱包清零
##   5  生成蟑螂          6  生成老鼠

const DUMMY_SCENE := preload("res://scenes/debug/target_dummy.tscn")
const MONSTER_SCENE := preload("res://scenes/enemies/monster.tscn")
const COCKROACH_DATA := preload("res://resources/enemies/monster_cockroach.tres")
const RAT_DATA := preload("res://resources/enemies/monster_rat.tres")

## 生成新靶子时距玩家的距离。
@export var spawn_distance: float = 6.0
## 生成怪物时距玩家的距离（比靶子近一点，方便马上试抓取）。
@export var monster_spawn_distance: float = 3.5

var _spawn_count: int = 0
var _monster_count: int = 0
## 左上角调试信息文本。
var _label: Label
## 最近一次操作的结果，显示在调试信息里。
var _last_action: String = "（无）"


func _ready() -> void:
	_label = get_node_or_null("HUD/Info") as Label
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	_update_label()


func _on_enemy_spawned(_enemy: Node3D) -> void:
	_monster_count += 1
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				get_tree().reload_current_scene()
			KEY_T:
				_spawn_dummy_ahead()
			KEY_F1:
				if _label:
					_label.visible = not _label.visible
			KEY_1:
				Wallet.add(5)
				_last_action = "加 5 元"
				_update_label()
			KEY_2:
				var ok := Wallet.spend(3)
				_last_action = "花 3 元 → %s" % ("成功" if ok else "钱不够，未扣款")
				_update_label()
			KEY_3:
				Wallet.add(100)
				_last_action = "加 100 元"
				_update_label()
			KEY_4:
				Wallet.reset()
				_last_action = "钱包清零"
				_update_label()
			KEY_5:
				_spawn_monster_ahead(COCKROACH_DATA)
			KEY_6:
				_spawn_monster_ahead(RAT_DATA)


func _spawn_dummy_ahead() -> void:
	var player := _find_player()
	if player == null:
		return
	var dummy := DUMMY_SCENE.instantiate() as Node3D
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	dummy.position = player.global_position + forward * spawn_distance
	dummy.position.y = 0.0
	add_child(dummy)
	_spawn_count += 1
	_update_label()


func _find_player() -> Node3D:
	for child in get_children():
		if child is Node3D and child.has_method("set_carry_weight"):
			return child
	return null


## 在玩家前方生成一只怪物。
func _spawn_monster_ahead(data: MonsterData) -> void:
	var player := _find_player()
	if player == null:
		return
	var monster := MONSTER_SCENE.instantiate() as Monster
	if monster == null:
		return
	monster.data = data
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	add_child(monster)
	monster.global_position = player.global_position + forward * monster_spawn_distance
	# 生成点贴地，避免从半空落下。
	monster.global_position.y = 0.05
	_last_action = "生成 %s" % data.display_name
	EventBus.enemy_spawned.emit(monster)


func _update_label() -> void:
	if _label == null:
		return
	_label.text = "测试场地（剑 + 钱包 + 怪物/尸体）\nR 重载   T 生成靶子   F1 隐藏本提示\n左键挥砍 · 右键抓取/放下 · WASD 移动 · 空格跳跃 · Esc 暂停菜单\n已生成靶子：%d   已生成怪物：%d\n自动刷新：蟑螂最多3只 / 每4秒 · 老鼠最多2只 / 每6秒\n钱包调试：[1] +5  [2] 花3  [3] +100  [4] 清零\n怪物调试：[5] 蟑螂  [6] 老鼠\n上次操作：%s" % [_spawn_count, _monster_count, _last_action]
