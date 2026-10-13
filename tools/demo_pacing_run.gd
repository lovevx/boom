extends SceneTree
## Real production scenes, weapons, physics and purchases; isolated saves only.
## --fixed-fps 60 removes wall-clock throttling, NOT game travel/fall/cooldown time.
var route := "bomb"
var run_seed := 7
var time := 0.0
var phase_start := 0.0
var last_event := 0.0
var longest_gap := 0.0
var phase_gap := 0.0
var hammer_next := 0.0
var shop_next := 0.0
var menu_until := 0.0
var phases: Array[Dictionary] = []
var purchases: Array[Dictionary] = []
var milestones: Dictionary = {}
var running := false
var target: Node2D
var g: Node
var u: Node
var r: Node
var s: Node
var d: Node
var building: Node
var hammer: Node
var fixed_seconds := 1.0 / 60.0
var max_seconds := 3600.0
var tier := 0
const OUTPUT := "E:/godotproject/boomame/artifacts/demo-pacing"
const ROUTES := {
	"hammer": ["hammer_damage", "hammer_range", "combo", "power_strike", "execute", "crit_chance", "hammer_speed"],
	"bomb": ["bomb_damage", "bomb_radius", "bomb_rate", "barrage", "blast_floor", "chain", "aftershock", "scatter", "bomb_launcher"],
	"economy": ["coin_base", "coin_multiplier", "contract", "salvage", "discount", "falling_damage", "building_drop_speed"],
}
const META := {
	"hammer": ["base_damage", "giant_power", "destroy_power", "auto_hammer", "combo_memory", "wave_training", "swift_wind", "coin_heart"],
	"bomb": ["turret_base_damage", "ammo_enhance", "blast_range", "blast_training", "barrage_training", "coin_heart"],
	"economy": ["coin_heart", "initial_capital", "salvage_license", "contract_license", "procurement", "coin_per_kill", "turret_base_damage"],
}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--route="): route = arg.get_slice("=", 1)
		if arg.begins_with("--seed="): run_seed = int(arg.get_slice("=", 1))
		if arg.begins_with("--max="): max_seconds = float(arg.get_slice("=", 1))
	_run.call_deferred()

func _run() -> void:
	if not "BoomameDemoValidation" in OS.get_user_data_dir() or not ROUTES.has(route):
		quit(2)
		return
	seed(run_seed)
	g = root.get_node("GoldManager")
	u = root.get_node("UpgradeManager")
	r = root.get_node("ReincarnationManager")
	s = root.get_node("SaveManager")
	d = root.get_node("DemoProgress")
	d.set_process(false) # Simulated elapsed seconds recorded below; production clock tested separately.
	s.start_new_game(2)
	s.onboarding_pending = false
	root.get_node("Presentation").reduced_motion = true
	root.get_node("Presentation").low_effects = true
	root.get_node("SoundManager").set_process(false)
	await enter_game()
	running = true

func enter_game() -> void:
	change_scene_to_file("res://scenes/Main.tscn")
	await scene_changed
	building = current_scene.get_node("Building")
	hammer = current_scene.get_node("Hammer")
	while building.get_child_count() < 360:
		await process_frame
	await physics_frame
	# Completion is inspected explicitly; no modal changes the automated policy.
	current_scene.get_node("GoldHUD/DemoSummary").set_process(false)
	target = null

func _process(_delta: float) -> bool:
	if not running:
		return false
	time += fixed_seconds
	d.elapsed_seconds += fixed_seconds
	if time >= max_seconds:
		finish(false)
		return false
	if time < menu_until:
		return false
	if paused:
		paused = false
	var current_gap := time - last_event
	longest_gap = maxf(longest_gap, current_gap)
	phase_gap = maxf(phase_gap, current_gap)
	if g.destroyed_count >= [100, 450, 1400, 2147483647][tier]:
		tier += 1
		event()
	if time >= hammer_next and not u.auto_hammer:
		# First minute: ~1.7 clicks/sec. After automation: a 6s burst every 18s.
		var manual: bool = u.get_bomb_launcher_count() == 0 or fmod(time - phase_start, 18.0) < 6.0
		if manual:
			if not is_instance_valid(target) or target._shattered or target.global_position.y < 180.0:
				target = pick_target()
			if is_instance_valid(target):
				hammer._maybe_smash(target.global_position)
			hammer_next = time + maxf(0.60, 0.5 / u.hammer_speed)
	if time >= shop_next:
		shop_next = time + 12.0
		shop()
	d.check_completion()
	if d.is_completed:
		phases.append(phase_result())
		finish(true)
	elif r.total_reincarnations < 3 and g.lifetime_gold_this_run >= r.get_required_run_gold():
		rebirth.call_deferred()
		running = false
	if int(time) % 60 == 0 and absf(time-roundf(time)) < 0.01:
		print("PACE ", route, " ", run_seed, " t=", roundi(time), " phase=", r.total_reincarnations, " gold=", g.lifetime_gold_this_run, " cannons=", u.get_bomb_launcher_count())
	return false

