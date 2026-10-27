extends Node

## 通过真实按钮通知完成场景跳转；测试节点留在 root，避免随 current_scene 一起释放。
const HOME := "res://scenes/MainMenu/MainMenu.tscn"
const MAP := "res://scenes/LevelSelectPage/LevelSelectMap.tscn"
const FIRST_LEVEL := "res://scenes/levels/level_01.tscn"
const WORKSHOP := "res://scenes/LevelSelectPage/LevelSelectPage.tscn"
const EDITOR := "res://scenes/editor/level_editor.tscn"
const WAIT_TIMEOUT_MSEC := 10000

var _failed := 0
var _original_save_path := ""
var _test_save_path := ""
var _original_transition_duration := 0.35
var _original_chapter := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_original_save_path = ProgressStore.save_path
	_test_save_path = "user://navigation_test_%d.json" % Time.get_ticks_usec()
	ProgressStore.save_path = _test_save_path
	_original_transition_duration = SceneTransition.duration
	SceneTransition.duration = 0.03
	_original_chapter = LevelSelectMap.remembered_chapter
	LevelSelectMap.remembered_chapter = 1
	# 本节点已经是 root 的孩子，只解除 current_scene 身份即可继续跨场景验收。
	get_tree().current_scene = null
	_run.call_deferred()


func _run() -> void:
	SceneTransition.change_to_file(HOME)
	if not await _wait_for_scene(HOME, "主页实际加载完成"):
		await _finish()
		return

	var home := get_tree().current_scene
	(home.get_node("MenuGroup/SelectButton") as Button).pressed.emit()
	if not await _wait_for_scene(MAP, "首页选择关卡按钮进入新地图"):
		await _finish()
		return

	var map := get_tree().current_scene as LevelSelectMap
	var playable_marker: LevelMarker = null
	for marker in map.get_chapter_markers(1):
		var candidate := marker as LevelMarker
		if candidate != null and not (candidate.get_node("HitButton") as Button).disabled:
			playable_marker = candidate
			break
	_check("新存档的第一章存在可游玩的入口", playable_marker != null)
	if playable_marker == null:
		await _finish()
		return
	_check("首个可玩入口对应第一个真实关卡", playable_marker.level_path == FIRST_LEVEL)
	(playable_marker.get_node("HitButton") as Button).pressed.emit()
	if not await _wait_for_scene(FIRST_LEVEL, "地图关卡按钮实际进入第一关"):
		await _finish()
		return

	var manager := get_tree().current_scene.get_node("LevelManager") as LevelManager
	_check("地图进入关卡携带正式游玩凭证", manager.run_mode == LevelRunContext.Mode.OFFICIAL)
	manager._set_paused(true)
	await get_tree().process_frame
	_check("游戏确实暂停且暂停菜单可见", get_tree().paused
			and (manager.get_node("PauseMenu") as CanvasLayer).visible)
	(manager.get_node("PauseMenu/Center/PanelContainer/Padding/Buttons/SelectButton") as Button).pressed.emit()
	if not await _wait_for_scene(MAP, "暂停菜单选关按钮返回新地图"):
		await _finish()
		return
	_check("退出暂停关卡后新地图正常运行", not get_tree().paused)

	(get_tree().current_scene.get_node("Design/BackButton") as Button).pressed.emit()
	if not await _wait_for_scene(HOME, "地图返回按钮回到主页"):
		await _finish()
		return
	(get_tree().current_scene.get_node("WorkshopButton") as Button).pressed.emit()
	if not await _wait_for_scene(WORKSHOP, "首页工坊按钮进入旧管理页面"):
		await _finish()
		return
	var workshop := get_tree().current_scene as LevelSelectPage
	_check("旧管理页面显示关卡工坊标题", (workshop.get_node("Title") as Label).text == "关卡工坊")

	var records := workshop.get_level_records()
	var edit := _find_button(workshop, "编辑")
	_check("工坊提供已有文件的编辑按钮", edit != null and not records.is_empty())
	if edit == null or records.is_empty():
		await _finish()
		return
	var expected_edit_path := str(records[0][&"path"])
	edit.pressed.emit()
	if not await _wait_for_scene(EDITOR, "工坊编辑按钮打开关卡编辑器"):
		await _finish()
		return
	var editor := get_tree().current_scene as LevelEditor
	_check("编辑器收到工坊交接的关卡路径", editor.get_current_path() == expected_edit_path)
	_check("编辑器已经载入既有关卡", editor.get_level_root() != null)
	editor._go_to_menu()
	if not await _wait_for_scene(WORKSHOP, "编辑器返回关卡工坊"):
		await _finish()
		return
	_check("编辑器返回后仍为工坊页面", (get_tree().current_scene.get_node("Title") as Label).text == "关卡工坊")
	await _finish()


func _wait_for_scene(expected: String, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + WAIT_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == expected and not SceneTransition.is_transitioning():
			# 等待新场景的 deferred 挂载、清理及布局完成。
			await get_tree().process_frame
			await get_tree().process_frame
			_check(label, true)
			return true
	var current := get_tree().current_scene
	var actual := current.scene_file_path if current != null else "<null>"
	_check(label, false, "等待超时：期望 %s，实际 %s，过渡中 %s" % [expected, actual, SceneTransition.is_transitioning()])
	return false


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _check(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		print("  [OK]   ", label)
	else:
		_failed += 1
		push_error("[FAIL] %s %s" % [label, detail])


func _finish() -> void:
	get_tree().paused = false
	var current := get_tree().current_scene
	get_tree().current_scene = null
	if current != null:
		current.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	ProgressStore.save_path = _original_save_path
	SceneTransition.duration = _original_transition_duration
	LevelSelectMap.remembered_chapter = _original_chapter
	if FileAccess.file_exists(_test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_save_path))
	print("\nTEST RESULT: ", "PASS" if _failed == 0 else "FAIL (%d)" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)
