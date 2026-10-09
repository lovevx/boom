extends CanvasLayer
## 动作驱动（states-driven）的分步新手引导。
##
## 玩家每完成一个关键动作，才浮现下一条提示：绝不弹模态窗、绝不打断手部操作、
## 同屏只显示一条主提示、可全局跳过。里程碑由现有模块信号驱动
## （GoldManager / UpgradeManager / UpgradePanel），
## 引导全程不改写任何模块的内部逻辑，只做单向监听；完成或跳过会通过 SaveManager
## 在当前槽位写入"已过引导"标记。引导状态跟随存档槽位独立（新存档从新手教程开始），
## 二次进退该槽位与重启游戏后不再出现。

# —— 步骤常量（按序推进，每步只在上一步完成后进入）——
enum Step {
	NONE = -1,                    # 未开始/未启用
	HIT = 0,                      # Step0 摧毁方块，获取 2 金币
	OPEN_TREE = 1,                # Step1 高亮技能树按钮，点升级
	ADD_DAMAGE = 2,               # Step2 在技能树加一次【锤子伤害】
	DONE = 3,                     # Step3 加点后退出面板 → 完成新手教程
}

# —— 指向目标（世界/屏幕坐标，相机固定居中且 1:1）——
const TARGET_BLOCK_ANCHOR := Vector2(960, 420)   # 楼体中央锚点，用于找"最近建筑方块"
const TREE_BTN_POS := Vector2(1806, 49)          # 右上角技能树按钮中心
const DAMAGE_NODE_POS := Vector2(960, 400)       # 兜底：技能树面板内"锤子伤害"节点的屏幕坐标
const DAMAGE_NODE_ID := "hammer_damage"          # 引导目标节点 id（优先运行时从面板动态取坐标）

# —— 提示文案 ——
const MSG := {
	Step.HIT: "摧毁方块，获取 2 金币！",
	Step.OPEN_TREE: "点击这里打开技能树",
	Step.ADD_DAMAGE: "在技能树中加一次【锤子伤害】",
	Step.DONE: "继续赚更多的金币吧！",
}

# —— 视觉 / 节奏参数（集中管理，避免魔数散落）——
const BAR_W := 680.0
const BAR_H := 60.0
const BAR_Y_BOTTOM := 920.0
const BAR_Y_TOP := 40.0
const GOLD_THRESHOLD := 2        # Step0 攒到该金币数（摧毁方块得 2 金币即进入 Step1）
const CARD_AUTO_CLOSE := 1.5     # Step2 加点完成后延迟自动关面板的时长
const DONE_HOLD := 2.5           # 退出面板后收尾提示的停留时长，随后完成教程
const ARROW_OFFSET := Vector2(-14, 14)   # 简单箭头的箭尖相对目标位置；箭杆向左下延伸

var _step: int = Step.NONE
var _done := false
var _damage_added := false	# Step2 已在技能树加了一次锤子伤害
var _auto_close_scheduled := false	# Step2 加点后已排入"延迟关面板"，避免重复
var _step_elapsed := 0.0
var _pulse := 0.0
var _arrow_cur := Vector2.ZERO    # 箭头当前位置（平滑插值用）
var _arrow_ever_shown := false	# 箭头是否已显示过（首显直接定位，不做滑入）
var _screen := Vector2(1920, 1080)

# UI 节点
var _bar: Panel
var _bar_label: Label
var _skip_btn: Button
var _arrow: Node2D
var _glow: Node2D

# 场景引用
var _hammer: Node2D

func _ready() -> void:
	layer = 25                       # 高于 HUD(10)/UILayer(15)/TestPanel(20)
	process_mode = Node.PROCESS_MODE_ALWAYS   # 技能树面板开会暂停树：引导需持续运行（箭头/自动关面板）
	# 当前槽位无需引导（已过引导 / 无活动槽位）时直接销毁，不占任何资源
	if not SaveManager.onboarding_pending:
		queue_free()
		return
	_screen = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(_on_viewport_resized)
	_build_ui()
	_resolve_nodes()
	_connect_signals()
	_enter_step(Step.HIT)


# —— 节点与信号绑定 ——

