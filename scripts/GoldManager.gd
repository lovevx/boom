extends Node
## 全局金币管理（Autoload 单例）。
## 建筑方块被毁时产出金币并累加到这里；HUD 监听 gold_changed 实时刷新。

signal gold_changed(new_total: int)

var total_gold: int = 0

var lifetime_gold_this_run: int = 0   # 本局累计产出金币（含已花掉的），转生 RP 的收益依据
var destroyed_count: int = 0               # 累计摧毁方块数（驱动材质挡位）

# —— 生涯总统计（跨槽位 / 跨重开，只增不减，供主菜单"生涯统计"面板展示）——
var stats_blocks_destroyed: int = 0   # 生涯累计击破方块数
var stats_gold_earned: int = 0        # 生涯累计获取金币（含已花掉的）


# 读取累计摧毁方块数（用于 BuildingSetup 反查当前材质挡位）。
func get_destroyed_count() -> int:
	return destroyed_count


# 登记一次摧毁：每块方块被彻底摧毁时调用一次（驱动材质挡位），与产出金币同一位置。
func register_destroyed() -> void:
	destroyed_count += 1
	stats_blocks_destroyed += 1


# 增加金币，并广播新的总数供 UI 刷新。
func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	total_gold += amount
	lifetime_gold_this_run += amount
	stats_gold_earned += amount
	gold_changed.emit(total_gold)


# 扣除金币（用于升级消耗）。金币足够则扣除并广播，返回 true；否则不操作返回 false。
func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if total_gold < amount:
		return false
	total_gold -= amount
	gold_changed.emit(total_gold)
	return true


# 重置金币：归零并广播新的总数（供 HUD / 技能树刷新）。用于"重新开始"。
func reset() -> void:
	total_gold = 0
	lifetime_gold_this_run = 0
	destroyed_count = 0
	gold_changed.emit(0)


# 从存档恢复金币状态（读档时调用，覆盖当前内存值）。
func restore_state(gold: int, lifetime: int, destroyed: int) -> void:
	total_gold = maxi(0, gold)
	lifetime_gold_this_run = maxi(0, lifetime)
	destroyed_count = maxi(0, destroyed)
	gold_changed.emit(total_gold)


# 从生涯统计存档恢复全局累计值（只增不减，故仅覆盖到更大值）。
func restore_life_stats(blocks: int, gold: int) -> void:
	stats_blocks_destroyed = blocks
	stats_gold_earned = gold