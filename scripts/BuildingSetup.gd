extends Node2D
## Building 节点上的初始化脚本：运行时生成一栋"无限层"的楼。
## 楼体按"列"托管：每列自上而下放满 VISIBLE_LAYERS 个方块，方块默认冻结（静态支撑）。
## 任一方块被砸碎后，它所在列的"上方方块"会一并失去支撑，各自作为独立刚体重力下落，
## 落到下方存活方块或地面后吸附回网格槽位并重新冻结；该列随之在楼顶补出一层，保持塔高。
## 从而形成"每块都有物理、各自下坠"的塌陷手感，又不失"砸一块塌一串、取之不尽"的玩法。
## 方块均为 RigidBody2D（默认 FREEZE_MODE_STATIC），被伤害后碎裂为破碎碎屑（不做掉落物）。

const BLOCK_SIZE := 40.0
const COLS := 12                 # 每层宽度（列数）
const VISIBLE_LAYERS := 30       # 每个柱子（列）的方块数：塔体向屏幕上方延申，营造"看不到顶"的无限感
const TOP_WORLD_Y := -180.0      # 楼顶槽位所在世界 y（Building 局部坐标 y=0）。最底层(槽位29)中心=980、底缘=1000=物理地面顶，塔脚稳立在地面上

# 材质阶梯：随累计摧毁数升档的"墙/窗/楼板"配置（堵 HP · 金币 · 演示色均按挡位）。
# 类型字符映射见 _type_key()： "#"→wall  "W"→window  "="→floor。
# threshold 触发累计摧毁数；旧塔不升档，只在补层/生成新方块时按当前挡位取材。
# 更高级越抗炸(hp 升)且越值钱(gold 升)，保证中后期挂机收益随进度增长。
# 数值口径（2026-08-25 起）：整个体系从"1"起步（借鉴 What the Buck!?）。
# 基础点击伤害 = 1（约等于最脆窗户 HP 3 的三分之一）；方块 HP 从个位数裸值铺起，
# 挡位越高越抗砸、更值钱。金币从一开始的 1~2 逐挡上涨。
const TIERS := [
	{
		"threshold": 0,
		"wall": { "material": "石膏板",   "hp": 5.0,  "gold": 2,  "color": Color(0.96, 0.95, 0.91) },
		"window": { "material": "普通玻璃", "hp": 2.0,  "gold": 1,  "color": Color(0.86, 0.92, 0.97) },
		"floor": { "material": "石灰石",   "hp": 7.0,  "gold": 2,  "color": Color(0.78, 0.76, 0.71) },
	},
	{
		"threshold": 100,
		"wall": { "material": "大理石",   "hp": 7.0,  "gold": 3,  "color": Color(0.90, 0.90, 0.93) },
		"window": { "material": "浮法玻璃", "hp": 3.0,  "gold": 2,  "color": Color(0.72, 0.88, 0.97) },
		"floor": { "material": "混凝土",   "hp": 9.0,  "gold": 3,  "color": Color(0.62, 0.63, 0.66) },
	},
	{
		"threshold": 450,
		"wall": { "material": "红砖",     "hp": 9.0,  "gold": 4,  "color": Color(0.70, 0.42, 0.34) },
		"window": { "material": "钢化玻璃", "hp": 5.0,  "gold": 3,  "color": Color(0.55, 0.78, 0.95) },
		"floor": { "material": "瓷砖",     "hp": 12.0, "gold": 5,  "color": Color(0.80, 0.81, 0.84) },
	},
	{
		"threshold": 1400,
		"wall": { "material": "花岗岩",   "hp": 12.0, "gold": 5,  "color": Color(0.60, 0.58, 0.56) },
		"window": { "material": "钢化玻璃", "hp": 5.0,  "gold": 4,  "color": Color(0.55, 0.78, 0.95) },
		"floor": { "material": "淬火高强钢", "hp": 16.0, "gold": 7,  "color": Color(0.55, 0.58, 0.64) },
	},
]

# 类型字符 → 挡位表键名映射。
func _type_key(type: String) -> String:
	match type:
		"#": return "wall"
		"W": return "window"
		"=": return "floor"
	return "floor"   # 兜底

