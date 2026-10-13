# UI、新手工程与原创液压炮（2026-10-09）

本轮沿用工地像素风，统一深蓝灰面板、工程黄主操作与青色提示。成长、伤害、费用、解锁条件及 RP 计算沿用当前工作区实现。

## 玩家操作

- HUD 将工程目标、合同进度和拆楼产出放入工程卡；技能树为主按钮，转生可结算时显示 RP 收益。
- 技能树保留 24 节点。`＋` 表示可购买，`缺` 表示金币不足，`锁` 表示前置或转生门槛未满足，`✓` 表示满级，数字表示当前等级/上限。悬停显示管理器提供的当前效果、下级效果、实际费用与原因。
- 转生保留 21 个永久节点，各列独立滚动，结算摘要与按钮固定；确认转生仍需第二次点击。
- 设置沿用已有选项；打开时暂停游玩，关闭时恢复进入前的暂停状态。

## 新手工程

新存档依次学习砸楼、升级锤伤、部署第一台炮、观察实际开炮、首次转生。等待金币时只显示轻提示，条件满足时显示箭头。教程不会自动打开/关闭面板、购买升级或确认转生。

`SaveManager.onboarding_stage` 按槽位保存：0 锤击与首次升级、1 已升级、2 已部署、3 已实际出弹、4 已完成或跳过。旧档 `onboarding.done=true` 仍代表整个教程完成；旧档缺少阶段字段时默认 0，并根据实际升级和炮台状态推进。跳过结束全部阶段，首次成功转生在切场前保存完成标记。

箭头和外框查询真实屏幕矩形；方块目标失效或下落时重新选择稳定可见方块。提示卡避开当前点击目标。设置、重开确认等遮挡目标时收起提示；减少动态模式使用静态箭头。

供表现层使用的接口：

- `GoldHUD.action_screen_rect(action)`：`skill_tree`、`rebirth`、`settings`。
- `UpgradePanel.node_screen_rect(nid)`、`close_screen_rect()`；`node_screen_pos(nid)` 保留兼容。
- `ReincarnationPanel.settlement_screen_rect()`：普通结算按钮或当前确认按钮。
- `BombLauncher.bomb_fired(at)`：实际生成一次齐射中的炮弹后触发一次，部署不触发。

## 原创炮素材

从文字设定独立生成概念图，再以原生像素图元绘制运行时素材，未将旧炮或旧重绘图作为生成/描摹输入。新轮廓为履带底座、方形炮身、斜向钢炮管、外露液压杆和青色压力灯。

- 可编辑源文件：`assets/presentation/sources/hydraulic/hydraulic_launcher.svg`，含 tracks、chassis、hydraulics、barrel 四组。
- 图层 PNG、图元 JSON、概念图和来源说明保存在同一目录；代码源为 `tools/build_hydraulic_launcher.py`。
- 运行时：`launcher.png`、`launcher_attack.png`、`launcher_frames.tres`。64×64 RGBA、2 倍最近邻显示；攻击 33 帧、16 FPS、索引 20 出弹；第 20 帧炮口 `(10,21)`，底座外边缘 y=64。
- 重建命令：`python tools/build_hydraulic_launcher.py`。完整素材构建器也调用此入口，不会重新使用旧炮图。
- Windows 与 Android 导出均排除旧素材目录和所有创作源图；本地历史素材保留。

## 验证与复现

先运行 `tools/prepare_demo_validation.ps1`，得到独立的 `boomame-demo-validation` 副本及 `BoomameDemoValidation` 用户数据目录。验证脚本会拒绝在玩家数据目录运行。

`godot --headless --path ../boomame-demo-validation --script res://tools/ui_refresh_verify.gd` 运行行为检查；去掉 `--headless` 后还会生成实际渲染截图。报告与截图写入 `artifacts/ui-refresh/`。

新手操作验证使用真实指针事件打开面板和购买节点；为快速覆盖炮台、转生及多炮边界，验证脚本注入里程碑金币。演示短视频同样加速资金积累，不能用来评估自然游玩的成长耗时。

检查包括槽位持久化、旧档兼容、跳过、提前行动、目标替换、面板遮挡、减少动态、四台炮与最快射速，以及 1280×720、1920×1080、2560×1440、3440×1440 的界面边界。原有展示、成长、数值与坍塌检查使用同一独立副本运行。
