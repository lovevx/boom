extends SceneTree
## Architectural geometry and actual gameplay regressions, in the art copy only.
const OUTPUT := "E:/godotproject/boomame/artifacts/building-depth"
var checks: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	print("DEPTH_CHECK ",label,": ","PASS" if ok else "FAIL")
	if not ok: failures.append(label)

func _run() -> void:
	if not "SceneArtValidation" in OS.get_user_data_dir():
		quit(2)
		return
	root.get_node("SaveManager").start_new_game(1)
	root.get_node("SaveManager").onboarding_pending = false
	root.get_node("Presentation").reduced_motion = true
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	var building := current_scene.get_node("Building")
	while building.get_child_count() < 360: await process_frame
	current_scene.get_node("TestPanel").hide()
	var solid_counts := true
	var bay_positions := true
	for level in 30:
		if block_at(building,0,level).is_floor: continue
		var windows := 0
		for col in 12:
			var block := block_at(building,col,level)
			if block.is_glass:
				windows += 1
				bay_positions = bay_positions and col in building.WINDOW_BAYS
		solid_counts = solid_counts and windows >= 2 and windows <= 4
	check(solid_counts,"initial_2_to_4_real_windows_per_storey")
	check(bay_positions,"glass_matches_regular_window_bays")
	var physics_unchanged := true
	var values_unchanged := true
	for block in building.get_children():
		var collision: CollisionShape2D
		for child in block.get_children():
			if child is CollisionShape2D: collision = child
		physics_unchanged = physics_unchanged and collision != null and collision.shape.size == Vector2(40,40)
		values_unchanged = values_unchanged and (is_equal_approx(block.hp,2.0) if block.is_glass else is_equal_approx(block.hp,7.0 if block.is_floor else 5.0))
		values_unchanged = values_unchanged and block.gold_value == (1 if block.is_glass else 2)
	check(physics_unchanged,"all_360_collisions_remain_40x40")
	check(values_unchanged,"material_hp_and_reward_values_preserved")
	check(current_scene.get_node("Hammer")._find_blocks(Vector2(1204,600)).is_empty(),"decorative_side_does_not_add_hit_targets")
	# Destroy the facade before the physical collapse advances: inspect the real notch.
	paused = true
	var victims: Array[Node2D] = []
	var shells: Array[WeakRef] = []
	var reward := 0
	for col in range(7,12):
		for level in range(15,19):
			var block := block_at(building,col,level)
			shells.append(weakref(block.visual_layer.get_node("DepthShell")))
			reward += block.gold_value
			victims.append(block)
	var before: int = root.get_node("GoldManager").total_gold
	for block in victims: block.take_damage(10000.0)
	await process_frame
	await process_frame
	var released := true
	for shell in shells: released = released and shell.get_ref() == null
	check(released,"destroyed_front_releases_its_entire_depth_shell")
	check(root.get_node("GoldManager").total_gold == before+reward,"cutaway_destruction_rewards_each_block_once")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join("cutaway.png"))
	paused = false
	await create_timer(2.0).timeout
	var deadline := Time.get_ticks_msec()+8000
	while (building._falling_blocks>0 or building.get_child_count()!=360) and Time.get_ticks_msec()<deadline:
		await process_frame
	check(building.get_child_count()==360 and building._falling_blocks==0,"cutaway_collapses_and_refills_to_360")
	var decorated := true
	var aligned := true
	for block in building.get_children():
		decorated = decorated and block.visual_layer.has_node("DepthShell") and block.visual_layer.has_node("FacadeDetails")
		aligned = aligned and block.position.is_equal_approx(Vector2(block.col*40.0,block.level*40.0))
	check(decorated,"refilled_blocks_receive_architectural_skin")
	check(aligned,"decorated_blocks_settle_on_original_grid")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join("settled.png"))
	var old_shell: WeakRef = weakref(building.get_child(0).visual_layer.get_node("DepthShell"))
	building.reset()
	while building.get_child_count()<360: await process_frame
	check(old_shell.get_ref()==null,"building_reset_releases_old_shells")
	var live_shell: WeakRef = weakref(building.get_child(0).visual_layer.get_node("DepthShell"))
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await scene_changed
	check(live_shell.get_ref()==null,"scene_change_releases_all_architecture")
	FileAccess.open(OUTPUT.path_join("depth-verification.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"user_dir":OS.get_user_data_dir()},"\t"))
	print("DEPTH_VERIFY_COMPLETE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func block_at(building: Node2D, col: int, level: int) -> Node2D:
	for block in building._cols[col]:
		if block.level == level: return block
	return null
