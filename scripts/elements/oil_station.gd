extends StaticBody3D

## 免费的测试涂油入口。正式购买油仍由后续商店实现。
func apply_to(sword: Sword) -> bool:
	if sword == null:
		return false
	sword.apply_oil()
	return true
