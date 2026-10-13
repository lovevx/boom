extends SceneTree
## Deterministic visual fixtures. Only run in the isolated scene-art copy.
var output := "E:/godotproject/boomame/artifacts/scene-art/before"
var movie := false

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await process_frame

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func fresh(threshold: int = 0) -> void:
	paused = false
	root.get_node("SaveManager").start_new_game(0)
	root.get_node("SaveManager").onboarding_pending = false
	root.get_node("GoldManager").destroyed_count = threshold
	root.get_node("GameFeel").reset()
	seed(719)
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	while current_scene.get_node("Building").get_child_count() < 360:
		await process_frame
	current_scene.get_node("TestPanel").hide()
	await frames(3)

func _run() -> void:
	if not "SceneArtValidation" in OS.get_user_data_dir():
		push_error("Use the isolated scene-art validation project")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	movie = args.has("movie")
	DirAccess.make_dir_recursive_absolute(output)
	var presentation := root.get_node("Presentation")
	presentation.reduced_motion = false
	presentation.low_effects = false
	presentation.shake_strength = 0.0
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await scene_changed
	await frames(25)
	if not movie:
		await shot("menu")
	await fresh()
	if movie:
		await record_game()
		quit()
		return
	for dimensions in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(2560,1440), Vector2i(3440,1440)]:
		root.size = dimensions
		await frames(8)
		await shot("initial_" + str(dimensions.x) + "x" + str(dimensions.y))
	root.size = Vector2i(1920,1080)
	var thresholds := [0,100,450,1400]
	for i in 4:
		await fresh(thresholds[i])
		await shot("tier_" + str(i))
	await fresh()
	var building := current_scene.get_node("Building")
	var gold := root.get_node("GoldManager")
	for i in range(1,4):
		gold.destroyed_count = thresholds[i]
		for c in range((i-1)*4,i*4):
			for block in building._cols[c].duplicate():
				if block.level == 20:
					block.take_damage(10000.0)
		await create_timer(1.3).timeout
	await shot("mixed_materials")
	for block in building._cols[5].duplicate():
		if block.level == 24:
			block.take_damage(10000.0)
	await frames(5)
	await shot("collapse")
	await fresh()
	gold.add_gold(1000000)
	var upgrades := root.get_node("UpgradeManager")
	for i in 4:
		upgrades.upgrade_bomb_launcher()
	for i in 3:
		upgrades.upgrade_bomb_rate()
	await frames(30)
	paused = true
	await shot("four_launchers")
	paused = false
	await create_timer(3.0).timeout
	await shot("bombing")
	print("SCENE_ART_CAPTURE_COMPLETE user_dir=",OS.get_user_data_dir())
	quit()

func record_game() -> void:
	await frames(30)
	var hammer := current_scene.get_node("Hammer")
	var building := current_scene.get_node("Building")
	for i in 4:
		var block: Node2D = building.get_child(270 + i * 2)
		hammer._smash(block.global_position)
		await frames(12)
	root.get_node("GoldManager").add_gold(1000000)
	var upgrades := root.get_node("UpgradeManager")
	for i in 4:
		upgrades.upgrade_bomb_launcher()
	for i in 3:
		upgrades.upgrade_bomb_rate()
	for i in 4:
		upgrades.upgrade_bomb_damage()
		upgrades.upgrade_bomb_radius()
	await frames(240)
