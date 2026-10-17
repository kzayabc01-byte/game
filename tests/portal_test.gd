extends Node

## 传送门单测：保角映射、镜像模式、未配对的坏门、自动互链。
## 跑法：tools\dev.bat 40

var _failed := 0


func _ready() -> void:
	_test_preserve_angle()
	_test_mirror()
	_test_unlinked()
	await _test_auto_link()
	print("")
	if _failed == 0:
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)


func _make_pair(exit_rotation: float) -> Array[Portal]:
	var entry := Portal.new()
	entry.position = Vector2.ZERO
	var exit := Portal.new()
	exit.position = Vector2(300.0, 0.0)
	exit.rotation = exit_rotation
	entry.linked_portal = exit
	return [entry, exit]


func _test_preserve_angle() -> void:
	print("")
	print("--- 保角映射 ---")
	var pair := _make_pair(PI * 0.5)
	var entry := pair[0]
	var exit := pair[1]

	var out := entry.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	_check("产生 1 条出射光线", out.size() == 1, "实际 %d 条" % out.size())
	if out.size() != 1:
		return

	var dir: Vector2 = out[0]["dir"]
	# Godot 屏幕坐标 Y 向下：+90° 旋转把 RIGHT 变成 DOWN
	_check("出口旋转 90° → 出射朝下", dir.dot(Vector2.DOWN) > 0.99, "实际 %s" % dir)
	var origin: Vector2 = out[0]["origin"]
	_check("起点在出口附近", origin.distance_to(exit.global_position) < 3.0,
			"实际 %s" % origin)
	_check("能量 = 0.8", absf(float(out[0]["energy"]) - 0.8) < 0.001,
			"实际 %.3f" % float(out[0]["energy"]))


func _test_mirror() -> void:
	print("")
	print("--- 镜像模式 ---")
	var pair := _make_pair(PI * 0.5)
	pair[0].mirror_out = true

	var out := pair[0].on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	_check("产生 1 条出射光线", out.size() == 1)
	if out.size() != 1:
		return
	var dir: Vector2 = out[0]["dir"]
	# 保角得到 (0,1)=DOWN，再关于出口法线 (0,1) 镜像 → (0,-1)=UP
	_check("镜像后朝上", dir.dot(Vector2.UP) > 0.99, "实际 %s" % dir)


func _test_unlinked() -> void:
	print("")
	print("--- 未配对的坏门 ---")
	var lonely := Portal.new()
	var out := lonely.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	_check("未配对时吞掉光线", out.is_empty(), "实际 %d 条" % out.size())


func _test_auto_link() -> void:
	print("")
	print("--- 自动互链（自由放置用）---")
	var a := Portal.new()
	a.position = Vector2(0.0, 0.0)
	var b := Portal.new()
	b.position = Vector2(120.0, 0.0)
	add_child(a)
	add_child(b)
	await get_tree().process_frame
	_check("A 自动连到 B", a.linked_portal == b)
	_check("B 自动连回 A", b.linked_portal == a)
	a.queue_free()
	b.queue_free()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s   %s" % [label, detail])
