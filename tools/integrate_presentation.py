"""One-time surgical integration. Original economy and save scripts are untouched."""
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]

def edit(path, transform):
    p=ROOT/path
    original=p.read_text(encoding="utf-8-sig")
    updated=transform(original)
    p.write_text(updated,encoding="utf-8",newline="\n")

def function(s,name,body):
    pattern=rf"(?ms)^func {re.escape(name)}\(.*?(?=^func |\Z)"
    match=re.search(pattern,s)
    if not match:
        raise ValueError("Missing function: "+name)
    return s[:match.start()]+body.rstrip()+"\n\n\n"+s[match.end():]

def project(s):
    s=s.replace('SaveManager="*res://scripts/SaveManager.gd"','SaveManager="*res://scripts/SaveManager.gd"\nPresentation="*res://scripts/Presentation.gd"')
    return s+'\n[gui]\n\ntheme/custom="res://assets/presentation/theme.tres"\n'

def building(s):
    mapping={"石膏石":"plaster","普通玻璃":"glass","浮法玻璃":"float_glass","石灰石":"limestone","大理石":"marble",
             "混凝土":"concrete","红砖":"brick","钢化玻璃":"tempered_glass","瓷砖":"ceramic","花岗岩":"granite","金属":"steel"}
    a=s.index("const MATERIAL_FILE := {")
    b=s.index("\n}",a)+2
    block=s[a:b]
    for old,new in mapping.items():
        # Change values only, leaving gameplay material keys intact.
        block=re.sub(r'(:\s*)"' + old + r'"',lambda m:m[1]+'"'+new+'"',block)
    s=s[:a]+block+s[b:]
    s=s.replace('load("res://assets/ui/%s.png" % file)','load("res://assets/presentation/materials/%s.png" % file)')
    s=s.replace('sprite.modulate = _brightness_modulate(base, block_hp, jitter)','sprite.modulate = Color(jitter, jitter, jitter)')
    s=s.replace('sprite.material = _get_material_effect(entry.material)','sprite.material = null')
    return s

def launcher(s):
    s=s.replace('const SPRITE_SCALE := 0.46','const SPRITE_SCALE := 2.0')
    s=s.replace('const ART_HALF := 120.0','const ART_HALF := 32.0')
    s=s.replace('Vector2(183.0, 98.0)','Vector2(27.0, 10.0)')
    s=s.replace('const FEET_BOTTOM_Y := 239.0','const FEET_BOTTOM_Y := 62.0')
    s=function(s,"_setup_sprite",'''func _setup_sprite() -> void:
\t_turret.sprite_frames = preload("res://assets/presentation/launcher_frames.tres")
\t_turret.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
\t_turret.play("idle")''')
    s=s.replace('Vector2(SPRITE_SCALE * _dir, SPRITE_SCALE)','Vector2(-SPRITE_SCALE * _dir, SPRITE_SCALE)')
    s=s.replace('Vector2(mz_local.x * _dir, mz_local.y)','Vector2(-mz_local.x * _dir, mz_local.y)')
    s=s.replace('func _play_recoil() -> void:\n','func _play_recoil() -> void:\n\tif Presentation.reduced_motion:\n\t\treturn\n')
    s=s.replace('flash.polygon = _circle_points(12.0)','flash.polygon = PackedVector2Array([Vector2(-12,-4),Vector2(-4,-4),Vector2(-4,-12),Vector2(4,-12),Vector2(4,-4),Vector2(12,-4),Vector2(12,4),Vector2(4,4),Vector2(4,12),Vector2(-4,12),Vector2(-4,4),Vector2(-12,4)])')
    s=s.replace('get_tree().current_scene.add_child(flash)','flash.add_to_group(&"in_game_entity")\n\tget_tree().current_scene.add_child(flash)')
    return s

def bomb(s):
    s=s.replace('res://assets/ui/炮弹图.png','res://assets/presentation/icons/bomb.png')
    s=s.replace('const BOMB_ART_SIZE := 204.0','const BOMB_ART_SIZE := 24.0')
    return function(s,"_play_explosion_fx",'''func _play_explosion_fx() -> void:
\tvar fx := preload("res://scripts/BlastFx.gd").new()
\tfx.position = global_position
\tfx.blast_radius = radius
\tget_tree().current_scene.add_child(fx)''')

