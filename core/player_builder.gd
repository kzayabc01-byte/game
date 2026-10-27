class_name PlayerBuilder
extends CanvasLayer

## Player-facing construction controls for a limited-build level.

const MIN_VIEW_ZOOM := 0.5
const MAX_VIEW_ZOOM := 2.5
const VIEW_ZOOM_STEP := 1.15

var _manager: LevelManager
var _level_root: Node2D
var _blocks: Node2D
var _camera: Camera2D
var _camera_initial_position := Vector2.ZERO
var _camera_initial_zoom := Vector2.ONE
var _camera_previous_process_mode: ProcessMode = Node.PROCESS_MODE_INHERIT
var _remaining: Dictionary = {}
var _placed: Array[Node2D] = []
var _links: Array[ActionLink] = []
var _wire_lines: Dictionary = {}
var _selection: Node2D = null
var _selected_link: ActionLink = null
var _placing_key := ""
var _wiring_source: Node2D = null
var _wire_dragging := false
var _setting_destination := false
var _view_panning := false
var _pan_button: MouseButton = MOUSE_BUTTON_NONE
var _transform_before: Dictionary = {}
var _source_rotations: Dictionary = {}
var _source_aim_before_test: Dictionary = {}
var _testing := false
var _inventory_box: VBoxContainer
var _status_label: Label
var _recycle_button: Button
var _wire_panel: PanelContainer
var _source_controls: VBoxContainer
var _connect_button: Button
var _source_hint: Label
var _wire_overlay: WireLayer
var _configuration_errors: PackedStringArray = []
var _wire_controls: VBoxContainer
var _test_button: Button
var _ghost: Polygon2D
var _bounds_outline: Line2D
var _wire_preview: Line2D
var _gizmo: SelectionGizmo


func configure(manager: LevelManager, level_root: Node2D) -> void:
	_manager = manager
	_level_root = level_root
	_blocks = _level_root.get_node("Blocks") as Node2D
	_camera = _level_root.get_node("Camera2D") as Camera2D
	_camera_initial_position = _camera.position
	_camera_initial_zoom = _camera.zoom
	_camera_previous_process_mode = _camera.process_mode
	_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	for index in manager.build_item_keys.size():
		if index < manager.build_item_counts.size():
			var count := maxi(manager.build_item_counts[index], 0)
			if count > 0:
				_remaining[manager.build_item_keys[index]] = count
	for child in _blocks.get_children():
		if child is StoneBlock:
			(child as StoneBlock).player_draggable = false
		elif child is LightSource:
			(child as LightSource).follow_mouse = manager.build_aimable_sources.has(
				str(_blocks.get_path_to(child)))
	_configuration_errors = LevelValidator.validate_build(manager, _blocks)
	_build_ui()
	_wire_overlay = WireLayer.new()
	_wire_overlay.name = "PlayerWirePorts"
	_wire_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_blocks.add_child(_wire_overlay)
	_wire_overlay.top_level = true
	_ghost = Polygon2D.new()
	_ghost.color = Color(0.35, 0.85, 1.0, 0.24)
	_ghost.visible = false
	_blocks.add_child(_ghost)
	_bounds_outline = Line2D.new()
	_bounds_outline.width = 2.0
	_bounds_outline.default_color = Color(0.35, 0.85, 1.0, 0.55)
	var bounds := manager.build_bounds
	_bounds_outline.points = PackedVector2Array([
		bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y), bounds.position,
	])
	_blocks.add_child(_bounds_outline)
	_wire_preview = Line2D.new()
	_wire_preview.width = 2.0
	_wire_preview.default_color = Color(1.0, 0.72, 0.25, 0.8)
	_wire_preview.visible = false
	_blocks.add_child(_wire_preview)
	_gizmo = SelectionGizmo.new()
	_gizmo.grid_snap_enabled = false
	_gizmo.z_index = 20
	_gizmo.transform_started.connect(_on_transform_started)
	_gizmo.transform_committed.connect(_on_transform_committed)
	_blocks.add_child(_gizmo)
	_level_root.process_mode = Node.PROCESS_MODE_DISABLED
	_refresh_ui()


