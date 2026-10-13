extends CanvasLayer
## One automatic completion dialog per save; opening it never resets the run.
var _overlay: Control
var _body: Label
var _paused_before := false

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.09, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var frame := PanelContainer.new()
	frame.name = "DemoResult"
	_overlay.add_child(frame)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	frame.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	margin.add_child(content)
	var title := Label.new()
	title.text = "Demo 工程完成"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Presentation.PROFILE.gold)
	content.add_child(title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("font_size", 21)
	content.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	content.add_child(buttons)
	for item in [["继续游玩", _close], ["返回主菜单", _menu]]:
		var button := Button.new()
		button.text = item[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 56
		button.pressed.connect(item[1])
		buttons.add_child(button)
	Presentation.bind_dialog(frame, Vector2(720, 460))
	_overlay.hide()

func _process(_delta: float) -> void:
	if not DemoProgress.is_completed or DemoProgress.summary_shown or ScreenTransition._busy:
		return
	# Let players finish reading/closing an existing dialog first.
	if get_tree().paused:
		return
	_show_result()

func _show_result() -> void:
	var result := DemoProgress.completion_stats
	var permanent: Dictionary = result.get("permanent", {})
	var count := 0
	for level in permanent.values():
		if int(level) > 0:
			count += 1
	_body.text = "试玩用时  %s%s\n\n累计拆除  %d 块    累计产出  %d 金币\n完成转生  %d 次    永久节点  %d 个\n\n锤击 → 自动轰炸 → 连锁余震 → 散射工程\n你可以继续搭配技能，或返回主菜单保存成果。" % [
		DemoProgress.format_time(float(result.get("seconds", 0))), "（旧档续玩）" if result.get("legacy", false) else "",
		int(result.get("blocks", 0)), int(result.get("gold", 0)), int(result.get("rebirths", 3)), count]
	DemoProgress.summary_shown = true
	SaveManager.save_current_slot()
	_paused_before = get_tree().paused
	get_tree().paused = true
	Presentation.dialog_enter(_overlay)
	SoundManager.play("upgrade")

func _unhandled_key_input(event: InputEvent) -> void:
	if _overlay.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

func _close() -> void:
	_overlay.hide()
	get_tree().paused = _paused_before

func _menu() -> void:
	_close()
	get_tree().current_scene.get_node("GoldHUD")._on_menu_pressed()
