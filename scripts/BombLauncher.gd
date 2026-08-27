extends StaticBody2D
## 炸弹发射器实体（游戏世界对象，非 UI）。
## 位于建筑两侧地面，朝建筑区域内随机目标发射抛物线炸弹。
## 美术：使用 assets/launcher/ 烘焙好的大炮帧序列（工业水泥搅拌车风格，朝右）。位于建筑右侧的炮台自动镜像朝左。
## 动画不再循环待机：平时静止显示第 IDLE 帧；
## 冷却完毕选定目标后，一次性播放攻击动画，在 FIRE_FRAME_INDEX 对应帧炮口出膛（炮弹沿炮口朝向的轨迹飞出），播放完回到待机帧。
## 伤害/半径/冷却实时读取 UpgradeManager，升级后立即生效。
## 每个炮台独立冷却（Timer 节点），发射时带后坐与炮口闪光。
## 部署（从地下升起）与可见性由 LauncherManager 控制；此处只负责单台发射/冷却。

@export var gravity: float = 680.0   # 抛体重力值（px/s²），下发到炮弹

# 横向瞄准偏好 -1..1：让每台炮台集中在建筑不同的横向区域（左右散开），
# 由 LauncherManager 随机赋予，多台合起来覆盖整栋楼的各个部位。
var aim_zone_x: float = 0.0

const PROJECTILE_SCENE := preload("res://scenes/BombProjectile.tscn")
const BUILDING_X_CENTER_OFFSET := 240.0   # 建筑中心 x 相对 Building 节点原点偏移（6 列 × 40px）
const BUILDING_HALF_W := 240.0            # 目标区水平半宽
const BUILDING_TOP_DY := 40.0              # 目标区顶部相对 Building 原点
const BUILDING_BOTTOM_DY := 820.0          # 目标区底部相对 Building 原点（覆盖到接近楼下地面）
const FIRST_SHOT_DELAY := 0.8             # 刚激活时首次开火的延迟（快速反馈）

# ---- 大炮帧序列（烘焙后 240×240，透明背景）----
const FRAME_PATH := "res://assets/launcher/launcher_%03d.png"
const FRAME_START := 6
const FRAME_END := 38
const SPRITE_SCALE := 0.46                 # 大炮最终缩放（240px → 约 110px 高，与 40px 方块匹配）
const ART_HALF := 120.0                    # 240px 帧的半边长（Sprite 居中，local 以帧中心为原点）
const MUZZLE_XY := Vector2(183.0, 98.0)    # 炮口（弹丸发射口）在某帧内的像素坐标
const FEET_BOTTOM_Y := 239.0               # 大炮底座底部像素行（着地点）
const BUILDING_CENTER_X := 960.0           # 建筑水平中心，用于决定炮台是否镜像朝左
const FEET_WORLD_Y := 1000.0               # 炮台底座着地的目标世界 y（地面顶面）
const SPAWN_Y := 985.0                     # LauncherManager 出生点标记的世界 y（Main.tscn 固定）

# ---- 非循环动画：待机静帧 + 一次性攻击 ----
const IDLE_FRAME_PNG := 6                  # 待机显示的帧（launcher_006，静止不循环）
const ATK_FPS := 16.0                      # 攻击动画播放速率（帧/秒）
const FIRE_FRAME_INDEX := 20               # 攻击序列中炮弹出膛帧（索引 0 对应 launcher_006 → 20 对应 026）
										   # 挺到这一帧才让炮弹沿炮口朝向飞出；效果可在此微调

@onready var _turret: AnimatedSprite2D = $TurretSprite
@onready var _muzzle: Marker2D = $MuzzlePosition
@onready var _timer: Timer = $CooldownTimer

var _active := false            # 是否已激活（由管理器置位）
var _timer_running := false     # 冷却计时是否已启动
var _dir := 1.0                 # 朝向：+1 朝右（正常），-1 朝左（镜像）
var _recoil_tween: Tween
var _firing := false            # 攻击动画是否在播放（等待出膛帧）
var _pending_target := Vector2.ZERO   # 本次攻击选定的目标


func _ready() -> void:
	_setup_sprite()
	_setup_facing()
	_ground_position()
	_timer.one_shot = false             # 循环冷却
	_timer.timeout.connect(_on_cooldown_timeout)


