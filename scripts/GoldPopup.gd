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
	scale = Vector2(0.5, 0.5)
	# 上飘并淡出
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + Vector2(0.0, -60.0), 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.12)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tween.finished.connect(queue_free)


func _draw() -> void:
	# 徽章：金色圆底 + 描边
	const RADIUS := 24.0
	draw_circle(Vector2.ZERO, RADIUS, _gold)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 40, _gold_dark, 4.0)
	# 数字写在金币右侧外部，字体自适应避免两位数截断
	var font: Font = ThemeDB.fallback_font
	var text := "+%d" % amount
	var fs: int = 30
	var origin := Vector2(RADIUS + 10.0, 9.0)
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var width: int = int(size.x + 8.0)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, width, fs, 6, _gold_dark)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, width, fs, Color.WHITE)