extends Node

## 主菜单测试：确认自动扫描能把 scenes/levels 下的关卡都列出来，
## 并且显示名来自各关卡 LevelManager.level_name（不是文件名兜底）。
## 跑法：tools\dev.bat 40

var _failed := 0


func _ready() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	_check("主菜单场景可加载", packed != null)
	if packed == null:
		_finish()
		return

	var menu := packed.instantiate()
	add_child(menu)
	await get_tree().process_frame

	var texts: Array[String] = []
	_collect_buttons(menu, texts)
	var level_buttons: Array[String] = []
	for text in texts:
		if text == "退出游戏" or text.begins_with("退出"):
			continue
		level_buttons.append(text)

	print("  自动扫描到的关卡按钮：")
	for text in level_buttons:
		print("    - %s" % text)

	_check("至少列出 5 个关卡", level_buttons.size() >= 5, "实际 %d 个" % level_buttons.size())
	_check("包含「折射偏折」", _has(level_buttons, "折射偏折"))
	_check("包含「一分为三」", _has(level_buttons, "一分为三"))
	_check("包含「融冰」", _has(level_buttons, "融冰"))
	_check("包含「传送门」", _has(level_buttons, "传送门"))
	_check("关卡按文件名排序（2 在 5 之前）", _ordered(level_buttons))

	menu.queue_free()
	await get_tree().process_frame
	_finish()


func _collect_buttons(node: Node, out: Array[String]) -> void:
	if node is Button:
		out.append((node as Button).text)
	for child in node.get_children():
		_collect_buttons(child, out)


func _has(texts: Array[String], needle: String) -> bool:
	for text in texts:
		if text.contains(needle):
			return true
	return false


func _ordered(texts: Array[String]) -> bool:
	var index_02 := -1
	var index_05 := -1
	for i in texts.size():
		if texts[i].contains("示例 2"):
			index_02 = i
		if texts[i].contains("示例 5"):
			index_05 = i
	return index_02 >= 0 and index_05 >= 0 and index_02 < index_05


func _finish() -> void:
	print("")
	if _failed == 0:
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s   %s" % [label, detail])
