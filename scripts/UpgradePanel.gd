extends Control
## 升级·技能树面板（放射状布局，独立界面，默认隐藏，通过屏幕按钮打开）。
##
## 结构（见 docs/SkillTree.md）：
##   - 中央 Hub 双层圆环 + 缓慢旋转标记；
##   - 四方向分支（八边形节点沿方向轴由内向外排布）：
##       ↑ 锤子(橙) / → 金币(金) / ↓ 炮台(红) / ← 建筑(蓝)
##   - 每条分支按 tier 由内向外：tier1(近 Hub) → tier2 → tier3(最外)。
##   - 深绿背景 + 程序化噪点；八边形外框；金橙色=已点亮、灰色+锁=未解锁。
##   - Hub→首节点、前置节点→高阶节点画连线；已点亮分支高亮脉动，其余虚线。
##   - 加点时沿分支方向飘一个绿色 ↑ 箭头。
##
## 状态由 UpgradeManager.get_node_state(nid) 统一出口：
##   locked(前置/机制门未满足) / available(可升级) / lit(已点亮) / maxed(满级)。
## 刷新由信号驱动（GoldManager.gold_changed / UpgradeManager.upgrades_changed）。

const OCT_R := 30.0      # 八边形节点外接圆半径
const HUB_R := 44.0      # 中心 Hub 半径
const SPACING := 100.0    # 为新增机制节点保留标题间距
const L1 := 160.0        # tier1 距 Hub
const L2 := 245.0        # tier2 距 Hub
const L3 := 330.0        # tier3 距 Hub
const GOLD := Color(0.94, 0.75, 0.19)     # 已点亮/高亮金橙色
const LGRAY := Color(0.45, 0.45, 0.5)     # 锁定/未激活

const C_HAMMER := Color(0.95, 0.6, 0.25)    # 锤子（橙）
const C_BOMB := Color(0.9, 0.35, 0.35)      # 炮台（红）
const C_ECON := Color(1.0, 0.85, 0.3)       # 金币（金）
const C_BUILD := Color(0.45, 0.65, 0.95)    # 建筑（蓝）

# 分支 → 径向角度（上/右/下/左）与主题色。
const BRANCH_ANGLE := {"hammer": -PI / 2.0, "econ": 0.0, "bomb": PI / 2.0, "build": PI}
const BRANCH_COLOR := {"hammer": C_HAMMER, "econ": C_ECON, "bomb": C_BOMB, "build": C_BUILD}
const BRANCH_DIST := {1: L1, 2: L2, 3: L3}

# 连线绘制层（DRAW 背景链 + 中心 Hub；位于节点之下）。
var _link_layer: Control
# 面板承载树（含标题/金币/关闭/连线/节点/卡片）。
var _tree: Control
var _coin_label: Label
var _hub_center: Vector2 = Vector2(900, 420)
var _all_cards: Array[Dictionary] = []     # 全部节点
var _center_map: Dictionary = {}           # id → 节点中心
var _t: float = 0.0                        # 连线/Hub 脉动相位
var _fills := {}                           # id → 入边填充进度(0..1)；加点瞬间从0冲到1

# —— 悬停提示（小浮窗，不开卡片） ——
var _close_button: Button
var _paused_before_open := false
var _tip: PanelContainer
var _tip_title: Label
var _tip_body: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 游戏进行中面板仍可交互
	_build_dim()
	_build_tree_panel()
	_build_nodes()
	_build_tip()
	GoldManager.gold_changed.connect(func(_t: int) -> void: refresh_all())
	UpgradeManager.upgrades_changed.connect(refresh_all)
	refresh_all()


func _process(delta: float) -> void:
	if not visible or Presentation.reduced_motion:
		return
	_t += delta
	_link_layer.queue_redraw()
	for card in _all_cards:
		if card.get("affordable",false):
			card.hex.queue_redraw()


# —— 界面打开 / 关闭 ——

func open() -> void:
	if visible:
		return
	_paused_before_open = get_tree().paused
	show()
	get_tree().paused = true   # 暂停整个游戏：升级面板期间主界面停止运行
	refresh_all()
	Presentation.dialog_enter(self)


