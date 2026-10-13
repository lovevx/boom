extends Node2D
## 初始破坏工具：锤子（白盒版）。
## 锤头用圆形图形占位（后续替换为锤子素材）。鼠标左键点击建筑方块时挥砸：

signal swung   # 每次挥砸发出（供新手引导监听首次挥击）
## 扣血、把方块打飞、触发震屏。多次挥砸可把方块砸碎为碎块。
## 支持范围升级：命中点击处一定半径内的所有方块（UpgradeManager.hammer_range）。
## 支持全自动升级：解锁后无需点击，冷却结束自动在鼠标指向处连锤。

@export var radius: float = 24.0            # 锤头圆形占位的半径
@export var smash_impulse: float = 180.0    # 挥砸把方块打飞的力度
@export var attack_speed: float = 2.0       # 每秒挥砸次数基础值（2.0 = 每 0.5 秒一次，节奏CD甜点区，见 Numeric_Balance）
const MIN_COOLDOWN := 0.30                  # 点击CD下限（秒）：CD低于此值则分层节奏被"手速碾压"破坏，作为守卫

var _swinging := false   # 是否正在挥砸动画中
var _cd_left := 0.0      # 冷却剩余时间（秒）
var _combo_stacks := 0
var _since_hit := 99.0
var _effective_swings := 0

const _DN_SCENE := preload("res://scenes/DamageNumber.tscn")
@onready var _dn_layer: Node2D = get_tree().current_scene.get_node("DamageNumberLayer")


func _ready() -> void:
	global_position = _offset_from_mouse()
	GoldManager.run_reset.connect(func() -> void:
		_combo_stacks = 0
		_effective_swings = 0
		_since_hit = 99.0
		_cd_left = 0.0)


func _process(delta: float) -> void:
	_since_hit += delta
	if _since_hit > UpgradeManager.combo_window + ReincarnationManager.get_specialization("combo_memory"):
		_combo_stacks = 0
	# 非挥砸状态下锤头跟随鼠标（带一点偏移更像手持）
	if not _swinging:
		global_position = _offset_from_mouse()
	if _cd_left > 0.0:
		_cd_left = maxf(_cd_left - delta, 0.0)
	# 全自动锤子：冷却结束且未在挥砸动画中时，自动瞄准挥砸建筑底层
	if UpgradeManager.auto_hammer and _cd_left <= 0.0 and not _swinging:
		_maybe_auto_smash()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_maybe_smash(get_global_mouse_position())


# 攻击速度限制：冷却期间忽略挥砸输入，其余进入挥砸。
# 实际攻击间隔 = 基础间隔 / 攻速倍率，且不小于 MIN_COOLDOWN 下限。
func _maybe_smash(at: Vector2) -> void:
	if _cd_left > 0.0:
		return   # 冷却中，本次点击不生效
	_cd_left = maxf(1.0 / maxf(attack_speed * UpgradeManager.hammer_speed, 0.001), MIN_COOLDOWN)
	_smash(at)


# 鼠标偏移：锤头略微偏向右上，模拟手持。
func _offset_from_mouse() -> Vector2:
	return get_global_mouse_position() + Vector2(18.0, -18.0)


# 自动挥砸：全自动模式下连续在鼠标指向处挥砸（跟随鼠标瞄准，带范围时一次砸中一片）。
func _maybe_auto_smash() -> void:
	_cd_left = maxf(1.0 / maxf(attack_speed * UpgradeManager.hammer_speed, 0.001), MIN_COOLDOWN)
	var building := get_tree().current_scene.get_node_or_null("Building")
	if building == null:
		return
	var target: RigidBody2D = building.get_lowest_alive_block()
	if target != null:
		_smash(target.global_position)


