extends Node2D
## 像素风爆炸特效（One-shot，纯代码生成，免手动配置 Inspector）。
##
## 挂在根节点的【位置/朝向】就是爆炸点。调用 explode() 后会自动：
##   1. 向四周 360° 全向喷射大量【石块】原有纹理碎片（带重力抛物线 + 自身翻滚旋转）；
##   2. 全部播完（取各层最长 lifetime 后）自动 queue_free 销毁。
##   （淡蓝半透明"烟雾/冲击波环"已移除，扬尘观感改由 DustFx 尘土 GIF 承担。）
##
## 用法：
##   var boom := PixelExplosion.new()
##   boom.position = 爆炸点
##   boom.stone_texture = <某材质贴图>
##   get_tree().current_scene.add_child(boom)
##   boom.explode()
## 或直接给一个 Node2D 挂上本脚本，调用 $PixelExplosion.explode()。
##
## 说明：
##   - 烟雾层每用 1 个 CPUParticles2D（工程为 Compatibility 渲染器，GPU 粒子不生效）。
##   - 已确认项目 default_texture_filter=0（Nearest），像素风无需改动；若日后换成别的工程，
##     需在 项目设置→Rendering→Textures→Canvas Textures→Default Texture Filter 里改 Nearest。
##   - 数据量小、为演示代码而写成 const 阈值；改成 @export 即可在 Inspector 逐个项目调参。


# ---------- 通用爆炸参数（写死为常量，方便整体调档；可按事件局部覆盖） ----------
const GRAVITY := 980.0            # 重力(px/s²)，Y 正向 = 2D 中向下，模拟真实下落抛物线
const SPREAD := 180.0             # 扩散角；配合 direction=ZERO 形成 360° 全向爆炸
const EXPLOSIVENESS := 1.0        # 1.0 = 所有粒子同一帧全部爆发

const STONE_LIFE := 1.2           # 石块碎片层生命周期

# ---------- 每层粒子数量（可调） ----------
var stone_amount: int = 64

# ---------- 贴图来源 ----------
## 石块/材质碎片贴图。默认引用项目已有的大理石材质；传入不同材质即可获得对应观感。
var stone_texture: Texture2D = preload("res://assets/ui/大理石.png")


## 点燃特效：创建石块碎片层，并安排整节点自动清理。
## 异步无需 await 也能跑（直接调用即可）；想等它播完再继续可 await boom.explode()。
func explode() -> void:
	_setup_stone()
	# 碎片层是本节点的子节点，等它播完再整节点销毁
	await get_tree().create_timer(STONE_LIFE).timeout
	queue_free()


# ======================================================================
#  石块层：把方块贴图按 GRID×GRID 切成网格，每格开一个粒子层。
#  每片碎粒只带整张贴图的一角（AtlasTexture 子区域），整体看是
#  "一整块碎成多个小片"而不是每粒都是完整方块，360° 全向 + 重力抛物线下落。
# ======================================================================
const STONE_GRID := 3            # 3×3 = 把贴图切成 9 片（片数越多碎得越细）

func _setup_stone() -> void:
	var cells := _split_texture(stone_texture, STONE_GRID)
	if cells.is_empty():
		cells.append(stone_texture)   # 无贴图/太小：退回一整张贴图当默认
	var per := maxi(1, ceili(float(stone_amount) / float(cells.size())))
	for tex in cells:
		var p := _new_layer(per, STONE_LIFE, tex)
		# 碎片用足量初速 + 满重力(980)，让它们喷得远一点再抛物线落下；
		# 缩放相对 64px 切片调大，保证碎片看得清（比先前整张贴图比例明显）。
		_apply_motion(p, 300.0, 640.0, 0.20, 0.38, GRAVITY)
		# 玻璃材质：整层调成半透明，保留贴图本色
		if stone_texture != null and "玻璃" in stone_texture.resource_path:
			p.modulate = Color(1, 1, 1, 0.6)
		# 颜色曲线：开头保持原样，末段轻微变暗后淡出
		var g := Gradient.new()
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1),
			Color(1, 1, 1, 1),
			Color(0.88, 0.86, 0.84, 0.0),
		])
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		p.color_ramp = g
		p.z_index = 60                # 盖过塔身(z=40)
		add_child(p)


# 把一张贴图切成 n×n 片，每片退回带"不规则多边形遮罩"的 ImageTexture：
# 先裁出该格矩形，再用一个随机多边形把多边形以外的像素挖成透明，
# 于是每片都是形状不一、斜着切出来的材质碎块（而非整齐矩形）。过小/拿不到时返回空数组。
#
# 性能：逐像素挖空较贵，按"材质路径+网格数"做静态缓存——同一种材质只算一次，
# 后续每次爆炸直接复用切片，避免砸块时反复拷贝大图 + 逐像素抠图导致的卡顿。
static var _slice_cache: Dictionary = {}