func close() -> void:
	_hide_tip()   # 关闭整个技能树时，收起悬停提示
	get_tree().paused = _paused_before_open   # 恢复进入前的暂停状态
	hide()


# 供外部（如新手引导）查询某个节点当前的屏幕坐标，用于定位引导箭头。
# _tree 是面板内全屏 Control（原点对齐屏幕），故 _tree.position + center 即屏幕坐标。
func node_screen_pos(nid: String) -> Vector2:
	return node_screen_rect(nid).get_center()

func node_screen_rect(nid: String) -> Rect2:
	for card in _all_cards:
		if card.id == nid:
			return Presentation.screen_rect(card.hex)
	return Rect2()

func close_screen_rect() -> Rect2:
	return Presentation.screen_rect(_close_button)


# —— UI 搭建 ——

# 全屏调暗底板：点击空白处 → 若卡片打开则先收起卡片；否则关闭整个技能树。
func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _build_dim() -> void:
	var dim := Button.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.62)
	dim.add_theme_stylebox_override("normal", sb)
	dim.add_theme_stylebox_override("hover", sb)
	dim.add_theme_stylebox_override("pressed", sb)
	dim.add_theme_stylebox_override("focus", sb)
	dim.pressed.connect(_on_dim_clicked)
	add_child(dim)


func _on_dim_clicked() -> void:
	# 点击空白处无事发生：悬停即提示、点击节点即加点，无卡片可收
	pass


# 居中的技能树面板：深绿底 + 噪点 + 顶部标题/金币/关闭 + 连线层。
func _build_tree_panel() -> void:
	var panel_size := Vector2(1800, 840)
	var scr := get_viewport_rect().size
	_tree = Control.new()
	_tree.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 空白处点击穿透到底板
	_tree.position = (scr - panel_size) / 2.0
	_tree.size = panel_size
	_tree.clip_contents = true
	add_child(_tree)
	Presentation.bind_dialog(_tree,panel_size,false)

	# 深绿底色
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree.add_child(bg)

	# 程序化噪点
	var noise_rect := TextureRect.new()
	noise_rect.texture = _make_noise_texture()
	noise_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	noise_rect.stretch_mode = TextureRect.STRETCH_SCALE
	noise_rect.modulate = Color(1, 1, 1, 0.06)
	noise_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree.add_child(noise_rect)

	# 连线层（Hub + 分支连线）
	_link_layer = Control.new()
	_link_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_link_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_link_layer.draw.connect(_draw_link_layer)
	_tree.add_child(_link_layer)

	# 标题
	var title := Label.new()
	title.text = "技 能 树"
	title.position = Vector2(24, 14)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_tree.add_child(title)

	# 金币显示
	_coin_label = Label.new()
	_coin_label.text = "● 0"
	_coin_label.position = Vector2(250, 24)
	_coin_label.add_theme_font_size_override("font_size", 28)
	_coin_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_tree.add_child(_coin_label)

	# 右上角关闭按钮（关闭整个技能树）
	var close_btn := Button.new()
	_close_button = close_btn
	close_btn.text = "✕"
	close_btn.position = Vector2(_tree.size.x - 74, 12)
	close_btn.size = Vector2(56, 48)
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.pressed.connect(close)
	_tree.add_child(close_btn)
	var guide := Label.new()
	guide.position = Vector2(42,150)
	guide.size = Vector2(360,560)
	guide.text = "拆除成长路线 · 24 节点\n\n主动拆除：连续作业 → 蓄势重锤\n自动轰炸：高能装药 → 延时余震\n工程经营：拆除合同 + 坍塌回收\n\n悬停查看效果、费用和前置\n点击节点购买，立即生效\n锁：前置或转生未满足\n＋：可购买　缺：金币不足\n✓：满级　数字：当前 / 上限\n\n第一次转生：重锤 / 重炮\n第二次转生：余震 / 空中解体\n第三次转生：散射 / 火控同步"
	guide.add_theme_font_size_override("font_size",20)
	guide.add_theme_color_override("font_color",Presentation.PROFILE.muted)
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree.add_child(guide)


