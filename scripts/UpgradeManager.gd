extends Node
## 全局升级管理器（Autoload 单例）。
## 统一管理锤子攻速/伤害、金币倍率等升级数值，以及各升级项的等级与费用。
## 升级后立即生效：攻击/爆炸/金币掉落的实际数值都会实时读取这里。

signal upgrades_changed   # 任一升级完成时发出，供升级面板刷新
signal launcher_upgraded(new_level: int)   # 炸弹发射器升级时发出，供 LauncherManager 实时激活/更新

const BASE_COST: int = 2         # 各升级项首次费用（经济随"从1起步"缩档：原 10）
const COST_GROWTH: float = 1.3   # 每次升级后费用成长倍率

# 各可升级项的满级上限（达到后按钮置灰显示"已满级"）。
# 统一口径：基础数值/绝对值增长上限 5 级（等级 0..5）；百分比/倍率增长上限 3 级（等级 0..3）。
const MAX_HAMMER_SPEED_LEVEL: int = 3       # 百分比（攻速倍率，+0.4/级）
const MAX_HAMMER_DAMAGE_LEVEL: int = 3      # 百分比（伤害倍率，+0.3/级）
const MAX_HAMMER_RANGE_LEVEL: int = 5       # 绝对值（+7px/级）
const MAX_COIN_MULTIPLIER_LEVEL: int = 5    # 金币倍率：用户指定上限 5 级
const MAX_COIN_BASE_LEVEL: int = 5          # 绝对值（+5 基础金币/级）
const MAX_BUILDING_DROP_SPEED_LEVEL: int = 3    # 百分比（下落速度倍率，+0.5/级）

# —— 炸弹发射器·数量升级表（索引 = 等级 0..4）——
const MAX_LAUNCHER_COUNT_LEVEL: int = 4
const LAUNCHER_COUNTS: Array[int]   = [0, 1, 2, 3, 4]   # 解锁的发射器数量（数量 = 等级）
const LAUNCHER_COOLDOWNS: Array[float] = [0.0, 3.0, 2.5, 2.0, 1.6]   # 冷却（秒），随数量等级缩短
const LAUNCHER_COSTS: Array[int]    = [2, 12, 25, 50, -1]  # 数量升级费用（满级为 -1，随"从1起步"缩档）

# —— 炸弹发射速率升级表（索引 = 等级 0..3）——
# 倍率作用于基础冷却：最终冷却 = 基础冷却 × 速率倍率（0级 = 1.0 不加速）。百分比类 → 上限 3 级。
const MAX_LAUNCHER_RATE_LEVEL: int = 3
const LAUNCHER_RATE_MULTIPLIERS: Array[float] = [1.0, 0.85, 0.72, 0.62]   # 冷却倍率（随速率等级缩短）
const LAUNCHER_RATE_COSTS: Array[int] = [4, 9, 18, 35]   # 速率升级费用

# —— 炸弹伤害升级表（索引 = 等级 0..5）——
# 绝对值 → 上限 5 级。
const MAX_BOMB_DAMAGE_LEVEL: int = 5
const BOMB_DAMAGES: Array[int] = [3, 4, 6, 9, 12, 16]   # 爆炸伤害（随"从1起步"缩档：原 30~120）
const BOMB_DAMAGE_COSTS: Array[int] = [4, 9, 20, 45, 90, -1]   # 伤害升级费用（满级为 -1，随"从1起步"缩档）

# —— 炸弹范围升级表（索引 = 等级 0..5）——
# 绝对值 → 上限 5 级。
const MAX_BOMB_RADIUS_LEVEL: int = 5
const BOMB_RADII: Array[float] = [80.0, 120.0, 160.0, 200.0, 240.0, 290.0]   # 爆炸半径 px（满级 290）
const BOMB_RADIUS_COSTS: Array[int] = [4, 9, 20, 45, 90, -1]   # 范围升级费用（满级为 -1，随"从1起步"缩档）

