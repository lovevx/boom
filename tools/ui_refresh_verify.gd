extends SceneTree
## Run only in the isolated validation project. No player save is touched.
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var output := "E:/godotproject/boomame/artifacts/ui-refresh"
var capture := false
var video := false
var g: Node
var u: Node
var r: Node
var s: Node
var p: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"name":label,"passed":ok,"detail":detail})
	print("CHECK ",label,": ","PASS" if ok else "FAIL")
	if not ok:
		failures.append(label)

func settle(seconds: float = 0.3) -> void:
	await create_timer(seconds,true,false,true).timeout

func shot(label: String) -> void:
	if not capture:
		return
	await settle(0.2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/"+label+".png")
	if video:
		await settle(1.2)

func scene(path: String) -> void:
	paused = false
	root.get_node("GameFeel").reset()
	change_scene_to_file(path)
	await scene_changed
	await settle(1.2)
	var test := current_scene.get_node_or_null("TestPanel") as CanvasLayer
	if test:
		test.hide()

func guide() -> Node:
	return current_scene.get_node("Onboarding")

func click(control: Control) -> void:
	var at: Vector2 = p.screen_rect(control).get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion,true)
	await process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		await process_frame
	await settle()

func skill(id: String) -> Control:
	for card in current_scene.get_node("UILayer/UpgradePanel")._all_cards:
		if card.id == id:
			return card.hex
	return null

