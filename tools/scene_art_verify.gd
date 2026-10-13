extends SceneTree
## Rendered contact-plane, transparency and wide-screen regressions.
const OUTPUT := "E:/godotproject/boomame/artifacts/scene-art"
var checks: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	print("ART_CHECK ",label,": ","PASS" if ok else "FAIL")
	if not ok:
		failures.append(label)

func frames(count: int) -> void:
	for i in count:
		await process_frame

func _run() -> void:
	if not "SceneArtValidation" in OS.get_user_data_dir():
		push_error("Use the scene-art validation copy")
		quit(2)
		return
	var presentation := root.get_node("Presentation")
	root.get_node("SaveManager").start_new_game(1)
	root.get_node("SaveManager").onboarding_pending = false
	presentation.reduced_motion = false
	presentation.shake_strength = 0.0
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	var building := current_scene.get_node("Building")
	while building.get_child_count() < 360:
		await process_frame
	current_scene.get_node("TestPanel").hide()
	check(building.get_child_count() == 360,"360_blocks_preserved")
	var tower_shadow := current_scene.get_node("TowerContactShadow")
	check(tower_shadow.global_position.is_equal_approx(Vector2(940,1000)) and is_equal_approx(tower_shadow.footprint,480.0),"tower_shadow_matches_actual_480px_footprint")
	var launcher := current_scene.get_node("LauncherManager")._launchers[0] as Node2D
	var shadow := launcher.get_node("ContactShadow") as Node2D
	check(not shadow.is_visible_in_tree(),"undeployed_launcher_has_no_shadow")
	root.get_node("GoldManager").add_gold(1000000)
	root.get_node("UpgradeManager").upgrade_bomb_launcher()
	var fixed_contact: Vector2 = shadow.global_position
	var deployment_grounded := true
	for i in 20:
		await process_frame
		deployment_grounded = deployment_grounded and shadow.global_position.is_equal_approx(fixed_contact)
	check(deployment_grounded and is_equal_approx(fixed_contact.y,1000.0),"deployment_shadow_stays_on_ground")
	await create_timer(0.5).timeout
	check(shadow.is_visible_in_tree() and is_equal_approx(shadow.modulate.a,1.0),"deployment_reveals_shadow")
	launcher._play_recoil()
	check(shadow.global_position.is_equal_approx(fixed_contact),"recoil_does_not_move_shadow")
	launcher.hide()
	check(not shadow.is_visible_in_tree(),"hidden_launcher_hides_shadow")
	launcher.show()
	presentation.reduced_motion = true
	shadow.reveal()
	check(is_equal_approx(shadow.modulate.a,1.0),"reduced_motion_shadow_appears_without_tween")
	root.get_node("UpgradeManager").reset()
	check(not shadow.is_visible_in_tree(),"run_reset_hides_deployed_shadow")
	# A detached outline would remain at the old grid slot during a collapse.
	var victim: Node2D = building._cols[0][24]
	var moving: Node2D = building._cols[0][23]
	var visual: Node2D = moving.visual_layer
	victim.take_damage(10000.0)
	await frames(5)
	check(moving.is_ancestor_of(visual) and visual.global_position.distance_to(moving.global_position) < 10.0,"silhouette_follows_falling_block")
	moving.take_damage(10000.0)
	await frames(2)
	check(not is_instance_valid(visual),"destroyed_block_releases_its_visuals")
	await create_timer(1.5).timeout
	check(building.get_child_count() == 360,"refill_after_styled_block_destruction")
	await verify_transparency()
	await verify_wide_edges()
	var weak_shadow: WeakRef = weakref(shadow)
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await scene_changed
	await frames(2)
	check(weak_shadow.get_ref() == null,"scene_change_releases_launcher_shadow")
	var report := {"checks":checks,"failures":failures,"user_dir":OS.get_user_data_dir(),"renderer":RenderingServer.get_video_adapter_name()}
	FileAccess.open(OUTPUT.path_join("verification.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SCENE_ART_VERIFY_COMPLETE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func verify_transparency() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(80,80)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/presentation/launcher.png")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.material = root.get_node("Presentation").scene_material("equipment")
	sprite.position = Vector2(40,40)
	sprite.modulate = Color(1,1,1,0.5)
	viewport.add_child(sprite)
	await frames(3)
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	check(rendered.get_pixel(0,0).a == 0.0,"equipment_shader_preserves_transparent_canvas")
	var max_alpha := 0.0
	for y in 80:
		for x in 80:
			max_alpha = maxf(max_alpha,rendered.get_pixel(x,y).a)
	check(absf(max_alpha-0.5) < 0.02,"shader_applies_deployment_alpha_once")
	viewport.queue_free()

func verify_wide_edges() -> void:
	root.size = Vector2i(3440,1440)
	await frames(8)
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	var background := current_scene.get_node("Background")
	var central: Sprite2D = background.get_child(0).get_child(1)
	var right: Sprite2D = background.get_child(0).get_child(2)
	var left: Sprite2D = background.get_child(0).get_child(0)
	check(central.scale.x > 0 and right.scale.x < 0 and left.scale.x < 0,"wide_extensions_share_matching_texture_edges")
	# Sample the actual rendered join, away from the HUD and the tower.
	var join := root.get_stretch_transform() * central.get_global_transform_with_canvas() * Vector2(480,0)
	var x := roundi(join.x)
	var max_jump := 0.0
	if x > 1 and x < rendered.get_width()-1:
		for y in range(250,450,20):
			var a := rendered.get_pixel(x-1,y)
			var b := rendered.get_pixel(x,y)
			max_jump = maxf(max_jump,Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length())
		check(max_jump < 0.05,"rendered_ultrawide_sky_has_no_color_seam")
	else:
		check(false,"rendered_ultrawide_join_is_visible")
	root.size = Vector2i(1920,1080)