# —— 机制升级（转生次数解锁后，单局技能树用金币购买；满级为 -1）——
# 暴击：方块受击时按暴击率判定 × 暴击伤害倍率。
const MAX_CRIT_CHANCE_LEVEL: int = 3
const CRIT_CHANCE_STEP: float = 0.10   # 每级 +10% 暴击率
const CRIT_CHANCE_COSTS: Array[int] = [5, 12, 28, -1]
const MAX_CRIT_MULT_LEVEL: int = 3
const CRIT_MULT_STEP: float = 0.5      # 每级暴击伤害倍率 +0.5（1.0 → 1.5/2.0/2.5）
const CRIT_MULT_COSTS: Array[int] = [5, 12, 28, -1]
# 连锁：爆炸击碎方块后，对周围存留方块追加的连锁加伤比例。
const MAX_CHAIN_LEVEL: int = 3
const CHAIN_STEP: float = 0.15         # 每级连锁加伤 +15%
const CHAIN_COSTS: Array[int] = [6, 14, 32, -1]
# 散射炮：单台每次发射基数（索引 = 等级 0..3），升级→每次多发。
const MAX_SCATTER_LEVEL: int = 3
const SCATTER_MULTIS: Array[float] = [1.0, 2.0, 3.0, 4.0]
const SCATTER_COSTS: Array[int] = [10, 22, 48, -1]

# —— 实际生效的升级倍率（供其它脚本读取）——
var hammer_speed: float = 1.0     # 锤子攻速倍率（1.0 为初始）
var hammer_damage: float = 1.0    # 锤子/爆炸伤害倍率（1.0 为初始）
var hammer_range: float = 0.0     # 锤子范围（命中半径，0 为仅命中点击处单个方块）
var coin_multiplier: float = 1.0  # 金币倍率（1.0 为初始）
var coin_base: int = 0            # 单块击破的基础金币加值（绝对值，加到击破基底上，见 BuildingBlock._spawn_gold）
var auto_hammer: bool = false     # 全自动锤子：开启后无需点击自动挥砸建筑
var building_drop_speed: float = 1.0   # 建筑塌落下坠速度倍率（1.0 为初始，越大下落越快）

# —— 各升级项的当前等级 ——
var _hammer_speed_level: int = 0
var _hammer_damage_level: int = 0
var _hammer_range_level: int = 0
var _coin_multiplier_level: int = 0
var _coin_base_level: int = 0
var _building_drop_speed_level: int = 0
var _bomb_launcher_level: int = 0       # 发射器数量等级（0 = 未解锁）
var _bomb_rate_level: int = 0           # 发射速率等级
var _bomb_damage_level: int = 0         # 炸弹伤害等级
var _bomb_radius_level: int = 0         # 炸弹范围等级

# —— 机制升级实际生效值（供锤子/炸弹实体读取）——
var crit_chance: float = 0.0            # 暴击率（0..1，命中时概率判定）
var crit_multiplier: float = 1.0        # 暴击伤害倍率
var chain_damage: float = 0.0           # 爆炸连锁加伤比例
var _crit_chance_level: int = 0
var _crit_mult_level: int = 0
var _chain_level: int = 0
var _scatter_level: int = 0


# —— 升级方法（提升数值并广播信号）——

func upgrade_hammer_speed() -> void:
	if _hammer_speed_level >= MAX_HAMMER_SPEED_LEVEL:
		return
	_hammer_speed_level += 1
	hammer_speed += 0.4
	upgrades_changed.emit()


func upgrade_building_drop_speed() -> void:
	if _building_drop_speed_level >= MAX_BUILDING_DROP_SPEED_LEVEL:
		return
	_building_drop_speed_level += 1
	building_drop_speed += 0.5   # 每级下落提速 50%（动画时长 = 0.3s / 倍率）
	upgrades_changed.emit()


func upgrade_hammer_damage() -> void:
	if _hammer_damage_level >= MAX_HAMMER_DAMAGE_LEVEL:
		return
	_hammer_damage_level += 1
	hammer_damage += 0.3
	upgrades_changed.emit()


func upgrade_hammer_range() -> void:
	if _hammer_range_level >= MAX_HAMMER_RANGE_LEVEL:
		return   # 已达到范围满级，防越界
	_hammer_range_level += 1
	hammer_range += 7.0   # 每级 +7px 命中半径（经验值：原 +40px 太巨大，缩为收敛的小增量）
	upgrades_changed.emit()


func upgrade_coin_multiplier() -> void:
	if _coin_multiplier_level >= MAX_COIN_MULTIPLIER_LEVEL:
		return
	_coin_multiplier_level += 1
	coin_multiplier += 0.5
	upgrades_changed.emit()


