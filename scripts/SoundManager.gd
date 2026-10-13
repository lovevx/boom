extends Node
## 全局音效管理器（Autoload：SoundManager）。
## 【 文件优先 + 合成兜底 】每个音效默认优先加载 assets/audio/ 下的真实音频文件；
## 当文件尚未导入（还没放文件 / 未编入工程）时，回退为启动时【程序化合成】的 AudioStreamWAV，
## 保证任何时候都有声音。因此你可以随时往 assets/audio/ 对应路径投放 .wav/.ogg，
## Godot 导入后游戏立刻变成真实音效，无需改动任何触发点代码。
##
## 三类播放：玩法音效 → SFX 总线；界面音效 → UI 总线；背景音乐 → Music 总线。
## 播放器按总线分组复用池，支持多音叠加；场景切换/升级等 BGM 需求用 play_music/stop_music。

const MIX_RATE := 22050          # 合成兜底用的采样率（只对合成音生效，文件音用文件自身）

# —— 总线（由本脚本在启动时按需创建：Master ↘ Music / SFX / UI）——
const CAT_SFX := "SFX"
const CAT_UI := "UI"
const CAT_MUSIC := "Music"
# 各总线基准音量（dB）：设置面板中音量滑到 100% 时保持该响度，调低时在其上按线性衰减。
const MUSIC_BASE_DB := -6.0
const SFX_BASE_DB := -2.0
const UI_BASE_DB := -6.0

# —— 设置持久化（全局，不随存档槽位走）——
const SETTINGS_PATH := "user://settings.cfg"
# 背景音乐候选曲目（按 index 切换，设置界面可手动换曲）
const BGM_FILES := [
	"res://assets/audio/bgm/BGM1.mp3",
	"res://assets/audio/bgm/bgm2.mp3",
]
const BGM_NAMES := ["BGM 1", "BGM 2"]   # 原有两首音乐，沿用当前选曲序号

# 当前音量（0.0~1.0，100% = 保持总线基准）与选中的 BGM 序号。
var music_volume := 1.0
var sfx_volume := 1.0
var bgm_index := 0

# 设置变化信号：设置面板据此刷新滑块/曲名显示。
signal settings_changed

# —— 音效清单表：名称 → 配置 ——
# path：assets/audio/ 下的候选文件路径（放好文件即生效）；bus：所属总线；volume：dB。
const TABLE := {
	"shatter_metal": {"path":"res://assets/presentation/audio/sfx/shatter_metal.wav", "bus":CAT_SFX, "volume":-8.0},
	# —— 玩法（SFX 总线）——
	"hammer_swing":    {"path": "res://assets/presentation/audio/sfx/hammer_swing.wav",   "bus": CAT_SFX, "volume": -6.0},
	"hammer_hit":      {"path": "res://assets/presentation/audio/sfx/hammer_hit.wav",     "bus": CAT_SFX, "volume": -4.0},
	"shatter_glass":   {"path": "res://assets/presentation/audio/sfx/shatter_glass.wav", "bus": CAT_SFX, "volume": -5.0},
	"shatter_stone":   {"path": "res://assets/presentation/audio/sfx/shatter_stone.wav", "bus": CAT_SFX, "volume": -5.0},
	"collapse":        {"path": "res://assets/presentation/audio/sfx/collapse.wav",      "bus": CAT_SFX, "volume": -3.0},
	"coin":            {"path": "res://assets/presentation/audio/sfx/coin.wav",           "bus": CAT_SFX, "volume": -6.0},
	"explosion":       {"path": "res://assets/presentation/audio/sfx/explosion.wav",      "bus": CAT_SFX, "volume": -6.0},
	"launcher_shoot":  {"path": "res://assets/presentation/audio/sfx/launcher_shoot.wav", "bus": CAT_SFX, "volume": -6.0},
	"launcher_deploy": {"path": "res://assets/presentation/audio/sfx/launcher_deploy.wav","bus": CAT_SFX, "volume": -4.0},
	"damage_tick":     {"path": "res://assets/presentation/audio/sfx/damage_tick.wav",    "bus": CAT_SFX, "volume": -10.0},
	# —— 界面（UI 总线）——
	"ui_click":        {"path": "res://assets/presentation/audio/sfx/ui_click.wav",             "bus": CAT_UI, "volume": -9.0},
	"ui_hover":        {"path": "res://assets/presentation/audio/sfx/ui_hover.wav",             "bus": CAT_UI, "volume": -14.0},
	"upgrade":         {"path": "res://assets/presentation/audio/sfx/upgrade.wav",              "bus": CAT_UI, "volume": -6.0},
	"error":           {"path": "res://assets/presentation/audio/sfx/error.wav",                "bus": CAT_UI, "volume": -8.0},
	"onboarding_pop":  {"path": "res://assets/presentation/audio/sfx/onboarding_pop.wav",       "bus": CAT_UI, "volume": -10.0},
	# —— 场景切换（UI 总线）——
	"scene_transition":{"path": "res://assets/presentation/audio/sfx/scene_transition.wav","bus": CAT_UI, "volume": -5.0},
}

