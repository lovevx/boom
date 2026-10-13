extends Control
## 转生 · 永久技能树界面（主菜单独立入口）。
## 全屏面板：顶部统计（RP / 本局累计金币 / 累计转生次数 / 已点亮节点），
## 中间三大方向列展示永久技能树节点（名称 / 等级 / 当前效果 / 点亮按钮），
## 底部"转生"按钮 + 二次确认框（本局累计金币 / 预计获得 RP / 转生后余额）。
## 数值消费全走 ReincarnationManager：purchase_node() 点亮节点、reincarnate() 结算转生；
## 刷新由 reincarnation_changed / permanent_node_changed 信号驱动。

# —— 配色 ——
const C_DIM := Color(0, 0, 0, 0.74)
const C_PANEL_BG := Color(0.10, 0.12, 0.16, 0.98)
const C_HEAD := Color(1, 0.88, 0.4, 1)
const C_TEXT := Color(0.95, 0.95, 0.95, 1)
const C_MUTED := Color(0.72, 0.74, 0.8, 1)
const C_ENABLED := Color(0.2, 0.55, 0.35, 1)
const C_DISABLED := Color(0.35, 0.37, 0.42, 1)
const C_FULL := Color(0.46, 0.40, 0.30, 1)
const C_COL_GOLD := Color(1.0, 0.85, 0.3)
const C_COL_ATTACK := Color(0.95, 0.6, 0.25)
const C_COL_TURRET := Color(0.9, 0.35, 0.35)

const MAIN_MENU_SCENE: String = "res://scenes/MainMenu.tscn"

# —— 节点展示顺序与所属方向（对应 ReincarnationManager.NODE_DEFS）——
const NODE_ORDER := [
	["GOLD", "coin_heart"], ["GOLD", "initial_capital"], ["GOLD", "coin_per_kill"],
	["ATTACK", "base_damage"], ["ATTACK", "auto_hammer"], ["ATTACK", "destroy_power"],
	["ATTACK", "swift_wind"], ["ATTACK", "giant_power"], ["ATTACK", "gravity_accel"],
	["TURRET", "turret_base_damage"], ["TURRET", "ammo_enhance"], ["TURRET", "blast_range"],
	["GOLD", "salvage_license"], ["GOLD", "contract_license"], ["GOLD", "procurement"],
	["ATTACK", "combo_memory"], ["ATTACK", "wave_training"], ["ATTACK", "execute_training"],
	["TURRET", "blast_training"], ["TURRET", "echo_mastery"], ["TURRET", "barrage_training"],
]
const COL_META := {
	"GOLD": {"label": "方向① 获取金币", "color": C_COL_GOLD},
	"ATTACK": {"label": "方向② 攻击", "color": C_COL_ATTACK},
	"TURRET": {"label": "方向③ 炮台", "color": C_COL_TURRET},
}

var _rp_label: Label
var _run_label: Label
var _count_label: Label
var _lit_label: Label
var _progress_label: Label
var _reinc_btn: Button
var _cf_ok: Button
var _paused_before_open := false
var _rows: Dictionary = {}   # nid -> {"name": Label, "effect": Label, "btn": Button}

# —— 二次确认框 ——
var _confirm: Control
var _cf_run: Label
var _cf_gain: Label
var _cf_after: Label
var _cf_warn: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	GoldManager.gold_changed.connect(func(_gold: int) -> void: refresh_all())
	ReincarnationManager.reincarnation_changed.connect(refresh_all)
	ReincarnationManager.permanent_node_changed.connect(func(_nid: String, _lv: int) -> void: refresh_all())
	refresh_all()


# —— 打开 / 关闭 ——

func open() -> void:
	if visible:
		return
	_paused_before_open = get_tree().paused
	get_tree().paused = true
	show()
	refresh_all()
	Presentation.dialog_enter(self)


func close() -> void:
	_confirm.hide()
	get_tree().paused = _paused_before_open
	hide()


