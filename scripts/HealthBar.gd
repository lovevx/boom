extends Node2D
## 方块血条：紧凑显示在方块顶部，默认隐藏。
## 受伤时显示 2.5 秒；悬停显示（满血不显示）；血量 ≤ 30% 常驻。
## 含"延迟条"：受击时当前条立即缩短，延迟条先停 0.3 秒再于 0.5 秒内缓慢追上。

const BAR_WIDTH := 32.0        # 血条宽 = 方块宽 40 × 0.8
const BAR_HEIGHT := 5.0        # 血条高
const LOW_HP_RATIO := 0.30     # 低血量阈值（常驻显示）
const SHOW_DURATION := 2.5     # 受伤后显示时长（秒）
const DELAY_AFTER := 0.3       # 延迟条开始缩短前的停顿
const DELAY_DURATION := 0.5    # 延迟条追赶到当前条的时长

var max_hp: float = 100.0   # 由生成方 setup() 注入

var _cur_ratio: float = 1.0   # 当前血量 / 最大血量
var _hovered := false         # 鼠标是否悬停
var _low := false             # 是否低血量（常驻）
var _delay_tween: Tween       # 延迟条追尾动画

@onready var _bg: ColorRect = $Background
@onready var _delay: ColorRect = $DelayBar
@onready var _current: ColorRect = $CurrentBar
var _timer: Timer   # 受伤显示计时器


func setup(p_max_hp: float) -> void:
	max_hp = maxf(p_max_hp, 0.001)


func _ready() -> void:
	# 计时器：时间到重新检查可见性（此时若仍悬停/低血则保持显示）
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = SHOW_DURATION
	_timer.timeout.connect(_refresh_visible)
	add_child(_timer)
	_layout_bars()
	_apply_current_bar()
	_refresh_visible()


# 方块 ask 扣血后调用：更新当前条/颜色/延迟条，并触发显示逻辑。
func notify_damage(new_hp: float) -> void:
	_cur_ratio = clampf(new_hp / maxf(max_hp, 0.001), 0.0, 1.0)
	_apply_current_bar()
	_animate_delay_bar()
	_low = _cur_ratio <= LOW_HP_RATIO
	_refresh_visible()
	_timer.start()   # 重新计时显示 2.5 秒


func set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_refresh_visible()


# 可见性 = 低血常驻 OR 悬停(且非满血) OR 受伤计时中。
func _refresh_visible() -> void:
	var hover_show: bool = _hovered and _cur_ratio < 1.0
	visible = _low or hover_show or _timer.time_left > 0.0


# 把三根横条统一布局到方块顶部、居中（本地坐标）。
func _layout_bars() -> void:
	var y := -BAR_HEIGHT   # 贴在方块上缘
	_bg.position = Vector2(-BAR_WIDTH / 2.0, y)
	_delay.position = Vector2(-BAR_WIDTH / 2.0, y)
	_current.position = Vector2(-BAR_WIDTH / 2.0, y)


# 当前血量条即时更新宽度并改色。
func _apply_current_bar() -> void:
	var w := BAR_WIDTH * _cur_ratio
	_current.size = Vector2(w, BAR_HEIGHT)
	_current.color = _color_for(_cur_ratio)


# 延迟条：颜色固定半透黄，先停 0.3 秒再在 0.5 秒内缩小到当前条宽度（黄色尾巴）。
func _animate_delay_bar() -> void:
	if _delay_tween and _delay_tween.is_valid():
		_delay_tween.kill()
	var new_w := BAR_WIDTH * _cur_ratio
	_delay_tween = create_tween()
	_delay_tween.tween_interval(DELAY_AFTER)
	_delay_tween.tween_property(_delay, "size:x", new_w, DELAY_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _color_for(ratio: float) -> Color:
	if ratio >= 0.6:
		return Color(0.3, 0.9, 0.3)    # 绿
	if ratio >= 0.3:
		return Color(1, 0.85, 0.2)     # 黄
	return Color(1, 0.25, 0.2)         # 红