# 各总线播放器池大小：SFX 玩法音量大、常同时爆多（连锁破坏），给足槽位；
# UI 界面音少且低频，小池即可。池满了按"找空闲→否则丢弃"策略，绝不打断正在播的音。
const SFX_POOL_SIZE := 20
const UI_POOL_SIZE := 8

var _last_played := {}
var _duck_tween: Tween
var _music_nominal_db := -6.0
var _streams := {}                       # 音效名 -> AudioStream（文件优先，否则合成）
var _pool := {}                          # 总线名 -> Array[AudioStreamPlayer]
var _music: AudioStreamPlayer            # BGM 单播放器
var _current_bgm_path := ""              # 当前正在播放的 BGM 路径（用于场景切换时防重播）


func _ready() -> void:
	_ensure_buses()
	_load_settings()   # 读回上次设置并应用到总线
	_build_pool()
	_setup_music()
	_generate_all()
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.threshold_db = -6.0
	AudioServer.add_bus_effect(0, limiter)


# —— 对外统一入口：播放一个预设音效（叠加安全，复用池内播放器） ——
func play(name: String) -> void:
	var now := Time.get_ticks_msec()
	var cooldown: int = 100 if name in ["coin", "damage_tick", "ui_hover"] else (70 if name.begins_with("shatter") else 0)
	if now - int(_last_played.get(name, -100000)) < cooldown:
		return
	_last_played[name] = now
	if name == "explosion" and is_instance_valid(_music):
		if _duck_tween and _duck_tween.is_valid():
			_duck_tween.kill()
		_music.volume_db = _music_nominal_db - 5.0
		_duck_tween = create_tween()
		_duck_tween.tween_property(_music, "volume_db", _music_nominal_db, 0.4)
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		return   # 未注册的音效直接忽略
	var cfg: Dictionary = TABLE[name]
	var bus: String = cfg["bus"]
	var player := _acquire(_pool[bus])
	if player == null:
		return   # 该总线播放器全忙：丢弃本次额外播放（大量同时破坏时自动合并，防爆音/断音）
	player.stream = stream
	player.volume_db = cfg["volume"] - 3.0
	player.pitch_scale = randf_range(0.95, 1.05) if bus == CAT_SFX else 1.0
	player.play()


# 从该总线播放器池挑一个可用的：优先空闲播放器（不干扰正在播的音）；
# 全忙则返回 null（让 play 这次直接丢弃），绝不 stop() 打断正在播放的音效。
func _acquire(arr: Array) -> AudioStreamPlayer:
	for p: AudioStreamPlayer in arr:
		if not p.playing:
			return p
	return null


# —— 背景音乐：播放当前选中的曲目（BGM_FILES[bgm_index]），默认循环 ——
func play_music(volume_db: float = -6.0, loop: bool = true) -> void:
	_music_nominal_db = volume_db
	var path: String = BGM_FILES[bgm_index]
	if not ResourceLoader.exists(path):
		push_warning("SoundManager: BGM 文件不存在 %s" % path)
		return
	# 若当前已在播放同一首曲子（如场景切换），不打断重播，保持连贯
	if _music.playing and _current_bgm_path == path:
		return
	var s := load(path) as AudioStream
	if s == null:
		return
	s = _dup_stream(s)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		s.loop_begin = 0
		s.loop_end = roundi(s.get_length() * s.mix_rate)
	elif s is AudioStreamOggVorbis:
		s.loop = loop
	elif s is AudioStreamMP3:
		s.loop = loop
	_music.stream = s
	_music.volume_db = volume_db
	_music.play()
	_current_bgm_path = path


# —— 音量 / BGM 设置：应用 → 落盘 → 广播（设置界面调用） ——
func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_settings()
	settings_changed.emit()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_settings()
	settings_changed.emit()


func set_bgm_index(i: int) -> void:
	bgm_index = clampi(i, 0, BGM_FILES.size() - 1)
	_save_settings()
	# 若当前正有 BGM 在播，立即换曲
	if _music != null and _music.playing:
		play_music()
	settings_changed.emit()


# —— 停止背景音乐（可选淡出，秒） ——
func stop_music(fade_sec: float = 0.0) -> void:
	if fade_sec <= 0.0:
		_music.stop()
		return
	var start_db: float = _music.volume_db
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _music.volume_db = v, start_db, -80.0, fade_sec)
	tw.tween_callback(_music.stop)


