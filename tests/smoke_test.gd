extends Node

## 冒烟测试驱动：无头验证 level_01 的完整通关链路。
## 运行方式（tests/smoke_test.tscn 继承自 level_01，挂在 TestDriver 节点上）：
##   godot --headless --path . res://tests/smoke_test.tscn
## 流程：初始直射被墙挡住 → 光源转到 -45° → 光线经镜面反射 → 蚕茧点亮。
## 组员做完新机关/新关卡后，可以照这个模板写自己的测试。

var _level_completed := false


func _ready() -> void:
	(owner.get_node("LevelManager") as LevelManager).completed.connect(_on_level_completed)
	_run_test()


func _run_test() -> void:
	await get_tree().physics_frame
	var source: LightSource
	var cocoon: Cocoon
	for node in get_tree().get_nodes_in_group("light_sources"):
		source = node as LightSource
	for node in get_tree().get_nodes_in_group("cocoons"):
		cocoon = node as Cocoon
	if source == null or cocoon == null:
		print("TEST RESULT: FAIL（找不到光源或蚕茧）")
		get_tree().quit(1)
		return
	source.follow_mouse = false
	var manager := get_parent().get_node("LevelManager") as LevelManager
	manager.publication_state = LevelManager.PublicationState.DRAFT
	var light_system := get_parent().get_node("LightSystem") as LightSystem

	print("TEST: 光源初始角度 = %.1f°（期望 0°）" % rad_to_deg(source.rotation))
	var angle_label_ok := source.get_angle_label_text() == "0°"
	print("TEST: 第一阶段——初始直射被墙挡住")
	for _frame in 30:
		await get_tree().physics_frame
	print("TEST: 蚕茧此时是否点亮（期望 false）: %s" % cocoon.is_lit())

	print("TEST: 第二阶段——光源转到 -45°，经镜面反射")
	source.rotation = deg_to_rad(-45.0)
	angle_label_ok = angle_label_ok and source.get_angle_label_text() == "315°"
	var fire_key := InputEventKey.new()
	fire_key.keycode = KEY_SPACE
	fire_key.pressed = true
	var completed_pulses: Array[int] = []
	light_system.pulse_finished.connect(func() -> void: completed_pulses.append(1))
	Input.parse_input_event(fire_key)
	await get_tree().create_timer(0.7, true).timeout
	var hotkey_started := completed_pulses.size() == 1
	print("TEST: 蚕茧是否点亮（期望 true）: %s" % cocoon.is_lit())
	print("TEST: 关卡管理器是否收到胜利（期望 true）: %s" % _level_completed)
	print("TEST: 光源角度读数遵循正右 0°（期望 true）: %s" % angle_label_ok)
	print("TEST: 空格键启动发射（期望 true）: %s" % hotkey_started)

	if cocoon.is_lit() and _level_completed and angle_label_ok and hotkey_started:
		print("TEST RESULT: PASS")
		get_tree().quit(0)
	else:
		print("TEST RESULT: FAIL")
		get_tree().quit(1)


func _on_level_completed(_level_name: String) -> void:
	_level_completed = true
