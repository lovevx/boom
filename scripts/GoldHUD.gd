extends CanvasLayer
## 金币 HUD：屏幕左上角显示当前总金币。
## 监听 GoldManager.gold_changed 实时刷新；数字变化时用 0.3 秒滚动过渡；
## 金币「增加」时整个徽章做左右缩放抖动（1.12→0.94→1.06→1.0）增强爽感，
## 消耗金币时不做抖动，避免消费也乱跳。

@onready var _label: Label = $GoldBar/CoinHBox/CoinLabel
@onready var _coin_bar: Control = $GoldBar/CoinHBox
@onready var _restart_btn: Button = $GoldBar/RestartButton
@onready var _restart_confirm: Control = $RestartConfirm
@onready var _restart_cancel_btn: Button = $RestartConfirm/Center/Panel/VBox/Buttons/CancelButton
@onready var _restart_ok_btn: Button = $RestartConfirm/Center/Panel/VBox/Buttons/OKButton
@onready var _menu_btn: Button = $GoldBar/MenuButton
@onready var _reinc_btn: Button = $GoldBar/ReincarnationButton
@onready var _settings_btn: Button = $GoldBar/SettingsButton

# 返回主菜单的目标场景
const MAIN_MENU_SCENE: String = "res://scenes/MainMenu.tscn"

var _displayed: float = 0.0   # 当前显示的金币数（滚动动画中间值）
var _tween: Tween            # 数字滚动 tween（变化时复用，避免叠加冲突）
var _pulse_tween: Tween      # 徽章左右缩放抖动 tween（增长时复用）
var _wobble_tween: Tween     # 徽章跷跷板倾斜摆动 tween（增长时复用）

# 场上临时实体归组的组名：BombProjectile / Debris / GoldPopup / DamageNumber / Bomb 都加入此组，
# 重置时遍历该组统一释放，避免旧弹体/碎屑残留。
const ENTITY_GROUP := &"in_game_entity"

# 数字滚动：恒定速率（金币/秒），保证每个金币增长速度一致；时长仍限制在 [MIN_SCROLL_TIME, MAX_SCROLL_TIME] 之间。
const SCROLL_RATE := 1500.0
const MIN_SCROLL_TIME := 0.12
const MAX_SCROLL_TIME := 0.45


func _ready() -> void:
	SoundManager.play_music()
	_setup_presentation_hud()
	_displayed = float(GoldManager.total_gold)
	_label.text = "%d" % GoldManager.total_gold
	_label.pivot_offset = _label.size / 2.0
	GoldManager.gold_changed.connect(_on_gold_changed)
	# 顶部"技能树"按钮：打开独立技能树面板
	$GoldBar/SkillTreeButton.pressed.connect(_open_skill_tree)
	# 顶部"重新开始"按钮：弹出二次确认框
	_restart_btn.pressed.connect(_on_restart_pressed)
	# 确认框按钮
	_restart_cancel_btn.pressed.connect(_confirm_restart_cancel)
	_restart_ok_btn.pressed.connect(_confirm_restart_ok)
	# 顶部"返回主菜单"按钮：带碎块转场切回主菜单
	_menu_btn.pressed.connect(_on_menu_pressed)
	# 顶部"转生"按钮：打开转生 · 永久技能树面板
	_reinc_btn.pressed.connect(_open_reincarnation)
	# 顶部"设置"按钮：打开设置面板
	_settings_btn.pressed.connect(_open_settings)


# 打开设置面板（面板定义见 SettingsPanel.gd 的 open()）。
func _open_settings() -> void:
	SoundManager.play("ui_click")
	var panel = get_node_or_null("../UILayer/SettingsPanel")
	if panel != null and panel.has_method("open"):
		panel.call("open")


# 打开转生 · 永久技能树界面（面板定义见 ReincarnationPanel.gd 的 open()）。
func _open_reincarnation() -> void:
	SoundManager.play("ui_click")
	var panel = get_node_or_null("../UILayer/ReincarnationPanel")
	if panel != null and panel.has_method("open"):
		panel.call("open")


# 返回主菜单：先自动落盘当前槽位，再带碎块转场切回主菜单场景。
func _on_menu_pressed() -> void:
	SoundManager.play("ui_click")
	SaveManager.save_current_slot()   # 返回主菜单前自动存档，避免长挂机进度丢失
	# 关闭可能开着的技能树，避免其残留在新场景
	var panel: Control = get_node_or_null("../UILayer/UpgradePanel")
	if panel != null and panel.visible and panel.has_method("close"):
		panel.call("close")
	ScreenTransition.transition_to(MAIN_MENU_SCENE)


# 打开独立技能树界面（面板定义见 UpgradePanel.gd 的 open()）。
func _open_skill_tree() -> void:
	SoundManager.play("ui_click")
	var panel: Control = get_node("../UILayer/UpgradePanel")
	if panel and panel.has_method("open"):
		panel.call("open")


