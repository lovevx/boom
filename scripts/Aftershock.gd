extends Node2D
class_name DemolitionAftershock
## 独立、场景所有的延时伤害。暂停随游戏时间；重开清理；不派生连锁或余震。
var damage := 1.0
var radius := 80.0
var damage_floor := 0.3
var _delay: float

func _ready() -> void:
	_delay = UpgradeManager.aftershock_delay
	add_to_group(&"in_game_entity")
	z_index = 45

func _physics_process(delta: float) -> void:
	_delay -= delta
	queue_redraw()
	if _delay > 0.0:
		return
	_pulse()
	queue_free()

func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.4, 0.8, 1.0, 0.45), 2.0, true)

func _pulse() -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_bodies = true
	var seen := {}
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 512):
		var block: Object = hit.collider
		if not block is BuildingBlock or seen.has(block) or block.hp <= 0.0:
			continue
		seen[block] = true
		var falloff := clampf(1.0 - global_position.distance_to(block.global_position) / maxf(radius, 0.001), damage_floor, 1.0)
		var hit_damage := damage * falloff * UpgradeManager.get_falling_multiplier(block.is_falling())
		var number := preload("res://scenes/DamageNumber.tscn").instantiate()
		number.position = block.global_position
		number.damage = hit_damage
		number.max_hp = block.max_hp
		number.is_lethal = block.hp <= hit_damage
		get_tree().current_scene.get_node("DamageNumberLayer").add_child(number)
		block.register_hit_origin(global_position)
		block.take_damage(hit_damage)
	var fx := preload("res://scripts/BlastFx.gd").new()
	fx.position = global_position
	fx.blast_radius = radius
	fx.modulate = Color(0.4, 0.8, 1.0)
	get_tree().current_scene.add_child(fx)
