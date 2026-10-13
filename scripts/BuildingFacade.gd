class_name DemolitionBuildingFacade
extends Node2D
## Block-owned architectural skin. No collisions, input, timers or gameplay state.
var depth_only := false
var column := 0
var glass := false
var floor_panel := false
var wall_color := Color.WHITE
var slab_color := Color.WHITE

func _draw() -> void:
	var profile := Presentation.PROFILE
	var light := lerpf(1.04,profile.building_front_right_light,float(column)/11.0)
	var wall := wall_color * Color(light,light,light)
	if depth_only:
		var d: Vector2 = profile.building_depth
		var a := Vector2(-20,-20)
		var b := Vector2(20,-20)
		var c := Vector2(20,20)
		# Surviving neighbours project a dark rear wall into a broken facade opening.
		draw_rect(Rect2(a+d,Vector2(40,40)),profile.building_interior)
		var top := wall * Color(0.86,0.86,0.83)
		var side := wall * Color(profile.building_side_light,profile.building_side_light,profile.building_side_light)
		if column < 11:
			side = profile.building_interior.lightened(0.06)
		draw_colored_polygon(PackedVector2Array([a,b,b+d,a+d]),top)
		draw_colored_polygon(PackedVector2Array([b,c,c+d,b+d]),side)
		if floor_panel:
			var slab_side := slab_color * Color(profile.building_side_light,profile.building_side_light,profile.building_side_light)
			draw_colored_polygon(PackedVector2Array([Vector2(20,8),c,c+d,Vector2(20,8)+d]),slab_side)
			draw_line(c,c+d,profile.building_interior,2.0)
		draw_line(b+d,c+d,profile.building_interior,2.0)
		return
	if glass:
		# Real glass occupies the central 32x32 opening; the surrounding masonry is solid.
		draw_rect(Rect2(-20,-20,40,2),wall)
		draw_rect(Rect2(-20,14,40,6),wall)
		draw_rect(Rect2(-20,-18,4,32),wall)
		draw_rect(Rect2(16,-18,4,32),wall)
		draw_rect(Rect2(-18,-20,36,36),profile.window_frame,false,2.0)
		draw_line(Vector2(-16,-18),Vector2(16,-18),profile.building_interior,2.0)
		draw_line(Vector2(-16,-18),Vector2(-16,14),profile.building_interior,2.0)
		draw_rect(Rect2(-20,16,40,2),profile.building_pilaster * Color(light,light,light))
		draw_rect(Rect2(-20,18,40,2),profile.building_slab_shadow)
	if floor_panel:
		draw_rect(Rect2(-20,8,40,2),profile.building_pilaster * Color(light,light,light))
		draw_rect(Rect2(-20,18,40,2),profile.building_slab_shadow)
	# Continuous edge columns and a central pier establish two regular window bays.
	var strip := Rect2()
	match column:
		0: strip = Rect2(-20,-20,12,40)
		5: strip = Rect2(10,-20,10,40)
		6: strip = Rect2(-20,-20,10,40)
		11: strip = Rect2(8,-20,12,40)
	if strip.size.x > 0:
		draw_rect(strip,profile.building_pilaster * Color(light,light,light))
		draw_rect(Rect2(strip.position,Vector2(2,40)),profile.sunlight * Color(0.89,0.89,0.89))
		draw_rect(Rect2(strip.end.x-2,-20,2,40),profile.building_slab_shadow * Color(1,1,1,0.55))
