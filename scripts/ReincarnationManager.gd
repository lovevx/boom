extends Node
## 全局转生管理器（Autoload 单例）。
## 负责 RP（转生点）的计算与消耗、累计转生次数、永久技能树（三大方向）的状态与存取，
## 以及在每局开始时把已点亮的永久加成折叠进 UpgradeManager / GoldManager。
##
## 对应文档：docs/Reincarnation.md（五、永久技能树；四、RP 收益公式；六、本地存档）。
## 设计定位：跨局 meta 层。单局内数值由 UpgradeManager 维护，本节点只在"开局"与"转生结算"两个时刻与其交互。
## 持久化统一由 SaveManager（3 槽位存档）负责：本节点不再自带读写，只暴露状态与结算方法。

# —— RP 收益常量（对齐 docs/Reincarnation.md 四，当前生效值）——
const RP_GAIN_BASE: int = 300_000            # 基准金币，30 万金币 ≈ 1 RP
const RP_GAIN_K: float = 1.0                 # 收益系数（未来调档用，当前 1.0）
const MIN_RUN_GOLD_FOR_GAIN: int = 10_000    # 低于此累计金币，转生只得 0 RP

signal reincarnation_changed            # RP 余额 / 累计转生次数变化（供转生界面刷新）
signal permanent_node_changed(node_id: String, level: int)   # 某永久节点点亮（供技能树刷新）

# —— 本地存档内 state ——
var reincarnation_points: int = 0            # 当前 RP 余额
var total_reincarnations: int = 0            # 累计转生次数

# 各永久节点点亮等级，形如 {"coin_heart": 2, "base_damage": 1, ...}
var permanent_nodes: Dictionary = {}


# —— 永久节点目录：id → {name, category, max_level, costs, kind}——
# kind 仅用于 UI 分组与区分"百分比/绝对值/标记"，数值计算集中在 _accumulate_* 方法里。
const NODE_DEFS := {
	# 方向① 获取金币
	"coin_heart":     {"name": "金币之心",     "category": "GOLD", "max_level": 3, "costs": [1, 2, 3], "kind": "percent"},
	"initial_capital": {"name": "初始资金",     "category": "GOLD", "max_level": 3, "costs": [1, 2, 3], "kind": "flat"},
	"coin_per_kill":  {"name": "击破金币",     "category": "GOLD", "max_level": 2, "costs": [1, 2],    "kind": "flat"},
	# 方向② 攻击（基础数值提升 + 百分比提升）
	"base_damage":    {"name": "基础伤害",     "category": "ATTACK", "max_level": 2, "costs": [1, 2],    "kind": "flat"},
	"auto_hammer":    {"name": "全自动锤",     "category": "ATTACK", "max_level": 1, "costs": [1],       "kind": "flag"},
	"destroy_power":  {"name": "破坏之力",     "category": "ATTACK", "max_level": 3, "costs": [1, 2, 3], "kind": "percent"},
	"swift_wind":     {"name": "疾风之势",     "category": "ATTACK", "max_level": 2, "costs": [1, 2],    "kind": "percent"},
	"giant_power":    {"name": "巨人之力",     "category": "ATTACK", "max_level": 2, "costs": [1, 2],    "kind": "flat"},
	"gravity_accel":  {"name": "重力加速",     "category": "ATTACK", "max_level": 2, "costs": [1, 2],    "kind": "percent"},
	# 方向③ 炮台（基础数值提升 + 伤害升级）
	"turret_base_damage": {"name": "炮塔基础伤害", "category": "TURRET", "max_level": 2, "costs": [1, 2],    "kind": "flat"},
	"ammo_enhance":   {"name": "弹药强化",     "category": "TURRET", "max_level": 3, "costs": [1, 2, 3], "kind": "percent"},
	"blast_range":    {"name": "爆裂范围",     "category": "TURRET", "max_level": 2, "costs": [1, 2],    "kind": "percent"},
}

# —— 机制升级（转生次数门槛解锁，不花 RP）——
const MECHANIC_THRESHOLDS := {
	"crit": 1,     # 暴击系统 ≥ 1 次
	"chain": 2,    # 连锁伤害加成 ≥ 2 次
	"scatter": 3,  # 散射炮 ≥ 3 次
}
# —— 炮台数量升级（转生次数门槛解锁，不花 RP）——
const LAUNCHER_COUNT_THRESHOLDS := [1, 2, 3, 4]   # 转生 ≥1/2/3/4 → 开局自带炮台 1/2/3/4 台


