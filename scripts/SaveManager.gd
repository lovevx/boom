extends Node
## 全局存档管理器（Autoload 单例）。
## 提供 3 个互相独立的完整存档槽：每个槽位保存【单局进度】（金币 / 本局累计 / 摧毁数 / 全部升级等级）
## 与【转生 meta】（RP 余额 / 累计转生次数 / 永久技能树），互不干扰。
## 槽位文件：user://save_slot_{0,1,2}.cfg（Godot ConfigFile）。
## 配套 UI：主菜单 3 个槽位卡片（继续 / 新游戏 / 删除）。
## 保存策略：**定时自动存档**（默认每 30 秒落盘当前活动槽位）+ 关键节点即时存档
## （返回主菜单 / 转生结算 / 点亮永久节点 / 新手教程完成）。

const SLOT_COUNT := 3
const SAVE_PATH_TMPL := "user://save_slot_%d.cfg"
const LIFE_STATS_PATH := "user://life_stats.cfg"   # 生涯总统计（跨槽位，不属于任一槽位）
const OLD_REINCARNATION_PATH := "user://reincarnation_save.cfg"   # 旧版单档（仅迁移用）
const AUTOSAVE_INTERVAL := 30.0   # 定时自动存档间隔（秒）

var active_slot: int = -1   # 当前正在游玩的槽位；-1 表示尚未进入任何槽位

var onboarding_pending := false   # 当前槽位是否仍需显示新手教程（每槽位独立）
var onboarding_stage := 0         # 0:锤击 1:升级完成 2:已部署 3:已开炮 4:完成/跳过


func _ready() -> void:
	_migrate_old_save()
	_load_life_stats()
	_start_autosave()


# 启动定时自动存档：技能树暂停游戏树时仍照常落盘，避免挂机/暂停期间进度丢失。
func _start_autosave() -> void:
	var timer := Timer.new()
	timer.name = "AutoSaveTimer"
	timer.wait_time = AUTOSAVE_INTERVAL
	timer.process_mode = Node.PROCESS_MODE_ALWAYS   # 忽略暂停（技能树面板暂停游戏树时继续计时）
	timer.timeout.connect(_on_autosave_timeout)
	add_child(timer)
	timer.start()


func _on_autosave_timeout() -> void:
	if active_slot >= 0:
		save_slot(active_slot)


# 旧版单一 reincarnation_save.cfg → 槽位 0（仅在槽位 0 为空时迁移一次），保留既有转生进度。
func _migrate_old_save() -> void:
	if has_save(0):
		return
	var old := ConfigFile.new()
	if old.load(OLD_REINCARNATION_PATH) != OK:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "time", Time.get_unix_time_from_system())
	cfg.set_value("reincarnation", "points", old.get_value("meta", "reincarnation_points", 0))
	cfg.set_value("reincarnation", "total", old.get_value("meta", "total_reincarnations", 0))
	cfg.set_value("reincarnation", "permanent_nodes", old.get_value("meta", "permanent_nodes", {}))
	# 旧档只有 meta、无单局数据：视为转生后的初始开局
	cfg.set_value("gold", "total", 0)
	cfg.set_value("gold", "lifetime", 0)
	cfg.set_value("gold", "destroyed", 0)
	cfg.set_value("upgrades", "levels", {})
	cfg.set_value("onboarding", "done", true)   # 旧档能走到转生说明早已过新手引导
	cfg.save(SAVE_PATH_TMPL % 0)
	DirAccess.open("user://").remove("reincarnation_save.cfg")


func _slot_path(slot: int) -> String:
	return SAVE_PATH_TMPL % slot


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


# 读取某槽位存档摘要（供主菜单卡片展示）；无存档时返回 {has_save:false}。
func get_slot_info(slot: int) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(_slot_path(slot)) != OK:
		return {"has_save": false}
	return {
		"has_save": true,
		"gold": int(cfg.get_value("gold", "total", 0)),
		"lifetime": int(cfg.get_value("gold", "lifetime", 0)),
		"destroyed": int(cfg.get_value("gold", "destroyed", 0)),
		"reincarnations": int(cfg.get_value("reincarnation", "total", 0)),
		"time": int(cfg.get_value("meta", "time", 0)),
	}


# 把当前全部状态写入指定槽位（覆盖式）。
func save_slot(slot: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "time", Time.get_unix_time_from_system())
	# 单局金币
	cfg.set_value("gold", "total", GoldManager.total_gold)
	cfg.set_value("gold", "lifetime", GoldManager.lifetime_gold_this_run)
	cfg.set_value("gold", "destroyed", GoldManager.destroyed_count)
	# 单局升级等级
	cfg.set_value("upgrades", "levels", _collect_upgrade_levels())
	# 转生 meta
	cfg.set_value("reincarnation", "points", ReincarnationManager.reincarnation_points)
	cfg.set_value("reincarnation", "total", ReincarnationManager.total_reincarnations)
	cfg.set_value("reincarnation", "permanent_nodes", ReincarnationManager.permanent_nodes)
	# 新手教程完成标记（每槽位独立）
	cfg.set_value("onboarding", "done", not onboarding_pending)
	cfg.set_value("onboarding", "stage", onboarding_stage)
	cfg.set_value("demo", "state", DemoProgress.get_save_state())
	cfg.save(_slot_path(slot))
	_save_life_stats()


