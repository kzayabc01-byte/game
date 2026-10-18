extends Node

## 端到端测试：真实的光线系统（LightSystem）驱动分束后的机关点亮。
## 覆盖链路段：光源 → trace_multi → 凹透镜分束 → 接收区扫描 → apply_lit。
## 跑法：tools\dev.bat 40

class Probe extends LightReceiver:
	pass


var _failed := 0


func _ready() -> void:
	var system := LightSystem.new()
	add_child(system)

	var source := LightSource.new()
	source.position = Vector2(0, 0)
	source.rotation = 0.0  # 朝 +X
	add_child(source)

	var direct := _make_probe(Vector2(150, 0))
	add_child(direct)
	await _wait_frames(3)
	_check("直射点亮接收区", direct.is_lit())

	# 插入凹透镜：光被分成 ±20° 两束，直射方向不再有光
	var lens := ConcaveLens.new()
	lens.position = Vector2(80, 0)
	lens.split_count = 2
	lens.fan_degrees = 40.0
	lens.energy_falloff = 0.6
	lens.collision_layer = RayCaster.LAYER_OPTIC
	lens.collision_mask = 0
	_add_box(lens, Vector2(8, 120))
	add_child(lens)

	var up_target := _make_probe(_point_at(Vector2(76, 0), -20.0, 110.0))
	var down_target := _make_probe(_point_at(Vector2(76, 0), 20.0, 110.0))
	add_child(up_target)
	add_child(down_target)

	await _wait_frames(4)
	_check("分束后原直射接收区熄灭", not direct.is_lit())
	_check("分束命中上方目标", up_target.is_lit())
	_check("分束命中下方目标", down_target.is_lit())
	_check("两个目标同时被点亮", up_target.is_lit() and down_target.is_lit())

	print("")
	if _failed == 0:
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)


func _point_at(origin: Vector2, degrees: float, distance: float) -> Vector2:
	return origin + Vector2.RIGHT.rotated(deg_to_rad(degrees)) * distance


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


func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s   %s" % [label, detail])