func _exit_tree() -> void:
	if is_instance_valid(_wire_overlay):
		_wire_overlay.free()
	if is_instance_valid(_ghost):
		_ghost.free()
	if is_instance_valid(_bounds_outline):
		_bounds_outline.free()
	if is_instance_valid(_wire_preview):
		_wire_preview.free()
	if is_instance_valid(_gizmo):
		_gizmo.free()
	if is_instance_valid(_camera):
		_camera.position = _camera_initial_position
		_camera.zoom = _camera_initial_zoom
		_camera.process_mode = _camera_previous_process_mode
	for line in _wire_lines.values():
		if is_instance_valid(line):
			(line as Node).free()


func is_testing() -> bool:
	return _testing


func cancel_active_tool() -> bool:
	if _placing_key.is_empty() and _wiring_source == null and not _setting_destination:
		return false
	_cancel_tool()
	return true


func _process(_delta: float) -> void:
	if _ghost != null and _ghost.visible:
		_ghost.global_position = _level_root.get_global_mouse_position()
	if _wire_preview != null and _wire_preview.visible and is_instance_valid(_wiring_source):
		_wire_preview.points = PackedVector2Array([
			_wiring_source.position, _blocks.get_local_mouse_position(),
		])
	for link in _links:
		if not is_instance_valid(link) or not _wire_lines.has(link):
			continue
		var line := _wire_lines[link] as Line2D
		var source := _source_for_link(link)
		var target := link.get_target()
		if line != null and source != null and target != null:
			line.points = PackedVector2Array([source.position, target.position])
	_sync_action_destination_hint()


func _unhandled_input(event: InputEvent) -> void:
	if _testing or get_tree().paused or SceneTransition.is_transitioning():
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_ESCAPE:
				_cancel_tool()
				get_viewport().set_input_as_handled()
				return
			KEY_Q, KEY_E:
				if (not key.ctrl_pressed and not key.alt_pressed and _can_drag_selection()
					and get_viewport().gui_get_focus_owner() == null):
					var direction := -1.0 if key.keycode == KEY_Q else 1.0
					_rotate_selected(direction * (1.0 if key.shift_pressed else 15.0))
					get_viewport().set_input_as_handled()
					return
			KEY_HOME:
				_camera.position = _camera_initial_position
				_camera.zoom = Vector2.ONE
				_camera.force_update_scroll()
				get_viewport().set_input_as_handled()
				return
			KEY_DELETE:
				if _placed.has(_selection):
					_recycle_selected()
					get_viewport().set_input_as_handled()
					return
	var motion := event as InputEventMouseMotion
	if motion != null and _view_panning:
		if not Input.is_mouse_button_pressed(_pan_button):
			_view_panning = false
			_pan_button = MOUSE_BUTTON_NONE
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			return
		_camera.position -= motion.relative / _camera.zoom
		_camera.force_update_scroll()
		get_viewport().set_input_as_handled()
		return
	if motion != null and _gizmo.is_dragging():
		_gizmo.update_drag(_world_position(motion.position))
		get_viewport().set_input_as_handled()
		return
	if _handle_view_input(event):
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if not button.pressed:
		if _wire_dragging:
			_wire_dragging = false
			var source := _wiring_source
			_wiring_source = null
			_wire_preview.hide()
			_refresh_ui()
			_try_connect(source, _block_at(_world_position(button.position)))
		elif _gizmo.is_dragging():
			_gizmo.end_drag()
		get_viewport().set_input_as_handled()
		return
	var world_point: Vector2 = _world_position(button.position)
	if (
		is_instance_valid(_selection) and not WireService.source_signal(_selection).is_empty()
		and world_point.distance_to(WireLayer.port_position(_selection, true)) <= 12.0
		and _placing_key.is_empty() and not _setting_destination
	):
		_begin_wire()
		_wire_dragging = is_instance_valid(_wiring_source)
		_wire_preview.visible = _wire_dragging
		get_viewport().set_input_as_handled()
		return
	if button.shift_pressed and _manager.build_wire_limit > 0:
		_select(_block_at(world_point))
		_begin_wire()
		if _wiring_source != null:
			_wire_dragging = true
			_wire_preview.show()
		get_viewport().set_input_as_handled()
		return
	if _setting_destination and is_instance_valid(_selected_link):
		var target := _selected_link.get_target()
		if target != null and _manager.build_bounds.has_point(world_point):
			var parent := target.get_parent() as Node2D
			var local_destination := parent.to_local(world_point) if parent != null else world_point
			_selected_link.move_offset = local_destination - target.position
			_setting_destination = false
			_refresh_ui()
		get_viewport().set_input_as_handled()
		return
	if _wiring_source != null:
		var source: Node2D = _wiring_source
		_wiring_source = null
		_refresh_ui()
		_try_connect(source, _block_at(world_point))
		get_viewport().set_input_as_handled()
		return
	if not _placing_key.is_empty():
		_place_item(_placing_key, world_point)
		get_viewport().set_input_as_handled()
		return
	var hit_mode := _gizmo.hit_test(world_point)
	if hit_mode != SelectionGizmo.DragMode.NONE:
		_gizmo.begin_drag(hit_mode, world_point)
		get_viewport().set_input_as_handled()
		return
	_select(_block_at(world_point))
	if _can_drag_selection():
		_gizmo.begin_drag(SelectionGizmo.DragMode.MOVE, world_point)
	get_viewport().set_input_as_handled()


