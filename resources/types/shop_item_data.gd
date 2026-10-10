class_name ShopItemData
extends Resource

## 商品配置。效果、价格、购买上限与占位颜色在 .tres 中设置。
enum UpgradeTarget { SWORD, HOLE, GRABBER }
const MAX_INT := 9223372036854775807
## 保证当前 10 + 5x 价格与等级在 int64 范围内；不是玩法购买次数上限。
const MAX_CORPSE_VALUE_LEVEL := 1844674407370955159
const MAX_GOLDEN_COIN_LEVEL := 20
@export var id: StringName = &"oil"
@export var display_name: String = "油"
@export_multiline var description: String = ""
@export_range(1, 1000000, 1) var price: int = 5
@export_range(0, 1000000, 1) var price_step: int = 0
@export_range(0.0, 10.0, 0.1) var weight: float = 0.3
@export var tint := Color(0.85, 0.62, 0.12)
@export var upgrade_tag: String = "oil"
@export var upgrade_target: UpgradeTarget = UpgradeTarget.SWORD
## 0 表示可重复升级不设购买次数上限。
@export_range(0, 100, 1) var purchase_limit: int = 1


func is_repeatable() -> bool:
	return upgrade_target == UpgradeTarget.HOLE and upgrade_tag in ["corpse_value", "golden_coin"]


static func get_level_limit(tag: String) -> int:
	match tag:
		"corpse_value":
			return MAX_CORPSE_VALUE_LEVEL
		"golden_coin":
			return MAX_GOLDEN_COIN_LEVEL
	return -1


func get_level_description(level: int) -> String:
	if upgrade_tag == "golden_coin":
		return "等级 %d/%d · 点金概率 %d%%" % [level, MAX_GOLDEN_COIN_LEVEL, level * 5]
	return "等级 %d · 尸体价值 +%d" % [level, level]


func get_price(purchase_count: int = 0) -> int:
	if price <= 0 or price_step < 0 or purchase_count < 0:
		return -1
	if price_step > 0:
		@warning_ignore("integer_division")
		var maximum_count := (MAX_INT - price) / price_step
		if purchase_count > maximum_count:
			return -1
	return price + price_step * purchase_count


func is_supported() -> bool:
	if price <= 0 or price_step < 0 or purchase_limit < 0 or (purchase_limit == 0 and not is_repeatable()):
		return false
	return (upgrade_target == UpgradeTarget.SWORD and upgrade_tag == "oil") or (upgrade_target == UpgradeTarget.HOLE and upgrade_tag in ["corpse_return", "corpse_value", "golden_coin"]) or (upgrade_target == UpgradeTarget.GRABBER and upgrade_tag == "charged_throw")


func make_upgraded_sword(base: SwordData) -> SwordData:
	if base == null or not is_supported() or upgrade_target != UpgradeTarget.SWORD:
		return null
	var result := base.duplicate() as SwordData
	result.upgrade_tags = base.upgrade_tags.duplicate()
	if not result.upgrade_tags.has(upgrade_tag):
		result.upgrade_tags.append(upgrade_tag)
	result.id = StringName(str(base.get_id()) + "_oil")
	result.display_name = base.display_name + " · 涂油"
	result.tint = Color(0.88, 0.74, 0.40)
	return result