func _make_noise_texture() -> Texture2D:
	var N := 256
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var g := randf_range(0.05, 0.16)
			img.set_pixel(x, y, Color(g, g, g, 1))
	return ImageTexture.create_from_image(img)


# 构建全部技能节点（放射状定位 + 八边形），并登记连线源。
func _build_nodes() -> void:
	var defs: Array[Dictionary] = [
		# 锤子(↑ 上)
		{"id": "hammer_speed", "title": "锤子速度", "branch": "hammer", "tier": 1, "slot": 1, "icon": "⚡",
			"src": "", "cost": UpgradeManager.get_hammer_speed_cost, "upgrade": UpgradeManager.upgrade_hammer_speed,
			"effect": func() -> String: return "攻速 ×%0.2f" % UpgradeManager.hammer_speed},
		{"id": "hammer_damage", "title": "锤子伤害", "branch": "hammer", "tier": 1, "slot": 2, "icon": "⚔",
			"src": "", "cost": UpgradeManager.get_hammer_damage_cost, "upgrade": UpgradeManager.upgrade_hammer_damage,
			"effect": func() -> String: return "伤害 ×%0.2f" % UpgradeManager.hammer_damage},
		{"id": "hammer_range", "title": "锤子范围", "branch": "hammer", "tier": 1, "slot": 3, "icon": "◎",
			"src": "", "cost": UpgradeManager.get_hammer_range_cost, "upgrade": UpgradeManager.upgrade_hammer_range,
			"effect": func() -> String: return "命中半径 %d px" % int(UpgradeManager.hammer_range)},
		{"id": "crit_chance", "title": "暴击几率", "branch": "hammer", "tier": 3, "slot": 1, "icon": "✦",
			"src": "hammer_damage", "cost": UpgradeManager.get_crit_chance_cost, "upgrade": UpgradeManager.upgrade_crit_chance,
			"effect": func() -> String: return "暴击率 %d%%" % int(UpgradeManager.crit_chance * 100.0)},
		{"id": "crit_mult", "title": "暴击伤害", "branch": "hammer", "tier": 3, "slot": 2, "icon": "✹",
			"src": "crit_chance", "cost": UpgradeManager.get_crit_mult_cost, "upgrade": UpgradeManager.upgrade_crit_mult,
			"effect": func() -> String: return "暴击伤害 ×%0.1f" % UpgradeManager.crit_multiplier},
		# 金币(→ 右)，金币倍率 与 基础金币 同级并置
		{"id": "coin_multiplier", "title": "金币倍率", "branch": "econ", "tier": 1, "slot": 1, "icon": "$",
			"src": "", "cost": UpgradeManager.get_coin_multiplier_cost, "upgrade": UpgradeManager.upgrade_coin_multiplier,
			"effect": func() -> String: return "金币 ×%0.2f" % UpgradeManager.coin_multiplier},
		{"id": "coin_base", "title": "基础金币", "branch": "econ", "tier": 1, "slot": 2, "icon": "💰",
			"src": "", "cost": UpgradeManager.get_coin_base_cost, "upgrade": UpgradeManager.upgrade_coin_base,
			"effect": func() -> String: return "单块基础金币 +%d" % UpgradeManager.coin_base},
		# 炮台(↓ 下)
		{"id": "bomb_launcher", "title": "发射器数量", "branch": "bomb", "tier": 1, "slot": 1, "icon": "💣",
			"src": "", "cost": UpgradeManager.get_bomb_launcher_cost, "upgrade": UpgradeManager.upgrade_bomb_launcher,
			"effect": func() -> String:
				if UpgradeManager.get_bomb_launcher_level() <= 0:
					return "数量 ×0 | 未解锁"
				return "数量 ×%d" % UpgradeManager.get_bomb_launcher_count()},
		{"id": "bomb_damage", "title": "炸弹伤害", "branch": "bomb", "tier": 2, "slot": 1, "icon": "🗡",
			"src": "bomb_launcher", "cost": UpgradeManager.get_bomb_damage_cost, "upgrade": UpgradeManager.upgrade_bomb_damage,
			"effect": func() -> String: return "爆炸伤害 %d" % UpgradeManager.get_bomb_launcher_damage()},
		{"id": "bomb_radius", "title": "炸弹范围", "branch": "bomb", "tier": 2, "slot": 2, "icon": "◯",
			"src": "bomb_launcher", "cost": UpgradeManager.get_bomb_radius_cost, "upgrade": UpgradeManager.upgrade_bomb_radius,
			"effect": func() -> String: return "爆炸半径 %d px" % int(UpgradeManager.get_bomb_launcher_radius())},
		{"id": "bomb_rate", "title": "发射速率", "branch": "bomb", "tier": 2, "slot": 3, "icon": "⏱",
			"src": "bomb_launcher", "cost": UpgradeManager.get_bomb_rate_cost, "upgrade": UpgradeManager.upgrade_bomb_rate,
			"effect": func() -> String: return "冷却 ×%0.2f" % UpgradeManager.get_bomb_rate_multiplier()},
		{"id": "chain", "title": "连锁伤害", "branch": "bomb", "tier": 3, "slot": 1, "icon": "⛓",
			"src": "bomb_damage", "cost": UpgradeManager.get_chain_cost, "upgrade": UpgradeManager.upgrade_chain,
			"effect": func() -> String: return "爆炸连锁加伤 %d%%" % int(UpgradeManager.chain_damage * 100.0)},
		{"id": "scatter", "title": "散射炮", "branch": "bomb", "tier": 3, "slot": 4, "icon": "✸",
			"src": "bomb_radius", "cost": UpgradeManager.get_scatter_cost, "upgrade": UpgradeManager.upgrade_scatter,
			"effect": func() -> String: return "每次发射 ×%d" % UpgradeManager.get_scatter_count()},
		# 建筑(← 左)
		{"id": "building_drop_speed", "title": "下落速度", "branch": "build", "tier": 1, "slot": 1, "icon": "⬇",
			"src": "", "cost": UpgradeManager.get_building_drop_speed_cost, "upgrade": UpgradeManager.upgrade_building_drop_speed,
			"effect": func() -> String: return "下落 ×%0.2f" % UpgradeManager.building_drop_speed},
	]

	# 统计每个 branch-tier 的槽位数，用于中心对齐。
	for nid in UpgradeManager.DEMO_NODES:
		var entry: Dictionary = UpgradeManager.DEMO_NODES[nid]
		defs.append({"id":nid, "title":entry.title, "branch":entry.branch, "tier":entry.tier, "slot":entry.slot, "src":entry.pre})
	# 新旧节点统一从管理器获取实际扣款价（包含采购折扣）。
	for d in defs:
		var nid: String = d.id
		d.cost = func() -> int: return UpgradeManager.get_node_cost(nid)
	var slot_count := {}
	for d in defs:
		var key := "%s:%d" % [d["branch"], d["tier"]]
		slot_count[key] = slot_count.get(key, 0) + 1

	for d in defs:
		var key := "%s:%d" % [d["branch"], d["tier"]]
		var n: int = slot_count[key]
		var perp_offset: float = (d["slot"] - (n + 1) / 2.0) * SPACING
		var ang: float = BRANCH_ANGLE[d["branch"]]
		var dir := Vector2(cos(ang), sin(ang))
		var perp := Vector2(-dir.y, dir.x)
		var center: Vector2 = _hub_center + dir * BRANCH_DIST[d["tier"]] + perp * perp_offset
		d["center"] = center
		d["color"] = BRANCH_COLOR[d["branch"]]
		_make_octagon(d)
		_all_cards.append(d)
		_center_map[d["id"]] = center


