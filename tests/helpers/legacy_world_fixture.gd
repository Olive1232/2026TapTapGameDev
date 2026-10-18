extends "res://scripts/autoload/game_flow.gd"

## 旧地图的机制专项使用显式历史夹具，不再假定主菜单会进入已弃用的地图。
## 只在测试进程中替换入口路由；保存格式、交易、暂停、菜单与机关仍使用原实现。
## main_world 的实际入口、升级、通行与存档由 run_main_world_* 专项验收。
const SCENE := "res://scenes/rooms/map_world.tscn"
var _fixture_scene := SCENE


static func install(tree: SceneTree, scene_path: String = SCENE) -> void:
	var flow := tree.root.get_node("GameFlow")
	flow.set_script(load("res://tests/helpers/legacy_world_fixture.gd"))
	flow.set("_pause_menu", flow.get_node("PauseMenu"))
	flow.set("_fixture_scene", scene_path)


func is_in_game() -> bool:
	var scene := get_tree().current_scene
	return (scene != null and scene.scene_file_path == _fixture_scene) or super.is_in_game()


func _get_upgrade_owner(scene: Node) -> Node:
	if scene != null and scene.scene_file_path == _fixture_scene:
		return scene.get_node("ShopRoom")
	return super._get_upgrade_owner(scene)


func _enter_game(coins: int, upgrades: Dictionary = {}, level: String = "world", opened_gates: Dictionary = {}, upgrade_levels: Dictionary = {}, tutorial_stage: String = "complete", dialogue_progress: Dictionary = {}) -> Dictionary:
	if level != "world":
		return super._enter_game(coins, upgrades, level, opened_gates, upgrade_levels, tutorial_stage, dialogue_progress)
	if _transitioning:
		return {"ok": false, "message": "正在进入游戏..."}
	var previous := Wallet.total
	Wallet.set_total(coins)
	var result := _change_scene(_fixture_scene, upgrades, opened_gates, upgrade_levels, tutorial_stage, dialogue_progress)
	if not result.ok:
		Wallet.set_total(previous)
	return result
