extends Node2D

## 实体机关组测试（开关 → 电线 → 机关 三元模型）：
## 触发开关 / 可动作镜面 / 石块 / 压力传感器 / 电线（ActionLink）。
## 运行方式（tests/entity_mechanism_test.tscn）：
##   godot --headless --path . res://tests/entity_mechanism_test.tscn
## 按阶段顺序验证，全部通过退出码 0。

const TriggerScene := preload("res://blocks/trigger_switch/trigger_switch.tscn")
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

	# —— 阶段 2：镜面 + 电线（触发开关 → 镜面：位移/旋转/恢复）——
	var actuator := MirrorScene.instantiate() as Node2D
	actuator.position = Vector2(300, 300)
	add_child(actuator)
	var actuator_origin := actuator.position
	var actuator_link := _make_link(actuator, Vector2(0, -60), 0.4, false, true)
	trigger.active_changed.connect(Callable(actuator_link, &"_on_signal"))
	_move_source(Vector2(100, 100), 0.0)
	await _settle(40)
	_check("阶段2 镜面：开关 ON 后电线把镜面移到动作位",
			actuator.position.distance_to(actuator_origin + Vector2(0, -60)) < 1.0)
	_move_source(Vector2(100, 50), 0.0)
	await _settle(40)
	_check("阶段2 镜面：光线离开后机关保持动作位",
			actuator.position.distance_to(actuator_origin + Vector2(0, -60)) < 1.0)
	actuator_link.restore_on_off = false
	_move_source(Vector2(100, 100), 0.0)
	await _settle(40)
	_move_source(Vector2(100, 50), 0.0)
	await _settle(30)
	_check("阶段2 镜面：不恢复时断电后停在动作位",
			actuator.position.distance_to(actuator_origin + Vector2(0, -60)) < 1.0)
	actuator_link.reset_state()
	await _settle(2)
	_check("阶段2 镜面：重置后回原位（开关 OFF）",
			actuator.position.distance_to(actuator_origin) < 0.01)
	actuator_link.restore_on_off = true

	# 电线也支持只旋转、不位移。
	actuator_link.move_offset = Vector2.ZERO
	actuator_link.rotate_degrees = 30.0
	_move_source(Vector2(100, 100), 0.0)
	await _settle(40)
	_check("阶段2 镜面：只旋转动作生效",
			absf(angle_difference(actuator.rotation, deg_to_rad(30.0))) < 0.01)
	_move_source(Vector2(100, 50), 0.0)
	await _settle(40)
	_check("阶段2 镜面：光线离开后保持旋转", absf(
		angle_difference(actuator.rotation, deg_to_rad(30.0))) < 0.01)
	actuator_link.move_offset = Vector2(0, -60)
	actuator_link.rotate_degrees = 0.0

	# —— 阶段 3：电线直接驱动镜面循环（循环往返 + 重置重放）——
	var mirror := MirrorScene.instantiate() as Node2D
	mirror.position = Vector2(300, 500)
	mirror.rotation = deg_to_rad(45.0)
	add_child(mirror)
	var mirror_link := _make_link(mirror, Vector2(0, 200), 0.4, true, true)
	trigger.active_changed.connect(Callable(mirror_link, &"_on_signal"))
	var recv_below := _make_receiver(Vector2(300, 650))
	_move_source(Vector2(100, 500), 0.0)
	await _settle(30)
	_check("阶段3 镜面：停住时反射点亮下方接收区", recv_below.is_lit())
	_move_source(Vector2(100, 100), 0.0)
	await _settle(30)
	_check("阶段3 镜面：开关 ON 后循环运动（离原位）", mirror.position.distance_to(Vector2(300, 500)) > 1.0)
	mirror_link.reset_state()
	_check("阶段3 镜面：重置瞬间回到原位", mirror.position.distance_to(Vector2(300, 500)) < 0.01)
	await _settle(2)
	_check("阶段3 镜面：重置后不因旧开关状态自动重启",
			mirror.position.distance_to(Vector2(300, 500)) < 0.01)
	_move_source(Vector2(100, 500), 0.0)
	await _settle(5)
	_move_source(Vector2(100, 100), 0.0)
	await _settle(30)
	_check("阶段3 镜面：新的触发再次启动往返",
			mirror.position.distance_to(Vector2(300, 500)) > 1.0)
	_move_source(Vector2(100, 500), 0.0)
	await _settle(40)
	_check("阶段3 镜面：光线离开后持续往返", mirror_link.is_active())
	mirror_link.reset_state()
	await _settle(2)
	_check("阶段3 镜面：重置后回原位", mirror.position.distance_to(Vector2(300, 500)) < 1.0)
	_check("阶段3 镜面：恢复后重新点亮接收区", recv_below.is_lit())

	# —— 阶段 4：石块重力、落地碰撞与重置 ——
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(850, 320)
	floor_body.collision_layer = RayCaster.LAYER_OPAQUE
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(180, 32)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	var falling_block := StoneBlockScene.instantiate() as StoneBlock
	falling_block.position = Vector2(850, 100)
	add_child(falling_block)
	_check("阶段4 石块：默认不能用鼠标拖动", not falling_block.player_draggable)
	await _settle(80)
	_check("阶段4 石块：受重力下落并停在地面",
			falling_block.is_on_floor() and absf(falling_block.position.y - 272.0) < 1.0)
	falling_block.reset_state()
	_check("阶段4 石块：重置位置并清零速度",
			falling_block.position == Vector2(850, 100) and falling_block.velocity == Vector2.ZERO)
	falling_block.free()
	floor_body.free()

	# —— 阶段 5：石块 + 压力传感器 + 电线 + 镜面联动 ——
	var sensor_target := MirrorScene.instantiate() as Node2D
	sensor_target.position = Vector2(600, 300)
	add_child(sensor_target)
	var sensor_target_origin := sensor_target.position
	var sensor_link := _make_link(sensor_target, Vector2(0, -60), 0.4, false, true)
	var sensor := SensorScene.instantiate() as PressureSensor
	sensor.position = Vector2(300, 760)
	add_child(sensor)
	sensor.pressed_changed.connect(Callable(sensor_link, &"_on_signal"))
	var block := StoneBlockScene.instantiate() as StoneBlock
	block.gravity_enabled = false  # 本阶段专测机关联动，避免重力改变既有测试坐标
	block.position = Vector2(300, 760)
	add_child(block)
	var recv_behind := _make_receiver(Vector2(500, 700))
	_move_source(Vector2(100, 700), 0.0)
	await _settle(40)
	_check("阶段5 联动：石块压在传感器上", sensor.is_pressed())
	_check("阶段5 联动：传感器经电线移动镜面",
			sensor_target.position.distance_to(sensor_target_origin + Vector2(0, -60)) < 1.0)
	_check("阶段5 联动：光线畅通照到接收区", recv_behind.is_lit())
	block.position = Vector2(300, 690)
	await _settle(40)
	_check("阶段5 联动：石块移开后传感器松开", not sensor.is_pressed())
	_check("阶段5 联动：镜面随之恢复原位",
			sensor_target.position.distance_to(sensor_target_origin) < 1.0)
	_check("阶段5 联动：石块挡住光线接收区熄灭", not recv_behind.is_lit())
	block.reset_state()
	await _settle(40)
	_check("阶段5 联动：石块重置回原位重新压住传感器", sensor.is_pressed())
	_check("阶段5 联动：镜面重新到动作位",
			sensor_target.position.distance_to(sensor_target_origin + Vector2(0, -60)) < 1.0)
	_check("阶段5 联动：光线重新畅通", recv_behind.is_lit())

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
