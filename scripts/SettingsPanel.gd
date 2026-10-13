extends Control
## 设置界面：调整音乐 / 音效音量 + 手动切换背景音乐（BGM1 / BGM2）。
## 滑块实时应用到 SoundManager 对应总线并持久化到 user://settings.cfg（全局设置，不随存档槽位走）。
## 主菜单与游戏内共用同一面板；由外部按钮调用 open() 打开、面板内 ✕ 或再次点击按钮关闭。

const C_DIM := Color(0, 0, 0, 0.74)
const C_PANEL_BG := Color(0.10, 0.12, 0.16, 0.98)
const C_HEAD := Color(1, 0.88, 0.4, 1)
const C_TEXT := Color(0.95, 0.95, 0.95, 1)
const C_MUTED := Color(0.72, 0.74, 0.8, 1)
const C_BTN_BG := Color(0.22, 0.26, 0.36, 1)
const C_BTN_SEL := Color(0.55, 0.4, 0.15, 1)
const C_BTN_HOVER := Color(0.3, 0.34, 0.46, 1)

var _paused_before_open := false
var _shake_slider: HSlider
var _motion_checkbox: CheckBox
var _density_select: OptionButton
var _music_pct: Label          # 音乐音量百分比
var _sfx_pct: Label            # 音效音量百分比
var _music_slider: HSlider
var _sfx_slider: HSlider
var _bgm_btns: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	SoundManager.settings_changed.connect(_refresh)
	Presentation.settings_changed.connect(_refresh)
	_refresh()


# —— 打开 / 关闭 ——

func open() -> void:
	if visible:
		return
	_paused_before_open = get_tree().paused
	get_tree().paused = true
	_refresh()
	Presentation.dialog_enter(self)


func close() -> void:
	hide()
	get_tree().paused = _paused_before_open


# —— 界面搭建（全部代码构建，风格对齐 ReincarnationPanel） ——

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = C_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel_size := Vector2(800, 840)
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

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 22)
	vbox.add_theme_constant_override("margin_left", 30)
	vbox.add_theme_constant_override("margin_top", 18)
	vbox.add_theme_constant_override("margin_right", 30)
	vbox.add_theme_constant_override("margin_bottom", 22)
	bg.add_child(vbox)

	# —— 顶栏：标题 + 关闭按钮 ——
	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 20)
	vbox.add_child(title_bar)
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", C_HEAD)
	title_bar.add_child(title)
	title_bar.add_child(_spacer())
	_close_btn(title_bar)

	# —— 音量行：滑块 + 百分比 ——
	vbox.add_child(_volume_row("音乐音量", C_HEAD, "music"))
	vbox.add_child(_volume_row("音效音量", Color(0.95, 0.6, 0.25), "sfx"))

	# —— BGM 切换行 ——
	var bgm_wrap := VBoxContainer.new()
	bgm_wrap.add_theme_constant_override("separation", 10)
	vbox.add_child(bgm_wrap)
	var bgm_cap := Label.new()
	bgm_cap.text = "背景音乐"
	bgm_cap.add_theme_font_size_override("font_size", 24)
	bgm_cap.add_theme_color_override("font_color", Color(0.6, 0.85, 1, 1))
	bgm_wrap.add_child(bgm_cap)
	var bgm_row := HBoxContainer.new()
	bgm_row.add_theme_constant_override("separation", 16)
	bgm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bgm_wrap.add_child(bgm_row)
	for i in SoundManager.BGM_NAMES.size():
		var b := Button.new()
		b.text = SoundManager.BGM_NAMES[i]
		b.set_meta("keep_ui_style",true)
		b.custom_minimum_size = Vector2(150, 54)
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", C_TEXT)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		var sn := StyleBoxFlat.new(); sn.bg_color = C_BTN_BG
		sn.corner_radius_top_left = 10; sn.corner_radius_top_right = 10
		sn.corner_radius_bottom_left = 10; sn.corner_radius_bottom_right = 10
		var sh := StyleBoxFlat.new(); sh.bg_color = C_BTN_HOVER
		sh.corner_radius_top_left = 10; sh.corner_radius_top_right = 10
		sh.corner_radius_bottom_left = 10; sh.corner_radius_bottom_right = 10
		b.add_theme_stylebox_override("normal", sn)
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("pressed", sh)
		b.add_theme_stylebox_override("focus", sn)
		b.pressed.connect(SoundManager.set_bgm_index.bind(i))
		b.pressed.connect(_play_ui_click)
		bgm_row.add_child(b)
		_bgm_btns.append(b)
	var bgm_hint := Label.new()
	bgm_hint.text = "点击切换，立即生效并自动保存"
	bgm_hint.add_theme_font_size_override("font_size", 15)
	bgm_hint.add_theme_color_override("font_color", C_MUTED)
	bgm_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bgm_wrap.add_child(bgm_hint)

	_build_presentation_settings(vbox)
	Presentation.bind_dialog(root,panel_size)

	# —— 底部说明 ——
	vbox.add_child(_spacer())
	var foot := Label.new()
	foot.text = "设置自动保存，主菜单与游戏内同步生效"
	foot.add_theme_font_size_override("font_size", 16)
	foot.add_theme_color_override("font_color", C_MUTED)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(foot)


