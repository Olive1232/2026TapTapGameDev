# 回归测试

使用 Godot 4.7.2 独立进程运行 `run_*_regression.gd`，固定 60 FPS。需要存档的测试必须传入独立临时目录，例如：

```sh
Godot --headless --path . --fixed-fps 60 --script res://tests/run_upgrade_save_regression.gd -- --data-dir=/tmp/taptap-upgrade-regression
```

当前正式地图的入口、旧档兼容、交易、献祭、回收、地形通行和裂缝恢复分别由 `run_main_world_*`、`run_rift_recovery_regression.gd` 等专项覆盖。`run_main_world_passages_regression.gd` 用真实 WASD 验证清扫房入口坡道的三条走线、双向移动和实际搬运尸体。回廊已恢复原模型的封闭岩壁；`run_main_world_regression.gd` 比较实际场景与原始导入网格，`run_main_world_return_regression.gd` 验证封闭处无法穿墙、不会误触发回收及其他开放入口正常工作。

`run_main_world_climbing_regression.gd` 直接使用正式地图中倾斜放置的 `FlammableVines`，覆盖三条接近路线、空手及真实搬运尸体、抓附、松键停留、下爬、越过顶部并站稳平台；同时检查藤蔓摆放保持不变。通用 `run_climbing_regression.gd` 还覆盖前倾和后倾、E 松开、遮挡、顶棚、烧毁和暂停。

历史地图的机制测试显式通过 `helpers/legacy_world_fixture.gd` 选择测试入口：

- `basic_rules`、`level_progress`、`map_world`、`throw` 使用现存的历史 `map_world.tscn`。
- `corpse_return`、`room_cleanup`、`upgrade_save`、`corpse_value`、`golden_coin`、`mirror` 使用 `fixtures/three_room_world.tscn`，其布局取自提交 `9a92590`。这份夹具继续引用现行玩家、商店、献祭、元素和回收组件，并保留对应测试的原有断言。

历史测试进程仅替换入口路由；生产 `GameFlow`、主菜单入口、存档允许的场景列表均不修改。夹具在 autoload 注册完成后动态加载。正式地图专项使用原生产流程，验证当前实际入口。

`upgrade_save`、`corpse_value`、`golden_coin`、`mirror` 等支持 `--phase=write` / `--phase=read`，使用相同临时目录在两个独立进程中验证持久化。`level_progress` 对应使用 `write_world` / `read_world` 和 `write_lab` / `read_lab`。