func _run() -> void:
	if not "BoomameDemoValidation" in OS.get_user_data_dir():
		push_error("Refusing to use player saves")
		quit(2)
		return
	capture = DisplayServer.get_name() != "headless"
	video = "video" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(output)
	g = root.get_node("GoldManager")
	u = root.get_node("UpgradeManager")
	r = root.get_node("ReincarnationManager")
	s = root.get_node("SaveManager")
	p = root.get_node("Presentation")
	p.reduced_motion = true
	s.start_new_game(0)
	await scene("res://scenes/MainMenu.tscn")
	await shot("menu")
	current_scene._on_start_pressed()
	await settle()
	current_scene._on_slot_selected(0)
	await shot("slots")
	await scene("res://scenes/Main.tscn")
	check(u.NODE_TITLES.size()+u.DEMO_NODES.size() == 24 and r.NODE_DEFS.size() == 21,"24_run_21_permanent_nodes")
	check(guide()._step == guide().Step.HIT and guide()._target.has_area(),"new_game_targets_visible_block")
	await shot("tutorial-01-hit")
	var first: Node2D = guide()._block
	first.take_damage(0.1)
	check(first.hp < first.max_hp,"target_is_damageable")
	first._shattered = true
	guide()._tick()
	check(guide()._block != first and guide()._target.has_area(),"target_replaced_when_destroyed")
	first._shattered = false
	g.add_gold(u.get_node_cost("hammer_damage"))
	await settle()
	check(guide()._step == guide().Step.OPEN_TREE,"enough_gold_points_to_tree")
	await shot("tutorial-02-open-tree")
	await click(current_scene.get_node("GoldHUD/GoldBar/SkillTreeButton"))
	var tree := current_scene.get_node("UILayer/UpgradePanel")
	check(tree.visible and paused and guide()._step == guide().Step.ADD_DAMAGE,"real_input_opens_tree_and_guide")
	guide()._update_arrow()
	var pointer_rect: Rect2 = guide()._arrow.get_global_transform_with_canvas()*Rect2(-82,-28,86,56)
	check(not pointer_rect.intersects(tree.node_screen_rect("hammer_speed")),"pointer_avoids_adjacent_skill")
	check(tree.node_screen_rect("hammer_damage").get_center().is_equal_approx(tree.node_screen_pos("hammer_damage")),"rect_api_matches_center_api")
	var money: int = g.total_gold
	await click(skill("hammer_damage"))
	check(u.get_hammer_damage_level() == 1 and g.total_gold == money-2,"real_input_buys_first_damage")
	await settle(1.7)
	check(tree.visible and guide()._step == guide().Step.RETURN,"tutorial_does_not_auto_close_tree")
	await shot("tutorial-03-upgraded")
	await click(tree._close_button)
	check(not paused and guide()._step == guide().Step.WAIT_LAUNCHER and not guide()._arrow.visible,"waiting_for_cannon_is_passive")
	var settings := current_scene.get_node("UILayer/SettingsPanel")
	settings.open()
	await settle()
	check(paused and not guide()._bar.visible and not guide()._arrow.visible,"settings_obscure_guidance")
	await shot("settings")
	settings.close()
	await settle()
	check(not paused and guide()._bar.visible,"settings_restore_pause_and_guidance")
	# Test fixtures fund milestones; the UI still uses the real purchase path.
	g.add_gold(u.get_node_cost("bomb_launcher"))
	await settle()
	await click(current_scene.get_node("GoldHUD/GoldBar/SkillTreeButton"))
	check(guide()._step == guide().Step.BUY_LAUNCHER,"cannon_available_guidance")
	await shot("tutorial-04-buy-cannon")
	await click(skill("bomb_launcher"))
	check(u.get_bomb_launcher_count() == 1 and s.onboarding_stage == 2,"deployment_is_not_first_shot")
	check(guide()._step == guide().Step.RETURN_LAUNCHER,"manual_return_after_deployment")
	await click(tree._close_button)
	var fire_deadline := Time.get_ticks_msec()+9000
	while s.onboarding_stage < 3 and Time.get_ticks_msec() < fire_deadline:
		await settle(0.2)
	check(s.onboarding_stage == 3 and guide()._step == guide().Step.WAIT_REBIRTH,"actual_first_fire_advances_tutorial")
	await shot("tutorial-05-first-fire")
	s.save_current_slot()
	await scene("res://scenes/MainMenu.tscn")
	check(s.load_slot(0) and s.onboarding_stage == 3 and s.onboarding_pending,"stage_persists_mid_tutorial")
	await scene("res://scenes/Main.tscn")
	check(guide()._step == guide().Step.WAIT_REBIRTH,"resume_skips_completed_steps")
	g.add_gold(r.MIN_RUN_GOLD_FOR_GAIN)
	await settle()
	check(guide()._step == guide().Step.OPEN_REBIRTH,"real_rebirth_threshold_used")
	await shot("tutorial-06-rebirth-ready")
	await click(current_scene.get_node("GoldHUD/GoldBar/ReincarnationButton"))
	var permanent := current_scene.get_node("UILayer/ReincarnationPanel")
	check(permanent.visible and guide()._step == guide().Step.CONFIRM_REBIRTH,"rebirth_panel_guidance")
	check(not guide()._target.intersects(p.screen_rect(guide()._bar)),"guidance_never_covers_rebirth_button")
	await shot("rebirth")
	await click(permanent._reinc_btn)
	check(permanent._confirm.visible,"rebirth_still_requires_confirmation")
	guide()._tick()
	guide()._update_arrow()
	pointer_rect = guide()._arrow.get_global_transform_with_canvas()*Rect2(-82,-28,86,56)
	var clear_of_cancel := true
	for button in permanent._confirm.find_children("*","Button",true,false):
		if button.text == "取消" and pointer_rect.intersects(p.screen_rect(button)):
			clear_of_cancel = false
	check(clear_of_cancel,"pointer_avoids_cancel_button")
	await shot("tutorial-07-confirm")
	await click(permanent._cf_ok)
	await settle(1.2)
	check(r.total_reincarnations == 1 and not s.onboarding_pending,"tutorial_completes_on_rebirth_before_scene_change")
	check(s.load_slot(0) and not s.onboarding_pending and s.onboarding_stage == 4,"completed_stage_saved")
	# Legacy done flag without stage remains authoritative.
	var cfg := ConfigFile.new()
	cfg.load("user://save_slot_0.cfg")
	cfg.erase_section_key("onboarding","stage")
	cfg.set_value("onboarding","done",true)
	cfg.save("user://save_slot_0.cfg")
	check(s.load_slot(0) and not s.onboarding_pending,"legacy_completed_slot_not_replayed")
	await scene("res://scenes/Main.tscn")
	check(current_scene.get_node_or_null("Onboarding") == null,"completed_guide_not_instantiated")
	u.set_state_from_save({"hammer_damage":1,"bomb_launcher":4,"bomb_rate":3})
	g.add_gold(10000)
	await settle()
	var launchers := current_scene.get_node("LauncherManager").get_children()
	var counts := [0,0,0,0]
	var volley_before := [0,0,0,0]
	for i in launchers.size():
		volley_before[i] = launchers[i]._volley_count
		var index := i
		launchers[i].bomb_fired.connect(func(_at: Vector2) -> void: counts[index] += 1)
		check(is_equal_approx(launchers[i].global_position.y+(64-32)*2,1000),"ground_anchor_"+str(i))
		var dir: float = launchers[i]._dir
		check((launchers[i]._muzzle.global_position.x-launchers[i].global_position.x)*dir > 0,"muzzle_faces_building_"+str(i))
		check(launchers[i]._turret.sprite_frames.get_frame_count("attack") == 33 and launchers[i].FIRE_FRAME_INDEX == 20,"animation_contract_"+str(i))
	await settle(6.0)
	check(counts.all(func(n: int) -> bool: return n > 0),"four_launchers_fire_at_fastest_rate",counts)
	for i in launchers.size():
		check(counts[i] == launchers[i]._volley_count-volley_before[i],"one_fire_event_per_volley_"+str(i))
	await shot("four-launchers")
	tree = current_scene.get_node("UILayer/UpgradePanel")
	tree.open()
	await settle()
	check(tree._all_cards.size() == 24,"all_skill_nodes_retained")
	for card in tree._all_cards:
		if card.id == "hammer_damage":
			tree._show_tip(card)
			check("当前" in tree._tip_body.text and "下一级" in tree._tip_body.text,"tooltip_actual_current_next_values")
	await shot("skill-tree")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3440,1440)]:
		root.size = dimensions
		await settle()
		var screen := root.get_visible_rect().grow(0.5)
		check(screen.encloses(p.screen_rect(tree._tree)),"skill_tree_bounds_"+str(dimensions))
		check(screen.encloses(tree.node_screen_rect("hammer_damage")),"target_transform_"+str(dimensions))
		await shot("skills-"+str(dimensions.x)+"x"+str(dimensions.y))
		tree.close()
		permanent = current_scene.get_node("UILayer/ReincarnationPanel")
		permanent.open()
		await settle()
		check(screen.encloses(permanent.settlement_screen_rect()),"fixed_rebirth_footer_"+str(dimensions))
		await shot("rebirth-"+str(dimensions.x)+"x"+str(dimensions.y))
		permanent.close()
		tree.open()
	tree.close()
	root.size = Vector2i(1920,1080)
	# Skip is per slot and global to all tutorial phases.
	s.start_new_game(1)
	await scene("res://scenes/Main.tscn")
	guide()._on_skip()
	check(not s.onboarding_pending and s.onboarding_stage == 4 and not guide().visible,"skip_finishes_all_phases")
	check(s.load_slot(1) and not s.onboarding_pending,"skip_persists")
	s.start_new_game(2)
	u.set_state_from_save({"hammer_damage":1,"bomb_launcher":1})
	await scene("res://scenes/Main.tscn")
	check(guide()._step == guide().Step.FIRST_FIRE,"advance_actions_do_not_require_repetition")
	p.reduced_motion = true
	guide()._step = guide().Step.OPEN_TREE
	guide()._target = current_scene.get_node("GoldHUD").action_screen_rect("skill_tree")
	guide()._arrow.show()
	guide()._update_arrow()
	var at: Vector2 = guide()._arrow.position
	guide()._pulse += 2
	guide()._update_arrow()
	check(at == guide()._arrow.position and guide()._glow.modulate.a == 1.0,"reduced_motion_static_pointer")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3440,1440)]:
		root.size = dimensions
		await settle()
		guide()._tick()
		var screen := root.get_visible_rect().grow(0.5)
		check(screen.encloses(p.screen_rect(guide()._bar)),"guide_card_bounds_"+str(dimensions))
		check(screen.encloses(p.screen_rect(guide()._skip_btn)),"guide_skip_bounds_"+str(dimensions))
		check(not guide()._target.intersects(p.screen_rect(guide()._bar)),"guide_target_uncovered_"+str(dimensions))
		settings = current_scene.get_node("UILayer/SettingsPanel")
		settings.open()
		await settle()
		check(screen.encloses(p.screen_rect(settings.get_child(1))),"settings_bounds_"+str(dimensions))
		settings.close()
	await scene("res://scenes/MainMenu.tscn")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3440,1440)]:
		root.size = dimensions
		await settle()
		var screen := root.get_visible_rect().grow(0.5)
		check(screen.encloses(p.screen_rect(current_scene._brand_root)),"menu_bounds_"+str(dimensions))
		current_scene._on_start_pressed()
		current_scene._on_slot_selected(0)
		await settle()
		check(screen.encloses(p.screen_rect(current_scene._slot_btns[0])) and screen.encloses(p.screen_rect(current_scene._confirm_btn)),"slot_controls_bounds_"+str(dimensions))
		current_scene._on_slot_menu_back()
	root.size = Vector2i(1920,1080)
	await settle(0.5)
	var report := {"checks":checks,"failures":failures,"user_dir":OS.get_user_data_dir(),"captured":capture,"fixtures":"Milestone currency injected; UI purchases use real pointer input."}
	var file := FileAccess.open(output+"/verification"+("-visual" if capture else "")+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("UI_REFRESH_COMPLETE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
