extends Node

## 全局事件总线（autoload 名：EventBus）
##
## 契约纪律：系统之间只准通过本总线的信号通信，或调用第 4 节列出的公开方法。
## 禁止 `get_node("../../某个具体路径")` 去抓别的系统——那会让模块无法独立改动。
##
## 命名约定：<主语>_<过去式动词>(载荷)。信号只报告"已经发生的事实"，
## 不表示"请求某人去做某事"；请求走公开方法调用。

# ---- 战斗 / 敌人 ----------------------------------------------------------
## 敌人死亡。此刻尸体尚未生成（生成后补发 corpse_spawned）。
signal enemy_died(enemy: Node3D)
## 敌人被生成（用于房间统计敌人数量）。
signal enemy_spawned(enemy: Node3D)

# ---- 尸体 ----------------------------------------------------------------
## 尸体已生成到世界中。
signal corpse_spawned(corpse: Node3D)
## 尸体被玩家扛起。
signal corpse_grabbed(corpse: Node3D)
## 尸体被玩家放下（未献祭）。
signal corpse_released(corpse: Node3D)
## 尸体被献祭给洞。base_value 是这具尸体的基础价值，洞据此决定涌现多少币。
signal corpse_offered(corpse: Node3D, base_value: int)
## 尸体因超时被回收；所有持有引用的系统必须在此释放。
signal corpse_expired(corpse: Node3D)

# ---- 钱币 / 钱包 ----------------------------------------------------------
## 洞完成一次涌现（总额与币数已确定）。
signal coins_erupted(total_value: int, coin_count: int)
## 单枚钱币被收进钱包（用于音效与飘字）。
signal coin_collected(value: int)
## 钱包总额变化。
signal wallet_changed(total: int, delta: int)

# ---- 商店 / 锻造 ----------------------------------------------------------
## 玩家拿取了货架上的锻造物品。
signal forge_item_grabbed(item: Node3D)
## 强化商品已放到忏悔室前的小台子上。
signal forge_item_placed(item: Node3D)
## 玩家左键砍中了店长（触发锻造流程）。
signal shopkeeper_struck(by: Node3D)
## 店长开始锻造（表现层可用：店长抽搐、光效等）。
signal forge_started(inserted_item: Node3D)
## 店长交付了一把新剑。
signal sword_granted(sword: SwordData)

# ---- 世界 ----------------------------------------------------------------
## 障碍被破除。tag 是被用来破它的标签（如火/雷），便于统计与解锁。
signal obstacle_broken(obstacle: Node3D, tag: StringName)
## 房间内敌人已清空。
signal room_cleared(room: Node3D)