# 生成一个八边形节点：图标(中心) + 等级(右下) + 锁(中心，锁定态)。
func _make_octagon(d: Dictionary) -> void:
	var r := OCT_R
	var oct := Control.new()
	oct.mouse_filter = Control.MOUSE_FILTER_STOP
	oct.size = Vector2(r * 2, r * 2)
	oct.position = d["center"] - Vector2(r, r)
	oct.draw.connect(func() -> void: _draw_octagon(oct, d))
	oct.mouse_entered.connect(func() -> void: _show_tip(d))
	oct.mouse_exited.connect(_hide_tip)
	oct.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			SoundManager.play("ui_click")
			_try_upgrade(d))
	# 图标（中心）
	var icon_lb := TextureRect.new()
	icon_lb.texture = Presentation.icon({"hammer":"hammer","econ":"coin","bomb":"bomb","build":"building"}[d["branch"]])
	icon_lb.position = Vector2(12,8)
	icon_lb.size = Vector2(36,36)
	icon_lb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_lb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oct.add_child(icon_lb)
	# 等级（右下角）
	var lvlb := Label.new()
	lvlb.text = ""
	lvlb.position = Vector2(r * 0.6, r * 1.05)
	lvlb.position = Vector2(9,36)
	lvlb.size = Vector2(42,20)
	lvlb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvlb.add_theme_font_size_override("font_size", 14)
	lvlb.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	oct.add_child(lvlb)
	var caption := Label.new()
	caption.text = d["title"]
	caption.position = Vector2(-52,64)
	caption.size = Vector2(164,22)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",16)
	caption.add_theme_color_override("font_color",d["color"])
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oct.add_child(caption)
	# 锁（锁定态覆盖）
	var lock_lb := TextureRect.new()
	lock_lb.texture = Presentation.icon("lock")
	lock_lb.position = Vector2(20,16)
	lock_lb.size = Vector2(24,24)
	lock_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_lb.visible = false
	oct.add_child(lock_lb)
	_tree.add_child(oct)
	d["hex"] = oct
	d["icon_label"] = icon_lb
	d["hex_label"] = lvlb
	d["hex_lock"] = lock_lb
	var status := Label.new()
	status.position = Vector2(45,-9)
	status.size = Vector2(24,24)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size",15)
	status.add_theme_color_override("font_outline_color",Presentation.PROFILE.ink)
	status.add_theme_constant_override("outline_size",5)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oct.add_child(status)
	d["status_label"] = status


