extends SceneTree
## Isolated screenshot runner. Run with --path <validation clone> --script res://tools/presentation_capture.gd.
var output := "res://artifacts/visual/before"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(719)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	print("CAPTURE_USER_DIR=", OS.get_user_data_dir())
	await _scene("res://scenes/MainMenu.tscn")
	await _shot("menu")
	await _scene("res://scenes/Main.tscn")
	await create_timer(1.0).timeout
	await _shot("game")
	var upgrade := root.get_node("UpgradeManager")
	root.get_node("GoldManager").add_gold(1000000)
	for i in 4:
		upgrade.upgrade_bomb_launcher()
	await create_timer(3.0).timeout
	await _shot("four_launchers")
	current_scene.get_node("UILayer/UpgradePanel").open()
	await _shot("upgrades")
	current_scene.get_node("UILayer/UpgradePanel").close()
	current_scene.get_node("UILayer/SettingsPanel").open()
	await _shot("settings")
	current_scene.get_node("UILayer/SettingsPanel").close()
	current_scene.get_node("UILayer/ReincarnationPanel").open()
	await _shot("reincarnation")
	print("CAPTURE_COMPLETE")
	quit()

func _scene(path: String) -> void:
	paused = false
	change_scene_to_file(path)
	await scene_changed
	await process_frame
	await process_frame
	var debug_panel := current_scene.get_node_or_null("TestPanel") as CanvasLayer
	if debug_panel:
		debug_panel.hide()

func _shot(label: String) -> void:
	await create_timer(0.3, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