# —— 界面搭建（全部用代码构建，便于维护）——

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _confirm.visible:
			_confirm.hide()
		else:
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

	var panel_size := Vector2(1460, 900)
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
	vbox.add_theme_constant_override("separation", 12)
	vbox.add_theme_constant_override("margin_left", 22)
	vbox.add_theme_constant_override("margin_top", 16)
	vbox.add_theme_constant_override("margin_right", 22)
	vbox.add_theme_constant_override("margin_bottom", 16)
	bg.add_child(vbox)

	# —— 顶栏：标题 + 关闭按钮 ——
	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 20)
	vbox.add_child(title_bar)
	var title := Label.new()
	title.text = "转生 · 永久技能树"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", C_HEAD)
	title_bar.add_child(title)
	title_bar.add_child(_spacer())
	_close_btn(title_bar)

	# —— 统计行 ——
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 24)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(stats)
	_rp_label = _stat_label(stats)
	_run_label = _stat_label(stats)
	_count_label = _stat_label(stats)
	_lit_label = _stat_label(stats)
	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress_label.custom_minimum_size.y = 58
	_progress_label.add_theme_font_size_override("font_size", 17)
	_progress_label.add_theme_color_override("font_color", C_COL_GOLD)
	vbox.add_child(_progress_label)

	# —— 三大方向列 ——
	var cols := HBoxContainer.new()
	cols.custom_minimum_size.y = 0
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(cols)

	var buckets := {"GOLD": VBoxContainer.new(), "ATTACK": VBoxContainer.new(), "TURRET": VBoxContainer.new()}
	for cid in COL_META:
		var col_root := _make_column(COL_META[cid])
		cols.add_child(col_root)
		var col_box: VBoxContainer = col_root.get_node("Scroll/VBox")
		buckets[cid] = col_box

	# 节点行
	for entry in NODE_ORDER:
		var nid: String = entry[1]
		var row: PanelContainer = _make_row(nid)
		buckets[entry[0]].add_child(row)

	# —— 底栏：转生按钮 + 说明 ——
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	vbox.add_child(foot)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "永久加成购买后立即生效；转生清空本局，按拆楼累计产出结算 RP，开局资金不计入收益。"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", C_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(hint)
	var reinc_center := CenterContainer.new()
	foot.add_child(reinc_center)
	var reinc_btn := Button.new()
	_reinc_btn = reinc_btn
	reinc_btn.text = "◆ 转　生　◆"
	reinc_btn.theme_type_variation = &"PrimaryButton"
	reinc_btn.custom_minimum_size = Vector2(260, 56)
	reinc_btn.add_theme_font_size_override("font_size", 26)
	var sbn := StyleBoxFlat.new(); sbn.bg_color = Color(0.72, 0.24, 0.1, 1)
	sbn.corner_radius_top_left = 10; sbn.corner_radius_top_right = 10
	sbn.corner_radius_bottom_left = 10; sbn.corner_radius_bottom_right = 10
	var sbh := StyleBoxFlat.new(); sbh.bg_color = Color(0.86, 0.32, 0.13, 1)
	sbh.corner_radius_top_left = 10; sbh.corner_radius_top_right = 10
	sbh.corner_radius_bottom_left = 10; sbh.corner_radius_bottom_right = 10
	reinc_btn.add_theme_stylebox_override("normal", sbn)
	reinc_btn.add_theme_stylebox_override("hover", sbh)
	reinc_btn.add_theme_stylebox_override("pressed", sbh)
	reinc_btn.add_theme_stylebox_override("focus", sbn)
	reinc_btn.pressed.connect(_on_reincarnate_pressed)
	reinc_center.add_child(reinc_btn)

	_build_confirm()


func _spacer() -> Control:
	var sp := Control.new()
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
	parent.add_child(btn)


func _stat_label(parent: Node) -> Label:
	var lb := Label.new()
	lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", C_TEXT)
	parent.add_child(lb)
	return lb


# 单个方向列：带标题边框的面板，内部 VBox 装节点行。
func _make_column(meta: Dictionary) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.custom_minimum_size = Vector2(410, 0)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.15, 0.2, 0.6)
	sb.border_width_top = 2
	sb.border_color = meta.color
	sb.corner_radius_top_left = 10; sb.corner_radius_top_right = 10
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 10; sb.content_margin_bottom = 10

	var head := Label.new()
	head.text = meta.label
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", meta.color)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(head)

	var box := VBoxContainer.new()
	box.name = "VBox"
	box.add_theme_constant_override("separation", 8)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrap.add_child(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return wrap


# 单个永久节点行。
func _make_row(nid: String) -> PanelContainer:
	var node_def: Dictionary = ReincarnationManager.NODE_DEFS[nid]
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.22, 0.3, 0.9)
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.corner_radius_top_left = 8; sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8; sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	row.add_child(v)

	var name_lb := Label.new()
	name_lb.add_theme_font_size_override("font_size", 20)
	name_lb.add_theme_color_override("font_color", C_HEAD)
	v.add_child(name_lb)

	var effect_lb := Label.new()
	effect_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_lb.add_theme_font_size_override("font_size", 14)
	effect_lb.add_theme_color_override("font_color", C_MUTED)
	v.add_child(effect_lb)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(func() -> void: _on_row_pressed(nid))
	v.add_child(btn)

	_rows[nid] = {"name": name_lb, "effect": effect_lb, "btn": btn}
	return row


