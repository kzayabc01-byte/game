extends Node

## 传送门“看得见”的验证：
##  1. 传送处必须断开折线，不能把入口 A 和出口 B 连成一条直线（这就是截图里的假光线）；
##  2. 整块门面都能传送：打在门面上方 40px（仍在门长范围内）也要从 B 的对应位置出来；
##  3. 打偏到门面之外就正常穿过去（不该被门旁边的空气传送）。
## 跑法：tools\dev.bat 40

var _failed := 0
var _a: Portal
var _b: Portal
var _receiver: Area2D


func _ready() -> void:
	await get_tree().physics_frame

	_a = _make_portal(Vector2(300, 300), 0.0)
	_b = _make_portal(Vector2(500, 300), PI)
	_a.linked_portal = _b
	_b.linked_portal = _a

	_receiver = _make_receiver(Vector2(620, 260))

	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_viewport().find_world_2d().direct_space_state

	# —— 命中门面中部 ——
	var traces := RayCaster.trace_all(space, Vector2(100, 300), Vector2.RIGHT)
	_check("中部命中：至少分成 2 段折线", traces.size() >= 2, "实际 %d 条" % traces.size())
	_check("中部命中：没有“A→B”的长直线桥接", not _has_bridge(traces, Vector2(300, 300), Vector2(500, 300)))
	_check("中部命中：有一条折线从 B 出发（x≈500）", _starts_near(traces, Vector2(500, 300), 4.0))

	# —— 命中门面偏上 40px（仍在门长 96 内）——
	var offset_traces := RayCaster.trace_all(space, Vector2(100, 340), Vector2.RIGHT)
	_check("偏上命中：仍然传送", _starts_near(offset_traces, Vector2(500, 260), 6.0),
			_str_points(offset_traces))
	_check("偏上命中：出射后继续向右飞过 x=600", _has_point_beyond_x(offset_traces, 600.0),
			_str_points(offset_traces))
	_check("偏上命中：接收区被点亮", _receiver_hit(offset_traces))

	# —— 打偏到门面之外（y=380，超出 96/2 + 厚度）——
	var miss_traces := RayCaster.trace_all(space, Vector2(100, 380), Vector2.RIGHT)
	_check("门面之外：不传送", not _starts_near(miss_traces, Vector2(500, 300), 10.0),
			_str_points(miss_traces))

	print("")
	if _failed == 0:
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)


func _make_portal(pos: Vector2, rotation_rad: float) -> Portal:
	var portal := Portal.new()
	portal.position = pos
	portal.rotation = rotation_rad
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 96)
	shape.shape = rect
	portal.add_child(shape)
	add_child(portal)
	return portal


func _make_receiver(pos: Vector2) -> Area2D:
	var area := Area2D.new()
	area.position = pos
	area.collision_layer = RayCaster.LAYER_RECEIVER
	area.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30, 30)
	shape.shape = rect
	area.add_child(shape)
	add_child(area)
	return area


## 是否出现“从 A 直连 B”的一段（相邻两点分别靠近 A 和 B）
func _has_bridge(traces: Array, a: Vector2, b: Vector2) -> bool:
	for trace in traces:
		var points: PackedVector2Array = trace.segments
		for i in range(points.size() - 1):
			if points[i].distance_to(a) < 6.0 and points[i + 1].distance_to(b) < 6.0:
				return true
	return false


func _starts_near(traces: Array, point: Vector2, tolerance: float) -> bool:
	for trace in traces:
		if trace.segments.size() > 0 and trace.segments[0].distance_to(point) < tolerance:
			return true
	return false


func _any_point_near(traces: Array, point: Vector2, tolerance: float) -> bool:
	for trace in traces:
		for p in trace.segments:
			if p.distance_to(point) < tolerance:
				return true
	return false


func _has_point_beyond_x(traces: Array, x: float) -> bool:
	for trace in traces:
		for p in trace.segments:
			if p.x > x:
				return true
	return false


func _receiver_hit(traces: Array) -> bool:
	for trace in traces:
		for hit in trace.receiver_hits:
			if hit.receiver == _receiver:
				return true
	return false


func _str_points(traces: Array) -> String:
	var out := ""
	for trace in traces:
		out += str(trace.segments) + " "
	return out


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s   %s" % [label, detail])
