extends Control
## 生涯统计面板（主菜单独立入口）。
## 全屏暗化 + 居中卡片，展示两个跨局累计统计：击破方块数量、总获取金币。
## 数值只读展示，来源为 GoldManager 的生涯统计（由 SaveManager 独立存档，只增不减）。
## 打开时实时刷新，关闭即隐藏。

# —— 配色（对齐 ReincarnationPanel 风格）——
const C_DIM := Color(0, 0, 0, 0.74)
const C_PANEL_BG := Color(0.10, 0.12, 0.16, 0.98)
const C_HEAD := Color(1, 0.88, 0.4, 1)
const C_TEXT := Color(0.95, 0.95, 0.95, 1)
const C_MUTED := Color(0.72, 0.74, 0.8, 1)
const C_ACCENT := Color(1.0, 0.85, 0.3)

var _blocks_label: Label
var _gold_label: Label


func open() -> void:
	_refresh()
	Presentation.dialog_enter(self)


func close() -> void:
	hide()


func _ready() -> void:
	_build()
	hide()   # 主菜单加载时隐藏，由"生涯统计"按钮打开


# 从 GoldManager 生涯统计刷新两行数字。
func _refresh() -> void:
	_blocks_label.text = "击破方块：%d 块" % GoldManager.stats_blocks_destroyed
	_gold_label.text = "总获取金币：%d" % GoldManager.stats_gold_earned


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 底板：挡住主菜单点击
	var dim := ColorRect.new()
	dim.color = C_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel_size := Vector2(620, 560)
	var scr := get_viewport_rect().size
	var root := Control.new()
	root.position = (scr - panel_size) / 2.0
	root.size = panel_size
	add_child(root)

	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL_BG
	sb.border_width_left = 3; sb.border_width_top = 3
	sb.border_width_right = 3; sb.border_width_bottom = 3
	sb.border_color = C_HEAD
	sb.corner_radius_top_left = 18; sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_left = 18; sb.corner_radius_bottom_right = 18
	bg.add_theme_stylebox_override("panel", sb)
	root.add_child(bg)
	Presentation.bind_dialog.call_deferred(root,panel_size)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 18)
	vbox.add_theme_constant_override("margin_left", 40)
	vbox.add_theme_constant_override("margin_top", 30)
	vbox.add_theme_constant_override("margin_right", 40)
	vbox.add_theme_constant_override("margin_bottom", 30)
	bg.add_child(vbox)

	# 顶栏：标题 + 关闭按钮
	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 20)
	vbox.add_child(title_bar)
	var title := Label.new()
	title.text = "生涯统计"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", C_HEAD)
	title_bar.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(44, 44)
	close_btn.add_theme_font_size_override("font_size", 26)
	var csb := StyleBoxFlat.new(); csb.bg_color = Color(0.55, 0.35, 0.18, 1)
	csb.corner_radius_top_left = 8; csb.corner_radius_top_right = 8
	csb.corner_radius_bottom_left = 8; csb.corner_radius_bottom_right = 8
	close_btn.add_theme_stylebox_override("normal", csb)
	close_btn.add_theme_stylebox_override("hover", csb)
	close_btn.add_theme_stylebox_override("pressed", csb)
	close_btn.add_theme_stylebox_override("focus", csb)
	close_btn.pressed.connect(close)
	title_bar.add_child(close_btn)

	# 分隔提示
	var sep := Label.new()
	sep.text = "历次游玩累计，只增不减"
	sep.add_theme_font_size_override("font_size", 17)
	sep.add_theme_color_override("font_color", C_MUTED)
	vbox.add_child(sep)

	# 两个统计数字
	_blocks_label = _stat_line(vbox, C_ACCENT)
	_gold_label = _stat_line(vbox, C_ACCENT)

	# 底部说明 + 关闭按钮
	var hint := Label.new()
	hint.text = "· 击破方块：所有方块被打碎的总次数\n· 总获取金币：历次产出金币的总和（含已花掉的）"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer2)

	var center := CenterContainer.new()
	vbox.add_child(center)
	var ok := Button.new()
	ok.text = "知道了"
	ok.custom_minimum_size = Vector2(220, 52)
	ok.add_theme_font_size_override("font_size", 22)
	ok.add_theme_color_override("font_color", Color(1, 0.96, 0.88))
	var okn := StyleBoxFlat.new()
	okn.bg_color = Color(0.75, 0.45, 0.15, 1)
	okn.corner_radius_top_left = 10; okn.corner_radius_top_right = 10
	okn.corner_radius_bottom_left = 10; okn.corner_radius_bottom_right = 10
	var okh := okn.duplicate(); okh.bg_color = Color(0.85, 0.52, 0.18, 1)
	ok.add_theme_stylebox_override("normal", okn)
	ok.add_theme_stylebox_override("hover", okh)
	ok.add_theme_stylebox_override("pressed", okh)
	ok.add_theme_stylebox_override("focus", okn)
	ok.pressed.connect(close)
	center.add_child(ok)


func _stat_line(parent: Node, color: Color) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", 34)
	lb.add_theme_color_override("font_color", color)
	parent.add_child(lb)
	return lb
