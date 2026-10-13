extends Node2D
## Public setup API preserved. Crisp, bounded pixel atlas.
const EXPLOSION_DUST := [1,2]
const COLLAPSE_DUST := [5]
var spawn_pos := Vector2.ZERO
var kind := 5
var fx_scale := 1.0

static func pick_dust(pool: Array) -> int:
	return int(pool[randi() % pool.size()]) if not pool.is_empty() else 5

func setup(at: Vector2, value: int, size: float, _forced: bool = false) -> void:
	spawn_pos = at
	kind = value
	fx_scale = size

func _ready() -> void:
	add_to_group(&"in_game_entity")
	if not Presentation.admit(self, "dust"):
		queue_free()
		return
	position = spawn_pos
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = Presentation.animation("dust")
	sprite.animation = "dust"
	sprite.scale = Vector2(2.0, 1.4 if kind == 5 else 2.0) * minf(fx_scale, 1.25)
	sprite.position.y = -30.0 * sprite.scale.y
	sprite.modulate.a = 0.55 if kind == 5 else 0.68
	sprite.z_index = 46
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.material = Presentation.scene_material("dust")
	add_child(sprite)
	sprite.play()
	sprite.animation_finished.connect(queue_free)
	if not Presentation.reduced_motion:
		var drift := Presentation.PROFILE.dust_drift * minf(fx_scale, 1.25)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(sprite, "position:y", sprite.position.y - drift, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "scale:x", sprite.scale.x * 1.3, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
