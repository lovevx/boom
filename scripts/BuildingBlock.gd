extends RigidBody2D
## 建筑方块（白盒用）。
## 默认冻结（freeze）作为静态支撑。当下方支撑被摧毁、失去支撑时，
## 由所属列（BuildingSetup）算出它的唯一目标槽位，然后"加速下落"到该格并定格（确定性槽位下落）。
## 这样从根上保证不散、不转、不穿透、不重叠、不断层，同时保留"越掉越快"的下坠手感。

class_name BuildingBlock

signal shattered   # 方块被彻底砸碎时发出，供所属列计数（BuildingSetup 监听）

const SLOT := 40.0   # 网格槽位边长（与 BuildingSetup.BLOCK_SIZE 一致）

const _PIXEL_EXPLOSION := preload("res://scripts/PixelExplosion.gd")   # 碎裂特效（烟雾+碎屑+冲击环）
const _DUST_FX := preload("res://scripts/DustFx.gd")   # 尘土 GIF 特效（塌落/落定扬尘）

@export var hp: float = 100.0   # 方块生命值，被爆炸伤害扣减
var max_hp: float = 100.0       # 方块最大生命值（供伤害等级判断 / 血条比例，由生成方按类型注入）
@export var gold_value: int = 10   # 该方块被毁后产出的金币数
var debris_color: Color = Color(0.8, 0.8, 0.8)   # 破碎碎屑颜色（由生成方按方块配色）

var col: int = 0            # 所属列（0..COLS-1）
var is_floor: bool = false  # 是否为楼板层方块（补层时据此取反，维持隔层楼板感）
var building: Node2D        # 所属 Building 节点，落定后上报以触发补层
var level: int = 0          # 当前网格层级（0=顶层），local y = level * SLOT

var crack_sprite: Sprite2D        # 程序化裂纹覆盖层（材质之上），血量下降驱动其 uniform
var debris_texture: Texture2D     # 该方块材质的贴图来源，碎屑按它采样（无贴图则回退纯色）
var is_glass := false             # 是否为玻璃方块，碎屑相应半透明（玻璃碎成亮茬）

var _falling := false        # 是否正处于"下落动画"中
var _pending_level := -1     # 下落动画中的目标层级（供列压实/补层时查询有效槽位）
var _fall_tween: Tween       # 下落动画句柄（可在重叠下移时被替换）

var visual_layer: Node2D     # P2：视觉层容器（材质 sprite + 裂纹）。人力旋转/摇摆只作用于此层，物理槽位不受影响
var _rot_tween: Tween        # P2：下落视觉摇摆动画句柄（独立于 _fall_tween，不同属性并行不互相覆盖）

var _hit_tween: Tween       # 受击抖动动画（仅静止支撑中的方块用）
var _shattered := false     # 同帧多次命中只允许一次碎裂/奖励/列更新
var _shatter_origin: Vector2 = Vector2.ZERO   # 最近一次命中时的来源点，破碎以它为中心


# 被命中时调用：仅在静止支撑时沿命中方向瞬时抖动，下落中则忽略。
func launch(direction: Vector2, _impulse_force: float) -> void:
	if _falling or _shattered:
		return
	var dir := direction
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	# 受击只移动外观，避免回弹与槽位下落同时写刚体位置、把已落定的块拉回旧格。
	if is_instance_valid(visual_layer):
		visual_layer.position = Vector2.ZERO
		_hit_tween = create_tween()
		_hit_tween.tween_property(visual_layer, "position", dir.normalized() * 7.0, 0.04) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hit_tween.tween_property(visual_layer, "position", Vector2.ZERO, 0.09)
	# 档1 受击视觉（白闪 + 即时裂纹）：仅"存活且非下落中"触发。
	# 本次命中若致死（hp<=0，take_damage 已在前面扣过）则跳过档1，交给档2 的碎裂反馈。
	if hp > 0.0:
		_spawn_hit_feedback()