# 点击节点行"点亮"按钮。
func _on_row_pressed(nid: String) -> void:
	if ReincarnationManager.purchase_node(nid):
		SoundManager.play("ui_click")


# —— 刷新 ——

func refresh_all() -> void:
	_rp_label.text = "▲ RP：%d" % ReincarnationManager.reincarnation_points
	_run_label.text = "本局累计金币：%d" % GoldManager.lifetime_gold_this_run
	_count_label.text = "累计转生：%d 次" % ReincarnationManager.total_reincarnations
	var lit := 0
	for nid in ReincarnationManager.NODE_DEFS:
		if ReincarnationManager.get_node_level(nid) > 0:
			lit += 1
	_lit_label.text = "已点亮节点：%d / %d" % [lit, ReincarnationManager.NODE_DEFS.size()]
	var run_gold := GoldManager.lifetime_gold_this_run
	var gain := ReincarnationManager.collect_total_rp(run_gold)
	var remaining := maxi(0, ReincarnationManager.get_next_rp_gold(run_gold) - run_gold)
	_progress_label.text = "本次 +%d RP · 下一档还差 %d 金币　|　第 %d 次转生：%s" % [gain, remaining, ReincarnationManager.total_reincarnations + 1, ReincarnationManager.get_milestone_text(ReincarnationManager.total_reincarnations + 1)]
	if gain >= ReincarnationManager.MAX_RP_PER_RUN:
		_progress_label.text = "本局 RP 已达上限 +%d　|　第 %d 次转生：%s" % [gain, ReincarnationManager.total_reincarnations + 1, ReincarnationManager.get_milestone_text(ReincarnationManager.total_reincarnations + 1)]
	_reinc_btn.disabled = gain <= 0
	_reinc_btn.text = "转生 · +%d RP" % gain if gain > 0 else "累计产出 %d 金币后转生" % ReincarnationManager.get_required_run_gold()
	for nid in _rows:
		_update_row(nid)


func _update_row(nid: String) -> void:
	var r: Dictionary = _rows[nid]
	var lv: int = ReincarnationManager.get_node_level(nid)
	var max_lv: int = ReincarnationManager.get_node_max_level(nid)
	var node_def: Dictionary = ReincarnationManager.NODE_DEFS[nid]

	var pips := "●".repeat(lv) + "○".repeat(max_lv - lv)
	r["name"].text = "%s　%s" % [node_def.name, pips]
	r["effect"].text = _effect_text(nid, lv)
	if lv < max_lv:
		r["effect"].text += "\n下级：" + _effect_text(nid, lv + 1)

	var btn: Button = r["btn"]
	if lv >= max_lv:
		btn.text = "已满级"
		btn.disabled = true
		btn.theme_type_variation = &"Button"
	else:
		var cost: int = ReincarnationManager.get_node_cost(nid)
		var afford := ReincarnationManager.can_afford_node(nid)
		var reason := ReincarnationManager.get_node_lock_reason(nid)
		btn.text = reason if not reason.is_empty() else ("升级 · %d RP" % cost if afford else "缺少 RP · 需要 %d" % cost)
		btn.disabled = not afford
		btn.theme_type_variation = &"AccentButton" if afford else &"Button"


func _box_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = 7; s.corner_radius_top_right = 7
	s.corner_radius_bottom_left = 7; s.corner_radius_bottom_right = 7
	return s


func _effect_text(nid: String, lv: int) -> String:
	return ReincarnationManager.get_node_effect(nid, lv)


# —— 转生：二次确认框 ——

