from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]

def edit(path,transform):
    p=ROOT/path
    p.write_text(transform(p.read_text(encoding="utf-8-sig")),encoding="utf-8",newline="\n")

def menu(s):
    s=s.replace('\t_build_stats_button()','\t_build_stats_button()\n\t_build_presentation_menu()')
    s=s.replace('btn.position = Vector2(48, 950)','btn.position = Vector2(48, 950)\n\tbtn.name = "CareerButton"')
    s += '''

var _brand_root: Control

func _build_presentation_menu() -> void:
\t$Bg.texture = preload("res://assets/presentation/yard.png")
\t$Bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
\t$Bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVER
\t$MenuArt.hide()
\t_brand_root = Control.new()
\t_brand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
\t_brand_root.size = Vector2(1920,1080)
\tadd_child(_brand_root)
\tvar panel := Panel.new()
\tpanel.position = Vector2(752,380)
\tpanel.size = Vector2(416,414)
\tpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
\tpanel.add_theme_stylebox_override("panel", Presentation.THEME.get_stylebox("panel","PanelContainer"))
\t_brand_root.add_child(panel)
\tvar logo := TextureRect.new()
\tlogo.texture = preload("res://assets/presentation/logo.png")
\tlogo.position = Vector2(540,160)
\tlogo.size = Vector2(840,200)
\tlogo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
\tlogo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
\tlogo.mouse_filter = Control.MOUSE_FILTER_IGNORE
\t_brand_root.add_child(logo)
\tvar caption := Label.new()
\tcaption.text = "砸碎 · 赚取 · 升级 · 自动轰炸"
\tcaption.position = Vector2(600,330)
\tcaption.size = Vector2(720,50)
\tcaption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
\tcaption.add_theme_font_size_override("font_size",26)
\tcaption.add_theme_color_override("font_outline_color",Presentation.PROFILE.ink)
\tcaption.add_theme_constant_override("outline_size",6)
\t_brand_root.add_child(caption)
\tfor index in 4:
\t\tvar button: Button = get_node(["StartButton","HowButton","SettingsButton","QuitButton"][index])
\t\tbutton.reparent(_brand_root, false)
\t\tbutton.position = Vector2(792,414 + index*86)
\t\tbutton.size = Vector2(336,66)
\t\tbutton.add_theme_font_size_override("font_size",28 if index==0 else 24)
\t\tbutton.icon = Presentation.icon(["hammer","building","gear","lock"][index])
\t\tbutton.add_theme_constant_override("icon_max_width",32)
\t_brand_root.move_to_front()
\t# Modal overlays must be above the new brand root.
\tfor name in ["SlotMenu","HowTo","SettingsPanel","StatsPanel"]:
\t\tget_node(name).move_to_front()
\tget_viewport().size_changed.connect(_layout_presentation_menu)
\t_layout_presentation_menu()

func _layout_presentation_menu() -> void:
\tvar viewport := get_viewport().get_visible_rect().size
\t_brand_root.position.x = (viewport.x-1920)/2.0
\tfor control in _slot_menu.get_children():
\t\tif control is Control and not (control is ColorRect):
\t\t\tif not control.has_meta("design_x"):
\t\t\t\tcontrol.set_meta("design_x",control.position.x)
\t\t\tcontrol.position.x = float(control.get_meta("design_x")) + (viewport.x-1920)/2.0
\t$CareerButton.position.y = viewport.y - 116
'''
    return s

