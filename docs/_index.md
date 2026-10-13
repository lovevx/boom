# Bible Index

> 每次开始新对话前，先读这个文件；
> 按任务匹配后只读对应的 1–2 个模块文件。

## 任何修改都不能违反（不变量）

1. 核心循环必须保留：砸/炸 → 赚金币 → 升级 → 解锁炮台 → 炸更猛，动词不得删减。
2. 可调数值统一通过脚本顶部 `@export` 暴露，并同步维护 SPEC.md 的数值边界表；禁止在函数体内散落硬编码 magic number。
3. 依赖必须单向：BombProjectile → BuildingBlock → Debris；禁止 Building 系反向调用 LauncherManager / BombLauncher，避免循环依赖。
4. 越界清理阈值（x<-100 / x>2020 / y>1200）在 BuildingBlock 与 Debris 各有一份副本，改动需两处同步。
5. 新增节点/脚本需遵循现有 snake_case + `class_name` 风格，并在 MODULES.md 模块表登记。
6. 永久进度（转生点/永久节点/转生次数）独立存档，单局 `reset()` 不得清空永久进度；单局升级归 `UpgradeManager`，永久加成归 `ReincarnationManager`，二者状态不得交叉持有。详见 Reincarnation.md。

## 速查表：你要改什么，读哪个文件

| 你要改什么 | 读哪个文件 | 一句话提示 |
| --- | --- | --- |
| 确认 MVP 范围 / 哪些不做 | MVP_Scope.md, SPEC.md | Non-goals 是禁区，不得越界 |
| 判断功能优先级 | Priority_Backlog.md | 先看 P0/P1/P2/P3 定义再排期 |
| 调数值（炸弹/爆炸/方块） | SPEC.md | 数字改动同步回脚本 @export |
| 调数值增长模型 / 加法×乘法 | Growth_Model.md | 先确认属性分类与双层公式，再动 getter |
| 调玩法手感 / 体验味道 | EXPERIENCE.md | 先读关键词与反例，再动手 |
| 写代码 / 加新模块 | MODULES.md | 先看依赖图，避免循环依赖 |
| 动核心循环 | Core_Loop.md | 循环的每个动词必须有功能承接 |
| 构思 / 实现主界面 | MainMenu.md | 先确认界面元素与 Non-goals 边界，再动场景 |
| 做场景切换过场（碎块下落） | ScreenTransition.md | 先读效果目标与关键数值，再动 MainMenu 切场调用 |
| 调方块材质 / 莫氏硬度数值 | Material_Tiers.md | 先读分档表与 4.4 设计规则，再动 BuildingSetup TIERS |
| 做转生 / 永久加成 | Reincarnation.md | 先确认转生点公式与三大方向，再动 UpgradeManager / GoldManager |
| 调单局技能树（升级面板）/ 节点前置层级 | SkillTree.md | 先确认每线垂直多级树与统一前置规则，再动 UpgradePanel / UpgradeManager |
| 校准 20–30 分钟完整 Demo（首炮/三次转生/散射收尾） | Demo_Pacing.md, Numeric_Balance.md | 模型、引擎流程、真人试玩分别报告；先校准阶段目标，再改费用和效果 |
| 借鉴同类破坏型增量的设计方法 | Reference_WhatTheBuck.md | 读 What the Buck?! 公开设计 → 六条方法映射；只学方法、数值自压 |
| 看完整 GDD（含设计决策与迭代过程） | GDD.md | 求职/整体视角：标准 GDD 框架 + 每章过程叙事；单点细节再按表查 |
| 讲"我用 AI 提效"的作品集案例 | AI_Workflow.md | 求职用：AI 在开发全流程的使用、方法、边界与真实案例 |
| 记录决策 / 测试结论 | EXPERIENCE.md 测试记录表 | 回填日期 + 一句话结论，供下轮迭代 |
## Demo 内容扩展

- [Demo_Expansion.md](Demo_Expansion.md)：24 个单局节点、21 个永久节点、三条成长路线、前三次转生内容和验证记录。

- UI、新手工程与原创炮素材：[UI_Refresh.md](UI_Refresh.md)。
- 破坏特效、炮弹尾迹与动态反馈：[Motion_Feedback.md](Motion_Feedback.md)。
- 场景配色、材质衔接、接地阴影与超宽屏：[Scene_Art_Harmony.md](Scene_Art_Harmony.md)。
- 楼体 2.5D、连续窗带、薄楼板和破坏断面：[Building_Depth.md](Building_Depth.md)。
