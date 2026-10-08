extends HBoxContainer

## 右上角金钱显示。
##
## 只订阅 EventBus.wallet_changed 一个信号——钱包是唯一数据源，
## 本节点不缓存金额、也不主动查询 Wallet，避免出现两份状态。
##
## 挂载位置：HUD（CanvasLayer）下，锚定右上角。

## 数字格式。默认纯十进制，将来若要"1.2万"这类缩写，改这里。
@export var number_format: String = "%d"

## 数字文本节点。留空则自动找名为 Count 的子节点。
@export var count_label_path: NodePath

var _label: Label
var _last_total: int = -1


func _ready() -> void:
	# 优先用场景唯一名 %Count（在 .tscn 里勾了 unique_name_in_owner），
	# 它对节点层级变动免疫；找不到再退回显式路径。
	# 早期版本这里写的是 get_node_or_null("Count")，但 Count 其实在 Panel/Row/ 下，
	# 于是静默失败 → 数字永远停在 0。
	_label = get_node_or_null(^"%Count") as Label
	if _label == null and not count_label_path.is_empty():
		_label = get_node_or_null(count_label_path) as Label
	if _label == null:
		push_warning("MoneyUI：找不到显示数字的 Label。请确认场景里有名为 Count 的节点，并勾选 unique_name_in_owner。")
		return
	EventBus.wallet_changed.connect(_on_wallet_changed)
	# 用当前值初始化，避免开场显示 0 而实际不为 0。
	_set_display(Wallet.total)


func _exit_tree() -> void:
	# 场景切换时断开，防止信号连到已释放的节点。
	if EventBus.wallet_changed.is_connected(_on_wallet_changed):
		EventBus.wallet_changed.disconnect(_on_wallet_changed)


func _on_wallet_changed(total: int, _delta: int) -> void:
	_set_display(total)


func _set_display(total: int) -> void:
	if _label == null or total == _last_total:
		return
	_last_total = total
	_label.text = number_format % total


## 供调试/测试使用：立刻刷新显示。
func refresh() -> void:
	if _label != null:
		_label.text = number_format % Wallet.total
		_last_total = Wallet.total
