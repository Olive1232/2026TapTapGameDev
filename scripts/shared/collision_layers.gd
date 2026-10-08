class_name CollisionLayers
extends RefCounted

## 物理碰撞层的唯一定义源。
##
## 场景里的数值（1、2、4…）容易写错且看不出来，一律用这里的常量。
## 在编辑器里设置 collision_layer / collision_mask 时，对照下面的位号勾选。
##
##   位 1 (值 1)   WORLD    静态地形、墙、地板
##   位 2 (值 2)   PLAYER   玩家角色
##   位 3 (值 4)   ENEMY    生物、可被打的靶子
##   位 4 (值 8)   PICKUP   尸体、钱币、锻造物品
##   位 5 (值 16)  WEAPON   剑的伤害区域（Area3D 用）
##   位 6 (值 32)  ELEMENT  火源与可燃物的接触区域
##
## 注意：剑的伤害 Area3D 监听 ENEMY | WORLD，命中检测由
## sword.gd 主动轮询 get_overlapping_bodies() 完成，避免 body_entered
## 信号在高速挥砍时漏触发。

const WORLD := 1 << 0
const PLAYER := 1 << 1
const ENEMY := 1 << 2
const PICKUP := 1 << 3
const WEAPON := 1 << 4
const ELEMENT := 1 << 5
