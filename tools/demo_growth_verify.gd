extends SceneTree
## Only run in the isolated BoomameDemoValidation copy.
var checks: Array[Dictionary] = []
var failed := 0
var output := "E:/godotproject/boomame/artifacts/demo-growth"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"name":label, "passed":ok, "detail":detail})
	print("CHECK ", label, ": ", "PASS" if ok else "FAIL", " ", detail)
	if not ok:
		failed += 1

func _run() -> void:
	if not "BoomameDemoValidation" in OS.get_user_data_dir():
		quit(2)
		return
	var u := root.get_node("UpgradeManager")
	var r := root.get_node("ReincarnationManager")
	var g := root.get_node("GoldManager")
	var s := root.get_node("SaveManager")
	s.start_new_game(0)
	s.onboarding_pending = false
	check(u.NODE_TITLES.size() + u.DEMO_NODES.size() == 24 and r.NODE_DEFS.size() == 21, "24_run_21_permanent_nodes")
	g.add_gold(1000000)
	var before: int = g.total_gold
	check(not u.purchase_node("combo") and g.total_gold == before, "new_prerequisite_rejects_without_charge")
	u.purchase_node("hammer_speed")
	check(u.purchase_node("combo"), "combo_available_in_first_run")
	check(not u.purchase_node("power_strike"), "first_rebirth_gate")
	r.reincarnation_points = 100
	check(not r.purchase_node("combo_memory"), "permanent_rebirth_gate")
	r.total_reincarnations = 3
	for nid in u.NODE_TITLES:
		while u.purchase_node(nid):
			pass
	# Retry dependent nodes after all baseline prerequisites are available.
	for nid in u.DEMO_NODES:
		while u.purchase_node(nid):
			pass
	var all_maxed := true
	for nid in u.DEMO_NODES:
		all_maxed = all_maxed and u.get_node_state(nid).state == "maxed" and u.get_node_cost(nid) == -1
	check(all_maxed, "all_10_new_nodes_purchase_and_cap")
	for nid in r.NODE_DEFS:
		while r.purchase_node(nid):
			pass
	check(r.get_node_level("barrage_training") == 2 and u.get_barrage_period() == 2, "permanent_fire_control_changes_cycle")
	check(is_equal_approx(u.get_cost_discount(), 0.25), "combined_discount_cap")
	var levels: Dictionary = s._collect_upgrade_levels()
	var permanent: Dictionary = r.permanent_nodes.duplicate()
	before = g.total_gold
	s.save_current_slot()
	s.load_slot(0)
	s.load_slot(0)
	check(s._collect_upgrade_levels() == levels and g.total_gold == before and r.permanent_nodes == permanent, "new_and_old_nodes_roundtrip_without_double_rewards")
	s.start_new_game(1)
	check(u.demo_levels.is_empty() and r.permanent_nodes.is_empty(), "slot_isolation_clears_expansion")
	u.set_state_from_save({"hammer_speed":1})
	check(u._get_node_level("combo") == 0 and u.get_hammer_speed_level() == 1, "legacy_save_defaults_new_nodes_to_zero")
	u.set_state_from_save({"combo":999,"aftershock":-4})
	check(u._get_node_level("combo") == 3 and u._get_node_level("aftershock") == 0, "new_save_levels_clamped")
	u.reset()
	u.demo_levels = {"contract":1}
	g.restore_state(0,0,49)
	g.register_destroyed()
	check(g.total_gold == 40 and g.lifetime_gold_this_run == 40, "contract_pays_at_50_and_counts_as_production")
	s.save_current_slot()
	s.load_slot(1)
	check(g.total_gold == 40, "contract_not_reissued_on_load")
	for i in 49:
		g.register_destroyed()
	check(g.total_gold == 40, "contract_waits_for_next_boundary")
	g.register_destroyed()
	check(g.total_gold == 80, "contract_repeatable_per_50_blocks")
	u.reset()
	u.demo_levels = {"discount":3}
	r.permanent_nodes = {"procurement":2}
	check(u.get_node_cost("hammer_damage") == 2 and u.get_node_cost("bomb_launcher") == 30, "discount_rounds_up_and_applies_to_existing_nodes")
	g.restore_state(1000,0,0)
	check(u.purchase_node("bomb_launcher") and g.total_gold == 970, "actual_purchase_matches_discounted_ui_cost")
	u.reset()
	r.permanent_nodes.clear()
	root.get_node("Presentation").reduced_motion = true
	root.get_node("Presentation").low_effects = true
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	var building := current_scene.get_node("Building")
	while building.get_child_count() < 360:
		await process_frame
	await physics_frame
	var panel := current_scene.get_node("UILayer/UpgradePanel")
	var rebirth_panel := current_scene.get_node("UILayer/ReincarnationPanel")
	check(panel._all_cards.size() == 24 and rebirth_panel._rows.size() == 21, "all_new_nodes_visible_in_real_panels")
	var centers := {}
	var layout_ok := true
	for card in panel._all_cards:
		layout_ok = layout_ok and not centers.has(card.center) and Rect2(Vector2(40,90),Vector2(1720,710)).has_point(card.center)
		centers[card.center] = true
		panel._show_tip(card)
		layout_ok = layout_ok and not panel._tip_body.text.is_empty()
	panel._hide_tip()
	check(layout_ok, "unique_in_bounds_positions_and_effect_tooltips")
	var hammer := current_scene.get_node("Hammer")
	var block: Node2D = building._cols[5][20]
	var neighbor: Node2D = building._cols[6][20]
	for b in building.get_children():
		b.hp = 10000.0
		b.max_hp = 10000.0
	u.demo_levels = {"combo":3}
	for i in 6:
		hammer._smash(block.global_position)
	check(is_equal_approx(10000.0 - block.hp, 8.4) and hammer._combo_stacks == 5, "real_combo_damage_ramp_and_stack_cap", 10000.0 - block.hp)
	hammer._process(1.6)
	check(hammer._combo_stacks == 0, "combo_timeout_uses_game_time")
	hammer._smash(block.global_position)
	hammer._smash(Vector2(100,100))
	check(hammer._combo_stacks == 0, "miss_clears_combo")
	g.reset()
	u.demo_levels = {"power_strike":3}
	block.hp = 10000.0
	for i in 3:
		hammer._smash(block.global_position)
	check(is_equal_approx(10000.0 - block.hp, 4.5) and neighbor.hp < 10000.0, "third_real_hit_boosts_damage_and_hits_neighbor", 10000.0 - block.hp)
	u.demo_levels = {"execute":3}
	block.hp = 5000.0
	hammer._smash(block.global_position)
	check(is_equal_approx(5000.0 - block.hp, 1.75), "real_hammer_execute_damage")
	u.demo_levels = {"falling_damage":3}
	block._falling = true
	before = roundi(block.hp * 100)
	hammer._smash(block.global_position)
	check(is_equal_approx(before / 100.0 - block.hp, 1.75), "real_hammer_falling_target_bonus")
	u.demo_levels = {"salvage":2}
	r.permanent_nodes = {"salvage_license":1}
	g.restore_state(0,0,0)
	block._spawn_gold()
	check(g.total_gold == block.gold_value + 3, "falling_block_real_reward_with_permanent_salvage")
	block._falling = false
	u.demo_levels = {"blast_floor":3}
	r.permanent_nodes.clear()
	var bomb: Node2D = load("res://scenes/BombProjectile.tscn").instantiate()
	current_scene.add_child(bomb)
	bomb.set_physics_process(false)
	bomb.position = block.global_position
	bomb.radius = 100.0
	bomb.damage = 1.0
	var neighbor_hp: float = neighbor.hp
	bomb._damage_blocks()
	check(is_equal_approx(neighbor_hp - neighbor.hp, 0.6), "real_blast_edge_floor", neighbor_hp - neighbor.hp)
	bomb.queue_free()
	u.demo_levels = {"aftershock":1}
	var primary: Node2D = load("res://scenes/BombProjectile.tscn").instantiate()
	current_scene.add_child(primary)
	primary.set_physics_process(false)
	primary.position = block.global_position
	primary.radius = 80.0
	primary.damage = 10.0
	primary._explode()
	var after_primary: float = block.hp
	await create_timer(0.2).timeout
	check(is_equal_approx(block.hp, after_primary), "aftershock_waits_before_dealing_damage")
	await create_timer(0.4).timeout
	check(is_equal_approx(after_primary - block.hp, 2.0), "real_aftershock_damage_at_original_center", after_primary - block.hp)
	var echoes := 0
	for node in current_scene.get_children():
		if node.get_script() and node.get_script().resource_path == "res://scripts/Aftershock.gd":
			echoes += 1
	check(echoes == 0, "aftershock_is_one_shot_without_recursive_spawns")
	u.demo_levels = {"barrage":3}
	u.upgrade_bomb_launcher()
	var launcher: Node2D = current_scene.get_node("LauncherManager")._launchers[0]
	launcher._timer.stop()
	launcher._volley_count = 0
	for i in 4:
		launcher._launch_bomb(block.global_position)
	check(is_equal_approx(launcher._volley_multiplier, 2.5), "fourth_real_volley_is_empowered")
	var heavy_projectile := false
	for node in current_scene.get_children():
		if node.get_script() and node.get_script().resource_path == "res://scripts/BombProjectile.gd":
			heavy_projectile = heavy_projectile or is_equal_approx(node.damage, u.get_bomb_launcher_damage() * 2.5)
	check(heavy_projectile, "empowered_damage_reaches_real_projectile")
	g.reset()
	check(launcher._volley_count == 0 and hammer._effective_swings == 0, "run_reset_clears_weapon_counters")
	# Exercise new delayed blasts and falling rewards on the real collapsing grid.
	u.reset()
	for node in get_nodes_in_group(&"in_game_entity"):
		node.queue_free()
	await process_frame
	building.reset()
	while building.get_child_count() < 360:
		await process_frame
	await physics_frame
	u.demo_levels = {"aftershock":3,"falling_damage":3,"salvage":3,"contract":3,"blast_floor":3}
	u.chain_damage = 0.45
	var mixed: Node2D = load("res://scenes/BombProjectile.tscn").instantiate()
	current_scene.add_child(mixed)
	mixed.set_physics_process(false)
	mixed.position = Vector2(960,700)
	mixed.radius = 170.0
	mixed.damage = 18.0
	mixed._explode()
	await create_timer(3.0).timeout
	var grid_ok: bool = building._falling_blocks == 0
	for column in building._cols:
		var occupied := {}
		grid_ok = grid_ok and column.size() == 30
		for b in column:
			grid_ok = grid_ok and not occupied.has(b.level) and not b.is_falling() and b.position.is_equal_approx(Vector2(b.col * 40.0,b.level * 40.0))
			occupied[b.level] = true
	check(grid_ok and g.destroyed_count > 50, "chain_aftershock_falling_rewards_settle_to_360_unique_slots", g.destroyed_count)
	var pending: Node2D = load("res://scripts/Aftershock.gd").new()
	current_scene.add_child(pending)
	pending.position = Vector2(960,700)
	u.demo_levels = {"combo":3,"aftershock":2}
	current_scene.get_node("GoldHUD")._confirm_restart_ok()
	await process_frame
	check(not is_instance_valid(pending) and u.demo_levels.is_empty(), "restart_removes_pending_aftershock_and_run_skills")
	# Real UI rebirth must clear all new run levels and preserve the new permanent tree.
	u.demo_levels = {"combo":3,"aftershock":2}
	r.permanent_nodes = {"combo_memory":1}
	r.total_reincarnations = 2
	r.reincarnation_points = 0
	g.lifetime_gold_this_run = r.get_required_run_gold()
	rebirth_panel.open()
	rebirth_panel._on_reincarnate_pressed()
	rebirth_panel._on_confirm_ok()
	await scene_changed
	check(u.demo_levels.is_empty() and r.get_node_level("combo_memory") == 1 and r.total_reincarnations == 3, "real_rebirth_clears_new_run_nodes_preserves_specialization")
	s.load_slot(1)
	check(u._get_node_level("aftershock") == 0 and r.get_node_level("combo_memory") == 1, "rebirth_expansion_state_persisted")
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output + "/verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failed":failed,"checks":checks}, "\t"))
	print("DEMO_GROWTH_VERIFY_", "PASS" if failed == 0 else "FAIL", " checks=", checks.size())
	quit(0 if failed == 0 else 1)