def block(s):
    s=s.replace('SoundManager.play("shatter_glass" if is_glass else "shatter_stone")','SoundManager.play("shatter_glass" if is_glass else ("shatter_metal" if debris_texture and "steel" in debris_texture.resource_path else "shatter_stone"))')
    a=s.index('\tvar popup_scene: PackedScene = preload("res://scenes/GoldPopup.tscn")')
    b=s.index('\t_spawn_coin_flight(amount)',a)
    s=s[:a]+'\tPresentation.gold_popup(_shatter_origin, amount)\n'+s[b:]
    s=s.replace('if amount <= 0:\n\t\treturn','if amount <= 0 or Presentation.reduced_motion:\n\t\treturn')
    s=s.replace('var coin_count := clampi(amount, 3, 9)','var coin_count := clampi(amount, 1, 3)')
    s=s.replace('var target: Vector2 = bar.get_global_transform_with_canvas().origin + bar.size / 2.0','var target: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * (bar.get_global_transform_with_canvas().origin + Vector2(32, 32))')
    return s

def feel(s):
    s=s.replace('var _key_seq := 0','var _active_level := 0\nvar _last_slowmo_ms := -100000\nvar _last_impact_shake_ms := -100000\nvar _key_seq := 0')
    s=function(s,"impact",'''func impact(level: int) -> void:
\tif level <= 0 or Presentation.reduced_motion:
\t\treturn
\tvar now := Time.get_ticks_msec()
\tif _active_level > level and now < _scale_deadline_ms:
\t\treturn
\tif level >= 3:
\t\t_strong_time_ms = now
\t\tif now - _last_slowmo_ms >= Presentation.PROFILE.slowmo_cooldown_ms:
\t\t\t_last_slowmo_ms = now
\t\t\t_active_level = level
\t\t\t_apply_scale(_scale_params(level))
\telse:
\t\t_active_level = level
\t\t_apply_scale(_scale_params(level))
\tif now - _last_impact_shake_ms >= 120:
\t\t_last_impact_shake_ms = now
\t\t_shake(level)''')
    s=function(s,"resolve_chain",'''func resolve_chain(count: int) -> void:
\tif count <= 0 or _time_since_strong_ms() < STRONG_SWALLOW_MS:
\t\treturn
\timpact(3 if count >= 3 else 2)''')
    s=s.replace('func reset() -> void:\n','func reset() -> void:\n\t_active_level = 0\n')
    s=s.replace('\t_active_key = ""\n\tEngine.time_scale = 1.0','\t_active_key = ""\n\t_active_level = 0\n\tEngine.time_scale = 1.0')
    return s

def camera(s):
    s=s.replace('\t_start_drift()\n','')
    s=s.replace('var _intensity: float = 0.0','var _last_shake_ms := -100000\nvar _intensity: float = 0.0')
    s=s.replace('func shake(intensity: float, duration: float) -> void:\n\t_intensity = intensity','''func shake(intensity: float, duration: float) -> void:
\tif Presentation.reduced_motion or Presentation.shake_strength <= 0.0:
\t\toffset = Vector2.ZERO
\t\treturn
\tvar now := Time.get_ticks_msec()
\tif now - _last_shake_ms < 90:
\t\treturn
\t_last_shake_ms = now
\t_intensity = maxf(intensity * Presentation.shake_strength, _intensity * 0.5)''')
    s=s.replace('\t_elapsed += delta','\t_elapsed += delta / maxf(Engine.time_scale, 0.001)')
    s=s.replace('func _process(delta: float) -> void:\n','func _process(delta: float) -> void:\n\tif Presentation.reduced_motion:\n\t\toffset = Vector2.ZERO\n\t\t_duration = 0.0\n')
    return s

def hammer(s):
    s=s.replace('func _play_swing(at: Vector2) -> void:\n','func _play_swing(at: Vector2) -> void:\n\tif Presentation.reduced_motion:\n\t\treturn\n')
    return function(s,"_draw",'''func _draw() -> void:
\t_draw_range()
\tdraw_texture_rect(Presentation.icon("hammer"), Rect2(-28,-32,56,56), false)
\t_draw_cooldown_ring()''')

def number(s):
    s=s.replace('func _ready() -> void:\n','func _ready() -> void:\n\tif not Presentation.admit(self, "number"):\n\t\tqueue_free()\n\t\treturn\n')
    s=s.replace('\t_configure_label()','\t_label.add_theme_font_override("font", Presentation.NUMBERS)\n\t_configure_label()')
    s=s.replace('randf_range(30.0, 50.0)','(10.0 if Presentation.reduced_motion else randf_range(30.0, 50.0))')
    s=s.replace('scale = Vector2(1.3, 1.3)','scale = Vector2.ONE if Presentation.reduced_motion else Vector2(1.15, 1.15)')
    return s

def coin(s):
    s=s.replace('func _ready() -> void:\n','func _ready() -> void:\n\tif not Presentation.admit(self, "coin"):\n\t\tqueue_free()\n\t\treturn\n')
    return function(s,"_draw",'''func _draw() -> void:
\tdraw_texture_rect(Presentation.icon("coin"), Rect2(-9,-9,18,18), false)''')