# 金币基础加值：每级单块击破基础金币 +5（绝对，加到 BuildingBlock._spawn_gold 的击破基底）。
func upgrade_coin_base() -> void:
	if _coin_base_level >= MAX_COIN_BASE_LEVEL:
		return
	_coin_base_level += 1
	coin_base += 5
	upgrades_changed.emit()


# 升级发射器数量：解锁下一个发射器（l1 r1 l2 r2，左二右二）。等级+1，广播刷新信号 + 专用信号（LauncherManager 据此激活新炮台）。
func upgrade_bomb_launcher() -> void:
	if _bomb_launcher_level >= MAX_LAUNCHER_COUNT_LEVEL:
		return   # 已满级，防越界
	_bomb_launcher_level += 1
	upgrades_changed.emit()
	launcher_upgraded.emit(_bomb_launcher_level)


# 升级炸弹发射速率：缩短冷却（独立于数量/伤害/范围）。
func upgrade_bomb_rate() -> void:
	if _bomb_rate_level >= MAX_LAUNCHER_RATE_LEVEL:
		return
	_bomb_rate_level += 1
	upgrades_changed.emit()
	# 速率影响已部署炮台的冷却，这里用发射器信号让 LauncherManager 实时刷新（等级不变，仅刷新冷却）。
	launcher_upgraded.emit(_bomb_launcher_level)


# 升级炸弹伤害（独立于数量/范围）。
func upgrade_bomb_damage() -> void:
	if _bomb_damage_level >= MAX_BOMB_DAMAGE_LEVEL:
		return
	_bomb_damage_level += 1
	upgrades_changed.emit()


# 升级炸弹爆炸范围（独立于数量/伤害）。
func upgrade_bomb_radius() -> void:
	if _bomb_radius_level >= MAX_BOMB_RADIUS_LEVEL:
		return
	_bomb_radius_level += 1
	upgrades_changed.emit()


# —— 机制升级方法（转生次数解锁后，面板可金币购买）——

func upgrade_crit_chance() -> void:
	if _crit_chance_level >= MAX_CRIT_CHANCE_LEVEL:
		return
	_crit_chance_level += 1
	crit_chance += CRIT_CHANCE_STEP
	upgrades_changed.emit()


func upgrade_crit_mult() -> void:
	if _crit_mult_level >= MAX_CRIT_MULT_LEVEL:
		return
	_crit_mult_level += 1
	crit_multiplier += CRIT_MULT_STEP
	upgrades_changed.emit()


func upgrade_chain() -> void:
	if _chain_level >= MAX_CHAIN_LEVEL:
		return
	_chain_level += 1
	chain_damage += CHAIN_STEP
	upgrades_changed.emit()


func upgrade_scatter() -> void:
	if _scatter_level >= MAX_SCATTER_LEVEL:
		return
	_scatter_level += 1
	upgrades_changed.emit()


# 重置全部升级：等级归 0、实际生效数值复位到初始值。
# 复位后广播 upgrades_changed（技能树刷新），并广播 launcher_upgraded(0)（让 LauncherManager 隐藏全部炮台）。
# 用于"重新开始"，需彻底复位以清除上一次游玩残留的等级。
func reset() -> void:
	# 六个数值类升级项：等级与派生数值一起复位
	_hammer_speed_level = 0   ; hammer_speed = 1.0
	_hammer_damage_level = 0  ; hammer_damage = 1.0
	_hammer_range_level = 0   ; hammer_range = 0.0
	_coin_multiplier_level = 0 ; coin_multiplier = 1.0
	_coin_base_level = 0       ; coin_base = 0
	auto_hammer = false   # 全自动锤仅由转生永久树提供，单局无节点；reset 复位后由 apply_permanent_bonuses 折叠
	_building_drop_speed_level = 0 ; building_drop_speed = 1.0
	# 炸弹分支四张升级表：等级全部归 0（炮台全部未解锁）
	_bomb_launcher_level = 0
	_bomb_rate_level = 0
	_bomb_damage_level = 0
	_bomb_radius_level = 0
	# 机制升级：等级归 0、派生值归位（转生门槛解锁由 ReincarnationManager 判定，单局等级不跨局保留）
	_crit_chance_level = 0  ; crit_chance = 0.0
	_crit_mult_level = 0    ; crit_multiplier = 1.0
	_chain_level = 0        ; chain_damage = 0.0
	_scatter_level = 0
	# 永久层·方向③数量升级：开局按累计转生次数自带炮台（转生 ≥1/2/3/4 → 1/2/3/4 台）
	_bomb_launcher_level = ReincarnationManager.get_starting_launcher_count()
	upgrades_changed.emit()
	launcher_upgraded.emit(_bomb_launcher_level)


