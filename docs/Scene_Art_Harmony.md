# 场景美术协调（2026-10-13）

本文记录配色协调阶段；同日后续的楼体体积、窗位重排和薄楼板更新见 [Building_Depth.md](Building_Depth.md)。

## 视觉方向

沿用清爽像素工地：蓝天、工程黄、钢蓝灰机械 UI。背景降低饱和度和对比，楼体减弱亮白网格，窗框、设备轮廓和接地阴影统一配色。此次保留当前液压炮、工坊 UI 与破坏动效；不改布局、碰撞、伤害、费用、成长或存档格式。

## 实现

- 背景、近地层与主菜单背景共用 `background_harmony.gdshader`。远景为 0.75 饱和度、0.85 对比度，加入 0.10 蓝灰雾色；接近地面时过渡到 0.90 / 0.94，保留土黄暖色。采用最近邻采样，无模糊滤镜。
- 相邻背景副本镜像延展，保持 1920×1080 中央构图，消除超宽屏重复贴图处的天空色差。扩展区可见镜像构图，不是新绘制的远景。
- `material_harmony.gdshader` 统一材质饱和度和对比；实心块边缘采样邻近内部像素，减弱原图白边；左上浅暖高光、右下蓝灰阴影。玻璃用统一窗框，保留三种玻璃的底色差异。
- 花岗岩原图的碎纹理仍偏强，单独以 0.35 细节强度向 `#a0a7a6` 收敛；其碎屑采用同样调色。纹理没有被模糊或重新生成。
- 楼体左右外轮廓附着于单块的 `VisualLayer`，随方块塌落、摇摆和销毁。裂纹仍使用原有独立覆盖层。
- `DemolitionContactShadow` 绘制相同颜色的两层像素阴影：4px 内阴影、10px 外阴影。塔脚接触面为 x=700～1180、y=1000；履带阴影宽 112px。炮台阴影保留为炮台子节点，使用 `top_level` 固定世界地面，部署时淡入，后坐不带动阴影；隐藏、重开和切场时跟随清理。减少动态时立即显现。
- 命中闪光、冲击环和尾迹共用暖白、橙黄、暖橙色。烟尘转为低饱和土灰；保留现有生命期、粒子数量预算与伤害结算。

参数位于 `PresentationProfile` 的 **Scene harmony** 分组，可通过 `assets/presentation/profile.tres` 编辑；新运行时创建共享材质。参数边界见 [SPEC.md](SPEC.md)。资源原图未覆盖，无生成服务依赖。

## 复现

在项目根目录执行：

```powershell
.\tools\prepare_scene_art_validation.ps1
godot --headless --editor --path ../boomame-scene-art-validation --quit
godot --path ../boomame-scene-art-validation --resolution 1920x1080 --script res://tools/scene_art_capture.gd -- E:/godotproject/boomame/artifacts/scene-art/after
godot --path ../boomame-scene-art-validation --resolution 1920x1080 --script res://tools/scene_art_verify.gd
godot --path ../boomame-scene-art-validation --script res://tools/presentation_verify.gd
godot --headless --path ../boomame-scene-art-validation --script res://tools/collapse_verify.gd
godot --path ../boomame-scene-art-validation --script res://tools/motion_verify.gd
godot --headless --path ../boomame-scene-art-validation --script res://tools/ui_refresh_verify.gd
```

验证项目名为 `BoomamePresentationValidationMotionSceneArtValidation`，移除 MCP 自动加载并禁用编辑器插件，使用独立用户目录。现有回归脚本只在验证副本中调整隔离目录判断和输出路径。各运行按顺序执行，避免测试存档和设置相互干扰。

录像使用 `scene_art_capture.gd` 的 `movie` 参数，Godot Movie Maker 输出后转成 H.264/AAC MP4。示例：

```powershell
godot --path ../boomame-scene-art-validation --fixed-fps 30 --write-movie E:/godotproject/boomame/artifacts/scene-art/scene-art.avi --script res://tools/scene_art_capture.gd -- E:/godotproject/boomame/artifacts/scene-art/movie movie
ffmpeg -y -i artifacts/scene-art/scene-art.avi -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart artifacts/scene-art/scene-art.mp4
```

## 验证结果

Godot 4.7.2 / GL Compatibility / NVIDIA GeForce RTX 3060 Laptop GPU：

| 检查 | 通过 | 结果 |
| --- | --- | --- |
| 场景美术专项 | 17 / 17 | 部署与后坐阴影贴地、隐藏/重开/切场清理、方块装饰跟随、半透明只应用一次、超宽屏实际渲染无天空色缝 |
| 原有表现回归 | 37 / 37 | 伤害/金币、补块、暂停、存读档、转生、命中映射、四种分辨率技能树边界 |
| 原有坍塌回归 | 11 / 11 | 网格归位、快速跨列破坏、范围锤及慢动作场景 |
| 原有动效回归 | 17 / 17 | 尾迹与低特效、减少动态、预算上限、重开清理、四炮自动破坏 |
| 原有 UI 回归 | 87 / 87 | 新手流程、炮口/脚底锚点、四种分辨率界面边界 |

四炮压力运行 35 秒，摧毁 2163 块；FPS 样本中位数 126、最低 80，所有视觉预算维持上限内。这是本机测试结果，不代表其他硬件的性能保证。最终花岗岩调色后重新采集全部对比截图并复跑 17 项美术检查，全部通过。

人工查看实际渲染的初始楼体、四档材质、混合材质、塌落、四炮和爆炸截图，以及 1280×720 / 1920×1080 / 2560×1440 / 3440×1440 场景：远景更柔和，窗框与楼体边缘一致，炮台与塔脚接地，最高档花岗岩噪声收敛。自动检查只说明行为正确，协调感仍以截图和实机画面评审。

测试过程无脚本或着色器错误。退出时仍出现基准运行已存在的 CanvasItem/ObjectDB 释放警告，本轮未处理无关生命周期问题。

## 交付物

- `artifacts/scene-art/comparison.html`：可离线打开的拖动对比页面，包含 13 组场景和实机录像。
- `artifacts/scene-art/before/` 与 `after/`：修改前从当前工作区采集的基准，以及修改后的实际渲染截图；截图颜色未后期修改。
- `artifacts/scene-art/scene-art.mp4`：1920×1080、30 FPS、约 12 秒的真实引擎演示。
- `artifacts/scene-art/verification.json` 与 `regression/`：专项及现有回归报告。

截图使用相同种子；光标、HUD 动画与物理抓帧时刻可能略有差异。材质阶段和多炮通过测试存档注入进度/金币加速展示，不用于评价自然成长节奏。所有测试均隔离玩家存档。
