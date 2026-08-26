# ScreenTransition.md —— 屏幕碎块下落切换场景

> 场景切换过场：旧屏幕截图被切成 N×M 矩形碎块，碎块带重力、随机旋转、轻微爆散后下落，露出下方新场景；全部碎块移出屏幕后自动清理，过渡结束。

## 一句话

点"开始游戏"切场景时，当前画面像被砸碎成一块块矩形碎块、哗啦啦往下掉，新场景从碎块缝隙中逐渐露出来。

## 效果目标 / 明确不做

- **做**：旧屏碎裂下落、新场景随碎块下落逐渐露出、一次切场播放一次、过渡期间屏蔽输入。
- **不做**（Non-goals）：
  - 反向入场（新场景碎块从四周飞入拼合成屏）——仅作后续可选，不进当前实现。
  - 碎块边缘描边 / 投影 / 粒子 / 发光等增强特效。
  - 音效（遵循 MVP"不做音效"边界）。
  - 不打断现有玩法逻辑：仅替换场景切换调用，不动 GoldManager / UpgradeManager 重置流程。

## 模块结构

| 项 | 内容 |
| --- | --- |
| 脚本 | [ScreenTransition.gd](file:///e:/godotproject/boomame/scripts/ScreenTransition.gd)（新增，`class_name ScreenTransition`，extends CanvasLayer） |
| 注册 | project.godot `[autoload]` 增加 `ScreenTransition="*res://scripts/ScreenTransition.gd"` |
| 类型 | 全局单例（Autoload），常驻不随场景销毁；层级设高（layer = 100），永远盖在场景之上 |
| 依赖 | 无玩法模块依赖，只使用 Viewport / Texture / SceneTree 标准 API → 无循环依赖风险 |

> 采用 **Autoload CanvasLayer** 而非场景内节点：Autoload 在 `change_scene_to_file` 后不会被销毁，碎块能全程存活到新场景载入完成，过渡不会中断。

## 数据流

```
transition_to(target_scene)
   │
   ├─ 1. _capture()        // 必须在切场前抓屏
   │      get_viewport().get_texture().get_image() → Image
   │      ImageTexture.create_from_image(img)        → 全屏纹理
   │
   ├─ 2. _spawn_shards()   // 按 cols×rows 切成矩形子区
   │      每块：AtlasTexture(atlas=全屏纹理, region=子区 Rect2)
   │      节点：TextureRect + 全屏鼠标拦截 Control（input 屏蔽）
   │      状态：_vel(初速度, 带随机爆散偏移)、_ang(角速度)、_delay(随机起步延迟)
   │
   ├─ 3. _delay(exit_delay) → get_tree().change_scene_to_file(target)
   │      新场景在碎块背后载入，随碎块下落逐渐露出
   │
   ├─ 4. _process(delta)   // 手动物理积分（UI 层不用 RigidBody2D）
   │      _vel.y += fall_gravity * delta
   │      _vel = _vel.limit_length(max_fall_speed)
   │      pos += _vel * delta；rotation += _ang * delta
   │      y 超过 (视口高 + clear_margin) → 移除碎块
   │
   └─ 5. 全部碎块移除 → _finish()
         释放纹理/数组、恢复输入、过渡完成
```

## 关键数值（`@export` 定义，实现时回填 SPEC.md 数值边界表）

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| cols | 10 | 横向碎块数（碎块宽度 = 1920/cols） |
| rows | 7 | 纵向碎块数（碎块高度 = 1080/rows） |
| fall_gravity | 2400 | 碎块下落重力加速度 |
| max_fall_speed | 1600 | 下落速度上限 |
| burst_speed | 60 | 起步爆散横向速度（让碎块先"裂开"再掉） |
| hop_up_speed | 420 | 起步向上跳动速度（先向上小跳一下再下落，0 = 直接下落） |
| rot_speed_range | 120 | 角速度范围（度/秒，随机 ±） |
| start_jitter | 0.25 | 起步随机延迟上限（秒），错落更有破碎感 |
| exit_delay | 0.25 | 切场延迟（秒）：碎块已散开、未掉完时切场景 |
| clear_margin | 120 | 碎块完全移出屏幕的额外余量（px） |
| input_block | true | 过渡期间用全屏 Control 拦截鼠标点击 |
| shake_radius | 5 | 生成瞬间全屏震屏抖动半径（px），随时间线性衰减 |
| shake_duration | 0.25 | 震屏时长（s） |
| pop_scale | 0.6 | 碎块生成弹跳起始缩放（弹簧弹回 1.0） |
| pop_duration | 0.12 | 弹跳恢复时长（s，TRANS_BACK 弹簧感） |

> 性能：10×7=70 块 TextureRect + 全屏一张纹理，GL Compatibility 下开销可忽略。
> 全屏拦截 Control 设 `mouse_filter = MOUSE_FILTER_STOP`，过渡结束 `_finish()` 时移除，避免新场景玩家误点。

## 集成点

- [MainMenu.gd](file:///e:/godotproject/boomame/scripts/MainMenu.gd#L23-L26) `_on_start_pressed()`：把第 26 行 `get_tree().change_scene_to_file(MAIN_SCENE)` 替换为 `ScreenTransition.transition_to(MAIN_SCENE)`；`GoldManager.reset()` / `UpgradeManager.reset()` 保持在调用前执行（维持"全新一局"）。
- 当前项目仅 MainMenu → Main 一处场景切换；未来新增切场点（如回到主菜单）同样调 `ScreenTransition.transition_to(...)` 即可。

## 依赖方向

```
ScreenTransition → SceneTree / Viewport / Texture（单向，标准 API）
```
不依赖任何玩法模块，玩法模块也不反向依赖它 → 无循环依赖，符合 MODULES.md 协作约定。

## 测试 / 验收

1. 主菜单点"开始游戏"：屏幕碎成矩形块下落，Main 场景从缝隙中露出，过渡约 1.5s 内完成。
2. 过渡期间鼠标点击无效（拦截生效），过渡结束后点击恢复正常。
3. 快速连点"开始游戏"只触发一次过渡（入口加 `_busy` 防抖）。
4. 过渡结束后无残留节点、无内存泄漏（碎块全部移出并释放，数组清空）。
5. 二次进入主菜单再切场，效果一致，不报错。

## 实现清单

- [ ] 新增 `scripts/ScreenTransition.gd`（含上述 @export、抓屏、碎块生成、物理积分、清理、_busy 防抖）
- [ ] project.godot `[autoload]` 注册
- [ ] MainMenu.gd 接入 `ScreenTransition.transition_to(MAIN_SCENE)`
- [ ] SPEC.md 数值边界表回填上表参数
- [ ] MODULES.md 模块表登记 ScreenTransition（遵循"实现后追加"约定）

## 后续可选（不进当前实现）

- 反向入场：新场景碎块从四周飞入拼合成屏（需要第二张截图=新场景截图，或倒放）。
- 碎块描边 / 轻微缩放 / 不同碎块尺寸混排，增强破碎感。
