extends SceneTree
## Capture with --write-movie <path>.avi --fixed-fps 30 --resolution 1280x720.
## Uses a separate user directory, never grants upgrades to player saves.
func _initialize() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await process_frame

func _run() -> void:
	if not "PresentationValidationMotion" in OS.get_user_data_dir():
		quit(2)
		return
	seed(719)
	var save := root.get_node("SaveManager")
	save.start_new_game(0)
	save.onboarding_pending = false
	var presentation := root.get_node("Presentation")
	presentation.reduced_motion = false
	presentation.low_effects = false
	presentation.shake_strength = 0.35
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	current_scene.get_node("TestPanel").hide()
	await frames(35)
	var building := current_scene.get_node("Building")
	var hammer := current_scene.get_node("Hammer")
	for i in 6:
		var block: Node2D = building.get_child(120 + i * 2)
		hammer._smash(block.global_position)
		await frames(12)
	var upgrade := root.get_node("UpgradeManager")
	for i in 4:
		upgrade.upgrade_bomb_launcher()
	for i in 3:
		upgrade.upgrade_bomb_rate()
	for i in 5:
		upgrade.upgrade_bomb_damage()
		upgrade.upgrade_bomb_radius()
	await frames(450)
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await scene_changed
	await frames(3)
	quit()
