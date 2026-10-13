extends SceneTree
## Rendered regression and visual capture. Never runs against player saves.
const OUTPUT := "E:/godotproject/boomame/artifacts/motion/after"
var failures: Array[String] = []
var checks: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	print("MOTION_CHECK ", label, ": ", "PASS" if ok else "FAIL")
	if not ok:
		failures.append(label)

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(label + ".png"))

func _run() -> void:
	if not "PresentationValidationMotion" in OS.get_user_data_dir():
		push_error("Run in the isolated motion validation project")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	seed(719)
	var save := root.get_node("SaveManager")
	var gold := root.get_node("GoldManager")
	var upgrades := root.get_node("UpgradeManager")
	var presentation := root.get_node("Presentation")
	var feel := root.get_node("GameFeel")
	save.start_new_game(1)
	save.onboarding_pending = false
	presentation.reduced_motion = false
	presentation.low_effects = false
	presentation.shake_strength = 0.0
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	await create_timer(1.0).timeout
	current_scene.get_node("TestPanel").hide()
	var building := current_scene.get_node("Building")
	var hammer := current_scene.get_node("Hammer")
	check(building.get_child_count() == 360, "initial_tower")
	var block: Node2D = building.get_child(8)
	var at := block.global_position
	var hp: float = block.hp
	hammer._smash(at)
	check(is_equal_approx(block.hp, hp - 1.0), "hammer_damage_preserved")
	feel.reset()
	await create_timer(0.07).timeout
	await shot("hammer_impact")
	await create_timer(0.8).timeout
	var bomb: Node2D = load("res://scenes/BombProjectile.tscn").instantiate()
	bomb.position = Vector2(585, 700)
	current_scene.add_child(bomb)
	bomb.set_initial_velocity(Vector2(120, -90))
	await create_timer(0.2).timeout
	check(bomb._trail.size() > 2 and bomb._trail.size() <= presentation.PROFILE.trail_points, "bounded_world_space_trail")
	await shot("projectile_trail")
	presentation.low_effects = true
	await physics_frame
	await physics_frame
	check(bomb._trail.size() <= 5, "low_effects_shortens_trail")
	presentation.reduced_motion = true
	await physics_frame
	await physics_frame
	check(bomb._trail.is_empty(), "reduced_motion_clears_trail")
	bomb.queue_free()
	presentation.reduced_motion = false
	presentation.low_effects = false
	var target: Node2D = building.get_child(120)
	var target_at := target.global_position
	var expected_gold: int = target.gold_value
	var before_gold: int = gold.total_gold
	target.register_hit_origin(target_at - Vector2(50,0))
	target.take_damage(10000.0)
	check(gold.total_gold == before_gold + expected_gold, "shatter_reward_preserved")
	await process_frame
	var material_fx: Node2D
	for node in get_nodes_in_group("in_game_entity"):
		if node.get_script() == load("res://scripts/PixelExplosion.gd"):
			material_fx = node
			break
	check(is_instance_valid(material_fx) and material_fx.global_position.is_equal_approx(target_at), "shards_spawn_at_destroyed_material")
	var blast: Node2D = load("res://scripts/BlastFx.gd").new()
	blast.position = target_at
	blast.blast_radius = 115.0
	current_scene.add_child(blast)
	feel.reset()
	await create_timer(0.14).timeout
	await shot("blast_pressure")
	await create_timer(1.4).timeout
	check(not is_instance_valid(blast), "blast_cleanup")
	check(building.get_child_count() == 360, "collapse_refill_preserved")
	var reservation := Node.new()
	root.add_child(reservation)
	check(presentation.admit(reservation, "hit", presentation.PROFILE.hit_limit), "reserve_impact_budget")
	var denied: Node2D = load("res://scripts/ImpactFx.gd").new()
	current_scene.add_child(denied)
	await process_frame
	check(not is_instance_valid(denied), "impact_budget_enforced")
	reservation.free()
	var paused_fx: Node2D = load("res://scripts/ImpactFx.gd").new()
	paused_fx.position = Vector2(600,650)
	current_scene.add_child(paused_fx)
	paused = true
	await create_timer(0.35, true).timeout
	check(is_instance_valid(paused_fx) and paused_fx._age == 0.0, "effects_pause_with_game")
	paused = false
	await create_timer(0.4).timeout
	check(not is_instance_valid(paused_fx), "effects_resume_and_cleanup")
	for i in 4:
		upgrades.upgrade_bomb_launcher()
	for i in 3:
		upgrades.upgrade_bomb_rate()
	for i in 5:
		upgrades.upgrade_bomb_damage()
		upgrades.upgrade_bomb_radius()
	var initial_destroyed: int = gold.destroyed_count
	var peaks := {}
	var fps_samples: Array[int] = []
	for second in 35:
		await create_timer(1.0, true, false, true).timeout
		var budget: Dictionary = presentation.budget_snapshot()
		for kind in budget:
			peaks[kind] = maxi(int(peaks.get(kind, 0)), int(budget[kind]))
		if second > 5:
			fps_samples.append(Engine.get_frames_per_second())
		if second == 9:
			await shot("four_launchers")
	check(gold.destroyed_count > initial_destroyed, "four_launchers_automatic_destruction")
	var bounded := true
	for kind in peaks:
		bounded = bounded and peaks[kind] <= int(presentation.PROFILE.get(kind + "_limit"))
	check(bounded, "all_visual_budgets_bounded")
	var stress_destroyed: int = gold.destroyed_count - initial_destroyed
	current_scene.get_node("GoldHUD")._confirm_restart_ok()
	await create_timer(1.5, true, false, true).timeout
	var clear := true
	for value in presentation.budget_snapshot().values():
		clear = clear and int(value) == 0
	check(clear, "restart_releases_all_effect_budgets")
	check(Engine.time_scale == 1.0, "restart_restores_time_scale")
	fps_samples.sort()
	var report := {"checks": checks, "failures": failures, "budget_peaks": peaks,
		"rendered_stress_seconds":35, "median_fps": fps_samples[fps_samples.size()/2],
		"minimum_sample_fps":fps_samples[0], "destroyed_during_stress": stress_destroyed,
		"renderer": RenderingServer.get_video_adapter_name()}
	FileAccess.open(OUTPUT.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MOTION_COMPLETE ", JSON.stringify(report))
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await scene_changed
	await create_timer(0.5).timeout
	quit(0 if failures.is_empty() else 1)
