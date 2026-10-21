extends Node

## 四个示例关卡的“解存在性”测试：按预设角度转光源，断言能真的通关。
## 这是自由放置/关卡设计的安全网：改了积木参数导致关卡无解，这里会立刻红。
## 跑法：tools\dev.bat 40

const CASES: Array[Dictionary] = [
	{ "path": "res://scenes/levels/level_02_折射入门.tscn", "deg": 0.0, "frames": 45 },
	{ "path": "res://scenes/levels/level_03_分束.tscn", "deg": 0.0, "frames": 45 },
	{ "path": "res://scenes/levels/level_04_融冰.tscn", "deg": 0.0, "frames": 240 },
	{ "path": "res://scenes/levels/level_05_传送门.tscn", "deg": 0.0, "frames": 45 },
]

var _failed := 0
var _completed := false


func _ready() -> void:
	GameEvents.level_completed.connect(_on_level_completed)
	for case in CASES:
		await _run_case(case)
	print("")
	if _failed == 0:
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)


func _on_level_completed(_level_name: String) -> void:
	_completed = true


func _run_case(case: Dictionary) -> void:
	_completed = false
	var path: String = case["path"]
	var packed := load(path) as PackedScene
	if packed == null:
		_check("%s 加载" % path.get_file(), false, "场景加载失败")
		return

	var level := packed.instantiate()
	add_child(level)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var source: LightSource = null
	for node in get_tree().get_nodes_in_group(LightSource.SOURCE_GROUP):
		var candidate := node as LightSource
		if candidate != null and level.is_ancestor_of(candidate):
			source = candidate
			break
	if source == null:
		_check("%s 光源" % path.get_file(), false, "关卡里找不到 LightSource")
		level.queue_free()
		await get_tree().process_frame
		return

	# 把光源转到“标准解”的角度
	source.rotation = deg_to_rad(float(case["deg"]))

	var frames: int = case["frames"]
	for _i in frames:
		if _completed:
			break
		await get_tree().physics_frame

	_check("%s（转到 %.0f° 通关）" % [path.get_file(), float(case["deg"])], _completed)
	if not _completed:
		_dump_portals(level)
	level.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


## 失败时的诊断输出：传送门是否配对、编号、朝向
func _dump_portals(level: Node) -> void:
	var blocks := level.get_node_or_null("Blocks")
	if blocks == null:
		return
	for child in blocks.get_children():
		var portal := child as Portal
		if portal != null:
			print("    调试 %s: pair_id='%s' linked=%s pos=%s rot=%.3f"
					% [portal.name, portal.pair_id, portal.linked_portal,
					portal.position, portal.rotation])


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s   %s" % [label, detail])
