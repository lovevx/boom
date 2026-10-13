extends Node2D
## One-shot blast; exclusively visual, never used by hit detection.
var blast_radius := 80.0
var _age := 0.0

func _ready() -> void:
	add_to_group(&"in_game_entity")
	if not Presentation.admit(self, "blast"):
		queue_free()
		return
	var sprite := AnimatedSprite2D.new()
	z_index = 48
	sprite.sprite_frames = Presentation.animation("blast")
	sprite.animation = "blast"
	sprite.scale = Vector2.ONE * clampf(blast_radius / 30.0, 1.5, 9.5)
	sprite.modulate.a = 0.65 if Presentation.reduced_motion else 0.9
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	sprite.play()
	sprite.animation_finished.connect(sprite.hide)

func _process(delta: float) -> void:
	_age += delta
	if _age >= Presentation.PROFILE.blast_seconds:
		queue_free()
	queue_redraw()

func _draw() -> void:
	if Presentation.reduced_motion:
		return
	var t := clampf(_age / Presentation.PROFILE.blast_seconds, 0.0, 1.0)
	var expansion := 1.0 - pow(1.0 - t, 3.0)
	var ring := blast_radius * lerpf(0.18, 1.12, expansion)
	var fade := pow(1.0 - t, 2.0)
	var flash := Presentation.PROFILE.flash_color
	flash.a = fade * 0.65
	var ember := Presentation.PROFILE.ember_color
	ember.a = fade * 0.3
	var spark := Presentation.PROFILE.spark_color
	spark.a = fade
	draw_arc(Vector2.ZERO, ring, 0.0, TAU, 64, flash, lerpf(6.0, 1.0, t), true)
	if Presentation.low_effects:
		return
	# Secondary pressure front and hot fragments outlast the short bright core.
	draw_arc(Vector2.ZERO, ring * 0.82, 0.0, TAU, 48, ember, 2.0, true)
	for i in Presentation.PROFILE.blast_sparks:
		var ray := Vector2.from_angle(i * 2.39996)
		var speed := blast_radius * (1.1 + (i % 3) * 0.23)
		var point := ray * (12.0 + speed * t) + Vector2(0, 85.0 * t * t)
		draw_line(point - ray * (12.0 * (1.0-t)), point, spark, 2.0)