func _resolve_nodes() -> void:
	var root := get_tree().current_scene
	_hammer = root.get_node_or_null("Hammer")


# 只做单向监听，不改各模块内部逻辑。
func _connect_signals() -> void:
	GoldManager.gold_changed.connect(_on_gold_changed)          # Step0 攒 2 金币
	UpgradeManager.upgrades_changed.connect(_on_upgrades_changed)  # Step2 加一次伤害
	var panel := _panel()
	if is_instance_valid(panel):
		panel.visibility_changed.connect(_on_panel_visibility)


# —— 状态推进（每步只在上一步完成后进入）——

# Step0 摧毁方块攒够 2 金币 → 高亮技能树按钮，提示"点击这里打开技能树"。
func _on_gold_changed(new_total: int) -> void:
	if _done:
		return
	if _step == Step.HIT and new_total >= GOLD_THRESHOLD:
		_enter_step(Step.OPEN_TREE)


# Step2 玩家在技能树加了一次伤害（锤子伤害 Lv≥1）→ 排入"延迟自动关面板"，免手动退出。
func _on_upgrades_changed() -> void:
	if _done:
		return
	if _step == Step.ADD_DAMAGE and UpgradeManager.get_hammer_damage_level() >= 1 \
			and not _damage_added:
		_damage_added = true
		if not _auto_close_scheduled:
			_auto_close_scheduled = true
			# 面板处于暂停态，需 process_always=true 让倒计时照常走完并自动关面板
			get_tree().create_timer(CARD_AUTO_CLOSE, true).timeout.connect(_auto_close_panel)


# 加点后延迟自动关闭技能树面板；面板隐藏会触发 _on_panel_visibility → 完成引导。
func _auto_close_panel() -> void:
	_auto_close_scheduled = false
	if _done or _step != Step.ADD_DAMAGE or not _damage_added:
		return
	var panel := _panel()
	if is_instance_valid(panel) and panel.visible:
		panel.close()


# 技能树面板显隐时刻（open() → show，close() → hide）。
func _on_panel_visibility() -> void:
	if _done:
		return
	var panel := _panel()
	var shown: bool = is_instance_valid(panel) and panel.visible
	if shown:
		# 第一次打开技能树：Step1 → Step2（引导在面板内加一次伤害）
		if _step == Step.OPEN_TREE:
			_enter_step(Step.ADD_DAMAGE)
	elif _step == Step.ADD_DAMAGE and _damage_added:
		# 加点后退出面板 → 进入收尾提示（停留一会儿再完成教程）
		_enter_step(Step.DONE)
		get_tree().create_timer(DONE_HOLD, true).timeout.connect(_finish)


# —— 进入某一步 ——

