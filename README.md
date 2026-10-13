# Boomame

一款 2D 休闲「破坏 + 挂机」小游戏（Godot 4.7 个人项目）：

**锤子砸楼 → 赚金币 → 升级锤子与经济 → 解锁自动轰炸炮台 → 炸更猛、赚更多、越玩越省力。**

核心是"手动破坏逐步让位给自动化"的成长闭环：你一开始一锤一锤砸，中期解锁自动炮台持续轰炸，后期靠升级和转生让破坏越来越猛、越来越省力。

> 求职作品集项目，用于展示从**玩法设计 → 数值平衡 → 工程实现 → 试玩迭代**的完整闭环能力。详细设计文档见 [docs/](./docs/)。

---

## 试玩 / 演示

- **演示视频**：[当前美术与自动轰炸演示](https://lovevx.github.io/my-work/videos/boomame.mp4)
- **Windows 版**：[下载最新试玩包](https://github.com/lovevx/boom/releases/latest)（无需安装 Godot）
- **作品集**：[项目介绍、截图与迭代记录](https://lovevx.github.io/my-work/works/boomame.html)
- **源码运行**：用 [Godot 4.7](https://godotengine.org) 打开本目录，按 `F5` 运行。

> 建议先看 30 秒演示视频 / 自录 GIF：先感受「First 30s」新手闭环 + 首炸爽感。视频分镜脚本见 [PORTFOLIO.md](docs/PORTFOLIO.md) 第六节。

---

## 核心玩法

| 阶段 | 玩家做的事 | 系统承接 |
| --- | --- | --- |
| 开局 | 用锤子点击建筑方块，把它砸碎成碎屑 | `Hammer` → `BuildingBlock` → `Debris` |
| 经济 | 砸出金币，用金币升级 | `GoldManager` + 升级面板 |
| 进阶 | 解锁自动轰炸炮台 | `LauncherManager` → `BombLauncher` → `BombProjectile` |
| 挂机 | 炮台自动轰炸、经济自动增长、越玩越省力 | 升级 + 数值增长模型 |
| 转生 | 单局归零换取永久加成 | `ReincarnationManager` |

- 破坏反馈统一做成**破碎/粉碎**（碎屑飞溅），不做掉落效果。
- 建筑按列维护唯一槽位，中层被砸碎后上方方块会**加速下落至新槽位**；落定后仅从楼顶补层，保持无限塔。

## 已实现系统（均实装可玩）

- 无限层破坏式建筑（确定性槽位塌落、自动补层、材质贴图与裂纹 shader）
- 锤子挥砸 + 震屏 + 破碎特效 + 金币弹出
- 自动轰炸炮台（冷却/自瞄/抛射/爆炸），同步音效
- 升级面板（技能树式，hover 显示、点击直接升级）
- 金币经济与数值滚动、伤害数字
- 新手引导（动作驱动分步提示）
- 屏幕切换碎块转场特效
- 转生 / 存档 / 设置 / 测试面板等后段框架
- 生涯统计（主菜单展示跨局累计：击破方块数量、总获取金币）

## 技术栈

- 引擎：**Godot 4.7.2**（GL Compatibility），2D，桌面端优先
- 分辨率：1920×1080（`canvas_items` 拉伸，适配窗口缩放）
- 结构：Autoload 单例（经济/升级/音效/转场/存档/转生）+ 场景组合（Main / MainMenu）
- 性能优化：建筑方块**分帧实例化**（每帧 24 块 × 15 批）消除切换场景时主线程卡顿

## 目录结构

```
boomame/
├─ assets/       # 美术 / 音效 / BGM 素材
├─ docs/         # 设计文档（GDD / 数值 / 体验 / 拆解）
├─ scenes/       # Godot 场景（Main / MainMenu / 各弹窗）
├─ scripts/      # GDScript 逻辑（按模块独立文件）
├─ project.godot
└─ README.md
```

## 设计文档入口

| 求职作品集材料（简历段/面试讲法/复盘/video 分镜） | [docs/PORTFOLIO.md](docs/PORTFOLIO.md) |
| 完整 GDD（标准框架 + 开发过程叙事） | [docs/GDD.md](docs/GDD.md) |
| 我用 AI 提效的工作流与案例 | [docs/AI_Workflow.md](docs/AI_Workflow.md) |
| 想了解 | 看这里 |
| --- | --- |
| 整体规划 / 怎么读文档 | [docs/_index.md](docs/_index.md) |
| 设计理念与迭代记录 | [docs/EXPERIENCE.md](docs/EXPERIENCE.md) |
| 数值平衡与完整 Demo（20–30 分钟目标） | [docs/Demo_Pacing.md](docs/Demo_Pacing.md)、[docs/Numeric_Balance.md](docs/Numeric_Balance.md) |
| 系统分工与依赖 | [docs/MODULES.md](docs/MODULES.md) |

## 状态说明

- 2026-10-13：场景配色统一，并增加楼体窄侧面、整栋受光、固定窗带、薄楼板及随破坏变化的断面。181 项专项与回归检查通过。见 [楼体表现说明](docs/Building_Depth.md)、[前后对比页面](artifacts/building-depth/comparison.html)、[13 秒实机录像](artifacts/building-depth/building-depth.mp4)。HTML 可下载后在本地打开；录像使用测试进度加速展示。

- 2026-10-13：Demo 增加四轮工程目标、试玩计时和散射工程完成提示，并校准首炮、基础爆破和转生门槛；完成后可继续游玩。20–30 分钟为休闲混合试玩目标，自动引擎数据与真人待验收项见 [节奏报告](docs/Demo_Pacing.md)。

- 2026-10-09：同步美术 / 音效 / UI、技能树与转生数值更新，修复受击回弹与下落动画竞争、落定时补层抢先填洞及重复破碎结算。见 [本次更新记录](docs/Release_2026-10-09.md)。
- 方块下落回归检查 11 项通过，覆盖单块破坏、范围锤、炸弹连锁、下落途中再次破坏及同帧重复命中。结果见 [验证报告](artifacts/collapse/verification.json)。

- 当前是可玩的垂直切片（vertical slice），核心循环完整可跑通。
- 转生 / 永久技能树已实装（面板、RP 结算、存档槽全链路可用）；离线收益等属"已设计、暂未实现"的长线方向，见各设计文档。
- 美术素材为工程演示用素材，非原创商业美术（如需商用请替换）。

## 联系方式

[李伟翔 · 游戏策划作品集](https://github.com/lovevx/my-work)
