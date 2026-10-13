extends SceneTree
## May also be run as an absolute external script against the exported PCK.
var failures: Array[String] = []
var checks: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for path in ["assets/presentation/launcher.png","assets/presentation/launcher_frames.tres","assets/presentation/icons/help.svg","assets/presentation/icons/exit.svg","assets/audio/bgm/BGM1.mp3","assets/audio/bgm/bgm2.mp3"]:
		check(ResourceLoader.exists("res://"+path),"runtime_present:"+path)
	for path in ["assets/launcher/launcher_006.png","assets/ui/大炮图.png","assets/presentation/sources/launcher.png","assets/presentation/sources/hydraulic/concept.png","assets/presentation/audio/yard_shift.wav","assets/presentation/audio/demolition_rhythm.wav"]:
		check(not ResourceLoader.exists("res://"+path) and not FileAccess.file_exists("res://"+path),"historical_source_excluded:"+path)
	root.get_node("SaveManager").onboarding_pending = false
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	await create_timer(1.5,true,false,true).timeout
	check(current_scene.get_node("Building").get_child_count() == 360,"exported_game_generates_tower")
	check(current_scene.get_node("GoldHUD").action_screen_rect("skill_tree").has_area(),"exported_ui_interfaces_work")
	var music := root.get_node("SoundManager")
	for i in 2:
		music.set_bgm_index(i)
		music.play_music()
		check(music._music.stream is AudioStreamMP3 and music._music.stream.loop and music._music.stream.get_length() > 0,"original_bgm_plays_and_loops_"+str(i))
	var stream: AudioStream = music._music.stream
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await scene_changed
	await create_timer(0.3,true,false,true).timeout
	check(music._music.stream == stream,"original_bgm_continues_across_scenes")
	var stats := current_scene.get_node("StatsPanel")
	stats.open()
	await process_frame
	check(root.get_visible_rect().encloses(root.get_node("Presentation").screen_rect(stats.get_child(1))),"career_dialog_bounds")
	var report := {"checks":checks,"failures":failures}
	var file := FileAccess.open("E:/godotproject/boomame/artifacts/ui-refresh/export-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("PACK_VERIFY_COMPLETE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	print(label,": ","PASS" if ok else "FAIL")
	if not ok:
		failures.append(label)
