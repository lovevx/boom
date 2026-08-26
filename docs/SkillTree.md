# 单局技能树（Upgrade Skill Tree）· 放射状布局

> 升级面板（`UpgradePanel`）里的技能树：单局内用**金币**购买、实时生效、转生/重开时全部清零（非永久）。对应文档 [SPEC.md](file:///e:/godotproject/boomame/docs/SPEC.md)「升级项」小节与 [Reincarnation.md](file:///e:/godotproject/boomame/docs/Reincarnation.md)（永久树，另一套）。
>
> 本文档定位：**单局技能树的唯一规格来源**。数值成长公式遵循 [Growth_Model.md](file:///e:/godotproject/boomame/docs/Growth_Model.md)（单局层以加法为主）。

## 一、定位与视觉风格

### 1.1 布局：放射状（Radial Layout）

- **中心枢纽（Hub）**：屏幕中央的圆形核心节点，代表「升级中枢」，作为所有分支的起点。
- **四方向分支**：从 Hub 向外发散四条独立的方向分支（Branch），每条代表一类能力提升：

| 方向 | 角度（相对屏幕中心） | 颜色主题 | 能力 |
| --- | --- | --- | --- |
| ↑ 上（北） | −90° | 橙 Hammer | 锤子：攻速 / 伤害 / 范围 / 全自动 / 暴击 |
| → 右（东） | 0° | 金 Gold | 金币：倍率（当前单点；预留扩展位） |
| ↓ 下（南） | +90° | 红 Bomb | 炮台：发射器数量 / 伤害 / 范围 / 速率 / 连锁 / 散射 |
| ← 左（西） | +180° | 蓝 Build | 建筑：下落速度（当前单点；预留扩展位） |

- 每条分支上的节点**沿方向轴线性排列**（不在同方向横向分叉）；同分支横向分叉（如同属"锤子二阶"的多节点）**仍沿方向轴并置**（等距排列），不单独分叉。

### 1.2 视觉风格（Pixel Art Retro 16-bit）

- **背景**：深绿色底色 `#0f1f0f` + 微弱噪点纹理（Pixel noise texture，运行时程序化生成，无资源文件）。
- **节点外框**：**八边形（Octagon）** 线框（粗 3px），分两种状态：
  - **未解锁**：灰色外框 `#808080`，图标暗淡
  - **已解锁 / 已点亮**：金橙色外框 `#f0c030`，图标明亮
- **节点图标**：当前用**占位文字 / 简单矢量图形**，后续替换为 PNG 像素素材。图标尺寸与八边形内切。
- **连线**：Hub → 首节点、节点 → 高阶节点的**放射状直线**
  - 未解锁分支：灰色 `#606060`、虚线
  - 已解锁分支：金橙色 `#f0c030`、实线、发光（Tween 闪烁）
- **升级粒子**：绿色 ↑ 箭头（`▲` / `up` 图标），沿方向轴"向上飘"表达升级方向。使用 `Label` + Tween 实现，无需资源。
- **中心 Hub**：同心圆双层圆环 + 中心点标记，激活时中心环缓慢旋转（Tween rotation）。

### 1.3 风格参考（仅描述，不生成资源）

参考提示词（用户提供）：
> Pixel art game UI, skill tree interface, radial layout, central hub connected to surrounding nodes by lines. Dark green background with subtle noise texture. Octagonal icon frames with thick borders. Icons inside: dollar bills, gold coin, yellow tent, purple potion flask. Green upward arrows indicating upgrades. One connection line is highlighted in bright orange/gold, others are grey. Retro 16-bit style, clean vector-like pixels, high contrast, flat design, game asset, isolated on background.

**本迭代**：用代码绘制八边形、连线、粒子与占位图标；美术素材到位后只需替换各节点 `icon_texture` 字段。

## 二、节点结构与分支排布

### 2.1 通用数据结构（代码用）

每个节点记录：

```
{
  id: String,           // 唯一 id，如 "hammer_speed"
  branch: String,       // "hammer" | "gold" | "bomb" | "build"
  tier: int,            // 1=基础(靠Hub) / 2=进阶 / 3=高阶(最外)
  slot_in_tier: int,    // 同tier中的序号(1..N)，决定横向并置位置
  distance: float,      // 距Hub的像素距离（沿分支方向轴）
  color: Color,         // 分支主题色
  icon_texture: String, // 占位icon文字，如 "锤" / "$" / "炮"；未来替换为纹理
  title: String,        // 节点名称（悬停/卡片显示）
  req: Array[String],   // 前置节点 id 列表；空=无前置
  mechanic_gate: String // 机制门（仅机制节点）:"crit"|"chain"|"scatter"|""
}
```

- **分支排布计算**：每条分支的基方向 = `angle_map[branch]`（上/右/下/左）。节点位置 = `hub_center + distance × direction_vector + slot_offset × perpendicular_vector`。
- **同tier多节点**（如锤子线的速度/伤害/范围）沿**垂直于分支方向**横向并置，间距 80px。

### 2.2 四大分支定义

#### 锤子分支（Hammer，↑ 上，橙）

| tier | id | slot | distance | icon | title | 前置 | 上限 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | hammer_speed | 1 | 200 | ⚡ | 锤子速度 | 无 | 3 级（百分比） |
| 1 | hammer_damage | 2 | 200 | ⚔ | 锤子伤害 | 无 | 3 级（百分比） |
| 1 | hammer_range | 3 | 200 | ◎ | 锤子范围 | 无 | 5 级（绝对值） |
| 3 | crit_chance | 1 | 520 | ✦ | 暴击几率 | hammer_damage ≥ 2 + 转生≥1 | 3 级 |
| 3 | crit_mult | 2 | 520 | ✹ | 暴击伤害 | hammer_damage ≥ 2 + 转生≥1 | 3 级 |

> **全自动锤不在单局技能树**，仅由转生永久树「初始熟练」提供（见 Reincarnation.md）。

#### 金币分支（Gold，→ 右，金）

| tier | id | slot | distance | icon | title | 前置 | 上限 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | coin_multiplier | 1 | 200 | $ | 金币倍率 | 无 | 5 级 |
| 1 | coin_base | 2 | 200 | 💰 | 基础金币 | 无 | 5 级（绝对值） |

> **金币倍率**（×0.5/级，5 级）与**基础金币**（+5/级，5 级）**同级并置**，互不依赖。基础金币加进击破基底 `gold_value + 转生击破金币 + 单局基础金币`，再 × 金币倍率 → 形成"加值 + 倍率"双层。

#### 建筑分支（Build，← 左，蓝）

| tier | id | slot | distance | icon | title | 前置 | 上限 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | building_drop_speed | 1 | 200 | ⬇ | 下落速度 | 无 | 3 级（百分比） |
| 2 | _(预留)_ | — | — | — | 待新增 | — | — |

#### 炮台分支（Bomb，↓ 下，红）

| tier | id | slot | distance | icon | title | 前置 | 上限 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | bomb_launcher | 1 | 200 | 💣 | 发射器数量 | 无 | 5 档（0..4） |
| 2 | bomb_damage | 1 | 360 | 🗡 | 炸弹伤害 | bomb_launcher ≥ 1 | 5 级（绝对值） |
| 2 | bomb_radius | 2 | 360 | ◯ | 炸弹范围 | bomb_launcher ≥ 1 | 5 级（绝对值） |
| 2 | bomb_rate | 3 | 360 | ⏱ | 发射速率 | bomb_launcher ≥ 1 | 3 级（百分比） |
| 3 | chain | 1 | 520 | ⛓ | 连锁伤害 | bomb_damage ≥ 2 + 转生≥2 | 3 级 |
| 3 | scatter | 2 | 520 | ✸ | 散射炮 | bomb_damage ≥ 2 + 转生≥3 | 3 级 |

> 上限口径：**基础数值/绝对值 → 5 级**；**百分比/倍率 → 3 级**。炮台数量为独立 0..4 表，总额仍由转生次数接管。

### 2.3 节点尺寸

- 八边形外框：外接圆半径 34px（对边 68px）
- Hub 节点：半径 50px
- 分支节点间距：同 tier 横向 80px，不同 tier 径向 160px

## 三、状态与前置规则

### 3.1 三态判定

每个节点 UI 与交互有三态，由 `UpgradeManager.is_node_state(nid)` 决定：

| 状态 | 条件 | 呈现 |
| --- | --- | --- |
| 已点亮（Lit） | `node_level > 0` | 金橙色外框，连线高亮发光 |
| 可购买（Available） | `req 全部满足` 且 `未达满级` | 灰色外框，可点击，弹出卡片显示"升级" |
| 未解锁（Locked） | `req 未满足` | 灰色外框 + 🔒 图标，弹出卡片显示"需先解锁：…" |

### 3.2 前置规则

- 每节点 `req` 为有序列表，全部满足才"可购买"。
- 机制节点（暴击/连锁/散射）额外受 `ReincarnationManager.is_mechanic_unlocked(mechanic_gate)` 门控；未通过门时，即便数值前置满足也视为锁定。
- **Hub 本身**无购买状态，始终高亮，作为纯视觉起点。

### 3.3 判定接口（统一出口）

`UpgradeManager.is_node_state(nid)` 返回：

```
{
  level: int,
  max_level: int,
  state: "lit" | "available" | "locked" | "maxed",
  reason: String,    // 锁定原因（锁定态才填）
  mechanic_gate: String
}
```

面板所有 UI 刷新走这一个接口，不再散落 `req` lambda。

## 四、UI / 代码实现要点

### 4.1 背景

- 用 `ColorRect`（深绿 `#0f1f0f`）作为底
- 程序化噪点：`_make_noise_layer()` 用 `Image.create()` 生成 256×256 随机亮暗像素 → `ImageTexture` → `TextureRect` 铺满，`modulate.a=0.25` 压暗
- 噪点生成一次缓存，不每帧重绘

### 4.2 Hub（中心枢纽）

- 绘制：`_draw_hub()`，用 `_tree.draw_colored_polygon` 画双层圆环（半径 50 / 44）+ 中心点
- 动画：`hub_ring.rotation += 0.005` 每帧，或 Tween 循环

### 4.3 分支连线

- `_draw_branch_links()` 按分支 `_links` 列表绘制
- 锁定分支：灰色 + `draw_line` 虚线（用多段短划实现虚线，Godot 4 `draw_line` 无原生 dash）
- 激活分支：金橙色 + 略宽（3px）+ 每帧 alpha 脉动（Tween 0.6↔1.0 循环）
- 连线绘制在独立 `_draw_layer` Control 上，`draw.connect(_draw_branch_links)` 驱动

### 4.4 八边形节点

- `_make_octagon(d)`：创建 `Control`，尺寸 `68×68`，`hex.draw.connect(func(): _draw_octagon_frame(hex, d))` 绘制外框
- 内放：占位 `Label`（显示 icon 文字，如 "⚡"）+ 等级 `Label`（右下角）+ 锁定 `Label`（🔒，默认隐藏）
- 点击 → 弹出升级卡片（沿用现有 popup 逻辑，但卡片位置按 radial 坐标换算）

### 4.5 升级粒子（绿色 ↑ 箭头）

- `_spawn_up_arrow(branch_start, branch_dir)`：在激活分支起点生成 Label（文字 "▲" / "↑"），Tween 沿 `branch_dir` 方向向上飘 200px 后自动消失
- 时机：**等级 +1 时一次性**生成（不是持续粒子），配合现有"+1 飘字/光爆/粒子"反馈
- 颜色：绿色 `#4caf50`，尺寸 16px

### 4.6 弹出升级卡片（Radial 适配）

- 弹出时位置根据节点 `center` 计算，用 `clampf` 确保卡在面板边界内
- 未解锁时卡片显示完整前置列表（由 `is_node_state` 返回的 `reason` 填充）
- 其余交互沿用现有逻辑（点击空白关闭 / 等级显示 / 效果预览 / 升级按钮）

## 五、数据流 / 接线

### 5.1 `UpgradeManager.gd`

- 新增 `NODE_DEFS` 字典（放射状布局节点目录，见 2.2）
- 新增 `get_node_state(nid)`：聚合等级 + 前置 + 机制门判定，返回 3.3 结构
- 保留原有 `get_*_level() / get_*_cost() / upgrade_*()` 作为"等级→数值"映射，不改变数值曲线

### 5.2 `UpgradePanel.gd`

- `_build_nodes()` 改为"放射状定位"：按 `NODE_DEFS` 的 `branch/tier/slot/distance` 计算坐标
- `_draw_tree()` 改为 `_draw_branch_links()`：按分支绘制 Hub→tier1、tier1→tier2、tier2→tier3 连线
- 状态刷新从散落 `req` lambda 改为统一读取 `UpgradeManager.get_node_state(nid)`
- 加点反馈在现有基础上，追加 `_spawn_up_arrow()` 沿分支方向飘绿色箭头

### 5.3 美术素材替换

- 节点当前用 `icon_texture` 字段存**占位文字**（Label 渲染）
- 美术 PNG 到位后，只需将 `icon_texture` 替换为 `icon_texture: Texture2D`，把 `Label` 换为 `TextureRect`，位置尺寸不变
- 代码中统一用 `_draw_node_icon(node_control, icon_source)` 工厂方法封装，替换成本低

## 六、数值 / 节奏

- **本迭代不动数值**：节点等级表、费用表、每级增量全部沿用 [UpgradeManager.gd](file:///e:/godotproject/boomame/scripts/UpgradeManager.gd) 现有值
- 变动仅限**结构（放射布局）**与**状态判定（统一 `get_node_state`）**

## 七、Non-goals（本迭代不做）

- 不做**新增节点**（金币分支 / 建筑分支扩展归下迭代）
- 不做**技能点货币**（仍用金币购买）
- 不做**全局跨分支金字塔**（分支间独立）
- 不做**分支内同级节点的分叉连线**（同 tier 节点沿主方向轴并置，不画 Y 型分叉）
- 不做美术素材导入（本迭代全部用矢量 + 占位文字，素材到位后替换）
- 不做**新机制**（暴击/连锁/散射的机制门保留现状）

## 八、关联文档

- [SPEC.md](file:///e:/godotproject/boomame/docs/SPEC.md)「升级项」：数值基线
- [Growth_Model.md](file:///e:/godotproject/boomame/docs/Growth_Model.md)：单局层数值成长公式
- [Reincarnation.md](file:///e:/godotproject/boomame/docs/Reincarnation.md)：机制门（crit/chain/scatter 转生门槛）
- [SkillTree.md（永久）](file:///e:/godotproject/boomame/docs/Reincarnation.md#五永久技能树三大方向)：另一棵树（转生永久），本文档与其独立
- [UpgradePanel.gd](file:///e:/godotproject/boomame/scripts/UpgradePanel.gd) / [UpgradeManager.gd](file:///e:/godotproject/boomame/scripts/UpgradeManager.gd)：现行实现，本次重构对象