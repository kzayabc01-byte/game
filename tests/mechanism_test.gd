extends Node2D

## 核心扩展机制测试：折射 / 分光 / 传送门 / 变色+颜色感应，按阶段顺序验证。
## 运行方式（tests/mechanism_test.tscn）：
##   godot --headless --path . res://tests/mechanism_test.tscn
## 组员写完新机关后，可照这个模板给自己负责的机关写测试。

const RED := Color(1.0, 0.2, 0.2)
const GREEN := Color(0.2, 1.0, 0.3)

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

	# —— 阶段 1：折射介质（光线穿过偏转 90°，向右的光变成向下）——
	var plate := _make_refract(Vector2(300, 300), Vector2(20, 200), 90.0)
	var recv_down := _make_receiver(Vector2(300, 450))
	var recv_straight := _make_receiver(Vector2(500, 300))
	_move_source(Vector2(100, 300), 0.0)
	await _settle()
	_check("阶段1 折射：偏转方向接收区点亮", recv_down.is_lit())
	_check("阶段1 折射：原直线方向接收区不亮", not recv_straight.is_lit())

	# —— 阶段 2：凹透镜分光（一束光分成 ±30° 两束）——
	var lens := _make_refract(Vector2(300, 100), Vector2(20, 80), 30.0, true)
	var recv_upper := _make_receiver(Vector2(438.6, 20))
	var recv_lower := _make_receiver(Vector2(438.6, 180))
	_move_source(Vector2(100, 100), 0.0)
	await _settle()
	_check("阶段2 分光：上支路接收区点亮", recv_upper.is_lit())
	_check("阶段2 分光：下支路接收区点亮", recv_lower.is_lit())
	_check("阶段2 分光：光源移走后阶段1接收区熄灭", not recv_down.is_lit())

	# —— 阶段 3：传送门（A 进 B 出，方向不变，双向互指）——
	var portal_a := _make_portal(Vector2(500, 500), null)
	var portal_b := _make_portal(Vector2(500, 50), portal_a)
	portal_a.linked_portal = portal_b
	var recv_portal := _make_receiver(Vector2(650, 50))
	_move_source(Vector2(100, 500), 0.0)
	await _settle()
	_check("阶段3 传送门：出口方向接收区点亮", recv_portal.is_lit())
	_check("阶段3 传送门：分光接收区已熄灭", not recv_upper.is_lit())

	# —— 阶段 4：变色机关 + 颜色感应机关（白光穿过滤色片变红）——
	var filter := _make_refract(Vector2(300, 700), Vector2(20, 60), 0.0)
	filter.recolor = true
	filter.output_color = RED
	var recv_any := _make_receiver(Vector2(450, 700))
	var recv_red := _make_receiver(Vector2(500, 700), RED, true)
	var recv_green := _make_receiver(Vector2(550, 700), GREEN, true)
	_source.light_color = Color.WHITE
	_move_source(Vector2(100, 700), 0.0)
	await _settle()
	_check("阶段4 颜色：不挑色的接收区点亮", recv_any.is_lit())
	_check("阶段4 颜色：红色感应接收区点亮", recv_red.is_lit())
	_check("阶段4 颜色：绿色感应接收区不亮", not recv_green.is_lit())
	_check("阶段4 颜色：机关读到命中颜色为红", recv_red.get_light_color().is_equal_approx(RED))

	if _failed:
		print("TEST RESULT: FAIL")
		get_tree().quit(1)
	else:
		print("TEST RESULT: PASS")
		get_tree().quit(0)


func _move_source(pos: Vector2, rotation_rad: float) -> void:
	_source.position = pos
	_source.rotation = rotation_rad


func _settle() -> void:
	for _frame in 30:
		await get_tree().physics_frame


func _check(label: String, passed: bool) -> void:
	print("TEST: %s : %s" % [label, "PASS" if passed else "FAIL"])
	if not passed:
		_failed = true


func _make_refract(pos: Vector2, size: Vector2, bend: float, split: bool = false) -> RefractSurface:
	var body := RefractSurface.new()
	body.bend_degrees = bend
	body.split = split
	body.add_child(_make_shape(size))
	body.position = pos
	add_child(body)
	return body


func _make_portal(pos: Vector2, linked: Portal) -> Portal:
	var body := Portal.new()
	body.linked_portal = linked
	body.add_child(_make_shape(Vector2(20, 60)))
	body.position = pos
	add_child(body)
	return body


func _make_receiver(pos: Vector2, filter: Color = Color.WHITE, match: bool = false) -> LightReceiver:
	var recv := LightReceiver.new()
	recv.color_filter = filter
	recv.match_color = match
	recv.add_child(_make_shape(Vector2(40, 40)))
	recv.position = pos
	add_child(recv)
	return recv


func _make_shape(size: Vector2) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	return shape
