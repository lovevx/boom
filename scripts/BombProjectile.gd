extends Area2D
## 飞行中的炸弹（游戏世界对象）。
## 用 _physics_process 物理模拟抛物线（velocity + 自定义 gravity），不用 Tween 模拟位置。
## 碰到方块/地面/墙体即爆炸：对半径内方块施加"距中心越远伤害越低"的范围伤害，
## 复用现有 DamageNumber / HealthBar / 破碎特效 / 金币产出。

signal exploded   # 炮弹爆炸时发出（供新手引导监听首轮轰炸）

var bomb_gravity: float = 680.0       # 自定义重力（px/s²），由发射器下发
var damage: float = 3.0               # 基础爆炸伤害（随"从1起步"缩档：原 30；实际由发射器按升级表覆盖）
var radius: float = 80.0              # 爆炸半径
var origin_launcher: Node2D = null   # 发射它的炮台（避免刚出生撞到自己）

const MAX_LIFE := 6.0                # 超过该时长自动爆炸（防卡死）
const EXPIRE_Y := 1040.0             # 落出屏幕下界自动爆炸
const CHAIN_RADIUS := 90.0           # 连锁伤害（机制升级）的追加半径：约覆盖上下各 1 列
const _DN_SCENE := preload("res://scenes/DamageNumber.tscn")
const _DUST_FX := preload("res://scripts/DustFx.gd")   # 尘土 GIF 特效（爆炸扬尘）

# ---- 炮弹美术：一颗圆润实心炮弹（蓝灰球体）----
const BOMB_ART := preload("res://assets/presentation/icons/bomb.png")
const BOMB_ART_SIZE := 24.0       # 素材边长（px）
const BOMB_SIZE := 26.0            # 炮弹在游戏中的世界边长（px，与原 26px 程序球一致）

var _velocity := Vector2.ZERO
var _life := 0.0
var _exploded := false
var _spin_speed := 0.0
var _base_scale := 1.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shadow: Sprite2D = $Shadow
@onready var _ground_y: float = _resolve_ground_y()


# 由发射器调用：设置初速度后入树。
func set_initial_velocity(v: Vector2) -> void:
	_velocity = v


func _ready() -> void:
	add_to_group(&"in_game_entity")   # 归入"场上临时实体"组，重置时统一清理
	_sprite.texture = BOMB_ART
	_shadow.texture = _make_shadow_texture()
	_spin_speed = randf_range(-7.0, 7.0)
	_base_scale = randf_range(0.9, 1.05) * (BOMB_SIZE / BOMB_ART_SIZE)
	_sprite.scale = Vector2(_base_scale, _base_scale)   # 立即生效，避免首帧以默认 scale=1 渲染出巨大炮弹
	body_entered.connect(_on_body_entered)