# 血量档位 → 色调调节：血越高越深实厚重（抗炸感），血越低越发白偏脆。
# delta 作用于明度(V)，sat_scale 缩放饱和度。
const HP_TIERS := [
	{ "max": 3.5, "delta": 0.14, "sat_scale": 0.65 },  # 脆（窗 HP 2~3：普通/浮法玻璃）：发白偏淡
	{ "max": 8.0, "delta": 0.0, "sat_scale": 0.9 },   # 中等（墙/楼板 HP 5~7 区间、钢化玻璃 5）
	{ "max": INF, "delta": -0.15, "sat_scale": 1.1 },   # 坚固（HP 9+：墙、楼板高挡）：深实厚重
]

@warning_ignore("unused_private_class_variable")
var _block_texture: Texture2D   # 兜底白色渐变（找不到贴图时的占位纹理）

# 材质名 → 美术贴图文件名（assets/ui/*.png，不带扩展名）。
# 挡位表里的材质（石膏板/浮法玻璃/石灰石…）在此映射到真实美术素材。
const MATERIAL_FILE := {
	"石膏板":   "plaster",
	"普通玻璃": "glass",
	"浮法玻璃": "float_glass",
	"石灰石":   "limestone",
	"大理石":   "marble",
	"混凝土":   "concrete",
	"红砖":     "brick",
	"钢化玻璃": "tempered_glass",
	"瓷砖":     "ceramic",
	"花岗岩":   "granite",
	"淬火高强钢": "steel",
}

var _texture_cache: Dictionary = {}   # 材质名 → Texture2D（避免每条方块重复 Load）

# 材质质感类别（_material_category 判定，驱动对应 shader）。
const CAT_STONE := 0   # 石材/砖/混凝土/瓷砖等实心块
const CAT_METAL := 1   # 金属（淬火高强钢…）
const CAT_GLASS := 2   # 玻璃（普通/浮法/钢化…）

# 玻璃材质 → 基础血量：不同玻璃抗冲击性天然不同（普通玻璃最脆，钢化玻璃最硬）。
# 窗的 HP 以材质为准（同一玻璃无论哪个挡位血量恒定），挡位表 window.hp 仅为展示/兜底。
const GLASS_BASE_HP := {
	"普通玻璃": 2.0,
	"浮法玻璃": 3.0,
	"钢化玻璃": 5.0,
}

# —— 玻璃：半透明 + 一道斜向高光带（模拟玻璃反光）——
const GLASS_ALPHA := 0.55                     # 透明度（越低越透）
const GLASS_HIGHLIGHT_INTENSITY := 0.35        # 高光强度
const GLASS_SHADER_CODE := """
shader_type canvas_item;
uniform float alpha : hint_range(0.0, 1.0) = 0.55;
uniform float highlight_intensity : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.a *= alpha;
	// 斜向高光带：沿对角线从上左到下右，叠加在较亮区域上更明显
	float d = UV.x - UV.y;
	float streak = clamp(1.0 - abs(d - 0.38) * 4.0, 0.0, 1.0);
	streak = streak * streak;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float gloss = streak * lum * highlight_intensity;
	c.rgb = mix(c.rgb, vec3(1.0), gloss);
	COLOR = c;
}
"""

# —— 金属：竖向高光带 + 轻提对比，冷硬金属质感 ——
const METAL_SHEEN_STRENGTH := 0.30             # 高光强度
const METAL_CONTRAST := 0.12                   # 对比加成
const METAL_SHADER_CODE := """
shader_type canvas_item;
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.30;
uniform float contrast : hint_range(-0.5, 0.5) = 0.12;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	// 竖向金属高光带（偏左一道）
	float streak = clamp(1.0 - abs(UV.x - 0.28) * 6.0, 0.0, 1.0);
	streak = streak * streak * lum;
	c.rgb = mix(c.rgb, vec3(1.0), streak * sheen_strength);
	// 轻提对比，冷硬感
	c.rgb = clamp(c.rgb + (c.rgb - vec3(0.5)) * contrast, 0.0, 1.0);
	COLOR = c;
}
"""