# 绘制一个八边形节点：框色由状态决定（点亮=金橙 / 可升=分支配色 / 锁定=灰）。
func _draw_octagon(oct: Control, d: Dictionary) -> void:
	var c := Vector2(OCT_R, OCT_R)
	var r := OCT_R
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0 - PI / 8.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var st: Variant = d.get("state", {})
	var state: String = st.get("state", "available") if st is Dictionary else "available"
	var fill := _darken(Color(0.13, 0.23, 0.33), 1.0)
	var outline := LGRAY
	if state == "lit" or state == "maxed":
		outline = GOLD
	elif state == "available":
		outline = Presentation.PROFILE.cyan if d.get("affordable",false) else Presentation.PROFILE.muted
	oct.draw_colored_polygon(pts, fill)
	var inner := PackedVector2Array()
	for point in pts:
		inner.append(c+(point-c)*0.82)
	oct.draw_colored_polygon(inner,Color("#1e3546"))
	oct.draw_line(pts[4],pts[5],Color("#7f9ca9"),3)
	oct.draw_line(pts[5],pts[6],Color("#7f9ca9"),3)
	var poly := pts.duplicate()
	poly.append(pts[0])
	oct.draw_polyline(poly, outline, 3.0)
	if d.get("affordable",false):
		var alpha := 0.5 if Presentation.reduced_motion else 0.3+0.3*sin(_t*3)
		oct.draw_arc(c,r-4,-PI*0.8,PI*0.2,16,Color(outline,alpha),2)
	for corner in [0,2,4,6]:
		var bolt := c+(pts[corner]-c)*0.88
		oct.draw_circle(bolt,2,Color("#afc1c8"))


func _darken(col: Color, _dummy: float) -> Color:
	return Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 1.0)


# —— 悬停提示（小浮窗，只显示效果；点击节点本身直接加点） ——

