extends SceneTree
## Run in a copy whose application name is BoomameCollapseValidation.
var checks: Array[Dictionary] = []
var failed := 0
var building: Node2D
var grid_error: Dictionary = {}
var output := "E:/godotproject/boomame/artifacts/collapse"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"name": label, "passed": ok, "detail": detail})
	print("CHECK ", label, ": ", "PASS" if ok else "FAIL", " ", detail)
	if not ok:
		failed += 1

func fresh() -> void:
	root.get_node("UpgradeManager").reset()
	root.get_node("GameFeel").reset()
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	building = current_scene.get_node("Building")
	while building.get_child_count() < 360:
		await process_frame
	await process_frame
	await physics_frame

func block_at(col: int, level: int) -> Node2D:
	for block in building._cols[col]:
		if block.effective_level() == level:
			return block
	return null

func grid_ok() -> bool:
	grid_error = {}
	for c in range(building._cols.size()):
		var col: Array = building._cols[c]
		if col.size() != 30:
			grid_error = {"column": c, "count": col.size()}
			return false
		var occupied := {}
		for block in col:
			if not is_instance_valid(block) or block.is_falling():
				grid_error = {"column": c, "unsettled": true}
				return false
			if occupied.has(block.level):
				grid_error = {"column": c, "duplicate_level": block.level}
				return false
			occupied[block.level] = true
			if not block.position.is_equal_approx(Vector2(block.col * 40.0, block.level * 40.0)):
				grid_error = {"column": c, "level": block.level, "position": str(block.position)}
				return false
	if building._falling_blocks != 0:
		grid_error = {"falling_count": building._falling_blocks}
	return building._falling_blocks == 0

func settle() -> void:
	await create_timer(1.0, true, false, true).timeout
	# Large chains can make a headless frame expensive. Wait for actual landing
	# completion rather than treating one elapsed second as a settled tower.
	var deadline := Time.get_ticks_msec() + 5000
	while (building._falling_blocks > 0 or not building._pending_columns.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame

func _run() -> void:
	if not "BoomameCollapseValidation" in OS.get_user_data_dir():
		push_error("Refusing to test player saves")
		quit(2)
		return
	root.get_node("SaveManager").active_slot = -1
	root.get_node("SaveManager").onboarding_pending = false
	root.get_node("Presentation").reduced_motion = true
	root.get_node("Presentation").low_effects = true
	seed(719)

	await fresh()
	var upper := block_at(5, 19)
	block_at(5, 20).take_damage(1000)
	await settle()
	check(upper.level == 20 and grid_ok(), "single_break_drops_and_refills")

	await fresh()
	upper = block_at(5, 19)
	upper.launch(Vector2(1, -1), 180)
	block_at(5, 20).take_damage(1000)
	await settle()
	check(upper.level == 20 and grid_ok(), "hit_recoil_cannot_undo_fall", {"level": upper.level, "position": str(upper.position)})

	await fresh()
	upper = block_at(5, 19)
	upper.launch(Vector2(1, -1), 180)
	await create_timer(0.03).timeout
	upper.launch(Vector2(1, -1), 180)
	await settle()
	check(grid_ok(), "repeated_hits_cannot_move_support", str(upper.position))

	await fresh()
	var victim := block_at(5, 20)
	var gold := root.get_node("GoldManager")
	var before: int = gold.destroyed_count
	var coins_before: int = gold.total_gold
	var reward: int = victim.gold_value
	victim.take_damage(1000)
	victim.take_damage(1000)
	check(gold.destroyed_count == before + 1 and gold.total_gold == coins_before + reward, "one_shatter_per_block")
	await settle()
	check(grid_ok(), "duplicate_hits_preserve_grid_and_fall_count")

	await fresh()
	block_at(5, 29).take_damage(1000)
	await process_frame
	await process_frame
	# Finish all but the last falling block within the same frame, then break
	# its new support before its landing callback. Deferred compact is pending.
	var falling: Array = building._cols[5].duplicate()
	falling.sort_custom(func(a, b): return a.effective_level() > b.effective_level())
	upper = falling.back()
	for block in falling:
		if block == upper:
			continue
		block._fall_tween.custom_step(1.0)
	block_at(5, 29).take_damage(1000)
	upper._fall_tween.custom_step(1.0)
	check(block_at(5, 29) == null, "pending_compact_prevents_bottom_refill")
	await settle()
	check(upper.level == 2 and grid_ok(), "break_on_last_landing_drops_again", {"level": upper.level, "position": str(upper.position)})

	await fresh()
	upper = block_at(5, 18)
	block_at(5, 20).take_damage(1000)
	block_at(5, 22).take_damage(1000)
	await create_timer(0.02).timeout
	block_at(5, 24).take_damage(1000)
	await settle()
	check(upper.level == 21 and grid_ok(), "multi_break_retargets_active_falls")

	await fresh()
	var projectile: Area2D = load("res://scenes/BombProjectile.tscn").instantiate()
	projectile.position = block_at(5, 24).global_position
	projectile.damage = 1000.0
	projectile.radius = 120.0
	current_scene.add_child(projectile)
	root.get_node("UpgradeManager").chain_damage = 0.5
	before = gold.destroyed_count
	projectile._explode()
	await settle()
	var bomb_ok: bool = gold.destroyed_count > before and grid_ok()
	check(bomb_ok, "bomb_and_chain_settle_to_unique_slots", {"destroyed": gold.destroyed_count - before, "grid": grid_error})

	root.get_node("Presentation").reduced_motion = false
	await fresh()
	upper = block_at(5, 19)
	victim = block_at(5, 20)
	victim.hp = 1.0
	root.get_node("UpgradeManager").hammer_range = 41.0
	current_scene.get_node("Hammer")._smash(victim.global_position)
	await settle()
	check(upper.level == 20 and grid_ok(), "range_hammer_with_recoil_and_slowmo")

	await fresh()
	for wave in range(30):
		var col := randi_range(2, 9)
		var level := randi_range(18, 29)
		var target := block_at(col, level)
		if target == null:
			continue
		target.launch(Vector2(1, -1), 180)
		target.take_damage(1000)
		await create_timer(0.02, true, false, true).timeout
	await settle()
	check(grid_ok(), "rapid_breaks_across_columns_with_motion")

	DirAccess.make_dir_recursive_absolute(output)
	var report := {"checks": checks, "failed": failed, "user_dir": OS.get_user_data_dir()}
	var file := FileAccess.open(output + "/verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("COLLAPSE_VERIFICATION_COMPLETE failures=", failed)
	file.close()
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await scene_changed
	await create_timer(0.4, true, false, true).timeout
	quit(0 if failed == 0 else 1)
