extends Node2D
## Four shared prebaked material shards. Admission cannot affect shatter/economy.
const STONE_LIFE := 0.75
var stone_amount := 12
var stone_texture: Texture2D = preload("res://assets/presentation/materials/marble.png")

func explode() -> void:
	add_to_group(&"in_game_entity")
	if not Presentation.admit(self, "fragment", stone_amount):
		queue_free()
		return
	var cells := Presentation.shard_frames(stone_texture)
	var count := maxi(1, ceili(float(stone_amount) / 4.0))
	for texture in cells:
		var particles := CPUParticles2D.new()
		particles.amount = count
		particles.one_shot = true
		particles.explosiveness = 1.0
		particles.lifetime = STONE_LIFE
		particles.texture = texture
		particles.direction = Vector2.UP
		particles.spread = 180
		particles.gravity = Vector2(0,980)
		particles.initial_velocity_min = 100
		particles.initial_velocity_max = 290
		particles.angular_velocity_min = -220
		particles.angular_velocity_max = 220
		particles.scale_amount_min = 1.0
		particles.scale_amount_max = 2.0
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1,1,1,0)])
		ramp.offsets = PackedFloat32Array([0,0.55,1])
		particles.color_ramp = ramp
		particles.z_index = 45
		add_child(particles)
	await get_tree().create_timer(STONE_LIFE + 0.05).timeout
	if is_inside_tree():
		queue_free()
