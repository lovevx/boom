extends CanvasLayer
## Per-slot, non-modal guidance. Never buys or opens/closes a panel for the player.
enum Step { NONE = -1, HIT, OPEN_TREE, ADD_DAMAGE, RETURN, WAIT_LAUNCHER, OPEN_LAUNCHER, BUY_LAUNCHER, RETURN_LAUNCHER, FIRST_FIRE, WAIT_REBIRTH, OPEN_REBIRTH, CONFIRM_REBIRTH }
var _step: int = Step.NONE
var _done := false
var _pulse := 0.0
var _elapsed := 0.0
var _screen := Vector2.ZERO
var _target := Rect2()
var _avoid_rects: Array[Rect2] = []
var _block: BuildingBlock
var _bar: PanelContainer
var _bar_label: Label
var _phase_label: Label
var _skip_btn: Button
var _arrow: Node2D
var _arrow_cur := Vector2.ZERO
var _arrow_dir := Vector2.RIGHT
var _glow: Node2D

func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not SaveManager.onboarding_pending:
		queue_free()
		return
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	ReincarnationManager.reincarnation_changed.connect(_on_rebirth)
	var manager := get_tree().current_scene.get_node_or_null("LauncherManager")
	if manager:
		for launcher in manager.get_children():
			if launcher.has_signal("bomb_fired"):
				launcher.bomb_fired.connect(_on_bomb_fired)
	_layout()
	_tick()

func _process(delta: float) -> void:
	if _done:
		return
	_pulse += delta * 3.0
	_elapsed += delta
	if _elapsed >= 0.12:
		_elapsed = 0.0
		_tick()
	_update_arrow()

func _panel() -> Control:
	return get_tree().current_scene.get_node_or_null("UILayer/UpgradePanel") as Control

func _rebirth_panel() -> Control:
	return get_tree().current_scene.get_node_or_null("UILayer/ReincarnationPanel") as Control

func _set_stage(stage: int) -> void:
	if SaveManager.onboarding_stage < stage:
		SaveManager.onboarding_stage = stage
		SaveManager.save_current_slot()

func _tick() -> void:
	if _done:
		return
	if ReincarnationManager.total_reincarnations > 0:
		_finish()
		return
	var tree := _panel()
	var tree_open: bool = is_instance_valid(tree) and tree.visible
	var new_step: int
	var message: String
	if UpgradeManager.get_hammer_damage_level() == 0 and SaveManager.onboarding_stage == 0:
		var price := UpgradeManager.get_node_cost("hammer_damage")
		if tree_open:
			new_step = Step.ADD_DAMAGE
			message = "点击「锤子伤害」升级一次 · %d 金币" % price
		elif GoldManager.total_gold < price:
			new_step = Step.HIT
			message = "鼠标移到方块上，点击砸楼 · 赚取 %d 金币" % price
		else:
			new_step = Step.OPEN_TREE
			message = "金币够了！打开技能树，强化你的锤子"
	else:
		_set_stage(1)
		if UpgradeManager.get_bomb_launcher_count() == 0:
			var price := UpgradeManager.get_node_cost("bomb_launcher")
			if tree_open and _step in [Step.ADD_DAMAGE, Step.RETURN]:
				new_step = Step.RETURN
				message = "锤子升级成功！点击 × 或按 Esc 返回工地"
			elif GoldManager.total_gold < price:
				new_step = Step.WAIT_LAUNCHER
				message = "继续拆楼 · 第一台液压炮还差 %d 金币" % (price - GoldManager.total_gold)
			elif tree_open:
				new_step = Step.BUY_LAUNCHER
				message = "点击「发射器数量」部署第一台液压炮 · %d 金币" % price
			else:
				new_step = Step.OPEN_LAUNCHER
				message = "可以部署液压炮了！打开技能树"
		else:
			_set_stage(2)
			if tree_open and SaveManager.onboarding_stage < 3:
				new_step = Step.RETURN_LAUNCHER
				message = "液压炮已部署 · 点击 × 或按 Esc 返回工地，看看它开炮"
			elif SaveManager.onboarding_stage < 3:
				new_step = Step.FIRST_FIRE
				message = "液压炮会自动瞄准和开火 · 你仍可继续锤击"
			elif ReincarnationManager.collect_total_rp(GoldManager.lifetime_gold_this_run) <= 0:
				new_step = Step.WAIT_REBIRTH
				message = "自动轰炸开始了！累计拆楼产出 %d / %d，准备首次转生" % [GoldManager.lifetime_gold_this_run, ReincarnationManager.get_required_run_gold()]
			elif _rebirth_panel().visible:
				new_step = Step.CONFIRM_REBIRTH
				message = "查看转生收益后自行确认 · 本局金币与升级清空，永久成长保留"
			else:
				new_step = Step.OPEN_REBIRTH
				message = "首次转生已就绪！打开转生界面，查看本次收益"
	if new_step != _step:
		_step = new_step
		SoundManager.play("onboarding_pop")
	_bar_label.text = message
	var phase := 1 if _step <= Step.RETURN else (2 if _step <= Step.FIRST_FIRE else 3)
	_phase_label.text = "新手工程  %d / 3  ·  %s" % [phase,["锤击与升级","自动拆楼","永久成长"][phase-1]]
	_target = _target_rect()
	_avoid_rects.clear()
	for button in get_tree().current_scene.find_children("*","BaseButton",true,false):
		if button.is_visible_in_tree():
			var rect: Rect2 = Presentation.screen_rect(button)
			if not rect.intersects(_target):
				_avoid_rects.append(rect.grow(4))
	if tree_open:
		for card in tree._all_cards:
			var rect: Rect2 = tree.node_screen_rect(card.id)
			if not rect.intersects(_target):
				_avoid_rects.append(rect.grow(4))
	_bar.position.y = _screen.y-124
	if _target.has_area() and _target.grow(16).intersects(Rect2(_bar.position,_bar.size)):
		_bar.position.y = 16
	var blocked := _obscured()
	_bar.visible = not blocked
	_arrow.visible = _target.has_area() and not blocked
	_glow.visible = _arrow.visible
	_glow.queue_redraw()

