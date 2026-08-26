extends Node2D
## 飞向金币UI的金币特效：由 BuildingBlock 在砸碎方块时生成数枚。
## 每枚金币从出生点沿抛物线弧线（二次贝塞尔）加速飞往左上角金币徽章，
## 边飞边逐渐缩小，落到目标即消失。不做物理掉落，符合"破坏反馈=破碎/粉碎"取向。

var end_pos: Vector2 = Vector2.ZERO   # 目标：金币UI徽章中心（世界≈屏幕坐标）
var delay: float = 0.0                # 起飞延迟（秒），用于错峰
var spread: float = 1.0               # 弧线高低差异（随机），让每枚轨迹不太一样

const FLIGHT_DURATION := 0.34         # 单枚飞行时长
const ARC_BASE := 70.0                # 弧线基础上抛高度

var _start: Vector2
var _ctrl: Vector2


func _ready() -> void:
	add_to_group(&"in_game_entity")   # 归入"场上临时实体"组，重置时统一清理
	_start = position
	# 弧线控制点：取起点与终点连线中点的上方，制造抛物线；spread 制造高低差异
	var mid := (_start + end_pos) * 0.5
	_ctrl = mid + Vector2(0.0, -1.0) * (ARC_BASE + 110.0 * spread)
	var tween := create_tween()
	tween.tween_interval(delay)                               # 错峰
	tween.tween_method(_advance, 0.0, 1.0, FLIGHT_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # 越飞越快，加速冲向UI
	tween.finished.connect(queue_free)


# 飞行进度：t 从 0 → 1，采样二次贝塞尔保证弧线路径；同时逐渐缩小、末端淡出。
func _advance(t: float) -> void:
	var inv := 1.0 - t
	position = inv * inv * _start + 2.0 * inv * t * _ctrl + t * t * end_pos
	# 边飞边缩小（先快后慢）：初始 1.0 → 接近 0
	var st := 1.0 - pow(1.0 - t, 2.0)
	scale = Vector2.ONE * lerpf(1.0, 0.12, st)
	# 末端淡出，让落地更平滑
	modulate.a = lerpf(1.0, 0.7, pow(t, 3.0))


func _draw() -> void:
	# 金币：金色圆底 + 暗色描边
	var r := 8.0
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.82, 0.25))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, Color(0.72, 0.5, 0.08), 2.0)