# 挥砸：命中点击处一定半径内所有方块，扣血打飞，并播放挥击动画。
# 实际伤害 = 基础伤害 × 伤害倍率；范围 = UpgradeManager.hammer_range。
func _smash(at: Vector2) -> void:
	var blocks := _find_blocks(at)
	if blocks.is_empty():
		_combo_stacks = 0
	else:
		_effective_swings += 1
		_since_hit = 0.0
	var combo_mult := 1.0 + _combo_stacks * UpgradeManager.demo_value("combo")
	var power_hit := not blocks.is_empty() and UpgradeManager.demo_value("power_strike") > 1.0 and _effective_swings % UpgradeManager.power_strike_every == 0
	if power_hit:
		var power_radius := UpgradeManager.hammer_range + UpgradeManager.power_strike_radius + ReincarnationManager.get_specialization("wave_training")
		blocks = _find_blocks(at, power_radius)
		var fx := preload("res://scripts/BlastFx.gd").new()
		fx.position = at
		fx.blast_radius = power_radius
		fx.modulate = Color(1.0, 0.65, 0.25)
		get_tree().current_scene.add_child(fx)
	# 基础伤害 = 1.0 + 转生"基础伤害"永久加值；再乘单局伤害倍率（含转生"破坏之力"乘和）。
	var dmg: float = ReincarnationManager.get_hammer_base_damage() * UpgradeManager.hammer_damage
	dmg *= combo_mult
	if power_hit:
		dmg *= UpgradeManager.demo_value("power_strike")
	var lethal_hits := 0
	for block in blocks:
		var dir := (block.global_position - at).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		# 暴击判定（机制升级）：命中时按暴击率判定，触发则 × 暴击伤害倍率。
		var hit_dmg := dmg
		var threshold := UpgradeManager.execute_threshold + ReincarnationManager.get_specialization("execute_training")
		if block.hp <= block.max_hp * threshold:
			hit_dmg *= 1.0 + UpgradeManager.demo_value("execute")
		hit_dmg *= UpgradeManager.get_falling_multiplier(block.is_falling())
		if UpgradeManager.crit_chance > 0.0 and randf() < UpgradeManager.crit_chance:
			hit_dmg *= UpgradeManager.crit_multiplier
		# 先判定本次是否会一击摧毁，供伤害数字用"致命一击"样式
		var lethal: bool = (block.hp - hit_dmg) <= 0.0
		if lethal:
			lethal_hits += 1
		var spawn_pos: Vector2 = block.global_position + Vector2(randf_range(-15.0, 15.0), 0.0)
		block.register_hit_origin(at)   # 以点击处作为破碎四散中心
		block.take_damage(hit_dmg)
		block.launch(dir, smash_impulse)
		_spawn_damage_number(spawn_pos, hit_dmg, block.max_hp, lethal)
	if not blocks.is_empty():
		var impact := preload("res://scripts/ImpactFx.gd").new()
		impact.position = at
		impact.power = power_hit
		get_tree().current_scene.add_child(impact)
		_combo_stacks = mini(UpgradeManager.combo_stack_cap, _combo_stacks + 1) if UpgradeManager.demo_value("combo") > 0.0 else 0
		SoundManager.play("hammer_hit")
		# 破坏反馈分档：本轮无任何致死 → 纯受击（档1，轻微顿帧+弱震）；
		# 若有致死则交给 BuildingSetup 的 0.25s 同瞬摧毁窗口判定 档2/档3，避免这里重复拉档。
		if lethal_hits <= 0:
			GameFeel.impact(1)
	swung.emit()
	SoundManager.play("hammer_swing")
	_play_swing(at)


# 在方块上方生成一个浮动伤害数字（加入专用层，不挂到方块下，方块碎裂时不受影响）。
func _spawn_damage_number(pos: Vector2, dmg: float, max_hp: float, lethal: bool) -> void:
	var dn: Node2D = _DN_SCENE.instantiate()
	dn.damage = dmg
	dn.max_hp = max_hp
	dn.is_lethal = lethal
	dn.position = pos
	_dn_layer.add_child(dn)


