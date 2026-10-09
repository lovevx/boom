extends Node2D
## 金币弹出提示（视觉特效）：在建筑被毁的位置弹出 "+N 金币"。
## 金币数量要明显：金色圆形徽章 + 大号数字，向上飘并淡出后自毁。
## 不做物理掉落，纯 UI 式浮动，符合"破坏反馈=破碎/粉碎"的取向。

var amount: int = 0          # 本次产出的金币数（由生成方在 add_child 前设置）
var _gold: Color = Color(1.0, 0.82, 0.25)
var _gold_dark: Color = Color(0.72, 0.5, 0.08)


func _ready() -> void:
	add_to_group(&"in_game_entity")   # 归入"场上临时实体"组，重置时统一清理
	# 初始缩放/透明度，用于"弹出"的放大感
	scale = (Vector2.ONE if Presentation.reduced_motion else Vector2(0.8, 0.8))
	# 上飘并淡出
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + Vector2(0.0, -12.0 if Presentation.reduced_motion else -48.0), 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.12)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tween.finished.connect(queue_free)


func _draw() -> void:
	draw_texture_rect(Presentation.icon("coin"),Rect2(-12,-12,24,24),false)
	var text := "+%d" % amount
	draw_string_outline(Presentation.NUMBERS,Vector2(17,8),text,HORIZONTAL_ALIGNMENT_LEFT,-1,24,4,Presentation.PROFILE.ink)
	draw_string(Presentation.NUMBERS,Vector2(17,8),text,HORIZONTAL_ALIGNMENT_LEFT,-1,24,Presentation.PROFILE.gold)


