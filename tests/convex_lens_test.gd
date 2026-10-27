extends Node

## 凸透镜单测：能量放大、光柱变细、方向不变、能量上限，以及光路里确实断成两段。
## 跑法：tools\dev.bat 40

var _failed := 0
var _fixtures: Array[Node] = []


func _ready() -> void:
	_test_focus()
	_test_cap()
	await _test_trace_break()
	print("")
	if _failed == 0:
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failed)
	for fixture in _fixtures:
		if is_instance_valid(fixture):
			fixture.free()
	_fixtures.clear()
	get_tree().quit(0 if _failed == 0 else 1)


func _test_focus() -> void:
	print("")
	print("--- 聚光：能量变大、光柱变细、方向不变 ---")
	var lens := ConvexLens.new()
	_fixtures.append(lens)
	lens.focus_gain = 1.8
	lens.beam_narrow = 0.45

	var out := lens.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	_check("产生 1 条出射光线", out.size() == 1, "实际 %d 条" % out.size())
	if out.size() != 1:
		return
	var ray: Dictionary = out[0]
	_check("能量 1.0 → 1.8", absf(float(ray["energy"]) - 1.8) < 0.001,
			"实际 %.3f" % float(ray["energy"]))
	_check("方向不变", (ray["dir"] as Vector2).dot(Vector2.RIGHT) > 0.999)
	_check("标记为变细（width=0.45）", absf(float(ray.get("width", 1.0)) - 0.45) < 0.001,
			"实际 %s" % ray.get("width", 1.0))
	_check("要求断开折线（break）", bool(ray.get("break", false)))


func _test_cap() -> void:
	print("")
	print("--- 能量上限 ---")
	var lens := ConvexLens.new()
	_fixtures.append(lens)
	lens.focus_gain = 1.8
	var out := lens.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 3.0)
	_check("能量封顶在 MAX_ENERGY(%.1f)" % RayCaster.MAX_ENERGY,
			out.size() == 1 and absf(float(out[0]["energy"]) - RayCaster.MAX_ENERGY) < 0.001,
			"实际 %s" % (out[0]["energy"] if out.size() == 1 else "无"))


func _test_trace_break() -> void:
	print("")
	print("--- 光路里：透镜前后是两段，宽度不同 ---")
	var lens := ConvexLens.new()
	_fixtures.append(lens)
	lens.focus_gain = 1.8
	lens.beam_narrow = 0.45
	lens.position = Vector2(300, 300)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 96)
	shape.shape = rect
	lens.add_child(shape)
	add_child(lens)

	var receiver := Area2D.new()
	receiver.position = Vector2(600, 300)
	receiver.collision_layer = RayCaster.LAYER_RECEIVER
	receiver.collision_mask = 0
	var rec_shape := CollisionShape2D.new()
	var rec_rect := RectangleShape2D.new()
	rec_rect.size = Vector2(40, 40)
	rec_shape.shape = rec_rect
	receiver.add_child(rec_shape)
	add_child(receiver)

	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_viewport().find_world_2d().direct_space_state
	var traces := RayCaster.trace_all(space, Vector2(100, 300), Vector2.RIGHT)

	_check("透镜处断成 2 段折线", traces.size() == 2, "实际 %d 条" % traces.size())
	var focused: RayCaster.LightTrace = null
	for trace in traces:
		if trace.width_scale < 0.9:
			focused = trace
	_check("有一段是变细的光柱（width<0.9）", focused != null)
	if focused != null:
		_check("变细段的能量是 1.8", absf(focused.energy - 1.8) < 0.01,
				"实际 %.3f" % focused.energy)
		var hit_receiver := false
		for hit in focused.receiver_hits:
			if hit.receiver == receiver:
				hit_receiver = true
		_check("变细后的光仍能点亮接收区", hit_receiver)

	lens.queue_free()
	receiver.queue_free()
	await get_tree().process_frame


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s   %s" % [label, detail])