# 查找命中点上的建筑方块（跳过墙体等其它碰撞体）。
# 范围升级 > 0 时改为查找以命中点为圆心、半径为 hammer_range 的所有方块。
func _find_blocks(at: Vector2, override_radius: float = -1.0) -> Array[BuildingBlock]:
	var result: Array[BuildingBlock] = []
	var space := get_world_2d().direct_space_state
	var range_radius: float = UpgradeManager.hammer_range
	if override_radius >= 0.0:
		range_radius = override_radius
	if range_radius <= 0.0:
		# 未升级范围：仅命中鼠标点击处那一个方块
		var query := PhysicsPointQueryParameters2D.new()
		query.position = at
		query.collide_with_bodies = true
		for hit in space.intersect_point(query):
			var collider: Object = hit.get("collider")
			if collider is BuildingBlock and collider.hp > 0.0 and not result.has(collider):
				result.append(collider)
		return result
	# 范围命中：命中圆内所有方块
	var shape := CircleShape2D.new()
	shape.radius = range_radius
	var shape_query := PhysicsShapeQueryParameters2D.new()
	shape_query.shape = shape
	shape_query.transform = Transform2D(0.0, at)   # 圆查询中心为命中点
	shape_query.collide_with_bodies = true
	for hit in space.intersect_shape(shape_query, 512):
		var collider: Object = hit.get("collider")
		if collider is BuildingBlock and collider.hp > 0.0 and not result.has(collider):
			result.append(collider)
	return result


# 挥砸动画：锤头扑向点击点再缩回。
func _play_swing(at: Vector2) -> void:
	if Presentation.reduced_motion:
		return
	_swinging = true
	global_position = at
	rotation = -0.9
	var tween := create_tween()
	tween.tween_property(self, "rotation", 0.5, 0.1)
	tween.tween_property(self, "rotation", -0.1, 0.1)
	tween.tween_callback(func() -> void:
		_swinging = false
	)


# 圆形锤头占位：填充圆 + 外圈描边 + 内圈高光。
func _draw() -> void:
	_draw_range()
	draw_texture_rect(Presentation.icon("hammer"), Rect2(-28,-32,56,56), false)
	_draw_cooldown_ring()
	if UpgradeManager.demo_value("combo") > 0.0 and _combo_stacks > 0:
		draw_string(ThemeDB.fallback_font, Vector2(-25, 46), "x%d +%d%%" % [_combo_stacks, roundi(_combo_stacks * UpgradeManager.demo_value("combo") * 100)], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.85, 0.3))
	if UpgradeManager.demo_value("power_strike") > 1.0:
		draw_string(ThemeDB.fallback_font, Vector2(-25, 66), "%d / %d" % [_effective_swings % UpgradeManager.power_strike_every, UpgradeManager.power_strike_every], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.65, 0.25))


func _draw_range() -> void:
	var r: float = UpgradeManager.hammer_range
	if r <= 0.0:
		return   # 未升级范围：不显示
	var center := to_local(get_global_mouse_position())
	var segments := 128
	var color := Color(0.95, 0.6, 0.15, 0.55)
	draw_arc(center, r, 0.0, TAU, segments, color, 2.0, true)
	# 中心小十字提示"以此为圆心"
	draw_line(center + Vector2(-6, 0), center + Vector2(6, 0), color, 1.5)
	draw_line(center + Vector2(0, -6), center + Vector2(0, 6), color, 1.5)


# 冷却进度条：锤头外侧一圈弧线，剩余冷却越多弧越完整。
func _draw_cooldown_ring() -> void:
	if _cd_left <= 0.0:
		return
	var dur := maxf(1.0 / maxf(attack_speed * UpgradeManager.hammer_speed, 0.001), MIN_COOLDOWN)
	var frac := clampf(_cd_left / dur, 0.0, 1.0)
	draw_arc(Vector2.ZERO, radius + 6.0, -TAU * 0.25, TAU * (frac - 0.25), 48,
			Color(0.95, 0.6, 0.15, 0.9), 4.0)
