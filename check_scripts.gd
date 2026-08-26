extends SceneTree

func _init() -> void:
	var paths := [
		"res://scripts/DustFx.gd",
		"res://scripts/BuildingBlock.gd",
		"res://scripts/BombProjectile.gd",
		"res://scripts/BuildingSetup.gd",
	]
	for p in paths:
		var s = load(p)
		print("LOADED: ", p, " -> ", s)
		if s == null:
			push_error("FAILED to load: " + p)
	# 校验尘土图集尺寸与配置一致（期望宽 = 10 列 × 单帧宽）
	var dust_script = load("res://scripts/DustFx.gd")
	for k in [1, 2, 3, 4, 5]:
		var cfg: Dictionary = dust_script.DUST[k]
		var sheet: Texture2D = load(cfg["path"])
		var rows: int = int(ceil(float(int(cfg["frames"])) / 10.0))
		var exp_w: int = 10 * int(cfg["w"])
		var exp_h: int = rows * int(cfg["h"])
		print("DUST ", k, " sheet=", sheet.get_size(), " expect=", Vector2i(exp_w, exp_h), " frames=", cfg["frames"], " fps=", cfg["fps"])
	quit()
