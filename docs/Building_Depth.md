# 楼体 2.5D 与破坏断面（2026-10-13）

## 当前效果

保留像素工地与正面拆楼操作，为原来的平面材料墙增加 40px 窄侧面、整栋左亮右暗的受光、连续边柱和中央柱、固定窗带，以及较薄的楼层腰线。

每个方块的 `VisualLayer` 拥有自己的 `DepthShell` 和 `FacadeDetails`。侧面向右后方 `(40,-16)` 挤出，外侧墙使用较暗的对应墙材质色；内部断面使用蓝灰暗色。方块被拆除时，自己的背面与侧面一并释放，缺口露出存活邻块的暗色断面、顶面和楼板厚度。塌落和受击摇摆自然带动装饰；没有固定的整栋立面外壳。

正面可拆范围保留 12 列 ×30 层、单块 40×40。窄侧面是装饰，不增加点击目标或阻挡炮弹。塔脚阴影增加与同一深度参数一致的侧向投影。

## 窗与楼板

- 真实玻璃重排到列 2/3 和 8/9 两组窗带，初始墙层每层仍随机开 2～4 扇窗。图上窗口与真实玻璃一一对应，没有把墙伪装成脆玻璃。
- 补层玻璃仅出现在这四个窗位，各窗位概率 0.75；完整墙层的期望数量仍为 3，与原来的 12 槽位 ×0.25 一致。弱点位置因此有所变化，不主张局部攻击收益完全相同。
- 窗内贴图裁为原生 16×16、2 倍显示，实际开口 32×32，增加凹入窗框和窗台。
- 楼板方块的实际碰撞与 HP 保留 40×40；外观上部是同档墙材质的窗间墙，下部 12px 显示原有楼板材质，减少宽灰条的棋盘感。
- 材质档位、血量、奖励、升级、存档格式和逐列压实/补层算法保持现有实现。

## 配置与模块

`PresentationProfile` 的 **Building depth** 分组集中配置侧面深度、侧墙亮度、正面右侧亮度、内壁色、边柱色和楼板阴影色。边界见 [SPEC.md](SPEC.md)。

`DemolitionBuildingFacade` 仅绘制几何，不接收输入、不创建碰撞、不执行逐帧邻居搜索，也不修改游戏状态。`BuildingSetup` 为新生成和补层的方块附加同样的皮肤。没有替换原始位图或新增生成服务。

## 验证

所有运行在独立的 `boomame-scene-art-validation` 副本和用户目录中执行，未操作玩家存档。

| 检查 | 通过 |
| --- | --- |
| 楼体专项：窗位/窗数、360 块碰撞与数值、侧面不增加命中目标、缺口奖励、断面清理、塌落补齐、重开/切场 | 12 / 12 |
| 原场景美术专项：接地、透明度、方块外观清理、超宽屏无色缝 | 17 / 17 |
| 表现回归：伤害、奖励、存读档、暂停、转生、四分辨率命中映射和面板边界 | 37 / 37 |
| 坍塌回归 | 11 / 11 |
| 动效与四炮压力回归 | 17 / 17 |
| UI 与新手回归 | 87 / 87 |

合计 181 项通过。四炮压力运行 35 秒，摧毁 2184 块；本机 RTX 3060 Laptop / Godot 4.7.2 的 FPS 样本中位数 95、最低 65，所有特效数量保持预算内。新增绘制带来额外开销；这是本机实测，不能直接外推至其他硬件。

实际查看初始楼体、四档材质、混合材质、破坏缺口、塌落补齐、四炮和 1280×720 / 1920×1080 / 2560×1440 / 3440×1440 截图。确认窄侧面与层线可见、真实玻璃与窗位对应，缺口没有完整侧墙残留。退出时仍有基准已有的 CanvasItem/ObjectDB 释放警告；最终测试过程无脚本错误。

## 复现与交付

```powershell
.\tools\prepare_scene_art_validation.ps1 -ArtifactGroup building-depth
godot --headless --editor --path ../boomame-scene-art-validation --quit
godot --path ../boomame-scene-art-validation --resolution 1920x1080 --script res://tools/building_depth_verify.gd
godot --path ../boomame-scene-art-validation --resolution 1920x1080 --script res://tools/scene_art_capture.gd -- E:/godotproject/boomame/artifacts/building-depth/after
```

原有回归命令同 [Scene_Art_Harmony.md](Scene_Art_Harmony.md)，包装脚本将结果写入本轮 `regression/` 目录。依次运行测试以隔离各运行的测试槽位和设置。

- `artifacts/building-depth/comparison.html`：本轮改动前后 13 组对比、真实缺口截图和录像，可离线打开。
- `artifacts/building-depth/before/` 与 `after/`：同一引擎捕获脚本生成的实际画面，未后期调色。窗位改变后随机序列不同，方块细节和物理抓帧时刻不完全一致。
- `artifacts/building-depth/cutaway.png` 与 `settled.png`：同一次局部破坏在塌落前和落定后的实际渲染；断面截图在暂停时采集。
- `artifacts/building-depth/building-depth.mp4`：引擎录像，展示锤击、局部断面、塌落和四炮轰炸；局部大缺口由脚本调用真实伤害接口，炮台通过注入测试金币加速部署，不用于评估自然成长时间。
- `depth-verification.json`、`verification.json`、`regression/`、`summary.json`：专项与回归报告。

录像入口为 `tools/building_depth_showcase.gd`，配合 Godot `--write-movie`、`--fixed-fps 30` 使用。所有美术源代码和参数仍在项目内，可继续编辑。