# 从存档等级恢复单局升级状态。前提：已执行 reset() + ReincarnationManager.apply_permanent_bonuses()
# （即"永久加成折叠后的起点"已就位）。此处按存档等级逐级叠加单局增量：
# 复用各 upgrade_* 方法保证派生数值公式与实玩完全一致（单一数据源）。
# 发射器数量是"绝对等级"（含开局自带数），与 reset 的起始数叠加会重复计数，故单独直接设置。
func set_state_from_save(s: Dictionary) -> void:
	for i in maxi(0, int(s.get("hammer_speed", 0))):
		upgrade_hammer_speed()
	for i in maxi(0, int(s.get("hammer_damage", 0))):
		upgrade_hammer_damage()
	for i in maxi(0, int(s.get("hammer_range", 0))):
		upgrade_hammer_range()
	for i in maxi(0, int(s.get("coin_multiplier", 0))):
		upgrade_coin_multiplier()
	for i in maxi(0, int(s.get("coin_base", 0))):
		upgrade_coin_base()
	for i in maxi(0, int(s.get("building_drop_speed", 0))):
		upgrade_building_drop_speed()
	for i in maxi(0, int(s.get("crit_chance", 0))):
		upgrade_crit_chance()
	for i in maxi(0, int(s.get("crit_mult", 0))):
		upgrade_crit_mult()
	for i in maxi(0, int(s.get("chain", 0))):
		upgrade_chain()
	for i in maxi(0, int(s.get("scatter", 0))):
		upgrade_scatter()
	_bomb_launcher_level = clampi(int(s.get("bomb_launcher", ReincarnationManager.get_starting_launcher_count())), 0, MAX_LAUNCHER_COUNT_LEVEL)
	_bomb_rate_level = clampi(int(s.get("bomb_rate", 0)), 0, MAX_LAUNCHER_RATE_LEVEL)
	_bomb_damage_level = clampi(int(s.get("bomb_damage", 0)), 0, MAX_BOMB_DAMAGE_LEVEL)
	_bomb_radius_level = clampi(int(s.get("bomb_radius", 0)), 0, MAX_BOMB_RADIUS_LEVEL)
	upgrades_changed.emit()
	launcher_upgraded.emit(_bomb_launcher_level)


# —— 获取当前等级的升级费用（初始 10，每级 ×1.5 取整）——

func get_hammer_speed_cost() -> int:
	return _cost_for_level(_hammer_speed_level)


func get_building_drop_speed_cost() -> int:
	return _cost_for_level(_building_drop_speed_level)


func get_hammer_damage_cost() -> int:
	if _hammer_damage_level == 0:
		return 2   # 首级固定 2 金币：与新手引导"摧毁方块得 2 金币 → 加一次伤害"闭环
	return _cost_for_level(_hammer_damage_level)


func get_hammer_range_cost() -> int:
	return _cost_for_level(_hammer_range_level)


func get_coin_multiplier_cost() -> int:
	return _cost_for_level(_coin_multiplier_level)


func get_coin_base_cost() -> int:
	return _cost_for_level(_coin_base_level)


# 发射器数量的升级费用：由独立费用表维护（满级返回 -1，供面板判定）。
func get_bomb_launcher_cost() -> int:
	return LAUNCHER_COSTS[_bomb_launcher_level]


# 发射速率的升级费用：由独立费用表维护。
func get_bomb_rate_cost() -> int:
	return LAUNCHER_RATE_COSTS[_bomb_rate_level]


# 炸弹伤害升级费用：由独立费用表维护。
func get_bomb_damage_cost() -> int:
	return BOMB_DAMAGE_COSTS[_bomb_damage_level]


# 炸弹范围升级费用：由独立费用表维护。
func get_bomb_radius_cost() -> int:
	return BOMB_RADIUS_COSTS[_bomb_radius_level]