# 复制一份流，避免 BGM 复用加载到的共享资源时被重复 set loop 污染全局。
func _dup_stream(s: AudioStream) -> AudioStream:
	return s.duplicate()


# —— 总线初始化（若缺失则动态创建，避免依赖手写 default_bus_layout） ——
func _ensure_buses() -> void:
	var order := [[CAT_MUSIC, MUSIC_BASE_DB], [CAT_SFX, SFX_BASE_DB], [CAT_UI, UI_BASE_DB]]
	for entry: Array in order:
		_add_bus(entry[0], entry[1])


# 把当前 music_volume / sfx_volume 应用到对应总线（100% = 基准响度，0 = 静音）。
func _apply_volumes() -> void:
	_set_bus_gain(CAT_MUSIC, music_volume)
	_set_bus_gain(CAT_SFX, sfx_volume)
	_set_bus_gain(CAT_UI, sfx_volume)


# 按线性倍率调整总线音量：gain = db_to_linear(基准dB) * volume，再换算回 dB。
func _set_bus_gain(bus: String, volume: float) -> void:
	var idx := _find_bus_index(bus)
	if idx < 0:
		return
	var base_gain := db_to_linear(_base_db(bus))
	var gain := base_gain * clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(gain, 0.0001)))


func _find_bus_index(bus: String) -> int:
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == bus:
			return i
	return -1


func _base_db(bus: String) -> float:
	match bus:
		CAT_MUSIC: return MUSIC_BASE_DB
		CAT_SFX: return SFX_BASE_DB
		CAT_UI: return UI_BASE_DB
	return 0.0


# —— 设置读写：user://settings.cfg（全局，跨存档槽位共享） ——
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", 1.0)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)
	bgm_index = clampi(int(cfg.get_value("audio", "bgm_index", 0)), 0, BGM_FILES.size() - 1)
	_apply_volumes()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "bgm_index", bgm_index)
	cfg.save(SETTINGS_PATH)


func _add_bus(bus: String, db: float) -> void:
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == bus:
			AudioServer.set_bus_volume_db(i, db)
			return
	AudioServer.add_bus()
	var last := AudioServer.bus_count - 1
	AudioServer.set_bus_name(last, bus)
	AudioServer.set_bus_volume_db(last, db)


# —— 播放器池：按总线分组与配比（SFX 多、UI 少），后续新增音效直接归列 ——
func _build_pool() -> void:
	_build_bus_pool(CAT_SFX, SFX_POOL_SIZE)
	_build_bus_pool(CAT_UI, UI_POOL_SIZE)


func _build_bus_pool(bus: String, size: int) -> void:
	var arr: Array[AudioStreamPlayer] = []
	for _i in size:
		var player := AudioStreamPlayer.new()
		player.bus = bus
		add_child(player)
		arr.append(player)
	_pool[bus] = arr


# BGM 专用播放器，独立挂在 Music 总线。
func _setup_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = CAT_MUSIC
	add_child(_music)


# —— 生成全部核心音效：先尝试加载文件，文件夹空/未导入时回退程序合成 ——
func _generate_all() -> void:
	for name: String in TABLE:
		var cfg: Dictionary = TABLE[name]
		var path: String = cfg.get("path", "")
		var stream: AudioStream = _load_file_if_exists(path)
		if stream == null:
			stream = _synth(name)
		_streams[name] = stream


# 文件优先：目标路径存在且可加载 → 用文件；否则返回 null（触发合成兜底）。
func _load_file_if_exists(path: String) -> AudioStream:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	return stream if stream != null else null


