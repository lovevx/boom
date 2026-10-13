extends SceneTree
var output := "E:/godotproject/boomame/artifacts/demo-growth"

func _initialize() -> void:
	_run.call_deferred()

func shot(label: String) -> void:
	await create_timer(0.2, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + label + ".png")

func _run() -> void:
	if not "BoomameDemoValidation" in OS.get_user_data_dir():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var s := root.get_node("SaveManager")
	var r := root.get_node("ReincarnationManager")
	var u := root.get_node("UpgradeManager")
	var g := root.get_node("GoldManager")
	s.start_new_game(2)
	s.onboarding_pending = false
	root.get_node("Presentation").reduced_motion = true
	r.total_reincarnations = 2
	r.reincarnation_points = 8
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	await create_timer(0.7).timeout
	g.add_gold(6000)
	u.set_state_from_save({"hammer_damage":2,"hammer_speed":2,"hammer_range":2,"combo":2,"power_strike":1,"bomb_launcher":1,"bomb_damage":2,"bomb_rate":1,"bomb_radius":2,"chain":1,"aftershock":1,"contract":1,"salvage":1,"building_drop_speed":1,"coin_multiplier":1,"coin_base":1})
	await create_timer(0.3).timeout
	var panel := current_scene.get_node("UILayer/UpgradePanel")
	panel.open()
	await shot("skill-tree-24")
	for card in panel._all_cards:
		if card.id == "aftershock":
			panel._show_tip(card)
	await shot("aftershock-tooltip")
	panel.close()
	var permanent := current_scene.get_node("UILayer/ReincarnationPanel")
	permanent.open()
	await shot("permanent-tree-21")
	# Show every added specialization inside the existing independent scroll columns.
	for nid in ["contract_license","wave_training","echo_mastery"]:
		var row: Control = permanent._rows[nid].name.get_parent().get_parent()
		var scroll: ScrollContainer = row.get_parent().get_parent()
		scroll.scroll_vertical = 10000
	await shot("permanent-specializations")
	permanent.close()
	await shot("demo-goals")
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await scene_changed
	await process_frame
	quit()