# —— 程序化裂纹（P1，全材质共用一套，无需每材质手绘损坏图）——
# 观感定为"少而粗、从受击点辐射的主裂纹"：少量壮实的裂缝从受击点(origin)放射，
# 根部(受击点)宽、向边缘尖端收敛为细缝，受损(crack)增大时条数、长度、深度递增，
# 并在受击中心留一小块压实的碎裂暗区。只在 crack>0 时绘制；
# 玻璃/金属/石材共用，靠各自半透明/本色自然区分。
const CRACK_SPOKE_MIN := 2.0        # 主裂缝起始条数下限（最少 2 条）
const CRACK_SPOKE_RAND := 3.0       # 每个方块"种子随机"额外条数范围（0..2），让不同方块裂缝条数不重样
const CRACK_SPOKE_GROW := 2.0       # 受损(crack→1)额外追加的主裂缝条数
const CRACK_REACH_MIN := 0.30       # 裂纹起始最大长度（按块边长比例）
const CRACK_REACH_GROW := 1.1       # 受损时再向外伸展的增量（满破碎几乎贯穿整块）
const CRACK_DEPTH_MIN := 0.55       # 裂纹基础深度
const CRACK_DEPTH_GROW := 0.45      # 越靠近破碎越深的增长量
const CRACK_SHADER_CODE := """
shader_type canvas_item;
uniform float crack : hint_range(0.0, 1.0) = 0.0;
uniform vec2 origin = vec2(0.5, 0.5);   // 受击点(块局部 UV)
uniform float seed = 0.0;               // 每方块的随机种子：决定本条块的裂缝条数与朝向

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec4 out_col = vec4(0.0, 0.0, 0.0, 0.0);   // 满血无裂纹（透明，不遮材质）
	if (crack > 0.001) {
		// 由种子派生两个不相关的随机数：r0→条数、r1→整组朝向偏转（r0+TAU 把一个裂纹组整体转个方向）
		float r0 = fract(sin(seed) * 43758.5453123);
		float r1 = fract(sin(seed * 2.0) * 43758.5453123);
		vec2 v = (floor(UV * 20.0) + vec2(0.5)) / 20.0 - origin;
		float rad = length(v);
		// —— 主裂缝：从受击点辐射、每块条数与朝向随机 ——
		float a0 = atan(v.y, v.x);
		// 每道裂缝轻微蜿蜒（幅度受限，保持"少而直"的主体，不搅匀噪点）
		float wob = (vnoise(v * 2.5 + vec2(9.0, 3.0)) - 0.5) * 0.35;
		float a = a0 + wob + r1 * TAU;                    // 整组随机偏转，避免每个方块裂纹同角度
		float spokes = %f + floor(r0 * %f) + floor(crack * %f);   // 每块随机(2..4) + 受损追加
		float d = abs(fract(a / TAU * spokes - 0.5) - 0.5);  // 距最近裂缝轴的角度距离（d∈0..0.5，0=在中轴）
		// 每道裂缝宽度：根部略宽(冲击撕开口)，向外收敛成细缝——但根部收窄，避免全部糊成实心黑点
		float fat = mix(0.10, 0.038, clamp(rad * 2.2, 0.0, 1.0)) * mix(0.9, 1.35, crack);
		float spoke = 1.0 - smoothstep(fat * 0.5, fat, d);
		float reach = mix(%f, %f, crack);                 // 长度随受损伸向整块
		float lenfade = 1.0 - smoothstep(reach * 0.9, reach, rad);
		// 受击中心只留一枚很小的冲击点（凹痕），主体靠放射裂缝，不抢戏
		float crush = (1.0 - smoothstep(0.03, 0.12, rad)) * 0.7;
		float m = clamp(max(spoke * lenfade, crush), 0.0, 1.0);
		float depth = %f + crack * %f;
		float alpha = m * crack * depth * 1.2;
		out_col = vec4(0.02, 0.018, 0.016, alpha);
	}
	COLOR = out_col;
}
""" % [CRACK_SPOKE_MIN, CRACK_SPOKE_RAND, CRACK_SPOKE_GROW, CRACK_REACH_MIN, CRACK_REACH_GROW,
		CRACK_DEPTH_MIN, CRACK_DEPTH_GROW]

# —— 石材/砖/混凝土/瓷砖：上亮下暗，立体实心块感 ——
const STONE_TOP_LIGHT := 0.06                  # 顶部提亮
const STONE_BOTTOM_AO := 0.10                  # 底部压暗（模拟环境光遮蔽）
const STONE_SHADER_CODE := """
shader_type canvas_item;
uniform float top_light : hint_range(0.0, 0.3) = 0.06;
uniform float bottom_ao : hint_range(0.0, 0.3) = 0.10;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	// 上亮下暗：实心块的立体感
	float shade = 1.0 + top_light * (1.0 - UV.y) - bottom_ao * UV.y;
	c.rgb *= clamp(shade, 0.7, 1.2);
	COLOR = c;
}
"""

