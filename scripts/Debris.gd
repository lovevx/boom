extends Node2D
## 破碎碎屑（视觉特效）：建筑方块被毁时生成的一小块碎片。
## 不做物理掉落，而是向外飞散、同时缩小并淡出，约 0.45 秒内消失。
## 纯视觉节点，不参与碰撞与重力。
## P1：碎块从"整齐小方块"升级为"随机不规则凸多边形碎屑"，每块姿态（顶点数/长宽比/旋转）随机，
## 且尽量按方块材质贴图采样上色（纹理随之变化），玻璃类碎屑半透明——不同材质破碎观感各异。
## 有材质贴图时采它的随机裁剪小区域；无贴图时回退纯 debris_color，形状仍不规则。

var size: float = 6.0            # 边长（由生成方在 add_child 前设置）
var base_color: Color = Color(0.6, 0.6, 0.6)
var fly_dir: Vector2 = Vector2.RIGHT   # 飞行方向（由生成方按均匀角度传入）
var texture: Texture2D = null    # 该方块材质的贴图来源（P1），碎块按它采样；null 则纯色
var is_glass := false            # 是否为玻璃方块，碎块半透明（玻璃碎成亮茬）

var _poly: PackedVector2Array = PackedVector2Array()      # 随机凸多边形顶点（局部坐标）
var _uvs: PackedVector2Array = PackedVector2Array()       # 贴图裁剪采样 UV（与顶点一一对应）
var _vert_colors: PackedColorArray = PackedColorArray()   # Gouraud 渐变顶点色（中心亮边缘暗）

const GLASS_ALPHA := 0.55        # 玻璃碎屑透明度（与玻璃块统一观感）
const EDGE_DARKEN := 0.28        # 顶点由中心到边缘压暗比例


func _ready() -> void:
	add_to_group(&"in_game_entity")   # 归入"场上临时实体"组，重置时统一清理
	_build_shard()
	# 沿给定方向向外飞散，同时缩小并淡出
	var distance := randf_range(30.0, 90.0)
	var fly := create_tween()
	fly.tween_property(self, "position", position + fly_dir * distance, randf_range(0.25, 0.4)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fly.parallel().tween_property(self, "scale", Vector2(0.05, 0.05), randf_range(0.3, 0.45))
	fly.parallel().tween_property(self, "modulate:a", 0.0, randf_range(0.35, 0.45))
	fly.parallel().tween_property(self, "rotation", randf_range(-4.0, 4.0), 0.3)
	fly.finished.connect(queue_free)


# 生成一块随机不规则碎块：随机 3~5 顶点的星形凸多边形 + 姿态（缩放/UV 采样）随机，
# 并算好 Gouraud 渐变顶点色（中心亮、边缘压暗）。有材质贴图时采样其随机小区域。
func _build_shard() -> void:
	var half := size * 0.5
	# 生成一批随机点，取其凸包获得"不规则但必为简单凸多边形"的碎屑。
	# 旧写法只按角度排序（仅保证 star 形，可能凹陷/自交/退化），draw_polygon 三角剖分失败，
	# 报 "Invalid polygon data, triangulation failed"。凸包多边形必为合法，稳定可三角化。
	var seed_pts := PackedVector2Array()
	for i in range(randi_range(5, 9)):
		var a := randf() * TAU
		var r := randf_range(half * 0.4, half)   # 半径随机：形似长短不一的碎茬/长条碎片
		seed_pts.append(Vector2(cos(a), sin(a)) * r)
	_poly = _convex_hull(seed_pts)
	if _poly.size() < 3:
		# 兜底：极罕见退化（近共线）时退化为一个菱形，保证 draw_polygon 合法
		_poly = PackedVector2Array([
			Vector2(-half, 0.0), Vector2(0.0, -half * 0.6),
			Vector2(half, 0.0), Vector2(0.0, half * 0.6),
		])
	var cx := 0.0
	var cy := 0.0
	for p in _poly:
		cx += p.x
		cy += p.y
	cx /= float(_poly.size())
	cy /= float(_poly.size())
	var centroid := Vector2(cx, cy)
	var max_d := 0.01
	for p in _poly:
		max_d = maxf(max_d, p.distance_to(centroid))
	var alpha := GLASS_ALPHA if is_glass else 1.0
	for p in _poly:
		var d := clampf(p.distance_to(centroid) / max_d, 0.0, 1.0)
		var k := 1.0 - d * EDGE_DARKEN   # 中心偏亮、边缘压暗，营造碎片立体感
		var c := base_color * Color(k, k, k, 1.0)
		_vert_colors.append(Color(c.r, c.g, c.b, alpha))
	# 有材质贴图：按随机 U/V 偏移裁一小块贴上（UV 与顶点对应），叠加 base_color 亮度/色调调制
	if texture != null and is_instance_valid(texture) \
			and texture.get_width() > 1 and texture.get_height() > 1:
		var us := randf_range(0.10, 0.26)   # 采样区域宽占比（小块区域，保留纹理细节）
		var vs := us
		var u0 := randf_range(0.0, 1.0 - us)
		var v0 := randf_range(0.0, 1.0 - vs)
		for p in _poly:
			var u := u0 + (p.x + half) / size * us
			var v := v0 + (p.y + half) / size * vs
			_uvs.append(Vector2(u, v))


# 单调链凸包：输入若干随机点，输出按逆时针排列的凸多边形顶点。
# 任一凸多边形都是合法的 triangulation 输入，绝不会触发 draw_polygon 三角剖分失败。
static func _convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var p: Array[Vector2] = []
	for pt in points:
		p.append(pt)
	p.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x if not is_equal_approx(a.x, b.x) else a.y < b.y)
	var lower := PackedVector2Array()
	var upper := PackedVector2Array()
	for pt in p:
		while lower.size() >= 2 and _cross(lower[lower.size() - 2], lower[lower.size() - 1], pt) <= 0.0:
			lower.remove_at(lower.size() - 1)
		lower.append(pt)
	for pt in p:
		while upper.size() >= 2 and _cross(upper[upper.size() - 2], upper[upper.size() - 1], pt) >= 0.0:
			upper.remove_at(upper.size() - 1)
		upper.append(pt)
	var hull := PackedVector2Array()
	hull.append_array(lower)   # 忽略末点为公共，用 upper 反向补全两侧
	for i in range(upper.size() - 2, 0, -1):
		hull.append(upper[i])
	return hull


# 叉积(cross)：向量 ab 与向量 ac 的叉积（z 分量），用于凸包判定转向。
static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


func _draw() -> void:
	if _poly.size() < 3:
		return
	if _uvs.size() == _poly.size() and is_instance_valid(texture):
		draw_polygon(_poly, _vert_colors, _uvs, texture)   # 纹理碎块：材质色 + 渐变明暗
	else:
		draw_polygon(_poly, _vert_colors)                   # 兜底：纯色不规则碎块（仍带渐变）
