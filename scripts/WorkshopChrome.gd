extends Control
## Presentation-only engraving, signal lights and tactile button feedback.
## A child overlay: never takes input and never changes its owner's hit rectangle.
var _owner: Control
var _presentation: Node
var _time := 0.0
var _hover := false
var _hot := 0.0
var _pressed := false
var _flash := 0.0
var _redraw_elapsed := 0.0
var _last_motion := false

func _ready() -> void:
	_owner = get_parent() as Control
	_presentation = get_node("/root/Presentation")
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_owner.resized.connect(queue_redraw)
	if _owner is BaseButton:
		_owner.mouse_entered.connect(_set_hover.bind(true))
		_owner.mouse_exited.connect(_set_hover.bind(false))
		_owner.focus_entered.connect(_set_hover.bind(true))
		_owner.focus_exited.connect(_set_hover.bind(false))
		_owner.button_down.connect(_press.bind(true))
		_owner.button_up.connect(_press.bind(false))
	queue_redraw()

func _set_hover(value: bool) -> void:
	_hover = value
	queue_redraw()

func _press(value: bool) -> void:
	_pressed = value
	if not _presentation.reduced_motion:
		_flash = 0.65 if value else 1.0
	queue_redraw()

func flash() -> void:
	if not _presentation.reduced_motion:
		_flash = 1.0
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var reduced: bool = _presentation.reduced_motion
	if reduced:
		_time = 0.0
		_flash = 0.0
		_hot = 1.0 if _hover else 0.0
		if reduced != _last_motion:
			queue_redraw()
	else:
		_time += delta
		_hot = move_toward(_hot,1.0 if _hover else 0.0,delta*8)
		_flash = move_toward(_flash,0.0,delta*2.8)
		_redraw_elapsed += delta
		if _redraw_elapsed >= 1.0/30.0:
			_redraw_elapsed = 0.0
			queue_redraw()
	_last_motion = reduced

func _draw() -> void:
	if not is_instance_valid(_owner) or size.x < 40 or size.y < 32:
		return
	var ink := Color("#07121c")
	var cyan := Color("#76d6ed")
	var gold := Color("#ffc857")
	var is_button := _owner is BaseButton
	if is_button:
		if _owner.disabled:
			return
		var primary: bool = _owner.theme_type_variation == &"PrimaryButton"
		var accent := ink if primary else cyan
		if _hot > 0.01:
			accent.a = _hot*0.7
			for x in [19.0,size.x-19]:
				draw_line(Vector2(x,19),Vector2(x,size.y-19),accent,2.0)
			# A restrained, traveling highlight on the bevel, away from button text.
			if not _presentation.reduced_motion:
				var start := 23+fposmod(_time*90,maxf(1,size.x-70))
				draw_line(Vector2(start,8),Vector2(minf(size.x-23,start+22),8),Color(1,1,0.85,0.65*_hot),2)
		if primary:
			var breathe := 1.0 if _presentation.reduced_motion else 0.65+0.25*sin(_time*2.2)
			draw_rect(Rect2(size.x-21,size.y/2-3,4,6),Color(0.1,0.22,0.25,breathe))
		if _pressed:
			draw_line(Vector2(22,size.y-13),Vector2(size.x-22,size.y-13),ink,3)
	else:
		# Physical corner braces and low-contrast blueprint engraving.
		var line := Color(0.4,0.65,0.72,0.055)
		if size.y > 120 and size.x > 280:
			for x in range(32,int(size.x)-24,32):
				draw_line(Vector2(x,24),Vector2(x,size.y-24),line,1)
			for y in range(32,int(size.y)-24,32):
				draw_line(Vector2(24,y),Vector2(size.x-24,y),line,1)
			for i in 3:
				var level := 1.0 if _presentation.reduced_motion else (1.0 if int(_time*2)%3 == i else 0.24)
				draw_rect(Rect2(size.x/2-13+i*10,10,6,3),Color(cyan,level*0.7))
			# Surface scratches remain small and subtle at every panel size.
			for i in 6:
				var x := 30.0+fposmod(i*137.0,maxf(1,size.x-90))
				var y := size.y-27.0-float(i%2)*3
				draw_line(Vector2(x,y),Vector2(x+14,y-2),Color(0.7,0.8,0.83,0.14),1)
			var scan := 0.0 if _presentation.reduced_motion else fposmod(_time*0.16,1.0)
			var x := 64+scan*maxf(0,size.x-160)
			draw_line(Vector2(x,size.y-18),Vector2(minf(size.x-64,x+24),size.y-18),Color(gold,0.7),2)
	if _flash > 0:
		draw_rect(Rect2(7,7,size.x-14,size.y-14),Color(gold,_flash*0.12))
		draw_line(Vector2(24,8),Vector2(size.x-24,8),Color(gold,_flash),3)
