extends Node

## 折射介质单测：直接调 on_ray() 验证数学，不依赖光线系统。
## 跑法：tools\dev.bat 40（自动扫描 tests\*.tscn）

var _failed := 0


func _ready() -> void:
	_test_fixed()
	_test_snell()
	print("")
	if _failed == 0:
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL（%d 项不通过）" % _failed)
	get_tree().quit(0 if _failed == 0 else 1)


func _test_fixed() -> void:
	print("")
	print("--- FIXED 模式 ---")
	var plate := RefractSurface.new()
	plate.mode = RefractSurface.BendMode.FIXED
	plate.bend_degrees = 20.0
	plate.attenuation = 0.05

	var out := plate.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	_check("产生 1 条出射光线", out.size() == 1, "实际 %d 条" % out.size())
	if out.size() != 1:
		return

	var dir: Vector2 = out[0]["dir"]
	var deviation := rad_to_deg(absf(dir.angle()))
	_check("偏折 20°", absf(deviation - 20.0) < 0.5, "实际 %.2f°" % deviation)
	_check("能量 = 0.95", absf(float(out[0]["energy"]) - 0.95) < 0.001,
			"实际 %.3f" % float(out[0]["energy"]))

	plate.bend_degrees = -45.0
	out = plate.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	# Godot 屏幕坐标 Y 向下：-45° 把 RIGHT 转成右上
	_check("偏折 -45° 时朝右上方", out.size() == 1 and (out[0]["dir"] as Vector2).y < -0.5,
			"实际 %s" % (out[0]["dir"] if out.size() == 1 else Vector2.ZERO))


func _test_snell() -> void:
	print("")
	print("--- SNELL 模式 ---")
	var plate := RefractSurface.new()
	plate.mode = RefractSurface.BendMode.SNELL
	plate.ior = 1.5
	plate.attenuation = 0.0

	# 法线入射：方向不变
	var out := plate.on_ray(Vector2.RIGHT, Vector2.LEFT, Vector2.ZERO, 1.0)
	var straight_ok: bool = out.size() == 1 and (out[0]["dir"] as Vector2).dot(Vector2.RIGHT) > 0.999
	_check("法线入射不偏折", straight_ok)

	# 40° 入射：按斯涅尔应偏折 14.63°
	var angle := deg_to_rad(40.0)
	var in_dir := Vector2.RIGHT.rotated(angle)
	out = plate.on_ray(in_dir, Vector2.LEFT, Vector2.ZERO, 1.0)
	if out.size() != 1:
		_check("40° 入射应有出射光线", false)
		return
	var out_dir: Vector2 = out[0]["dir"]
	var dev := rad_to_deg(absf(out_dir.angle() - in_dir.angle()))
	_check("40° 入射偏折 ≈ 14.63°", absf(dev - 14.63) < 0.6, "实际 %.2f°" % dev)
	_check("折射后方向朝前", out_dir.x > 0.0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s   %s" % [label, detail])
