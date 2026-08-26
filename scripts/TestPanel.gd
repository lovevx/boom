extends CanvasLayer
## 测试面板（仅开发调试用）：一键为 GoldManager 增加指定数量金币，方便测试升级与金币相关功能。

const OnboardingScript := preload("res://scripts/Onboarding.gd")

var _toggle: Button          # "测试"开关按钮
var _panel: PanelContainer   # 面板容器（默认收起）
var _coin: Label             # 面板内的金币显示
var _rp: Label               # 面板内的转生币显示

const PANEL_H := 320.0       # 面板可视高度；内容超高时滚动查看


# 深色半透明面板底板样式（与升级面板一致）。
func _make_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.14, 0.94)
	sb.border_color = Color(0.35, 0.30, 0.18, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 16.0
	return sb


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 技能树打开时游戏暂停，测试面板仍可点击使用
	layer = 90   # 最高 UI 层级：盖过技能树页面(15)/新手引导(25)，仅低于过场渐隐(100)
	_build_ui()
	GoldManager.gold_changed.connect(func(_t: int) -> void: _refresh())
	ReincarnationManager.reincarnation_changed.connect(_refresh)
	_refresh()


func _build_ui() -> void:
	# —— 左下角"测试"开关按钮 ——
	_toggle = Button.new()
	_toggle.text = "测试"
	_toggle.position = Vector2(16, 1080 - 64)
	_toggle.size = Vector2(100, 48)
	_toggle.add_theme_font_size_override("font_size", 22)
	_toggle.pressed.connect(_on_toggle)
	add_child(_toggle)

	# —— 测试面板（默认收起） ——
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 1080 - 64 - PANEL_H)
	_panel.custom_minimum_size = Vector2(320, 0)
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_panel.hide()
	add_child(_panel)

	# 可滚动容器：内容超出面板可视高度时滚轮滑动查看
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, PANEL_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "测试面板"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	# 面板内"关闭"按钮：保证面板无论是否盖住开关都能关闭
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(72, 40)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(func() -> void: _panel.hide())
	header.add_child(close_btn)

	# 面板内金币显示
	_coin = Label.new()
	_coin.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_coin)

	# 面板内转生币显示
	_rp = Label.new()
	_rp.add_theme_font_size_override("font_size", 22)
	_rp.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	vbox.add_child(_rp)

	# 增加金币的快捷按钮
	for amount in [10, 100, 1000, 10000]:
		var btn := Button.new()
		btn.text = "增加 %d 金币" % amount
		btn.custom_minimum_size = Vector2(0, 44)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(func() -> void: GoldManager.add_gold(amount))
		vbox.add_child(btn)

	# 重置新手引导：清除完成标记并从头重放引导
	var reset_btn := Button.new()
	reset_btn.text = "重置新手引导"
	reset_btn.custom_minimum_size = Vector2(0, 44)
	reset_btn.add_theme_font_size_override("font_size", 20)
	reset_btn.pressed.connect(func() -> void: OnboardingScript.reset_and_restart())
	vbox.add_child(reset_btn)

	# 增加转生币的快捷按钮（调试转生系统用）
	for amount in [1, 10, 100]:
		var btn := Button.new()
		btn.text = "增加 %d 转生币" % amount
		btn.custom_minimum_size = Vector2(0, 44)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(func() -> void: ReincarnationManager.add_reincarnation_points(amount))
		vbox.add_child(btn)


# 面板开关：切换显示。
func _on_toggle() -> void:
	_panel.visible = not _panel.visible


# 刷新面板内的金币 / 转生币显示。
func _refresh() -> void:
	if not is_instance_valid(_coin):
		return
	_coin.text = "金币: %d" % GoldManager.total_gold
	if is_instance_valid(_rp):
		_rp.text = "转生币: %d" % ReincarnationManager.reincarnation_points