# 保存到当前活动槽位（惰性落盘到 active_slot；自动存档定时器 / 关键节点临时触发共用）。
func save_current_slot() -> void:
	if active_slot >= 0:
		save_slot(active_slot)


func _collect_upgrade_levels() -> Dictionary:
	var levels := {
		"hammer_speed": UpgradeManager.get_hammer_speed_level(),
		"hammer_damage": UpgradeManager.get_hammer_damage_level(),
		"hammer_range": UpgradeManager.get_hammer_range_level(),
		"coin_multiplier": UpgradeManager.get_coin_multiplier_level(),
		"coin_base": UpgradeManager.get_coin_base_level(),
		"building_drop_speed": UpgradeManager.get_building_drop_speed_level(),
		"bomb_launcher": UpgradeManager.get_bomb_launcher_level(),
		"bomb_rate": UpgradeManager.get_bomb_rate_level(),
		"bomb_damage": UpgradeManager.get_bomb_damage_level(),
		"bomb_radius": UpgradeManager.get_bomb_radius_level(),
		"crit_chance": UpgradeManager.get_crit_chance_level(),
		"crit_mult": UpgradeManager.get_crit_mult_level(),
		"chain": UpgradeManager.get_chain_level(),
		"scatter": UpgradeManager.get_scatter_level(),
	}
	for nid in UpgradeManager.DEMO_NODES:
		levels[nid] = UpgradeManager._get_node_level(nid)
	return levels


# 从槽位读取并恢复完整状态到各管理器；无存档返回 false。
# 恢复顺序：转生 meta → 单局层重建（reset 铺起点 → 永久加成折叠 → 叠加存档等级）→ 金币覆盖。
func load_slot(slot: int) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(_slot_path(slot)) != OK:
		return false
	active_slot = slot
	# 1) 转生 meta（须先恢复：UpgradeManager.reset() 的开局炮台数依赖转生次数）
	ReincarnationManager.reincarnation_points = int(cfg.get_value("reincarnation", "points", 0))
	ReincarnationManager.total_reincarnations = int(cfg.get_value("reincarnation", "total", 0))
	var stored_nodes: Dictionary = cfg.get_value("reincarnation", "permanent_nodes", {})
	ReincarnationManager.permanent_nodes.clear()
	for nid in ReincarnationManager.NODE_DEFS:
		ReincarnationManager.permanent_nodes[nid] = clampi(int(stored_nodes.get(nid, 0)), 0, ReincarnationManager.NODE_DEFS[nid].max_level)
	# 教程完成标记
	onboarding_pending = not bool(cfg.get_value("onboarding", "done", false))
	onboarding_stage = clampi(int(cfg.get_value("onboarding", "stage", 0)), 0, 4) if onboarding_pending else 4
	# 2) 单局层：重置起点 → 永久加成折叠 → 叠加存档等级
	UpgradeManager.reset()
	ReincarnationManager.apply_permanent_bonuses(false)
	UpgradeManager.set_state_from_save(cfg.get_value("upgrades", "levels", {}))
	# 3) 金币覆盖（apply_permanent_bonuses 注入的初始资金以存档值为准）
	GoldManager.restore_state(
		int(cfg.get_value("gold", "total", 0)),
		int(cfg.get_value("gold", "lifetime", 0)),
		int(cfg.get_value("gold", "destroyed", 0)))
	# restore_state emits run_reset; restore demo counters only after that signal.
	DemoProgress.restore_state(cfg.get_value("demo", "state", {}), not cfg.has_section("demo"))
	ReincarnationManager.reincarnation_changed.emit()
	return true


# 在指定（空）槽位开启全新一局：设置活动槽位、新开局进度、并保留新手教程（新存档从教程开始）。
func start_new_game(slot: int) -> void:
	active_slot = slot
	onboarding_pending = true   # 新存档需要走新手教程
	onboarding_stage = 0
	ReincarnationManager.reincarnation_points = 0
	ReincarnationManager.total_reincarnations = 0
	ReincarnationManager.permanent_nodes.clear()
	GoldManager.reset()
	DemoProgress.reset_all()
	UpgradeManager.reset()
	ReincarnationManager.apply_permanent_bonuses()


# 标记当前槽位新手教程已完成（引导结束时调用），并落盘。
func mark_onboarding_done() -> void:
	onboarding_pending = false
	onboarding_stage = 4
	save_current_slot()


# 删除某槽位存档（不可恢复）。
func delete_slot(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.open("user://").remove(path.get_file())
	if active_slot == slot:
		active_slot = -1


# —— 生涯总统计持久化（独立文件，跨槽位共享，只增不减）——

func _save_life_stats() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "blocks_destroyed", GoldManager.stats_blocks_destroyed)
	cfg.set_value("stats", "gold_earned", GoldManager.stats_gold_earned)
	cfg.save(LIFE_STATS_PATH)


func _load_life_stats() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LIFE_STATS_PATH) != OK:
		return
	GoldManager.restore_life_stats(
		int(cfg.get_value("stats", "blocks_destroyed", 0)),
		int(cfg.get_value("stats", "gold_earned", 0)))