# —— 获取当前等级 ——

func get_bomb_launcher_level() -> int:
	return _bomb_launcher_level

func get_bomb_rate_level() -> int:
	return _bomb_rate_level

func get_bomb_damage_level() -> int:
	return _bomb_damage_level

func get_bomb_radius_level() -> int:
	return _bomb_radius_level

func get_hammer_speed_level() -> int:
	return _hammer_speed_level


func get_building_drop_speed_level() -> int:
	return _building_drop_speed_level


func get_hammer_damage_level() -> int:
	return _hammer_damage_level


func get_hammer_range_level() -> int:
	return _hammer_range_level


func get_coin_multiplier_level() -> int:
	return _coin_multiplier_level


func get_coin_base_level() -> int:
	return _coin_base_level


# —— 炸弹发射器属性查询（实时读取，升级后立即生效）——

func get_bomb_launcher_count() -> int:
	return LAUNCHER_COUNTS[_bomb_launcher_level]


func get_bomb_launcher_cooldown() -> float:
	# 最终冷却 = 基础冷却（随数量） × 速率倍率（独立升级）
	return LAUNCHER_COOLDOWNS[_bomb_launcher_level] * LAUNCHER_RATE_MULTIPLIERS[_bomb_rate_level]


# 当前发射速率倍率（越小冷却越短；1.0 为初始）。
func get_bomb_rate_multiplier() -> float:
	return LAUNCHER_RATE_MULTIPLIERS[_bomb_rate_level]


func get_bomb_launcher_damage() -> int:
	return BOMB_DAMAGES[_bomb_damage_level]


func get_bomb_launcher_radius() -> float:
	return BOMB_RADII[_bomb_radius_level]


# —— 机制升级费用 / 等级 / 生效值查询 ——

func get_crit_chance_cost() -> int:
	return CRIT_CHANCE_COSTS[_crit_chance_level]


func get_crit_mult_cost() -> int:
	return CRIT_MULT_COSTS[_crit_mult_level]


func get_chain_cost() -> int:
	return CHAIN_COSTS[_chain_level]


func get_scatter_cost() -> int:
	return SCATTER_COSTS[_scatter_level]


func get_crit_chance_level() -> int:
	return _crit_chance_level


func get_crit_mult_level() -> int:
	return _crit_mult_level


func get_chain_level() -> int:
	return _chain_level


func get_scatter_level() -> int:
	return _scatter_level


# 每次发射的炮弹数（散射炮升级；等级 0 时 = 1）。
func get_scatter_count() -> int:
	return int(SCATTER_MULTIS[_scatter_level])


# ================================================================
# —— 单局技能树：节点状态统一出口（放射状面板使用）——
# 结构参照 docs/SkillTree.md：节点 id → 前置/机制门/最大等级/中文名。
# ================================================================

## 节点中文名（用于锁定提示）
const NODE_TITLES := {
	"hammer_speed": "锤子速度", "hammer_damage": "锤子伤害", "hammer_range": "锤子范围",
	"coin_multiplier": "金币倍率", "coin_base": "基础金币", "building_drop_speed": "下落速度",
	"bomb_launcher": "发射器数量", "bomb_damage": "炸弹伤害", "bomb_radius": "炸弹范围",
	"bomb_rate": "发射速率", "crit_chance": "暴击几率", "crit_mult": "暴击伤害",
	"chain": "连锁伤害", "scatter": "散射炮",
}

## 前置依赖：节点 → 满足其一即可的前置节点列表组（每组内为 {node,lvl} 的或分支）。
## 这里取"单一前置"（每组仅一条），更复杂的或分支后续再扩。
const NODE_PRE_REQS := {
	"crit_chance": [{"node": "hammer_damage", "lvl": 2}],
	"crit_mult":   [{"node": "hammer_damage", "lvl": 2}],
	"bomb_damage": [{"node": "bomb_launcher", "lvl": 1}],
	"bomb_radius": [{"node": "bomb_launcher", "lvl": 1}],
	"bomb_rate":   [{"node": "bomb_launcher", "lvl": 1}],
	"chain":       [{"node": "bomb_damage", "lvl": 2}],
	"scatter":     [{"node": "bomb_damage", "lvl": 2}],
}

