extends Node

## level_02 全流程通关测试（联动展示关，验证手写场景连线的正确性）：
## 石块压传感器 → 电线直接驱动镜面 → 镜面扫过水平光束 → 蚕茧点亮。
## 运行方式（tests/level_02_test.tscn 继承自 level_02）：
##   godot --headless --path . res://tests/level_02_test.tscn

var _level_completed := false
var _failed := false


func _ready() -> void:
	(owner.get_node("LevelManager") as LevelManager).completed.connect(_on_level_completed)
	_run_test()


func _run_test() -> void:
	await get_tree().physics_frame
	var source: LightSource
	var cocoon: Cocoon
	var mirror: Node2D
	var block: StoneBlock
	var sensor: PressureSensor
	for node in get_tree().get_nodes_in_group("light_sources"):
		source = node as LightSource
	for node in get_tree().get_nodes_in_group("cocoons"):
		cocoon = node as Cocoon
	for node in get_tree().get_nodes_in_group("resettables"):
		if node is StoneBlock:
			block = node
		elif node is PressureSensor:
			sensor = node
	mirror = get_tree().root.find_child("Mirror", true, false) as Node2D
	if source == null or cocoon == null or mirror == null or block == null or sensor == null:
		_check("关卡节点齐全", false)
		_finish()
		return
	_check("关卡节点齐全", true)
	source.follow_mouse = false
	var manager := get_parent().get_node("LevelManager") as LevelManager
	manager.publication_state = LevelManager.PublicationState.DRAFT
	var light := get_parent().get_node("LightSystem") as LightSystem

	# 第一步：石块拖到压力传感器上 → 镜面开始移动
	block.position = sensor.position
	await _settle(30)
	_check("第一步：传感器被压住", sensor.is_pressed())
	var start_pos := mirror.position
	await _settle(30)
	_check("第一步：镜面开始移动", mirror.position.distance_to(start_pos) > 1.0)

	# 第二步：等镜面经过水平光路时发射，光线结束后判定胜利。
	source.rotation = 0.0
	var won := false
	for _frame in 600:
		if absf(mirror.position.y - 400.0) < 7.0 and not light.is_pulse_active():
			light.request_fire()
		await get_tree().physics_frame
		if cocoon.is_lit():
			won = true
			break
	_check("第二步：蚕茧点亮", won)
	_check("第二步：收到关卡完成信号", _level_completed)
	_finish()


func _settle(frames: int) -> void:
	for _frame in frames:
		await get_tree().physics_frame


func _check(label: String, passed: bool) -> void:
	print("TEST: %s : %s" % [label, "PASS" if passed else "FAIL"])
	if not passed:
		_failed = true


func _finish() -> void:
	if _failed:
		print("TEST RESULT: FAIL")
		get_tree().quit(1)
	else:
		print("TEST RESULT: PASS")
		get_tree().quit(0)


func _on_level_completed(_level_name: String) -> void:
	_level_completed = true