# 单行音量：左标签 + 滑块 + 右百分比。
func _volume_row(caption: String, color: Color, kind: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	var cap := Label.new()
	cap.text = caption
	cap.custom_minimum_size = Vector2(150, 0)
	cap.add_theme_font_size_override("font_size", 24)
	cap.add_theme_color_override("font_color", color)
	row.add_child(cap)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(280, 0)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = 1.0
	row.add_child(slider)

	var pct := Label.new()
	pct.custom_minimum_size = Vector2(64, 0)
	pct.add_theme_font_size_override("font_size", 22)
	pct.add_theme_color_override("font_color", C_TEXT)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)

	if kind == "music":
		_music_slider = slider
		_music_pct = pct
		slider.value_changed.connect(func(v: float) -> void:
			SoundManager.set_music_volume(v)
			_music_pct.text = "%d%%" % roundi(v * 100.0))
	else:
		_sfx_slider = slider
		_sfx_pct = pct
		slider.value_changed.connect(func(v: float) -> void:
			SoundManager.set_sfx_volume(v)
			_sfx_pct.text = "%d%%" % roundi(v * 100.0))
	return row


func _spacer() -> Control:
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sp


func _close_btn(parent: Node) -> void:
	var btn := Button.new()
	btn.text = "✕"
	btn.custom_minimum_size = Vector2(44, 44)
	btn.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.55, 0.35, 0.18, 1)
	sb.corner_radius_top_left = 8; sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8; sb.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.pressed.connect(close)
	btn.pressed.connect(_play_ui_click)
	parent.add_child(btn)


func _play_ui_click() -> void:
	SoundManager.play("ui_click")


# 同步滑块 / 百分比 / BGM 选中态到 SoundManager 当前值。
func _refresh() -> void:
	if _shake_slider:
		_shake_slider.set_value_no_signal(Presentation.shake_strength)
		_motion_checkbox.set_pressed_no_signal(Presentation.reduced_motion)
		_density_select.select(1 if Presentation.low_effects else 0)
	_music_slider.set_value_no_signal(SoundManager.music_volume)
	_music_pct.text = "%d%%" % roundi(SoundManager.music_volume * 100.0)
	_sfx_slider.set_value_no_signal(SoundManager.sfx_volume)
	_sfx_pct.text = "%d%%" % roundi(SoundManager.sfx_volume * 100.0)
	for i in _bgm_btns.size():
		var selected := i == SoundManager.bgm_index
		for state in ["normal","hover","pressed","focus"]:
			_bgm_btns[i].remove_theme_stylebox_override(state)
		_bgm_btns[i].theme_type_variation = &"AccentButton" if selected else &"Button"



func _build_presentation_settings(parent: VBoxContainer) -> void:
	var heading := Label.new()
	heading.text = "画面与动态效果"
	heading.add_theme_font_size_override("font_size",26)
	heading.add_theme_color_override("font_color",Presentation.PROFILE.cyan)
	parent.add_child(heading)
	var shake_row := HBoxContainer.new()
	shake_row.add_theme_constant_override("separation",18)
	parent.add_child(shake_row)
	var label := Label.new()
	label.text = "震屏强度"
	label.custom_minimum_size.x = 150
	shake_row.add_child(label)
	_shake_slider = HSlider.new()
	_shake_slider.name = "ShakeStrength"
	_shake_slider.min_value = 0
	_shake_slider.max_value = 1
	_shake_slider.step = 0.05
	_shake_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shake_row.add_child(_shake_slider)
	_shake_slider.value_changed.connect(func(value: float) -> void:
		Presentation.shake_strength = value
		Presentation.save_preferences())
	_motion_checkbox = CheckBox.new()
	_motion_checkbox.name = "ReducedMotion"
	_motion_checkbox.text = "减少动态：关闭震屏、慢动作及大幅动画"
	parent.add_child(_motion_checkbox)
	_motion_checkbox.toggled.connect(func(value: bool) -> void:
		Presentation.reduced_motion = value
		Presentation.save_preferences())
	var density_row := HBoxContainer.new()
	parent.add_child(density_row)
	var density_label := Label.new()
	density_label.text = "特效密度"
	density_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	density_row.add_child(density_label)
	_density_select = OptionButton.new()
	_density_select.name = "EffectDensity"
	_density_select.add_item("标准")
	_density_select.add_item("低")
	_density_select.custom_minimum_size.x = 180
	density_row.add_child(_density_select)
	_density_select.item_selected.connect(func(index: int) -> void:
		Presentation.low_effects = index == 1
		Presentation.save_preferences())
