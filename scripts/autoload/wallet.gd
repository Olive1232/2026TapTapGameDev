extends Node

## 钱包（autoload 名：Wallet）——玩家持有的金钱。
##
## 当前路线：增量外壳 + 战斗内核，不做挂机产出或大数运算。
## 钱包仍是一个 int，由 SaveGame 手动保存、GameFlow 新建或载入。
## 钱币的"品质"只是外观不同，价值统一累加到这个总数里。
##
## 全局变化通过 EventBus.wallet_changed(total, delta) 广播，UI 订阅那一个信号即可。

## 当前金钱。禁止外部直接写，一律走 add / spend / set_total。
var total: int = 0


## 加钱。返回加完之后的总数。
func add(amount: int) -> int:
	if amount == 0:
		return total
	total += amount
	EventBus.wallet_changed.emit(total, amount)
	return total


## 尝试花钱。钱不够则**不扣款**并返回 false。
## 返回 true 表示扣款成功。
func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if total < amount:
		# 失败也要广播一次，让 UI 能据此播放"钱不够"的反馈。
		EventBus.wallet_changed.emit(total, 0)
		return false
	total -= amount
	EventBus.wallet_changed.emit(total, -amount)
	return true


## 钱是否够。
func can_afford(amount: int) -> bool:
	return total >= amount


## 替换钱包总额（新建 / 载入），同步通知 HUD。
func set_total(amount: int) -> void:
	var previous := total
	total = maxi(0, amount)
	EventBus.wallet_changed.emit(total, total - previous)


## 清空（新建游戏或调试用，不删除磁盘存档）。
func reset() -> void:
	set_total(0)