func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.custom_minimum_size = Vector2(380, 0)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不拦截任何点击
	_tip.position = Vector2(-9999, -9999)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.96)
	sb.border_color = Color(0.62, 0.56, 0.36)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 12.0
	sb.content_margin_bottom = 8.0
	_tip.add_theme_stylebox_override("panel", sb)
	_tip.hide()
	_tree.add_child(_tip)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_tip.add_child(vbox)

	_tip_title = Label.new()
	_tip_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_tip_title)
	_tip_body = Label.new()
	_tip_body.custom_minimum_size.x = 336
	_tip_body.add_theme_font_size_override("font_size", 20)
	_tip_body.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_tip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_tip_body)


# 悬停显示节点效果的小浮窗（放在节点旁，尽量不挡视野）。
func _show_tip(d: Dictionary) -> void:
	var st: Dictionary = UpgradeManager.get_node_state(d["id"])
	_tip_title.text = d["title"]
	_tip_title.add_theme_color_override("font_color", d["color"])
	var lines := PackedStringArray()
	lines.append("当前：" + UpgradeManager.get_node_effect(d["id"]))
	if st.state != "maxed":
		lines.append("下一级：" + UpgradeManager.get_node_effect(d["id"], true))
	var lv: int = st.level
	var max_lv: int = st.max_level
	if max_lv >= 0:
		lines.append("等级 Lv.%d/%d" % [lv, max_lv])
	else:
		lines.append("等级 Lv.%d" % lv)
	match st.state:
		"locked":
			lines.append("需先解锁：%s" % st.reason)
		"maxed":
			lines.append("已满级")
		"lit", "available":
			var cost := UpgradeManager.get_node_cost(d.id)
			lines.append("点击购买 · %d 金币" % cost if GoldManager.total_gold >= cost else "金币不足 · 费用 %d，还差 %d" % [cost,cost-GoldManager.total_gold])
	_tip_body.text = "\n".join(lines)
	_tip.show()
	_tip.reset_size()
	var half := _tip.size / 2.0
	var c: Vector2 = d["center"]
	_tip.position = Vector2(
		clampf(c.x + OCT_R + 18, 8, _tree.size.x - _tip.size.x - 8),
		clampf(c.y - half.y, 8, _tree.size.y - _tip.size.y - 8))
	_tip.show()


func _hide_tip() -> void:
	if _tip:
		_tip.hide()


# —— 连线与中心 Hub 绘制 ——

func _draw_link_layer() -> void:
	# Etched plotting guides, separate from actionable skill links.
	var grid := Color(0.36,0.65,0.73,0.065)
	for x in range(440,int(_tree.size.x)-24,40):
		_link_layer.draw_line(Vector2(x,80),Vector2(x,_tree.size.y-28),grid,1)
	for y in range(80,int(_tree.size.y)-24,40):
		_link_layer.draw_line(Vector2(440,y),Vector2(_tree.size.x-24,y),grid,1)
	_link_layer.draw_line(Vector2(420,92),Vector2(420,_tree.size.y-34),Color("#405d6c"),2)
	# 分支连线：源(前置/hub) → 目标；已点亮=金色渐变"进度条"沿源→目标推进 + 流动光带，未点亮=灰色虚线
	for d in _all_cards:
		var from: Vector2 = _center_map.get(d["src"], _hub_center)
		var to: Vector2 = d["center"]
		var st: Dictionary = d.get("state", {})
		var state: String = st.get("state", "available") if st is Dictionary else "available"
		if state == "lit" or state == "maxed":
			# 依加点填充进度截断连线：加点瞬间 fill 0→1，形成"进度条冲到节点"的动画
			var eff: float = _fills.get(d["id"], 1.0)
			var to_t: Vector2 = from.lerp(to, eff)
			_draw_gradient_bar(_link_layer, from, to_t, GOLD, 3.0)
			_draw_flow_glow(_link_layer, from, to_t, GOLD)
		else:
			_draw_dashed_line(_link_layer, from, to, LGRAY, 9, 7, 2.0)
	# 中心 Hub（双层圆环 + 旋转标记）
	_draw_hub()


