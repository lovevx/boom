class_name PresentationProfile
extends Resource
## Editable art direction and bounded visual budgets; never used for damage/economy.
@export var panel := Color("#172b40")
@export var panel_light := Color("#25425b")
@export var ink := Color("#0b1828")
@export var gold := Color("#ffc857")
@export var cyan := Color("#76d6ed")
@export var text := Color("#f3f3df")
@export var muted := Color("#a9bccb")
@export var enter_seconds := 0.16
@export var slowmo_cooldown_ms := 2200
@export var fragment_limit := 768
@export var dust_limit := 12
@export var blast_limit := 8
@export var number_limit := 32
@export var coin_limit := 48
@export var popup_limit := 16
@export var hit_limit := 48
@export_group("Motion feedback")
@export var blast_seconds := 0.55
@export var blast_sparks := 10
@export var impact_seconds := 0.24
@export var trail_points := 12
@export var trail_spacing := 5.0
@export var dust_drift := 28.0
@export_group("Scene harmony")
@export_range(0.0, 1.5) var background_saturation := 0.75
@export_range(0.0, 1.5) var background_contrast := 0.85
@export var distance_haze := Color("#b2cddd")
@export_range(0.0, 0.5) var distance_haze_strength := 0.10
@export_range(0.0, 1.5) var ground_saturation := 0.90
@export_range(0.0, 1.5) var ground_contrast := 0.94
@export_range(0.0, 1.5) var material_saturation := 0.86
@export_range(0.0, 1.5) var material_contrast := 0.90
@export_range(0.0, 1.0) var granite_detail_strength := 0.35
@export var granite_base := Color("#a0a7a6")
@export var sunlight := Color("#fff0ce")
@export var window_frame := Color("#344b5b")
@export var contact_shadow := Color("#343c40")
@export_range(0.0, 1.0) var shadow_inner_alpha := 0.28
@export_range(0.0, 1.0) var shadow_outer_alpha := 0.12
@export var ground_contact := Color("#806247")
@export var flash_color := Color("#fff0ce")
@export var spark_color := Color("#ffc05b")
@export var ember_color := Color("#ed924d")
@export var dust_color := Color("#a69b88")
@export_group("Building depth")
@export var building_depth := Vector2(40,-16)
@export_range(0.3,1.0) var building_side_light := 0.58
@export_range(0.5,1.2) var building_front_right_light := 0.83
@export var building_interior := Color("#293845")
@export var building_pilaster := Color("#c7c3b2")
@export var building_slab_shadow := Color("#56616a")
