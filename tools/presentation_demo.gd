extends SceneTree
## Deterministic 30 second gameplay film, isolated from player saves.
var frame := 0

func _initialize() -> void:
	_run.call_deferred()

func wait_frames(count: int) -> void:
	for index in count:
		await process_frame

func _scene(path: String) -> void:
	paused = false
	root.get_node("GameFeel").reset()
	change_scene_to_file(path)
	await scene_changed
	var debug_panel := current_scene.get_node_or_null("TestPanel") as CanvasLayer
	if debug_panel:
		debug_panel.hide()
	await wait_frames(24)

func _run() -> void:
	if not "PresentationValidation" in OS.get_user_data_dir():
		quit(2)
		return
	seed(719)
	root.get_node("SaveManager").start_new_game(0)
	root.get_node("SaveManager").onboarding_pending = false
	root.get_node("Presentation").reduced_motion = false
	await _scene("res://scenes/MainMenu.tscn")
	await wait_frames(65)
	await _scene("res://scenes/Main.tscn")
	var building := current_scene.get_node("Building")
	for hit in 12:
		var block: Node2D = building.get_child(200 + (hit % 8))
		current_scene.get_node("Hammer")._smash(block.global_position)
		await wait_frames(18)
	var gold := root.get_node("GoldManager")
	gold.add_gold(1000)
	var panel := current_scene.get_node("UILayer/UpgradePanel")
	panel.open()
	await wait_frames(18)
	var cannon: Dictionary
	for card in panel._all_cards:
		if card.id == "bomb_launcher":
			cannon = card
			break
	panel._show_tip(cannon)
	await wait_frames(25)
	panel._try_upgrade(cannon)
	await wait_frames(35)
	panel.close()
	await wait_frames(145)
	var upgrade := root.get_node("UpgradeManager")
	for hit in 3:
		upgrade.upgrade_bomb_launcher()
	for hit in 3:
		upgrade.upgrade_bomb_rate()
	for hit in 4:
		upgrade.upgrade_bomb_damage()
	for hit in 4:
		upgrade.upgrade_bomb_radius()
	await wait_frames(290)
	print("DEMO_COMPLETE")
	quit()