# 受到伤害时记录命中来源点(如鼠标点击位置)，供破碎作为四散中心。
# 同时把受击点换算成方块局部 UV，喂给裂纹覆盖层作为"主裂缝放射原点"。
func register_hit_origin(origin: Vector2) -> void:
	_shatter_origin = origin
	var new_uv := Vector2(0.5, 0.5)   # 兜底：中心
	if is_instance_valid(crack_sprite):
		# 裂纹覆盖层为方块(0,0)子节点：其局部坐标即方块局部坐标（-20~20），映射到 0~1
		var local := crack_sprite.to_local(origin)
		new_uv = Vector2(
			clampf((local.x / SLOT) + 0.5, 0.0, 1.0),
			clampf((local.y / SLOT) + 0.5, 0.0, 1.0)
		)
	_crack_uv = new_uv
	update_crack()   # 受击点变化也即时刷新裂隙放射方向


var _crack_uv := Vector2(0.5, 0.5)   # 主裂缝放射原点（方块局部 UV，0~1）


# 由生成方把裂纹覆盖层绑定到本块，并按当前血量初始化 uniform（满血 crack=0，无裂纹）。
func setup_crack_sprite(sprite: Sprite2D) -> void:
	crack_sprite = sprite
	update_crack()


# 依据当前血量更新裂纹覆盖层：crack = 1 - hp/max_hp（满血 0 无裂纹，越靠近破碎越密越深）。
# 一并下发主裂缝放射原点(origin)。玻璃/金属/石材共用同一套 shader，只改 uniform；
# 受击微动时作为方块子节点自然跟随。
func update_crack() -> void:
	if not is_instance_valid(crack_sprite):
		return
	var mat := crack_sprite.material as ShaderMaterial
	if mat == null:
		return
	var val := 1.0 - clampf(hp / maxf(max_hp, 0.0001), 0.0, 1.0)
	mat.set_shader_parameter("crack", val)
	mat.set_shader_parameter("origin", _crack_uv)


# ==================== 档1：受击视觉（白闪 + 即时裂纹） ====================
# 仅存活方块命中时调用；两块特效都挂到 current_scene（不在方块下，方块碎裂/回弹不会连累它们），
# 并归入 in_game_entity 组，重置统一清理。Tween 一律绑定到特效节点自身，避免被销毁带跑动画。
func _spawn_hit_feedback() -> void:
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	_spawn_white_flash(scene)
	_spawn_hit_cracks(scene)


# 白闪：一块盖住方块的白色 Polygon，快速淡出。
func _spawn_white_flash(scene: Node) -> void:
	var flash := Polygon2D.new()
	if not Presentation.admit(flash, "hit"):
		flash.free()
		return
	flash.polygon = PackedVector2Array([
		Vector2(-SLOT / 2.0, -SLOT / 2.0), Vector2(SLOT / 2.0, -SLOT / 2.0),
		Vector2(SLOT / 2.0, SLOT / 2.0), Vector2(-SLOT / 2.0, SLOT / 2.0),
	])
	flash.position = global_position
	flash.color = Color(1.0, 0.95, 0.78, 0.45)
	flash.z_index = 40
	flash.add_to_group(&"in_game_entity")
	scene.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(flash.queue_free)