# —— 永久节点：状态查询 ——

func get_node_level(nid: String) -> int:
	return int(permanent_nodes.get(nid, 0))


func get_node_max_level(nid: String) -> int:
	return NODE_DEFS[nid].max_level


func is_node_mastered(nid: String) -> bool:
	return get_node_level(nid) >= get_node_max_level(nid)


# 下一级费用；已满级返回 -1（供 UI 置灰"已满级"）。
func get_node_cost(nid: String) -> int:
	if not NODE_DEFS.has(nid):
		return -1
	var lv: int = get_node_level(nid)
	if lv >= get_node_max_level(nid):
		return -1
	return int(NODE_DEFS[nid].costs[lv])


# —— 永久节点：购买 / 加点 ——

func can_afford_node(nid: String) -> bool:
	var cost := get_node_cost(nid)
	return cost > 0 and reincarnation_points >= cost


## 用 RP 点亮一个永久节点的一级。成功扣 RP、等级 +1、立即生效并落盘，返回 true。
func purchase_node(nid: String) -> bool:
	if not NODE_DEFS.has(nid):
		return false
	var cost := get_node_cost(nid)
	if cost <= 0 or reincarnation_points < cost:
		return false
	reincarnation_points -= cost
	permanent_nodes[nid] = get_node_level(nid) + 1
	SaveManager.save_current_slot()   # 落盘到当前槽位
	reincarnation_changed.emit()
	permanent_node_changed.emit(nid, int(permanent_nodes[nid]))
	return true


# —— RP 收益：对齐 docs/Reincarnation.md 四 ——
#   获得 RP = floor( sqrt(本局累计金币 / RP_GAIN_BASE) × K )，且本局累计低于 MIN 得 0。

func collect_total_rp(run_total_gold: int) -> int:
	if run_total_gold < MIN_RUN_GOLD_FOR_GAIN:
		return 0
	return int(floor(sqrt(float(run_total_gold) / float(RP_GAIN_BASE)) * RP_GAIN_K))


## 转生结算：根据本局累计金币结算 RP、累计转生次数 +1。
## 只负责 meta 状态落账并广播；单局重置（GoldManager/Upgrade 归零、切回主菜单）由调用方负责，
## 且调用方在结算后需 SaveManager.save_current_slot() 落盘"转生后新开局"状态。
## 返回本次获得的 RP，供转生流程弹窗展示。
func reincarnate() -> int:
	var gained := collect_total_rp(GoldManager.lifetime_gold_this_run)
	reincarnation_points += gained
	total_reincarnations += 1
	reincarnation_changed.emit()
	return gained


## 直接在余额上增加指定 RP（仅测试面板调试用），落账并广播刷新。
func add_reincarnation_points(amount: int) -> void:
	reincarnation_points += amount
	SaveManager.save_current_slot()
	reincarnation_changed.emit()


# —— 机制 / 数量升级门槛（按累计转生次数自动解锁，不花 RP）——

func is_mechanic_unlocked(mech_id: String) -> bool:
	return MECHANIC_THRESHOLDS.get(mech_id, 2147483647) <= total_reincarnations


func get_unlocked_mechanics() -> Array[String]:
	var out: Array[String] = []
	for m in MECHANIC_THRESHOLDS:
		if is_mechanic_unlocked(m):
			out.append(m)
	return out


## 开局自带炮台数量：按累计转生次数映射 1/2/3/4（≥4 封顶 4 台）。
func get_starting_launcher_count() -> int:
	var n := 0
	for threshold in LAUNCHER_COUNT_THRESHOLDS:
		if total_reincarnations >= threshold:
			n += 1
	return n


# —— 永久加成结算（每局开局调用一次，须在 UpgradeManager.reset() 之后）——
# 对齐 Growth_Model 双层公式：永久层折叠进单局层起点值。
# 注意：金币/伤害/攻速/下落用百分比乘进起点；范围/基础伤害/炮台基础伤害用绝对值加进起点。

