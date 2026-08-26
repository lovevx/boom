extends Node2D

func _ready() -> void:
	var dust_script = load("res://scripts/DustFx.gd")
	for k in [1, 2, 3, 4, 5]:
		var fx = dust_script.new()
		fx.setup(Vector2(100 + k * 40, 100), k, 1.0, true)
		add_child(fx)
		await get_tree().process_frame
		var anim = fx.get_node("DustSprite") as AnimatedSprite2D
		var frames = anim.sprite_frames
		print("DUST", k, " built_frames=", frames.get_frame_count("dust"),
				" fps=", frames.get_animation_speed("dust"),
				" frame0_size=", frames.get_frame_texture("dust", 0).get_size())
	# 随机种也来一发
	var fx = dust_script.new()
	fx.setup(Vector2(400, 300), -1, 0.7, false)
	add_child(fx)
	print("dust test done")
	get_tree().quit()
