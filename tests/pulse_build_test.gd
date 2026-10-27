extends Node2D

var _failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run_test()


func _run_test() -> void:
	var original_save_path := ProgressStore.save_path
	ProgressStore.save_path = "user://pulse_build_progress_test.json"
	var fixture := FileAccess.open(ProgressStore.save_path, FileAccess.WRITE)
	if fixture != null:
		fixture.store_string("{\"coins\":0,\"hint_level\":0}")
		fixture.close()
	ProgressStore.award_clear()
	ProgressStore.award_clear()
	_check("正式关卡每次完成获得 50 金币", ProgressStore.get_coins() == 100)
	_check("花 100 金币升级虚线 120 单位", ProgressStore.buy_hint_upgrade()
		and ProgressStore.get_coins() == 0
		and is_equal_approx(ProgressStore.get_hint_length(), 360.0))
	ProgressStore.save_path = original_save_path
	var level := (load("res://scenes/levels/level_base.tscn") as PackedScene).instantiate()
	var manager := level.get_node("LevelManager") as LevelManager
	manager.level_kind = LevelManager.LevelKind.BUILD
	manager.build_item_keys = PackedStringArray(["mirror"])
	manager.build_item_counts = PackedInt32Array([1])
	manager.build_wire_limit = 1
	manager.build_wire_targets = PackedStringArray(["FixedMirror"])
	manager.build_wire_sources = PackedStringArray(["Switch"])
	var blocks := level.get_node("Blocks") as Node2D
	var source := _add_block(blocks, "res://blocks/light_source/light_source.tscn",
		"Source", Vector2(100.0, 300.0)) as LightSource
	var trigger := _add_block(blocks, "res://blocks/trigger_switch/trigger_switch.tscn",
		"Switch", Vector2(250.0, 300.0)) as TriggerSwitch
	var mirror := _add_block(blocks, "res://blocks/mirror/mirror.tscn",
		"FixedMirror", Vector2(500.0, 300.0))
	_add_block(blocks, "res://blocks/cocoon/cocoon.tscn",
		"Goal", Vector2(700.0, 500.0))
	add_child(level)
	await get_tree().process_frame
	var builder := manager.get_node_or_null("PlayerBuilder") as PlayerBuilder
	var light := level.get_node("LightSystem") as LightSystem
	_check("限定搭建关进入搭建状态", builder != null
		and level.process_mode == Node.PROCESS_MODE_DISABLED)
	var build_panel := builder.get_child(0) as PanelContainer if builder != null else null
	_check("玩家工具箱只占紧凑区域",
		build_panel != null and build_panel.size.y < 340.0)
	_check("预置光源默认锁定方向", not source.follow_mouse)
	if builder == null:
		_finish()
		return
	var inventory_buttons: Array[String] = []
	for child in builder._inventory_box.get_children():
		if child is Button:
			inventory_buttons.append((child as Button).text)
	_check("左侧只列出本关允许摆放的元件", inventory_buttons == ["镜面 × 1"])
	builder._select(source)
	_check("预置元件不显示变换手柄，左栏仅保留回收和开始",
		builder._gizmo.get_target() == null
		and builder._recycle_button.disabled
		and builder._test_button.text == "开始试射")
	var authored_text := LevelFileIO.serialize_level(level)
	var save_path := "user://pulse_build_roundtrip.tscn"
	var saved := LevelFileIO.write_text(save_path, authored_text) == OK
	var packed := ResourceLoader.load(save_path, "PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE) as PackedScene if saved else null
	var restored := packed.instantiate() if packed != null else null
	var restored_manager := restored.get_node_or_null("LevelManager") as LevelManager if restored != null else null
	_check("搭建库存、接线权限和摆放区域可保存并重新加载",
		restored_manager != null
		and restored_manager.level_kind == LevelManager.LevelKind.BUILD
		and restored_manager.build_item_counts == PackedInt32Array([1])
		and restored_manager.build_wire_targets.has("FixedMirror")
		and restored_manager.build_wire_sources.has("Switch")
		and restored_manager.build_bounds == manager.build_bounds)
	if restored != null:
		restored.free()
	builder._select(mirror)
	builder._rotate_selected(15.0)
	_check("设计者预置元件不能由玩家旋转", is_zero_approx(mirror.rotation))
	builder._place_item("mirror", Vector2(350.0, 450.0))
	_check("玩家能放置限定数量的元件", builder._placed.size() == 1
		and int(builder._remaining["mirror"]) == 0)
	builder._select(builder._placed[0])
	_check("玩家元件通过场景手柄移动、缩放、旋转",
		builder._can_drag_selection()
		and builder._gizmo.get_target() == builder._placed[0])
	var placed_mirror := builder._placed[0]
	var scale_anchor := placed_mirror.global_position + Vector2(32.0, 12.0)
	builder._gizmo.begin_drag(SelectionGizmo.DragMode.SCALE_BR, scale_anchor)
	builder._gizmo.update_drag(scale_anchor + Vector2(16.0, 6.0))
	builder._gizmo.end_drag()
	_check("拖动角点实际改变元件尺寸", placed_mirror.scale.x > 1.1)
	var rotation_anchor := placed_mirror.global_position + Vector2.UP * 50.0
	builder._gizmo.begin_drag(SelectionGizmo.DragMode.ROTATE, rotation_anchor)
	builder._gizmo.update_drag(placed_mirror.global_position + Vector2.RIGHT * 50.0)
	builder._gizmo.end_drag()
	_check("拖动旋转钮实际改变角度", absf(placed_mirror.rotation) > 0.1)
	builder._set_view_zoom(1.4)
	_check("搭建画布可直接缩放", is_equal_approx(
		(level.get_node("Camera2D") as Camera2D).zoom.x, 1.4))
	var placed_stone := (load("res://blocks/stone_block/stone_block.tscn") as PackedScene).instantiate() as StoneBlock
	blocks.add_child(placed_stone)
	builder._placed.append(placed_stone)
	builder._select(placed_stone)
	_check("搭建关石块不能用鼠标拖动", not builder._can_drag_selection())
	builder._select(trigger)
	builder._placed.erase(placed_stone)
	placed_stone.free()
	_check("完整搭建配置通过检查", LevelValidator.validate_build(manager, blocks).is_empty())
	manager.build_wire_sources = []
	builder._refresh_ui()
	_check("未开放开关时明确显示原因且不允许接线", builder._connect_button.disabled
		and builder._source_hint.text.contains("未开放"))
	builder._try_connect(trigger, mirror)
	_check("绕过按钮也无法接未开放开关", builder._links.is_empty())
	_check("发布检查能发现有电线却无可用开关",
		not LevelValidator.validate_build(manager, blocks).is_empty())
	manager.build_wire_sources = PackedStringArray(["Switch"])
	manager.build_wire_targets = PackedStringArray(["MissingTarget"])
	_check("发布检查能发现已删除的接线目标",
		not LevelValidator.validate_build(manager, blocks).is_empty())
	manager.build_wire_targets = PackedStringArray(["FixedMirror"])
	builder._set_view_zoom(1.0)
	var camera: Camera2D = level.get_node("Camera2D") as Camera2D
	camera.position = Vector2(576, 324)
	camera.force_update_scroll()
	builder._refresh_ui()
	_check("选中开关直接出现接线入口", builder._source_controls.visible
		and not builder._connect_button.disabled)
	# 经 Viewport 的真实输入分发，覆盖端口命中、松开接线和 GUI 拦截。
	_mouse_button(WireLayer.port_position(trigger, true), true)
	_mouse_button(mirror.global_position, false)
	await get_tree().process_frame
	_check("拖动端口到目标经过输入系统完成接线", builder._links.size() == 1)
	builder._remove_selected_wire()
	await get_tree().process_frame
	_check("拆线不会残留信号连接", builder._links.is_empty()
		and trigger.active_changed.get_connections().is_empty())
	builder._select(trigger)
	builder._connect_button.pressed.emit()
	_mouse_button(mirror.global_position, true)
	_mouse_button(mirror.global_position, false)
	await get_tree().process_frame
	_check("接线按钮加点击目标也能完成接线", builder._links.size() == 1)
	builder._try_connect(trigger, placed_mirror)
	_check("达到电线上限时不能通过第二个入口超额连接", builder._links.size() == 1)
	_check("已开放的预置目标可以接玩家电线", builder._links.size() == 1)
	_check("电线参数只在右侧上下文面板显示", builder._wire_panel.visible
		and builder._wire_panel.position.x > 600.0)
	if builder._links.is_empty():
		_finish()
		return
	var link := builder._links[0] as ActionLink
	_check("选中电线目标时显示机关运动终点", builder._wire_overlay.has_action_hint()
		and builder._wire_overlay.get_action_hint_endpoint().is_equal_approx(
			mirror.global_position))
	var speed_controls_match: bool = true
	for row in builder._wire_controls.get_children():
		for control in row.get_children():
			if control is SpinBox and control.has_meta("wire_property"):
				var property: StringName = StringName(control.get_meta("wire_property"))
				speed_controls_match = speed_controls_match and is_equal_approx(
					(control as SpinBox).value, float(link.get(property)))
	_check("电线输入框与真实参数一致（120/90 不显示成 121/91）", speed_controls_match)
	link.move_offset = Vector2(120.0, 0.0)
	link.repeat = true
	_check("终点提示跟随电线位移参数", builder._wire_overlay.get_action_hint_endpoint().is_equal_approx(
		mirror.global_position + Vector2(120.0, 0.0)))
	builder._begin_destination()
	builder._wire_overlay.set_action_hint(link, true, Vector2(680.0, 360.0))
	_check("设置终点时显示鼠标候选位置", builder._wire_overlay.get_action_hint_endpoint().is_equal_approx(
		Vector2(680.0, 360.0)))
	builder._cancel_tool()
	var pause_key: InputEventKey = InputEventKey.new()
	pause_key.keycode = KEY_ESCAPE
	pause_key.pressed = true
	get_viewport().push_input(pause_key, true)
	_check("搭建时 Esc 打开暂停而不是退出", get_tree().paused and manager._pause_menu.visible)
	manager._on_resume_pressed()
	builder._start_test()
	_check("试射开始后场景恢复运行", builder.is_testing()
		and level.process_mode == Node.PROCESS_MODE_INHERIT
		and not builder._wire_overlay.visible
		and not builder._wire_overlay.has_action_hint())
	await get_tree().process_frame
	_check("开始试射后光源随鼠标瞄准", source.follow_mouse
		and not is_zero_approx(source.rotation))
	# 固定这一帧的鼠标瞄准结果，让渲染器在后续物理帧同步；不比较不同时钟的状态。
	source.set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var preview := light._renderer as LightRayRenderer
	var preview_path: PackedVector2Array = preview._segment_sets[0] \
		if not preview._segment_sets.is_empty() else PackedVector2Array()
	_check("试射虚线按光源瞄准方向实时绘制", preview.preview_mode
		and preview_path.size() >= 2
		and (preview_path[1] - preview_path[0]).normalized().dot(
			source.get_light_direction()) > 0.98)
	source.follow_mouse = false
	source.rotation = 0.0
	_check("点击发射前开关和机关保持静止", not trigger.is_active()
		and mirror.position.is_equal_approx(Vector2(500.0, 300.0)))
	_check("光线请求成功", light.request_fire())
	for _frame in 30:
		if get_tree().paused:
			break
		await get_tree().physics_frame
	_check("光线演出时冻结场景，机关未开始移动", get_tree().paused
		and not trigger.is_active() and mirror.position.is_equal_approx(Vector2(500.0, 300.0)))
	await light.pulse_finished
	_check("光线结束才触发开关", not get_tree().paused and trigger.is_active())
	await get_tree().create_timer(0.8, true).timeout
	_check("机关按设定速度向终点移动", mirror.position.x > 550.0)
	await get_tree().create_timer(1.2, true).timeout
	_check("触发后持续往返", mirror.position.x < 590.0 and link.is_active())
	builder._return_to_build()
	_check("返回搭建恢复机关，保留玩家元件和电线",
		level.process_mode == Node.PROCESS_MODE_DISABLED
		and mirror.position.is_equal_approx(Vector2(500.0, 300.0))
		and builder._placed.size() == 1 and builder._links.size() == 1
		and builder._wire_overlay.visible and builder._wire_overlay.has_action_hint())
	var serialized := LevelFileIO.serialize_level(level)
	_check("关卡类型和工具箱写入关卡文件",
		serialized.contains("level_kind = 1")
		and serialized.contains("build_item_keys")
		and serialized.contains("build_item_counts"))
	var ghost := builder._ghost as Polygon2D
	var bounds_outline := builder._bounds_outline as Line2D
	builder.free()
	_check("编辑器清理试玩界面时不遗留摆放辅助图形",
		not is_instance_valid(ghost) and not is_instance_valid(bounds_outline))
	_finish()


func _mouse_button(world_point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = get_viewport().get_canvas_transform() * world_point
	event.global_position = event.position
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _add_block(parent: Node2D, path: String, name: String, position: Vector2) -> Node2D:
	var block := (load(path) as PackedScene).instantiate() as Node2D
	block.name = name
	block.position = position
	parent.add_child(block)
	return block


func _check(label: String, ok: bool) -> void:
	print("TEST: %s: %s" % [label, "PASS" if ok else "FAIL"])
	if not ok:
		_failed = true


func _finish() -> void:
	print("TEST RESULT: %s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)
