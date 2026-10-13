class_name DemolitionImpactFx
extends Node2D
## Short, budgeted hammer / muzzle accents. No collision or gameplay timing.
var muzzle := false
var direction := Vector2.RIGHT
var power := false
var _age := 0.0

func _ready() -> void:
	add_to_group(&"in_game_entity")
	z_index = 49
	if not Presentation.admit(self, "hit"):
		queue_free()
		return
	rotation = direction.angle()

func _process(delta: float) -> void:
	_age += delta
	if _age >= Presentation.PROFILE.impact_seconds:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var t := clampf(_age / Presentation.PROFILE.impact_seconds, 0.0, 1.0)
	var fade := (1.0 - t) * (1.0 - t)
	var gold := Presentation.PROFILE.spark_color
	gold.a = fade
	var cream := Presentation.PROFILE.flash_color
	cream.a = fade
	if Presentation.reduced_motion:
		cream.a = fade * 0.45
		draw_circle(Vector2.ZERO, 6.0, cream)
		return
	if muzzle:
		var reach := lerpf(32.0, 52.0, t)
		var wedge := PackedVector2Array([Vector2(-3,-5),Vector2(reach*0.48,-9),Vector2(reach,0),Vector2(reach*0.48,9),Vector2(-3,5)])
		draw_colored_polygon(wedge, gold)
		draw_line(Vector2.ZERO, Vector2(reach * 0.7, 0), cream, 4.0)
	else:
		var reach := (58.0 if power else 38.0) * (0.75 + t * 0.6)
		# Broken arcs leave the struck material and damage numbers readable.
		for side in 2:
			var start := -2.6 + side * PI + t * 0.4
			draw_arc(Vector2.ZERO, reach, start, start + 1.25, 16, gold, 4.0 * (1.0-t) + 1.0, true)
			draw_arc(Vector2.ZERO, reach - 5.0, start, start + 0.8, 12, cream, 2.0, true)
	var count := 3 if Presentation.low_effects else 6
	for i in count:
		var angle := (float(i) / count - 0.5) * (1.2 if muzzle else TAU)
		var ray := Vector2.from_angle(angle)
		var distance := (10.0 + t * (40.0 + i * 4.0)) * (1.4 if power else 1.0)
		var point := ray * distance + Vector2(0, 28.0 * t * t)
		draw_line(point - ray * (8.0 * (1.0-t)), point, cream if i % 2 == 0 else gold, 2.0)
