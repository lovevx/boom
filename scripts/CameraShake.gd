extends Camera2D
## 震屏效果：在 duration 秒内随机偏移 Camera2D.offset 实现，随时间衰减。
## P3 追加极缓慢镜头漂移：只在 baseline(_base_offset) 上做超低频、超小幅度的周期性上下摆动，
## 与震屏(在 baseline 上叠加随机偏移)互不打扰；复位保护见 reset_drift()。
## 注意：相机本身不随光标移动（背景视差由 Background.gd 用光标独立驱动，避免"大楼在动"）。

var _last_shake_ms := -100000
var _intensity: float = 0.0
var _duration: float = 0.0
var _elapsed: float = 0.0
var _base_offset := Vector2.ZERO

# —— P3：极缓慢镜头漂移参数（氛围用，务必极小幅度、低频，避免影响瞄准/震屏）——
const DRIFT_AMPLITUDE := 7.0    # 上下漂移峰值(px)：极小，肉眼近乎无感；不改变 limits/定位核心
const DRIFT_LEG_S := 4.0        # 到端点/回中的每段时长(s)：一个完整往复周期约 16s，超低频
var _drift_tween: Tween = null
var _orig_base := Vector2.ZERO  # 初始 baseline，复位/切场景时归位到它


func _ready() -> void:
	_base_offset = offset
	_orig_base = _base_offset


func shake(intensity: float, duration: float) -> void:
	if Presentation.reduced_motion or Presentation.shake_strength <= 0.0:
		offset = Vector2.ZERO
		return
	var now := Time.get_ticks_msec()
	if now - _last_shake_ms < 90:
		return
	_last_shake_ms = now
	_intensity = maxf(intensity * Presentation.shake_strength, _intensity * 0.5)
	_duration = duration
	_elapsed = 0.0
	set_process(true)


func _process(delta: float) -> void:
	if Presentation.reduced_motion:
		offset = Vector2.ZERO
		_duration = 0.0
	if _duration <= 0.0:
		_elapsed = 1.0
		_offset_reset()
		return

	_elapsed += delta / maxf(Engine.time_scale, 0.001)
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	# 强度随时间线性衰减
	var strength := _intensity * (1.0 - t)
	offset = _base_offset + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength

	if t >= 1.0:
		_offset_reset()


func _offset_reset() -> void:
	offset = _base_offset
	set_process(false)


# —— P3：极缓慢镜头漂移 ——
# 只在 baseline(_base_offset.y) 上做周期性摆动，不动 global_position（不产生可见视差）。
# 震屏 _process 每次以 `_base_offset + 随机偏移` 覆写 offset，因此漂移(baseline)与震屏天然叠加互不打架。
func _start_drift() -> void:
	if _drift_tween != null and _drift_tween.is_valid():
		return
	var base_y: float = _orig_base.y
	var a := DRIFT_AMPLITUDE
	var tween := create_tween()
	_drift_tween = tween
	tween.set_loops()   # 0→+A→0→-A→0… 无限往复
	tween.tween_property(self, "_base_offset:y", base_y + a, DRIFT_LEG_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "_base_offset:y", base_y - a, DRIFT_LEG_S * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "_base_offset:y", base_y, DRIFT_LEG_S * 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# 复位保护：结束漂移并把 baseline 归回初始值（切场景/重置时调用，确保后台归位、无残留偏移）。
func reset_drift() -> void:
	if _drift_tween != null and _drift_tween.is_valid():
		_drift_tween.kill()
	_drift_tween = null
	_base_offset = _orig_base
	offset = _orig_base