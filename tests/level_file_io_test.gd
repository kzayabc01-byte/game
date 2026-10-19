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
	_check(text.contains("[gd_scene load_steps=11 format=3]"), "level_06 头部 load_steps=11")
	_check(text.contains("[node name=\"Level06\" instance=ExtResource(\"1_base\")]"), "level_06 根节点行")
	_check(text.contains("level_name = \"机关秀 · 实体机关组\""), "LevelManager 覆盖 level_name")
	_check(text.contains("position = Vector2(120, 400)"), "Source 位置覆盖")
	_check(text.contains(
			"[connection signal=\"pressed_changed\" from=\"Blocks/PressureSensor\" to=\"Blocks/MovingBase\" method=\"set_enabled\"]"),
			"压力传感器→底座连接行")
	_check(text.contains(
			"[connection signal=\"active_changed\" from=\"Blocks/TriggerSwitch\" to=\"Blocks/StoneDoor\" method=\"set_external_open\"]"),
			"触发开关→石门连接行")
	_check(not text.contains("WireLayer") and not text.contains("LevelEditor"), "输出不含编辑器节点")

	# 2. 幂等往返：写出 → 读入 → 再序列化 → 完全一致
	var roundtrip_path := "user://io_roundtrip.tscn"
	_check(LevelFileIO.write_text(roundtrip_path, text) == OK, "写出 user:// 临时文件")
	var reloaded := (load(roundtrip_path) as PackedScene).instantiate()
	var text2 := LevelFileIO.serialize_level(reloaded)
	_check(text == text2, "往返序列化逐字节一致")
	reloaded.free()

	# 3. 改动 + 新增连接再往返
	var trigger := level06.get_node("Blocks/TriggerSwitch")
	var moving := level06.get_node("Blocks/MovingBase")
	trigger.active_changed.connect(moving.set_enabled)
	var source := level06.get_node("Blocks/Source") as Node2D
	source.position = Vector2(150, 420)
	var text3 := LevelFileIO.serialize_level(level06)
	_check(text3.contains(
			"[connection signal=\"active_changed\" from=\"Blocks/TriggerSwitch\" to=\"Blocks/MovingBase\" method=\"set_enabled\"]"),
			"新增连接被序列化")
	_check(text3.contains("position = Vector2(150, 420)"), "改动后的位置被序列化")
	LevelFileIO.write_text(roundtrip_path, text3)
	var reloaded3 := (load(roundtrip_path) as PackedScene).instantiate()
	var trigger3 := reloaded3.get_node("Blocks/TriggerSwitch")
	_check(trigger3.get_signal_connection_list(&"active_changed").size() == 2,
			"重载后 active_changed 有 2 条连接")
	reloaded3.free()
	level06.free()

	# 4. level_01 的 next_level_scene
	var packed01 := load("res://scenes/levels/level_01.tscn") as PackedScene
	var level01 := packed01.instantiate()
	var text01 := LevelFileIO.serialize_level(level01)
	_check(text01.contains("[gd_scene load_steps=8 format=3]"), "level_01 头部 load_steps=8")
	_check(text01.contains("path=\"res://scenes/levels/level_02_折射入门.tscn\" id=\"7_next\""),
			"下一关 PackedScene 进入 ext 表")
	_check(text01.contains("next_level_scene = ExtResource(\"7_next\")"), "next_level_scene 覆盖行")
	level01.free()

	# 5. 文件名与解析
	_check(LevelFileIO.suggest_file_name() == "level_07_说明.tscn", "建议文件名 level_07")
	_check(LevelFileIO.validate_file_name("level_07_说明.tscn"), "校验合法文件名")
	_check(LevelFileIO.validate_file_name("level_08.tscn"), "校验纯编号文件名")
	_check(not LevelFileIO.validate_file_name("level_base.tscn"), "拒绝基座文件名")
	_check(not LevelFileIO.validate_file_name("foo.tscn"), "拒绝非关卡文件名")
	_check(LevelFileIO.get_base_scene_path_from_file("res://scenes/levels/level_06_机关秀.tscn")
			== LevelFileIO.BASE_SCENE_DEFAULT, "解析基座场景路径")
	_check(LevelFileIO.read_root_name("res://scenes/levels/level_06_机关秀.tscn") == "Level06",
			"解析根节点名")
	_check(LevelFileIO.is_valid_wire(&"active_changed", &"set_enabled"), "电线兼容表允许 active_changed→set_enabled")
	_check(not LevelFileIO.is_valid_wire(&"active_changed", &"reset_state"), "电线兼容表拒绝 reset_state")

	# 6. capture/restore 抵消 moving_base._ready 位移
	var base := (load(LevelFileIO.BASE_SCENE_DEFAULT) as PackedScene).instantiate()
	var mb := (load("res://blocks/moving_base/moving_base.tscn") as PackedScene).instantiate() as Node2D
	mb.name = "MovingBase"
	mb.position = Vector2(500, 300)
	mb.path_a = Vector2(0, 200)
	base.get_node("Blocks").add_child(mb)
	var captured := LevelFileIO.capture_props(base)
	add_child(base)
	await get_tree().process_frame
	await get_tree().process_frame
	var shifted: bool = mb.position != Vector2(500, 300)
	LevelFileIO.restore_props(base, captured)
	_check(shifted and mb.position == Vector2(500, 300), "capture/restore 抵消 _ready 位移")
	base.queue_free()
	await get_tree().process_frame

	if _failures.is_empty():
		print("TEST RESULT: PASS")
		get_tree().quit(0)
	else:
		print("TEST RESULT: FAIL（%d 项）" % _failures.size())
		get_tree().quit(1)
