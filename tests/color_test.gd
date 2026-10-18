extends Node

## 端到端测试：颜色链路——光源颜色 → 变色片改色 → 接收区按颜色判定。
## 覆盖：trace_multi 颜色传播、ReceiverHit.color、received_colors / matches_color、
## ColorChanger 变色、ColorSensor 滤色开关（match / 任意色两种模式）。
## 跑法：tools\dev.bat 40

class Probe extends LightReceiver:
	pass


var _failed := 0


func _ready() -> void:
	var system := LightSystem.new()
	add_child(system)

	# 白光源，朝 +X
	var source := LightSource.new()
	source.position = Vector2(0, 0)
	source.rotation = 0.0
	source.light_color = Color(1, 1, 1)
	add_child(source)

	# 变色片：白光 → 红光（x=80 处的竖薄片，光从中间穿过）
	var changer := ColorChanger.new()
	changer.position = Vector2(80, 0)
	changer.recolor = Color(1, 0, 0, 1)
	_add_box(changer, Vector2(8, 120))
	add_child(changer)

	# 变色片前：白光探针
	var white_probe := _make_probe(Vector2(40, 0))
	add_child(white_probe)

	# 变色片后：红感应器（应匹配）/ 蓝感应器（不该匹配）/ 关滤色感应器（应匹配）
	var red_sensor := ColorSensor.new()
	red_sensor.position = Vector2(150, 0)
	_add_box(red_sensor, Vector2(30, 30))
	add_child(red_sensor)

	var blue_sensor := ColorSensor.new()
	blue_sensor.position = Vector2(200, 0)
	blue_sensor.match_color = Color(0, 0, 1)
	_add_box(blue_sensor, Vector2(30, 30))
	add_child(blue_sensor)

	var any_sensor := ColorSensor.new()
	any_sensor.position = Vector2(250, 0)
	any_sensor.match_color = Color(0, 0, 1)
	any_sensor.color_filter = false
	_add_box(any_sensor, Vector2(30, 30))
	add_child(any_sensor)

	for _i in 5:
		await get_tree().physics_frame

	_check("白光探针收到白色", white_probe.matches_color(Color(1, 1, 1)))
	_check("白光探针没收到红色", not white_probe.matches_color(Color(1, 0, 0)))
	_check("变色片后的感应器被照亮", red_sensor.is_lit())
	_check("红色感应器匹配红光", red_sensor.is_matched())
	_check("蓝色感应器被照亮但颜色不符（不匹配）", blue_sensor.is_lit() and not blue_sensor.is_matched())
	_check("蓝色感应器收不到蓝光", not blue_sensor.matches_color(Color(0, 0, 1)))
	_check("关闭滤色的感应器匹配任意颜色", any_sensor.is_matched())
	_check("红色感应器收到的颜色是红色", red_sensor.matches_color(Color(1, 0, 0)))

	print("")
	if _failed == 0:
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)


func _make_probe(pos: Vector2) -> Probe:
	var probe := Probe.new()
	probe.position = pos
	_add_box(probe, Vector2(30, 30))
	return probe


func _add_box(node: CollisionObject2D, size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	node.add_child(shape)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