# 渐变"进度条"连线：颜色沿路径从暗渐变到亮金，表达进度从源端填充到目标节点。
func _draw_gradient_bar(canvas: CanvasItem, from: Vector2, to: Vector2, end_col: Color, width := 3.0, seg := 24) -> void:
	var start_col := end_col.darkened(0.45)
	for i in seg:
		var t0: float = float(i) / float(seg)
		var t1: float = float(i + 1) / float(seg)
		var col := start_col.lerp(end_col, (t0 + t1) / 2.0)
		canvas.draw_line(from.lerp(to, t0), from.lerp(to, t1), col, width)


# 沿连线流向终点的金色光带（能量正在流向并点亮的暗示），带透明度脉动；
# 终点即填充进度截断点，光带始终在其内部流动，不会伸出已填充范围。
func _draw_flow_glow(canvas: CanvasItem, from: Vector2, to: Vector2, col: Color) -> void:
	var d := to - from
	var len := d.length()
	if len <= 0.0:
		return
	var frac := fposmod(_t * 0.35, 1.0) * 0.92   # 轻微留白，让光带在填充末端"漏一眼"即回头
	var p := from.lerp(to, frac)
	var seg := clampf(0.16 * len, 4.0, 26.0)
	col.a = clampf(0.45 + 0.4 * sin(_t * 6.0), 0.25, 0.85)
	canvas.draw_line(p, p + d.normalized() * seg, col, 5.0)


func _draw_hub() -> void:
	var c := _hub_center
	_link_layer.draw_circle(c, HUB_R, Color(0.13, 0.26, 0.36))
	_link_layer.draw_arc(c, HUB_R, 0, TAU, 64, GOLD, 3.0)
	_link_layer.draw_arc(c, HUB_R - 7, 0, TAU, 56, Color(0.30, 0.55, 0.72), 2.0)
	_link_layer.draw_circle(c, 5, Color(1, 0.85, 0.4))
	_link_layer.draw_texture_rect(Presentation.icon("building"),Rect2(c-Vector2(24,24),Vector2(48,48)),false)
	for i in 8:
		var a := TAU * i / 8.0 + _t * 0.3
		var p := c + Vector2(cos(a), sin(a)) * HUB_R
		_link_layer.draw_circle(p, 3, GOLD)


# Godot 4 CanvasItem.draw_line 无原生虚线，用多段短划近似。
func _draw_dashed_line(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, dash := 9.0, gap := 7.0, width := 2.0) -> void:
	var d := to - from
	var len := d.length()
	if len <= 0.0:
		return
	var n := d / len
	var seg := 0.0
	while seg < len:
		var e := minf(seg + dash, len)
		canvas.draw_line(from + n * seg, from + n * e, color, width)
		seg += dash + gap


# —— 刷新（信号驱动） ——

func refresh_all() -> void:
	if _coin_label:
		_coin_label.text = "● %d" % GoldManager.total_gold
	for d in _all_cards:
		refresh_node(d)


func refresh_node(d: Dictionary) -> void:
	var st: Dictionary = UpgradeManager.get_node_state(d["id"])
	d["state"] = st
	var locked: bool = st.state == "locked"
	d["locked"] = locked
	d["hex_lock"].visible = locked
	d["hex_label"].text = "%d/%d" % [st.level,st.max_level] if not locked else ""
	var affordable: bool = not locked and st.state != "maxed" and GoldManager.total_gold >= UpgradeManager.get_node_cost(d.id)
	d["affordable"] = affordable
	d["status_label"].text = "锁" if locked else ("✓" if st.state == "maxed" else ("＋" if affordable else "缺"))
	d["status_label"].add_theme_color_override("font_color",Presentation.PROFILE.cyan if affordable else Presentation.PROFILE.muted)
	d["icon_label"].modulate = Color(1, 1, 1, 0.4) if locked else Color(1, 1, 1, 1)
	d["hex"].queue_redraw()


# —— 加点：扣金币 + 升级 + 刷新 + 强反馈 ——

