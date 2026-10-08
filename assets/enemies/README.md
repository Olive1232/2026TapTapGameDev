# 怪物美术交付目录

- `rat/`：老鼠的模型、贴图、材质与动画。
- `cockroach/`：蟑螂的模型、贴图、材质与动画。

目录中的 `.gitkeep` 仅用于保留交付位置，可在放入实际美术文件后删除。
素材文件使用小写下划线命名，例如 `rat.glb`、`rat_albedo.png`。

当前怪物仍使用程序化占位方块，`MonsterData` 尚无模型场景字段。
放入美术文件不会自动替换游戏中的模型；正式接入时需另行增加本体与尸体的表现入口。

现有数据分别为 `resources/enemies/monster_rat.tres` 和 `monster_cockroach.tres`。
当前世界模型位于 `assets/prototypes/map/map_v2.fbx`。早期 GridMap 测试场景与网格库已于 2026-10-08 按用户要求移除。
