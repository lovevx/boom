class_name DemolitionContactShadow
extends Node2D
## Two crisp ground bands. top_level keeps deployment/recoil off the contact plane.
@export var footprint := 112.0
@export var projected_side := false
var owner_visual: Node2D
var ground_y := 1000.0

func _ready() -> void:
	z_index = -5
	if owner_visual:
		top_level = true
		global_position = Vector2(owner_visual.global_position.x, ground_y)
		owner_visual.visibility_changed.connect(_sync_visibility)
		_sync_visibility()
	queue_redraw()

func _sync_visibility() -> void:
	visible = owner_visual.visible

func reveal() -> void:
	modulate.a = 0.0
	if Presentation.reduced_motion:
		modulate.a = 1.0
		return
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)

func _draw() -> void:
	var half := footprint * 0.5
	var outer := Presentation.PROFILE.contact_shadow
	outer.a = Presentation.PROFILE.shadow_outer_alpha
	var inner := Presentation.PROFILE.contact_shadow
	inner.a = Presentation.PROFILE.shadow_inner_alpha
	draw_colored_polygon(PackedVector2Array([
		Vector2(-half-6,0),Vector2(half+6,0),Vector2(half+6,4),
		Vector2(half+12,4),Vector2(half+12,10),Vector2(-half-12,10),
		Vector2(-half-12,4),Vector2(-half-6,4)]), outer)
	draw_rect(Rect2(-half,0,footprint,4),inner)
	if projected_side:
		var front := Vector2(half,0)
		var back := front + Presentation.PROFILE.building_depth
		draw_colored_polygon(PackedVector2Array([front,back,back+Vector2(12,10),front+Vector2(0,10)]),outer)
		draw_colored_polygon(PackedVector2Array([front,back,back+Vector2(0,4),front+Vector2(0,4)]),inner)