# 加载大炮帧序列并挂为两个动画：
# idle —— 仅第 IDLE_FRAME_PNG 帧（静止待机，不循环）；
# attack —— 整段 006~038，一次性播放，出膛帧由 FIRE_FRAME_INDEX 决定。
func _setup_sprite() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.add_animation("attack")
	for i in range(FRAME_START, FRAME_END + 1):
		var img := Image.load_from_file(ProjectSettings.globalize_path(FRAME_PATH % i))
		var tex := ImageTexture.create_from_image(img)
		if i == IDLE_FRAME_PNG:
			frames.add_frame("idle", tex)
		frames.add_frame("attack", tex)
	frames.set_animation_speed("idle", 1.0)
	frames.set_animation_speed("attack", ATK_FPS)
	frames.set_animation_loop("idle", false)
	frames.set_animation_loop("attack", false)
	_turret.sprite_frames = frames
	_turret.play("idle")


# 依据炮台相对建筑中心的位置决定镜像：左侧朝右、右侧朝左。
func _setup_facing() -> void:
	_dir = -1.0 if global_position.x > BUILDING_CENTER_X else 1.0
	_turret.scale = Vector2(SPRITE_SCALE * _dir, SPRITE_SCALE)
	# 炮口 local = (帧内坐标 - 帧中心) × 缩放，再乘以朝向（镜像后炮口转到镜像侧）
	var mz_local := (MUZZLE_XY - Vector2(ART_HALF, ART_HALF)) * SPRITE_SCALE
	_muzzle.position = Vector2(mz_local.x * _dir, mz_local.y)


# 上移炮台，使其底座底部落到地面（FEET_WORLD_Y）。
func _ground_position() -> void:
	var feet_local := (FEET_BOTTOM_Y - ART_HALF) * SPRITE_SCALE
	position.y += (FEET_WORLD_Y - SPAWN_Y) - feet_local


# 由 LauncherManager 调用：部署动画（从地下升起 + 弹入），并启动冷却。
func play_deploy() -> void:
	_active = true
	SoundManager.play("launcher_deploy")
	position.y += 42.0          # 从"地下"起点
	scale = Vector2(0.12, 0.12)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 42.0, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ensure_timer_started()


# 升级时由管理器调用：刷新冷却（按剩余比例缩短），伤害/半径在发射时实时读取。
func refresh_stats() -> void:
	# 冷却中：按剩余时间比例缩短到新冷却值；否则应用新冷却
	if _timer_running and _timer.time_left > 0.0:
		var frac := clampf(_timer.time_left / maxf(_timer.wait_time, 0.001), 0.0, 1.0)
		_timer.wait_time = UpgradeManager.get_bomb_launcher_cooldown()
		_timer.start(_timer.wait_time * frac)
	else:
		_timer.wait_time = UpgradeManager.get_bomb_launcher_cooldown()
		if _timer_running:
			_timer.start()


# 启动冷却计时（首次开火用较短延迟，给玩家即时反馈）。
func _ensure_timer_started() -> void:
	if _timer_running:
		return
	_timer_running = true
	_timer.wait_time = minf(UpgradeManager.get_bomb_launcher_cooldown(), FIRST_SHOT_DELAY)
	_timer.start()


# 冷却结束：选定目标并播放一次攻击动画；出膛那帧才真正发射。随后预置下一轮冷却。
func _on_cooldown_timeout() -> void:
	if not _active:
		return
	_start_attack()
	_timer.wait_time = UpgradeManager.get_bomb_launcher_cooldown()


# 挑一个建筑区域内的随机点作为目标。
# 采样中心按每台炮台的横向偏好左右偏移，再叠加均匀噪声，让目标分布在整个楼面上，
# 而不是(因为炮弹横飞提前撞墙)堆在靠近炮台的侧半边。
func _pick_target() -> Vector2:
	var b := get_tree().current_scene.get_node_or_null("Building") as Node2D
	if b == null:
		return global_position + Vector2(520.0, -260.0)   # 兜底：向右上方打
	var cx := b.position.x + BUILDING_X_CENTER_OFFSET
	var top := b.position.y + BUILDING_TOP_DY
	var bottom := b.position.y + BUILDING_BOTTOM_DY
	var shift := aim_zone_x * BUILDING_HALF_W * 0.5          # 偏好把采样中心左右移
	return Vector2(cx + shift + randf_range(-BUILDING_HALF_W, BUILDING_HALF_W) * 0.6,
			randf_range(top, bottom))


# 由 LauncherManager 调用：赋予本台炮台的横向瞄准偏好。
func set_aim_zone(x: float) -> void:
	aim_zone_x = clampf(x, -1.0, 1.0)


