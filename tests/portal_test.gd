extends Node

## 传送门单测：平面语义（切向保留 / 法向取反）、对应位置、两侧一致、
## 单向、镜像、pair_id 配对、未配对吞光。
## 跑法：tools\dev.bat 40

var _failed := 0
var _fixtures: Array[Node] = []


func _ready() -> void:
	_test_plane_mapping()
	_test_front_side()
	_test_offset_preserved()
	_test_mirror()
	_test_one_way()
	_test_unlinked()
	await _test_pair_id()
	await _test_auto_link()
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


func _make_pair(entry_rotation: float, exit_rotation: float, exit_pos := Vector2(300.0, 0.0)) -> Array[Portal]:
	var entry := Portal.new()
	_fixtures.append(entry)
	entry.position = Vector2.ZERO
	entry.rotation = entry_rotation
	var exit := Portal.new()
	_fixtures.append(exit)
	exit.position = exit_pos
	exit.rotation = exit_rotation
	entry.linked_portal = exit
	exit.linked_portal = entry
	return [entry, exit]


func _test_plane_mapping() -> void:
	print("")
	print("--- 平面映射：同朝向的两扇门 ---")
	var pair := _make_pair(0.0, 0.0)
	var entry: Portal = pair[0]

	# 光朝 +X 打向 A：A 法线也是 +X，属于“从背面射入”
	var out := entry.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	_check("产生 1 条出射光线", out.size() == 1, "实际 %d 条" % out.size())
	if out.size() != 1:
		return

	var dir: Vector2 = out[0]["dir"]
	# 切向保留、法向取反：(1,0) → (-1,0)
	_check("出射方向 = 法向取反（朝 -X）", dir.dot(Vector2.LEFT) > 0.99, "实际 %s" % dir)
	_check("能量 = 0.8", absf(float(out[0]["energy"]) - 0.8) < 0.001,
			"实际 %.3f" % float(out[0]["energy"]))


func _test_front_side() -> void:
	print("")
	print("--- 正面进 → 正面出 ---")
	# A 法线朝 -X（正面迎着朝 +X 的光），B 法线朝 +Y
	var pair := _make_pair(PI, PI * 0.5)
	var entry: Portal = pair[0]
	var exit: Portal = pair[1]

	_check("A 的正面迎着入射光", entry.get_approach_sign(Vector2.RIGHT) < 0.0)
	var out := entry.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	if out.size() != 1:
		_check("产生 1 条出射光线", false, "实际 %d 条" % out.size())
		return
	var dir: Vector2 = out[0]["dir"]
	# 从 A 正面进 → 从 B 正面出（+nB = DOWN）
	_check("从 B 的正面射出（朝下）", dir.dot(Vector2.DOWN) > 0.99, "实际 %s" % dir)
	var origin: Vector2 = out[0]["origin"]
	_check("起点在 B 平面附近", origin.distance_to(exit.global_position) < 2.0, "实际 %s" % origin)


func _test_offset_preserved() -> void:
	print("")
	print("--- 对应位置：打在 A 上方，就从 B 上方出来 ---")
	var pair := _make_pair(0.0, 0.0, Vector2(300.0, 0.0))
	var entry: Portal = pair[0]
	# A 的切向 = DOWN，所以“上方”是 -Y（offset = -30）
	var hit := entry.global_position - Vector2.DOWN * 30.0
	var exit_point := entry.map_point(hit)
	_check("map_point 切向偏移保持", absf(exit_point.y - (-30.0)) < 0.001,
			"实际 %s" % exit_point)

	var out := entry.on_ray(Vector2.RIGHT, Vector2.LEFT, hit, 1.0)
	if out.size() != 1:
		_check("产生 1 条出射光线", false)
		return
	var origin: Vector2 = out[0]["origin"]
	_check("出射点也在 B 上方", origin.y < -25.0, "实际 %s" % origin)


func _test_mirror() -> void:
	print("")
	print("--- 镜像模式（不可能光路）---")
	var pair := _make_pair(0.0, 0.0)
	var entry: Portal = pair[0]
	entry.mirror_out = true

	var in_dir := Vector2(0.8, 0.6).normalized()
	var out := entry.on_ray(in_dir, Vector2.LEFT, Vector2.ZERO, 1.0)
	if out.size() != 1:
		_check("产生 1 条出射光线", false)
		return
	var dir: Vector2 = out[0]["dir"]
	# 不镜像：(0.6, -0.8) 方向 → (-0.8, 0.6)；镜像后切向再反 → (-0.8, -0.6)
	var expected := Vector2(-0.8, -0.6).normalized()
	_check("镜像后切向取反", dir.dot(expected) > 0.99, "实际 %s" % dir)

	var hit := Vector2(0.0, 25.0)
	var mirrored_point := entry.map_point(hit)
	_check("镜像后出射点也翻到另一侧", mirrored_point.y < 0.0, "实际 %s" % mirrored_point)