func _on_gold_changed(new_total: int) -> void:
	var increased := new_total > int(_displayed)
	# 数字滚动：按恒定速率（每个金币滚动速度一致），增量越大动画越长；加最低时长兜底小额变化
	if _tween and _tween.is_valid():
		_tween.kill()
	var delta_gold := float(new_total - _displayed)
	var duration := clampf(absf(delta_gold) / SCROLL_RATE, MIN_SCROLL_TIME, MAX_SCROLL_TIME)
	_tween = create_tween()
	_tween.tween_method(_set_gold_text, _displayed, float(new_total), duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_displayed = float(new_total)
	# 金币「增加」时整个徽章做左右缩放抖动；消耗金币不动，避免乱跳
	if increased:
		_pulse_coin_bar()


# 金币徽章获得反馈：绕自身中心小幅点头摆动 + 横向缩放抖动，视觉稳、不飞出屏幕。
func _pulse_coin_bar() -> void:
	if Presentation.reduced_motion:
		return
	if _pulse_tween and _pulse_tween.is_valid():
		return
	_coin_bar.pivot_offset = _coin_bar.size/2.0
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_coin_bar,"scale",Vector2(1.035,1.035),0.06)
	_pulse_tween.tween_property(_coin_bar,"scale",Vector2.ONE,0.12)


func _set_gold_text(value: float) -> void:
	_label.text = "%d" % roundi(value)


# —— 重新开始：二次确认 + 一次性重置所有状态 ——

# 点击"重新开始"按钮：弹出二次确认框（不改动任何状态）。
func _on_restart_pressed() -> void:
	SoundManager.play("ui_click")
	_restart_confirm.show()


# 确认框"取消"：关闭确认框，不执行任何重置。
func _confirm_restart_cancel() -> void:
	_restart_confirm.hide()


# 确认框"确定重新开始"：一次性重置金币 / 升级 / 楼体 / 场上残留，并关闭技能树。
func _confirm_restart_ok() -> void:
	GameFeel.reset()
	_restart_confirm.hide()
	# 1) 重置金币
	GoldManager.reset()
	# 2) 重置升级（内含广播 upgrades_changed，并让 LauncherManager 隐藏全部炮台）
	UpgradeManager.reset()
	# 3) 重建楼体（先清旧塔再生成满楼）
	var building: Node = get_node_or_null("../Building")
	if building != null and building.has_method("reset"):
		building.call("reset")
	# 4) 清理场上残留临时实体 + 伤害数字层
	_clear_in_game_entities()
	# 5) 关闭可能开着的技能树
	var panel: Control = get_node_or_null("../UILayer/UpgradePanel")
	if panel != null and panel.visible and panel.has_method("close"):
		panel.call("close")


# 遍历"场上临时实体"组并释放，同时清空伤害数字层子节点。释放前一律校验有效性，避免访问已 free 实例。
func _clear_in_game_entities() -> void:
	for node in get_tree().get_nodes_in_group(ENTITY_GROUP):
		if is_instance_valid(node):
			node.queue_free()
	var dn_layer := get_node_or_null("../DamageNumberLayer")
	if dn_layer != null:
		for child in dn_layer.get_children():
			if is_instance_valid(child):
				child.queue_free()


func _setup_presentation_hud() -> void:
	var icon: TextureRect = $GoldBar/CoinHBox/CoinIcon
	icon.texture = Presentation.icon("coin")
	icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	icon.position = Vector2(12,10)
	icon.size = Vector2(44,44)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_label.add_theme_font_override("font",Presentation.NUMBERS)
	_label.add_theme_color_override("font_color",Presentation.PROFILE.gold)
	_label.add_theme_color_override("font_outline_color",Presentation.PROFILE.ink)
	_label.add_theme_constant_override("outline_size",4)
	var badge := Panel.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	badge.add_theme_stylebox_override("panel",Presentation.THEME.get_stylebox("normal","Button"))
	_coin_bar.add_child(badge)
	_coin_bar.move_child(badge,0)
	get_viewport().size_changed.connect(_layout_presentation_hud)
	_layout_presentation_hud()

func _layout_presentation_hud() -> void:
	var viewport := get_viewport().get_visible_rect().size
	_coin_bar.position = Vector2(24,24)
	_coin_bar.size = Vector2(300,64)
	var right := viewport.x - 24
	for name in ["SkillTreeButton","RestartButton","MenuButton","SettingsButton"]:
		var button: Button = get_node("GoldBar/"+name)
		var width := 184.0 if name in ["SkillTreeButton","MenuButton"] else 160.0
		right -= width
		button.position = Vector2(right,24)
		button.size = Vector2(width,64)
		right -= 12
	_reinc_btn.position = Vector2(344,24)
	_reinc_btn.size = Vector2(144,64)