# 启动攻击：选定目标并播放一次性攻击动画。在 FIRE_FRAME_INDEX 帧经 _on_attack_frame 出膛。
func _start_attack() -> void:
	if _firing:
		return
	_pending_target = _pick_target()
	_firing = true
	_turret.frame = 0
	_turret.frame_changed.connect(_on_attack_frame)
	# 防御：若上一发动画不明原因未触发 animation_finished（单次连接残留），先清掉旧连接再重挂，
	# 避免 "already connected" 报错。
	if _turret.animation_finished.is_connected(_on_attack_finished):
		_turret.animation_finished.disconnect(_on_attack_finished)
	_turret.animation_finished.connect(_on_attack_finished, CONNECT_ONE_SHOT)
	_turret.play("attack")


# 攻击动画逐帧推进：到达出膛帧即发射一发炮弹（炮弹沿炮口朝向对应的轨迹飞出）。
func _on_attack_frame() -> void:
	if not _firing:
		return
	if _turret.frame < FIRE_FRAME_INDEX:
		return
	# 注意：这里保持 _firing=true（不提前复位），直到整段攻击动画播完触发 animation_finished。
	# 若在出膛帧就置 false，而上一发的 animation_finished 单次连接仍挂着，短冷却（升级后）
	# 在动画结束前再次 _start_attack 时会重复 connect，触发 "already connected" 报错。
	_turret.frame_changed.disconnect(_on_attack_frame)
	_launch_bomb(_pending_target)


# 攻击动画播完：复位到待机静帧。
func _on_attack_finished() -> void:
	_firing = false
	_turret.frame_changed.disconnect(_on_attack_frame)
	_turret.stop()
	_turret.play("idle")


# 在炮口实例化炮弹并赋予抛物线初速。散射炮（机制升级）升级后一次发射多发。
func _launch_bomb(target: Vector2) -> void:
	if not is_instance_valid(self):
		return
	SoundManager.play("launcher_shoot")
	_play_recoil()
	_play_muzzle_flash()
	var count: int = maxi(UpgradeManager.get_scatter_count(), 1)
	for _i in range(count):
		# 散射：多发目标在原始瞄准点周围散布，形成扇形覆盖；单发则精确命中。
		var aim := target
		if count > 1:
			var spread := Vector2(randf_range(-80.0, 80.0), randf_range(-45.0, 45.0))
			aim = target + spread
		_spawn_projectile(aim)


func _spawn_projectile(target: Vector2) -> void:
	var proj: Node2D = PROJECTILE_SCENE.instantiate()
	proj.position = _muzzle.global_position
	proj.bomb_gravity = gravity
	# 炮弹伤害 = 升级表值 ×(1+弹药强化%转生乘和) + 炮塔基础伤害永久加值；半径 = 范围表值 ×(1+爆裂范围%转生乘和)。
	proj.damage = UpgradeManager.get_bomb_launcher_damage() * ReincarnationManager.get_bomb_damage_mult() \
			+ ReincarnationManager.get_bomb_base_damage_bonus()
	proj.radius = UpgradeManager.get_bomb_launcher_radius() * ReincarnationManager.get_bomb_radius_mult()
	proj.origin_launcher = self
	get_tree().current_scene.add_child(proj)
	proj.set_initial_velocity(_ballistic_velocity(_muzzle.global_position, target, gravity))


# 弹道解算：给定起末点与重力，反推初速度（飞行时间随距离自适应，保证弧线自然）。
func _ballistic_velocity(from: Vector2, to: Vector2, g: float) -> Vector2:
	var dx := to.x - from.x
	var dy := to.y - from.y
	var dist := maxf(from.distance_to(to), 1.0)
	var t := clampf(dist / 500.0, 0.7, 2.2)
	return Vector2(dx / t, (dy - 0.5 * g * t * t) / t)


# 后坐力：大炮沿朝向反方向平移再回弹。
func _play_recoil() -> void:
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_turret.position.x -= 6.0 * _dir
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(_turret, "position:x", _turret.position.x + 6.0 * _dir, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# 炮口闪光。
func _play_muzzle_flash() -> void:
	var flash := Polygon2D.new()
	flash.polygon = _circle_points(12.0)
	flash.color = Color(1.0, 0.9, 0.5, 0.9)
	flash.position = _muzzle.global_position
	get_tree().current_scene.add_child(flash)
	flash.scale = Vector2(0.3, 0.3)
	var t := flash.create_tween()
	t.tween_property(flash, "scale", Vector2.ONE, 0.08)
	t.parallel().tween_property(flash, "modulate:a", 0.0, 0.14)
	t.tween_callback(flash.queue_free)


func _circle_points(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	const SEG := 24
	for i in range(SEG):
		var a := TAU * float(i) / float(SEG)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts
