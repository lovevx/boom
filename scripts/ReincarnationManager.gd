extends Node
## 全局转生管理器（Autoload 单例）。
## 负责 RP（转生点）的计算与消耗、累计转生次数、永久技能树（三大方向）的状态与存取，
## 以及在每局开始时把已点亮的永久加成折叠进 UpgradeManager / GoldManager。
##
## 对应文档：docs/Reincarnation.md（五、永久技能树；四、RP 收益公式；六、本地存档）。
## 设计定位：跨局 meta 层。单局内数值由 UpgradeManager 维护，本节点只在"开局"与"转生结算"两个时刻与其交互。
## 持久化统一由 SaveManager（3 槽位存档）负责：本节点不再自带读写，只暴露状态与结算方法。

# —— RP 收益常量（对齐 docs/Reincarnation.md 四，当前生效值）——
const RP_GAIN_BASE: int = 1000              # 4000 / 9000 / 16000 产出金币 → 2 / 3 / 4 RP
const RP_GAIN_K: float = 1.0                 # 收益系数（未来调档用，当前 1.0）
const MIN_RUN_GOLD_FOR_GAIN: int = 4000     # 首次有效转生给 2 RP
const MAX_RP_PER_RUN: int = 8               # 单局收益上限，保留多次转生的成长目标

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
	"auto_hammer":    {"name": "全自动锤",     "category": "ATTACK", "max_level": 1, "costs": [2],       "kind": "flag"},
	"destroy_power":  {"name": "破坏之力",     "category": "ATTACK", "max_level": 3, "costs": [1, 2, 3], "kind": "percent"},
	"swift_wind":     {"name": "疾风之势",     "category": "ATTACK", "max_level": 2, "costs": [1, 2],    "kind": "percent"},
	"giant_power":    {"name": "巨人之力",     "category": "ATTACK", "max_level": 2, "costs": [1, 2],    "kind": "flat"},
	"gravity_accel":  {"name": "重力加速",     "category": "ATTACK", "max_level": 2, "costs": [1, 2],    "kind": "percent"},
	# 方向③ 炮台（基础数值提升 + 伤害升级）
	"turret_base_damage": {"name": "炮塔基础伤害", "category": "TURRET", "max_level": 2, "costs": [1, 2],    "kind": "flat"},
	"ammo_enhance":   {"name": "弹药强化",     "category": "TURRET", "max_level": 3, "costs": [1, 2, 3], "kind": "percent"},
	"blast_range":    {"name": "爆裂范围",     "category": "TURRET", "max_level": 2, "costs": [1, 2],    "kind": "percent"},
}

# 永久分支：先点基础节点，再沿该方向发展。旧档已购买节点继续保留。
const NODE_PRE_REQS := {
	"initial_capital": {"node": "coin_heart", "lvl": 1},
	"coin_per_kill": {"node": "coin_heart", "lvl": 2},
	"auto_hammer": {"node": "base_damage", "lvl": 1},
	"destroy_power": {"node": "base_damage", "lvl": 1},
	"swift_wind": {"node": "destroy_power", "lvl": 1},
	"giant_power": {"node": "base_damage", "lvl": 1},
	"gravity_accel": {"node": "giant_power", "lvl": 1},
	"ammo_enhance": {"node": "turret_base_damage", "lvl": 1},
	"blast_range": {"node": "ammo_enhance", "lvl": 1},
}
const INITIAL_CAPITAL := [0, 20, 60, 140]

# —— 机制升级（转生次数门槛解锁，不花 RP）——
const MECHANIC_THRESHOLDS := {
	"crit": 1,     # 暴击系统 ≥ 1 次
	"chain": 2,    # 连锁伤害加成 ≥ 2 次
	"scatter": 3,  # 散射炮 ≥ 3 次
}
# —— 炮台数量升级（转生次数门槛解锁，不花 RP）——
const LAUNCHER_COUNT_THRESHOLDS := [1, 3, 5, 8]   # 转生 ≥1/3/5/8 → 开局自带炮台 1/2/3/4 台


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
	return get_node_lock_reason(nid).is_empty() and cost > 0 and reincarnation_points >= cost


## 用 RP 点亮一个永久节点的一级。成功扣 RP、等级 +1、立即重算当前局属性并落盘，返回 true。
func purchase_node(nid: String) -> bool:
	if not NODE_DEFS.has(nid):
		return false
	var cost := get_node_cost(nid)
	if not can_afford_node(nid):
		return false
	var old_capital := _get_initial_capital()
	reincarnation_points -= cost
	permanent_nodes[nid] = get_node_level(nid) + 1
	UpgradeManager.recalculate_stats()
	GoldManager.grant_starting_gold(_get_initial_capital() - old_capital)
	UpgradeManager.upgrades_changed.emit()
	SaveManager.save_current_slot()   # 落盘到当前槽位
	reincarnation_changed.emit()
	permanent_node_changed.emit(nid, int(permanent_nodes[nid]))
	return true


# —— RP 收益：对齐 docs/Reincarnation.md 四 ——
#   获得 RP = floor( sqrt(本局累计金币 / RP_GAIN_BASE) × K )，且本局累计低于 MIN 得 0。

func collect_total_rp(run_total_gold: int) -> int:
	if run_total_gold < MIN_RUN_GOLD_FOR_GAIN:
		return 0
	return mini(MAX_RP_PER_RUN, int(floor(sqrt(float(run_total_gold) / float(RP_GAIN_BASE)) * RP_GAIN_K)))


## 转生结算：根据本局累计金币结算 RP、累计转生次数 +1。
## 只负责 meta 状态落账并广播；单局重置（GoldManager/Upgrade 归零、切回主菜单）由调用方负责，
## 且调用方在结算后需 SaveManager.save_current_slot() 落盘"转生后新开局"状态。
## 返回本次获得的 RP，供转生流程弹窗展示。
func reincarnate() -> int:
	var gained := collect_total_rp(GoldManager.lifetime_gold_this_run)
	if gained <= 0:
		return 0
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