# 点击节点：直接加点（扣金币 + 升级 + 刷新 + 强反馈）。
func _try_upgrade(d: Dictionary) -> void:
	var st: Dictionary = UpgradeManager.get_node_state(d["id"])
	if st.state == "locked" or st.state == "maxed":
		SoundManager.play("error")   # 锁定：给个失败音，不执行
		return
	# 首次点亮：升级前该节点连线还是未点亮（available）；若已是 lit/maxed 则仅强化，不再播放连线冲程
	var first_light: bool = st.state != "lit" and st.state != "maxed"
	if not UpgradeManager.purchase_node(d["id"]):
		return
	SoundManager.play("upgrade")
	refresh_all()
	_show_tip(d)
	_play_feedback(d, first_light)


# 加点反馈：八边形缩放弹跳 + 金色光爆 + 彩色粒子飞溅 + "+1" 飘字 + 绿色↑箭头。
func _play_feedback(d: Dictionary, first_light: bool) -> void:
	if Presentation.reduced_motion:
		refresh_node(d)
		return
	var oct: Control = d["hex"]
	var center: Vector2 = d["center"]

	oct.pivot_offset = oct.size / 2.0
	oct.scale = Vector2.ONE
	var t1 := create_tween()
	t1.tween_property(oct, "scale", Vector2(1.35, 1.35), 0.1)
	t1.tween_property(oct, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_burst_star(center)
	_burst_particles(center, d["color"])
	_float_plus(center)
	_spawn_up_arrow(d)
	if first_light:
		_play_fill_flow(d)


# 加点瞬间：该节点入边填充进度 0→1，呈"进度条从源端冲到节点"的动画，随后保持满格渐变。
func _play_fill_flow(d: Dictionary) -> void:
	var nid: String = d["id"]
	_fills[nid] = 0.0
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _fills[nid] = v, 0.0, 1.0, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# 沿分支方向向外飘一个绿色 ↑ 箭头，表达本分支提升方向。
func _spawn_up_arrow(d: Dictionary) -> void:
	if Presentation.reduced_motion:
		return
	var dir := _branch_dir(d["branch"])
	var lbl := Label.new()
	lbl.text = "▲"
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.35, 0.9, 0.45))
	lbl.position = d["center"] - Vector2(9, 9)
	_tree.add_child(lbl)
	var target := lbl.position + dir * 66.0
	var tw := create_tween()
	tw.tween_property(lbl, "position", target, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(lbl.queue_free)


func _branch_dir(branch: String) -> Vector2:
	match branch:
		"hammer": return Vector2(0, -1)
		"econ": return Vector2(1, 0)
		"bomb": return Vector2(0, 1)
		"build": return Vector2(-1, 0)
		_: return Vector2(0, -1)


func _burst_star(center: Vector2) -> void:
	var star := Label.new()
	star.text = "✦"
	star.add_theme_font_size_override("font_size", 60)
	star.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	star.position = center - Vector2(30, 30)
	star.pivot_offset = Vector2(30, 30)
	_tree.add_child(star)
	var tw := create_tween()
	tw.tween_property(star, "scale", Vector2(2.2, 2.2), 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(star, "modulate:a", 0.0, 0.32)
	tw.tween_callback(star.queue_free)


func _burst_particles(center: Vector2, color: Color) -> void:
	for i in 12:
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_font_size_override("font_size", 16)
		dot.add_theme_color_override("font_color", color.lightened(0.3))
		dot.position = center - Vector2(8, 8)
		_tree.add_child(dot)
		var ang := TAU * (i / 12.0) + randf_range(-0.2, 0.2)
		var dist := 55.0 + randf_range(0.0, 45.0)
		var target := center + Vector2(cos(ang), sin(ang)) * dist
		var tw := create_tween()
		tw.tween_property(dot, "position", target, 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(dot, "modulate:a", 0.0, 0.4)
		tw.tween_callback(dot.queue_free)


func _float_plus(center: Vector2) -> void:
	var p := Label.new()
	p.text = "+1"
	p.add_theme_font_size_override("font_size", 24)
	p.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	p.position = center - Vector2(14, 10)
	_tree.add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "position:y", p.position.y - 42.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _btn_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_right = 10.0
	sb.content_margin_bottom = 6.0
	return sb