func apply_permanent_bonuses() -> void:
	# 方向① 金币：金币之心（百分比乘进起点）
	UpgradeManager.coin_multiplier = 1.0 * (1.0 + _get_percent_sum("coin_heart"))
	# 方向② 攻击·百分比：破坏之力 / 疾风之势 / 重力加速（乘进起点）
	UpgradeManager.hammer_damage = 1.0 * (1.0 + _get_percent_sum("destroy_power"))
	UpgradeManager.hammer_speed = 1.0 * (1.0 + _get_percent_sum("swift_wind"))
	UpgradeManager.building_drop_speed = 1.0 * (1.0 + _get_percent_sum("gravity_accel"))
	# 方向② 攻击·绝对值：巨人之力（锤子范围加到起点 0）
	UpgradeManager.hammer_range = UpgradeManager.hammer_range + _get_flat_sum("giant_power")
	# 方向② 攻击·标记：全自动锤（开局即开启）
	if get_node_level("auto_hammer") > 0:
		UpgradeManager.auto_hammer = true
	# 方向① 初始资金：开局直接送金币
	GoldManager.add_gold(_get_initial_capital())
	# 以下数值消费已接线（2026-08-25），本节点只暴露数值，实装侧在对应模块消费——
	#   get_hammer_base_damage()   → Hammer.gd _smash（替换原硬编码基础伤害 1.0）
	#   get_coin_per_kill_bonus()  → BuildingBlock._spawn_gold（叠加进击破基底）
	#   get_bomb_damage_mult() / get_bomb_base_damage_bonus() → BombLauncher._spawn_projectile（炸弹伤害）
	#   get_bomb_radius_mult()     → BombLauncher._spawn_projectile（炸弹爆炸半径）
	#   get_starting_launcher_count() → UpgradeManager.reset() 注入 _bomb_launcher_level
	#   is_mechanic_unlocked()/get_unlocked_mechanics() → UpgradePanel 机制节点 req + Hammer 暴击 / BombProjectile 连锁 / BombLauncher 散射


# 锤子基础伤害（= 初始 1.0 + 基础伤害永久加值）。由 Hammer.gd _smash 消费。
func get_hammer_base_damage() -> float:
	return 1.0 + int(_get_flat_sum("base_damage"))


# 单块击破的基础金币加成（击破金币 +1/+2）。
func get_coin_per_kill_bonus() -> int:
	return int(_get_flat_sum("coin_per_kill"))


# 炸弹伤害百分比倍率（弹药强化，作用于 BOMB_DAMAGES 表值起点）。
func get_bomb_damage_mult() -> float:
	return 1.0 + _get_percent_sum("ammo_enhance")


# 炸弹基础伤害加值（炮塔基础伤害 +3/+6）。
func get_bomb_base_damage_bonus() -> int:
	return int(_get_flat_sum("turret_base_damage"))


# 炸弹爆炸半径百分比倍率（爆裂范围）。
func get_bomb_radius_mult() -> float:
	return 1.0 + _get_percent_sum("blast_range")


# 初始资金：500 / 1500 / 3000 金币。
func _get_initial_capital() -> int:
	return int(_get_flat_sum("initial_capital"))


# —— 加总：同"kind"的同类节点按永久等级累加 ——

# 百分比节点：level × 单级增量（节点目录里的第 idx 级增量 == idx，见各节点定义）。
# 采用统一表驱动：percent_points = {"coin_heart":0.5, "destroy_power":0.05, ...}
const PERCENT_POINTS := {
	"coin_heart": 0.5,        # +50%/级
	"destroy_power": 0.05,    # +5%/级
	"swift_wind": 0.10,       # +10%/级
	"gravity_accel": 0.10,    # +10%/级
	"ammo_enhance": 0.15,     # +15%/级
	"blast_range": 0.15,      # +15%/级
}


func _get_percent_sum(nid: String) -> float:
	var lv := get_node_level(nid)
	if lv <= 0:
		return 0.0
	return PERCENT_POINTS.get(nid, 0.0) * lv


# 绝对值节点：单级增量表（巨人之力 +14/级、炮塔基础伤害 +3/级、击破金币 +1/级、初始资金按档、基础伤害 +1/级）
const FLAT_POINTS := {
	"giant_power": 14.0,          # 锤子范围 +14px/级
	"turret_base_damage": 3.0,    # 炸弹基础伤害 +3/级
	"coin_per_kill": 1.0,         # 击破金币 +1/级
	"base_damage": 1.0,           # 锤子基础伤害 +1/级
}


func _get_flat_sum(nid: String) -> float:
	var lv := get_node_level(nid)
	if lv <= 0:
		return 0.0
	# 初始资金为非线性档位：500/1500/3000，单独处理
	if nid == "initial_capital":
		return [0.0, 500.0, 1500.0, 3000.0][lv]
	return FLAT_POINTS.get(nid, 0.0) * lv