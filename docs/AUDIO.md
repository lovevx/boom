# AUDIO.md —— 音频设计说明

> 本文约定：一个音效放在哪里、由谁触发、命名/目录长什么样、如何接入。
> 当前 [SoundManager.gd](file:///e:/godotproject/boomame/scripts/SoundManager.gd) 采用**程序合成**兜底，逐步替换为**真实音频文件**；替换时只动 SoundManager，不改各触发点代码。

---

## 1. 设计目标（先定味道，再定文件）

- 破坏反馈统一为**破碎 / 粉碎**取向（沿用项目约定，不做"掉落"），音频要给出清脆、碎裂、爆响的通感。
- 核心循环「砸/炸 → 赚金币 → 升级 → 解锁炮台 → 炸更猛」每一步都要有**可辨识的听觉回报**，让操作有重感（weight）。
- **音量分层**：音乐 < 环境 < 玩法音效 < UI 音效，互不淹没；金币、碎裂频率高，音量要偏低避免疲劳。

---

## 2. 音频总线结构（project 的 Audio Bus）

在 Godot 编辑器的 `Audio → Bus Layout`（或 `default_bus_layout.tres`）里规划 4 条总线，SoundManager 与音乐节点按类别归总到对应总线，便于统一调音量/淡入淡出：

| Bus | 用途 | 相对音量（参考） | 归属 |
| --- | --- | --- | --- |
| `Master` | 总输出（默认总线，不可删） | 0 dB | 一切最终出口 |
| `Music` | 背景音乐 / 循环 | ≈ 0 dB 内，比 SFX 柔 | BGM |
| `SFX` | 玩法音效（砸/炸/碎/金币/环境） | 0 dB | 玩法触发 |
| `UI` | 界面音效（按钮/升级/过场） | ≈ -4 ~ -6 dB | UI 触发 |

> 现有 SoundManager 播放器 `bus = &"Master"`（见 [SoundManager.gd](file:///e:/godotproject/boomame/scripts/SoundManager.gd#L48)），后续按播放类别分到 `Master / SFX / UI`。

---

## 3. 音效触点清单（什么地方需要什么音）

下表逐条对应"系统的哪个动作事件 → 播放哪个音效，属于哪条总线"。前 7 项 **已实现**（由 SoundManager 合成），其余为 **缺口**（接口已存在或逻辑已存在，但还没有音频）。

### 3.1 已实现（当前可播放）

| 触点（文件 / 事件） | 音效名 | Bus | 说明 |
| --- | --- | --- | --- |
| [Hammer.gd](file:///e:/godotproject/boomame/scripts/Hammer.gd#L82-84) 锤子挥动 | `hammer_swing` | SFX | 短促"呼"，挥空/挥出都播 |
| [Hammer.gd](file:///e:/godotproject/boomame/scripts/Hammer.gd#L82) 锤子命中 | `hammer_hit` | SFX | 低频闷响 + 轻脆响，命中反馈 |
| [BuildingBlock.gd](file:///e:/godotproject/boomame/scripts/BuildingBlock.gd#L116) 方块被砸碎 | `shatter_glass` / `shatter_stone` | SFX | 玻璃块放玻璃碎声，石材/金属/其余放石头碎声 |
| [BuildingSetup.gd](file:///e:/godotproject/boomame/scripts/BuildingSetup.gd#L397) 同时下落 ≥3 块的连锁崩塌 | `collapse` | SFX | 一次性"哗啦"崩塌音，同次连锁只响一声 |
| [BuildingBlock.gd](file:///e:/godotproject/boomame/scripts/BuildingBlock.gd#L138) 产出金币 | `coin` | SFX | 升调"叮—咚"，与 shatter 同帧叠加 |
| [BombProjectile.gd](file:///e:/godotproject/boomame/scripts/BombProjectile.gd#L118) 炸弹爆炸 | `explosion` | SFX | 低频下滑轰 + 噪声，全游戏最响 |
| [GoldHUD.gd](file:///e:/godotproject/boomame/scripts/GoldHUD.gd#L42-52) / [UpgradePanel.gd](file:///e:/godotproject/boomame/scripts/UpgradePanel.gd#L217) 按钮点击 | `ui_click` | UI | 通用"嗒"声 |
| [UpgradePanel.gd](file:///e:/godotproject/boomame/scripts/UpgradePanel.gd#L437) 升级成功 | `upgrade` | UI | 三音上行琶音，购买成功的奖励感 |

### 3.2 缺口（建议补齐）

| 触点 | 建议音效名 | Bus | 说明 |
| --- | --- | --- | --- |
| 主菜单按钮 Play / How to Play / Exit | `ui_hover`、`ui_click` | UI | 悬停轻"嘀"，点击复用 ui_click |
| 进游戏 / 返回主菜单 场景切换（[ScreenTransition.gd](file:///e:/godotproject/boomame/scripts/ScreenTransition.gd) 碎块过场） | `scene_transition` | UI | 碎块爆散 + 落地的一阵 Whooosh/哗啦 |
| 炸弹炮台"部署解锁"（LauncherManager `play_deploy()`） | `launcher_deploy` | SFX | 机械就位/成长感音，跟随解锁成长 |
| 炸弹炮台每发发射（BombLauncher 投掷） | `launcher_shoot` | SFX | 短促发射"咻"，注意节流防吵 |
| 引导提示浮现（[Onboarding.gd](file:///e:/godotproject/boomame/scripts/Onboarding.gd)） | `onboarding_pop` | UI | 轻快的小弹跳提示音，低音量 |
| 伤害数字跳出（DamageNumber） | `damage_tick` | SFX | 很轻的一声"嗒"，可有可无，防过度 |
| 升满级 / 无法购买 | `error`（或 `locked`） | UI | 低沉"镗"，明确告知无效点击 |

> 建议优先级：`launcher_shoot`、`scene_transition`、`ui_hover` > 其余按体验优先级补。

### 3.3 背景音乐与环境

| 场景 | 建议资源 | 说明 |
| --- | --- | --- |
| 主菜单 | `bgm_main_menu` | 舒缓循环，树立游戏基调 |
| 主玩法页面 | `bgm_gameplay` | 节奏感更强的循环，支撑挂机/自动化节奏 |
| （可选）高压时刻 | `amb_battle` | 连爆/大量生产时的环境层 |

> BGM 走 `Music` 总线，用 AudioStreamPlayer 循环播放；场景切换时做淡入淡出，由 SoundManager 暴露 `play_music/stop_music(fade_sec)`。
>
> **当前实现**：`assets/audio/bgm/` 下 `BGM1.mp3` / `bgm2.mp3` 两首曲目由 SoundManager 的 `bgm_index` 选定（见 [SoundManager.gd](file:///e:/godotproject/boomame/scripts/SoundManager.gd) `BGM_FILES`），主菜单与玩法统一调 `SoundManager.play_music()`（不传路径，按当前选曲播放）。场景切换时若曲目未变则不打断重播，保持连贯。
>
> **音量设置**：主菜单与游戏内 HUD 均有「设置」入口，打开 [SettingsPanel.gd](file:///e:/godotproject/boomame/scripts/SettingsPanel.gd) 可调「音乐音量 / 音效音量」并手动切换 BGM 曲目；设置实时应用到 `Music / SFX / UI` 总线并持久化到全局 `user://settings.cfg`（不随存档槽位走）。

---

## 4. 文件夹结构（assets/audio/）

所有音频统一放 `assets/audio/`,按 **类别分目录**；美术在 `assets/ui/`,音频同理对齐这条"最小映射"约定。

```
assets/
└── audio/
    ├── bgm/                          # 背景音乐（循环）
    │   ├── bgm_main_menu.wav/ogg
    │   └── bgm_gameplay.wav/ogg
    ├── amb/                          # 环境/氛围（可选）
    │   └── amb_battle.wav/ogg
    ├── sfx/
    │   ├── gameplay/                 # 玩法核心音
    │   │   ├── hammer_swing.wav
    │   │   ├── hammer_hit.wav
    │   │   ├── shatter_glass.mp3    # 玻璃块破碎声
    │   │   ├── shatter_stone.mp3    # 石材/金属块破碎声
    │   │   ├── collapse.mp3         # 大量方块同时下落的崩塌声
    │   │   ├── coin.wav
    │   │   ├── explosion.wav
    │   │   ├── launcher_deploy.wav
    │   │   ├── launcher_shoot.wav
    │   │   └── damage_tick.wav
    │   └── ui/                       # 界面与系统音
    │       ├── ui_hover.wav
    │       ├── ui_click.wav
    │       ├── upgrade.wav
    │       ├── error.wav
    │       └── onboarding_pop.wav
    └── transitions/                  # 场景切换
        └── scene_transition.wav
```

命名规范（沿用项目 snake_case）：

- 全小写 + 下划线，`类别_动作[_序号]`，如 `shatter_3.wav`、`ui_click.wav`。
- 用 44.1kHz / 16bit 单声道；音乐可用立体声 ogg 减小体积。
- **避用中文文件名**（现有贴图用中文主要是历史遗留），新音频一律英文 snake_case。

---

## 5. 如何接入（最小改动路径）

1. 把音频文件按第 4 节结构放入 `assets/audio/…`。
2. 修改 [SoundManager.gd](file:///e:/godotproject/boomame/scripts/SoundManager.gd#L127) `_generate_all()`：把对应条目从合成函数换成 `load("res://assets/audio/xxx.wav")`。
3. 在 `VOLUMES`（[SoundManager.gd](file:///e:/godotproject/boomame/scripts/SoundManager.gd#L9)）登记每个音效的相对音量 dB。
4. 按类别把该音的 `player.bus` 指到 `SFX / UI / Music`。
5. 新增触点：在触发点调用 `SoundManager.play("音效名")` 即可，无需改池逻辑。

示例（以玻璃碎声为例，把文件放进对应路径即可）：
 
```gdscript
"shatter_glass": load("res://assets/audio/sfx/gameplay/shatter_glass.mp3"),
```

---

## 6. 当前状态与待办清单

| 项 | 状态 | 动作 |
| --- | --- | --- |
| 音频总线分 Music/SFX/UI | ✅ 已搭（SoundManager 启动时动态创建） | 音量可在总线里微调 |
| 文件优先 + 合成兜底加载 | ✅ 已搭 | 往 assets/audio/ 对应路径投文件即生效 |
| play_music / stop_music（BGM 管理） | ✅ 已搭（API 就绪） | 在 MainMenu/Main 里调用并放好 BGM 文件 |
| 7 种原有音效（合成） | ✅ 已实现 | 可选替换为真音频 |
| launcher_shoot / deploy | ✅ 已实现（合成兜底） | 替换真音频 |
| scene_transition 过场音 | ✅ 已实现（合成兜底） | 替换真音频 |
| ui_hover 主菜单悬停音 | ✅ 已实现（合成兜底） | 替换真音频 |
| onboarding_pop 引导提示音 | ✅ 已实现（合成兜底） | 替换真音频 |
| damage_tick / error | ⬜ 已注册未接线 | 需要时在 DamageNumber / UpgradePanel 触发 |
| BGM 文件（主菜单/玩法） | ✅ 已接入 | BGM1.mp3 / bgm2.mp3 由设置面板切换，主菜单与玩法统一 play_music() |
| 音量设置（音乐/音效） | ✅ 已实现 | 设置面板实时调 Music/SFX/UI 总线，持久化到 user://settings.cfg |

> 加载优化：Godot 的 `.import` 会自动导入 `assets/audio/` 下的音频；运行时 `load()` 一次性缓存全量即可，体积都很小，无需异步。