func _obscured() -> bool:
	for path in ["UILayer/SettingsPanel","GoldHUD/RestartConfirm"]:
		var panel := get_tree().current_scene.get_node_or_null(path) as Control
		if panel and panel.visible:
			return true
	return _rebirth_panel().visible and _step != Step.CONFIRM_REBIRTH

func _target_rect() -> Rect2:
	var hud := get_tree().current_scene.get_node("GoldHUD")
	match _step:
		Step.HIT:
			# Reconsider untouched targets as the tower finishes spawning; keep a damaged
			# target stable so a player can finish the block they already started hitting.
			if not is_instance_valid(_block) or _block._shattered or _block._falling or _block.hp >= _block.max_hp:
				_block = null
				var best := INF
				var building := get_tree().current_scene.get_node_or_null("Building")
				if building:
					for node in building.get_children():
						if not node is BuildingBlock or node._shattered or node._falling:
							continue
						var pos: Vector2 = node.get_global_transform_with_canvas().origin
						if not Rect2(Vector2(80,220),_screen-Vector2(160,420)).has_point(pos):
							continue
						var score: float = pos.distance_squared_to(_screen*0.5) + node.hp*1000
						if score < best:
							best = score
							_block = node
			if is_instance_valid(_block):
				return Rect2(_block.get_global_transform_with_canvas().origin-Vector2(20,20),Vector2(40,40))
		Step.OPEN_TREE, Step.OPEN_LAUNCHER:
			return hud.action_screen_rect("skill_tree")
		Step.ADD_DAMAGE:
			return _panel().node_screen_rect("hammer_damage")
		Step.BUY_LAUNCHER:
			return _panel().node_screen_rect("bomb_launcher")
		Step.RETURN, Step.RETURN_LAUNCHER:
			return _panel().close_screen_rect()
		Step.OPEN_REBIRTH:
			if not _panel().visible:
				return hud.action_screen_rect("rebirth")
		Step.CONFIRM_REBIRTH:
			return _rebirth_panel().settlement_screen_rect()
	return Rect2()

func _update_arrow() -> void:
	if not _arrow.visible:
		return
	var center := _target.get_center()
	var spaces := [center.x,_screen.x-center.x,center.y-160,_screen.y-center.y-160]
	var choice := spaces.find(spaces.max())
	var candidates := [0,1,2,3]
	candidates.sort_custom(func(a: int,b: int) -> bool: return spaces[a] > spaces[b])
	for candidate in candidates:
		var direction: Vector2 = [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP][candidate]
		var half_size := _target.size*0.5
		var tip := center-direction*((half_size.x if candidate < 2 else half_size.y)+14)
		var arrow_rect := Transform2D(direction.angle(),tip)*Rect2(-82,-28,86,56)
		var free := Rect2(Vector2(8,8),_screen-Vector2(16,16)).encloses(arrow_rect)
		free = free and not arrow_rect.intersects(Rect2(_bar.position,_bar.size))
		for rect in _avoid_rects:
			if arrow_rect.intersects(rect):
				free = false
				break
		if free:
			choice = candidate
			break
	_arrow_dir = [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP][choice]
	var half := _target.size*0.5
	var edge := center-_arrow_dir*(half.x if choice < 2 else half.y)
	var breathe := 0.0 if Presentation.reduced_motion else sin(_pulse)*4.0
	_arrow_cur = (edge-_arrow_dir*(14+breathe)).round()
	_arrow.position = _arrow_cur
	_arrow.rotation = _arrow_dir.angle()
	_arrow.queue_redraw()
	_glow.modulate.a = 1.0 if Presentation.reduced_motion else 0.8+sin(_pulse)*0.15

func _draw_arrow() -> void:
	var points := PackedVector2Array([Vector2(-76,-9),Vector2(-28,-9),Vector2(-28,-22),Vector2(0,0),Vector2(-28,22),Vector2(-28,9),Vector2(-76,9)])
	_arrow.draw_colored_polygon(points,Presentation.PROFILE.gold)
	var outline := points.duplicate()
	outline.append(points[0])
	_arrow.draw_polyline(outline,Presentation.PROFILE.ink,5.0)
	_arrow.draw_line(Vector2(-68,-5),Vector2(-32,-5),Color("#ffe49b"),2.0)

func _draw_glow() -> void:
	if _target.has_area():
		_glow.draw_rect(_target.grow(6),Presentation.PROFILE.ink,false,7.0)
		_glow.draw_rect(_target.grow(6),Presentation.PROFILE.gold,false,3.0)

func _on_bomb_fired(_at: Vector2) -> void:
	if not _done and UpgradeManager.get_bomb_launcher_count() > 0:
		_set_stage(3)
		_tick()

func _on_rebirth() -> void:
	if ReincarnationManager.total_reincarnations > 0:
		_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	SaveManager.mark_onboarding_done()
	hide()

func _on_skip() -> void:
	_finish()

func _build_ui() -> void:
	_glow = Node2D.new()
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_arrow = Node2D.new()
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)
	_bar = PanelContainer.new()
	_bar.name = "GuideCard"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(row)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(body)
	_phase_label = Label.new()
	_phase_label.add_theme_font_size_override("font_size",16)
	_phase_label.add_theme_color_override("font_color",Presentation.PROFILE.cyan)
	body.add_child(_phase_label)
	_bar_label = Label.new()
	_bar_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bar_label.add_theme_font_size_override("font_size",21)
	body.add_child(_bar_label)
	_skip_btn = Button.new()
	_skip_btn.text = "跳过指引"
	_skip_btn.add_theme_font_size_override("font_size",16)
	_skip_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skip_btn.pressed.connect(_on_skip)
	row.add_child(_skip_btn)

func _layout() -> void:
	_screen = get_viewport().get_visible_rect().size
	_bar.size = Vector2(minf(820,_screen.x-64),106)
	_bar.position = Vector2((_screen.x-_bar.size.x)/2,_screen.y-124)

static func reset_and_restart() -> void:
	SaveManager.onboarding_pending = true
	SaveManager.onboarding_stage = 0
	var scene: Node = Engine.get_main_loop().current_scene
	if scene == null:
		return
	var old := scene.get_node_or_null("Onboarding")
	if old:
		old.name = "Onboarding_old"
		old.queue_free()
	var guide := CanvasLayer.new()
	guide.name = "Onboarding"
	guide.set_script(load("res://scripts/Onboarding.gd"))
	scene.add_child(guide)
