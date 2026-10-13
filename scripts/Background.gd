extends ParallaxBackground
## Fixed world contact plane, shared 960x540 backdrop and separate foreground.
const BACKDROP = preload("res://assets/presentation/backdrop.png")
const FOREGROUND = preload("res://assets/presentation/foreground.png")

func _ready() -> void:
	for texture in [BACKDROP, FOREGROUND]:
		var layer := ParallaxLayer.new()
		layer.motion_scale = Vector2.ZERO
		add_child(layer)
		for index in [-1, 0, 1]:
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.material = Presentation.scene_material("background")
			# Mirror neighbouring copies so both sky and ground meet at the same edge.
			sprite.scale = Vector2(2 if index == 0 else -2, 2)
			sprite.position = Vector2(960 + index * 1920, 540)
			layer.add_child(sprite)
	var contact := Polygon2D.new()
	contact.polygon = PackedVector2Array([Vector2(-1920,1000),Vector2(3840,1000),Vector2(3840,1010),Vector2(-1920,1010)])
	contact.color = Presentation.PROFILE.ground_contact
	get_child(1).add_child(contact)
