extends SceneTree
var output := "E:/godotproject/boomame/artifacts/balance"

func _initialize() -> void:
	_run.call_deferred()

func shot(label: String) -> void:
	await create_timer(0.35, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + label + ".png")

func _run() -> void:
	if not "BoomameBalanceValidation" in OS.get_user_data_dir():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var save := root.get_node("SaveManager")
	var gold := root.get_node("GoldManager")
	var rebirth := root.get_node("ReincarnationManager")
	save.start_new_game(0)
	save.onboarding_pending = false
	root.get_node("Presentation").reduced_motion = true
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	await create_timer(0.7).timeout
	var panel := current_scene.get_node("UILayer/ReincarnationPanel")
	panel.open()
	await shot("rebirth_locked")
	gold.add_gold(4000)
	rebirth.reincarnation_points = 2
	rebirth.reincarnation_changed.emit()
	await shot("rebirth_ready")
	panel._on_reincarnate_pressed()
	await shot("rebirth_confirm")
	panel.close()
	var skills := current_scene.get_node("UILayer/UpgradePanel")
	skills.open()
	for card in skills._all_cards:
		if card.id == "hammer_range":
			skills._show_tip(card)
	await shot("skills_next_level")
	skills.close()
	print("BALANCE_CAPTURE_COMPLETE")
	quit()