func _enter_step(s: int) -> void:
	_step = s
	_step_elapsed = 0.0
	_bar_label.text = MSG[s]
	SoundManager.play("onboarding_pop")   # 引导提示浮现轻提醒
	_position_bar(false)   # 提示条统一在底部
	_bar.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_bar, "scale", Vector2(0.96, 0.96), 0.0)
	tween.tween_property(_bar, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _position_bar(top: bool) -> void:
	var x := (_screen.x - BAR_W) / 2.0
	_bar.position = Vector2(x, BAR_Y_TOP if top else BAR_Y_BOTTOM)


# —— 每帧：箭头呼吸、锤头亮圈 ——

func _process(delta: float) -> void:
	if _done or _step == Step.NONE:
		return
	_step_elapsed += delta
	_pulse += delta * 3.0
	_update_arrow(delta)
	_update_glow()


func _update_arrow(delta: float) -> void:
	var target: Variant = _arrow_target()
	if target == null:
		_arrow.visible = false
		return
	_arrow.visible = true
	var pos: Vector2 = target + ARROW_OFFSET
	# 首次显示直接定位（不做滑入）；之后用指数插值平滑跟随目标移动
	if not _arrow_ever_shown:
		_arrow_cur = pos
		_arrow_ever_shown = true
	else:
		var t := 1.0 - exp(-10.0 * delta)   # 阻尼系数：越小越慢越"顺滑"
		_arrow_cur = _arrow_cur.lerp(pos, t)
	_arrow.global_position = _arrow_cur
	var breathe := 1.0 if Presentation.reduced_motion else 1.0 + 0.06 * sin(_pulse)
	_arrow.scale = Vector2(breathe, breathe)
	_arrow.modulate.a = 0.85


func _update_glow() -> void:
	if _step == Step.HIT and is_instance_valid(_hammer):
		_glow.visible = true
		_glow.global_position = _hammer.global_position
		_glow.modulate.a = 0.65 + 0.35 * sin(_pulse)
	elif _step == Step.OPEN_TREE:
		# 高亮技能树按钮：沿按钮外圈画呼吸描边
		_glow.visible = true
		_glow.global_position = _tree_button_position()
		_glow.modulate.a = 0.7 + 0.3 * sin(_pulse)
	else:
		_glow.visible = false


# 各步箭头指向：目标物失效/无有效目标时返回 null → 自动隐藏（is_instance_valid 防悬空）。
func _arrow_target() -> Variant:
	match _step:
		Step.HIT:
			return _nearest_block_pos()
		Step.OPEN_TREE:
			return _tree_button_position()
		Step.ADD_DAMAGE:
			# 悬停可看效果、点击节点直接加点 → 箭头始终指向该节点；加完之后即结束
			return _damage_node_pos() if not _damage_added else null
		Step.DONE:
			return null
	return null


# 引导目标节点坐标：优先从技能树面板动态取（跟随布局改动），面板不可用时回退常量兜底。
func _damage_node_pos() -> Vector2:
	var panel := _panel()
	if is_instance_valid(panel) and panel.has_method("node_screen_pos"):
		return panel.call("node_screen_pos", DAMAGE_NODE_ID)
	return DAMAGE_NODE_POS


# 用楼体锚点的物理点查询找出"最近的一个建筑方块"，块被毁后下一帧自动换到邻块。
func _nearest_block_pos() -> Variant:
	var root := get_tree().current_scene
	var building := root.get_node_or_null("Building") as Node2D
	if building == null:
		return null
	var space: PhysicsDirectSpaceState2D = building.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.position = TARGET_BLOCK_ANCHOR
	q.collide_with_bodies = true
	for hit in space.intersect_point(q):
		var c: Object = hit.get("collider")
		if is_instance_valid(c) and c.get_script() != null \
				and c.get_script().resource_path.ends_with("BuildingBlock.gd"):
			return c.get_global_transform_with_canvas().origin
	return null


# —— 跳过 / 结束 / 持久化 ——

func _on_skip() -> void:
	_finish()


func _finish() -> void:
	_done = true
	SaveManager.mark_onboarding_done()   # 当前槽位落盘"已过引导"
	visible = false   # 隐藏整个引导层


# —— UI 搭建 ——

func _build_ui() -> void:
	# 底部/顶部提示条
	_bar = Panel.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size = Vector2(BAR_W, BAR_H)
	_bar.add_theme_stylebox_override("panel", _bar_style(Color(0, 0, 0, 0.72)))
	add_child(_bar)

	_bar_label = Label.new()
	_bar_label.size = Vector2(BAR_W, BAR_H)
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_label.add_theme_font_size_override("font_size", 26)
	_bar_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	_bar.add_child(_bar_label)

	# 右上角常驻跳过按钮
	_skip_btn = Button.new()
	_skip_btn.text = "跳过 ×"
	_skip_btn.size = Vector2(180, 48)
	_skip_btn.add_theme_font_size_override("font_size", 20)
	_skip_btn.add_theme_stylebox_override("normal", _btn_style(Color(0.9, 0.3, 0.3)))
	_skip_btn.add_theme_stylebox_override("hover", _btn_style(Color(1.0, 0.4, 0.4)))
	_skip_btn.add_theme_stylebox_override("pressed", _btn_style(Color(0.7, 0.22, 0.22)))
	_skip_btn.add_theme_stylebox_override("focus", _btn_style(Color(0.9, 0.3, 0.3)))
	_skip_btn.pressed.connect(_on_skip)
	add_child(_skip_btn)

	# 手型箭头层（Node2D，在 CanvasLayer 下坐标为屏幕坐标）
	_arrow = Node2D.new()
	_arrow.visible = false
	_arrow.draw.connect(func() -> void: _draw_arrow(_arrow))
	add_child(_arrow)

	# 锤头亮圈
	_glow = Node2D.new()
	_glow.visible = false
	_glow.draw.connect(func() -> void: _draw_glow(_glow))
	add_child(_glow)

	# 初始定位
	_position_bar(false)
	# 右上角（避开技能树按钮 y25..73；放到金币栏下方的右上角，不挡点击）
	_skip_btn.position = Vector2(_screen.x - 200.0, 158.0)


func _draw_arrow(n: Node2D) -> void:
	# 简单箭头：箭尖位于节点原点并指向目标（右上），箭杆向坐下延伸。
	# 节点由 _update_arrow 放置在 目标 + ARROW_OFFSET，即"坐下指向目标"。
	var col := Color(1.0, 0.85, 0.3, 1.0)
	var out := Color(0, 0, 0, 0.5)
	var dir := Vector2(1, -1).normalized()   # 指向右上
	var wing := Vector2(-dir.y, dir.x)       # 垂直方向
	var tail := -70.0 * dir                  # 箭尾（坐下）
	# 箭杆（带黑描边增强可读性）
	n.draw_line(tail, Vector2.ZERO, out, 7.0)
	n.draw_line(tail, Vector2.ZERO, col, 4.5)
	# 箭尖（V 形，尖端在原点）
	var b1 := -22.0 * dir + 14.0 * wing
	var b2 := -22.0 * dir - 14.0 * wing
	n.draw_line(Vector2.ZERO, b1, out, 6.0)
	n.draw_line(Vector2.ZERO, b2, out, 6.0)
	n.draw_line(Vector2.ZERO, b1, col, 3.0)
	n.draw_line(Vector2.ZERO, b2, col, 3.0)


func _draw_glow(n: Node2D) -> void:
	var col := Color(1.0, 0.8, 0.25, 1.0)
	if _step == Step.OPEN_TREE:
		# 技能树按钮外圈呼吸描边（按钮约 180x48，留一点外扩）
		var half := Vector2(96, 30)
		n.draw_rect(Rect2(-half, half * 2.0), col, false, 5.0)
		n.draw_rect(Rect2(-half + Vector2(7, 7), half * 2.0 - Vector2(14, 14)), \
			Color(col.r, col.g, col.b, 0.35), false, 2.0)
		return
	n.draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 48, col, 6.0)
	n.draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 48, col, 3.0)