func _handle_view_input(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button == null:
		return false
	if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
		if _gizmo.is_dragging() or _wire_dragging:
			return false
		_set_view_zoom(_camera.zoom.x * VIEW_ZOOM_STEP)
		return true
	if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if _gizmo.is_dragging() or _wire_dragging:
			return false
		_set_view_zoom(_camera.zoom.x / VIEW_ZOOM_STEP)
		return true
	if button.button_index != MOUSE_BUTTON_MIDDLE and button.button_index != MOUSE_BUTTON_RIGHT:
		return false
	if button.pressed and not _gizmo.is_dragging() and not _wire_dragging:
		_view_panning = true
		_pan_button = button.button_index
		Input.set_default_cursor_shape(Input.CURSOR_DRAG)
		return true
	if not button.pressed and _view_panning and button.button_index == _pan_button:
		_view_panning = false
		_pan_button = MOUSE_BUTTON_NONE
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return true
	return false


func _set_view_zoom(value: float) -> void:
	var target := clampf(value, MIN_VIEW_ZOOM, MAX_VIEW_ZOOM)
	if is_equal_approx(target, _camera.zoom.x):
		return
	var before := _level_root.get_global_mouse_position()
	_camera.zoom = Vector2.ONE * target
	_camera.force_update_scroll()
	var after := _level_root.get_global_mouse_position()
	_camera.position += before - after
	_camera.force_update_scroll()


func _on_transform_started() -> void:
	if not _can_drag_selection():
		return
	_transform_before = {
		"position": _selection.position,
		"scale": _selection.scale,
		"rotation": _selection.rotation,
	}


func _on_transform_committed() -> void:
	if not _can_drag_selection():
		return
	if not _can_place(_selection, _selection.global_position):
		_selection.position = _transform_before.get("position", _selection.position)
		_selection.scale = _transform_before.get("scale", _selection.scale)
		_selection.rotation = _transform_before.get("rotation", _selection.rotation)
		_status_label.text = "这里不能放置元件。"
	_sync_placed_origin(_selection)
	_gizmo.queue_redraw()


func _can_drag_selection() -> bool:
	return (
		is_instance_valid(_selection)
		and _placed.has(_selection)
		and not (_selection is StoneBlock)
	)


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 96.0)
	panel.custom_minimum_size = Vector2(224.0, 0.0)
	_style_panel(panel)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(224.0, minf(132.0 + _remaining.size() * 42.0, 500.0))
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(208.0, 0.0)
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "可放置元件"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.0))
	box.add_child(title)
	_inventory_box = VBoxContainer.new()
	box.add_child(_inventory_box)
	_recycle_button = _make_button("回收", _recycle_selected)
	box.add_child(_recycle_button)
	_test_button = _make_button("开始试射", _toggle_test)
	box.add_child(_test_button)

	_wire_panel = PanelContainer.new()
	_wire_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wire_panel.offset_left = -264.0
	_wire_panel.offset_right = -16.0
	_wire_panel.offset_top = 96.0
	_wire_panel.custom_minimum_size = Vector2(248.0, 0.0)
	_style_panel(_wire_panel)
	_wire_panel.hide()
	add_child(_wire_panel)
	var wire_box := VBoxContainer.new()
	wire_box.add_theme_constant_override("separation", 8)
	_wire_panel.add_child(wire_box)
	var wire_title := Label.new()
	wire_title.text = "接线 / 机关动作"
	wire_title.add_theme_font_size_override("font_size", 18)
	wire_title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.0))
	wire_box.add_child(wire_title)
	_source_controls = VBoxContainer.new()
	wire_box.add_child(_source_controls)
	_source_hint = Label.new()
	_source_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_source_hint.custom_minimum_size.x = 224.0
	_source_controls.add_child(_source_hint)
	_connect_button = _make_button("从这个开关接线", _begin_wire)
	_source_controls.add_child(_connect_button)
	_wire_controls = VBoxContainer.new()
	_wire_controls.add_theme_constant_override("separation", 6)
	wire_box.add_child(_wire_controls)
	_wire_controls.add_child(_make_button("设置机关运动终点", _begin_destination))
	var angle_row := HBoxContainer.new()
	_wire_controls.add_child(angle_row)
	angle_row.add_child(_make_label("旋转角度"))
	var angle_spin := _make_spin(-360.0, 360.0, 0.1)
	angle_spin.value_changed.connect(func(value: float) -> void:
		if is_instance_valid(_selected_link):
			_selected_link.rotate_degrees = value)
	angle_row.add_child(angle_spin)
	angle_spin.set_meta("wire_property", "rotate_degrees")
	var move_row := HBoxContainer.new()
	_wire_controls.add_child(move_row)
	move_row.add_child(_make_label("移动速度"))
	var move_spin := _make_spin(1.0, 2000.0, 1.0)
	move_spin.value_changed.connect(func(value: float) -> void:
		if is_instance_valid(_selected_link):
			_selected_link.move_speed = value)
	move_row.add_child(move_spin)
	move_spin.set_meta("wire_property", "move_speed")
	var rotate_row := HBoxContainer.new()
	_wire_controls.add_child(rotate_row)
	rotate_row.add_child(_make_label("旋转速度"))
	var rotate_spin := _make_spin(1.0, 2000.0, 1.0)
	rotate_spin.value_changed.connect(func(value: float) -> void:
		if is_instance_valid(_selected_link):
			_selected_link.rotate_speed = value)
	rotate_row.add_child(rotate_spin)
	rotate_spin.set_meta("wire_property", "rotate_speed")
	var repeat_check := CheckBox.new()
	repeat_check.text = "触发后一直往返"
	repeat_check.toggled.connect(func(value: bool) -> void:
		if is_instance_valid(_selected_link):
			_selected_link.repeat = value)
	repeat_check.set_meta("wire_property", "repeat")
	_wire_controls.add_child(repeat_check)
	_wire_controls.add_child(_make_button("拆除选中电线", _remove_selected_wire))
	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status_label.offset_left = 16.0
	_status_label.offset_right = 520.0
	_status_label.offset_top = -72.0
	_status_label.offset_bottom = -12.0
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.76))
	add_child(_status_label)


