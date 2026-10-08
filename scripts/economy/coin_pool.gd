extends Node

## 钱币对象池（autoload 名：CoinPool）。
##
## 洞一次可能喷出几十上百枚币，频繁 instantiate/free 会造成卡顿与内存抖动
## （R2 风险：800 枚币要稳 60fps）。这里预生成并复用。
##
## 池自身跨场景保留；钱币属于当前场景，场景退出时清除池中的引用。

const COIN_SCENE := preload("res://scenes/economy/coin.tscn")

## 场上同时存在的钱币上限。超过则不再新建，复用最早的。
@export var max_active: int = 800

var _free: Array[Coin] = []
var _active: Array[Coin] = []
## 钱币的父节点（场景根）。为 null 时池自己当父节点。
var _host: Node = null


## 让钱币挂到某个节点下（通常是当前场景根），便于随场景一起释放。
func set_host(node: Node) -> void:
	if is_instance_valid(_host):
		if _host == node:
			return
		if _host.tree_exiting.is_connected(_on_host_tree_exiting):
			_host.tree_exiting.disconnect(_on_host_tree_exiting)
	# 切换到另一个仍在树中的场景时，也不能留下旧场景的钱币。
	for coin in _active + _free:
		if is_instance_valid(coin):
			coin.queue_free()
	_active.clear()
	_free.clear()
	_host = node
	if is_instance_valid(_host):
		_host.tree_exiting.connect(_on_host_tree_exiting)


func _on_host_tree_exiting() -> void:
	# 钱币由场景释放，autoload 只清引用；重载后的新场景重新注册 host。
	_active.clear()
	_free.clear()
	_host = null


func _on_coin_tree_exiting(coin: Coin) -> void:
	# 同时覆盖钱币被其他系统单独销毁的情况。
	_active.erase(coin)
	_free.erase(coin)


## 取一枚钱币。会自动加入场景树并激活。
func acquire() -> Coin:
	var coin: Coin
	while not _free.is_empty():
		var candidate: Variant = _free.pop_back()
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			coin = candidate
			break
	if coin == null:
		if _active.size() >= max_active:
			# 到上限了就强行回收最老的一枚，避免无限增长。
			coin = _active.pop_front()
			coin.reset_for_pool()
		else:
			coin = COIN_SCENE.instantiate() as Coin
			coin.tree_exiting.connect(_on_coin_tree_exiting.bind(coin))
			var parent := _host if is_instance_valid(_host) and not _host.is_queued_for_deletion() else self
			parent.add_child(coin)
	coin.visible = true
	_active.append(coin)
	return coin


## 归还一枚钱币。
func release(coin: Coin) -> void:
	if not is_instance_valid(coin) or coin.is_queued_for_deletion():
		return
	coin.reset_for_pool()
	var idx := _active.find(coin)
	if idx >= 0:
		_active.remove_at(idx)
	if not _free.has(coin):
		_free.append(coin)


## 当前场上活跃的钱币数。
func active_count() -> int:
	return _active.size()


## 池里空闲的钱币数。
func free_count() -> int:
	return _free.size()


## 回收场上全部钱币（重开一局 / 换房间用）。
func release_all() -> void:
	for i in range(_active.size() - 1, -1, -1):
		release(_active[i])
