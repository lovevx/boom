extends Node2D
## 炸弹发射器管理器：在 Main 场景中预置 4 台 BombLauncher（左二右二，默认隐藏+禁用），
## 依据 UpgradeManager 的发射器等级逐个"部署"激活。
## 升级解锁顺序固定为 l1→r1→l2→r2（对应 Spawn0..Spawn3，左/右成对出现）。
## 监听 launcher_upgraded 信号实时激活新炮台并刷新冷却；多炮台天然错开放射（激活时机不同）。

signal first_launcher_deployed   # 首台炮台首次部署时发出（供新手引导监听）

const MAX_LAUNCHERS := 4
const LAUNCHER_SCENE := preload("res://scenes/BombLauncher.tscn")

var _launchers: Array[Node2D] = []
var _ever_deployed := false   # 是否已有过首台炮台部署


func _ready() -> void:
	_precreate()
	_upgrade_manager_connected()
	# 初始按当前等级同步（通常为 0，全部隐藏）
	_sync(UpgradeManager.get_bomb_launcher_level())


func _precreate() -> void:
	var spawn_parent := get_tree().current_scene.get_node_or_null("LauncherSpawns")
	if spawn_parent == null:
		push_warning("LauncherManager: 未找到 LauncherSpawns 容器，无法预置发射器")
		return
	for i in range(MAX_LAUNCHERS):
		var marker := spawn_parent.get_node_or_null("Spawn%d" % i)
		var launcher: Node2D = LAUNCHER_SCENE.instantiate()
		launcher.name = "BombLauncher%d" % (i + 1)
		if marker != null:
			launcher.global_position = marker.global_position
			launcher.rotation = marker.rotation
		# 每台炮台的横向瞄准偏好固定为均匀间隔（-1..1），覆盖建筑的左→中→右
		if launcher.has_method("set_aim_zone"):
			launcher.set_aim_zone(-1.0 + 2.0 * float(i) / float(MAX_LAUNCHERS - 1))
		launcher.visible = false
		launcher.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(launcher)
		_launchers.append(launcher)


func _upgrade_manager_connected() -> void:
	# 已有信号连接则用同一个（防御性），此处仅连接一次
	if UpgradeManager.launcher_upgraded.is_connected(_on_launcher_upgraded):
		return
	UpgradeManager.launcher_upgraded.connect(_on_launcher_upgraded)


func _on_launcher_upgraded(new_level: int) -> void:
	_sync(new_level)


# 依据等级对齐炮台：激活前 N 台，其余隐藏+禁用；已激活的刷新冷却等属性。
func _sync(level: int) -> void:
	var count := clampi(level, 0, MAX_LAUNCHERS)
	if count > 0 and not _ever_deployed:
		_ever_deployed = true
		first_launcher_deployed.emit()
	for i in range(MAX_LAUNCHERS):
		var launcher := _launchers[i]
		if not is_instance_valid(launcher):
			continue
		var should_active: bool = i < count
		if should_active and not launcher.visible:
			launcher.visible = true
			launcher.process_mode = Node.PROCESS_MODE_INHERIT
			launcher.play_deploy()
		elif not should_active and launcher.visible:
			launcher.visible = false
			launcher.process_mode = Node.PROCESS_MODE_DISABLED
		if should_active and launcher.has_method("refresh_stats"):
			launcher.refresh_stats()