var _effect_materials: Dictionary = {}   # 材质类别 → ShaderMaterial（懒加载并复用）
var _crack_shader: Shader = null         # 裂纹 shader 资源（全局共享，ShaderMaterial 按方块各自持有以存独立 crack 值）


# 获取共享的裂纹 shader（只需编译一次）。
func _crack_shader_res() -> Shader:
	if _crack_shader == null:
		_crack_shader = Shader.new()
		_crack_shader.code = CRACK_SHADER_CODE
	return _crack_shader

# 按列托管：_cols[col] 为自上而下（index 0 = 该列当前顶层）的方块数组。
# 任意列方块数始终补足到 VISIBLE_LAYERS，楼体整体保持满高。
var _cols: Array = []            # Array[Array[BuildingBlock]]
var _pending_columns: Dictionary = {}


func _ready() -> void:
	_generate()


func _generate() -> void:
	var start_x := 960.0 - (COLS * BLOCK_SIZE) / 2.0   # 水平居中
	position = Vector2(start_x, TOP_WORLD_Y)           # Building 节点位置 = 楼顶槽位(y=0)
	_cols.clear()
	for c in range(COLS):
		_cols.append([])
	# 分帧生成：一整栋 360 块方块的实例化拆到多帧执行（每帧一批），
	# 避免"整楼一次性建好"在切场瞬间长时间占用主线程造成卡顿。
	await _generate_in_batches()
	print("BuildingSetup: 初始生成 %d 列 x %d 层" % [COLS, VISIBLE_LAYERS])


# 分帧生成全部方块：自下而上逐层生成（底部先就位，地面支撑与塌陷目标尽早可用），
# 每生成 GENERATION_BATCH 块就让出当前帧（await process_frame），把耗时摊到多帧。
const GENERATION_BATCH := 24          # 每帧生成的方块数（360 块 ≈ 15 批 ≈ 0.25s 内铺满）
var _generation_id := 0               # 生成代次：新一次生成自增；旧协程发现代次不符即中止

func _generate_in_batches() -> void:
	_generation_id += 1
	var token := _generation_id
	var made := 0
	for level in range(VISIBLE_LAYERS - 1, -1, -1):   # 自下而上：先底层后顶层
		var row := VISIBLE_LAYERS - 1 - level   # 原始行号（奇数行楼板）
		var is_floor := row % 2 == 1
		var pattern := _random_layer_pattern(is_floor)
		for c in range(COLS):
			var type: String = pattern[c]
			if type == ".":
				continue
			var block := _spawn_block(c, level, type, is_floor)
			_cols[c].append(block)
			made += 1
			if made % GENERATION_BATCH == 0:
				await get_tree().process_frame
				if token != _generation_id:
					return   # 期间被重置：放弃本批，避免与新一轮生成叠加
	print("BuildingSetup: 分帧生成完成，共 %d 块" % made)


# 重置楼体：先释放当前所有方块子节点（清掉旧塔 + 下落中/受击残留），再重新生成一栋满楼。
# 生成改成分帧（_generate → _generate_in_batches），本方法释放完即返回；
# 期间若再次 reset，_generation_id 代次守卫会让旧协程中止，不会叠加出新楼。
# 释放前统一用 is_instance_valid 校验，避免访问已 free 实例。
func reset() -> void:
	_pending_columns.clear()
	_falling_blocks = 0   # 旧塔直接释放（下落中不会落定回退），重新计数
	for child in get_children():
		if is_instance_valid(child):
			child.free()
	_generate()


