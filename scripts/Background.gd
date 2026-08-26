extends ParallaxBackground
## 氛围层：多层视差背景，放大"这是一栋高耸摩天楼"的尺度感。
## 用 Godot 原生 ParallaxBackground + ParallaxLayer（参照教程 BV1Th4y1X7Kz 的用法）。
## 从后到前共 4 层：远处城市+天空 / 近城市 / 草地 / 土地。
## 挂在 Main.tscn 的 Background 节点上（置于 Building / 方块层之前），永远在塔和地面之后、UI 之前。
## 机制（视差）：相机与大楼都保持不动，光标横向位置驱动各 ParallaxLayer.motion_offset：
##   每层 motion_offset.x = 光标比例 × MAX_OFF × 该层系数(px)。
## 各层系数不同 → 四层背景以不同速度横向平移制造纵深：越近(系数越大)动得越快、越远越慢。
## 每个 ParallaxLayer 内横向平铺三份同图(左/中/右)，保证平移时不露黑边。
## 大楼脚下的地面带单独放在一个 px=0 的 ParallaxLayer（motion_offset 恒为 0），
## 像"土壤"一样固锁在楼脚坐标，避免被速度最快的近景层带动、造成"大楼在动"的错觉。
## 纯 Sprite2D，不拦截鼠标拾取方块。

# 铺满屏宽所需缩放 = 1920 / 素材宽 1120（4 张背景素材均为 1120 宽）
const VIEW_W := 1920.0
const NATIVE_W := 1120.0
const SCALE := VIEW_W / NATIVE_W            # ≈ 1.714

# 光标每滑到屏幕边缘，速度最快的层最多横向平移 MAX_OFF px（再乘以各层系数）。
# 三份平铺间距=VIEW_W，只要 MAX_OFF<VIEW_W/2≈960 就不会露边。
# 设为 0 即关闭视差（所有背景层固定不动，仅作为静态氛围层）。
const MAX_OFF := 0.0

# 每层配置：file=素材名(无扩展名)；px=横向视差系数(越大越靠前景、动得越快)；center_y=初始竖直中心(世界 y)
# 竖直排布让"天空在顶部、远景地平线偏低、近景草地在屏底"，塔(40px 块)始终叠在最前成为主角。
# px 两个移动层(远处城市+天空 / 近城市)速度分开制造纵深；草地与土地固定 px=0，
# 作为楼脚底部固锁参照系，不随背景滑动，避免"楼在动"的错觉。
const LAYERS := [
	{ "file": "远处城市和天空", "px": 0.06, "center_y": 285.0 },   # 后景：几乎贴住，动得最慢
	{ "file": "近城市",         "px": 0.22, "center_y": 620.0 },   # 中后景城市剪影：中速
	{ "file": "草地",           "px": 0.00, "center_y": 900.0 },   # 中景草地：固定不动(与土地共同作为地面参照系)
	{ "file": "土地",           "px": 0.00, "center_y": 1048.0 },  # 前景土壤：固定不动(楼脚参照系)
]

# 地表带：楼脚下一条平坦的"平地"(草绿->深土色)。顶边(世界y=1000)正好托住楼底，其下才是地下泥土。
const SURFACE_TOP_Y := 1000.0      # 地表带顶边(= 楼底方块底缘，与物理地面顶面一致)
const SURFACE_HEIGHT := 24.0       # 地表带厚度(往下延伸进土壤的一层表土)

var _layers: Array = []        # [ {node:ParallaxLayer, px} ]：node=单层(内含3份sprite)，px=横向系数


func _ready() -> void:
	for cfg in LAYERS:
		var tex: Texture2D = load("res://assets/ui/%s.png" % cfg.file) as Texture2D
		if tex == null:
			continue
		# 每层：横向放 3 份同一张图(左/中/右)，整体 motion_offset 随光标平移。
		var layer := ParallaxLayer.new()
		layer.name = "Layer_" + cfg.file
		for k in [-1.0, 0.0, 1.0]:
			var sp := Sprite2D.new()
			sp.texture = tex
			sp.scale = Vector2(SCALE, SCALE)
			sp.position = Vector2(k * VIEW_W, 0.0)   # 左-1920 / 中0 / 右+1920(相对层中心)
			layer.add_child(sp)
		layer.position = Vector2(960.0, cfg.center_y)
		add_child(layer)
		_layers.append({ "node": layer, "px": cfg.px })
	_build_surface()


# 地面带：楼脚下一条平坦的"地表"（草绿渐变 -> 下方土色）。顶边正好托住楼底(y=1000)。
# 放进一个 px=0 的 ParallaxLayer，motion_offset 恒为 0，完全不参与视差，跟随楼底座在屏幕原位。
func _build_surface() -> void:
	var gtex := GradientTexture2D.new()
	gtex.width = int(VIEW_W)
	gtex.height = int(SURFACE_HEIGHT)
	gtex.fill = GradientTexture2D.FILL_LINEAR
	gtex.fill_from = Vector2(0.0, 0.0)      # 顶→
	gtex.fill_to = Vector2(0.0, 1.0)        # →底
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(0.38, 0.66, 0.30), Color(0.36, 0.47, 0.26)])   # 草绿 -> 深表土
	gtex.gradient = grad
	var surf := Sprite2D.new()
	surf.name = "GroundSurface"
	surf.texture = gtex
	surf.position = Vector2(0.0, SURFACE_TOP_Y + SURFACE_HEIGHT / 2.0)   # 相对层(960,0)→屏上(960,1012)
	var holder := ParallaxLayer.new()
	holder.name = "Layer_GroundSurface"
	holder.add_child(surf)
	holder.position = Vector2(960.0, 0.0)
	add_child(holder)
	_layers.append({ "node": holder, "px": 0.0 })


func _process(_delta: float) -> void:
	# 光标相对屏幕中心的横移比例(-1..1)。相机/世界不动，仅驱动各层背景横向平移。
	var vp: Viewport = get_viewport()
	var mouse: Vector2 = vp.get_mouse_position()
	var center: Vector2 = vp.get_visible_rect().size * 0.5
	var relx: float = clampf((mouse.x - center.x) / center.x, -1.0, 1.0)
	for entry in _layers:
		var layer: ParallaxLayer = entry.node
		if not is_instance_valid(layer):
			continue
		layer.motion_offset.x = relx * MAX_OFF * entry.px
