extends Node

## 冰川单测：持续照射会融化、断光暂停、R 重置复原。
## 跑法：tools\dev.bat 40

var _failed := 0


func _ready() -> void:
	await _test_melt_gate()
	await _test_no_light_no_melt()
	await _test_reset()
	print("")
	if _failed == 0:
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)


func _make_glacier() -> Glacier:
	var ice := Glacier.new()
	ice.collision_layer = 8
	ice.melt_seconds = 0.2
	ice.melt_efficiency = 1.0
	ice.bend_degrees = 0.0
	add_child(ice)
	return ice


func _test_melt_gate() -> void:
	print("")
	print("--- 持续照射会融化 ---")
	var ice := _make_glacier()
	var start := Time.get_ticks_msec()
	while not ice.is_melted() and Time.get_ticks_msec() - start < 3000:
		ice.on_ray(Vector2.RIGHT, Vector2.LEFT, ice.global_position, 1.0)
		await get_tree().physics_frame
	var elapsed := Time.get_ticks_msec() - start
	_check("会被光融化", ice.is_melted())
	_check("耗时接近 melt_seconds(0.2s)", elapsed < 1200, "实际 %d ms" % elapsed)
	_check("融化后不再参与光路", ice.on_ray(Vector2.RIGHT, Vector2.LEFT, ice.global_position, 1.0).is_empty())
	_check("融化后碰撞层归零", ice.collision_layer == 0, "实际 %d" % ice.collision_layer)
	ice.queue_free()
	await get_tree().process_frame


func _test_no_light_no_melt() -> void:
	print("")
	print("--- 断光不融化 ---")
	var ice := _make_glacier()
	# 只照一帧，然后停 15 帧
	ice.on_ray(Vector2.RIGHT, Vector2.LEFT, ice.global_position, 1.0)
	await get_tree().physics_frame
	for _i in 15:
		await get_tree().physics_frame
	_check("断光后不会自己融化", not ice.is_melted())
	_check("进度没有超过 0.5", ice.get_progress() < 0.5, "实际 %.2f" % ice.get_progress())
	ice.queue_free()
	await get_tree().process_frame


func _test_reset() -> void:
	print("")
	print("--- R 重置复原 ---")
	var ice := _make_glacier()
	var start := Time.get_ticks_msec()
	while not ice.is_melted() and Time.get_ticks_msec() - start < 3000:
		ice.on_ray(Vector2.RIGHT, Vector2.LEFT, ice.global_position, 1.0)
		await get_tree().physics_frame
	_check("先确认已融化", ice.is_melted())

	ice.reset_state()
	await get_tree().physics_frame
	_check("重置后回到未融化", not ice.is_melted())
	_check("重置后进度归零", is_zero_approx(ice.get_progress()), "实际 %.2f" % ice.get_progress())
	_check("重置后碰撞层恢复", ice.collision_layer == 8, "实际 %d" % ice.collision_layer)
	ice.queue_free()
	await get_tree().process_frame


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s   %s" % [label, detail])
