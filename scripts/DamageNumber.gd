extends Node2D
## 浮动伤害数字（视觉特效）：方块受到攻击时向上飘出伤害数值并淡出。
## 生成方应在 add_child 之前设置 damage / max_hp / is_lethal。
## 动画结束自动 queue_free；用静态计数实现"同一帧多个"的纵向错开。

var damage: float = 0.0    # 本次伤害值
var max_hp: float = 100.0  # 方块最大生命值（用于判断伤害等级）
var is_lethal: bool = false   # 是否一击摧毁（致命一击样式）

# 同一帧内多次生成时按序号递增的纵向错开（防重叠）
static var _count_frame: int = -1
static var _count: int = 0

@onready var _label: Label = $Label


func _ready() -> void:
	if not Presentation.admit(self, "number"):
		queue_free()
		return
	add_to_group(&"in_game_entity")   # 归入"场上临时实体"组，重置时统一清理
	_label.add_theme_font_override("font", Presentation.NUMBERS)
	_configure_label()
	_layout_draw()
	_play_animation()


# 根据伤害等级配置文字颜色 / 字号 / 描边。
func _configure_label() -> void:
	var ratio: float = clampf(damage / maxf(max_hp, 0.001), 0.0, 1.0)
	var color: Color
	var font_size: int

	if is_lethal:
		# 致命一击：大红 + 白色描边 + 加快飘动
		color = Color(1, 0.2, 0.1)
		font_size = 26
		_label.add_theme_color_override("font_outline_color", Color(1, 1, 1))
		_label.add_theme_constant_override("outline_size", 8)
	elif ratio < 0.3:
		color = Color.WHITE              # 普通：白，小号
		font_size = 16
	elif ratio <= 0.7:
		color = Color(1, 0.85, 0.2)      # 中等：黄，中号
		font_size = 18
	else:
		color = Color(1, 0.4, 0.1)       # 高伤害：橙红，大号
		font_size = 22

	_label.add_theme_color_override("font_color", color)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.text = "%d" % roundi(damage)


# 设置生成位置：上方 + 同帧错开偏移 + 致命一击随机旋转。
func _layout_draw() -> void:
	position.y += -20.0 + _claim_stagger_offset()
	if is_lethal:
		rotation = deg_to_rad(randf_range(-10.0, 10.0))


# 同帧内每次生成 y 递增 12px，形成纵向排列。
func _claim_stagger_offset() -> float:
	var frame := Engine.get_process_frames()
	if frame != _count_frame:
		_count_frame = frame
		_count = 0
	var idx := _count
	_count += 1
	return 12.0 * float(idx)


# 动画：弹出缩放 + 上飘 + 末尾淡出，全部使用 Tween。
func _play_animation() -> void:
	var dur: float = 0.4 if is_lethal else 0.6   # 致命更快
	var float_dist: float = (10.0 if Presentation.reduced_motion else randf_range(30.0, 50.0))
	var fade_start: float = dur - 0.2            # 最后 0.2 秒开始淡出
	scale = Vector2.ONE if Presentation.reduced_motion else Vector2(1.15, 1.15)                    # 生成瞬间放大，弹回 1.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # 弹出感
	tween.tween_property(self, "position", position + Vector2(0, -float_dist), dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)   # 先快后慢上飘
	tween.tween_property(self, "modulate:a", 0.0, 0.2).set_delay(fade_start)  # 淡出
	tween.finished.connect(queue_free)   # 结束自毁（或用对象池时可改为隐藏回收）