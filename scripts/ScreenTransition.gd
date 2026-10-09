extends CanvasLayer
## 场景切换过场：抓取当前画面，切成 N×M 矩形碎块，
## 碎块带重力、随机旋转、轻微爆散后下落，露出下方新场景；
## 全部移出屏幕后自动清理，过渡结束。
## 作为 Autoload 常驻，change_scene 后不会被销毁，过渡全程不中断。

# 碎块网格密度（横向 / 纵向）
@export var cols: int = 10
@export var rows: int = 7
# 下落重力加速度
@export var fall_gravity: float = 2400.0
# 下落速度上限
@export var max_fall_speed: float = 1600.0
# 起步爆散横向速度（让碎块先"裂开"再掉）
@export var burst_speed: float = 60.0
# 起步向上跳动速度（先向上小跳一下再下落，0 = 直接下落）
@export var hop_up_speed: float = 420.0
# 角速度范围（度/秒，随机 ±）
@export var rot_speed_range: float = 120.0
# 起步随机延迟上限（秒），错落更有破碎感
@export var start_jitter: float = 0.25
# 切场延迟（秒）：碎块已散开、未掉完时切场景
@export var exit_delay: float = 0.25
# 碎块完全移出屏幕的额外余量（px）
@export var clear_margin: float = 120.0
# 过渡期间是否用全屏 Control 拦截鼠标点击
@export var input_block: bool = true
# 生成瞬间的全屏震屏（抖动半径 px / 时长 s），随时间线性衰减
@export var shake_radius: float = 5.0
@export var shake_duration: float = 0.25
# 碎块生成弹跳：起始缩放 + 弹簧恢复时长（s），增强"跳出来"的破碎感
@export var pop_scale: float = 0.6
@export var pop_duration: float = 0.12

# 单个碎块运行时状态
class Shard:
	var node: TextureRect
	var vel: Vector2
	var ang: float   # 角速度（rad/s）
	var delay: float # 起步延迟剩余时间


var _shards: Array[Shard] = []
var _blocker: Control = null
var _target_scene: String = ""
var _exit_countdown: float = -1.0
var _scene_switched: bool = false
var _busy: bool = false
var _shake_time: float = 0.0


func _ready() -> void:
	layer = 100  # 盖在所有场景之上
	process_mode = Node.PROCESS_MODE_ALWAYS  # 场景切换期间也不暂停本节点
	set_process(false)


# 入口：抓屏 → 生成碎块 → 延时切场景。忙碌时忽略重复调用（防连点）。
func transition_to(target_scene: String) -> void:
	GameFeel.reset()
	if Presentation.reduced_motion:
		get_tree().paused = false
		get_tree().change_scene_to_file(target_scene)
		return
	if _busy:
		return
	_busy = true
	_target_scene = target_scene
	_exit_countdown = exit_delay
	_scene_switched = false

	SoundManager.play("scene_transition")
	_capture_and_spawn()
	_add_input_blocker()
	_shake_time = 0.0  # 生成瞬间震屏
	set_process(true)


func _process(delta: float) -> void:
	# 0) 生成瞬间震屏：CanvasLayer 整体随机抖动，随时间线性衰减
	if _shake_time > 0.0:
		_shake_time -= delta
		var t := clampf(_shake_time / maxf(shake_duration, 0.001), 0.0, 1.0)
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_radius * t
		if _shake_time <= 0.0:
			offset = Vector2.ZERO

	# 1) 切场倒计时：碎块已散开、未掉完时切入新场景
	if not _scene_switched and _exit_countdown >= 0.0:
		_exit_countdown -= delta
		if _exit_countdown <= 0.0:
			_switch_scene()

	if _shards.is_empty():
		return

	# 2) 碎块物理积分（UI 层手动物理，不用 RigidBody2D）与移除
	var view_h: float = get_viewport().get_visible_rect().size.y
	var alive: Array[Shard] = []
	for shard in _shards:
		if shard.delay > 0.0:
			shard.delay -= delta   # 起步延迟未到，原地不动（错落破碎感）
			alive.append(shard)
			continue
		shard.vel.y += fall_gravity * delta
		shard.vel = shard.vel.limit_length(max_fall_speed)
		shard.node.position += shard.vel * delta
		shard.node.rotation += shard.ang * delta
		if shard.node.position.y > view_h + clear_margin:
			shard.node.queue_free()  # 完全移出屏幕
		else:
			alive.append(shard)
	_shards = alive

	if _shards.is_empty():
		_finish()


