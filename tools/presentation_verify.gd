extends SceneTree
## End-to-end checks run ONLY in an isolated validation copy.
var failures: Array[String] = []
var checks: Array[Dictionary] = []
var output := "E:/godotproject/boomame/artifacts"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, name: String, details: Variant = null) -> void:
	checks.append({"name":name,"passed":ok,"details":details})
	print("CHECK ",name,": ", "PASS" if ok else "FAIL")
	if not ok:
		failures.append(name)

func _scene(path: String) -> void:
	paused = false
	root.get_node("GameFeel").reset()
	change_scene_to_file(path)
	await scene_changed
	await create_timer(0.8, true, false, true).timeout
	var debug_panel := current_scene.get_node_or_null("TestPanel") as CanvasLayer
	if debug_panel:
		debug_panel.hide()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/visual/verification/"+name+".png")

func _run() -> void:
	if not "PresentationValidation" in OS.get_user_data_dir():
		push_error("Refusing to test against player saves")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output+"/visual/verification")
	seed(719)
	var gold := root.get_node("GoldManager")
	var upgrade := root.get_node("UpgradeManager")
	var save := root.get_node("SaveManager")
	var presentation := root.get_node("Presentation")
	var feel := root.get_node("GameFeel")
	save.start_new_game(2)
	save.onboarding_pending = false
	presentation.reduced_motion = false
	presentation.low_effects = false
	presentation.shake_strength = 0.55
	await _scene("res://scenes/Main.tscn")
	var building := current_scene.get_node("Building")
	var generation_deadline := Time.get_ticks_msec() + 8000
	while building.get_child_count() < 360 and Time.get_ticks_msec() < generation_deadline:
		await process_frame
	check(building.get_child_count() == 360,"initial_360_blocks",building.get_child_count())
	var window_block: Node2D
	for node in building.get_children():
		if node.is_glass and node.global_position.y > 200 and node.global_position.y < 850:
			window_block = node
			break
	var original_hp: float = window_block.hp
	var original_gold: int = gold.total_gold
	var yield_gold: int = window_block.gold_value
	var hammer := current_scene.get_node("Hammer")
	hammer._smash(window_block.global_position)
	check(is_equal_approx(window_block.hp,original_hp - 1),"hammer_damage_unchanged")
	await create_timer(0.12,true,false,true).timeout
	hammer._smash(window_block.global_position)
	await create_timer(0.1,true,false,true).timeout
	check(gold.total_gold == original_gold + yield_gold,"shatter_gold_unchanged",gold.total_gold-original_gold)
	await create_timer(1.0,true,false,true).timeout
	check(building.get_child_count() == 360,"column_refill")
	var reservation := Node.new()
	root.add_child(reservation)
	check(presentation.admit(reservation,"fragment",768),"reserve_fragment_budget")
	var victim: Node2D = building.get_child(0)
	var before: int = gold.total_gold
	var expected: int = victim.gold_value
	victim.take_damage(1000)
	await process_frame
	check(gold.total_gold == before + expected,"budget_never_suppresses_rewards")
	reservation.free()
	await create_timer(1.0,true,false,true).timeout
	gold.add_gold(1000000)
	for i in 4:
		upgrade.upgrade_bomb_launcher()
	for i in 3:
		upgrade.upgrade_bomb_rate()
	check(upgrade.get_bomb_launcher_count() == 4,"four_launchers")
	var expected_cooldown: float = upgrade.LAUNCHER_COOLDOWNS[4] * upgrade.LAUNCHER_RATE_MULTIPLIERS[3]
	check(is_equal_approx(upgrade.get_bomb_launcher_cooldown(),expected_cooldown),"max_rate_matches_current_balance")
	var destroyed_before: int = gold.destroyed_count
	var bombing_deadline := Time.get_ticks_msec() + 30000
	while gold.destroyed_count <= destroyed_before and Time.get_ticks_msec() < bombing_deadline:
		await process_frame
	check(gold.destroyed_count > destroyed_before,"automatic_bombing_destroys_blocks")
	await shot("four_launchers")
	var panel := current_scene.get_node("UILayer/UpgradePanel")
	panel.open()
	await create_timer(0.25,true,false,true).timeout
	check(paused,"upgrade_pauses_game")
	panel._show_tip(panel._all_cards[0])
	check("\n" in panel._tip_body.text and not "\\n" in panel._tip_body.text,"tooltip_newlines")
	await shot("upgrade_tooltip")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3440,1440)]:
		root.size = dimensions
		await create_timer(0.25,true,false,true).timeout
		var rect: Rect2 = panel._tree.get_global_rect()
		check(root.get_visible_rect().encloses(rect),"upgrade_bounds_"+str(dimensions))
		await shot("upgrade_"+str(dimensions.x)+"x"+str(dimensions.y))
		panel.close()
		var target: Node2D = building.get_child(150)
		var screen_point := target.get_global_transform_with_canvas().origin
		var world_point: Vector2 = root.get_canvas_transform().affine_inverse() * screen_point
		check(hammer._find_blocks(world_point).has(target),"screen_to_hit_mapping_"+str(dimensions))
		panel.open()
	panel.close()
	check(not paused,"upgrade_resumes_game")
	root.size = Vector2i(1920,1080)
	await process_frame
	var settings := current_scene.get_node("UILayer/SettingsPanel")
	settings.open()
	await create_timer(0.25,true,false,true).timeout
	feel._last_slowmo_ms = -100000
	feel.impact(3)
	check(Engine.time_scale < 1,"strong_feedback")
	settings._motion_checkbox.button_pressed = true
	check(Engine.time_scale == 1,"reduced_motion_resets_time")
	feel.impact(3)
	check(Engine.time_scale == 1,"reduced_motion_blocks_slowmo")
	var pref := ConfigFile.new()
	check(pref.load("user://presentation.cfg") == OK and pref.get_value("presentation","reduced_motion",false),"presentation_preferences_saved")
	settings._motion_checkbox.button_pressed = false
	settings._density_select.item_selected.emit(1)
	check(presentation.low_effects,"low_effect_density")
	presentation.low_effects = false
	presentation.save_preferences()
	settings.close()
	var saved_gold: int = gold.total_gold
	save.save_current_slot()
	gold.reset()
	upgrade.reset()
	check(save.load_slot(2),"save_load")
	check(gold.total_gold == saved_gold and upgrade.get_bomb_launcher_count() == 4,"save_values_preserved")
	var hud := current_scene.get_node("GoldHUD")
	hud._on_restart_pressed()
	hud._confirm_restart_cancel()
	check(gold.total_gold == saved_gold,"restart_cancel_preserves_progress")
	hud._confirm_restart_ok()
	await create_timer(1.0,true,false,true).timeout
	check(gold.total_gold == 0 and building.get_child_count() == 360,"restart_resets_scene")
	check(Engine.time_scale == 1,"restart_time_reset")
	var budget: Dictionary = presentation.budget_snapshot()
	var empty := true
	for value in budget.values():
		if int(value) != 0:
			empty = false
	check(empty,"temporary_budget_released",budget)
	gold.add_gold(300000)
	var reincarnation := root.get_node("ReincarnationManager")
	var previous_rp: int = reincarnation.reincarnation_points
	var reinc_panel := current_scene.get_node("UILayer/ReincarnationPanel")
	reinc_panel._on_reincarnate_pressed()
	var expected_rp: int = reincarnation.collect_total_rp(gold.lifetime_gold_this_run)
	check(reinc_panel._confirm.visible,"reincarnation_confirmation")
	reinc_panel._on_confirm_ok()
	await create_timer(2.0,true,false,true).timeout
	check(current_scene.name == "MainMenu","reincarnation_returns_menu")
	check(reincarnation.reincarnation_points == previous_rp+expected_rp,"reincarnation_formula_preserved")
	current_scene._on_start_pressed()
	current_scene._on_slot_selected(2)
	current_scene._on_confirm_pressed()
	await create_timer(2.0,true,false,true).timeout
	check(current_scene.name == "Main","continue_saved_game")
	var music := root.get_node("SoundManager")
	music.set_bgm_index(1)
	check(music._music.stream is AudioStreamMP3 and music._music.stream.loop,"music_has_real_loop")
	check(AudioServer.get_bus_effect_count(0) > 0,"master_limiter_present")
	var report := {"checks":checks,"failures":failures,"user_dir":OS.get_user_data_dir(),"engine":Engine.get_version_info()}
	var file := FileAccess.open(output+"/functional-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("FUNCTIONAL_VERIFICATION_COMPLETE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
