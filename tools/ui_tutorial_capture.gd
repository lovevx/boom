extends "res://tools/ui_refresh_verify.gd"
## Movie demonstration in the isolated project; milestones are accelerated by fixtures.
func _run() -> void:
	if not "BoomameDemoValidation" in OS.get_user_data_dir():
		quit(2)
		return
	g = root.get_node("GoldManager")
	u = root.get_node("UpgradeManager")
	r = root.get_node("ReincarnationManager")
	s = root.get_node("SaveManager")
	p = root.get_node("Presentation")
	p.reduced_motion = false
	s.start_new_game(0)
	await scene("res://scenes/Main.tscn")
	await settle(1.2)
	# Drive the real hammer/cooldown path to earn the first upgrade.
	for i in 12:
		if g.total_gold >= u.get_node_cost("hammer_damage"):
			break
		var block: Node2D = guide()._block
		if is_instance_valid(block):
			var at: Vector2 = block.get_global_transform_with_canvas().origin
			root.warp_mouse(at)
			current_scene.get_node("Hammer")._maybe_smash(block.global_position)
		await settle(0.6)
	if g.total_gold < u.get_node_cost("hammer_damage"):
		push_error("Movie first hit did not earn enough gold")
		quit(1)
		return
	await settle(1.0)
	await click(current_scene.get_node("GoldHUD/GoldBar/SkillTreeButton"))
	await settle(1.0)
	await click(skill("hammer_damage"))
	if u.get_hammer_damage_level() != 1:
		push_error("Movie first purchase failed")
		quit(1)
		return
	await settle(1.0)
	await click(current_scene.get_node("UILayer/UpgradePanel")._close_button)
	await settle(1.0)
	g.add_gold(u.get_node_cost("bomb_launcher"))
	await settle(1.0)
	await click(current_scene.get_node("GoldHUD/GoldBar/SkillTreeButton"))
	await settle(1.0)
	await click(skill("bomb_launcher"))
	await settle(0.8)
	await click(current_scene.get_node("UILayer/UpgradePanel")._close_button)
	await settle(6.0)
	g.add_gold(r.MIN_RUN_GOLD_FOR_GAIN)
	await settle(1.5)
	await click(current_scene.get_node("GoldHUD/GoldBar/ReincarnationButton"))
	await settle(1.5)
	var panel := current_scene.get_node("UILayer/ReincarnationPanel")
	await click(panel._reinc_btn)
	await settle(1.5)
	await click(panel._cf_ok)
	await settle(2.0)
	quit()