# 切场：碎块已散开、未掉完时切入新场景。
# Main.tscn 里 Building 节点本身极轻（360 个方块由 BuildingSetup 运行时"分帧生成"，
# 见 BuildingSetup._generate_in_batches），不会在切场瞬间长时间占用主线程，直接同步切换即可。
func _switch_scene() -> void:
	_scene_switched = true
	get_tree().change_scene_to_file(_target_scene)


# 抓屏 + 按 cols×rows 切成矩形碎块铺满全屏。
func _capture_and_spawn() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	# 抓取当前帧画面；无渲染环境（headless / 取不到图）时退回纯色屏
	var tex: Texture2D = null
	if DisplayServer.get_name() != "headless":
		var vp_tex := get_viewport().get_texture()
		if vp_tex != null:
			var img := vp_tex.get_image()
			if img != null:
				tex = ImageTexture.create_from_image(img)
	if tex == null:
		tex = _fallback_texture(vp_size)

	var w: float = vp_size.x / float(cols)
	var h: float = vp_size.y / float(rows)

	for r in rows:
		for c in cols:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(c * w, r * h, w, h)

			var shard_node := TextureRect.new()
			shard_node.texture = atlas
			shard_node.position = Vector2(c * w, r * h)
			shard_node.size = Vector2(w + 1.0, h + 1.0)  # +1px 防碎块间缝隙
			shard_node.pivot_offset = Vector2(w, h) / 2.0  # 绕中心旋转
			add_child(shard_node)
			# 生成弹跳：先缩小再弹簧弹回 1.0，增强"跳出来"的破碎感
			# Tween 绑定在碎块节点本身，碎块被释放时自动销毁，无残留
			shard_node.scale = Vector2(pop_scale, pop_scale)
			shard_node.create_tween().tween_property(shard_node, "scale", Vector2.ONE, pop_duration) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

			var shard := Shard.new()
			shard.node = shard_node
			shard.vel = Vector2(randf_range(-burst_speed, burst_speed), -randf_range(0.0, hop_up_speed))
			shard.ang = deg_to_rad(randf_range(-rot_speed_range, rot_speed_range))
			shard.delay = randf_range(0.0, start_jitter)
			_shards.append(shard)


# 无渲染环境（如 headless 测试）抓不到画面的兜底：纯黑屏。
func _fallback_texture(vp_size: Vector2) -> Texture2D:
	var img := Image.create(int(vp_size.x), int(vp_size.y), false, Image.FORMAT_RGB8)
	img.fill(Color(0, 0, 0))
	return ImageTexture.create_from_image(img)


# 全屏鼠标拦截，避免过渡期间误操作新场景。
func _add_input_blocker() -> void:
	if not input_block:
		return
	_blocker = Control.new()
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_blocker)


# 全部碎块移出屏幕：清理节点、恢复输入、解除忙碌。
func _finish() -> void:
	# 极慢加载兜底：碎块已全部清空但场景仍未切换，直接同步切换，避免卡死在过渡
	if not _scene_switched and _target_scene != "":
		_scene_switched = true
		get_tree().change_scene_to_file(_target_scene)
	for shard in _shards:
		if is_instance_valid(shard.node):
			shard.node.queue_free()
	_shards.clear()
	if is_instance_valid(_blocker):
		_blocker.queue_free()
	_blocker = null
	offset = Vector2.ZERO  # 震屏收尾归零
	_target_scene = ""
	_exit_countdown = -1.0
	_scene_switched = false
	_busy = false
	set_process(false)
