extends Node

## level_02 全流程通关测试（联动展示关，验证手写场景连线的正确性）：
## 石块压传感器 → 底座启动 → 光源 -25° 照触发机关（锁存）→ 石门打开
## → 光线转回 0°，等镜面扫过蚕茧 → 胜利。
## 运行方式（tests/level_02_test.tscn 继承自 level_02）：
##   godot --headless --path . res://tests/level_02_test.tscn

var _level_completed := false
var _failed := false


func _ready() -> void:
	GameEvents.level_completed.connect(_on_level_completed)
	_run_test()


func _run_test() -> void:
	await get_tree().physics_frame
	var source: LightSource
	var cocoon: Cocoon
	var base: MovingBase
	var block: StoneBlock
	var sensor: PressureSensor
	var door: StoneDoor
	var trigger: TriggerSwitch
	for node in get_tree().get_nodes_in_group("light_sources"):
		source = node as LightSource
	for node in get_tree().get_nodes_in_group("cocoons"):
		cocoon = node as Cocoon
	for node in get_tree().get_nodes_in_group("resettables"):
		if node is MovingBase:
			base = node
		elif node is StoneBlock:
			block = node
		elif node is PressureSensor:
			sensor = node
		elif node is StoneDoor:
			door = node
		elif node is TriggerSwitch:
			trigger = node
	if source == null or cocoon == null or base == null or block == null or sensor == null or door == null or trigger == null:
		_check("关卡节点齐全", false)
		_finish()
		return
	_check("关卡节点齐全", true)

	# 第一步：石块拖到压力传感器上 → 移动底座启动
	block.position = sensor.position
	await _settle(30)
	_check("第一步：传感器被压住", sensor.is_pressed())
	var start_pos := base.position
	await _settle(30)
	_check("第一步：底座开始移动", base.position.distance_to(start_pos) > 1.0)

	# 第二步：光源 -25° 照触发机关（锁存）→ 石门打开
	source.rotation = deg_to_rad(-25.0)
	await _settle(90)
	_check("第二步：触发机关激活", trigger.is_active())
	_check("第二步：石门打开", door.is_open())

	# 第三步：转回 0°，等镜面扫过蚕茧 → 胜利
	source.rotation = 0.0
	var won := false
	for _frame in 450:
		await get_tree().physics_frame
		if cocoon.is_lit():
			won = true
			break
	_check("第三步：蚕茧点亮", won)
	_check("第三步：收到关卡完成信号", _level_completed)
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
