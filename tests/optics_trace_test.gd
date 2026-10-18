extends Node

## 集成测试：验证 RayCaster.trace_multi 会把光线交给「光路表面」（层 4），
## 并且折射后的光路仍能扫到接收区（层 3）。这是契约的端到端验收。
## 跑法：tools\dev.bat 40

var _failed := 0
var _receiver: Area2D
var _plate: RefractSurface


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_viewport().find_world_2d().direct_space_state

	# 1) 空场景：光直走，扫不到接收区（接收区还没建）
	var traces := RayCaster.trace_multi(space, Vector2(0, 0), Vector2.RIGHT, 32)
	_check("空场景只有 1 条折线", traces.size() == 1, "实际 %d 条" % traces.size())
	_check("空场景没有命中接收区", not _hits_receiver(traces))

	# 2) 建接收区（层 3）：放在「光直走」的路径上，先确认直射能命中
	_receiver = _make_receiver(Vector2(600, 0))
	add_child(_receiver)
	await get_tree().physics_frame
	await get_tree().physics_frame
	traces = RayCaster.trace_multi(space, Vector2(0, 0), Vector2.RIGHT, 32)
	_check("直射能命中接收区", _hits_receiver(traces))

	# 3) 中间插一片 -45° 折射片（层 4）→ 光线应被偏折，直射路径上的接收区打不到了
	_plate = _make_plate(Vector2(300, 0), -45.0)
	add_child(_plate)
	await get_tree().physics_frame
	await get_tree().physics_frame
	traces = RayCaster.trace_multi(space, Vector2(0, 0), Vector2.RIGHT, 32)
	_check("插入折射片后光路分成 2 条折线", traces.size() == 2, "实际 %d 条" % traces.size())
	_check("折射后打不到原来的接收区", not _hits_receiver(traces))

	var bent_trace = _find_bent_trace(traces)
	_check("找到向上偏折的折线", bent_trace != null)
	if bent_trace != null:
		var tip: Vector2 = bent_trace.segments[bent_trace.segments.size() - 1]
		_check("偏折方向朝上", tip.y < -50.0, "末端 %s" % tip)

	# 4) 把接收区挪到偏折后的路径上 → 应命中（层 4 分发 + 层 3 扫描都通了）
	_receiver.position = Vector2(402, -106)
	await get_tree().physics_frame
	await get_tree().physics_frame
	traces = RayCaster.trace_multi(space, Vector2(0, 0), Vector2.RIGHT, 32)
	_check("折射后的光路能命中接收区", _hits_receiver(traces))

	# 5) 预算约束：段数很少时不应卡死
	traces = RayCaster.trace_multi(space, Vector2(0, 0), Vector2.RIGHT, 2)
	_check("小预算不报错且能返回", traces.size() >= 1, "实际 %d 条" % traces.size())

	print("")
	if _failed == 0:
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)


func _make_receiver(pos: Vector2) -> Area2D:
	var area := Area2D.new()
	area.position = pos
	area.collision_layer = RayCaster.LAYER_RECEIVER
	area.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 40)
	shape.shape = rect
	area.add_child(shape)
	return area


func _make_plate(pos: Vector2, bend: float) -> RefractSurface:
	var plate := RefractSurface.new()
	plate.position = pos
	plate.mode = RefractSurface.BendMode.FIXED
	plate.bend_degrees = bend
	plate.attenuation = 0.0
	plate.collision_layer = RayCaster.LAYER_OPTIC
	plate.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8, 120)
	shape.shape = rect
	plate.add_child(shape)
	return plate


func _hits_receiver(traces: Array) -> bool:
	for trace in traces:
		for hit in trace.receiver_hits:
			if hit.receiver == _receiver:
				return true
	return false


func _find_bent_trace(traces: Array):
	for trace in traces:
		if trace.segments.size() < 2:
			continue
		if trace.segments[0].x < 350.0 and trace.segments[trace.segments.size() - 1].y < -50.0:
			return trace
	return null


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s   %s" % [label, detail])