# 即时目录裂纹：以命中点为起点，向方块内部生成 2~3 道短线，短促生长并淡出。
# 用 Line2D 以命中点为原点向外扩散（scale 由小放大即"由命中点向内部蔓延"），
# 命中点即 _shatter_origin（launch 前已由调用方 register_hit_origin 写入）。
func _spawn_hit_cracks(scene: Node) -> void:
	var root := Node2D.new()
	if not Presentation.admit(root, "hit"):
		root.free()
		return
	root.position = _shatter_origin   # 裂纹以命中点为根
	root.z_index = 40
	root.add_to_group(&"in_game_entity")
	# 从命中点指向方块中心的方向（受击方向的反向 = 进入方块内）
	var inward := (global_position - _shatter_origin)
	if inward.length() < 0.001:
		inward = Vector2.RIGHT
	var inward_ang := inward.angle()
	for i in range(randi_range(2, 3)):
		var line := Line2D.new()
		line.width = 2.0
		line.antialiased = false
		line.default_color = Color(0.12, 0.12, 0.12, 0.85)
		var a := inward_ang + randf_range(-0.9, 0.9)
		var len := randf_range(SLOT * 0.22, SLOT * 0.5)
		var end := Vector2.from_angle(a) * len
		line.points = PackedVector2Array([Vector2.ZERO, end])
		root.add_child(line)
	scene.add_child(root)
	root.scale = Vector2(0.15, 0.15)
	var tween := root.create_tween()
	tween.tween_property(root, "scale", Vector2.ONE, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(root, "modulate:a", 0.0, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(root.queue_free)


# ==================== P2：落地扬尘 + 微震 ====================
# 方块真正落到新格的瞬间，按"落定批次"聚合扬尘：一小段时间窗内落定的方块合并成
# 一团尘土，横向尺寸按本批接触范围（跨几列）放大，而非每块各放一团。
# 不播向左右两侧扩散的粒子，只播底部横版尘土（dust5）；单块落定退化为基准大小。
func _spawn_landing_dust() -> void:
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var now := Time.get_ticks_msec()
	var b := _landing_batch
	var fresh: bool = not b["dirty"] or now - int(b["win_ms"]) > LANDING_BATCH_WINDOW_MS
	if fresh:
		b["win_ms"] = now
		b["min_x"] = global_position.x
		b["max_x"] = global_position.x
		b["dirty"] = true
		_defer_batch_dust(scene)   # 批次起点：延迟一个窗口，等同一批其他落定块并入后再统一放
	else:
		b["min_x"] = minf(b["min_x"], global_position.x)
		b["max_x"] = maxf(b["max_x"], global_position.x)
	b["y"] = global_position.y


# 落定批次聚合状态（整场共享静态：跨节点累计同一批落定的横向范围，凑成一团尘土）。
static var _landing_batch := {
	"win_ms": -1000000,   # 批次窗口起点（ms）
	"min_x": 0.0,         # 本批最左落点 x
	"max_x": 0.0,         # 本批最右落点 x
	"y": 0.0,             # 落点 y（同一批基本同层，取最新）
	"dirty": false,       # 是否有待发射的聚合尘土
}
const LANDING_BATCH_WINDOW_MS := 120   # 聚合窗口：窗口内有新落定则批次延续

# 批次起点：延迟一个窗口后检查——期间没有新落定（窗口未被刷新）才发射这团聚合尘土。
static func _defer_batch_dust(scene: Node) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	scene.get_tree().create_timer(LANDING_BATCH_WINDOW_MS / 1000.0).timeout.connect(func() -> void:
		if not _landing_batch["dirty"]:
			return
		var now := Time.get_ticks_msec()
		if now - int(_landing_batch["win_ms"]) > LANDING_BATCH_WINDOW_MS:
			_landing_batch["dirty"] = false
			_emit_batch_dust(scene)
		else:
			_defer_batch_dust(scene)   # 窗口内又有新落定：批次延续，再等一个窗口
	)


# 发射聚合尘土：中心 = 本批落点横向中点，缩放按接触范围（跨列数）放大。
# 尘土单帧约 282px 宽，基准 0.5（≈141px ≈ 3.5 格）；接触范围每多 1 列(40px)放大一档。
static func _emit_batch_dust(scene: Node) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	var b := _landing_batch
	var span := float(b["max_x"]) - float(b["min_x"])
	var center := Vector2((float(b["min_x"]) + float(b["max_x"])) * 0.5, float(b["y"]))
	var s := clampf(0.5 + span / (SLOT * 3.0), 0.5, 2.5)
	var fx := _DUST_FX.new()
	fx.setup(center, _DUST_FX.pick_dust(_DUST_FX.COLLAPSE_DUST), s, false)
	scene.add_child(fx)


# 受到来自 BOMB 的爆炸伤害。
func take_damage(damage: float) -> void:
	if _shattered:
		return
	hp -= damage
	if hp <= 0.0:
		_shatter()
		return
	_notify_healthbar()   # 未碎裂才更新血条（碎裂后方块/血条销毁）
	update_crack()        # 未碎裂：血量下降 → 裂纹覆盖层越密越深


# 失去支撑 → 下移到目标层级（target_level > level）。
# P2 改为"先蓄后发"两段式时间曲线：
#   蓄力段：占 ~22%，位置仅极轻微下压 3px（先缓后慢的"绷一下"）；爆发段：剩余用 CUBIC/EASE_IN，
#   距离越远总时长越长，末端加速感越猛。下落速度仍受"建筑下落速度"升级影响（越大越快）。
# 仍保持单条 _fall_tween 链以沿用现有重叠下移/打断逻辑；落定后定格为目标静态支撑。
func drop_to(target_level: int) -> void:
	if target_level <= level:
		return
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	_hit_tween = null
	if is_instance_valid(visual_layer):
		visual_layer.position = Vector2.ZERO
	# 重叠下移：若上一次下落还没播完，则从当前位置接着落到新目标，不打断。
	if _fall_tween and _fall_tween.is_valid():
		_fall_tween.kill()
	_pending_level = target_level   # 记录目标槽位，供压实/补层查询有效位置
	var from_y: float = position.y
	var to_y := float(target_level) * SLOT
	var dist := absf(to_y - from_y)
	var speed: float = 520.0 * maxf(UpgradeManager.building_drop_speed, 0.1)
	var total := clampf(dist / speed, 0.05, 0.8)

	# —— 先蓄后发：位置极轻下压(蓄力) → 猛地加速砸下(爆发) ——
	var hold_frac := 0.22                    # 蓄力占总时长比例（克制，避免拖死挂机节奏）
	var press := 3.0                         # 蓄力段轻微下压距离 px
	_falling = true
	_fall_tween = create_tween()
	_fall_tween.tween_property(self, "position:y", from_y + press, total * hold_frac) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall_tween.tween_property(self, "position:y", to_y, total * (1.0 - hold_frac)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_fall_tween.tween_callback(_finalize_level.bind(target_level))

	# —— 下落带姿态：视觉层极轻微歪斜后归正，落定精确回格 ——
	_start_fall_sway(total)


# P2：下落姿态。整体时长内视觉层先歪向一个随机微调角，落定前摆回 0°。
# 只旋转 visual_layer（外观），block.position.y / freeze / 碰撞完全不受影响，落定量级确定不变。
func _start_fall_sway(total: float) -> void:
	if Presentation.reduced_motion:
		if is_instance_valid(visual_layer):
			visual_layer.rotation = 0.0
		return
	if _rot_tween and _rot_tween.is_valid():
		_rot_tween.kill()
	if visual_layer == null or not is_instance_valid(visual_layer):
		return
	visual_layer.rotation = 0.0
	var tilt := deg_to_rad(randf_range(8.0, 18.0)) * (-1.0 if randf() < 0.5 else 1.0)
	var peak := total * 0.5
	_rot_tween = create_tween()   # 绑定到本块，target 是 visual_layer，与 _fall_tween(作用 position) 并行独立
	_rot_tween.tween_property(visual_layer, "rotation", tilt, peak) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rot_tween.tween_property(visual_layer, "rotation", 0.0, peak) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# 定格在目标层级：校正网格、重新作为静态支撑，并通知所属列尝试补层。
func _finalize_level(target_level: int) -> void:
	_falling = false
	_fall_tween = null
	_pending_level = -1
	level = target_level
	position.y = float(target_level) * SLOT   # 落定精确回网格槽位（红线：位置始终由槽位决定，不斜插/不悬浮/不重叠）
	# 落定归正：视觉层摆回 0°，并清理可能残留的摇摆动画
	if visual_layer != null and is_instance_valid(visual_layer):
		visual_layer.rotation = 0.0
	if _rot_tween and _rot_tween.is_valid():
		_rot_tween.kill()
	_rot_tween = null
	_spawn_landing_dust()   # P2：落定迸尘（仅"真正落到新格的一批"才调用到本逻辑）
	GameFeel.micro_shake()  # P2：低强度微震（GameFeel 内做同帧去重，连锁多块只发一次）
	if building != null and is_instance_valid(building) and building.has_method("_on_block_settled"):
		building._on_block_settled(col)


# 对外查询是否正处于"下落动画"中（供 BuildingSetup 判定补层时机）。
func is_falling() -> bool:
	return _falling


# 当前占据的有效槽位：下落到一半时按目标槽位计，定格后按定格槽位计。
# 让列压实/补层在方块仍在下落、level 未刷新时也能读到正确位置。
func effective_level() -> int:
	if _falling and _pending_level >= 0:
		return _pending_level
	return level


# 通知血条同步当前血量（追加逻辑：不改变原有血量/碎裂行为）。
func _notify_healthbar() -> void:
	var hb := get_node_or_null("HealthBar")
	if hb != null and hb.has_method("notify_damage"):
		hb.notify_damage(hp)


# 碎裂（破碎效果）：在命中点播放 PixelExplosion（烟雾+材质碎屑+冲击环），然后移除自身。
func _shatter() -> void:
	if _shattered:
		return
	_shattered = true
	shattered.emit()   # 通知所属列：本块已被摧毁，其上支撑需级联下落
	SoundManager.play("shatter_glass" if is_glass else ("shatter_metal" if debris_texture and "steel" in debris_texture.resource_path else "shatter_stone"))   # 玻璃块放玻璃碎声，石材/金属/其余放石头碎声
	GoldManager.register_destroyed()   # 每毁一块 → 累计摧毁数 +1（驱动材质挡位）
	_spawn_pixel_explosion()   # 用 PixelExplosion 提供碎裂特效（材质碎屑四散）
	_spawn_gold()
	queue_free()


# 碎裂特效：实例化 PixelExplosion。每块碎裂都播放；为应对连锁塌塔批碎，把数量调低，避免一次爆量。
func _spawn_pixel_explosion() -> void:
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var boom = _PIXEL_EXPLOSION.new()
	boom.stone_texture = debris_texture   # 碎屑沿用该方块材质的贴图（粒子层用其本色）
	boom.stone_amount = 12                # 调低碎屑数：连锁批碎时每块一个而不爆量
	boom.position = _shatter_origin       # 先设起点再入树，explode 里各层以其为爆点
	scene.add_child(boom)
	boom.explode()


# 产出金币：基础 = 方块基础价格 + 转生"击破金币"永久加值 + 单局技能树"基础金币"加值，再 × 金币倍率（含转生"金币之心"乘和）。
func _spawn_gold() -> void:
	var base: int = gold_value + ReincarnationManager.get_coin_per_kill_bonus() + UpgradeManager.coin_base
	if base <= 0:
		return
	var amount: int = roundi(base * UpgradeManager.coin_multiplier)
	GoldManager.add_gold(amount)
	SoundManager.play("coin")
	Presentation.gold_popup(_shatter_origin, amount)
	_spawn_coin_flight(amount)   # 额外生成数枚金币飞向左上角金币UI


# 砸碎后生成数枚金币，从破坏点沿抛物线飞向左上角的金币UI徽章，边飞边缩小。
# 金币数量随产出的大小浮动但限制在合适区间，避免超大增量刷屏。
func _spawn_coin_flight(amount: int) -> void:
	if amount <= 0 or Presentation.reduced_motion:
		return
	# 目标：金币UI徽章中心（GoldHUD 是 CanvasLayer，其徽章屏幕坐标≈世界坐标）
	var hud: CanvasLayer = get_tree().current_scene.get_node_or_null("GoldHUD")
	if hud == null or not hud.has_node("GoldBar/CoinHBox"):
		return
	var bar: Control = hud.get_node("GoldBar/CoinHBox")
	var target: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * (bar.get_global_transform_with_canvas().origin + Vector2(32, 32))
	var coin_scene: PackedScene = preload("res://scenes/CoinFly.tscn")
	var coin_count := clampi(amount, 1, 3)
	for i in range(coin_count):
		var coin: Node2D = coin_scene.instantiate()
		# 出生点在破坏点周围散布，落点小幅散射到徽章附近，制造凌乱飞舞感
		coin.position = _shatter_origin + Vector2(randf_range(-18, 18), randf_range(-18, 18))
		coin.end_pos = target + Vector2(randf_range(-26, 26), randf_range(-14, 14))
		coin.delay = i * 0.05 + randf_range(0.0, 0.04)   # 错峰起飞
		coin.spread = randf_range(0.4, 1.7)              # 弧线高低差异
		get_tree().current_scene.add_child(coin)


# 边界清理：飞出屏幕范围的物理对象自动销毁（确定性下落一般不会触发，仅兜底）。
func _process(_delta: float) -> void:
	var g := global_position
	if g.y > 1200.0 or g.x < -100.0 or g.x > 2020.0:
		queue_free()
