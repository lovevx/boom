extends Node
## 手感中枢（autoload）：统一处理"先蓄后发"的破坏反馈分层。
## 负责三档反馈的"时间缩放 / 顿帧 / 慢动作 / 震屏"，保证互斥不叠加。
##   档1 受击：极短顿帧 + 弱震（白闪/裂纹由 BuildingBlock 自己画）。
##   档2 单块碎裂：短顿帧 + 中震（粉尘/冲击环由 BuildingBlock 自己画）。
##   档3 连锁：慢动作 + 大震屏（炸弹强事件直接调、塌塔级联由 BuildingSetup 汇总后调）。
## 安全原则：任何缩放请求都必须带唯一 key，后到覆盖旧请求，并在时长结束后回到 1.0；
## 由 _process 看门狗兜底，绝不把 Engine.time_scale 残留在非 1.0，避免挂机模式卡死。

# —— 三档时间缩放参数：格式均统一为 Vector2(目标 time_scale, 持续真实秒数) ——
# 档1/2 是"顿帧"（极短到短），档3 是"慢动作"（短）。数值来自 P0 规格。
const LEVEL1_HIT_STOP := Vector2(0.25, 0.03)   # 档1 受击：缩到 0.25，极短顿帧 0.03s（轻微）
const LEVEL2_HIT_STOP := Vector2(0.35, 0.07)   # 档2 碎裂：缩到 0.35，短顿帧 0.07s
const LEVEL3_SLOWMO   := Vector2(0.35, 0.30)   # 档3 连锁：缩到 0.35，慢动作 0.30s

# —— 三档震屏强度 ——
const SHAKE_1 := Vector2(5.0, 0.15)   # [intensity, duration]
const SHAKE_2 := Vector2(9.0, 0.30)
const SHAKE_3 := Vector2(14.0, 0.45)
const SHAKE_MAX := Vector2(20.0, 0.50)   # P2：链式大塌塔（一次塌落块数越多）的震屏上限，随同瞬摧毁数逼近
const SLOWMO_MAX := Vector2(0.32, 0.42)  # P2：大塌塔慢动作上限（更多块→更久更缓，克制，保挂机节奏）

const TIME_SCALE_IDLE_GUARD_MS := 600   # 看门狗：超过该时长仍未复位则强制拉回 1.0（兜底从不会触发）
const STRONG_SWALLOW_MS := 450          # 档3 强事件后该时间内的链式计数被吞掉，避免炸弹二次叠加

var _active_level := 0
var _last_slowmo_ms := -100000
var _last_impact_shake_ms := -100000
var _key_seq := 0                       # 唯一 key 递增序列
var _active_key := ""                    # 当前生效的缩放请求 key（后到覆盖）
var _scale_deadline_ms := 0              # 当前缩放应复位的真实时刻(ms)，看门狗用

var _strong_time_ms := -1000000          # 最近一次档3发生时刻(ms)，用于吞掉强事件后的链式反馈


func _ready() -> void:
	# autoload 常驻：即使用户开了面板/切场景，看门狗也照常跑，确保 time_scale 复位
	process_mode = Node.PROCESS_MODE_ALWAYS


# 对外入口：按档位触发"时间缩放 + 震屏"。level 1/2/3。
# 后到的更强/相近调用会用新 key 覆盖旧的恢复任务，避免多目标重复顿帧叠加。
func impact(level: int) -> void:
	if level <= 0 or Presentation.reduced_motion:
		return
	var now := Time.get_ticks_msec()
	if _active_level > level and now < _scale_deadline_ms:
		return
	if level >= 3:
		_strong_time_ms = now
		if now - _last_slowmo_ms >= Presentation.PROFILE.slowmo_cooldown_ms:
			_last_slowmo_ms = now
			_active_level = level
			_apply_scale(_scale_params(level))
	else:
		_active_level = level
		_apply_scale(_scale_params(level))
	if now - _last_impact_shake_ms >= 120:
		_last_impact_shake_ms = now
		_shake(level)


func resolve_chain(count: int) -> void:
	if count <= 0 or _time_since_strong_ms() < STRONG_SWALLOW_MS:
		return
	impact(3 if count >= 3 else 2)


func _apply_scale(scale_data: Vector2) -> void:
	var key := _new_key()
	Engine.time_scale = scale_data.x
	_scale_deadline_ms = Time.get_ticks_msec() + int(scale_data.y * 1000.0)
	_restore_after(key, scale_data.y)


# 按强度直接触发震屏（补强度向量版，供 resolve_chain 精确递增用）。
func _apply_shake(shake: Vector2) -> void:
	var cam: Node = get_tree().current_scene.get_node_or_null("MainCamera")
	if cam == null or not cam.has_method("shake"):
		return
	cam.call("shake", shake.x, shake.y)


# 强制复位（供重置/切场景安全兜底调用；通常看门狗已覆盖，这里双保险）。
func reset() -> void:
	_active_level = 0
	_active_key = ""
	_scale_deadline_ms = 0
	Engine.time_scale = 1.0


func _scale_params(level: int) -> Vector2:
	match level:
		1: return LEVEL1_HIT_STOP
		2: return LEVEL2_HIT_STOP
		_: return LEVEL3_SLOWMO


func _shake(level: int) -> void:
	var cam: Node = get_tree().current_scene.get_node_or_null("MainCamera")
	if cam == null or not cam.has_method("shake"):
		return
	var s: Vector2
	match level:
		1: s = SHAKE_1
		2: s = SHAKE_2
		_: s = SHAKE_3
	cam.call("shake", s.x, s.y)


# ==================== P2：落地微震（落定 + 连锁微响应） ====================
# 低强度轻震，不做时间缩放（避免拖慢挂机连击节奏；节奏本身由 P2 的窄蓄力控制在受限范围）。
# 内置同帧去重窗口：80ms 内只发一次，连锁塔底多块连续落定时只震一次，杜绝震屏叠加发疯。
# 与 P0 各档震屏互补共存：P2 管每块落定微响应，P0 管连锁大震屏，去重窗口互不干扰。
const SHAKE_LANDING := Vector2(3.5, 0.14)   # [intensity, duration]
var _last_landing_shake_ms := -1000000

func micro_shake() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_landing_shake_ms < 80:
		return
	_last_landing_shake_ms = now
	var cam: Node = get_tree().current_scene.get_node_or_null("MainCamera")
	if cam == null or not cam.has_method("shake"):
		return
	cam.call("shake", SHAKE_LANDING.x, SHAKE_LANDING.y)


func _new_key() -> String:
	_key_seq += 1
	return str(_key_seq)


# 创建真实时间的恢复任务（ignore_time_scale=true，改 time_scale 不会拖慢它）。
# 若期间被更新的 key 覆盖，则本次是空操作，只由最新 key 负责复位。
func _restore_after(key: String, duration: float) -> void:
	_active_key = key
	var timer := get_tree().create_timer(duration, true, false, true)
	await timer.timeout
	if _active_key != key:
		return   # 已被更高优先级的请求覆盖，留给它复位
	_active_key = ""
	_active_level = 0
	Engine.time_scale = 1.0


func _time_since_strong_ms() -> int:
	return Time.get_ticks_msec() - _strong_time_ms


# 看门狗：极强兜底，任何异常（await 被打断等）下也强制把 time_scale 拉回 1.0。
func _process(_delta: float) -> void:
	if Engine.time_scale == 1.0:
		return
	if _active_key.is_empty() or Time.get_ticks_msec() >= _scale_deadline_ms + TIME_SCALE_IDLE_GUARD_MS:
		_active_key = ""
		Engine.time_scale = 1.0