func _bar_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.18)
	return sb


func _btn_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_right = 10.0
	sb.content_margin_bottom = 6.0
	return sb


func _panel() -> Control:
	return get_tree().current_scene.get_node_or_null("UILayer/UpgradePanel") as Control


# —— 持久化 ——
# 引导完成标记由 SaveManager 按槽位持久化（mark_onboarding_done），此处不再自管文件。

# 供测试面板调用的"重置引导"入口：将当前槽位标为待引导，并就地重建引导层从头开始。
static func reset_and_restart() -> void:
	SaveManager.onboarding_pending = true
	var scene: Node = Engine.get_main_loop().current_scene
	if scene == null:
		return
	# 移除旧引导层（改名避免与接下来新节点重名冲突）
	var old: Node = scene.get_node_or_null("Onboarding")
	if old != null and is_instance_valid(old):
		old.name = "Onboarding_old"
		old.queue_free()
	# 重建引导层：复用 Main.tscn 中的脚本与层级
	var o := CanvasLayer.new()
	o.name = "Onboarding"
	o.layer = 25
	o.set_script(load("res://scripts/Onboarding.gd"))
	scene.add_child(o)


func _tree_button_position() -> Vector2:
	var button := get_tree().current_scene.get_node_or_null("GoldHUD/GoldBar/SkillTreeButton") as Control
	return button.get_global_rect().get_center() if button else TREE_BTN_POS

func _on_viewport_resized() -> void:
	_screen = get_viewport().get_visible_rect().size
	if _skip_btn:
		_skip_btn.position = Vector2(_screen.x-200,158)
	if _bar:
		_position_bar(_step == Step.ADD_DAMAGE)
