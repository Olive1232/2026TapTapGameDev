class_name HitInfo
extends RefCounted

## 一次命中的完整描述，在剑 → 敌人 → 障碍 之间传递。
##
## 用 tags 而不是枚举，是为了让"火剑能烧藤蔓"这类规则靠标签匹配实现，
## 而不是写成 `if sword == fire_sword` 的分支。

## 本次命中的伤害值。
var damage: float = 0.0
## 伤害来源（通常是玩家或剑的持有者）。可为 null。
var source: Node3D = null
## 伤害标签，如 ["physical"]、["physical", "fire"]。
var tags: PackedStringArray = PackedStringArray()
## 击退方向与力度（世界坐标）。
var knockback: Vector3 = Vector3.ZERO
## 命中点世界坐标（用于生成火花与飘字）。
var hit_position: Vector3 = Vector3.ZERO


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func _to_string() -> String:
	# 三分支都返回 String，避免 "ternary values not mutually compatible" 警告。
	var src := "<null>"
	if source != null:
		src = source.name
	return "HitInfo(dmg=%.1f, tags=%s, from=%s)" % [damage, str(tags), src]