# 在指定列 level(0=顶层) 放置一个方块并连接碎裂回调。
func _spawn_block(col: int, level: int, type: String, is_floor: bool) -> BuildingBlock:
	var block := RigidBody2D.new()
	block.name = "Block_%d_%d" % [col, level]
	block.position = Vector2(col * BLOCK_SIZE, level * BLOCK_SIZE)
	block.set_script(load("res://scripts/BuildingBlock.gd"))
	var bb: BuildingBlock = block
	bb.col = col
	bb.is_floor = is_floor
	bb.level = level
	bb.building = self
	bb.freeze = true                 # 默认 FREEZE_MODE_STATIC：先作为静态支撑
	# 按当前材质挡位取值（旧塔不升档：只在生成/补层时读取）
	var entry: Dictionary = TIERS[_current_tier()][_type_key(type)]
	# 玻璃 HP 由材质决定（普通<浮法<钢化，同一玻璃各挡位血量恒定），非玻璃材质回退挡位表 hp。
	var material: String = entry.material
	var block_hp: float = GLASS_BASE_HP.get(material, entry.hp)
	bb.hp = block_hp
	bb.max_hp = block_hp
	bb.gold_value = entry.gold

	# 碰撞体：40x40
	var shape := RectangleShape2D.new()
	shape.size = Vector2(BLOCK_SIZE, BLOCK_SIZE)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	bb.add_child(collision)

	# P2：视觉层容器。下落时"先蓄后发"的轻微旋转/摇摆只作用于此层（含材质 sprite 与裂纹覆盖层），
	# 物理槽位(block.position.y/freeze)、碰撞体与血条完全不受影响，落定时由方块把视觉层归正 → 精确回格。
	var visual := Node2D.new()
	visual.name = "VisualLayer"
	bb.add_child(visual)
	bb.visual_layer = visual

	# 部件贴图：优先加载真实美术素材；找不到则回退程序白渐变 + 纯色着色。
	# 真实贴图只做"亮度调制"（弱→亮、强→深），保留材质的天然配色（红砖/玻璃/金属…）。
	var sprite := Sprite2D.new()
	var base: Color = entry.color
	var jitter := 0.96 + randf() * 0.08
	var photo: Texture2D = _get_material_texture(entry.material)
	# P1：把材质贴图与"是否玻璃"一并下发给方块，供碎屑按材质上色/半透明（无贴图则留 null 回退纯色）。
	bb.debris_texture = photo
	bb.is_glass = _material_category(entry.material) == CAT_GLASS
	if photo != null:
		sprite.texture = photo
		_apply_block_render(sprite)
		sprite.modulate = Color(jitter, jitter, jitter)
		sprite.material = null   # 按材质类别加质感（玻璃/金属/石材）
	else:
		sprite.texture = _get_block_texture()
		sprite.modulate = _tint_by_hp(base, block_hp, jitter)
	bb.debris_color = _tint_by_hp(base, block_hp, jitter)   # 破碎碎屑沿用材质色，保持色彩关联
	visual.add_child(sprite)

	# 程序化裂纹覆盖层：材质之上叠一层暗色裂缝（P1，全材质共用同一套 shader）。
	# 随方块生成时就建好并绑定（不是破裂时才出现），满血无裂纹，血量下降由 update_crack() 驱动。
	# 每方块一块 40x40 Sprite2D，用统一 CRACK_SHADER_CODE；Shader 全局共享，ShaderMaterial 按块独立存 crack 值。
	var crack_sprite := Sprite2D.new()
	crack_sprite.name = "CrackOverlay"
	crack_sprite.texture = _get_block_texture()   # 仅作 40x40 载体，shader 走 UV 噪声，不采色
	crack_sprite.show_behind_parent = false       # 叠在材质之上
	crack_sprite.z_index = 1                      # 高于材质 sprite（0），低于分块外部的白闪(z=40)
	var crack_mat := ShaderMaterial.new()
	crack_mat.shader = _crack_shader_res()
	crack_mat.set_shader_parameter("crack", 0.0)
	crack_mat.set_shader_parameter("seed", randf() * 10.0)   # 每方块独立种子：裂缝条数/朝向各不相同
	crack_sprite.material = crack_mat
	visual.add_child(crack_sprite)
	bb.setup_crack_sprite(crack_sprite)   # 满血初始 crack=0，无裂纹

	# 血条：贴在方块顶部（局部上方居中），默认隐藏；开启鼠标拾取以支持悬停显示
	var healthbar: Node2D = load("res://scenes/HealthBar.tscn").instantiate()
	healthbar.name = "HealthBar"
	healthbar.position = Vector2(0.0, -BLOCK_SIZE / 2.0 - 6.0)   # 方块顶部上方，留约 6px 空隙
	bb.add_child(healthbar)
	healthbar.setup(block_hp)
	bb.input_pickable = true
	bb.mouse_entered.connect(healthbar.set_hovered.bind(true))
	bb.mouse_exited.connect(healthbar.set_hovered.bind(false))

	bb.shattered.connect(_on_block_shattered.bind(bb))
	add_child(bb)
	return bb


