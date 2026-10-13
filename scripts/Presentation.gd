extends Node
## Shared art resources, preferences and presentation-only admission budgets.
signal settings_changed
const PREFS := "user://presentation.cfg"
const PROFILE = preload("res://assets/presentation/profile.tres")
const THEME = preload("res://assets/presentation/theme.tres")
const FONT = preload("res://assets/presentation/fonts/NotoSansCJKsc-Regular.otf")
const NUMBERS = preload("res://assets/presentation/fonts/JetBrainsMono-Regular.ttf")
const WORKSHOP_CHROME = preload("res://scripts/WorkshopChrome.gd")
const BACKGROUND_HARMONY = preload("res://assets/presentation/shaders/background_harmony.gdshader")
const MATERIAL_HARMONY = preload("res://assets/presentation/shaders/material_harmony.gdshader")
const DUST_HARMONY = preload("res://assets/presentation/shaders/dust_harmony.gdshader")
var _popup_scene: PackedScene
var shake_strength := 0.55
var reduced_motion := false
var low_effects := false
var _counts: Dictionary = {}
var _popups: Dictionary = {}
var _frames: Dictionary = {}
var _shards: Dictionary = {}
var _scene_materials: Dictionary = {}

func scene_material(kind: String) -> ShaderMaterial:
	if _scene_materials.has(kind):
		return _scene_materials[kind]
	var material := ShaderMaterial.new()
	if kind == "background":
		material.shader = BACKGROUND_HARMONY
		material.set_shader_parameter("saturation",PROFILE.background_saturation)
		material.set_shader_parameter("contrast",PROFILE.background_contrast)
		material.set_shader_parameter("ground_saturation",PROFILE.ground_saturation)
		material.set_shader_parameter("ground_contrast",PROFILE.ground_contrast)
		material.set_shader_parameter("haze_color",PROFILE.distance_haze)
		material.set_shader_parameter("haze_strength",PROFILE.distance_haze_strength)
	elif kind == "dust":
		material.shader = DUST_HARMONY
		material.set_shader_parameter("dust_color",PROFILE.dust_color)
	else:
		material.shader = MATERIAL_HARMONY
		material.set_shader_parameter("saturation",PROFILE.material_saturation)
		material.set_shader_parameter("contrast",PROFILE.material_contrast)
		material.set_shader_parameter("sunlight",PROFILE.sunlight)
		material.set_shader_parameter("frame_color",PROFILE.window_frame)
		material.set_shader_parameter("block_surface",kind in ["stone","glass","granite"])
		material.set_shader_parameter("glass_surface",kind == "glass")
		if kind == "granite" or kind == "granite_shard":
			material.set_shader_parameter("detail_strength",PROFILE.granite_detail_strength)
			material.set_shader_parameter("surface_base",PROFILE.granite_base)
	_scene_materials[kind] = material
	return material

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(PREFS) == OK:
		shake_strength = clampf(float(config.get_value("presentation", "shake", 0.55)), 0.0, 1.0)
		reduced_motion = bool(config.get_value("presentation", "reduced_motion", false))
		low_effects = bool(config.get_value("presentation", "low_effects", false))
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	_popup_scene = load("res://scenes/GoldPopup.tscn")

func save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("presentation", "shake", shake_strength)
	config.set_value("presentation", "reduced_motion", reduced_motion)
	config.set_value("presentation", "low_effects", low_effects)
	config.save(PREFS)
	if reduced_motion:
		GameFeel.reset()
	settings_changed.emit()

func _on_node_added(node: Node) -> void:
	if node is Control and not node is ColorRect:
		_skin.call_deferred(node)

func _skin(node: Variant) -> void:
	# 大范围拆除可能在延迟回调前释放 UI，先检查引用再检查类型。
	if not is_instance_valid(node) or not node is Control:
		return
	if node.has_meta("workshop_chrome"):
		return
	node.theme = THEME
	if node is Button and not node.text.is_empty() and not node.has_meta("keep_ui_style"):
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			node.remove_theme_stylebox_override(state)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			node.remove_theme_color_override(state)
	elif node is PanelContainer or node is Panel:
		node.remove_theme_stylebox_override("panel")
	if (node is BaseButton and not node.text.is_empty()) or node is PanelContainer or node is Panel:
		if not node.has_node("_WorkshopChrome"):
			var chrome := Control.new()
			chrome.name = "_WorkshopChrome"
			chrome.set_meta("workshop_chrome",true)
			chrome.set_script(WORKSHOP_CHROME)
			node.add_child(chrome)

func _on_node_removed(node: Node) -> void:
	if node.has_meta("presentation_budget"):
		var key: String = node.get_meta("presentation_budget")
		var weight: int = node.get_meta("presentation_weight", 1)
		_counts[key] = maxi(0, int(_counts.get(key, 0)) - weight)

func admit(node: Node, kind: String, weight: int = 1) -> bool:
	var cap: int = int(PROFILE.get(kind + "_limit"))
	if low_effects:
		cap = maxi(2, cap / 3)
	var count: int = _counts.get(kind, 0)
	if count + weight > cap:
		return false
	_counts[kind] = count + weight
	node.set_meta("presentation_budget", kind)
	node.set_meta("presentation_weight", weight)
	return true

