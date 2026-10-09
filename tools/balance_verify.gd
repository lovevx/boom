extends SceneTree
## Run only in the isolated BoomameBalanceValidation copy.
var checks: Array[Dictionary] = []
var failed := 0
var game_time := 0.0
var output := "E:/godotproject/boomame/artifacts/balance"

func _initialize() -> void:
	_run.call_deferred()

func _process(delta: float) -> bool:
	game_time += delta
	return false

func check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"name": label, "passed": ok, "detail": detail})
	print("CHECK ", label, ": ", "PASS" if ok else "FAIL")
	if not ok:
		failed += 1

func _run() -> void:
	if not "BoomameBalanceValidation" in OS.get_user_data_dir():
		push_error("Refusing to test player saves")
		quit(2)
		return
	var gold := root.get_node("GoldManager")
	var upgrade := root.get_node("UpgradeManager")
	var rebirth := root.get_node("ReincarnationManager")
	var save := root.get_node("SaveManager")
	var presentation := root.get_node("Presentation")
	save.start_new_game(2)
	save.onboarding_pending = false
	check(upgrade.get_hammer_damage_cost() == 2, "tutorial_first_damage_cost")
	check(not upgrade.purchase_node("hammer_damage"), "insufficient_gold_rejected")
	gold.add_gold(10000)
	check(not upgrade.purchase_node("bomb_damage"), "locked_purchase_rejected")
	check(upgrade.purchase_node("hammer_damage"), "purchase_debits_and_upgrades")
	check(gold.total_gold == 9998 and is_equal_approx(upgrade.hammer_damage, 1.5), "first_damage_gain")
	upgrade.purchase_node("hammer_damage")
	upgrade.purchase_node("hammer_damage")
	var before: int = gold.total_gold
	check(not upgrade.purchase_node("hammer_damage") and gold.total_gold == before, "maxed_node_does_not_consume_gold")
	check(upgrade.get_hammer_damage_cost() == -1, "maxed_cost_sentinel")
	check(rebirth.collect_total_rp(3999) == 0 and rebirth.collect_total_rp(4000) == 2, "first_rebirth_boundary")
	check(rebirth.collect_total_rp(9000) == 3 and rebirth.collect_total_rp(16000) == 4, "deep_rebirth_curve")
	check(rebirth.collect_total_rp(64000) == 8 and rebirth.collect_total_rp(1000000) == 8 and rebirth.get_next_rp_gold(64000) == 0, "per_run_rp_cap")
	check(rebirth.get_next_rp_gold(0) == 4000 and rebirth.get_next_rp_gold(4000) == 9000, "next_rp_threshold")
	gold.reset()
	var count: int = rebirth.total_reincarnations
	check(rebirth.reincarnate() == 0 and rebirth.total_reincarnations == count, "zero_reward_cannot_farm_unlocks")
	gold.add_gold(4000)
	check(rebirth.reincarnate() == 2 and rebirth.total_reincarnations == count + 1, "valid_rebirth_grants_points")
	check(rebirth.get_starting_launcher_count() == 1 and rebirth.is_mechanic_unlocked("crit"), "first_rebirth_unlocks")
	rebirth.reincarnation_points = 100
	check(not rebirth.purchase_node("auto_hammer"), "permanent_branch_prerequisite")
	check(rebirth.purchase_node("base_damage"), "permanent_root_purchase")
	check(rebirth.purchase_node("destroy_power"), "permanent_child_purchase")
	check(is_equal_approx(upgrade.hammer_damage, 2.75 * 1.2), "run_and_permanent_multiply")
	check(is_equal_approx(rebirth.get_hammer_base_damage(), 1.5), "fractional_base_damage_retained")
	check(rebirth.purchase_node("coin_heart"), "economy_root_purchase")
	var lifetime: int = gold.lifetime_gold_this_run
	var career: int = gold.stats_gold_earned
	check(rebirth.purchase_node("initial_capital"), "capital_purchase")
	check(gold.lifetime_gold_this_run == lifetime and gold.stats_gold_earned == career, "capital_excluded_from_rp_and_career")
	upgrade.recalculate_stats()
	var damage: float = upgrade.hammer_damage
	upgrade.recalculate_stats()
	check(is_equal_approx(upgrade.hammer_damage, damage), "bonus_recalculation_idempotent")
	rebirth.purchase_node("auto_hammer")
	upgrade.purchase_node("hammer_range")
	upgrade.purchase_node("coin_base")
	upgrade.purchase_node("bomb_launcher")
	var saved_levels: Dictionary = save._collect_upgrade_levels()
	var saved_total: int = gold.total_gold
	var saved_damage: float = upgrade.hammer_damage
	save.save_current_slot()
	save.load_slot(2)
	save.load_slot(2)
	check(save._collect_upgrade_levels() == saved_levels and gold.total_gold == saved_total, "save_load_levels_and_balance")
	check(is_equal_approx(upgrade.hammer_damage, saved_damage), "save_load_preserves_permanent_product")
	check(gold.stats_gold_earned == career, "load_never_grants_income")
	check(upgrade.crit_multiplier == 2.0, "crit_chance_has_immediate_damage_gain")
	for n in [0, 1, 2, 3, 5, 8]:
		rebirth.total_reincarnations = n
		var expected: int = {0:0, 1:1, 2:1, 3:2, 5:3, 8:4}[n]
		check(rebirth.get_starting_launcher_count() == expected, "launcher_milestone_%d" % n)
	save.start_new_game(1)
	check(rebirth.total_reincarnations == 0 and rebirth.permanent_nodes.is_empty() and rebirth.reincarnation_points == 0, "new_slot_does_not_inherit_meta")
	save.onboarding_pending = false
	presentation.reduced_motion = true
	presentation.low_effects = true
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	await create_timer(1.0).timeout
	var panel := current_scene.get_node("UILayer/UpgradePanel")
	var reinc_panel := current_scene.get_node("UILayer/ReincarnationPanel")
	gold.add_gold(100000)
	panel.open()
	var max_card: Dictionary
	for card in panel._all_cards:
		if card.id == "hammer_damage":
			max_card = card
	for i in 3:
		panel._try_upgrade(max_card)
	before = gold.total_gold
	panel._try_upgrade(max_card)
	check(before == gold.total_gold, "ui_maxed_click_does_not_spend")
	check(panel._tip_body.text.contains("锤击伤害"), "tooltip_uses_actual_damage")
	panel.close()
	reinc_panel.open()
	check(paused and not reinc_panel._reinc_btn.disabled, "rebirth_modal_pauses_game")
	reinc_panel.close()
	check(not paused, "rebirth_modal_restores_pause")
	# A center blast must hit >32 blocks and must be independent of hammer upgrades.
	var blast: Node2D = load("res://scenes/BombProjectile.tscn").instantiate()
	current_scene.add_child(blast)
	blast.set_physics_process(false)
	blast.position = Vector2(960, 580)
	blast.radius = 200.0
	blast.damage = 0.01
	var building := current_scene.get_node("Building")
	var block_hps := {}
	for b in building.get_children():
		block_hps[b] = b.hp
	blast._damage_blocks()
	var hits := 0
	var max_hit := 0.0
	for b in block_hps:
		var delta: float = block_hps[b] - b.hp
		if delta > 0.0:
			hits += 1
			max_hit = maxf(max_hit, delta)
	check(hits > 32, "large_blast_not_capped_at_32", hits)
	check(max_hit <= 0.01001, "bomb_damage_independent_from_hammer", max_hit)
	blast.queue_free()
	# Automatic hammer should work while the cursor is outside the building.
	upgrade.auto_hammer = true
	var hammer := current_scene.get_node("Hammer")
	before = gold.destroyed_count
	for i in 6:
		hammer._maybe_auto_smash()
		await process_frame
	check(gold.destroyed_count > before, "auto_hammer_targets_building")
	upgrade.auto_hammer = false
	for i in 4:
		upgrade.upgrade_bomb_launcher()
	for i in 3:
		upgrade.upgrade_bomb_rate()
	check(is_equal_approx(upgrade.get_bomb_launcher_cooldown(), 3.4 * 0.60), "quantity_does_not_double_boost_rate")
	var launcher: Node2D = current_scene.get_node("LauncherManager")._launchers[0]
	await create_timer(0.3).timeout
	var shot_times: Array[float] = []
	var observe := func(node: Node) -> void:
		if node.get_script() and node.get_script().resource_path == "res://scripts/BombProjectile.gd" and node.origin_launcher == launcher:
			shot_times.append(game_time)
	node_added.connect(observe)
	launcher._timer.stop()
	launcher._on_cooldown_timeout()
	check(launcher._turret.speed_scale > 1.0, "fire_animation_scales_with_rate")
	await create_timer(6.5).timeout
	node_added.disconnect(observe)
	check(shot_times.size() >= 3, "live_max_rate_shot_count", shot_times)
	if shot_times.size() >= 2:
		check(absf(shot_times[1] - shot_times[0] - 2.04) < 0.15, "live_max_rate_matches_cooldown", shot_times[1] - shot_times[0])
	check(gold.destroyed_count > before, "live_automation_destroys_blocks")
	# Exercise the real confirmation, reset, save and scene-transition chain.
	rebirth.permanent_nodes = {"coin_heart": 1, "initial_capital": 1, "base_damage": 1}
	upgrade.recalculate_stats()
	gold.lifetime_gold_this_run = 64000
	rebirth.total_reincarnations = 0
	rebirth.reincarnation_points = 0
	reinc_panel.open()
	reinc_panel._on_reincarnate_pressed()
	reinc_panel._on_confirm_ok()
	await scene_changed
	await process_frame
	check(not paused and current_scene.scene_file_path == "res://scenes/MainMenu.tscn", "rebirth_confirmation_returns_to_menu")
	check(rebirth.reincarnation_points == 8 and rebirth.total_reincarnations == 1 and rebirth.get_node_level("base_damage") == 1, "rebirth_preserves_meta_and_grants_rp")
	check(gold.total_gold == 20 and gold.lifetime_gold_this_run == 0 and gold.destroyed_count == 0, "rebirth_resets_run_and_grants_capital_once")
	check(upgrade.get_hammer_damage_level() == 0 and upgrade.get_bomb_launcher_count() == 1, "rebirth_restores_starting_upgrade_state")
	save.load_slot(1)
	check(gold.total_gold == 20 and gold.lifetime_gold_this_run == 0 and rebirth.reincarnation_points == 8, "rebirth_state_persisted")
	paused = false
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output + "/verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failed": failed, "checks": checks}, "\t"))
	print("BALANCE_VERIFY_", "PASS" if failed == 0 else "FAIL", " checks=", checks.size())
	await create_timer(0.2).timeout
	quit(0 if failed == 0 else 1)
