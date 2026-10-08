class_name ShopItemData
extends Resource

## 商品配置。先交付油，价格 / 重量 / 占位颜色在 .tres 中设置。
@export var id: StringName = &"oil"
@export var display_name: String = "油"
@export_range(1, 1000000, 1) var price: int = 5
@export_range(0.0, 10.0, 0.1) var weight: float = 0.3
@export var tint := Color(0.85, 0.62, 0.12)
@export var upgrade_tag: String = "oil"


func is_supported() -> bool:
	return price > 0 and upgrade_tag == "oil"


func make_upgraded_sword(base: SwordData) -> SwordData:
	if base == null or not is_supported():
		return null
	var result := base.duplicate() as SwordData
	result.upgrade_tags = base.upgrade_tags.duplicate()
	if not result.upgrade_tags.has(upgrade_tag):
		result.upgrade_tags.append(upgrade_tag)
	result.id = StringName(str(base.get_id()) + "_oil")
	result.display_name = base.display_name + " · 涂油"
	result.tint = Color(0.88, 0.74, 0.40)
	return result