# 生成一层楼面模板（字符：# 墙  W 窗  = 楼板）。
# 楼板层全 "="；墙面层满墙 "#"，两端封墙、中部随机位置开 2~4 扇窗。
func _random_layer_pattern(is_floor: bool) -> String:
	if is_floor:
		return "=".repeat(COLS)
	var cells: Array[String] = []
	for i in range(COLS):
		cells.append("#")
	var windows := randi_range(2, 4)
	var placed := 0
	while placed < windows:
		var col := randi_range(1, COLS - 2)
		if cells[col] == "#":
			cells[col] = "W"
			placed += 1
	return "".join(cells)


# 某列的一块方块被砸碎后回调：从该列移除被碎方块。
# 无论本列同帧被毁掉多少块（范围锤/炸弹命中多块），都重新按"底部压实"布局：
# 存活的方块向底部压紧（各自唯一目标槽位，确定性下落，不散不重叠），
# 空缺因此只出现在顶部，随后由补层在楼顶补入 → 保证新方块总是从上面进来而非原地填在底部。
func _on_block_shattered(block: BuildingBlock) -> void:
	if not is_inside_tree():
		return
	var c := block.col
	if c < 0 or c >= _cols.size():
		return
	# 下落途中被炸碎的方块不会再落定：提前回收"正在下落"计数，避免崩塌计数泄漏。
	if block.is_falling():
		_falling_blocks = maxi(_falling_blocks - 1, 0)
	_cols[c].erase(block)
	# 注意：此回调可能在物理回调栈（炸弹爆炸/连锁伤害的 intersect_shape）中同步触发，
	# 压实与补层会实例化新刚体并改冻结/速度，在 flushing queries 阶段会报
	# "body_set_shape_disabled" 错误，故推迟到物理步结束后再执行重建。
	if not _pending_columns.has(c):
		_pending_columns[c] = _generation_id
		_deferred_rebuild_column.call_deferred(c, _generation_id)
	_queue_chain_feedback()   # 同瞬摧毁计数：聚合多种碎裂来决定 档2/档3 反馈（由手感中枢裁决）


# 推迟到物理步结束执行列重建（压实 + 补层），避免在物理回调/查询刷新期间改刚体状态。
func _deferred_rebuild_column(c: int, generation: int = -1) -> void:
	if generation >= 0:
		if int(_pending_columns.get(c, -1)) != generation:
			return
		_pending_columns.erase(c)
		if generation != _generation_id:
			return
	if not is_inside_tree():
		return
	_compact_column(c)
	_maybe_refill(c)


# —— 崩塌音：同时下落的方块数达到阈值时触发一次 ——
# 用"正在下落的方块总数"衡量崩塌规模：任意列压实/连锁塌陷时累计，落定/被炸碎时回退，
# 天然跨列聚合（炸弹炸塌多列会叠加计数），只有同时悬空的数量够大才响"哗啦"一声。
var _falling_blocks := 0               # 当前跨列正在下落的方块数
const COLLAPSE_FALL_THRESHOLD := 10# 同时下落 ≥ 该数量 → 触发崩塌音
var _collapse_cooldown_ms := -1000000  # 防连发冷却（真实时间）
const COLLAPSE_SOUND_COOLDOWN_MS := 800


# 崩塌规模达阈值且过冷却时播一次崩塌音（同一次连锁只响一声，避免刷屏）。
func _try_collapse_sound() -> void:
	if _falling_blocks < COLLAPSE_FALL_THRESHOLD:
		return
	var now := Time.get_ticks_msec()
	if now - _collapse_cooldown_ms < COLLAPSE_SOUND_COOLDOWN_MS:
		return
	_collapse_cooldown_ms = now
	SoundManager.play("collapse")


# —— 同瞬摧毁计数（档2/档3 汇总判定）——
# 每次方块碎裂唤起本回调，在 0.25s 真实时间窗口内累计计数；窗口结束时把收敛后的数量交给
# GameFeel.resolve_chain 决策：1~2 块 → 档2，≥3 块 → 档3。窗口用真实时间（忽略 time_scale），
# 这样慢动作/顿帧期间窗口仍按真实节奏收敛，不会因时间缩放而拖长导致误分组。
var _chain_count := 0
var _chain_flushing := false

func _queue_chain_feedback() -> void:
	_chain_count += 1
	if _chain_flushing:
		return
	_chain_flushing = true
	_flush_chain_feedback()


func _flush_chain_feedback() -> void:
	var timer := get_tree().create_timer(0.25, true, false, true)
	await timer.timeout
	if _chain_count <= 0:
		_chain_flushing = false
		return
	GameFeel.resolve_chain(_chain_count)
	_chain_count = 0
	_chain_flushing = false