func _split_texture(tex: Texture2D, n: int) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	if tex == null or not is_instance_valid(tex):
		return out
	if tex.get_width() < n or tex.get_height() < n:
		return out                       # 切不出 n×n，退回整张贴图
	var key := tex.resource_path + "|" + str(n)   # 每片遮罩随机，缓存整批避免重算
	if _slice_cache.has(key):
		return _slice_cache[key]
	var src := tex.get_image()           # 只取一次原图，供各格采样
	# 性能：碎片显示才几十像素，遮罩无需贴图原尺寸精度。先把源图缩到够用的大小
	# （每片最长边 = SLICE_PX），首算挖遮罩的像素量从百万级骤降，几次爆炸不卡。
	const SLICE_PX := 64
	var limit := SLICE_PX * n            # 源图缩到 limit×limit 后切 n 片，每片 64px
	if src.get_width() > limit or src.get_height() > limit:
		src.resize(limit, limit, Image.INTERPOLATE_NEAREST)
	var cw := src.get_width() / n
	var ch := src.get_height() / n
	for gy in range(n):
		for gx in range(n):
			var img := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
			img.blit_rect(src, Rect2i(gx * cw, gy * ch, cw, ch), Vector2i.ZERO)
			# 把矩形片挖成不规则斜片，返回处理后的字节流，再重建为带遮罩的贴图
			var data := _crop_irregular(img)
			var cut := Image.create_from_data(cw, ch, false, Image.FORMAT_RGBA8, data)
			out.append(ImageTexture.create_from_image(cut))
	_slice_cache[key] = out              # 同材质后续爆炸直接复用
	return out


# 把一张矩形片用"随机多边形遮罩"挖空：多边形内的像素保留（材质局部），
# 多边形外的像素置为透明。多边形按角度环绕生成，保证不自交 → 稳定出片。
# 返回处理后的 RGBA8 字节流（不写回原 Image，由调用方 create_from_data 重建）。
func _crop_irregular(img: Image) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var hw := w * 0.5
	var hh := h * 0.5
	# 随机多边形顶点（4~7 边，半径随机 → 凹凸斜切感）
	var poly: PackedVector2Array = []
	var sides := randi_range(4, 7)
	for i in range(sides):
		var a := TAU * float(i) / float(sides) + randf_range(-0.10, 0.10)
		var r := randf_range(minf(hw, hh) * 0.35, minf(hw, hh))
		poly.append(Vector2(cos(a), sin(a)) * r)
	# 一次取整张字节流（RGBA8，每像素 4 字节），只对"多边形外"写入透明，最后一次性返回。
	# 相比逐像素 set_pixel，省去海量函数调用/边界检查——这是碎裂不卡的关键。
	var dst := img.get_data()
	var stride := w * 4
	for y in range(h):
		var row := y * stride
		for x in range(w):
			if not _point_in_poly(Vector2(x - hw, y - hh), poly):
				var i := row + x * 4
				dst[i + 3] = 0            # 仅 alpha 置 0 即可隐藏（RGB 不管）
	return dst


# 射线法判断点是否在多边形内（对简单多边形通用，含凹凸）。
static func _point_in_poly(pt: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in range(n):
		var a := poly[i]
		var b := poly[j]
		if ((a.y > pt.y) != (b.y > pt.y)) \
				and (pt.x < (b.x - a.x) * (pt.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside


# ======================================================================
#  通用：构建一个空 CPUParticles2D 层的公共字段
#  （工程为 Compatibility 渲染器，不用 GPUParticles2D）
# ======================================================================
func _new_layer(amount: int, lifetime: float, tex: Texture2D) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true          # 一次性，播完即止
	p.explosiveness = EXPLOSIVENESS   # 1.0 = 所有粒子同一帧爆发
	p.texture = tex
	return p


# ======================================================================
#  通用：把爆炸运动参数直接写到 CPUParticles2D 节点上
#  vmin/vmax 初速度区间，smin/smax 粒子局部缩放（min~max 随机即"随机度"），
#  gravity 本层重力（烟雾轻、碎片重，营造不同观感）
# ======================================================================
func _apply_motion(p: CPUParticles2D, v_min: float, v_max: float,
		s_min: float, s_max: float, gravity: float) -> void:
	# —— 运动 ——
	# 注意：CPUParticles2D 的初速方向 = direction 按 spread 偏转后的结果。
	# direction 必须是【非零】向量才会喷射；配合 spread=180 就在 360° 全向散开。
	p.gravity = Vector2(0, gravity)
	p.direction = Vector2(0.0, -1.0)
	p.spread = SPREAD                    # 180° 锥角 → 全向爆炸
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	# —— 翻滚旋转 ——
	p.angular_velocity_min = -360.0      # 正负随机，碎片边飞边转
	p.angular_velocity_max = 360.0
	# —— 缩放（随机大小 → 自然层次）+ 渐进缩小 ——
	p.scale_amount_min = s_min
	p.scale_amount_max = s_max
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, 0.30))      # 到寿命末缩到 30%
	p.scale_amount_curve = sc
