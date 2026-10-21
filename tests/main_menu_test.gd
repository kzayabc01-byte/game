extends Node

## 主菜单 / 开始游戏 / 关卡工坊验收：正式关卡与草稿隔离，
## 草稿可以发布、进入玩家目录、撤回并保留，副本始终从草稿开始。

const LEVEL_01 := "res://scenes/levels/level_01.tscn"

var _failed := 0


func _ready() -> void:
	var home_packed := load("res://scenes/MainMenu/MainMenu.tscn") as PackedScene
	_check("主页场景可加载", home_packed != null)
	var packed := load("res://scenes/LevelSelectPage/LevelSelectPage.tscn") as PackedScene
	_check("关卡选择场景可加载", packed != null)
	if home_packed == null or packed == null:
		_finish()
		return

	var home := home_packed.instantiate()
	add_child(home)
	await get_tree().process_frame
	var home_texts := _collect_control_texts(home)
	_check("主页提供开始游戏", home_texts.has("开始游戏"))
	_check("主页提供选择关卡", home_texts.has("选择关卡"))
	_check("主页提供关卡工坊", home_texts.has("关卡工坊"))
	_check("主页提供退出游戏", home_texts.has("退出游戏"))
	home.queue_free()
	await get_tree().process_frame

	LevelSelectPage.open_workshop_on_entry = true
	var workshop_entry := packed.instantiate() as LevelSelectPage
	add_child(workshop_entry)
	await get_tree().process_frame
	_check("从主页进入时直接显示关卡工坊",
			(workshop_entry.get_node("Title") as Label).text == "关卡工坊")
	workshop_entry.queue_free()
	await get_tree().process_frame

	var menu := packed.instantiate() as LevelSelectPage
	add_child(menu)
	await get_tree().process_frame

	_check("关卡选择页默认显示正式关卡",
			(menu.get_node("Title") as Label).text == "选择关卡")
	menu.show_workshop()
	_check("关卡选择页可以打开工坊",
			(menu.get_node("Title") as Label).text == "关卡工坊")
	var publish_button := _find_button(menu, "发布为正式关卡")
	_check("发布按钮可以取得", publish_button != null)
	if publish_button != null:
		publish_button.pressed.emit()
		await get_tree().process_frame
	var publish_dialog := _find_visible_publish_dialog(menu)
	_check("点击发布会打开发布窗口", publish_dialog != null)
	if publish_dialog != null:
		publish_dialog.hide()

	menu.show_start_game()
	var play_texts := _collect_control_texts(menu.get_node("%LevelList"))
	_check("开始游戏包含镜面正式关", _has(play_texts, "镜面转角"))
	_check("开始游戏包含折射正式关", _has(play_texts, "折射偏折"))
	_check("开始游戏包含传送门正式关", _has(play_texts, "传送门"))
	_check("开始游戏不显示第7关草稿", not _has(play_texts, "level_07"))
	_check("开始游戏按章节展示", _has(play_texts, "第 1 章") and _has(play_texts, "第 2 章"))

	menu.show_workshop()
	var workshop_texts := _collect_control_texts(menu.get_node("%LevelList"))
	_check("工坊同时显示已发布状态", workshop_texts.has("已发布"))
	_check("工坊同时显示草稿状态", workshop_texts.has("草稿"))
	_check("草稿提供发布入口", workshop_texts.has("发布为正式关卡"))
	_check("正式关卡提供撤回入口", workshop_texts.has("撤回发布"))
	_check("工坊提供新建草稿入口", workshop_texts.has("＋ 新建草稿关卡"))

	var records := menu.get_level_records()
	var published_count := 0
	var draft_count := 0
	for record in records:
		if record[&"published"]:
			published_count += 1
		else:
			draft_count += 1
	_check("六个既有关卡迁移为正式关卡", published_count >= 6)
	_check("第7、8关保留为工坊草稿", draft_count >= 2)

	# 用第1关生成临时副本，完整验证 草稿 → 发布 → 撤回 → 删除。
	var temp_path := menu.duplicate_level_as_draft(LEVEL_01)
	_check("复制正式关卡会生成新文件", not temp_path.is_empty()
			and FileAccess.file_exists(temp_path))
	var temp_metadata := LevelFileIO.read_level_metadata(temp_path)
	_check("副本默认是草稿", int(temp_metadata.get(
			&"publication_state", -1)) == LevelManager.PublicationState.DRAFT)

	var publish_errors := menu.publish_level(temp_path, {
		&"level_name": "发布流程测试",
		&"chapter": 3,
		&"order_in_chapter": 1,
		&"difficulty": 4,
		&"mechanic_tags": PackedStringArray(["镜面", "测试"]),
	})
	_check("结构完整的草稿可以发布", publish_errors.is_empty(),
			"；".join(publish_errors))
	temp_metadata = LevelFileIO.read_level_metadata(temp_path)
	var saved_tags: PackedStringArray = temp_metadata.get(
			&"mechanic_tags", PackedStringArray())
	_check("发布状态保存进关卡", int(temp_metadata.get(
			&"publication_state", -1)) == LevelManager.PublicationState.PUBLISHED)
	_check("章节、难度和标签保存进关卡",
			int(temp_metadata.get(&"chapter", 0)) == 3
			and int(temp_metadata.get(&"difficulty", 0)) == 4
			and saved_tags.has("测试"))

	menu.show_start_game()
	play_texts = _collect_control_texts(menu.get_node("%LevelList"))
	_check("发布后进入开始游戏", _has(play_texts, "发布流程测试"))
	_check("发布后出现第三章", _has(play_texts, "第 3 章"))

	_check("正式关卡可以撤回发布", menu.unpublish_level(temp_path))
	menu.show_start_game()
	play_texts = _collect_control_texts(menu.get_node("%LevelList"))
	_check("撤回后退出开始游戏", not _has(play_texts, "发布流程测试"))
	_check("撤回不会删除关卡文件", FileAccess.file_exists(temp_path))
	_check("草稿文件可以删除", menu._delete_level_file(temp_path))
	_check("临时关卡已经清理", not FileAccess.file_exists(temp_path))

	menu.queue_free()
	await get_tree().process_frame
	if not temp_path.is_empty() and FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	_finish()


func _collect_control_texts(node: Node) -> Array[String]:
	var result: Array[String] = []
	_collect_control_texts_recursive(node, result)
	return result


func _collect_control_texts_recursive(node: Node, out: Array[String]) -> void:
	if node is Button:
		out.append((node as Button).text)
	elif node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_collect_control_texts_recursive(child, out)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _find_visible_publish_dialog(node: Node) -> ConfirmationDialog:
	for child in node.get_children():
		if child is ConfirmationDialog:
			var dialog := child as ConfirmationDialog
			if dialog.visible and dialog.title == "发布为正式关卡":
				return dialog
		var nested := _find_visible_publish_dialog(child)
		if nested != null:
			return nested
	return null


func _has(texts: Array[String], needle: String) -> bool:
	for text in texts:
		if text.contains(needle):
			return true
	return false


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