func _test_one_way() -> void:
	print("")
	print("--- 单向门 ---")
	var pair := _make_pair(0.0, 0.0)
	var entry: Portal = pair[0]
	entry.one_way = true

	var from_back := entry.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	_check("从背面射入被吞掉", from_back.is_empty(), "实际 %d 条" % from_back.size())

	var from_front := entry.on_ray(Vector2.LEFT, Vector2.RIGHT, Vector2.ZERO, 1.0)
	_check("从正面射入可以传送", from_front.size() == 1, "实际 %d 条" % from_front.size())


func _test_unlinked() -> void:
	print("")
	print("--- 未配对的坏门 ---")
	var lonely := Portal.new()
	_fixtures.append(lonely)
	lonely.position = Vector2.ZERO
	var out := lonely.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	_check("未配对时吞掉光线", out.is_empty(), "实际 %d 条" % out.size())


func _test_pair_id() -> void:
	print("")
	print("--- pair_id 配对（多对门同场不乱配）---")
	var a := Portal.new()
	_fixtures.append(a)
	a.position = Vector2(0.0, 0.0)
	a.pair_id = &"red"
	var b := Portal.new()
	_fixtures.append(b)
	b.position = Vector2(500.0, 0.0)
	b.pair_id = &"red"
	var c := Portal.new()
	_fixtures.append(c)
	c.position = Vector2(60.0, 0.0)   # 离 A 更近，但 pair_id 不同
	c.pair_id = &"blue"
	add_child(a)
	add_child(b)
	add_child(c)
	await get_tree().process_frame

	_check("A 配到同 id 的 B（而不是更近的 C）", a.linked_portal == b,
			"实际 %s" % ("null" if a.linked_portal == null else a.linked_portal.name))
	_check("B 也指回 A", b.linked_portal == a)
	_check("C 保持未配对", c.linked_portal == null)

	a.queue_free()
	b.queue_free()
	c.queue_free()
	await get_tree().process_frame


func _test_auto_link() -> void:
	print("")
	print("--- 配对与距离无关 ---")
	# 1) 两扇门挨得很近，但没有编号：不应该被自动配对
	var near_a := Portal.new()
	_fixtures.append(near_a)
	near_a.position = Vector2(0.0, 0.0)
	var near_b := Portal.new()
	_fixtures.append(near_b)
	near_b.position = Vector2(40.0, 0.0)
	add_child(near_a)
	add_child(near_b)
	await get_tree().process_frame
	_check("挨得近但没编号 → 不配对",
			near_a.linked_portal == null and near_b.linked_portal == null,
			"%s / %s" % [near_a.linked_portal, near_b.linked_portal])
	near_a.queue_free()
	near_b.queue_free()
	await get_tree().process_frame

	# 2) 编号相同、相距几千像素：仍然配对
	var far_a := Portal.new()
	_fixtures.append(far_a)
	far_a.position = Vector2(0.0, 0.0)
	far_a.pair_id = &"far"
	var far_b := Portal.new()
	_fixtures.append(far_b)
	far_b.position = Vector2(2400.0, 1800.0)
	far_b.pair_id = &"far"
	add_child(far_a)
	add_child(far_b)
	await get_tree().process_frame
	_check("相距约 3000px 仍按编号配对",
			far_a.linked_portal == far_b and far_b.linked_portal == far_a,
			"%s / %s" % [far_a.linked_portal, far_b.linked_portal])

	# 3) 离得再远也不改关系：同编号 + 另一个未编号的近门，仍配原来那扇
	var near_c := Portal.new()
	_fixtures.append(near_c)
	near_c.position = far_a.position + Vector2(30.0, 0.0)
	add_child(near_c)
	await get_tree().process_frame
	_check("新增的近门不会抢走已配对的门",
			far_a.linked_portal == far_b and near_c.linked_portal == null,
			"%s / %s" % [far_a.linked_portal, near_c.linked_portal])

	far_a.queue_free()
	far_b.queue_free()
	near_c.queue_free()
	await get_tree().process_frame


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s   %s" % [label, detail])
