extends Node2D
## One-shot blast; exclusively visual, never used by hit detection.
var blast_radius := 80.0

func _ready() -> void:
	add_to_group(&"in_game_entity")
	if not Presentation.admit(self, "blast"):
		queue_free()
		return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = Presentation.animation("blast")
	sprite.animation = "blast"
	sprite.scale = Vector2.ONE * clampf(blast_radius / 30.0, 1.5, 9.5)
	sprite.z_index = 48
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	sprite.play()
	sprite.animation_finished.connect(queue_free)