# 把整列存活方块压实到底部：按"当前有效槽位"从高到低排序，依次分配给最底部（最高层号）的槽位，
# 目标槽位 != 当前槽位的方块触发下落；目标已就位的方块不动。空缺随之集中到顶部。
# 用 effective_level() 读取方块位置，即使下落到一半（level 未刷新）也能稳定计算，可容忍同帧多块被毁。
func _compact_column(c: int) -> void:
	if c < 0 or c >= _cols.size():
		return
	var blocks: Array[BuildingBlock] = []
	for i in range(_cols[c].size() - 1, -1, -1):
		var b: RigidBody2D = _cols[c][i]
		if not is_instance_valid(b):
			_cols[c].remove_at(i)
			continue
		blocks.append(b as BuildingBlock)
	blocks.sort_custom(
		func(a: BuildingBlock, k: BuildingBlock) -> bool:
			return a.effective_level() > k.effective_level()
	)
	var slot := VISIBLE_LAYERS - 1
	for b in blocks:
		if b.effective_level() != slot:
			if not b.is_falling():
				_falling_blocks += 1   # 只有"新开始下落"才计入，避免同块多次压实重复计数
			b.drop_to(slot)
		slot -= 1
	_try_collapse_sound()


# 某列的一块下落方块落定（下移到目标槽并定格）后回调：尝试补层。
func _on_block_settled(c: int) -> void:
	_falling_blocks = maxi(_falling_blocks - 1, 0)   # 一块落定 → 正在下落的方块少一块
	_maybe_refill(c)


# 当该列没有任何方块仍在"下落"时，把该列在楼顶补满（无限塔）。
func _maybe_refill(c: int) -> void:
	if c < 0 or c >= _cols.size():
		return
	# 同帧新破坏的压实尚未执行：落定回调不能抢先把下方空洞原地补回。
	if _pending_columns.has(c):
		return
	# 清理该列可能已失效的引用
	for i in range(_cols[c].size() - 1, -1, -1):
		if not is_instance_valid(_cols[c][i]):
			_cols[c].remove_at(i)
	for b in _cols[c]:
		var bb: BuildingBlock = b as BuildingBlock
		if bb != null and bb.is_falling():
			return   # 还有方块在落下，等它落定再补
	_refill_column(c)


# 将该列补满至 VISIBLE_LAYERS 层（无限塔）。只补"缺席的层级"，自顶层（level 0）向上找空缺，
# 新块楼板/墙面按层级奇偶决定，维持隔层楼板的楼层感；已存在的方块不变。
func _refill_column(c: int) -> void:
	if c < 0 or c >= _cols.size():
		return
	var occupied := {}
	for b in _cols[c]:
		var bb: BuildingBlock = b as BuildingBlock
		if bb != null:
			occupied[bb.effective_level()] = true
	for level in range(VISIBLE_LAYERS):
		if occupied.has(level):
			continue
		var block := _spawn_block(c, level, _refill_type(_level_is_floor(level)), _level_is_floor(level))
		_cols[c].append(block)


# 某层级是否为楼板层（隔层楼板：奇数层是楼板），与初始生成的第 0 层到 (VISIBLE_LAYERS-1) 层一致。
func _level_is_floor(level: int) -> bool:
	return level % 2 == 1


# 补层方块类型：楼板层用楼板；墙面层在墙/窗间随机。
func _refill_type(is_floor: bool) -> String:
	if is_floor:
		return "="
	return "W" if randf() < 0.25 else "#"


# 供全自动锤子使用的取块接口：返回当前最低（最靠近地面）的存活方块，用于自动瞄准。
func get_lowest_alive_block() -> RigidBody2D:
	var best: RigidBody2D = null
	var best_y := -INF
	for c in _cols:
		for i in range(c.size() - 1, -1, -1):
			var b: RigidBody2D = c[i]
			if not is_instance_valid(b):
				c.remove_at(i)   # 兜底清理已释放节点
				continue
			if b.global_position.y > best_y:
				best = b
				best_y = b.global_position.y
	return best


# 由累计摧毁数反查当前材质挡位（默认挡 0）。
# 只在补层/生成新方块时调用：旧塔不升档，下落中的方块也算旧，不回溯。
func _current_tier() -> int:
	var n := GoldManager.get_destroyed_count()
	for i in range(TIERS.size() - 1, -1, -1):
		if n >= TIERS[i].threshold:
			return i
	return 0

