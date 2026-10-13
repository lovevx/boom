extends CanvasLayer
## 主界面：游戏启动第一屏（run/main_scene）。
## 流程：主菜单（背景 / 菜单图 / 开始游戏 / 玩法说明 / 退出）→ 点击「开始游戏」
## 弹出覆盖层「选择存档」（3 个存档槽位：继续 / 新游戏 / 删除）→ 确认后切入游戏场景。
## 槽位卡片由本脚本在 _ready 用代码搭建（标签随 SaveManager 动态刷新）。

const MAIN_SCENE: String = "res://scenes/Main.tscn"

# 玩法说明弹出面板（场景内定义，默认隐藏）
@onready var _how_to: Control = $HowTo
@onready var _close_btn: Button = $HowTo/Center/Panel/VBox/CloseCenter/CloseButton
# 设置面板（场景内定义，默认隐藏；由设置按钮打开）
@onready var _settings: Control = $SettingsPanel

# —— 选存档覆盖层布局（绝对坐标，配合 1920×1080 视口）——
const SLOT_COUNT := 3
const SLOT_X := 800.0
const SLOT_W := 300.0
const SLOT_H := 62.0
const SLOT_Y0 := 452.0
const SLOT_GAP := 72.0
const ACT_X := 820.0     # 底部操作条「确定」按钮
const ACT_W := 200.0
const DELFIX_X := 1040.0 # 底部「删除」按钮
const DELFIX_W := 200.0
const ACT_Y := 716.0
const ACT_H := 64.0

var _slot_menu: Control          # 选存档覆盖层（代码构建，默认隐藏）
var _slot_btns: Array[Button] = []
var _selected_slot: int = -1     # 当前选中（待确定/删除）的槽位；-1 表示未选中
var _confirm_btn: Button         # 底部「确定」按钮
var _del_btn: Button             # 底部「删除」按钮
var _del_armed := false          # 删除二次确认：已点击一次「删除」，需再点一次确认


func _ready() -> void:
	SoundManager.play_music()
	_build_slot_menu()
	$StartButton.pressed.connect(_on_start_pressed)
	$HowButton.pressed.connect(_on_how_to_pressed)
	$QuitButton.pressed.connect(_on_quit_pressed)
	$SettingsButton.pressed.connect(_on_settings_pressed)
	_close_btn.pressed.connect(_on_how_to_close)
	$StartButton.mouse_entered.connect(_on_ui_hover)
	$HowButton.mouse_entered.connect(_on_ui_hover)
	$QuitButton.mouse_entered.connect(_on_ui_hover)
	$SettingsButton.mouse_entered.connect(_on_ui_hover)
	_close_btn.mouse_entered.connect(_on_ui_hover)
	_build_stats_button()
	_build_presentation_menu()


# 通用悬停提示音。
func _on_ui_hover() -> void:
	SoundManager.play("ui_hover")


# —— 选存档覆盖层：开始游戏按钮 + 3 槽位卡片 + 返回 ——

func _build_slot_menu() -> void:
	_slot_menu = Control.new()
	_slot_menu.name = "SlotMenu"
	_slot_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_menu.hide()
	add_child(_slot_menu)
	var dim := ColorRect.new()
	dim.color = Color(0.02,0.05,0.09,0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_menu.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_menu.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620,0)
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",18)
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title := Label.new()
	title.text = "选择工程存档"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size",32)
	title.add_theme_color_override("font_color",Presentation.PROFILE.gold)
	header.add_child(title)
	var back := Button.new()
	back.text = "×"
	back.pressed.connect(_on_slot_menu_back)
	header.add_child(back)
	var hint := Label.new()
	hint.text = "三个独立工程 · 选择后继续或开始新游戏"
	hint.add_theme_font_size_override("font_size",18)
	hint.add_theme_color_override("font_color",Presentation.PROFILE.muted)
	body.add_child(hint)
	for i in SLOT_COUNT:
		var btn := Button.new()
		btn.custom_minimum_size.y = 86
		btn.add_theme_font_size_override("font_size",20)
		btn.set_meta("keep_ui_style",true)
		btn.pressed.connect(_on_slot_selected.bind(i))
		btn.mouse_entered.connect(_on_ui_hover)
		body.add_child(btn)
		_slot_btns.append(btn)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",16)
	body.add_child(actions)
	_confirm_btn = Button.new()
	_confirm_btn.custom_minimum_size.y = 60
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.theme_type_variation = &"PrimaryButton"
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	actions.add_child(_confirm_btn)
	_del_btn = Button.new()
	_del_btn.custom_minimum_size.y = 60
	_del_btn.pressed.connect(_on_delete_pressed)
	actions.add_child(_del_btn)
	_refresh_slot_cards()


# 通用操作按钮构建：normal/hover/pressed/focus 四态统一。
func _action_button(parent: Node, pos: Vector2, size: Vector2, text: String,
		bg: Color, hover: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = size
	b.text = text
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Color(1, 0.97, 0.92))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.25)
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate()
	sb_h.bg_color = hover
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)
	b.add_theme_stylebox_override("focus", sb)
	b.pressed.connect(cb)
	b.mouse_entered.connect(_on_ui_hover)
	parent.add_child(b)
	return b


func _refresh_slot_cards() -> void:
	_del_armed = false
	for i in SLOT_COUNT:
		var info := SaveManager.get_slot_info(i)
		_slot_btns[i].text = _slot_label(i, info)
		_apply_selected_style(_slot_btns[i], i == _selected_slot)
	_confirm_btn.text = "开始新游戏" if (_selected_slot >= 0 and not _has_save(_selected_slot)) else "继续游戏"
	_confirm_btn.visible = _selected_slot >= 0
	_del_btn.visible = _selected_slot >= 0 and _has_save(_selected_slot)
	_del_btn.text = "确认删除?" if _del_armed else "删除"


func _has_save(slot: int) -> bool:
	return SaveManager.has_save(slot)


# 槽位卡片选中态样式：边框加亮 + 底色提亮。
func _apply_selected_style(btn: Button, selected: bool) -> void:
	for state in ["normal","hover","pressed","focus"]:
		btn.remove_theme_stylebox_override(state)
	btn.theme_type_variation = &"PrimaryButton" if selected else &"Button"
	for state in ["font_color","font_hover_color","font_pressed_color"]:
		btn.remove_theme_color_override(state)


func _slot_label(i: int, info: Dictionary) -> String:
	if not info.get("has_save", false):
		return "存档 %d（空）\n点击选中，再点确定开始" % (i + 1)
	var t := int(info.get("time", 0))
	var date := Time.get_date_string_from_unix_time(t) if t > 0 else "——"
	return "存档 %d · 金币 %d · 转生 %d 次\n上次 %s" % [i + 1, int(info.get("gold", 0)), int(info.get("reincarnations", 0)), date]


# —— 主菜单 → 选存档覆盖层 ——

func _on_start_pressed() -> void:
	SoundManager.play("ui_click")
	_selected_slot = -1
	_refresh_slot_cards()
	_slot_menu.visible = true
	Presentation.dialog_enter(_slot_menu)


func _on_slot_menu_back() -> void:
	SoundManager.play("ui_click")
	_selected_slot = -1
	_del_armed = false
	_slot_menu.visible = false


# —— 槽位交互：选中 → 二级确定 / 删除 ——

# 点击一张槽位卡片 = 选中（高亮 + 出现底部操作条），不立即进入。
func _on_slot_selected(slot: int) -> void:
	SoundManager.play("ui_click")
	_selected_slot = slot
	_del_armed = false
	_refresh_slot_cards()


# 底部「确定」按钮：对选中的槽位开始新游戏 / 继续游戏并进入游戏场景。
func _on_confirm_pressed() -> void:
	if _selected_slot < 0:
		return
	SoundManager.play("ui_click")
	var slot := _selected_slot
	if SaveManager.has_save(slot):
		if not SaveManager.load_slot(slot):
			return   # 读取失败（异常）：不切场
	else:
		SaveManager.start_new_game(slot)
	ScreenTransition.transition_to(MAIN_SCENE)


# 底部「删除」按钮：二次确认后删除选中槽位。
func _on_delete_pressed() -> void:
	if _selected_slot < 0:
		return
	SoundManager.play("ui_click")
	if not _del_armed:
		_del_armed = true
		_del_btn.text = "确认删除?"
		return
	SaveManager.delete_slot(_selected_slot)
	_selected_slot = -1
	_del_armed = false
	_refresh_slot_cards()


func _on_how_to_pressed() -> void:
	_how_to.show()


func _on_how_to_close() -> void:
	_how_to.hide()


func _on_settings_pressed() -> void:
	SoundManager.play("ui_click")
	_settings.call("open")


func _on_quit_pressed() -> void:
	get_tree().quit()


# —— 生涯统计：左下角入口按钮 + 打开面板 ——

func _build_stats_button() -> void:
	var btn := Button.new()
	btn.position = Vector2(48, 950)
	btn.name = "CareerButton"
	btn.size = Vector2(200, 54)
	btn.text = "生涯统计"
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(1, 0.96, 0.88))
	btn.add_theme_color_override("font_hover_color", Color(1, 0.82, 0.28))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.24, 0.33, 0.94)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 0.7, 0.35, 0.9)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.pressed.connect(_on_stats_pressed)
	btn.mouse_entered.connect(_on_ui_hover)
	add_child(btn)


func _on_stats_pressed() -> void:
	SoundManager.play("ui_click")
	$StatsPanel.call("open")

var _brand_root: Control
var _logo_node: TextureRect
var _menu_time := 0.0

func _build_presentation_menu() -> void:
	$Bg.texture = preload("res://assets/presentation/yard.png")
	$Bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	$Bg.material = Presentation.scene_material("background")
	$Bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	$MenuArt.hide()
	_brand_root = Control.new()
	_brand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brand_root.size = Vector2(1920,1080)
	add_child(_brand_root)
	var panel := Panel.new()
	panel.position = Vector2(752,380)
	panel.size = Vector2(416,414)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", Presentation.THEME.get_stylebox("panel","PanelContainer"))
	_brand_root.add_child(panel)
	var logo := TextureRect.new()
	_logo_node = logo
	logo.texture = preload("res://assets/presentation/logo.png")
	logo.position = Vector2(540,160)
	logo.size = Vector2(840,200)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brand_root.add_child(logo)
	var caption := Label.new()
	caption.text = "砸碎 · 赚取 · 升级 · 自动轰炸"
	caption.position = Vector2(600,330)
	caption.size = Vector2(720,50)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",26)
	caption.add_theme_color_override("font_outline_color",Presentation.PROFILE.ink)
	caption.add_theme_constant_override("outline_size",6)
	_brand_root.add_child(caption)
	for index in 4:
		var button: Button = get_node(["StartButton","HowButton","SettingsButton","QuitButton"][index])
		button.reparent(_brand_root, false)
		button.position = Vector2(792,414 + index*86)
		button.size = Vector2(336,66)
		button.add_theme_font_size_override("font_size",28 if index==0 else 24)
		if index == 0:
			button.theme_type_variation = &"PrimaryButton"
		button.icon = Presentation.icon(["hammer","help","gear","exit"][index])
		button.add_theme_constant_override("icon_max_width",32)
	_brand_root.move_to_front()
	# Modal overlays must be above the new brand root.
	for name in ["SlotMenu","HowTo","SettingsPanel","StatsPanel"]:
		get_node(name).move_to_front()
	Presentation.bind_dialog(_brand_root,Vector2(1920,1080),false)
	get_viewport().size_changed.connect(_layout_presentation_menu)
	_layout_presentation_menu()
	if not Presentation.reduced_motion:
		for index in 4:
			var button: Button = _brand_root.get_node(["StartButton","HowButton","SettingsButton","QuitButton"][index])
			button.modulate.a = 0.0
			var reveal := button.create_tween()
			reveal.tween_interval(index*0.06)
			reveal.tween_property(button,"modulate:a",1.0,0.24)

func _process(delta: float) -> void:
	if is_instance_valid(_logo_node):
		_menu_time += delta
		_logo_node.position.y = 160.0 if Presentation.reduced_motion else 160.0+sin(_menu_time*0.9)*3.0

func _layout_presentation_menu() -> void:
	var viewport := get_viewport().get_visible_rect().size
	$CareerButton.position = Vector2(24,viewport.y-88)
	$CareerButton.icon = Presentation.icon("chart")
