extends Node
## Shared art resources, preferences and presentation-only admission budgets.
signal settings_changed
const PREFS := "user://presentation.cfg"
const PROFILE = preload("res://assets/presentation/profile.tres")
const THEME = preload("res://assets/presentation/theme.tres")
const FONT = preload("res://assets/presentation/fonts/NotoSansCJKsc-Regular.otf")
const NUMBERS = preload("res://assets/presentation/fonts/JetBrainsMono-Regular.ttf")
var _popup_scene: PackedScene
var shake_strength := 0.55
var reduced_motion := false
var low_effects := false
var _counts: Dictionary = {}
var _popups: Dictionary = {}
var _frames: Dictionary = {}
var _shards: Dictionary = {}

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
	node.theme = THEME
	if node is Button and not node.text.is_empty():
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			node.remove_theme_stylebox_override(state)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			node.remove_theme_color_override(state)
	elif node is PanelContainer:
		node.remove_theme_stylebox_override("panel")

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
	return load("res://assets/presentation/icons/" + name + ".png")

func bind_dialog(frame: Control, design_size: Vector2, scroll: bool = true) -> void:
	var recenter := func() -> void:
		if not is_instance_valid(frame):
			return
		var viewport := frame.get_viewport_rect().size
		frame.size = Vector2(minf(design_size.x, viewport.x - 64), minf(design_size.y, viewport.y - 64))
		frame.position = (viewport - frame.size) / 2.0
	frame.get_viewport().size_changed.connect(recenter)
	recenter.call()
	if scroll:
		var panel := frame.get_child(0) as PanelContainer
		if panel and panel.get_child_count() > 0:
			var body := panel.get_child(0) as Control
			panel.remove_child(body)
			var scroller := ScrollContainer.new()
			scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
			panel.add_child(scroller)
			body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroller.add_child(body)

func dialog_enter(dialog: Control) -> void:
	dialog.show()
	dialog.modulate = Color.WHITE
	if reduced_motion:
		return
	dialog.modulate.a = 0.0
	dialog.create_tween().tween_property(dialog, "modulate:a", 1.0, PROFILE.enter_seconds)

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