func budget_snapshot() -> Dictionary:
	return _counts.duplicate()

func animation(kind: String) -> SpriteFrames:
	if _frames.has(kind):
		return _frames[kind]
	var frames := SpriteFrames.new()
	frames.add_animation(kind)
	frames.set_animation_loop(kind, false)
	frames.set_animation_speed(kind, 18.0 if kind == "blast" else 14.0)
	var atlas: Texture2D = load("res://assets/presentation/fx/" + kind + ".png")
	for index in 8:
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = Rect2(index * 64, 0, 64, 64)
		frames.add_frame(kind, frame)
	_frames[kind] = frames
	return frames

func shard_frames(texture: Texture2D) -> Array[Texture2D]:
	var key := texture.resource_path.get_file().get_basename() if texture else "concrete"
	if _shards.has(key):
		return _shards[key]
	var atlas: Texture2D = load("res://assets/presentation/shards/" + key + ".png")
	var pieces: Array[Texture2D] = []
	for index in 4:
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = Rect2(index * 6, 0, 6, 6)
		pieces.append(frame)
	_shards[key] = pieces
	return pieces

func gold_popup(at: Vector2, amount: int) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cell := Vector2i(floori(at.x / 100.0), floori(at.y / 100.0))
	var key := str(scene.get_instance_id()) + ":" + str(cell)
	var entry: Dictionary = _popups.get(key, {})
	var now := Time.get_ticks_msec()
	var previous: Node2D = entry.get("node")
	if is_instance_valid(previous) and now - int(entry.get("time", 0)) < 180:
		previous.amount += amount
		previous.queue_redraw()
		return
	var popup: Node2D = _popup_scene.instantiate()
	if not admit(popup, "popup"):
		popup.free()
		return
	popup.position = at
	popup.amount = amount
	scene.add_child(popup)
	_popups[key] = {"node": popup, "time": now}
	popup.tree_exited.connect(func() -> void:
		if _popups.get(key, {}).get("node") == popup:
			_popups.erase(key)
	)

func icon(name: String) -> Texture2D:
	var path := "res://assets/presentation/icons/" + name
	return load(path + (".svg" if ResourceLoader.exists(path+".svg") else ".png"))

func bind_dialog(frame: Control, design_size: Vector2, _scroll: bool = true) -> void:
	frame.set_meta("workshop_frame",true)
	# Keep design coordinates stable for fixed layouts; containers fill the design canvas.
	var recenter := func() -> void:
		if not is_instance_valid(frame):
			return
		var viewport := frame.get_viewport_rect().size
		var entrance: Tween = frame.get_meta("workshop_entry") if frame.has_meta("workshop_entry") else null
		if entrance and entrance.is_valid():
			entrance.kill()
		var factor := minf(1.0, minf((viewport.x-64)/design_size.x, (viewport.y-64)/design_size.y))
		frame.size = design_size
		frame.scale = Vector2.ONE * factor
		frame.position = (viewport-design_size*factor)/2.0
	var viewport := frame.get_viewport()
	viewport.size_changed.connect(recenter)
	frame.tree_exiting.connect(func() -> void:
		if viewport.size_changed.is_connected(recenter):
			viewport.size_changed.disconnect(recenter))
	recenter.call()

func screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func dialog_enter(dialog: Control) -> void:
	var previous: Tween = dialog.get_meta("workshop_fade") if dialog.has_meta("workshop_fade") else null
	if previous and previous.is_valid():
		previous.kill()
	dialog.show()
	dialog.modulate = Color.WHITE
	if reduced_motion:
		return
	dialog.modulate.a = 0.0
	var tween := dialog.create_tween()
	dialog.set_meta("workshop_fade",tween)
	tween.tween_property(dialog,"modulate:a",1.0,0.2)
	for frame in dialog.find_children("*","Control",true,false):
		if frame.has_meta("workshop_frame"):
			var last: Tween = frame.get_meta("workshop_entry") if frame.has_meta("workshop_entry") else null
			if last and last.is_valid():
				last.kill()
			var rest: Vector2 = (frame.get_viewport_rect().size-frame.size*frame.scale)/2
			frame.position = rest+Vector2(0,20)
			var entry := frame.create_tween()
			frame.set_meta("workshop_entry",entry)
			entry.tween_property(frame,"position",rest,0.28).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func flash_control(control: Control) -> void:
	for chrome in control.find_children("_WorkshopChrome","Control",true,false):
		chrome.flash()

func celebrate_rebirth() -> void:
	SoundManager.play("upgrade")
	if reduced_motion:
		return
	var layer := CanvasLayer.new()
	layer.layer = 101
	add_child(layer)
	var mark := TextureRect.new()
	mark.texture = icon("rebirth")
	mark.size = Vector2(96,96)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.position = (get_viewport().get_visible_rect().size - mark.size) / 2.0
	mark.pivot_offset = mark.size/2.0
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(mark)
	var tween := mark.create_tween()
	tween.tween_property(mark,"scale",Vector2(1.25,1.25),0.18)
	tween.tween_interval(0.35)
	tween.tween_property(mark,"modulate:a",0.0,0.25)
	tween.tween_callback(layer.queue_free)
