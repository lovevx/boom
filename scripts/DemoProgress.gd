extends Node
## Per-slot demo goals and real elapsed play time. No time gates or rewards.
signal completed

@export var finale_gold := 1000000
@export var required_scatter_volleys := 10
const PHASES := ["首次工程 · 部署液压炮", "第二轮 · 重锤 / 重炮专精", "第三轮 · 连锁 / 余震组合", "最终工程 · 散射拆除"]
var elapsed_seconds := 0.0
var scatter_volleys := 0
var blocks_destroyed := 0
var gold_earned := 0
var is_completed := false
var summary_shown := false
var legacy_save := false
var completion_stats: Dictionary = {}
var _last_clock_ms := 0
var _poll := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_clock_ms = Time.get_ticks_msec()
	GoldManager.run_reset.connect(reset_run)

func _process(delta: float) -> void:
	_sample_clock(Time.get_ticks_msec(), DisplayServer.window_is_focused())
	_poll += delta / maxf(Engine.time_scale, 0.001)
	if _poll >= 0.25:
		_poll = 0.0
		check_completion()

func _notification(what: int) -> void:
	# Some platforms stop frames while minimized. Never charge that gap on focus-in.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_last_clock_ms = Time.get_ticks_msec()

func _sample_clock(now_ms: int, focused: bool) -> void:
	var seconds := maxf(0.0, (now_ms - _last_clock_ms) / 1000.0)
	_last_clock_ms = now_ms
	if not focused or is_completed or SaveManager.active_slot < 0:
		return
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://scenes/Main.tscn" or ScreenTransition._busy:
		return
	var settings := scene.get_node_or_null("UILayer/SettingsPanel") as Control
	if settings and settings.visible:
		return
	elapsed_seconds += seconds

func get_phase() -> int:
	return mini(3, ReincarnationManager.total_reincarnations)

func get_goal_gold() -> int:
	return finale_gold if get_phase() == 3 else ReincarnationManager.get_required_run_gold()

func get_goal() -> Dictionary:
	return {"phase": get_phase(), "title": PHASES[get_phase()], "target": get_goal_gold(),
		"produced": GoldManager.lifetime_gold_this_run, "scatter": scatter_volleys,
		"scatter_target": required_scatter_volleys, "completed": is_completed}

func register_scatter_volley(projectiles: int) -> void:
	if not is_completed and get_phase() == 3 and projectiles > 1:
		scatter_volleys = mini(required_scatter_volleys, scatter_volleys + 1)

func check_completion() -> void:
	if is_completed or SaveManager.active_slot < 0 or get_phase() < 3:
		return
	if GoldManager.lifetime_gold_this_run < finale_gold or scatter_volleys < required_scatter_volleys:
		return
	is_completed = true
	completion_stats = {"seconds": elapsed_seconds, "blocks": blocks_destroyed, "gold": gold_earned,
		"rebirths": ReincarnationManager.total_reincarnations, "permanent": ReincarnationManager.permanent_nodes.duplicate(),
		"upgrades": SaveManager._collect_upgrade_levels(), "legacy": legacy_save}
	SaveManager.save_current_slot()
	completed.emit()

func reset_run() -> void:
	scatter_volleys = 0

func reset_all() -> void:
	elapsed_seconds = 0.0
	scatter_volleys = 0
	blocks_destroyed = 0
	gold_earned = 0
	is_completed = false
	summary_shown = false
	legacy_save = false
	completion_stats.clear()
	_last_clock_ms = Time.get_ticks_msec()

func get_save_state() -> Dictionary:
	return {"elapsed": elapsed_seconds, "scatter": scatter_volleys, "blocks": blocks_destroyed,
		"gold": gold_earned, "completed": is_completed, "shown": summary_shown,
		"legacy": legacy_save, "result": completion_stats.duplicate(true)}

func restore_state(state: Dictionary, legacy: bool = false) -> void:
	elapsed_seconds = maxf(0.0, float(state.get("elapsed", 0.0)))
	scatter_volleys = maxi(0, int(state.get("scatter", 0)))
	blocks_destroyed = maxi(0, int(state.get("blocks", GoldManager.destroyed_count)))
	gold_earned = maxi(0, int(state.get("gold", GoldManager.lifetime_gold_this_run)))
	is_completed = bool(state.get("completed", false))
	summary_shown = bool(state.get("shown", false)) and is_completed
	legacy_save = bool(state.get("legacy", legacy))
	completion_stats = state.get("result", {}).duplicate(true)
	_last_clock_ms = Time.get_ticks_msec()

func format_time(seconds: float = -1.0) -> String:
	var total := int(elapsed_seconds if seconds < 0.0 else seconds)
	return "%02d:%02d" % [total / 60, total % 60]
