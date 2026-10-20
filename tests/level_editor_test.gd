extends Node

## 关卡编辑器 API 测试（验证门 2）：headless 实例化编辑器场景，
## 验证六步挂载中和、生成/命名、电线连线序列化、撤销复原、删除/复制。
## 跑法：godot --headless --path . res://tests/level_editor_test.tscn

const WALL_SCENE := "res://blocks/wall/wall.tscn"
const SWITCH_SCENE := "res://blocks/trigger_switch/trigger_switch.tscn"
const MIRROR_SCENE := "res://blocks/mirror/mirror.tscn"
const REFRACT_SCENE := "res://blocks/refract_surface/refract_surface.tscn"

var _failures: Array[String] = []
var _editor: LevelEditor = null


func _ready() -> void:
	# 看门狗：_run 中途崩溃时 quit 不会执行，保证进程必定退出而不是挂死
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("TEST RESULT: FAIL（90 秒超时，测试脚本崩溃或挂起）")
		get_tree().quit(1))
	_run()


func _check(message: String, condition: bool) -> void:
	if condition:
		print("  [OK]   ", message)
	else:
		_failures.append(message)
		print("  [FAIL] ", message)


func _run() -> void:
	var packed := load("res://scenes/editor/level_editor.tscn") as PackedScene
	_check("编辑器场景可加载", packed != null)
	if packed == null:
		_finish()
		return
	_check("既有关卡可加入编辑队列",
			LevelFileIO.queue_level_for_edit("res://scenes/levels/level_01.tscn"))
	_editor = packed.instantiate() as LevelEditor
	add_child(_editor)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("编辑器启动时载入指定的已有关卡",
			_editor.get_current_path() == "res://scenes/levels/level_01.tscn"
			and _editor.get_level_root().name == "Level01")
	_editor.new_level()

	# 1. 场景结构
	_check("编辑器节点树齐全",
			_editor.get_node_or_null("World/RayRenderer") != null
			and _editor.get_node_or_null("World/WireLayer") != null
			and _editor.get_node_or_null("World/LevelRoot") != null
			and _editor.get_node_or_null("World/Gizmo") != null
			and _editor.get_node_or_null("EditorCamera") != null
			and _editor.get_node_or_null("UI") != null)

	# 2. new_level 中和（六步管线）
	var root := _editor.get_level_root()
	_check("new_level 挂载了关卡根", root != null)
	_check("关卡根 process 已停摆", root != null and root.process_mode == Node.PROCESS_MODE_DISABLED)
	var level_camera := root.get_node_or_null("Camera2D") as Camera2D
	_check("关卡相机已禁用", level_camera != null and not level_camera.enabled)

	# 3. 生成与命名
	var wall1 := _editor.spawn_block(WALL_SCENE, Vector2(100, 100))
	var wall2 := _editor.spawn_block(WALL_SCENE, Vector2(200, 200))
	_check("生成第一块墙体命名 Wall", wall1 != null and wall1.name == "Wall")
	_check("生成第二块墙体命名 Wall2", wall2 != null and wall2.name == "Wall2")
	_check("积木挂在 Blocks 下", wall1 != null and wall1.get_parent() == root.get_node("Blocks"))

	# 4. 微移 + 撤销复原（撤销会换子树，引用全部重取）
	_editor.select(wall1)
	_editor.nudge_selected(Vector2(32, 0))
	_check("微移生效", wall1.position == Vector2(132, 100))
	_check("撤销成功", _editor.undo())
	root = _editor.get_level_root()
	wall1 = root.get_node("Blocks/Wall") as Node2D
	_check("撤销后位置复原", wall1 != null and wall1.position == Vector2(100, 100))
	_editor.select(wall1)
	var rotation_spin := _editor.get("_spin_rotation") as SpinBox
	_check("检查器数值框开启输入即更新",
			rotation_spin != null and rotation_spin.update_on_text_changed)
	if rotation_spin != null:
		var rotation_edit := rotation_spin.get_line_edit()
		rotation_edit.text = "37"
		rotation_edit.text_changed.emit("37")
		await get_tree().process_frame
	_check("检查器键入旋转角后画面立即响应",
			wall1 != null and absf(rad_to_deg(wall1.rotation) - 37.0) < 0.01)

	# 5. 电线连线
	var trigger := _editor.spawn_block(SWITCH_SCENE, Vector2(300, 300))
	var mirror := _editor.spawn_block(MIRROR_SCENE, Vector2(400, 300))
	_check("连线成功", _editor.connect_wire(trigger, mirror))
	_check("电线数 1", _editor.get_wire_count() == 1)
	_check("重复连线到同一机关被拒绝", not _editor.connect_wire(trigger, mirror))
	_check("电线数仍为 1", _editor.get_wire_count() == 1)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check("镜面在编辑器里不漂移", mirror != null and mirror.position == Vector2(400, 300))
	var link := root.get_node_or_null("Blocks/Wire") as ActionLink
	_editor.select(mirror)
	_editor.nudge_selected(Vector2(16, 0))
	_check("电线目标重新摆放后原位同步", mirror.position == Vector2(416, 300))
	_editor.select_wire(0)
	_editor.set_wire_property(0, &"move_offset", Vector2(96, -32))
	_editor.set_wire_property(0, &"rotate_degrees", 30.0)
	_check("可开启电线动作位预览", link != null and _editor.preview_wire_action(0, true))
	_check("电线预览让指定机关立即位移旋转", mirror.position == Vector2(512, 268)
			and absf(rad_to_deg(mirror.rotation) - 30.0) < 0.01)
	_editor.set_wire_property(0, &"move_offset", Vector2(64, -48), false)
	_check("预览中修改电线参数立即响应", mirror.position == Vector2(480, 252))
	var preview_text := _editor.serialize()
	_check("序列化后仍保持编辑器预览", mirror.position == Vector2(480, 252))
	var preview_path := "user://editor_preview_safety_test.tscn"
	_check("写预览安全性临时关卡", LevelFileIO.write_text(preview_path, preview_text) == OK)
	var preview_packed := ResourceLoader.load(
			preview_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var preview_saved := preview_packed.instantiate() if preview_packed != null else null
	var preview_saved_mirror: Node2D = null
	if preview_saved != null:
		preview_saved_mirror = preview_saved.get_node_or_null("Blocks/Mirror") as Node2D
	_check("动作位预览不会被写进关卡", preview_saved_mirror != null
			and preview_saved_mirror.position == Vector2(416, 300)
			and absf(preview_saved_mirror.rotation) < 0.01)
	if preview_saved != null:
		preview_saved.free()
	_check("关闭预览后目标回原位", _editor.preview_wire_action(0, false)
			and mirror.position == Vector2(416, 300)
			and absf(mirror.rotation) < 0.01)

	# 6. 序列化内容
	var text := _editor.serialize()
	_check("序列化含正确电线连接行", text.contains(
			"[connection signal=\"active_changed\" from=\"Blocks/TriggerSwitch\" to=\"Blocks/Wire\" method=\"_on_signal\"]"))
	_check("序列化含电线节点目标", text.contains("target_node = NodePath(\"../Mirror\")"))
	_check("输出不含编辑器节点", not text.contains("WireLayer") and not text.contains("LevelEditor")
			and not text.contains("Gizmo") and not text.contains("EditorCamera")
			and not text.contains("RayRenderer"))

	# 7. 产物可载入、连接表正确
	var out_path := "user://editor_test_level.tscn"
	_check("写临时关卡文件", LevelFileIO.write_text(out_path, text) == OK)
	var reloaded_packed := load(out_path) as PackedScene
	_check("产物可载入", reloaded_packed != null)
	var reloaded := reloaded_packed.instantiate()
	var reloaded_trigger := reloaded.get_node("Blocks/TriggerSwitch")
	_check("重载后连接表正确", reloaded_trigger != null
			and reloaded_trigger.get_signal_connection_list(&"active_changed").size() == 1)
	var reloaded_wire := reloaded.get_node_or_null("Blocks/Wire")
	_check("重载后电线节点存在", reloaded_wire != null
			and reloaded_wire is ActionLink
			and (reloaded_wire as ActionLink).target_node == NodePath("../Mirror"))
	_check("重载后 4 块积木 + 1 条电线", LevelFileIO.walk_instance_roots(reloaded).size() == 5)
	reloaded.free()

	# 8. 删除
	wall2 = root.get_node("Blocks/Wall2") as Node2D
	_check("删除前 Wall2 存在", wall2 != null)
	_editor.select(wall2)
	_editor.delete_selected()
	_check("删除后序列化不含 Wall2", not _editor.serialize().contains("name=\"Wall2\""))

	# 9. 复制
	wall1 = root.get_node("Blocks/Wall") as Node2D
	_editor.select(wall1)
	_editor.duplicate_selected()
	var blocks := root.get_node("Blocks")
	_check("复制后 Blocks 下有两块墙体", blocks.has_node("Wall") and blocks.has_node("Wall2"))
	var copy := blocks.get_node("Wall2") as Node2D
	_check("复制体偏移 32px", copy != null and copy.position == Vector2(132, 132))

	# 10. 变色片预设（折射面改色预设）
	var changer := _editor.spawn_block(
			REFRACT_SCENE, Vector2(500, 500), "", {"recolor": true}, "color_changer")
	_check("变色片预设生效", changer != null and changer.recolor and changer.name == "ColorChanger")
	var color_entry := PaletteData.find_entry_for(REFRACT_SCENE, "ColorChanger")
	_check("预设条目按名字区分", color_entry.get("key", "") == "color_changer")
	var plain_entry := PaletteData.find_entry_for(REFRACT_SCENE, "RefractSurface")
	_check("普通折射面不受预设影响", plain_entry.get("key", "") == "refract_surface")
	var plain_props: Array = plain_entry.get("props", [])
	var has_bend_degrees := false
	for prop in plain_props:
		if prop.get("name") == &"bend_degrees":
			has_bend_degrees = true
	_check("普通折射面可在编辑面板设置折射偏角", has_bend_degrees)
	var plain_refract := _editor.spawn_block(REFRACT_SCENE, Vector2(550, 420)) as RefractSurface
	_editor.set_selected_property(&"bend_degrees", -35.0)
	_check("折射偏角修改立即写入积木", plain_refract != null
			and is_equal_approx(plain_refract.bend_degrees, -35.0))
	var bend_path := "user://editor_refract_angle_test.tscn"
	_check("写折射偏角临时关卡",
			LevelFileIO.write_text(bend_path, _editor.serialize()) == OK)
	var bend_packed := ResourceLoader.load(
			bend_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var bend_saved := bend_packed.instantiate() if bend_packed != null else null
	var bend_saved_refract: RefractSurface = null
	if bend_saved != null:
		bend_saved_refract = bend_saved.get_node_or_null("Blocks/RefractSurface") as RefractSurface
	_check("折射偏角会保存进关卡", bend_saved_refract != null
			and is_equal_approx(bend_saved_refract.bend_degrees, -35.0))
	if bend_saved != null:
		bend_saved.free()
	var has_color_trigger := false
	for entry in PaletteData.get_entries():
		if entry.get("key", "") == "color_trigger":
			has_color_trigger = true
	_check("调色板不再提供颜色感应开关", not has_color_trigger)
	var filtered_trigger := _editor.spawn_block(
			SWITCH_SCENE, Vector2(600, 500), "",
			{"match_color": true, "color_filter": Color(1.0, 0.25, 0.25)}, "trigger_switch")
	_check("普通触发机关可启用颜色感应",
			filtered_trigger != null and filtered_trigger.match_color
			and filtered_trigger.color_filter.is_equal_approx(Color(1.0, 0.25, 0.25)))

	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("TEST RESULT: PASS")
		get_tree().quit(0)
	else:
		print("TEST RESULT: FAIL（%d 项）" % _failures.size())
		get_tree().quit(1)
