extends Node

## 主菜单测试：确认自动扫描能把 scenes/levels 下的关卡都列出来，
## 显示名来自各关卡 LevelManager.level_name（不是文件名兜底），
## 以及 debug 构建的编辑 / 删除按钮流程（临时关卡文件，测完清理）。
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
		if text == "退出游戏" or text.begins_with("退出") or text == "×" \
				or text == "编辑" or text.begins_with("关卡编辑器"):
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

	# —— × 删除按钮流程（debug 构建）：临时关卡 → 按 × → 确认 → 文件删除 + 列表刷新 ——
	var temp_path := "res://scenes/levels/level_99_删除测试.tscn"
	_write_temp_level(temp_path)
	var menu2 := packed.instantiate()
	add_child(menu2)
	await get_tree().process_frame
	var texts2: Array[String] = []
	_collect_buttons(menu2, texts2)
	_check("临时关卡出现在列表里", _has(texts2, "删除测试"))

	var temp_row: HBoxContainer = null
	for child in menu2.get_node("%LevelList").get_children():
		if child is HBoxContainer:
			temp_row = child  # level_99 排在最后，取最后一个行容器
	_check("临时关卡所在行存在", temp_row != null)
	var delete_button: Button = null
	var edit_button: Button = null
	if temp_row != null:
		for child in temp_row.get_children():
			if child is Button and (child as Button).text == "编辑":
				edit_button = child
			if child is Button and (child as Button).text == "×":
				delete_button = child
	_check("行内编辑按钮存在", edit_button != null)
	_check("行内删除按钮存在", delete_button != null)

	var dialog: ConfirmationDialog = null
	if delete_button != null:
		delete_button.pressed.emit()
		for child in menu2.get_children():
			if child is ConfirmationDialog:
				dialog = child
	_check("弹出删除确认框", dialog != null)
	if dialog != null:
		dialog.confirmed.emit()
	await get_tree().process_frame
	_check("关卡文件已被删除", not FileAccess.file_exists(temp_path))
	var texts_after: Array[String] = []
	_collect_buttons(menu2, texts_after)
	_check("列表已刷新（不再显示删除测试）", not _has(texts_after, "删除测试"))
	_check("状态栏提示已删除",
			(menu2.get_node("%StatusLabel") as Label).text.contains("已删除关卡"))
	menu2.queue_free()
	await get_tree().process_frame

	# 兜底清理：失败路径下也别把临时关卡留给其他测试
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	_finish()


## 写一个最小可加载的临时关卡场景（没有 LevelManager，显示名走文件名兜底）
func _write_temp_level(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[gd_scene format=3]\n\n[node name=\"Level99\" type=\"Node2D\"]\n")
	file.close()


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
