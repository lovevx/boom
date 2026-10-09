extends SceneTree
## Rendered real-time stress: 900 wall-clock seconds, four launchers, max rate.
var samples: Array[Dictionary] = []
var begin_ms := 0
var sample_ms := 0
var duration_ms := 900000
var output := "E:/godotproject/boomame/artifacts"
var initial_destroyed := 0
var frames := 0
var warmup_end := 0
var frame_histogram: Dictionary = {}
var last_frame_usec := 0
var frame_count := 0
var worst_frame_ms := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not "PresentationValidation" in OS.get_user_data_dir():
		quit(2)
		return
	seed(719)
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		duration_ms = int(arguments[0]) * 1000
	root.get_node("SaveManager").start_new_game(1)
	root.get_node("SaveManager").onboarding_pending = false
	var presentation := root.get_node("Presentation")
	presentation.reduced_motion = false
	presentation.low_effects = false
	presentation.shake_strength = 0.55
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	current_scene.get_node("TestPanel").hide()
	while current_scene.get_node("Building").get_child_count() < 360:
		await process_frame
	var upgrade := root.get_node("UpgradeManager")
	for i in 4:
		upgrade.upgrade_bomb_launcher()
	for i in 3:
		upgrade.upgrade_bomb_rate()
	for i in 5:
		upgrade.upgrade_bomb_damage()
	for i in 5:
		upgrade.upgrade_bomb_radius()
	await create_timer(5.0,true,false,true).timeout
	begin_ms = Time.get_ticks_msec()
	warmup_end = begin_ms + 60000
	initial_destroyed = root.get_node("GoldManager").destroyed_count
	sample_ms = begin_ms
	print("STRESS_START duration_seconds=",duration_ms/1000," renderer=",RenderingServer.get_video_adapter_name())
	last_frame_usec = Time.get_ticks_usec()
	await _measure()

func _measure() -> void:
	var peaks := {}
	var process_max := 0.0
	var physics_max := 0.0
	while Time.get_ticks_msec() - begin_ms < duration_ms:
		await process_frame
		frames += 1
		var now := Time.get_ticks_msec()
		var usec := Time.get_ticks_usec()
		var frame_ms := (usec-last_frame_usec)/1000.0
		last_frame_usec = usec
		if now >= warmup_end:
			var bucket := ceili(frame_ms)
			frame_histogram[bucket] = int(frame_histogram.get(bucket,0)) + 1
			frame_count += 1
			worst_frame_ms = maxf(worst_frame_ms,frame_ms)
		if now - sample_ms >= 1000:
			var presentation := root.get_node("Presentation")
			var budget: Dictionary = presentation.budget_snapshot()
			for key in budget:
				peaks[key] = maxi(int(peaks.get(key,0)),int(budget[key]))
			var sample := {
				"seconds":(now-begin_ms)/1000.0,
				"fps":Engine.get_frames_per_second(),
				"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,
				"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,
				"memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,
				"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
				"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				"blocks":current_scene.get_node("Building").get_child_count(),
				"destroyed":root.get_node("GoldManager").destroyed_count,
				"budget":budget,
				"audio_peak_left_db":AudioServer.get_bus_peak_volume_left_db(0,0)
			}
			samples.append(sample)
			process_max = maxf(process_max,sample.process_ms)
			physics_max = maxf(physics_max,sample.physics_ms)
			sample_ms = now
			if samples.size() % 30 == 0:
				print("STRESS_PROGRESS ",JSON.stringify(sample))
				_write({"status":"running","samples":samples,"budget_peaks":peaks})
	var stable: Array[Dictionary] = []
	for sample in samples:
		if sample.seconds >= 60:
			stable.append(sample)
	var fps: Array[float] = []
	for sample in stable:
		fps.append(float(sample.fps))
	fps.sort()
	var median := fps[fps.size()/2] if not fps.is_empty() else 0.0
	var p05 := fps[int(fps.size()*0.05)] if not fps.is_empty() else 0.0
	var report := {
		"status":"complete","duration_seconds":(Time.get_ticks_msec()-begin_ms)/1000.0,
		"median_fps":median,"p05_fps":p05,
		"first_stable_memory_mb":stable[0].memory_mb if not stable.is_empty() else 0,
		"last_memory_mb":samples[-1].memory_mb,
		"first_stable_nodes":stable[0].nodes if not stable.is_empty() else 0,
		"last_nodes":samples[-1].nodes,"process_max_ms":process_max,"physics_max_ms":physics_max,
		"destroyed_during_test":root.get_node("GoldManager").destroyed_count-initial_destroyed,
		"budget_peaks":peaks,"samples":samples
	}
	report["frame_p95_ms"] = _frame_percentile(0.95)
	report["frame_p99_ms"] = _frame_percentile(0.99)
	report["worst_frame_ms"] = worst_frame_ms
	_write(report)
	print("STRESS_COMPLETE ",JSON.stringify({"median_fps":median,"p05_fps":p05,"frames":frames}))
	quit()

func _write(report: Dictionary) -> void:
	var file := FileAccess.open(output+"/stress-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))

func _frame_percentile(fraction: float) -> int:
	var keys := frame_histogram.keys()
	keys.sort()
	var count := 0
	for key in keys:
		count += int(frame_histogram[key])
		if count >= frame_count*fraction:
			return int(key)
	return 0