## 开局自带炮台数量：按累计转生次数 1/3/5/8 映射 1/2/3/4 台。
func get_starting_launcher_count() -> int:
	var n := 0
	for threshold in LAUNCHER_COUNT_THRESHOLDS:
		if total_reincarnations >= threshold:
			n += 1
	return n


# —— 永久加成结算（每局开局调用一次，须在 UpgradeManager.reset() 之后）——
# 对齐 Growth_Model 双层公式：永久层折叠进单局层起点值。
# 注意：金币/伤害/攻速/下落用百分比乘进起点；范围/基础伤害/炮台基础伤害用绝对值加进起点。

func apply_permanent_bonuses(grant_capital: bool = true) -> void:
	UpgradeManager.recalculate_stats()
	if grant_capital:
		GoldManager.grant_starting_gold(_get_initial_capital())


func get_node_lock_reason(nid: String) -> String:
	if not NODE_DEFS.has(nid):
		return "未知节点"
	if get_node_level(nid) > 0 or not NODE_PRE_REQS.has(nid):
		return ""
	var pre: Dictionary = NODE_PRE_REQS[nid]
	if get_node_level(pre.node) < int(pre.lvl):
		return "需%s Lv.%d" % [NODE_DEFS[pre.node].name, pre.lvl]
	return ""


func get_next_rp_gold(run_gold: int) -> int:
	if collect_total_rp(run_gold) >= MAX_RP_PER_RUN:
		return 0
	var next := collect_total_rp(run_gold) + 1
	return maxi(MIN_RUN_GOLD_FOR_GAIN, int(ceil(RP_GAIN_BASE * pow(float(next) / RP_GAIN_K, 2))))


func get_milestone_text(count: int) -> String:
	var parts: Array[String] = []
	for mech in MECHANIC_THRESHOLDS:
		if int(MECHANIC_THRESHOLDS[mech]) == count:
			parts.append({"crit": "暴击升级", "chain": "连锁升级", "scatter": "散射升级"}[mech])
	if count in LAUNCHER_COUNT_THRESHOLDS:
		parts.append("开局自带 %d 台炮台" % (LAUNCHER_COUNT_THRESHOLDS.find(count) + 1))
	return "、".join(parts) if not parts.is_empty() else "永久成长继续累积"


func get_node_effect(nid: String, lv: int) -> String:
	if PERCENT_POINTS.has(nid):
		var title: String = {"coin_heart": "金币产出", "destroy_power": "锤击伤害", "swift_wind": "锤击攻速", "gravity_accel": "建筑下落", "ammo_enhance": "炮弹伤害", "blast_range": "爆炸半径"}[nid]
		return "%s +%d%%" % [title, roundi(float(PERCENT_POINTS[nid]) * lv * 100.0)]
	match nid:
		"initial_capital": return "开局资金 %d 金币" % INITIAL_CAPITAL[lv]
		"auto_hammer": return "自动瞄准底层挥砸" if lv > 0 else "尚未开启自动锤"
		"base_damage": return "锤击基础伤害 +%.1f" % (float(FLAT_POINTS[nid]) * lv)
		"coin_per_kill": return "每块基础金币 +%d" % lv
		"giant_power": return "锤击范围 +%d px" % (float(FLAT_POINTS[nid]) * lv)
		"turret_base_damage": return "炮弹基础伤害 +%d" % (float(FLAT_POINTS[nid]) * lv)
	return ""


# 锤子基础伤害（= 初始 1.0 + 基础伤害永久加值）。由 Hammer.gd _smash 消费。
func get_hammer_base_damage() -> float:
	return 1.0 + _get_flat_sum("base_damage")


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


# 初始资金：20 / 60 / 140 金币（不记 RP 产出）。
func _get_initial_capital() -> int:
	return int(_get_flat_sum("initial_capital"))


# —— 加总：同"kind"的同类节点按永久等级累加 ——

# 百分比节点：level × 单级增量（节点目录里的第 idx 级增量 == idx，见各节点定义）。
# 采用统一表驱动：percent_points = {"coin_heart":0.5, "destroy_power":0.05, ...}
const PERCENT_POINTS := {
	"coin_heart": 0.25,        # +25%/级
	"destroy_power": 0.20,    # +20%/级
	"swift_wind": 0.10,       # +10%/级
	"gravity_accel": 0.25,    # +25%/级
	"ammo_enhance": 0.15,     # +15%/级
	"blast_range": 0.10,      # +10%/级
}


func _get_percent_sum(nid: String) -> float:
	var lv := get_node_level(nid)
	if lv <= 0:
		return 0.0
	return PERCENT_POINTS.get(nid, 0.0) * lv


# 绝对值节点：单级增量表（巨人之力 +12/级、炮塔基础伤害 +2/级、击破金币 +1/级、初始资金按档、基础伤害 +0.5/级）
const FLAT_POINTS := {
	"giant_power": 12.0,          # 锤子范围 +12px/级
	"turret_base_damage": 2.0,    # 炸弹基础伤害 +2/级
	"coin_per_kill": 1.0,         # 击破金币 +1/级
	"base_damage": 0.5,           # 锤子基础伤害 +0.5/级
}


func _get_flat_sum(nid: String) -> float:
	var lv := get_node_level(nid)
	if lv <= 0:
		return 0.0
	# 初始资金按 INITIAL_CAPITAL 档位处理
	if nid == "initial_capital":
		return float(INITIAL_CAPITAL[lv])
	return FLAT_POINTS.get(nid, 0.0) * lv
