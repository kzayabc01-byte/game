extends Node

## 凹透镜（分束）单测：验证束数、扇面夹角、能量衰减。
## 跑法：tools\dev.bat 40

var _failed := 0


func _ready() -> void:
	_test_three_rays()
	_test_two_rays()
	_test_energy_floor()
	print("")
	if _failed == 0:
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)


func _test_three_rays() -> void:
	print("")
	print("--- 三分束 ---")
	var lens := ConcaveLens.new()
	lens.split_count = 3
	lens.fan_degrees = 30.0
	lens.energy_falloff = 0.6

	var out := lens.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	_check("分 3 束", out.size() == 3, "实际 %d 束" % out.size())
	if out.size() != 3:
		return

	var angles: Array[float] = []
	for ray in out:
		angles.append(rad_to_deg((ray["dir"] as Vector2).angle()))
	_check("扇面夹角 15°", absf(absf(angles[1] - angles[0]) - 15.0) < 0.5,
			"实际 %.2f°" % absf(angles[1] - angles[0]))
	_check("中间那束沿原方向", absf(angles[1]) < 0.5, "实际 %.2f°" % angles[1])
	_check("能量 = 0.6", absf(float(out[0]["energy"]) - 0.6) < 0.001,
			"实际 %.3f" % float(out[0]["energy"]))


func _test_two_rays() -> void:
	print("")
	print("--- 两分束 ---")
	var lens := ConcaveLens.new()
	lens.split_count = 2
	lens.fan_degrees = 40.0
	var out := lens.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	_check("分 2 束", out.size() == 2, "实际 %d 束" % out.size())
	if out.size() != 2:
		return
	var a := rad_to_deg((out[0]["dir"] as Vector2).angle())
	var b := rad_to_deg((out[1]["dir"] as Vector2).angle())
	_check("对称 ±20°", absf(a + 20.0) < 0.5 and absf(b - 20.0) < 0.5,
			"实际 %.1f° / %.1f°" % [a, b])


func _test_energy_floor() -> void:
	print("")
	print("--- 能量地板 ---")
	var lens := ConcaveLens.new()
	lens.split_count = 3
	lens.energy_falloff = 0.6
	# 能量 0.2 × 0.6 = 0.12 < MIN_ENERGY(0.15) → 不应产生光线
	var out := lens.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 0.2)
	_check("能量不足时不产生光线", out.is_empty(), "实际 %d 束" % out.size())


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s   %s" % [label, detail])
