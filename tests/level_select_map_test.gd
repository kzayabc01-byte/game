extends Node

## 地图选关集成验收。所有进度写入独立测试文件，不触碰玩家的真实存档。

var _failed := 0
var _original_save_path := ""
var _test_save_path := ""
var _map: LevelSelectMap = null
var _activated_count := 0
var _last_activated_path := ""


func _ready() -> void:
	_original_save_path = ProgressStore.save_path
	_test_save_path = "user://level_select_map_test_%d.json" % Time.get_ticks_usec()
	ProgressStore.save_path = _test_save_path
	await _run_tests()
	if is_instance_valid(_map):
		_map.queue_free()
		await get_tree().process_frame
	ProgressStore.save_path = _original_save_path
	if FileAccess.file_exists(_test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_test_save_path))
	_check("测试完成后恢复原存档路径", ProgressStore.save_path == _original_save_path)
	print("TEST RESULT: PASS" if _failed == 0 else "TEST RESULT: FAIL (%d)" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)


func _run_tests() -> void:
	var packed := load("res://scenes/LevelSelectPage/LevelSelectMap.tscn") as PackedScene
	_check("地图场景可以加载", packed != null)
	if packed == null:
		return
	_map = packed.instantiate() as LevelSelectMap
	_check("地图使用独立的选关控制脚本", _map != null)
	if _map == null:
		return
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_check("标题为选择关卡", (_map.get_node("Design/Title") as Label).text == "选择关卡")
	_check("地图提供返回按钮", _map.get_node("Design/BackButton") is Button)
	_check("打开地图默认位于第一章", _map.active_chapter == 1)
	var first_markers: Array = _map.get_chapter_markers(1)
	var second_markers: Array = _map.get_chapter_markers(2)
	var third_markers: Array = _map.get_chapter_markers(3)
	_check("三章均保留八个可编排的入口位置",
			first_markers.size() == 8 and second_markers.size() == 8 and third_markers.size() == 8)
	if first_markers.size() < 2 or third_markers.is_empty():
		return

	var official := ChapterCatalog.get_official_levels()
	_check_chapter_bindings(1, first_markers, official)
	_check_chapter_bindings(2, second_markers, official)
	_check("当前第一章和第二章各有三个真实关卡",
			_count_playable_records(first_markers) == 3 and _count_playable_records(second_markers) == 3)
	_check("第三章未伪造可游玩的关卡", _count_playable_records(third_markers) == 0)
	var first := first_markers[0] as LevelMarker
	var second := first_markers[1] as LevelMarker
	var future := third_markers[0] as LevelMarker
	_check("新存档首关开放且未通关", not first.locked and not first.completed and not first.placeholder)
	_check("新存档第二关锁定", second.locked and not second.completed)
	_check("编号文本按关卡入口显示", (first.get_node("NumberLabel") as Label).text == "01")
	_check("占位入口没有实际关卡路径", future.placeholder and future.level_path.is_empty())

	var first_button := first.get_node("HitButton") as Button
	var first_name := first.get_node("NameLabel") as Label
	first.set_hovered(false)
	_check("平时只显示编号，名称隐藏", not first_name.visible)
	first_button.mouse_entered.emit()
	await get_tree().process_frame
	_check("鼠标悬停显示完整关卡名", first_name.visible and first_name.text == first.level_title)
	first_button.mouse_exited.emit()
	await get_tree().process_frame
	_check("鼠标离开后名称恢复隐藏", not first_name.visible)
	var orbit := first.get_node("HitButton/Visual/OrbitPivot") as Node2D
	_check("绕圈小点具有独立旋转中心", orbit != null)
	var previous_rotation := orbit.rotation
	await get_tree().create_timer(0.1).timeout
	_check("当前关卡的小圆点动画确实在转动", orbit.visible
			and not is_equal_approx(orbit.rotation, previous_rotation))
	_check("锁定占位入口不播放绕圈提示",
			not (future.get_node("HitButton/Visual/OrbitPivot") as Node2D).visible)
	var center := first_button.size * 0.5
	_check("圆形按钮中心可以点击", bool(first_button.call("_has_point", center)))
	_check("圆形按钮方框的四角不可点击",
			not bool(first_button.call("_has_point", Vector2(1.0, 1.0)))
			and not bool(first_button.call("_has_point", Vector2(first_button.size.x - 1.0, 1.0)))
			and not bool(first_button.call("_has_point", Vector2(1.0, first_button.size.y - 1.0)))
			and not bool(first_button.call("_has_point", first_button.size - Vector2.ONE)))

	_capture_activation(second)
	(second.get_node("HitButton") as Button).pressed.emit()
	_check("锁定入口即使收到按钮 pressed 也不能进入关卡", _activated_count == 0)
	_capture_activation(future)
	(future.get_node("HitButton") as Button).pressed.emit()
	_check("未开放占位入口不会触发关卡跳转", _activated_count == 0)
	_capture_activation(first)
	first_button.pressed.emit()
	_check("开放入口发出对应的真实场景路径",
			_activated_count == 1 and _last_activated_path == first.level_path)

	for number in [2, 3, 1]:
		var button := _map.get_node("Design/ChapterButtons/Chapter%02dButton" % number) as Button
		button.pressed.emit()
		await get_tree().process_frame
		_check("点击第 %d 章按钮切换当前章节" % number, _map.active_chapter == number)
		for candidate in [1, 2, 3]:
			var chapter := _map.get_node("Design/MapArea/Chapter%02d" % candidate) as Control
			_check("章节 %d 切换后地图 %d 的显示状态正确" % [number, candidate],
					chapter.visible == (candidate == number))

	_check("测试通关数据写入隔离文件", ProgressStore.record_official_clear(first.level_id))
	_map.refresh_catalog()
	await get_tree().process_frame
	first_markers = _map.get_chapter_markers(1)
	first = first_markers[0] as LevelMarker
	second = first_markers[1] as LevelMarker
	_check("刷新目录后首关显示真实通关状态", first.completed)
	_check("刷新目录后第二关按真实进度解锁", not second.locked and not second.placeholder)
	_check("测试存档路径始终未切回真实玩家存档", ProgressStore.save_path == _test_save_path)


func _check_chapter_bindings(number: int, markers: Array, official: Array[Dictionary]) -> void:
	var records: Array[Dictionary] = []
	for record in official:
		if int(record["chapter"]) == number:
			records.append(record)
	var matched := records.size() <= markers.size()
	for index in mini(records.size(), markers.size()):
		var marker := markers[index] as LevelMarker
		matched = matched and marker.level_id == records[index]["level_id"] \
				and marker.level_path == records[index]["path"] \
				and marker.level_title == records[index]["title"] and not marker.placeholder
	_check("第 %d 章入口绑定章节目录中的真实名称、ID和场景" % number, matched)


func _count_playable_records(markers: Array) -> int:
	var count := 0
	for marker in markers:
		if not (marker as LevelMarker).placeholder:
			count += 1
	return count


func _capture_activation(marker: LevelMarker) -> void:
	# 测试中断开地图导航，保留 Button -> Marker 的真实信号链，避免实际切换场景。
	for connection in marker.get_signal_connection_list("activated"):
		marker.disconnect("activated", connection["callable"])
	marker.activated.connect(_on_marker_activated)


func _on_marker_activated(path: String) -> void:
	_activated_count += 1
	_last_activated_path = path


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  [OK]   " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)
