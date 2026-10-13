# 2026-10-13 破坏特效与动态反馈

本轮把拆楼动作连接成一条可读的反馈链，沿用现有像素素材。玩法数值与存档格式不变。

- 锤击：短促的双段挥击弧线与飞散火花，重锤使用更大范围。
- 发射：炮口闪光沿实际初速度方向喷出，保留现有攻击帧与后坐动画。
- 飞行：炮弹留下渐细、渐淡的世界坐标尾迹；点数固定上限。
- 爆炸：序列动画搭配扩张压力环、次级环与火星，之后快速消散。
- 碎裂：修复范围攻击的碎屑全部挤在攻击原点的问题；各方块按自身材质，从实际位置向外飞散。
- 扬尘：落定与爆炸粉尘缓缓上升、横向扩散并淡出。

新增绘制不生成额外物理体。锤击、炮口、爆炸与碎屑沿用现有表现预算。低特效缩短尾迹并关闭次级环、爆炸火星；减少动态效果关闭尾迹、弧线、压力环与粉尘位移，并降低碎屑速度。

## 已执行验证

Godot 4.7.2、GL Compatibility、RTX 3060 Laptop GPU，独立项目 `boomame-motion-validation` 与独立用户目录运行，未使用玩家存档。

`tools/motion_verify.gd` 的 17 项检查全部通过：初始楼体、锤击伤害、碎裂奖励、碎屑实际出生位置、尾迹上限、低特效与减少动态效果、生命周期、暂停恢复、数量预算、塌落补层、四炮台自动破坏、重开清理与时间缩放复位。

四炮台满射速、最大基础伤害/半径，实际渲染运行 35 秒，摧毁 1906 块。逐秒帧率采样中位数 129 FPS，最低采样 103 FPS。此结果只代表本机这次短时运行，未验证长时间挂机或其他硬件。预算峰值：碎屑 768、命中特效 48、爆炸 3、粉尘 6，均在上限内。原有退出时 3 个 CanvasItem RID / 6 个 ObjectDB 实例告警在改动前截图程序中也存在，本轮未修改其来源；本轮验证无脚本或运行错误。

证据：`artifacts/motion/after/report.json`、`artifacts/motion-verify.log`；截图位于 `artifacts/motion/after`，动效预览为 `artifacts/motion/preview.mp4`。

## 重跑

在项目根目录运行 `tools/prepare_motion_validation.ps1`，然后用本机 Godot 可执行程序执行：

```powershell
godot --headless --editor --path ../boomame-motion-validation --quit
godot --path ../boomame-motion-validation --script res://tools/motion_verify.gd
```

参数入口见 [SPEC.md](SPEC.md) 表现优化参数表与 `assets/presentation/profile.tres`。录制脚本 `tools/motion_showcase.gd` 仅在独立副本运行；开头展示锤击，随后展示四炮台。