def hud(s):
    s=s.replace('\tSoundManager.play_music()','\tSoundManager.play_music()\n\t_setup_presentation_hud()')
    a=s.index('func _pulse_coin_bar() -> void:')
    b=s.find('\nfunc ',a+5)
    s=s[:a]+'''func _pulse_coin_bar() -> void:
\tif Presentation.reduced_motion:
\t\treturn
\tif _pulse_tween and _pulse_tween.is_valid():
\t\treturn
\t_coin_bar.pivot_offset = _coin_bar.size/2.0
\t_pulse_tween = create_tween()
\t_pulse_tween.tween_property(_coin_bar,"scale",Vector2(1.035,1.035),0.06)
\t_pulse_tween.tween_property(_coin_bar,"scale",Vector2.ONE,0.12)

'''+s[b:]
    s=s.replace('func _confirm_restart_ok() -> void:\n','func _confirm_restart_ok() -> void:\n\tGameFeel.reset()\n')
    s += '''

func _setup_presentation_hud() -> void:
\tvar icon: TextureRect = $GoldBar/CoinHBox/CoinIcon
\ticon.texture = Presentation.icon("coin")
\ticon.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
\ticon.position = Vector2(12,10)
\ticon.size = Vector2(44,44)
\ticon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
\t_label.add_theme_font_override("font",Presentation.NUMBERS)
\t_label.add_theme_color_override("font_color",Presentation.PROFILE.gold)
\t_label.add_theme_color_override("font_outline_color",Presentation.PROFILE.ink)
\t_label.add_theme_constant_override("outline_size",4)
\tvar badge := Panel.new()
\tbadge.mouse_filter = Control.MOUSE_FILTER_IGNORE
\tbadge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
\tbadge.add_theme_stylebox_override("panel",Presentation.THEME.get_stylebox("normal","Button"))
\t_coin_bar.add_child(badge)
\t_coin_bar.move_child(badge,0)
\tget_viewport().size_changed.connect(_layout_presentation_hud)
\t_layout_presentation_hud()

func _layout_presentation_hud() -> void:
\tvar viewport := get_viewport().get_visible_rect().size
\t_coin_bar.position = Vector2(24,24)
\t_coin_bar.size = Vector2(300,64)
\tvar right := viewport.x - 24
\tfor name in ["SkillTreeButton","RestartButton","MenuButton","SettingsButton"]:
\t\tvar button: Button = get_node("GoldBar/"+name)
\t\tvar width := 184.0 if name in ["SkillTreeButton","MenuButton"] else 160.0
\t\tright -= width
\t\tbutton.position = Vector2(right,24)
\t\tbutton.size = Vector2(width,64)
\t\tright -= 12
\t_reinc_btn.position = Vector2(344,24)
\t_reinc_btn.size = Vector2(144,64)
'''
    return s

def settings(s):
    s=s.replace('var _music_pct: Label','var _shake_slider: HSlider\nvar _motion_checkbox: CheckBox\nvar _density_select: OptionButton\nvar _music_pct: Label')
    s=s.replace('\tSoundManager.settings_changed.connect(_refresh)','\tSoundManager.settings_changed.connect(_refresh)\n\tPresentation.settings_changed.connect(_refresh)')
    s=s.replace('Vector2(640, 480)','Vector2(760, 790)')
    s=s.replace('\tbgm_hint.text = "点击切换当前背景音乐，立即生效并自动保存"','\tbgm_hint.text = "点击切换，立即生效并自动保存"')
    s=s.replace('\t# —— 底部说明 ——','\t_build_presentation_settings(vbox)\n\tPresentation.bind_dialog(root,panel_size)\n\n\t# —— 底部说明 ——')
    s=s.replace('func open() -> void:\n\t_refresh()\n\tshow()','func open() -> void:\n\t_refresh()\n\tPresentation.dialog_enter(self)')
    s=s.replace('func _refresh() -> void:\n','''func _refresh() -> void:
\tif _shake_slider:
\t\t_shake_slider.set_value_no_signal(Presentation.shake_strength)
\t\t_motion_checkbox.set_pressed_no_signal(Presentation.reduced_motion)
\t\t_density_select.select(1 if Presentation.low_effects else 0)
''')
    s += '''

func _build_presentation_settings(parent: VBoxContainer) -> void:
\tvar heading := Label.new()
\theading.text = "画面与动态效果"
\theading.add_theme_font_size_override("font_size",26)
\theading.add_theme_color_override("font_color",Presentation.PROFILE.cyan)
\tparent.add_child(heading)
\tvar shake_row := HBoxContainer.new()
\tshake_row.add_theme_constant_override("separation",18)
\tparent.add_child(shake_row)
\tvar label := Label.new()
\tlabel.text = "震屏强度"
\tlabel.custom_minimum_size.x = 150
\tshake_row.add_child(label)
\t_shake_slider = HSlider.new()
\t_shake_slider.name = "ShakeStrength"
\t_shake_slider.min_value = 0
\t_shake_slider.max_value = 1
\t_shake_slider.step = 0.05
\t_shake_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
\tshake_row.add_child(_shake_slider)
\t_shake_slider.value_changed.connect(func(value: float) -> void:
\t\tPresentation.shake_strength = value
\t\tPresentation.save_preferences())
\t_motion_checkbox = CheckBox.new()
\t_motion_checkbox.name = "ReducedMotion"
\t_motion_checkbox.text = "减少动态：关闭震屏、慢动作及大幅动画"
\tparent.add_child(_motion_checkbox)
\t_motion_checkbox.toggled.connect(func(value: bool) -> void:
\t\tPresentation.reduced_motion = value
\t\tPresentation.save_preferences())
\tvar density_row := HBoxContainer.new()
\tparent.add_child(density_row)
\tvar density_label := Label.new()
\tdensity_label.text = "特效密度"
\tdensity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
\tdensity_row.add_child(density_label)
\t_density_select = OptionButton.new()
\t_density_select.name = "EffectDensity"
\t_density_select.add_item("标准")
\t_density_select.add_item("低")
\t_density_select.custom_minimum_size.x = 180
\tdensity_row.add_child(_density_select)
\t_density_select.item_selected.connect(func(index: int) -> void:
\t\tPresentation.low_effects = index == 1
\t\tPresentation.save_preferences())
'''
    return s

