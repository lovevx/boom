extends SceneTree
var checks: Array[Dictionary] = []
var failed := 0
var g: Node
var u: Node
var r: Node
var s: Node
var d: Node
const OUTPUT := "E:/godotproject/boomame/artifacts/demo-pacing"

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.get_texture().get_image().save_png(OUTPUT+"/"+label+".png")

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, name: String) -> void:
	checks.append({"name":name,"passed":ok})
	print("CHECK ",name,": ","PASS" if ok else "FAIL")
	if not ok: failed += 1

func _run() -> void:
	if not "BoomameDemoValidation" in OS.get_user_data_dir():
		quit(2)
		return
	g = root.get_node("GoldManager")
	u = root.get_node("UpgradeManager")
	r = root.get_node("ReincarnationManager")
	s = root.get_node("SaveManager")
	d = root.get_node("DemoProgress")
	d.set_process(false)
	s.start_new_game(0)
	s.onboarding_pending = false
	root.get_node("Presentation").reduced_motion = true
	root.get_node("Presentation").low_effects = true
	for stage in 4:
		r.total_reincarnations = stage
		var threshold: int = r.get_required_run_gold()
		g.lifetime_gold_this_run = threshold - 1
		check(r.collect_total_rp(threshold-1) == 0 and r.reincarnate() == 0, "stage_%d_rejects_below_threshold" % stage)
		check(r.collect_total_rp(threshold) > 0 and r.get_next_rp_gold(0) == threshold, "stage_%d_threshold_and_rp_hint_agree" % stage)
	check(r.collect_total_rp(10000000) == 8, "rp_still_capped_at_8")
	s.start_new_game(0)
	s.onboarding_pending = false
	g.grant_starting_gold(40)
	check(d.gold_earned == 0, "starting_capital_excluded_from_demo_production")
	g.add_gold(123)
	g.register_destroyed()
	check(d.gold_earned == 123 and d.blocks_destroyed == 1, "demo_statistics_include_real_production")
	d.elapsed_seconds = 125.0
	d.scatter_volleys = 4
	s.save_current_slot()
	s.load_slot(0)
	s.load_slot(0)
	check(d.elapsed_seconds == 125.0 and d.scatter_volleys == 4 and d.gold_earned == 123 and d.blocks_destroyed == 1, "repeated_load_preserves_counters_without_rewards")
	s.start_new_game(1)
	check(d.elapsed_seconds == 0.0 and d.scatter_volleys == 0 and not d.is_completed and not d.legacy_save, "new_slot_clears_demo_state")
	s.load_slot(0)
	check(d.elapsed_seconds == 125.0 and d.scatter_volleys == 4, "slot_isolation_restores_demo_state")
	# A real old ConfigFile lacks the demo section, but retains economy and meta.
	var cfg := ConfigFile.new()
	cfg.load(s._slot_path(0))
	cfg.erase_section("demo")
	cfg.save(s._slot_path(0))
	s.load_slot(0)
	check(d.legacy_save and d.elapsed_seconds == 0.0 and g.lifetime_gold_this_run == 123, "legacy_save_keeps_progress_defaults_demo_clock")
	r.total_reincarnations = 2
	d.register_scatter_volley(3)
	check(d.scatter_volleys == 0, "scatter_count_requires_final_phase")
	r.total_reincarnations = 3
	d.register_scatter_volley(1)
	check(d.scatter_volleys == 0, "single_projectile_not_scatter")
	d.register_scatter_volley(2)
	check(d.scatter_volleys == 1, "one_scatter_round_counts_once")
	d.elapsed_seconds = 145.0
	g.reset()
	check(d.scatter_volleys == 0 and d.elapsed_seconds == 145.0 and d.legacy_save, "run_reset_preserves_elapsed_and_legacy_clears_volleys")
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	var building := current_scene.get_node("Building")
	while building.get_child_count() < 360: await process_frame
	await physics_frame
	var hud := current_scene.get_node("GoldHUD")
	var summary: Node = hud.get_node("DemoSummary")
	summary.set_process(false)
	var tree := current_scene.get_node("UILayer/UpgradePanel")
	var settings := current_scene.get_node("UILayer/SettingsPanel")
	var rebirth := current_scene.get_node("UILayer/ReincarnationPanel")
	hud._update_engineer_card()
	var goal_target: float = hud._rebirth_progress.max_value
	g.lifetime_gold_this_run = 64000
	hud._update_engineer_card()
	check(hud._rebirth_progress.max_value == goal_target and goal_target == d.finale_gold, "engineering_goal_does_not_jump_with_rp_brackets")
	rebirth.open()
	rebirth._on_reincarnate_pressed()
	check(rebirth._cf_warn.text.contains("散射进度"), "early_finale_rebirth_warns_about_reset")
	await capture("finale-rebirth-warning")
	rebirth.close()
	await capture("finale-hud")
	d._last_clock_ms = -10000
	d._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(d._last_clock_ms >= 0, "focus_in_discards_suspended_background_gap")
	d._last_clock_ms = 1000
	d.elapsed_seconds = 0.0
	d._sample_clock(2000,true)
	check(d.elapsed_seconds == 1.0, "clock_counts_gameplay")
	tree.open()
	d._sample_clock(3000,true)
	check(d.elapsed_seconds == 2.0, "clock_counts_skill_reading_while_paused")
	tree.close()
	rebirth.open()
	d._sample_clock(4000,true)
	check(d.elapsed_seconds == 3.0, "clock_counts_rebirth_reading")
	rebirth.close()
	settings.open()
	d._sample_clock(5000,true)
	check(d.elapsed_seconds == 3.0, "clock_excludes_settings")
	settings.close()
	d._sample_clock(6000,false)
	check(d.elapsed_seconds == 3.0, "clock_excludes_unfocused_window")
	Engine.time_scale = 0.35
	d._sample_clock(7000,true)
	check(d.elapsed_seconds == 4.0, "clock_uses_real_seconds_despite_hitstop")
	Engine.time_scale = 1.0
	root.get_node("ScreenTransition")._busy = true
	d._sample_clock(8000,true)
	check(d.elapsed_seconds == 4.0, "clock_excludes_scene_transition")
	root.get_node("ScreenTransition")._busy = false
	# Real launcher path, including multi-projectile spawning.
	u.set_state_from_save({"bomb_launcher":1})
	g.total_gold = 1000
	check(not u.purchase_node("scatter"), "scatter_requires_radius_upgrade")
	u.set_state_from_save({"bomb_launcher":1,"bomb_radius":1})
	check(u.purchase_node("scatter") and u.get_scatter_count() == 2, "scatter_available_with_radius_level_one")
	u.set_state_from_save({"bomb_launcher":1,"scatter":1,"bomb_radius":2})
	var launcher: Node2D = current_scene.get_node("LauncherManager")._launchers[0]
	launcher._timer.stop()
	d.scatter_volleys = 0
	launcher._launch_bomb(Vector2(960,600))
	check(d.scatter_volleys == 1, "real_launcher_registers_a_scatter_round")
	g.lifetime_gold_this_run = d.finale_gold
	d.scatter_volleys = d.required_scatter_volleys - 1
	d.check_completion()
	check(not d.is_completed, "gold_alone_cannot_complete_demo")
	d.scatter_volleys += 1
	g.lifetime_gold_this_run = d.finale_gold - 1
	d.check_completion()
	check(not d.is_completed, "scatter_alone_cannot_complete_demo")
	g.lifetime_gold_this_run = d.finale_gold
	var completions := [0]
	d.completed.connect(func() -> void: completions[0] += 1)
	d.check_completion()
	d.check_completion()
	check(d.is_completed and completions[0] == 1 and not d.summary_shown, "completion_fires_once_and_saves_pending_summary")
	s.load_slot(0)
	check(d.is_completed and not d.summary_shown, "pending_summary_survives_reload")
	tree.open()
	summary._process(0)
	check(not d.summary_shown and not summary._overlay.visible, "completion_waits_until_existing_modal_closes")
	tree.close()
	summary._process(0)
	await process_frame
	check(paused and summary._overlay.visible and d.summary_shown and not summary._body.text.is_empty(), "completion_dialog_pauses_and_displays_results")
	await capture("completion")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3440,1440)]:
		root.size = dimensions
		await process_frame
		var frame: Control = summary._overlay.get_node("DemoResult")
		check(root.get_visible_rect().grow(1).encloses(root.get_node("Presentation").screen_rect(frame)), "summary_fits_"+str(dimensions))
	summary._close()
	check(not paused and not summary._overlay.visible, "continue_playing_restores_pause")
	s.load_slot(0)
	summary._process(0)
	check(d.summary_shown and d.is_completed and not summary._overlay.visible, "completed_save_never_reopens_automatic_summary")
	var result: Dictionary = d.completion_stats.duplicate(true)
	hud._confirm_restart_ok()
	await process_frame
	check(d.is_completed and d.completion_stats == result and d.scatter_volleys == 0, "restart_preserves_completed_result")
	summary._show_result()
	summary._menu()
	await scene_changed
	check(not paused and current_scene.scene_file_path == "res://scenes/MainMenu.tscn", "completion_return_to_menu_uses_real_save_and_transition")
	d.is_completed = false
	d._last_clock_ms = 8000
	d._sample_clock(9000,true)
	check(d.elapsed_seconds == 4.0, "clock_excludes_main_menu")
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var file := FileAccess.open(OUTPUT+"/verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failed":failed,"checks":checks},"\t"))
	print("DEMO_PACING_VERIFY_", "PASS" if failed == 0 else "FAIL", " checks=", checks.size())
	quit(0 if failed == 0 else 1)