func pick_target() -> Node2D:
	var best: Node2D
	var best_score := INF
	for b in building.get_children():
		if not b is RigidBody2D or b._shattered or b.global_position.y < 180 or b.global_position.y > 960:
			continue
		var score: float = b.hp + absf(b.global_position.x - 950.0) * 0.003
		if score < best_score:
			best = b
			best_score = score
	return best

func shop() -> void:
	var bought := 0
	for i in 8:
		var signatures := [["combo","salvage","contract","blast_floor"], ["power_strike","execute","barrage"], ["chain","aftershock","falling_damage"], ["scatter"]]
		for signature in signatures[mini(3,r.total_reincarnations)]:
			var state: Dictionary = u.get_node_state(signature)
			if state.state == "available" and g.total_gold >= u.get_node_cost(signature):
				milestones.get_or_add("phase_%d_mechanic_available" % r.total_reincarnations, snappedf(time-phase_start,0.1))
		var nid := next_purchase()
		if nid.is_empty() or not u.purchase_node(nid):
			break
		bought += 1
		purchases.append({"time": snappedf(time,0.1), "phase": r.total_reincarnations, "node": nid, "level": u._get_node_level(nid)})
		milestones.get_or_add("first_upgrade", time)
		if nid == "bomb_launcher": milestones.get_or_add("first_cannon", time)
		event()
	if bought > 0:
		paused = true
		menu_until = time + 2.0 + bought * 0.6

func next_purchase() -> String:
	# Tutorial is identical for all routes; no gold or permanent skills are injected.
	for nid in ["hammer_damage", "hammer_speed", "bomb_launcher"]:
		if u._get_node_level(nid) == 0:
			return nid if g.total_gold >= u.get_node_cost(nid) else ""
	var best := ""
	var score := INF
	for nid in u.NODE_TITLES.keys() + u.DEMO_NODES.keys():
		var state: Dictionary = u.get_node_state(nid)
		var cost: int = u.get_node_cost(nid)
		if state.state == "locked" or state.state == "maxed" or cost <= 0 or cost > g.total_gold:
			continue
		var weight := 0.55 if nid in ROUTES[route] else 1.0
		if u._get_node_level(nid) == 0: weight *= 0.8
		if r.total_reincarnations == 3 and nid == "scatter" and u._get_node_level(nid) == 0: weight *= 0.1
		if cost * weight < score:
			score = cost * weight
			best = nid
	return best

func event() -> void:
	last_event = time

func phase_result() -> Dictionary:
	return {"phase": r.total_reincarnations, "seconds": snappedf(time-phase_start,0.1), "gold": g.lifetime_gold_this_run,
		"blocks": g.destroyed_count, "longest_progress_gap": snappedf(phase_gap,0.1), "levels": s._collect_upgrade_levels()}

func rebirth() -> void:
	phases.append(phase_result())
	paused = false
	r.reincarnate()
	g.reset()
	u.reset()
	r.apply_permanent_bonuses()
	for i in 20:
		var purchased := false
		for nid in META[route]:
			if r.purchase_node(nid):
				purchased = true
				break
		if not purchased: break
	s.save_current_slot()
	# Include 15 seconds for reading permanent skills / choosing Continue.
	time += 15.0
	phase_start = time
	phase_gap = 0.0
	tier = 0
	event()
	await enter_game()
	shop_next = time
	running = true

func finish(ok: bool) -> void:
	running = false
	paused = false
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var file := FileAccess.open(OUTPUT + "/engine-" + route + "-" + str(run_seed) + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"completed":ok, "route":route, "seed":run_seed, "seconds": snappedf(time,0.1),
		"eligible_seconds": snappedf(d.elapsed_seconds,0.1),
		"parameters":{"rebirth_targets":r.run_gold_targets,"finale_gold":d.finale_gold,"bomb_damage":u.BOMB_DAMAGES,"scatter_cost":u.SCATTER_COSTS[0],"scatter_radius_prerequisite":u.NODE_PRE_REQS.scatter[0].lvl},
		"phases":phases,"milestones":milestones,"purchases":purchases,"longest_progress_gap":longest_gap,
		"settings":"reduced_motion=true; low_effects=true; fixed_fps=60; real production physics; simulated 2s+0.6s/purchase menu reading and 15s/rebirth",
		"permanent":r.permanent_nodes,"scatter_volleys":d.scatter_volleys},"\t"))
	print("DEMO_PACING_RUN_", "PASS" if ok else "TIMEOUT", " seconds=", snappedf(time,0.1))
	quit(0 if ok else 1)
