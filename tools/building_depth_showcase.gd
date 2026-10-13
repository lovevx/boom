extends SceneTree
## Godot Movie Maker fixture; controlled cutaway and accelerated cannon deployment.
func _initialize() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count: await process_frame

func _run() -> void:
	if not "SceneArtValidation" in OS.get_user_data_dir():
		quit(2)
		return
	root.get_node("SaveManager").start_new_game(0)
	root.get_node("SaveManager").onboarding_pending = false
	root.get_node("Presentation").reduced_motion = false
	root.get_node("Presentation").low_effects = false
	root.get_node("Presentation").shake_strength = 0.0
	seed(719)
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	var building := current_scene.get_node("Building")
	while building.get_child_count()<360: await process_frame
	current_scene.get_node("TestPanel").hide()
	await frames(40)
	var hammer := current_scene.get_node("Hammer")
	var target: Node2D
	for block in building._cols[2]:
		if block.is_glass and block.global_position.y > 500 and block.global_position.y < 700:
			target = block
			break
	if target:
		var at := target.global_position
		hammer._smash(at)
		await frames(14)
		hammer._smash(at)
		await frames(25)
	# Pause for a short inspection of the genuine opening before gravity closes it.
	paused = true
	for col in range(8,12):
		for block in building._cols[col].duplicate():
			if block.level >= 16 and block.level <= 18:
				block.take_damage(10000.0)
	await frames(24)
	paused = false
	await frames(30)
	root.get_node("GoldManager").add_gold(1000000)
	var upgrades := root.get_node("UpgradeManager")
	for i in 4: upgrades.upgrade_bomb_launcher()
	for i in 3: upgrades.upgrade_bomb_rate()
	for i in 4:
		upgrades.upgrade_bomb_damage()
		upgrades.upgrade_bomb_radius()
	await frames(240)
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await scene_changed
	await frames(2)
	quit()
