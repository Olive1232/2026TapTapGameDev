# 怪物美术交付目录

- `rat/`：老鼠的模型、贴图、材质与动画。
- `cockroach/`：蟑螂的模型、贴图、材质与动画。

目录中的 `.gitkeep` 仅用于保留交付位置，可在放入实际美术文件后删除。
素材文件使用小写下划线命名，例如 `rat.glb`、`rat_albedo.png`。

当前老鼠使用 `scenes/enemies/rat_visual.tscn` 与 `scripts/enemies/rat_visual.gd` 生成低多边形模型，包含灰色身体、浅色腹部、尖鼻、耳朵、眼睛、胡须、四爪及三段尾巴；活体有呼吸、嗅探、眨眼、摆耳、走路和尾巴动画，尸体复用模型并闭眼停止动画。公共网格与基础材质缓存共享，每只老鼠的毛色和受击材质独立。

`MonsterData.visual_scene` 是可选模型入口，老鼠资源已经配置。表现根节点可实现 `configure(dimensions, material, is_corpse)` 接口，在入树前接收当前尺寸、独立的主材质和尸体状态。模型只负责表现；碰撞、血量、移动、尸体价值与抓取继续由原有脚本管理。未配置模型的怪种继续使用原有方块外观。

现有数据分别为 `resources/enemies/monster_rat.tres` 和 `monster_cockroach.tres`。
当前正式世界模型位于 `assets/map_origin.glb`。早期 GridMap 测试场景与网格库已于 2026-10-08 按用户要求移除。
