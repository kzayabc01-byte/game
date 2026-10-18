extends Node2D

## 实体机关组测试（人C 的五个机关）：触发机关 / 石门机关 / 移动底座 / 石块 / 压力传感器。
## 运行方式（tests/entity_mechanism_test.tscn）：
##   godot --headless --path . res://tests/entity_mechanism_test.tscn
## 按阶段顺序验证，全部通过退出码 0。

const TriggerScene := preload("res://blocks/trigger_switch/trigger_switch.tscn")
const StoneDoorScene := preload("res://blocks/stone_door/stone_door.tscn")
const MovingBaseScene := preload("res://blocks/moving_base/moving_base.tscn")
const MirrorScene := preload("res://blocks/mirror/mirror.tscn")
const StoneBlockScene := preload("res://blocks/stone_block/stone_block.tscn")
const SensorScene := preload("res://blocks/pressure_sensor/pressure_sensor.tscn")

var _source: LightSource
var _failed := false


func _ready() -> void:
	var system := LightSystem.new()
	system.name = "LightSystem"
	add_child(system)
	_source = LightSource.new()
	add_child(_source)
	_run_test()


func _run_test() -> void:
	await get_tree().physics_frame

	# —— 阶段 1：触发机关（默认跟随光照，锁存模式照到一次就保持）——
	var trigger := TriggerScene.instantiate() as TriggerSwitch
	trigger.position = Vector2(300, 100)
	add_child(trigger)
	_move_source(Vector2(100, 100), 0.0)
	await _settle(30)
	_check("阶段1 触发机关：被光照到后激活", trigger.is_active())
	_move_source(Vector2(100, 50), 0.0)
	await _settle(30)
	_check("阶段1 触发机关：光离开后关闭（非锁存）", not trigger.is_active())
	trigger.latch = true
	_move_source(Vector2(100, 100), 0.0)
	await _settle(30)
	_move_source(Vector2(100, 50), 0.0)
	await _settle(30)
	_check("阶段1 触发机关：锁存模式下光离开仍激活", trigger.is_active())
	trigger.reset_state()
	_check("阶段1 触发机关：重置后锁存解除", not trigger.is_active())

	# —— 阶段 2：石门机关（光照开门 + 外部开关）——
	var door := StoneDoorScene.instantiate() as StoneDoor
	door.position = Vector2(300, 300)
	add_child(door)
	_move_source(Vector2(100, 300), 0.0)
	await _settle(90)
	_check("阶段2 石门：被光照到后打开", door.is_open())
	_move_source(Vector2(100, 260), 0.0)
	await _settle(90)
	_check("阶段2 石门：光离开后关闭", not door.is_open())
	door.set_external_open(true)
	await _settle(90)
	_check("阶段2 石门：外部开关可强制开门", door.is_open())
	door.set_external_open(false)
	await _settle(90)
	_check("阶段2 石门：外部开关关闭后复原", not door.is_open())

	# —— 阶段 3：移动底座（运载镜子，禁用/启用/重置）——
	var base := MovingBaseScene.instantiate() as MovingBase
	base.position = Vector2(300, 500)
	base.path_b = Vector2(0, -150)
	base.speed = 150.0
	base.start_enabled = false
	add_child(base)
	var mirror := MirrorScene.instantiate() as Node2D
	mirror.rotation = deg_to_rad(45.0)
	base.add_child(mirror)
	var recv_below := _make_receiver(Vector2(300, 650))
	_move_source(Vector2(100, 500), 0.0)
	await _settle(30)
	_check("阶段3 底座：停住时镜面反射点亮下方接收区", recv_below.is_lit())
	base.set_enabled(true)
	await _settle(90)
	_check("阶段3 底座：启用后镜面移走接收区熄灭", not recv_below.is_lit())
	base.reset_state()
	await _settle(30)
	_check("阶段3 底座：重置后回到起点且恢复禁用", recv_below.is_lit())

	# —— 阶段 4：石块 + 压力传感器 + 石门联动 ——
	var door2 := StoneDoorScene.instantiate() as StoneDoor
	door2.position = Vector2(600, 300)
	add_child(door2)
	var sensor := SensorScene.instantiate() as PressureSensor
	sensor.position = Vector2(300, 760)
	add_child(sensor)
	sensor.pressed_changed.connect(door2.set_external_open)
	var block := StoneBlockScene.instantiate() as StoneBlock
	block.position = Vector2(300, 760)
	add_child(block)
	var recv_behind := _make_receiver(Vector2(500, 700))
	_move_source(Vector2(100, 700), 0.0)
	await _settle(60)
	_check("阶段4 联动：石块压在传感器上", sensor.is_pressed())
	_check("阶段4 联动：传感器信号打开石门", door2.is_open())
	_check("阶段4 联动：光线畅通照到接收区", recv_behind.is_lit())
	block.position = Vector2(300, 690)
	await _settle(60)
	_check("阶段4 联动：石块移开后传感器松开", not sensor.is_pressed())
	_check("阶段4 联动：石门随之关闭", not door2.is_open())
	_check("阶段4 联动：石块挡住光线接收区熄灭", not recv_behind.is_lit())
	block.reset_state()
	await _settle(60)
	_check("阶段4 联动：石块重置回原位重新压住传感器", sensor.is_pressed())
	_check("阶段4 联动：石门重新打开", door2.is_open())
	_check("阶段4 联动：光线重新畅通", recv_behind.is_lit())

	if _failed:
		print("TEST RESULT: FAIL")
		get_tree().quit(1)
	else:
		print("TEST RESULT: PASS")
		get_tree().quit(0)


func _move_source(pos: Vector2, rotation_rad: float) -> void:
	_source.position = pos
	_source.rotation = rotation_rad


func _settle(frames: int) -> void:
	for _frame in frames:
		await get_tree().physics_frame


func _check(label: String, passed: bool) -> void:
	print("TEST: %s : %s" % [label, "PASS" if passed else "FAIL"])
	if not passed:
		_failed = true


func _make_receiver(pos: Vector2) -> LightReceiver:
	var recv := LightReceiver.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 40)
	shape.shape = rect
	recv.add_child(shape)
	recv.position = pos
	add_child(recv)
	return recv