func _style_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.043, 0.047, 0.039, 0.94)
	style.border_color = Color(1.0, 0.72, 0.0)
	style.border_width_top = 1
	style.border_width_left = 1
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)


func _make_button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	return button


func _make_label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.custom_minimum_size.x = 72.0
	return label


func _make_spin(minimum: float, maximum: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.update_on_text_changed = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _refresh_ui() -> void:
	for child in _inventory_box.get_children():
		_inventory_box.remove_child(child)
		child.queue_free()
	for entry in PaletteData.get_entries():
		var key := str(entry["key"])
		if not _remaining.has(key):
			continue
		var label := str(entry["label"])
		if bool(entry.get("spawn_pair", false)):
			label += "（一对）"
		var button := _make_button("%s × %d" % [label, _remaining[key]],
			_select_item.bind(key))
		button.tooltip_text = "点击后在场景中放置；再次点击或按 Esc 取消"
		button.disabled = int(_remaining[key]) <= 0 or _testing
		_inventory_box.add_child(button)
	_recycle_button.disabled = _testing or not _placed.has(_selection)
	var source_selected: bool = not WireService.source_signal(_selection).is_empty()
	_wire_panel.visible = (is_instance_valid(_selected_link) or source_selected) and not _testing
	_source_controls.visible = source_selected
	_wire_controls.visible = is_instance_valid(_selected_link)
	if source_selected:
		var reason: String = _wire_source_error(_selection)
		_source_hint.text = reason if not reason.is_empty() else "可接线 %d / %d · 点击接线后选择目标，或拖动开关右侧端口。" % [
			_manager.build_wire_limit - _links.size(), _manager.build_wire_limit]
		_connect_button.disabled = not reason.is_empty()
	if is_instance_valid(_wire_overlay):
		_wire_overlay.visible = not _testing
		_wire_overlay.set_source_hint(_selection if source_selected and _wire_source_error(_selection).is_empty() else null)
		_sync_action_destination_hint()
	if _wire_panel.visible and is_instance_valid(_selected_link):
		for child in _wire_controls.get_children():
			for control in child.get_children():
				_sync_wire_control(control)
			_sync_wire_control(child)
	_test_button.text = "返回搭建" if _testing else "开始试射"
	if _testing:
		_status_label.text = "移动鼠标瞄准，按空格发射。"
	elif not _placing_key.is_empty():
		_status_label.text = "点击场景放置：%s" % str(
			_entry_for_key(_placing_key).get("label", "元件"))
	else:
		_status_label.text = "拖动手柄旋转或缩放；滚轮缩放视图；选中开关可接线。"
		if not _configuration_errors.is_empty():
			_status_label.text = "关卡配置待完善：" + _configuration_errors[0]
	if _wiring_source != null:
		_status_label.text = "点击允许连接的机关，或拖到目标后松开鼠标。"
	if _setting_destination:
		_status_label.text = "点击场景，指定机关运动终点。"
	if _ghost != null:
		_ghost.visible = not _placing_key.is_empty() and not _testing


func _sync_wire_control(control: Node) -> void:
	if not control.has_meta("wire_property"):
		return
	var value: Variant = _selected_link.get(StringName(control.get_meta("wire_property")))
	if control is SpinBox:
		(control as SpinBox).set_value_no_signal(float(value))
	elif control is CheckBox:
		(control as CheckBox).set_pressed_no_signal(bool(value))


func _select_item(key: String) -> void:
	_placing_key = "" if _placing_key == key else key
	_wiring_source = null
	_setting_destination = false
	if not _placing_key.is_empty():
		var entry := _entry_for_key(_placing_key)
		var size: Vector2 = entry.get("size", Vector2(32.0, 32.0))
		_ghost.polygon = PackedVector2Array([
			-size * 0.5, Vector2(size.x * 0.5, -size.y * 0.5),
			size * 0.5, Vector2(-size.x * 0.5, size.y * 0.5),
		])
	_refresh_ui()


func _cancel_tool() -> void:
	_placing_key = ""
	_wiring_source = null
	_wire_dragging = false
	if _wire_preview != null:
		_wire_preview.hide()
	_setting_destination = false
	_refresh_ui()


func _entry_for_key(key: String) -> Dictionary:
	for entry in PaletteData.get_entries():
		if entry["key"] == key:
			return entry
	return {}


func _place_item(key: String, point: Vector2) -> void:
	if int(_remaining.get(key, 0)) <= 0:
		return
	var entry := _entry_for_key(key)
	if entry.is_empty():
		return
	var size: Vector2 = entry.get("size", Vector2(32.0, 32.0))
	if not _manager.build_bounds.has_point(point):
		_status_label.text = "请放在本关允许的区域内。"
		return
	var offsets: Array[Vector2] = [Vector2.ZERO]
	if bool(entry.get("spawn_pair", false)):
		var half_gap := float(entry.get("pair_gap", 260.0)) * 0.5
		offsets = [Vector2(-half_gap, 0.0), Vector2(half_gap, 0.0)]
	for offset in offsets:
		if not _can_place_size(point + offset, size, null):
			_status_label.text = "这里与已有元件重叠，或超出了摆放区域。"
			return
	var created: Array[Node2D] = []
	for offset in offsets:
		var packed := load(str(entry["path"])) as PackedScene
		if packed == null:
			return
		var block := packed.instantiate() as Node2D
		if block == null:
			return
		block.name = _unique_name(key.to_pascal_case())
		block.position = point + offset
		for prop in entry.get("preset", {}):
			block.set(prop, entry["preset"][prop])
		block.set_meta("player_placed", true)
		block.set_meta("inventory_key", key)
		_blocks.add_child(block)
		if block is StoneBlock:
			(block as StoneBlock).player_draggable = false
		_placed.append(block)
		created.append(block)
	if created.size() == 2 and created[0] is Portal and created[1] is Portal:
		var first := created[0] as Portal
		var second := created[1] as Portal
		first.pair_id = StringName("player_%d" % first.get_instance_id())
		second.pair_id = first.pair_id
		first.linked_portal = second
		second.linked_portal = first
		second.rotation = PI
	_remaining[key] = int(_remaining[key]) - 1
	if int(_remaining[key]) <= 0:
		_placing_key = ""
	_select(created[0])
	_refresh_ui()


func _can_place(node: Node2D, point: Vector2) -> bool:
	var size := PaletteData.entry_size(node.scene_file_path) * node.global_scale.abs()
	return _can_place_size(point, size, node)


func _can_place_size(point: Vector2, size: Vector2, moving: Node2D) -> bool:
	var bounds := _manager.build_bounds
	var candidate := Rect2(point - size * 0.5, size)
	if not bounds.encloses(candidate):
		return false
	for child in _blocks.get_children():
		var other := child as Node2D
		if (
			other == null or other == moving or other is ActionLink
			or other is Line2D or other is Polygon2D or other is SelectionGizmo
		):
			continue
		var other_size := PaletteData.entry_size(other.scene_file_path)
		other_size *= other.global_scale.abs()
		var other_rect := Rect2(other.global_position - other_size * 0.5, other_size)
		if candidate.intersects(other_rect.grow(-3.0)):
			return false
	return true


func _block_at(point: Vector2) -> Node2D:
	var children := _blocks.get_children()
	for index in range(children.size() - 1, -1, -1):
		var block := children[index] as Node2D
		if (
			block == null or block is ActionLink or block is Line2D
			or block is Polygon2D or block is SelectionGizmo
		):
			continue
		var size := PaletteData.entry_size(block.scene_file_path)
		var local := (point - block.global_position).rotated(-block.rotation)
		local.x /= maxf(absf(block.global_scale.x), 0.001)
		local.y /= maxf(absf(block.global_scale.y), 0.001)
		if absf(local.x) <= size.x * 0.5 and absf(local.y) <= size.y * 0.5:
			return block
	return null


func _select(block: Node2D) -> void:
	_selection = block
	_selected_link = _link_for_target(block)
	_gizmo.set_target(block if _can_drag_selection() else null)
	_refresh_ui()


func _rotate_selected(degrees: float) -> void:
	if not _can_drag_selection():
		return
	var previous := _selection.rotation
	_selection.rotation += deg_to_rad(degrees)
	if not _can_place(_selection, _selection.global_position):
		_selection.rotation = previous
	_sync_placed_origin(_selection)
	_gizmo.queue_redraw()
	_refresh_ui()


func _recycle_selected() -> void:
	if _testing or not _placed.has(_selection):
		return
	var key := str(_selection.get_meta("inventory_key", ""))
	var removed: Array[Node2D] = [_selection]
	if _selection is Portal:
		var partner := (_selection as Portal).linked_portal
		if partner != null and _placed.has(partner):
			removed.append(partner)
	for block in removed:
		for link in _links.duplicate():
			if link.get_target() == block or _source_for_link(link) == block:
				_remove_link(link)
		_placed.erase(block)
		block.queue_free()
	_remaining[key] = int(_remaining.get(key, 0)) + 1
	_selection = null
	_selected_link = null
	_gizmo.set_target(null)
	_refresh_ui()


func _wire_source_error(source: Node2D) -> String:
	if _testing:
		return "请先返回搭建阶段。"
	if _manager.build_wire_limit <= 0:
		return "本关未提供玩家电线。"
	if _links.size() >= _manager.build_wire_limit:
		return "电线已用完，请先拆除已有电线。"
	if WireService.source_signal(source).is_empty():
		return "请选择触发开关或压力传感器。"
	if not _placed.has(source) and not _manager.build_wire_sources.has(str(_blocks.get_path_to(source))):
		return "设计者未开放这个预置开关的接线权限。"
	return ""


func _begin_wire() -> void:
	var reason: String = _wire_source_error(_selection)
	if not reason.is_empty():
		_status_label.text = reason
		return
	_placing_key = ""
	_setting_destination = false
	_wiring_source = _selection
	_refresh_ui()


func _try_connect(source: Node2D, target: Node2D) -> void:
	var reason: String = _wire_source_error(source)
	if reason.is_empty():
		reason = WireService.connection_error(_blocks, source, target)
	if reason.is_empty() and not _can_wire_target(target):
		reason = "设计者未开放这个目标的接线权限。"
	if not reason.is_empty():
		_status_label.text = reason
		return
	var link: ActionLink = WireService.create_wire(_blocks, source, target)
	if link == null:
		_status_label.text = "接线失败，请重新选择开关和目标。"
		return
	_links.append(link)
	var line: Line2D = Line2D.new()
	line.width = 2.0
	line.default_color = Color(1.0, 0.65, 0.25)
	_blocks.add_child(line)
	_wire_lines[link] = line
	_select(target)
	_status_label.text = "已连接。选择“设置机关运动终点”指定动作。"


func _can_wire_target(target: Node2D) -> bool:
	if not WireService.is_target(target):
		return false
	return _placed.has(target) or _manager.build_wire_targets.has(str(_blocks.get_path_to(target)))


func _world_position(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position


func _link_for_target(target: Node2D) -> ActionLink:
	for link in _links:
		if is_instance_valid(link) and link.get_target() == target:
			return link
	return null


func _source_for_link(link: ActionLink) -> Node2D:
	for connection in link.get_incoming_connections():
		var signal_value: Signal = connection.get("signal")
		var source := signal_value.get_object() as Node2D
		if source != null:
			return source
	return null


func _begin_destination() -> void:
	if not is_instance_valid(_selected_link):
		return
	_setting_destination = true
	_refresh_ui()


func _sync_action_destination_hint() -> void:
	if not is_instance_valid(_wire_overlay):
		return
	if _testing or not is_instance_valid(_selected_link):
		_wire_overlay.set_action_hint(null)
		return
	if _setting_destination:
		_wire_overlay.set_action_hint(
			_selected_link, true, _level_root.get_global_mouse_position())
	else:
		_wire_overlay.set_action_hint(_selected_link)


func _remove_selected_wire() -> void:
	if is_instance_valid(_selected_link):
		_remove_link(_selected_link)
	_selected_link = null
	_refresh_ui()


func _remove_link(link: ActionLink) -> void:
	if _wire_lines.has(link):
		(_wire_lines[link] as Node).queue_free()
		_wire_lines.erase(link)
	_links.erase(link)
	WireService.remove_wire(link)


func _sync_placed_origin(block: Node2D) -> void:
	if block is StoneBlock:
		(block as StoneBlock).set_build_origin()
	for link in _links:
		if is_instance_valid(link) and link.get_target() == block:
			link.sync_origin_from_target()


func _start_test() -> void:
	_cancel_tool()
	if _view_panning:
		_view_panning = false
		_pan_button = MOUSE_BUTTON_NONE
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if _gizmo.is_dragging():
		_gizmo.end_drag()
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	_source_rotations.clear()
	_source_aim_before_test.clear()
	for child in _blocks.get_children():
		var source := child as LightSource
		if source == null:
			continue
		_source_aim_before_test[source] = source.follow_mouse
		if _placed.has(source):
			_source_rotations[source] = source.rotation
	_manager.reset_level()
	var first_source: LightSource = null
	for source in _source_aim_before_test:
		if not is_instance_valid(source):
			continue
		if _source_rotations.has(source):
			source.rotation = _source_rotations[source]
		source.follow_mouse = true
		if first_source == null:
			first_source = source
	if first_source != null:
		first_source.select_for_aim()
	_testing = true
	_bounds_outline.visible = false
	_gizmo.hide()
	_level_root.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_ui()


func _return_to_build() -> void:
	_manager.reset_level()
	for source in _source_aim_before_test:
		if not is_instance_valid(source):
			continue
		source.follow_mouse = _source_aim_before_test[source]
		if _source_rotations.has(source):
			source.rotation = _source_rotations[source]
	_source_rotations.clear()
	_source_aim_before_test.clear()
	_level_root.process_mode = Node.PROCESS_MODE_DISABLED
	_testing = false
	_bounds_outline.visible = true
	_gizmo.show()
	_refresh_ui()


func _toggle_test() -> void:
	if get_tree().paused or SceneTransition.is_transitioning():
		return
	if _testing:
		_return_to_build()
	else:
		_start_test()


func _unique_name(base: String) -> String:
	var result := base
	var index := 2
	while _blocks.has_node(result):
		result = "%s%d" % [base, index]
		index += 1
	return result