# 找不到文件时的程序合成兜底。新音效若要加合成兜底，在这里补一条即可。
func _synth(name: String) -> AudioStream:
	match name:
		"hammer_swing": return _wav(_noise(0.16, 1.3, 0.55))            # 挥锤：短促"呼"
		"hammer_hit": return _wav(_sum([                                # 命中：低频闷响 + 轻脆响
			_sine(150.0, 90.0, 0.12, 0.6),
			_noise(0.08, 2.0, 0.4),
		], int(0.12 * MIX_RATE)))
		"shatter_glass": return _wav(_sum([                                 # 玻璃碎：高频脆响 + 亮噪声
			_noise(0.22, 3.0, 0.5),
			_sine(1600.0, 2600.0, 0.14, 0.3),
		], int(0.22 * MIX_RATE)))
		"shatter_stone": return _wav(_sum([                                 # 石头碎：低频闷爆 + 低碎
			_noise(0.24, 2.2, 0.6),
			_sine(150.0, 80.0, 0.2, 0.5),
		], int(0.24 * MIX_RATE)))
		"collapse": return _wav(_sum([                                     # 崩塌：一连串闷响 + 隆隆
			_noise(0.5, 2.0, 0.5),
			_sine(120.0, 60.0, 0.45, 0.7),
		], int(0.5 * MIX_RATE)))
		"coin": return _wav(_stagger([                                  # 金币：两声升调"叮—咚"
			[0.00, _sine(988.0, 988.0, 0.18, 0.5)],
			[0.07, _sine(1319.0, 1319.0, 0.30, 0.5)],
		], int(0.4 * MIX_RATE)))
		"explosion": return _wav(_sum([                                 # 爆炸：低频下滑轰 + 噪声
			_sine(90.0, 28.0, 0.6, 0.9, 1.5),
			_noise(0.5, 1.8, 0.5),
		], int(0.6 * MIX_RATE)))
		"launcher_shoot": return _wav(_sum([                            # 炮台发射：短促"咻"
			_sine(620.0, 900.0, 0.14, 0.45, 1.4),
			_noise(0.09, 2.5, 0.35),
		], int(0.14 * MIX_RATE)))
		"launcher_deploy": return _wav(_stagger([                       # 炮台部署：机械升起
			[0.00, _sine(120.0, 220.0, 0.35, 0.45)],
			[0.12, _noise(0.14, 2.2, 0.3)],
		], int(0.4 * MIX_RATE)))
		"damage_tick": return _wav(_sine(880.0, 760.0, 0.05, 0.3))     # 受击小"嗒"（轻）
		"ui_click": return _wav(_sine(720.0, 700.0, 0.06, 0.5))         # 界面点击：短"嗒"
		"ui_hover": return _wav(_sine(1050.0, 1050.0, 0.04, 0.25))      # 悬停：极短"嘀"（轻）
		"upgrade": return _wav(_stagger([                               # 升级：三音上行琶音
			[0.00, _sine(660.0, 660.0, 0.25, 0.5)],
			[0.07, _sine(880.0, 880.0, 0.25, 0.5)],
			[0.14, _sine(1175.0, 1175.0, 0.30, 0.5)],
		], int(0.5 * MIX_RATE)))
		"error": return _wav(_sum([                                     # 无效操作：低沉"镗"
			_sine(220.0, 180.0, 0.22, 0.5),
			_noise(0.12, 2.6, 0.3),
		], int(0.22 * MIX_RATE)))
		"onboarding_pop": return _wav(_stagger([                        # 引导提示：轻快两音
			[0.00, _sine(740.0, 740.0, 0.12, 0.4)],
			[0.07, _sine(1110.0, 1110.0, 0.20, 0.4)],
		], int(0.3 * MIX_RATE)))
		"scene_transition": return _wav(_sum([                          # 过场：碎块爆散的"哗啦"
			_noise(0.5, 1.4, 0.5),
			_sine(400.0, 120.0, 0.4, 0.3),
		], int(0.55 * MIX_RATE)))
	return null


# 正弦音（f0→f1 线性/幂曲线滑音），指数衰减。
func _sine(f0: float, f1: float, dur: float, vol: float, power: float = 1.0) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := lerpf(f0, f1, pow(t, power))
		ph += TAU * f / MIX_RATE
		var env := 1.0 - t
		out[i] = sin(ph) * env * env * vol
	return out


# 白噪声（衰减指数越大衰减越快），带短渐入避免起始爆音。
func _noise(dur: float, decay: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var attack_n := maxi(int(0.008 * MIX_RATE), 1)
	for i in n:
		var env := pow(1.0 - float(i) / float(n), decay) * clampf(float(i) / attack_n, 0.0, 1.0)
		out[i] = randf_range(-1.0, 1.0) * env * vol
	return out


# 把多个样本段【同时叠加】成一段（求和并限幅）。
func _sum(parts: Array, out_len: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(out_len)
	for arr: PackedFloat32Array in parts:
		for i in mini(arr.size(), out_len):
			out[i] += arr[i]
	for i in out_len:
		out[i] = clampf(out[i], -1.0, 1.0)
	return out


# 把多个样本段【按起始时间错开】排进同一段（用于琶音序列）。
func _stagger(parts: Array, out_len: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(out_len)
	for part in parts:
		var start := int(part[0] * MIX_RATE)
		var arr: PackedFloat32Array = part[1]
		for i in arr.size():
			var idx := start + i
			if idx >= out_len:
				break
			out[idx] += arr[i]
	for i in out_len:
		out[i] = clampf(out[i], -1.0, 1.0)
	return out


# 把 float 样本数组编码成 16-bit 单声道 AudioStreamWAV。
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var s := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav
