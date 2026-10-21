extends Node

## 关卡编辑器 API 测试（验证门 2）：headless 实例化编辑器场景，
## 验证六步挂载中和、生成/命名、电线连线序列化、撤销复原、删除/复制。
## 跑法：godot --headless --path . res://tests/level_editor_test.tscn

const WALL_SCENE := "res://blocks/wall/wall.tscn"
const SWITCH_SCENE := "res://blocks/trigger_switch/trigger_switch.tscn"
const MIRROR_SCENE := "res://blocks/mirror/mirror.tscn"
const REFRACT_SCENE := "res://blocks/refract_surface/refract_surface.tscn"
const LIGHT_SOURCE_SCENE := "res://blocks/light_source/light_source.tscn"

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

	# 3. 画布缩放 / 平移只改变编辑视图，不污染关卡数据
	var view_text_before := _editor.serialize()
	var anchor := Vector2(720.0, 360.0)
	var anchor_world_before := _editor.screen_to_world(anchor)
	_editor.set_view_zoom(2.0, anchor)
	var anchor_world_after := _editor.screen_to_world(anchor)
	_check("缩放以鼠标位置为锚点",
			anchor_world_before.distance_to(anchor_world_after) < 0.1)
	var center_before_pan := _editor.get_view_center()
	_editor.pan_view(Vector2(80.0, -40.0))
	_check("画布可以平移", _editor.get_view_center().distance_to(center_before_pan) > 1.0)
	_check("缩放和平移不写进关卡", _editor.serialize() == view_text_before)
	_editor.reset_view()
	_check("复位视图恢复 100% 和关卡中心",
			is_equal_approx(_editor.get_view_zoom(), 1.0)
			and _editor.get_view_center().is_equal_approx(Vector2(576.0, 324.0)))
	var zoom_in_button := _find_base_button(_editor, "＋")
	_check("工具栏提供放大按钮", zoom_in_button != null)
	if zoom_in_button != null:
		zoom_in_button.pressed.emit()
	_check("点击放大按钮立即生效", _editor.get_view_zoom() > 1.0)
	_editor.reset_view()

	# 4. 生成与命名
	var wall1 := _editor.spawn_block(WALL_SCENE, Vector2(100, 100))
	var wall2 := _editor.spawn_block(WALL_SCENE, Vector2(200, 200))
	_check("生成第一块墙体命名 Wall", wall1 != null and wall1.name == "Wall")
	_check("生成第二块墙体命名 Wall2", wall2 != null and wall2.name == "Wall2")
	_check("积木挂在 Blocks 下", wall1 != null and wall1.get_parent() == root.get_node("Blocks"))

	# 5. 微移 + 撤销复原（撤销会换子树，引用全部重取）
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
	var light_source := _editor.spawn_block(
			LIGHT_SOURCE_SCENE, Vector2(720.0, 120.0)) as LightSource
	var source_rotation_before := light_source.rotation
	var turn_source_button := _find_base_button(_editor, "右转")
	_check("光源检查器提供快捷旋转", turn_source_button != null)
	if turn_source_button != null:
		turn_source_button.pressed.emit()
	_check("快捷旋转光源会立即改变方向",
			light_source.rotation > source_rotation_before
			and light_source.get_light_direction().y > 0.0)

	# 6. 电线连线
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

	# 信号源可一次预览全部出线，不运行关卡也能核对机关动作。
	_editor.select(trigger)
	var trigger_preview := _find_base_button(_editor, "模拟触发（仅预览）")
	_check("触发机关提供模拟开关", trigger_preview != null)
	if trigger_preview != null:
		trigger_preview.set_pressed_no_signal(true)
		trigger_preview.toggled.emit(true)
	_check("模拟触发会显示机关动作位",
			trigger.is_active() and mirror.position == Vector2(480, 252))
	if trigger_preview != null:
		trigger_preview.set_pressed_no_signal(false)
		trigger_preview.toggled.emit(false)
	_check("关闭模拟触发会恢复原位",
			not trigger.is_active() and mirror.position == Vector2(416, 300))

	# 实时验证运行真实信号和 Tween；退出后必须恢复进入前快照。
	# 光线系统会持续重算照射状态；锁存开关保证手动注入的上升沿可观察。
	_editor.set_selected_property(&"latch", true)
	_editor.set_wire_property(0, &"duration", 0.01)
	var validation_text := _editor.serialize()
	var validation_toggle := _find_base_button(_editor, "实时验证")
	_check("工具栏提供实时验证", validation_toggle != null)
	if validation_toggle != null:
		validation_toggle.set_pressed_no_signal(true)
		validation_toggle.toggled.emit(true)
	_check("实时验证会启用关卡处理",
			_editor.is_validation_mode()
			and root.process_mode == Node.PROCESS_MODE_INHERIT)
	(trigger as TriggerSwitch).apply_lit(true)
	for _frame in range(30):
		if mirror.position.distance_to(Vector2(480, 252)) < 1.0:
			break
		await get_tree().physics_frame
	_check("实时验证中触发机关会驱动目标",
			mirror.position.distance_to(Vector2(480, 252)) < 1.0)
	if validation_toggle != null:
		validation_toggle.set_pressed_no_signal(false)
		validation_toggle.toggled.emit(false)
	_check("结束实时验证会回到编辑模式", not _editor.is_validation_mode())
	root = _editor.get_level_root()
	trigger = root.get_node("Blocks/TriggerSwitch") as Node2D
	mirror = root.get_node("Blocks/Mirror") as Node2D
	link = root.get_node_or_null("Blocks/Wire") as ActionLink
	light_source = root.get_node_or_null("Blocks/LightSource") as LightSource
	var validation_text_after := _editor.serialize()
	_check("结束实时验证恢复设计快照",
			_normalize_root_name(validation_text_after) == _normalize_root_name(validation_text)
			and mirror.position == Vector2(416, 300))

	# 删除积木走真实按钮，并确认不会重现“释放正在发信号按钮”的对象锁错误。
	_editor.select(light_source)
	var delete_source_button := _find_base_button(_editor, "删除这个积木（Del）")
	_check("积木检查器提供删除按钮", delete_source_button != null)
	if delete_source_button != null:
		delete_source_button.pressed.emit()
		await get_tree().process_frame
	_check("点击删除积木后编辑器仍运行且积木已移除",
			is_instance_valid(_editor) and not root.get_node("Blocks").has_node("LightSource"))

	# 断开电线必须点击真实 Inspector 按钮，直接调 API 会漏掉对象锁崩溃。
	_editor.select_wire(0)
	var disconnect_button := _find_base_button(_editor, "断开这条电线")
	_check("电线检查器提供断开按钮", disconnect_button != null)
	if disconnect_button != null:
		disconnect_button.pressed.emit()
		await get_tree().process_frame
	_check("点击断开不会退出且电线已删除",
			is_instance_valid(_editor) and _editor.get_wire_count() == 0)
	_check("断开电线可以撤销", _editor.undo())
	root = _editor.get_level_root()
	trigger = root.get_node("Blocks/TriggerSwitch") as Node2D
	mirror = root.get_node("Blocks/Mirror") as Node2D
	link = root.get_node_or_null("Blocks/Wire") as ActionLink
	_check("撤销后电线恢复", _editor.get_wire_count() == 1 and link != null)

	# 7. 序列化内容
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


func _find_base_button(node: Node, text: String) -> BaseButton:
	if node is BaseButton and (node as BaseButton).text == text:
		return node as BaseButton
	for child in node.get_children():
		var found := _find_base_button(child, text)
		if found != null:
			return found
	return null


func _normalize_root_name(text: String) -> String:
	var lines := text.split("\n")
	for index in lines.size():
		if not lines[index].begins_with("[node name="):
			continue
		var instance_position := lines[index].find(" instance=")
		if instance_position >= 0:
			lines[index] = "[node name=\"ROOT\"" + lines[index].substr(instance_position)
		break
	return "\n".join(lines)


func _finish() -> void:
	if _failures.is_empty():
		print("TEST RESULT: PASS")
		get_tree().quit(0)
	else:
		print("TEST RESULT: FAIL（%d 项）" % _failures.size())
		get_tree().quit(1)