def popup(s):
    s=s.replace('Vector2(0.5, 0.5)','(Vector2.ONE if Presentation.reduced_motion else Vector2(0.8, 0.8))')
    s=s.replace('Vector2(0.0, -60.0)','Vector2(0.0, -12.0 if Presentation.reduced_motion else -48.0)')
    return function(s,"_draw",'''func _draw() -> void:
\tdraw_texture_rect(Presentation.icon("coin"),Rect2(-12,-12,24,24),false)
\tvar text := "+%d" % amount
\tdraw_string_outline(Presentation.NUMBERS,Vector2(17,8),text,HORIZONTAL_ALIGNMENT_LEFT,-1,24,4,Presentation.PROFILE.ink)
\tdraw_string(Presentation.NUMBERS,Vector2(17,8),text,HORIZONTAL_ALIGNMENT_LEFT,-1,24,Presentation.PROFILE.gold)''')

def sound(s):
    # Keep the user's BGM. Only gameplay/UI effects use the presentation sound pack.
    s=re.sub(r'"res://assets/audio/(?!bgm/)[^"]*/([^/"]+)\.(?:mp3|wav)"',lambda m:'"res://assets/presentation/audio/sfx/'+m[1]+'.wav"',s)
    s=s.replace('const TABLE := {','const TABLE := {\n\t"shatter_metal": {"path":"res://assets/presentation/audio/sfx/shatter_metal.wav", "bus":CAT_SFX, "volume":-8.0},')
    s=s.replace('var _streams := {}','var _last_played := {}\nvar _duck_tween: Tween\nvar _streams := {}')
    s=s.replace('\t_generate_all()','\t_generate_all()\n\tvar limiter := AudioEffectLimiter.new()\n\tlimiter.ceiling_db = -1.0\n\tlimiter.threshold_db = -6.0\n\tAudioServer.add_bus_effect(0, limiter)')
    s=s.replace('func play(name: String) -> void:\n','''func play(name: String) -> void:
\tvar now := Time.get_ticks_msec()
\tvar cooldown: int = 100 if name in ["coin", "damage_tick", "ui_hover"] else (70 if name.begins_with("shatter") else 0)
\tif now - int(_last_played.get(name, -100000)) < cooldown:
\t\treturn
\t_last_played[name] = now
\tif name == "explosion" and is_instance_valid(_music):
\t\tif _duck_tween and _duck_tween.is_valid():
\t\t\t_duck_tween.kill()
\t\t_music.volume_db = -10.0
\t\t_duck_tween = create_tween()
\t\t_duck_tween.tween_property(_music, "volume_db", 0.0, 0.4)
''')
    s=s.replace('\tplayer.volume_db = cfg["volume"]','\tplayer.volume_db = cfg["volume"] - 3.0\n\tplayer.pitch_scale = randf_range(0.95, 1.05) if bus == CAT_SFX else 1.0')
    return s

def transition(s):
    s=s.replace('func transition_to(target_scene: String) -> void:\n','''func transition_to(target_scene: String) -> void:
\tGameFeel.reset()
\tif Presentation.reduced_motion:
\t\tget_tree().paused = false
\t\tget_tree().change_scene_to_file(target_scene)
\t\treturn
''')
    s=s.replace('_shake_time = shake_duration','_shake_time = 0.0')
    return s

for path,transform in [
    ("project.godot",project),("scripts/BuildingSetup.gd",building),("scripts/BombLauncher.gd",launcher),
    ("scripts/BombProjectile.gd",bomb),("scripts/BuildingBlock.gd",block),("scripts/GameFeel.gd",feel),
    ("scripts/CameraShake.gd",camera),("scripts/Hammer.gd",hammer),("scripts/DamageNumber.gd",number),
    ("scripts/CoinFly.gd",coin),("scripts/GoldPopup.gd",popup),("scripts/SoundManager.gd",sound),
    ("scripts/ScreenTransition.gd",transition)]:
    edit(path,transform)

# Static animation resource, imported textures referenced directly (works in PCK exports).
frames='[gd_resource type="SpriteFrames" load_steps=36 format=3]\n[ext_resource type="Texture2D" path="res://assets/presentation/launcher_attack.png" id="1"]\n'
for i in range(33):
    frames+=f'[sub_resource type="AtlasTexture" id="f{i}"]\natlas = ExtResource("1")\nregion = Rect2({64*i}, 0, 64, 64)\n'
entry=lambda i:'{"duration":1.0,"texture":SubResource("f'+str(i)+'")}'
frames+='[resource]\nanimations = [{"frames":['+entry(0)+'],"loop":false,"name":&"idle","speed":1.0},\n'
frames+='{"frames":['+','.join(entry(i) for i in range(33))+'],"loop":false,"name":&"attack","speed":16.0}]\n'
(ROOT/"assets/presentation/launcher_frames.tres").write_text(frames,encoding="utf-8")
print("PRESENTATION_INTEGRATED")
