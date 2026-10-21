extends Node

## 关卡编辑器里的传送门行为：
##  1. 从调色板生成时一次生成“一对”（面对面、自动配对、自动编号）
##  2. Inspector 改编号时，另一扇门同步
##  3. 删除按对删除；复制生成新的一对
## 跑法：tools\dev.bat 40

const PORTAL_SCENE := "res://blocks/portal/portal.tscn"

var _failures: Array[String] = []
var _editor: LevelEditor = null


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("TEST RESULT: FAIL（60 秒超时）")
		get_tree().quit(1))
	_run()


func _check(message: String, condition: bool, detail := "") -> void:
	if condition:
		print("  [OK]   %s" % message)
	else:
		_failures.append(message)
		print("  [FAIL] %s   %s" % [message, detail])


func _run() -> void:
	var packed := load("res://scenes/editor/level_editor.tscn") as PackedScene
	_check("编辑器场景可加载", packed != null)
	if packed == null:
		_finish()
		return

	_editor = packed.instantiate() as LevelEditor
	add_child(_editor)
	await get_tree().process_frame
	await get_tree().process_frame
	_editor.new_level()
	await get_tree().process_frame

	var entry := PaletteData.find_entry(PORTAL_SCENE)
	_check("调色板传送门条目带“成对生成”标记", bool(entry.get("spawn_pair", false)))

	# —— 1. 一次生成一对 ——
	_editor.spawn_pair(entry, Vector2(500, 300))
	await get_tree().process_frame
	var portals := _all_portals()
	_check("一次生成两扇门", portals.size() == 2, "实际 %d" % portals.size())
	if portals.size() != 2:
		_finish()
		return

	var a: Portal = portals[0]
	var b: Portal = portals[1]
	_check("两扇门互相配对", a.linked_portal == b and b.linked_portal == a)
	_check("两扇门编号相同（1）", String(a.pair_id) == "1" and String(b.pair_id) == "1",
			"%s / %s" % [a.pair_id, b.pair_id])
	_check("第二扇旋转 180°（面对面）", absf(absf(b.rotation) - PI) < 0.01, "实际 %.3f" % b.rotation)
	_check("两扇门不重叠", a.position.distance_to(b.position) > 100.0)

	# —— 2. 改编号同步 ——
	_editor.select(a)
	_editor.set_selected_property(&"pair_id", "7")
	_check("本门编号变为 7", String(a.pair_id) == "7", String(a.pair_id))
	_check("配对门同步为 7", String(b.pair_id) == "7", String(b.pair_id))

	var text := _editor.serialize()
	_check("序列化包含配对编号（&\"7\"）", text.contains("pair_id = &\"7\""))
	_check("序列化不写运行时配对引用", not text.contains("linked_portal"))
	_check("保存产物不含编辑器预览状态（相机停用）", not text.contains("enabled = false"))

	# —— 3. 复制成新的一对 ——
	_editor.select(a)
	_editor.duplicate_selected()
	await get_tree().process_frame
	portals = _all_portals()
	_check("复制后共 4 扇门（两对）", portals.size() == 4, "实际 %d" % portals.size())
	var labels := {}
	for portal in portals:
		labels[String(portal.pair_id)] = true
	_check("两对编号互不相同", labels.size() == 2, str(labels.keys()))

	# —— 4. 删除按对 ——
	_editor.select(portals[0])
	_editor.delete_selected()
	await get_tree().process_frame
	portals = _all_portals()
	_check("删除一对后只剩 2 扇门", portals.size() == 2, "实际 %d" % portals.size())
	if portals.size() == 2:
		_check("剩下的两扇仍然互相配对",
				portals[0].linked_portal == portals[1] and portals[1].linked_portal == portals[0])

	_finish()


func _all_portals() -> Array[Portal]:
	var result: Array[Portal] = []
	var root := _editor.get_level_root()
	if root == null:
		return result
	var blocks := root.get_node_or_null("Blocks")
	if blocks == null:
		return result
	for child in blocks.get_children():
		var portal := child as Portal
		if portal != null:
			result.append(portal)
	return result


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
