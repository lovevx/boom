extends "res://tools/ui_refresh_verify.gd"
## Rendered style/motion validation and a short recording in the isolated project.
func _run() -> void:
	if not "BoomameDemoValidation" in OS.get_user_data_dir():
		quit(2)
		return
	output = "E:/godotproject/boomame/artifacts/workshop"
	DirAccess.make_dir_recursive_absolute(output)
	capture = DisplayServer.get_name() != "headless"
	g = root.get_node("GoldManager")
	u = root.get_node("UpgradeManager")
	r = root.get_node("ReincarnationManager")
	s = root.get_node("SaveManager")
	p = root.get_node("Presentation")
	p.reduced_motion = false
	check(p.THEME.get_stylebox("normal","Button") is StyleBoxTexture,"buttons_use_artwork_nine_slice")
	check(p.THEME.get_stylebox("panel","PanelContainer") is StyleBoxTexture,"panels_use_artwork_nine_slice")
	await scene("res://scenes/MainMenu.tscn")
	await shot("styled-menu")
	var start: Button = current_scene._brand_root.get_node("StartButton")
	var chrome := start.get_node("_WorkshopChrome")
	var bounds: Rect2 = p.screen_rect(start)
	var motion := InputEventMouseMotion.new()
	motion.position = bounds.get_center()
	root.push_input(motion,true)
	await settle(0.4)
	check(chrome._hot > 0.9,"hover_animates_mechanical_brackets")
	check(p.screen_rect(start) == bounds,"hover_keeps_hit_target_stable")
	await shot("styled-hover")
	var down := InputEventMouseButton.new()
	down.position = bounds.get_center()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down,true)
	await process_frame
	check(chrome._pressed,"real_pointer_press_drives_feedback")
	await shot("styled-pressed")
	down.pressed = false
	root.push_input(down,true)
	await settle(0.4)
	check(current_scene._slot_menu.visible,"styled_button_still_opens_slots")
	await shot("styled-slots")
	current_scene._on_slot_menu_back()
	s.start_new_game(2)
	s.onboarding_pending = false
	await scene("res://scenes/Main.tscn")
	g.add_gold(700)
	var meter: Control = current_scene.get_node("GoldHUD/GoldBar/CoinHBox")
	var plates := meter.find_children("_WorkshopChrome","Control",true,false)
	check(not plates.is_empty() and plates[0]._flash > 0,"gold_gain_flashes_counter_plate")
	await settle(0.8)
	await shot("styled-hud")
	var tree := current_scene.get_node("UILayer/UpgradePanel")
	tree.open()
	var target: Vector2 = (root.get_visible_rect().size-tree._tree.size*tree._tree.scale)/2
	check(tree._tree.position.y > target.y,"dialog_has_visible_slide_in")
	await settle(0.4)
	check(tree._tree.position.is_equal_approx(target),"dialog_settles_at_layout_position")
	var deck: Control = tree._tree.get_child(0).get_node("_WorkshopChrome")
	var clock_before: float = deck._time
	await settle(0.5)
	check(paused and deck._time > clock_before,"ui_motion_runs_while_game_is_paused")
	await shot("styled-skills")
	await click(skill("hammer_damage"))
	check(u.get_hammer_damage_level() == 1,"styled_node_purchase_retains_gameplay")
	await shot("styled-upgrade-feedback")
	p.reduced_motion = true
	await settle(0.3)
	check(deck._time == 0 and deck._flash == 0,"reduced_motion_stops_panel_scan_and_flash")
	var frozen: float = deck._time
	await settle(0.5)
	check(deck._time == frozen,"reduced_motion_stays_static")
	tree.close()
	tree.open()
	check(tree._tree.position.is_equal_approx(target) and tree.modulate.a == 1,"reduced_motion_opens_without_slide_or_fade")
	tree.close()
	p.reduced_motion = false
	var settings := current_scene.get_node("UILayer/SettingsPanel")
	settings.open()
	await settle(0.4)
	await shot("styled-settings")
	settings.close()
	g.add_gold(r.MIN_RUN_GOLD_FOR_GAIN)
	var rebirth := current_scene.get_node("UILayer/ReincarnationPanel")
	rebirth.open()
	await settle(0.4)
	await shot("styled-rebirth")
	check(root.get_visible_rect().encloses(rebirth.settlement_screen_rect()),"styled_rebirth_action_is_visible")
	rebirth.close()
	await scene("res://scenes/MainMenu.tscn")
	# Creating, hovering and closing multiple scenes must not leave global animations alive.
	check(current_scene._brand_root.get_node("StartButton/_WorkshopChrome") != null,"chrome_recreated_after_scene_change")
	var file := FileAccess.open(output+"/motion-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"user_dir":OS.get_user_data_dir()},"\t"))
	print("WORKSHOP_MOTION_COMPLETE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