# 按血量档位对部件主色做明度/饱和度调节：血越高越深实厚重，血越低越发白偏脆。
func _tint_by_hp(base: Color, hp_value: float, jitter: float) -> Color:
	var tier: Dictionary = HP_TIERS.back()
	for t in HP_TIERS:
		if hp_value <= t.max:
			tier = t
			break
	var v: float = clampf((base.v + tier.delta) * jitter, 0.0, 1.0)
	var s: float = clampf(base.s * tier.sat_scale, 0.0, 1.0)
	return Color.from_hsv(base.h, s, v)


# 亮度调制：仅改变明度（保留贴图本色用于 modulate），按血量挡位弱→亮、强→深。
func _brightness_modulate(base: Color, hp_value: float, jitter: float) -> Color:
	var v: float = _tint_by_hp(base, hp_value, 1.0).v * jitter
	v = clampf(v, 0.0, 1.0)
	return Color(v, v, v)


# 加载指定材质名对应的美术贴图；缓存避免重复 Load。找不到返回 null。
func _get_material_texture(material: String) -> Texture2D:
	if _texture_cache.has(material):
		return _texture_cache[material]
	var file: String = MATERIAL_FILE.get(material, "")
	var tex: Texture2D = null
	if not file.is_empty():
		tex = load("res://assets/presentation/materials/%s.png" % file) as Texture2D
	_texture_cache[material] = tex
	return tex


# 由材质名判定材质质感类别（玻璃优先于钢：钢化玻璃仍算玻璃）。
func _material_category(material: String) -> int:
	if material.contains("玻璃"):
		return CAT_GLASS
	if material.contains("钢") or material.contains("金属"):
		return CAT_METAL
	return CAT_STONE


# 获取某材质对应的质感 ShaderMaterial；按类别懒加载并复用（只需编译一次）。
func _get_material_effect(material: String) -> ShaderMaterial:
	var cat := _material_category(material)
	if _effect_materials.has(cat):
		return _effect_materials[cat]
	var code: String
	match cat:
		CAT_GLASS: code = GLASS_SHADER_CODE
		CAT_METAL: code = METAL_SHADER_CODE
		_:         code = STONE_SHADER_CODE
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	match cat:
		CAT_GLASS:
			mat.set_shader_parameter("alpha", GLASS_ALPHA)
			mat.set_shader_parameter("highlight_intensity", GLASS_HIGHLIGHT_INTENSITY)
		CAT_METAL:
			mat.set_shader_parameter("sheen_strength", METAL_SHEEN_STRENGTH)
			mat.set_shader_parameter("contrast", METAL_CONTRAST)
		_:
			mat.set_shader_parameter("top_light", STONE_TOP_LIGHT)
			mat.set_shader_parameter("bottom_ao", STONE_BOTTOM_AO)
	_effect_materials[cat] = mat
	return mat


# 让 40x40 方块从大贴图里裁一块正方形，等比例缩放到方块尺寸（不拉伸失真）。
# 每块随机取位，让相邻方块之间也有细微纹理变化，看起来不那么呆板。
func _apply_block_render(sprite: Sprite2D) -> void:
	var tw := sprite.texture.get_width()
	var th := sprite.texture.get_height()
	var crop := mini(tw, th)
	var ox := randi_range(0, maxi(tw - crop, 0))
	var oy := randi_range(0, maxi(th - crop, 0))
	sprite.region_enabled = true
	sprite.region_rect = Rect2(ox, oy, crop, crop)
	sprite.scale = Vector2(BLOCK_SIZE / float(crop), BLOCK_SIZE / float(crop))


# 生成一张可复用的 40x40 白色底纹理（配合 modulate 上色，所有方块共用）。
func _get_block_texture() -> Texture2D:
	if _block_texture == null:
		var t := GradientTexture2D.new()
		t.width = int(BLOCK_SIZE)
		t.height = int(BLOCK_SIZE)
		t.fill = GradientTexture2D.FILL_SQUARE
		t.fill_from = Vector2.ZERO
		t.fill_to = Vector2(BLOCK_SIZE, BLOCK_SIZE)
		var g := Gradient.new()
		g.colors = PackedColorArray([Color.WHITE, Color(0.88, 0.88, 0.88)])
		g.offsets = PackedFloat32Array([0.0, 1.0])
		t.gradient = g
		_block_texture = t
	return _block_texture
