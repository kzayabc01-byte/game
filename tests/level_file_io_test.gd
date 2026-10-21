extends Node

## 关卡序列化往返测试（关卡编辑器的验证门 1）。
## 运行：godot --headless --path . res://tests/level_file_io_test.tscn
## 覆盖：现有关卡序列化结构、幂等往返、新增连接、next_level_scene、
##       文件名校验/建议、capture/restore 抵消 _ready 副作用。

var _failures: Array[String] = []


func _ready() -> void:
	# 看门狗：_run 中途崩溃时 quit 不会执行，保证进程必定退出而不是挂死
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("TEST RESULT: FAIL（60 秒超时，测试脚本崩溃或挂起）")
		get_tree().quit(1))
	_run()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  [OK]   ", message)
	else:
		_failures.append(message)
		print("  [FAIL] ", message)


func _run() -> void:
	# 1. level_06 序列化结构
	var packed06 := load("res://scenes/levels/level_06_机关秀.tscn") as PackedScene
	var level06 := packed06.instantiate()
	var text := LevelFileIO.serialize_level(level06)
	_check(text.contains("[gd_scene load_steps=9 format=3]"), "level_06 头部 load_steps=9")
	_check(text.contains("[node name=\"Level06\" instance=ExtResource(\"1_base\")]"), "level_06 根节点行")
	_check(text.contains("level_name = \"机关秀 · 重力镜面\""), "LevelManager 覆盖 level_name")
	_check(text.contains("publication_state = 1"), "正式关卡发布状态被序列化")
	_check(text.contains("chapter = 2") and text.contains("order_in_chapter = 3"),
			"章节与章节内顺序被序列化")
	_check(text.contains("mechanic_tags = PackedStringArray(\"重力\", \"电线\", \"压力传感\")"),
			"玩法标签被序列化")
	_check(text.contains("position = Vector2(120, 400)"), "Source 位置覆盖")
	_check(text.contains(
			"[connection signal=\"pressed_changed\" from=\"Blocks/PressureSensor\" to=\"Blocks/WireMirror\" method=\"_on_signal\"]"),
			"压力传感器→镜面电线连接行")
	_check(text.contains("target_node = NodePath(\"../Mirror\")"), "电线节点目标指向镜面")
	_check(text.contains("repeat = true"), "镜面电线循环参数写入")
	_check(not text.contains("WireLayer") and not text.contains("LevelEditor"), "输出不含编辑器节点")

	# 2. 幂等往返：写出 → 读入 → 再序列化 → 完全一致
	var roundtrip_path := "user://io_roundtrip.tscn"
	_check(LevelFileIO.write_text(roundtrip_path, text) == OK, "写出 user:// 临时文件")
	var reloaded := (load(roundtrip_path) as PackedScene).instantiate()
	var text2 := LevelFileIO.serialize_level(reloaded)
	_check(text == text2, "往返序列化逐字节一致")
	reloaded.free()

	# 3. 改动 + 新增电线再往返
	var sensor := level06.get_node("Blocks/PressureSensor")
	var extra_link := (load("res://blocks/action_link/action_link.tscn") as PackedScene).instantiate() as ActionLink
	extra_link.name = "Wire"
	extra_link.target_node = NodePath("../Mirror")
	extra_link.move_offset = Vector2(32, 0)
	level06.get_node("Blocks").add_child(extra_link)
	sensor.pressed_changed.connect(Callable(extra_link, &"_on_signal"))
	var source := level06.get_node("Blocks/Source") as Node2D
	source.position = Vector2(150, 420)
	var text3 := LevelFileIO.serialize_level(level06)
	_check(text3.contains(
			"[connection signal=\"pressed_changed\" from=\"Blocks/PressureSensor\" to=\"Blocks/Wire\" method=\"_on_signal\"]"),
			"新增电线连接被序列化")
	_check(text3.contains("move_offset = Vector2(32, 0)"), "新增电线动作参数被序列化")
	_check(text3.contains("position = Vector2(150, 420)"), "改动后的位置被序列化")
	LevelFileIO.write_text(roundtrip_path, text3)
	var reloaded3 := (load(roundtrip_path) as PackedScene).instantiate()
	var sensor3 := reloaded3.get_node("Blocks/PressureSensor")
	_check(sensor3.get_signal_connection_list(&"pressed_changed").size() == 2,
			"重载后 pressed_changed 有 2 条连接")
	reloaded3.free()
	level06.free()

	# 4. level_01 的 next_level_scene
	var packed01 := load("res://scenes/levels/level_01.tscn") as PackedScene
	var level01 := packed01.instantiate()
	var text01 := LevelFileIO.serialize_level(level01)
	_check(text01.contains("[gd_scene load_steps=7 format=3]"), "level_01 头部 load_steps=7")
	_check(text01.contains("path=\"res://scenes/levels/level_02_折射入门.tscn\""),
			"下一关 PackedScene 进入 ext 表")
	_check(text01.contains("next_level_scene = ExtResource("), "next_level_scene 覆盖行")
	level01.free()

	# 5. 文件名与解析
	# 建议名 = 现有最大编号 + 1（不写死编号：关卡会增删）
	var suggested := LevelFileIO.suggest_file_name()
	var max_existing := 0
	for entry in LevelFileIO.scan_levels():
		var number_text := entry.trim_prefix("level_").split("_")[0]
		if number_text.is_valid_int():
			max_existing = maxi(max_existing, number_text.to_int())
	_check(suggested == "level_%02d_说明.tscn" % (max_existing + 1),
			"建议文件名接在最大编号后（%s）" % suggested)
	_check(LevelFileIO.validate_file_name("level_07_说明.tscn"), "校验合法文件名")
	_check(LevelFileIO.validate_file_name("level_08.tscn"), "校验纯编号文件名")
	_check(not LevelFileIO.validate_file_name("level_base.tscn"), "拒绝基座文件名")
	_check(not LevelFileIO.validate_file_name("foo.tscn"), "拒绝非关卡文件名")
	_check(LevelFileIO.get_base_scene_path_from_file("res://scenes/levels/level_06_机关秀.tscn")
			== LevelFileIO.BASE_SCENE_DEFAULT, "解析基座场景路径")
	_check(LevelFileIO.read_root_name("res://scenes/levels/level_06_机关秀.tscn") == "Level06",
			"解析根节点名")
	_check(LevelFileIO.is_valid_wire(&"active_changed", &"_on_signal"), "电线兼容表允许 active_changed→_on_signal")
	_check(LevelFileIO.is_valid_wire(&"pressed_changed", &"_on_signal"), "电线兼容表允许 pressed_changed→_on_signal")
	_check(not LevelFileIO.is_valid_wire(&"active_changed", &"set_enabled"), "电线兼容表拒绝旧入口 set_enabled")
	_check(not LevelFileIO.is_valid_wire(&"active_changed", &"reset_state"), "电线兼容表拒绝 reset_state")
	_check(not LevelFileIO.queue_level_for_edit("res://scenes/levels/不存在.tscn"),
			"编辑队列拒绝不存在的关卡")
	_check(LevelFileIO.queue_level_for_edit("res://scenes/levels/level_01.tscn"),
			"现有关卡可进入编辑队列")
	_check(LevelFileIO.take_level_to_edit() == "res://scenes/levels/level_01.tscn",
			"编辑队列交接正确路径")
	_check(LevelFileIO.take_level_to_edit().is_empty(), "编辑队列取出后清空")
	var draft_errors := LevelFileIO.validate_level_for_publication(
			"res://scenes/levels/level_07_说明.tscn")
	_check(draft_errors.has("至少需要一个通关目标"), "缺少通关目标的草稿不能发布")

	# 6. capture/restore 抵消 portal._ready 自动配对副作用
	var base := (load(LevelFileIO.BASE_SCENE_DEFAULT) as PackedScene).instantiate()
	var portal1 := (load("res://blocks/portal/portal.tscn") as PackedScene).instantiate() as Node2D
	portal1.name = "PortalA"
	portal1.position = Vector2(200, 200)
	var portal2 := (load("res://blocks/portal/portal.tscn") as PackedScene).instantiate() as Node2D
	portal2.name = "PortalB"
	portal2.position = Vector2(400, 200)
	base.get_node("Blocks").add_child(portal1)
	base.get_node("Blocks").add_child(portal2)
	var captured := LevelFileIO.capture_props(base)
	add_child(base)
	await get_tree().process_frame
	await get_tree().process_frame
	var paired: bool = portal1.get("linked_portal") != null
	LevelFileIO.restore_props(base, captured)
	_check(paired and portal1.get("linked_portal") == null, "capture/restore 抵消 _ready 自动配对")
	base.queue_free()
	await get_tree().process_frame

	if _failures.is_empty():
		print("TEST RESULT: PASS")
		get_tree().quit(0)
	else:
		print("TEST RESULT: FAIL（%d 项）" % _failures.size())
		get_tree().quit(1)
