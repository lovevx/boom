extends Node2D
## 尘土 GIF 特效（One-shot，纯代码，免手动配置 Inspector）。
##
## 美术准备的 3 个尘土 GIF（assets/audio/尘土1/2/5.gif）已离线转成"10 列网格图集"
## （assets/fx/dust/dust1/2/5.png）。本脚本在运行时把图集组装成 SpriteFrames，
## 用 AnimatedSprite2D 一次性播放后自动销毁，供"方块塌落 / 落定 / 炸弹爆炸"等处调用。
## （尘土3 背景不透明、尘土4 被弃用，故序号不连续：1/2/5。）
##
## 用法（跟 PixelExplosion 一致：实例化 → setup → add_child 即自动开播）：
##   const DUST_FX := preload("res://scripts/DustFx.gd")
##   var fx := DUST_FX.new()
##   fx.setup(world_pos, -1, 0.7, false)   # 随机挑一种尘土
##   get_tree().current_scene.add_child(fx)
##
## 说明：
##   - SpriteFrames 按尘土序号静态缓存：同一种尘土首次生成后复用，不重复组装。
##   - 连锁塌落/落定会瞬间触发多次，内置静态节流窗口：短时间内只放少量，防刷屏卡帧；
##     爆炸等单发强事件可传 force=true 绕过节流，保证必播。
##   - 尘土为软边烟尘，AnimatedSprite2D 用 Linear 采样（工程默认 Nearest 像素风，
##     对贴图类特效会块化，故单独放宽）。


## —— 图集配置：每张图集 10 列网格，第 i 帧位于 (col = i%10, row = i/10) ——
const GRID_COLS := 10
## 尘土序号 → 图集信息（帧数/播放速度由源 GIF 帧延迟换算，尺寸为单帧像素）
## 注：尘土3 背景不透明、尘土4 被弃用，序号保持 1/2/5（不连续）。
const DUST := {
	1: { "path": "res://assets/fx/dust/dust1.png", "frames": 13, "fps": 13.3, "w": 277, "h": 277 },
	2: { "path": "res://assets/fx/dust/dust2.png", "frames": 50, "fps": 25.0, "w": 282, "h": 158 },
	5: { "path": "res://assets/fx/dust/dust5.png", "frames": 50, "fps": 25.0, "w": 282, "h": 158 },
}

## 尘土分组：爆炸扬尘用 1/2（大团烟尘），方块掉落/落定用 5（横版贴地扬尘）。
## 调用方从对应组随机挑选，避免爆炸和掉落出现同款尘土。
const EXPLOSION_DUST := [1, 2]
const COLLAPSE_DUST := [5]

## 从尘土组里随机挑一个有效序号（组内若有已弃用的序号自动跳过）。
static func pick_dust(pool: Array) -> int:
	var valid: Array = []
	for k in pool:
		if DUST.has(k):
			valid.append(k)
	if valid.is_empty():
		return DUST.keys()[randi() % DUST.size()]   # 兜底：整组失效时退回全量随机
	return valid[randi() % valid.size()]

# SpriteFrames 静态缓存：尘土序号 → SpriteFrames（首次生成后复用）
static var _frames_cache: Dictionary = {}

# 静态节流：连锁事件（多块同帧塌落/落定）只放少量尘土，避免刷屏卡帧。
static var _throttle_win_ms := -1000000
static var _throttle_count := 0
const THROTTLE_WINDOW_MS := 80
const THROTTLE_MAX := 6


var spawn_pos := Vector2.ZERO    # 尘土播放的世界坐标（setup 传入）
var kind := -1                   # 尘土序号（1/2/5）；非有效序号则随机挑一种
var fx_scale := 1.0              # 世界缩放（图集单帧约 277~282px）
var force := false               # true = 绕过节流必播（单发强事件用）


## 初始化参数：在 add_child 前调用。
func setup(pos: Vector2, k: int, s: float, forced: bool = false) -> void:
	spawn_pos = pos
	kind = k
	fx_scale = s
	force = forced


func _ready() -> void:
	# 节流（force=true 跳过）：窗口内限量，避免连锁塌落时刷一堆尘土卡帧。
	if not force and not _throttle_pass():
		queue_free()
		return
	add_to_group(&"in_game_entity")   # 归入"场上临时实体"组，重置时统一清理
	position = spawn_pos
	var k: int = kind
	if not DUST.has(k):
		k = DUST.keys()[randi() % DUST.size()]   # 序号不连续（1/2/5），从有效键里随机挑
	var frames := _frames(k)
	var anim := AnimatedSprite2D.new()
	anim.name = "DustSprite"
	anim.sprite_frames = frames
	anim.animation = "dust"
	anim.scale = Vector2(fx_scale, fx_scale)
	anim.z_index = 60             # 盖过塔身(z=40)，烟尘浮在建筑之上
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # 软烟尘线性采样，避免像素块化
	add_child(anim)
	anim.play()
	# 播完销毁；兜底超时清理（万一异常未触发 finished 也不残留）
	anim.animation_finished.connect(queue_free)
	var life := float(frames.get_frame_count("dust")) / maxf(frames.get_animation_speed("dust"), 0.001)
	get_tree().create_timer(life + 0.4).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)


# 节流判定：窗口内已放满则本次不播。
static func _throttle_pass() -> bool:
	var now := Time.get_ticks_msec()
	if now - _throttle_win_ms > THROTTLE_WINDOW_MS:
		_throttle_win_ms = now
		_throttle_count = 0
	if _throttle_count >= THROTTLE_MAX:
		return false
	_throttle_count += 1
	return true


# 构建/复用某序号尘土的 SpriteFrames（图集 → 逐帧 AtlasTexture）。
static func _frames(k: int) -> SpriteFrames:
	if _frames_cache.has(k):
		return _frames_cache[k]
	var cfg: Dictionary = DUST[k]
	var sheet: Texture2D = load(cfg["path"]) as Texture2D
	var fw := float(cfg["w"])
	var fh := float(cfg["h"])
	var count := int(cfg["frames"])
	var sf := SpriteFrames.new()
	sf.add_animation("dust")
	sf.set_animation_loop("dust", false)
	sf.set_animation_speed("dust", float(cfg["fps"]))
	for i in range(count):
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2((i % GRID_COLS) * fw, (i / GRID_COLS) * fh, fw, fh)
		sf.add_frame("dust", at)
	_frames_cache[k] = sf
	return sf
