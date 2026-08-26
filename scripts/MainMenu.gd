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


# 通用悬停提示音。
func _on_ui_hover() -> void:
	SoundManager.play("ui_hover")


# —— 选存档覆盖层：开始游戏按钮 + 3 槽位卡片 + 返回 ——

func _build_slot_menu() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.name = "SlotMenu"
	overlay.visible = false
	add_child(overlay)
	_slot_menu = overlay

	# 底板：挡住主菜单点击
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	# 标题
	var title := Label.new()
	title.position = Vector2(SLOT_X - 40, 372)
	title.size = Vector2(SLOT_W + 80, 56)
	title.text = "选择存档"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1, 0.88, 0.4))
	overlay.add_child(title)

	# 返回按钮
	var back := Button.new()
	back.position = Vector2(60, 44)
	back.size = Vector2(150, 58)
	back.text = "← 返回"
	back.add_theme_font_size_override("font_size", 26)
	back.add_theme_color_override("font_color", Color(1, 0.96, 0.88))
	back.add_theme_color_override("font_hover_color", Color(1, 0.82, 0.28))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.2, 0.24, 0.33, 0.94)
	bsb.set_corner_radius_all(10)
	bsb.set_border_width_all(2)
	bsb.border_color = Color(1, 0.7, 0.35, 0.9)
	back.add_theme_stylebox_override("normal", bsb)
	back.add_theme_stylebox_override("hover", bsb)
	back.add_theme_stylebox_override("pressed", bsb)
	back.add_theme_stylebox_override("focus", bsb)
	back.pressed.connect(_on_slot_menu_back)
	back.mouse_entered.connect(_on_ui_hover)
	overlay.add_child(back)

	# 3 张槽位卡片（点击=选中，不做立即进入）
	for i in SLOT_COUNT:
		var y := SLOT_Y0 + i * SLOT_GAP
		var btn := Button.new()
		btn.position = Vector2(SLOT_X, y)
		btn.size = Vector2(SLOT_W, SLOT_H)
		btn.add_theme_font_size_override("font_size", 19)
		btn.add_theme_color_override("font_color", Color(1, 0.96, 0.88))
		btn.add_theme_color_override("font_hover_color", Color(1, 0.82, 0.28))
		btn.pressed.connect(_on_slot_selected.bind(i))
		btn.mouse_entered.connect(_on_ui_hover)
		overlay.add_child(btn)
		_slot_btns.append(btn)

	# 底部操作条：选中槽位后出现 ——「确定」（开始/继续）+「删除」
	_confirm_btn = _action_button(overlay, Vector2(ACT_X, ACT_Y), Vector2(ACT_W, ACT_H), "确定",
		Color(0.2, 0.55, 0.35), Color(0.28, 0.68, 0.44), _on_confirm_pressed)
	_del_btn = _action_button(overlay, Vector2(DELFIX_X, ACT_Y), Vector2(DELFIX_W, ACT_H), "删除",
		Color(0.55, 0.22, 0.2), Color(0.7, 0.3, 0.26), _on_delete_pressed)
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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.26, 0.32, 0.44, 0.97) if selected else Color(0.2, 0.24, 0.33, 0.94)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 0.85, 0.4, 1) if selected else Color(1, 0.7, 0.35, 0.9)
	var sb_h := sb.duplicate()
	sb_h.bg_color = Color(0.3, 0.35, 0.46, 0.96)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_h)
	btn.add_theme_stylebox_override("focus", sb)


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