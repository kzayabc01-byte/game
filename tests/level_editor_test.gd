extends Node

## 关卡编辑器 API 测试（验证门 2）：headless 实例化编辑器场景，
## 验证六步挂载中和、生成/命名、电线连线序列化、撤销复原、删除/复制。
## 跑法：godot --headless --path . res://tests/level_editor_test.tscn

const WALL_SCENE := "res://blocks/wall/wall.tscn"
const SWITCH_SCENE := "res://blocks/trigger_switch/trigger_switch.tscn"
const MIRROR_SCENE := "res://blocks/mirror/mirror.tscn"
const REFRACT_SCENE := "res://blocks/refract_surface/refract_surface.tscn"
const LIGHT_SOURCE_SCENE := "res://blocks/light_source/light_source.tscn"
const STONE_SCENE := "res://blocks/stone_block/stone_block.tscn"

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
	var toolbar := _editor.get_node("UI").get_child(0) as PanelContainer
	var toolbar_rows := toolbar.get_child(0) as VBoxContainer
	var top_row := toolbar_rows.get_child(0) as HBoxContainer
	var coverage_row := toolbar_rows.get_child(1) as HBoxContainer
	_check("两行工具栏在关卡视口宽度内",
			top_row.get_combined_minimum_size().x <= _editor.get_viewport_rect().size.x
			and coverage_row.get_combined_minimum_size().x <= _editor.get_viewport_rect().size.x)

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
	_check("光源正右显示 0°", light_source.get_angle_label_text() == "0°")
	light_source.rotation = PI * 0.5
	_check("光源正下显示 90°", light_source.get_angle_label_text() == "90°")
	light_source.rotation = PI
	_check("光源正左显示 180°", light_source.get_angle_label_text() == "180°")
	light_source.rotation = -PI * 0.5
	_check("光源正上显示 270°", light_source.get_angle_label_text() == "270°")
	light_source.rotation = source_rotation_before
	var turn_source_button := _find_base_button(_editor, "右转")
	_check("光源检查器提供快捷旋转", turn_source_button != null)
	if turn_source_button != null:
		turn_source_button.pressed.emit()
	_check("快捷旋转光源会立即改变方向",
			light_source.rotation > source_rotation_before
			and light_source.get_light_direction().y > 0.0
			and light_source.get_angle_label_text() == "5°")
	var source_rotation_spin := _editor.get("_spin_rotation") as SpinBox
	_check("光源面板与旁边的小字使用同一角度",
			source_rotation_spin != null and is_equal_approx(source_rotation_spin.value, 5.0))

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
	_editor.set_wire_property(0, &"move_speed", 10000.0)
	_editor.set_wire_property(0, &"rotate_speed", 10000.0)
	var validation_text := _editor.serialize()
	var validation_toggle := _find_base_button(_editor, "实时验证")
	var coverage_toggle := _find_base_button(_editor, "全光线覆盖")
	var light_range_button := _find_base_button(_editor, "有光 0°→360°")
	_check("工具栏提供实时验证", validation_toggle != null)
	_check("全光线覆盖只在测试模式可开启",
			coverage_toggle != null and coverage_toggle.disabled)
	if light_range_button != null:
		light_range_button.pressed.emit()
		var light_start_spin := _editor.get("_coverage_start_spin") as SpinBox
		var light_end_spin := _editor.get("_coverage_end_spin") as SpinBox
		var light_dialog := _editor.get("_coverage_dialog") as ConfirmationDialog
		light_start_spin.value = 330.0
		light_end_spin.value = 30.0
		light_dialog.confirmed.emit()
		light_dialog.hide()
	_check("测试前可设置有光角度",
			light_range_button != null
			and light_range_button.text == "有光 330°→30°")
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
	if coverage_toggle != null:
		coverage_toggle.set_pressed_no_signal(true)
		coverage_toggle.toggled.emit(true)
	var light_system := root.get_node("LightSystem") as LightSystem
	var lit_directions := light_system.get_emission_directions(Vector2.RIGHT)
	_check("实时验证只在跨 0° 的有光区域发射光线",
			coverage_toggle != null and not coverage_toggle.disabled
			and light_system.full_coverage_enabled
			and lit_directions.size() == 30
			and lit_directions[0].is_equal_approx(
				Vector2.RIGHT.rotated(deg_to_rad(330.0)))
			and lit_directions[29].is_equal_approx(
				Vector2.RIGHT.rotated(deg_to_rad(28.0))))
	_check("有光区域固定以正右为 0°，不随光源旋转",
			light_system.get_emission_directions(Vector2.DOWN)[0].is_equal_approx(
				Vector2.RIGHT.rotated(deg_to_rad(330.0))))
	_check("覆盖开启后不能改有光区域",
			not _editor.set_full_coverage_light_range(0.0, 90.0))
	for _frame in range(2):
		await get_tree().physics_frame
	var runtime_renderer := light_system.get_node("RayRenderer") as LightRayRenderer
	var runtime_segments: Array = runtime_renderer.get("_segment_sets")
	_check("有光区域光线实际参与物理光路绘制", runtime_segments.size() >= 30)
	if validation_toggle != null:
		validation_toggle.set_pressed_no_signal(false)
		validation_toggle.toggled.emit(false)
	_check("结束实时验证会回到编辑模式", not _editor.is_validation_mode())
	root = _editor.get_level_root()
	_check("结束验证自动关闭全光线覆盖",
			coverage_toggle != null and coverage_toggle.disabled
			and not coverage_toggle.button_pressed
			and not (root.get_node("LightSystem") as LightSystem).full_coverage_enabled)
	trigger = root.get_node("Blocks/TriggerSwitch") as Node2D
	mirror = root.get_node("Blocks/Mirror") as Node2D
	link = root.get_node_or_null("Blocks/Wire") as ActionLink
	light_source = root.get_node_or_null("Blocks/LightSource") as LightSource
	var validation_text_after := _editor.serialize()
	_check("结束实时验证恢复设计快照",
			_normalize_root_name(validation_text_after) == _normalize_root_name(validation_text)
			and mirror.position == Vector2(416, 300))

	# 试玩留在编辑器内：运行中能改已有块和电线，结束只保留主动编辑。
	var play_button := _find_base_button(_editor, "试玩")
	_check("工具栏提供可编辑试玩", play_button != null)
	var source_angle_before := light_source.rotation
	var wire_duration_before := link.duration
	if play_button != null:
		play_button.pressed.emit()
	_check("试玩启动后关卡运行且编辑器仍在场",
			_editor.is_playtest_mode()
			and root.process_mode == Node.PROCESS_MODE_INHERIT
			and play_button != null and play_button.text == "结束试玩")
	if coverage_toggle != null:
		coverage_toggle.set_pressed_no_signal(true)
		coverage_toggle.toggled.emit(true)
	light_system = root.get_node("LightSystem") as LightSystem
	_check("试玩也可开启全光线覆盖",
			light_system.full_coverage_enabled
			and light_system.get_emission_directions(Vector2.RIGHT).size() == 30)
	if coverage_toggle != null:
		coverage_toggle.set_pressed_no_signal(false)
		coverage_toggle.toggled.emit(false)
	(trigger as TriggerSwitch).apply_lit(true)
	for _frame in range(30):
		if mirror.position.distance_to(Vector2(480, 252)) < 1.0:
			break
		await get_tree().physics_frame
	_check("试玩期间电线机关仍会运行",
			mirror.position.distance_to(Vector2(480, 252)) < 1.0)
	_editor.call("_press_world", light_source.global_position)
	_check("试玩中点击光源可进入拖动瞄准",
			_editor.get("_playtest_aim_source") == light_source)
	_editor.call("_aim_playtest_source_at", light_source.global_position + Vector2.DOWN * 100.0)
	_check("试玩拖动瞄准会实时转动光源",
			light_source.get_light_direction().is_equal_approx(Vector2.DOWN)
			and light_source.get_angle_label_text() == "90°")
	var aiming_spin := _editor.get("_spin_rotation") as SpinBox
	_check("试玩瞄准时检查器角度同步更新",
			aiming_spin != null and is_equal_approx(aiming_spin.value, 90.0))
	_editor.call("_release_world", light_source.global_position)
	_editor.select(light_source)
	var playtest_rotation_spin := _editor.get("_spin_rotation") as SpinBox
	if playtest_rotation_spin != null:
		playtest_rotation_spin.value = rad_to_deg(source_angle_before) + 21.0
	_check("试玩中检查器可立即旋转已有光源",
			absf(light_source.rotation - source_angle_before - deg_to_rad(21.0)) < 0.01)
	_editor.set_wire_property(0, &"duration", 0.25)
	_check("试玩中可修改已有电线", is_equal_approx(link.duration, 0.25))
	_check("试玩中禁止增删关卡结构",
			_editor.spawn_block(WALL_SCENE, Vector2(32, 32)) == null
			and not _editor.connect_wire(trigger, light_source))
	if play_button != null:
		play_button.pressed.emit()
	_check("结束试玩回到编辑状态", not _editor.is_playtest_mode())
	root = _editor.get_level_root()
	mirror = root.get_node("Blocks/Mirror") as Node2D
	link = root.get_node_or_null("Blocks/Wire") as ActionLink
	light_source = root.get_node_or_null("Blocks/LightSource") as LightSource
	_check("试玩只保留设计改动，不保留机关临时位移",
			absf(light_source.rotation - source_angle_before - deg_to_rad(21.0)) < 0.01
			and is_equal_approx(link.duration, 0.25)
			and mirror.position == Vector2(416, 300))
	_check("试玩改动可整体撤销", _editor.undo())
	root = _editor.get_level_root()
	mirror = root.get_node("Blocks/Mirror") as Node2D
	link = root.get_node_or_null("Blocks/Wire") as ActionLink
	light_source = root.get_node_or_null("Blocks/LightSource") as LightSource
	_check("撤销试玩恢复原有设计",
			is_equal_approx(light_source.rotation, source_angle_before)
			and is_equal_approx(link.duration, wire_duration_before)
			and mirror.position == Vector2(416, 300))
	var stone := _editor.spawn_block(STONE_SCENE, Vector2(900, 100)) as StoneBlock
	_check("试玩重力测试石块已生成", stone != null)
	_editor.set_playtest_mode(true)
	for _frame in range(12):
		await get_tree().physics_frame
	_check("试玩中的石块会受重力下落", stone.position.y > 100.0)
	_editor.select(stone)
	var stone_x_spin := _editor.get("_spin_x") as SpinBox
	if stone_x_spin != null:
		stone_x_spin.value = 920.0
	_editor.set_playtest_mode(false)
	root = _editor.get_level_root()
	stone = root.get_node_or_null("Blocks/StoneBlock") as StoneBlock
	_check("只改石块 X 不会保存重力造成的 Y 偏移",
			stone != null and stone.position == Vector2(920, 100))
	_editor.select(stone)
	_editor.delete_selected()
	root = _editor.get_level_root()
	light_source = root.get_node_or_null("Blocks/LightSource") as LightSource

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
	var settings_button := _find_base_button(_editor, "关卡玩法设置")
	_check("编辑器提供两类关卡设置入口", settings_button != null)
	if settings_button != null:
		settings_button.pressed.emit()
		var kind_option := _editor.get("_level_kind_option") as OptionButton
		var inventory_spins: Dictionary = _editor.get("_build_inventory_spins")
		var wire_spin := _editor.get("_build_wire_spin") as SpinBox
		var settings_dialog := _editor.get("_level_settings_dialog") as ConfirmationDialog
		kind_option.select(LevelManager.LevelKind.BUILD)
		(inventory_spins["mirror"] as SpinBox).value = 2.0
		wire_spin.value = 1.0
		settings_dialog.confirmed.emit()
		settings_dialog.hide()
	var saved_manager := root.get_node("LevelManager") as LevelManager
	_check("编辑器可配置搭建元件数量与玩家电线数量",
		saved_manager.level_kind == LevelManager.LevelKind.BUILD
		and saved_manager.build_item_keys.has("mirror")
		and saved_manager.build_wire_limit == 1)
	_editor.select(plain_refract)
	var player_target_check := _find_base_button(_editor, "允许玩家给此预置机关接线")
	_check("可单独开放预置机关的玩家接线权限", player_target_check != null)
	if player_target_check != null:
		player_target_check.set_pressed_no_signal(true)
		player_target_check.toggled.emit(true)
	_check("预置机关权限写入关卡配置",
		saved_manager.build_wire_targets.has("RefractSurface")
		and _editor.serialize().contains("build_wire_targets"))
	_editor.select(trigger)
	var player_source_check := _find_base_button(_editor, "允许玩家从此预置开关接线")
	_check("可单独开放预置开关的接线权限", player_source_check != null)
	if player_source_check != null:
		player_source_check.set_pressed_no_signal(true)
		player_source_check.toggled.emit(true)
	_check("预置开关权限写入关卡配置",
		saved_manager.build_wire_sources.has("TriggerSwitch")
		and _editor.serialize().contains("build_wire_sources"))

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