## 机制门：节点 → 需转生解锁的机制（转到 ReincarnationManager.is_mechanic_unlocked）
const NODE_MECHANIC_GATE := {
	"crit_chance": "crit", "crit_mult": "crit",
	"chain": "chain", "scatter": "scatter",
}
const MECH_GATE_THRESHOLD := {"crit": 1, "chain": 2, "scatter": 3}

## 节点满级（-1 = 无上限）。与各 get_*_level / 升级方法一致。
func get_node_max_level(nid: String) -> int:
	match nid:
		"hammer_speed": return MAX_HAMMER_SPEED_LEVEL
		"hammer_damage": return MAX_HAMMER_DAMAGE_LEVEL
		"hammer_range": return MAX_HAMMER_RANGE_LEVEL
		"coin_multiplier": return MAX_COIN_MULTIPLIER_LEVEL
		"coin_base": return MAX_COIN_BASE_LEVEL
		"building_drop_speed": return MAX_BUILDING_DROP_SPEED_LEVEL
		"crit_chance": return MAX_CRIT_CHANCE_LEVEL
		"crit_mult": return MAX_CRIT_MULT_LEVEL
		"chain": return MAX_CHAIN_LEVEL
		"scatter": return MAX_SCATTER_LEVEL
		"bomb_launcher": return MAX_LAUNCHER_COUNT_LEVEL
		"bomb_damage": return MAX_BOMB_DAMAGE_LEVEL
		"bomb_radius": return MAX_BOMB_RADIUS_LEVEL
		"bomb_rate": return MAX_LAUNCHER_RATE_LEVEL
		_: return -1


## 读取某节点当前等级（各 num 字段来自上方升级方法，集中走一个入口便于面板统一查询）。
func _get_node_level(nid: String) -> int:
	match nid:
		"hammer_speed": return _hammer_speed_level
		"hammer_damage": return _hammer_damage_level
		"hammer_range": return _hammer_range_level
		"coin_multiplier": return _coin_multiplier_level
		"coin_base": return _coin_base_level
		"building_drop_speed": return _building_drop_speed_level
		"bomb_launcher": return _bomb_launcher_level
		"bomb_damage": return _bomb_damage_level
		"bomb_radius": return _bomb_radius_level
		"bomb_rate": return _bomb_rate_level
		"crit_chance": return _crit_chance_level
		"crit_mult": return _crit_mult_level
		"chain": return _chain_level
		"scatter": return _scatter_level
	return 0


## 单局技能树节点状态（面板统一出口）。
## 返回：{level, max_level, state, reason, mechanic_gate}
## state ∈ "locked" | "maxed" | "lit" | "available"
func get_node_state(nid: String) -> Dictionary:
	var max_lv := get_node_max_level(nid)
	var lv := _get_node_level(nid)
	var gate: String = NODE_MECHANIC_GATE.get(nid, "")
	var reasons: Array[String] = []
	if gate != "" and not ReincarnationManager.is_mechanic_unlocked(gate):
		reasons.append("转生 ≥ %d 次解锁" % int(MECH_GATE_THRESHOLD.get(gate, 1)))
	for pre in NODE_PRE_REQS.get(nid, []):
		if _get_node_level(pre.node) < int(pre.lvl):
			reasons.append("先解锁「%s」Lv.%d" % [NODE_TITLES.get(pre.node, pre.node), int(pre.lvl)])
	if not reasons.is_empty():
		return _make_node_state(nid, "locked", reasons, gate, lv, max_lv)
	if max_lv >= 0 and lv >= max_lv:
		return _make_node_state(nid, "maxed", [], gate, lv, max_lv)
	if lv > 0:
		return _make_node_state(nid, "lit", [], gate, lv, max_lv)
	return _make_node_state(nid, "available", [], gate, lv, max_lv)


func _make_node_state(nid: String, state: String, reasons: Array[String], gate: String, lv: int, max_lv: int) -> Dictionary:
	return {
		"level": lv, "max_level": max_lv, "state": state,
		"reason": "；".join(reasons), "mechanic_gate": gate,
	}


# 费用公式：BASE_COST × COST_GROWTH^level
func _cost_for_level(level: int) -> int:
	return roundi(BASE_COST * pow(COST_GROWTH, level))
