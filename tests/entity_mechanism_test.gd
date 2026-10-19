extends Node2D

## 实体机关组测试（开关 → 电线 → 机关 三元模型）：
## 触发开关 / 石门 / 移动底座 / 石块 / 压力传感器 / 电线（ActionLink）。
## 运行方式（tests/entity_mechanism_test.tscn）：
##   godot --headless --path . res://tests/entity_mechanism_test.tscn
## 按阶段顺序验证，全部通过退出码 0。

const TriggerScene := preload("res://blocks/trigger_switch/trigger_switch.tscn")
const StoneDoorScene := preload("res://blocks/stone_door/stone_door.tscn")
const MovingBaseScene := preload("res://blocks/moving_base/moving_base.tscn")
const MirrorScene := preload("res://blocks/mirror/mirror.tscn")
const StoneBlockScene := preload("res://blocks/stone_block/stone_block.tscn")
const SensorScene := preload("res://blocks/pressure_sensor/pressure_sensor.tscn")
const LinkScene := preload("res://blocks/action_link/action_link.tscn")

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

	# —— 阶段 1：触发开关（默认跟随光照，锁存模式照到一次就保持）——
	var trigger := TriggerScene.instantiate() as TriggerSwitch
	trigger.position = Vector2(300, 100)
	add_child(trigger)
	_move_source(Vector2(100, 100), 0.0)
	await _settle(30)
	_check("阶段1 触发开关：被光照到后激活", trigger.is_active())
	_move_source(Vector2(100, 50), 0.0)
	await _settle(30)
	_check("阶段1 触发开关：光离开后关闭（非锁存）", not trigger.is_active())
	trigger.latch = true
	_move_source(Vector2(100, 100), 0.0)
	await _settle(30)
	_move_source(Vector2(100, 50), 0.0)
	await _settle(30)
	_check("阶段1 触发开关：锁存模式下光离开仍激活", trigger.is_active())
	trigger.reset_state()
	_check("阶段1 触发开关：重置后锁存解除", not trigger.is_active())
	trigger.latch = false  # 后续阶段用非锁存开关驱动电线

	# —— 阶段 2：石门 + 电线（触发开关 → 石门：移 (0,-60)，断电恢复/不恢复）——
	var door := StoneDoorScene.instantiate() as StoneDoor
	door.position = Vector2(300, 300)
	add_child(door)
	var door_link := _make_link(door, Vector2(0, -60), 0.4, false, true)
	trigger.active_changed.connect(Callable(door_link, &"_on_signal"))
	_move_source(Vector2(100, 100), 0.0)
	await _settle(40)
	_check("阶段2 石门：开关 ON 后电线把门移到动作位", door.is_open())
	_move_source(Vector2(100, 50), 0.0)
	await _settle(40)
	_check("阶段2 石门：开关 OFF 后门恢复原状", not door.is_open())
	door_link.restore_on_off = false
	_move_source(Vector2(100, 100), 0.0)
	await _settle(40)
	_move_source(Vector2(100, 50), 0.0)
	await _settle(30)
	_check("阶段2 石门：不恢复时断电后停在动作位", door.is_open())
	door_link.reset_state()
	await _settle(2)
	_check("阶段2 石门：重置后回原位（开关 OFF）", not door.is_open())
	door_link.restore_on_off = true

	# —— 阶段 3：移动底座 + 电线循环（镜面随底座一起动，循环往返 + 重置重放）——
	var base := MovingBaseScene.instantiate() as MovingBase
	base.position = Vector2(300, 500)
	add_child(base)
	var mirror := MirrorScene.instantiate() as Node2D
	mirror.rotation = deg_to_rad(45.0)
	base.add_child(mirror)
	var base_link := _make_link(base, Vector2(0, 200), 0.4, true, true)
	trigger.active_changed.connect(Callable(base_link, &"_on_signal"))
	var recv_below := _make_receiver(Vector2(300, 650))
	_move_source(Vector2(100, 500), 0.0)
	await _settle(30)
	_check("阶段3 底座：停住时镜面反射点亮下方接收区", recv_below.is_lit())
	_move_source(Vector2(100, 100), 0.0)
	await _settle(30)
	_check("阶段3 底座：开关 ON 后循环运动（离原位）", base.position.distance_to(Vector2(300, 500)) > 1.0)
	base_link.reset_state()
	_check("阶段3 底座：重置瞬间回到原位", base.position.distance_to(Vector2(300, 500)) < 0.01)
	await _settle(2)
	_check("阶段3 底座：开关仍 ON，复查后重新动起来", base.position.distance_to(Vector2(300, 500)) > 1.0)
	_move_source(Vector2(100, 500), 0.0)
	await _settle(40)
	_check("阶段3 底座：开关 OFF 后恢复原位", base.position.distance_to(Vector2(300, 500)) < 1.0)
	_check("阶段3 底座：恢复后镜面重新点亮接收区", recv_below.is_lit())

	# —— 阶段 4：石块 + 压力传感器 + 电线 + 石门联动 ——
	var door2 := StoneDoorScene.instantiate() as StoneDoor
	door2.position = Vector2(600, 300)
	add_child(door2)
	var door2_link := _make_link(door2, Vector2(0, -60), 0.4, false, true)
	var sensor := SensorScene.instantiate() as PressureSensor
	sensor.position = Vector2(300, 760)
	add_child(sensor)
	sensor.pressed_changed.connect(Callable(door2_link, &"_on_signal"))
	var block := StoneBlockScene.instantiate() as StoneBlock
	block.position = Vector2(300, 760)
	add_child(block)
	var recv_behind := _make_receiver(Vector2(500, 700))
	_move_source(Vector2(100, 700), 0.0)
	await _settle(40)
	_check("阶段4 联动：石块压在传感器上", sensor.is_pressed())
	_check("阶段4 联动：传感器经电线打开石门", door2.is_open())
	_check("阶段4 联动：光线畅通照到接收区", recv_behind.is_lit())
	block.position = Vector2(300, 690)
	await _settle(40)
	_check("阶段4 联动：石块移开后传感器松开", not sensor.is_pressed())
	_check("阶段4 联动：石门随之恢复关闭", not door2.is_open())
	_check("阶段4 联动：石块挡住光线接收区熄灭", not recv_behind.is_lit())
	block.reset_state()
	await _settle(40)
	_check("阶段4 联动：石块重置回原位重新压住传感器", sensor.is_pressed())
	_check("阶段4 联动：石门重新打开", door2.is_open())
	_check("阶段4 联动：光线重新畅通", recv_behind.is_lit())

	if _failed:
		print("TEST RESULT: FAIL")
		get_tree().quit(1)
	else:
		print("TEST RESULT: PASS")
		get_tree().quit(0)


## 造一条电线：target_node 指向目标机关，返回已进树并解析好目标的电线节点
func _make_link(
	target: Node2D, offset: Vector2, duration: float, repeat: bool, restore: bool,
) -> ActionLink:
	var link := LinkScene.instantiate() as ActionLink
	add_child(link)
	link.target_node = link.get_path_to(target)
	link.move_offset = offset
	link.duration = duration
	link.repeat = repeat
	link.restore_on_off = restore
	link.resolve_target()
	return link


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