func _make_shadow_texture() -> Texture2D:
	var t := GradientTexture2D.new()
	t.width = 28
	t.height = 28
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(14, 14)
	t.fill_to = Vector2(12, 12)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0.30), Color(0, 0, 0, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	t.gradient = g
	return t


func _resolve_ground_y() -> float:
	# 地面顶世界 y（Ground StaticBody2D 顶面，Main 布局固定值）
	return 1000.0


func _physics_process(delta: float) -> void:
	_velocity.y += bomb_gravity * delta
	position += _velocity * delta
	_sprite.rotation += _spin_speed * delta
	_sprite.scale = Vector2(_base_scale, _base_scale)
	_life += delta
	_update_shadow()

	if _life >= MAX_LIFE:
		_explode()
		return
	var g := global_position
	if g.y > EXPIRE_Y or g.x > 2000.0 or g.x < -60.0:
		_explode()


# 地面投影随高度变化：越高越小越淡，落地附近明显。
func _update_shadow() -> void:
	var h := clampf(_ground_y - global_position.y, 0.0, 600.0)
	var k := clampf(1.0 - h / 600.0, 0.15, 1.0)
	_shadow.scale = Vector2(k, k)
	_shadow.modulate.a = klamp(k)


func klamp(x: float) -> float:
	return clampf(x, 0.0, 1.0)


# 碰到物理体：方块或地面/墙体都触发爆炸。
func _on_body_entered(body: Node) -> void:
	if body == origin_launcher:
		return
	if body is BuildingBlock or body is RigidBody2D or body is StaticBody2D:
		_explode()


# 爆炸：视觉特效 + 震屏 + 对半径内方块造成范围衰减伤害。
func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	exploded.emit()
	SoundManager.play("explosion")
	_play_explosion_fx()
	_spawn_explosion_dust()   # 尘土 GIF：爆炸点扬尘
	GameFeel.impact(3)   # 炸弹是强事件：爆炸自带大震屏 + 短慢动作（不走 BuildingSetup 链式窗口计数）
	_damage_blocks()
	queue_free()


# 尘土 GIF：爆炸点喷一团扬尘。爆炸是单发强事件，force=true 绕过节流保证必播。
func _spawn_explosion_dust() -> void:
	if get_tree() == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fx := _DUST_FX.new()
	fx.setup(global_position, _DUST_FX.pick_dust(_DUST_FX.EXPLOSION_DUST), 1.0, true)
	scene.add_child(fx)


# 用一个大圆缩放 + 淡出表现爆炸光球（与 Bomb.gd 一致的手法）。
func _play_explosion_fx() -> void:
	var fx := preload("res://scripts/BlastFx.gd").new()
	fx.position = global_position
	fx.blast_radius = radius
	get_tree().current_scene.add_child(fx)


func _circle_points(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	const SEG := 32
	for i in range(SEG + 1):
		var a := TAU * float(i) / float(SEG)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


# 对半径内所有方块：距离衰减伤害 + 受击抖动 + 伤害数字。伤害倍率与破坏/金币复用现有链路。
func _damage_blocks() -> void:
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, global_position)
	q.collide_with_bodies = true
	var base_dmg: float = damage
	var seen := {}
	var destroyed_pos: Array[Vector2] = []   # 本次被击碎的方块位置（供连锁伤害追加）
	for hit in space.intersect_shape(q, 512):
		var hit_body: Object = hit.get("collider")
		if not (hit_body is BuildingBlock) or seen.has(hit_body):
			continue
		if not is_instance_valid(hit_body):
			continue
		seen[hit_body] = true
		var bb := hit_body as BuildingBlock
		var dist := global_position.distance_to(bb.global_position)
		var falloff := clampf(1.0 - dist / maxf(radius, 0.001), 0.3, 1.0)
		var dmg := base_dmg * falloff
		var lethal: bool = (bb.hp - dmg) <= 0.0
		var spawn_pos: Vector2 = bb.global_position + Vector2(randf_range(-15.0, 15.0), 0.0)
		bb.register_hit_origin(global_position)   # 破碎以爆炸点为中心
		var dir := (bb.global_position - global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		bb.launch(dir, 400.0)          # 受击抖动（保持静态支撑）
		bb.take_damage(dmg)            # 扣除生命，<=0 则碎裂
		if lethal:
			destroyed_pos.append(bb.global_position)
		_spawn_damage_number(spawn_pos, dmg, bb.max_hp, lethal)
	# 连锁伤害（机制升级）：被击碎的方块对周围存留方块追加一次范围加伤，可连锁再碎。
	if UpgradeManager.chain_damage > 0.0:
		var chain_dmg := base_dmg * UpgradeManager.chain_damage
		for center in destroyed_pos:
			_apply_chain(chain_dmg, center)


# 连锁伤害追加：以一碎块位置为圆心，对半径内"仍存活"的方块追加伤害。
func _apply_chain(dmg: float, center: Vector2) -> void:
	if not is_instance_valid(self):
		return
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = CHAIN_RADIUS
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, center)
	q.collide_with_bodies = true
	for hit in space.intersect_shape(q, 512):
		var body: Object = hit.get("collider")
		if not (body is BuildingBlock):
			continue
		var bb := body as BuildingBlock
		if not is_instance_valid(bb) or bb.hp <= 0.0:
			continue
		var lethal: bool = (bb.hp - dmg) <= 0.0
		var spawn_pos: Vector2 = bb.global_position + Vector2(randf_range(-15.0, 15.0), 0.0)
		bb.register_hit_origin(center)
		var dir := (bb.global_position - center).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		bb.launch(dir, 300.0)
		bb.take_damage(dmg)
		_spawn_damage_number(spawn_pos, dmg, bb.max_hp, lethal)


# 在方块上方生成浮动伤害数字（加入专用层）。
func _spawn_damage_number(pos: Vector2, dmg: float, max_hp: float, lethal: bool) -> void:
	var dn: Node2D = _DN_SCENE.instantiate()
	dn.damage = dmg
	dn.max_hp = max_hp
	dn.is_lethal = lethal
	dn.position = pos
	get_tree().current_scene.get_node("DamageNumberLayer").add_child(dn)