func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.visible = false
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm)

	var cd := ColorRect.new()
	cd.color = Color(0, 0, 0, 0.78)
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.add_child(cd)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL_BG
	sb.border_width_top = 3; sb.border_width_bottom = 3
	sb.border_width_left = 3; sb.border_width_right = 3
	sb.border_color = C_COL_TURRET
	sb.corner_radius_top_left = 16; sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16; sb.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(560, 0)
	v.add_theme_constant_override("separation", 16)
	v.add_theme_constant_override("margin_left", 30)
	v.add_theme_constant_override("margin_top", 26)
	v.add_theme_constant_override("margin_right", 30)
	v.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(v)

	var title := Label.new()
	title.text = "确认转生？"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", C_HEAD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	_cf_run = Label.new(); _cf_run.add_theme_font_size_override("font_size", 22); _cf_run.add_theme_color_override("font_color", C_TEXT); v.add_child(_cf_run)
	_cf_gain = Label.new(); _cf_gain.add_theme_font_size_override("font_size", 22); _cf_gain.add_theme_color_override("font_color", C_COL_GOLD); v.add_child(_cf_gain)
	_cf_after = Label.new(); _cf_after.add_theme_font_size_override("font_size", 22); _cf_after.add_theme_color_override("font_color", C_TEXT); v.add_child(_cf_after)
	_cf_warn = Label.new(); _cf_warn.add_theme_font_size_override("font_size", 17); _cf_warn.add_theme_color_override("font_color", C_MUTED); _cf_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(_cf_warn)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	v.add_child(buttons)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(150, 50)
	cancel.add_theme_font_size_override("font_size", 22)
	var sc := _box_style(C_DISABLED)
	cancel.add_theme_stylebox_override("normal", sc); cancel.add_theme_stylebox_override("hover", sc)
	cancel.add_theme_stylebox_override("pressed", sc); cancel.add_theme_stylebox_override("focus", sc)
	cancel.pressed.connect(func() -> void: _confirm.hide())
	buttons.add_child(cancel)

	var ok := Button.new()
	_cf_ok = ok
	ok.text = "确认转生"
	ok.theme_type_variation = &"PrimaryButton"
	ok.custom_minimum_size = Vector2(150, 50)
	ok.add_theme_font_size_override("font_size", 22)
	var so := _box_style(Color(0.68, 0.22, 0.08, 1))
	ok.add_theme_stylebox_override("normal", so); ok.add_theme_stylebox_override("hover", so)
	ok.add_theme_stylebox_override("pressed", so); ok.add_theme_stylebox_override("focus", so)
	ok.pressed.connect(_on_confirm_ok)
	buttons.add_child(ok)


func _on_reincarnate_pressed() -> void:
	SoundManager.play("ui_click")
	var run_gold := GoldManager.lifetime_gold_this_run
	var gain := ReincarnationManager.collect_total_rp(run_gold)
	_cf_run.text = "本局累计金币：%d" % run_gold
	_cf_gain.text = "预计获得 RP：+%d" % gain
	_cf_after.text = "转生后 RP 余额：%d → %d" % [ReincarnationManager.reincarnation_points, ReincarnationManager.reincarnation_points + gain]
	var lit := 0
	for nid in ReincarnationManager.NODE_DEFS:
		if ReincarnationManager.get_node_level(nid) > 0:
			lit += 1
	if run_gold < ReincarnationManager.get_required_run_gold():
		_cf_warn.text = "还差 %d 拆楼产出金币；达到门槛后才可转生。" % (ReincarnationManager.get_required_run_gold() - run_gold)
	else:
		_cf_warn.text = "转生后本局金币与升级清零，%d 个永久节点保留。\n本次解锁：%s" % [lit, ReincarnationManager.get_milestone_text(ReincarnationManager.total_reincarnations + 1)]
	if ReincarnationManager.total_reincarnations >= 3 and not DemoProgress.is_completed:
		_cf_warn.text += "\n最终工程尚未完成：再次转生将清空本轮产出和散射进度。"
	_cf_ok.disabled = gain <= 0
	_confirm.show()


func _on_confirm_ok() -> void:
	if ReincarnationManager.collect_total_rp(GoldManager.lifetime_gold_this_run) <= 0:
		return
	Presentation.celebrate_rebirth()
	_confirm.hide()
	get_tree().paused = false
	ReincarnationManager.reincarnate()   # 结算 RP、累计转生次数 +1
	# 转生结算完成：重置本局进度，注入永久加成起点，并落盘"转生后新开局"到当前槽位，再切回主菜单
	GoldManager.reset()
	UpgradeManager.reset()
	ReincarnationManager.apply_permanent_bonuses()
	SaveManager.save_current_slot()
	ScreenTransition.transition_to(MAIN_MENU_SCENE)


func settlement_screen_rect() -> Rect2:
	return Presentation.screen_rect(_cf_ok if _confirm.visible else _reinc_btn)