def upgrade(s):
    s=s.replace('const L3 := 395.0','const L3 := 330.0').replace('const L2 := 280.0','const L2 := 245.0')
    s=s.replace('Vector2(900, 440)','Vector2(900, 420)')
    s=s.replace('if not visible:\n\t\treturn','if not visible or Presentation.reduced_motion:\n\t\treturn')
    s=s.replace('bg.color = Color(0x14, 0x1d, 0x14) / 255.0','bg.color = Presentation.PROFILE.panel')
    s=s.replace('noise_rect.modulate = Color(1, 1, 1, 0.35)','noise_rect.modulate = Color(1, 1, 1, 0.06)')
    s=s.replace('Color(0.12, 0.20, 0.14)','Color(0.13, 0.23, 0.33)')
    s=s.replace('Color(0.13, 0.26, 0.15)','Color(0.13, 0.26, 0.36)')
    s=s.replace('Color(0.30, 0.55, 0.32)','Color(0.30, 0.55, 0.72)')
    s=s.replace('\tadd_child(_tree)','\tadd_child(_tree)\n\tPresentation.bind_dialog(_tree,panel_size,false)')
    a=s.index('\tvar icon_lb := Label.new()')
    b=s.index('\t# 等级',a)
    s=s[:a]+'''\tvar icon_lb := TextureRect.new()
\ticon_lb.texture = Presentation.icon({"hammer":"hammer","econ":"coin","bomb":"bomb","build":"building"}[d["branch"]])
\ticon_lb.position = Vector2(12,8)
\ticon_lb.size = Vector2(36,36)
\ticon_lb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
\ticon_lb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
\ticon_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
\toct.add_child(icon_lb)
'''+s[b:]
    a=s.index('\tvar lock_lb := Label.new()')
    b=s.index('\toct.add_child(lock_lb)',a)
    s=s[:a]+'''\tvar lock_lb := TextureRect.new()
\tlock_lb.texture = Presentation.icon("lock")
\tlock_lb.position = Vector2(20,16)
\tlock_lb.size = Vector2(24,24)
\tlock_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
\tlock_lb.visible = false
'''+s[b:]
    s=s.replace('("font_size", 13)','("font_size", 18)')
    s=s.replace('("font_size", 17)','("font_size", 22)').replace('("font_size", 14)','("font_size", 20)')
    s=s.replace(r'"\\n".join(lines)',r'"\n".join(lines)')
    s=s.replace('lines.append("🔒 需先解锁：%s" % st.reason)','lines.append("需先解锁：%s" % st.reason)')
    s=s.replace('func _spawn_up_arrow(d: Dictionary) -> void:\n','func _spawn_up_arrow(d: Dictionary) -> void:\n\tif Presentation.reduced_motion:\n\t\treturn\n')
    # Retain pause semantics but use the shared reduced-motion-aware entrance.
    a=s.index('\t# 整体淡入进场')
    b=s.index('\nfunc close()',a)
    s=s[:a]+'\tPresentation.dialog_enter(self)\n\n'+s[b:]
    return s

def panels(s):
    s=s.replace('\troot.add_child(bg)','\troot.add_child(bg)\n\tPresentation.bind_dialog.call_deferred(root,panel_size)')
    s=s.replace('\tshow()\n','\tPresentation.dialog_enter(self)\n')
    return s

def onboarding(s):
    s=s.replace('TREE_BTN_POS\n','_tree_button_position()\n')
    s=s.replace('1.0 + 0.10 * sin(_pulse)','1.0 if Presentation.reduced_motion else 1.0 + 0.06 * sin(_pulse)')
    s += '''

func _tree_button_position() -> Vector2:
\tvar button := get_tree().current_scene.get_node_or_null("GoldHUD/GoldBar/SkillTreeButton") as Control
\treturn button.get_global_rect().get_center() if button else TREE_BTN_POS
'''
    return s

def launcher(s):
    s=s.replace('\tSoundManager.play("launcher_deploy")\n','\tSoundManager.play("launcher_deploy")\n\tif Presentation.reduced_motion:\n\t\t_ensure_timer_started()\n\t\treturn\n')
    return s

for path,transform in [
    ("scripts/MainMenu.gd",menu),("scripts/GoldHUD.gd",hud),("scripts/SettingsPanel.gd",settings),
    ("scripts/UpgradePanel.gd",upgrade),("scripts/ReincarnationPanel.gd",panels),("scripts/StatsPanel.gd",panels),
    ("scripts/Onboarding.gd",onboarding),("scripts/BombLauncher.gd",launcher)]:
    edit(path,transform)
print("PRESENTATION_UI_INTEGRATED")
