class_name PlayerBuilder
extends CanvasLayer

## Player-facing construction controls for a limited-build level.

const ACTION_LINK_SCENE := preload("res://blocks/action_link/action_link.tscn")

var _manager: LevelManager
var _level_root: Node2D
var _blocks: Node2D
var _remaining: Dictionary = {}
var _placed: Array[Node2D] = []
var _links: Array[ActionLink] = []
var _wire_lines: Dictionary = {}
var _selection: Node2D = null
var _selected_link: ActionLink = null
var _placing_key := ""
var _wiring_source: Node2D = null
var _setting_destination := false
var _dragging := false
var _drag_offset := Vector2.ZERO
var _testing := false
var _inventory_box: VBoxContainer
var _selection_label: Label
var _status_label: Label
var _wire_controls: VBoxContainer
var _test_button: Button
var _return_button: Button
var _ghost: Polygon2D
var _bounds_outline: Line2D


func configure(manager: LevelManager) -> void:
	_manager = manager
	_level_root = manager.get_parent() as Node2D
	_blocks = _level_root.get_node("Blocks") as Node2D
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	for index in manager.build_item_keys.size():
		if index < manager.build_item_counts.size():
			_remaining[manager.build_item_keys[index]] = maxi(manager.build_item_counts[index], 0)
	for child in _blocks.get_children():
		if child is StoneBlock:
			(child as StoneBlock).player_draggable = false
		elif child is LightSource:
			(child as LightSource).follow_mouse = manager.build_aimable_sources.has(
				str(_blocks.get_path_to(child)))
	_build_ui()
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
	_level_root.process_mode = Node.PROCESS_MODE_DISABLED
	_refresh_ui()


func _exit_tree() -> void:
	if is_instance_valid(_ghost):
		_ghost.free()
	if is_instance_valid(_bounds_outline):
		_bounds_outline.free()
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
	for link in _links:
		if not is_instance_valid(link) or not _wire_lines.has(link):
			continue
		var line := _wire_lines[link] as Line2D
		var source := _source_for_link(link)
		var target := link.get_target()
		if line != null and source != null and target != null:
			line.points = PackedVector2Array([source.position, target.position])


func _unhandled_input(event: InputEvent) -> void:
	if _testing:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_placing_key = ""
		_wiring_source = null
		_setting_destination = false
		_ghost.visible = false
		_refresh_ui()
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		if not _can_drag_selection():
			_dragging = false
			return
		var next_position := _level_root.get_global_mouse_position() + _drag_offset
		if _can_place(_selection, next_position):
			_selection.global_position = next_position
			_sync_placed_origin(_selection)
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if not button.pressed:
		_dragging = false
		return
	var world_point := _level_root.get_global_mouse_position()
	if _setting_destination and is_instance_valid(_selected_link):
		var target := _selected_link.get_target()
		if target != null and _manager.build_bounds.has_point(world_point):
			_selected_link.move_offset = world_point - target.global_position
			_setting_destination = false
			_refresh_ui()
		get_viewport().set_input_as_handled()
		return
	if _wiring_source != null:
		_try_connect(_wiring_source, _block_at(world_point))
		_wiring_source = null
		_refresh_ui()
		get_viewport().set_input_as_handled()
		return
	if not _placing_key.is_empty():
		_place_item(_placing_key, world_point)
		get_viewport().set_input_as_handled()
		return
	_select(_block_at(world_point))
	if _can_drag_selection():
		_dragging = true
		_drag_offset = _selection.global_position - world_point
	get_viewport().set_input_as_handled()


func _can_drag_selection() -> bool:
	return (
		is_instance_valid(_selection)
		and _placed.has(_selection)
		and not (_selection is StoneBlock)
	)


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12.0, 94.0)
	panel.custom_minimum_size = Vector2(260.0, 0.0)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260.0, 475.0)
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(235.0, 0.0)
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "本关工具箱"
	title.add_theme_font_size_override("font_size", 19)
	box.add_child(title)
	_inventory_box = VBoxContainer.new()
	box.add_child(_inventory_box)
	box.add_child(_make_button("取消放置 / 接线", _cancel_tool))
	_selection_label = Label.new()
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_selection_label)
	box.add_child(_make_button("旋转选中元件 −15°", _rotate_selected.bind(-15.0)))
	box.add_child(_make_button("旋转选中元件 +15°", _rotate_selected.bind(15.0)))
	box.add_child(_make_button("回收选中元件", _recycle_selected))
	box.add_child(_make_button("从选中开关接电线", _begin_wire))
	_wire_controls = VBoxContainer.new()
	box.add_child(_wire_controls)
	_wire_controls.add_child(_make_button("设置机关运动终点", _begin_destination))
	var angle_row := HBoxContainer.new()
	_wire_controls.add_child(angle_row)
	angle_row.add_child(_make_label("旋转角度"))
	var angle_spin := _make_spin(-360.0, 360.0, 15.0)
	angle_spin.value_changed.connect(func(value: float) -> void:
		if is_instance_valid(_selected_link):
			_selected_link.rotate_degrees = value)
	angle_row.add_child(angle_spin)
	angle_spin.set_meta("wire_property", "rotate_degrees")
	var move_row := HBoxContainer.new()
	_wire_controls.add_child(move_row)
	move_row.add_child(_make_label("移动速度"))
	var move_spin := _make_spin(1.0, 2000.0, 10.0)
	move_spin.value_changed.connect(func(value: float) -> void:
		if is_instance_valid(_selected_link):
			_selected_link.move_speed = value)
	move_row.add_child(move_spin)
	move_spin.set_meta("wire_property", "move_speed")
	var rotate_row := HBoxContainer.new()
	_wire_controls.add_child(rotate_row)
	rotate_row.add_child(_make_label("旋转速度"))
	var rotate_spin := _make_spin(1.0, 2000.0, 10.0)
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
	_test_button = _make_button("开始试射", _start_test)
	box.add_child(_test_button)
	_return_button = _make_button("返回搭建", _return_to_build)
	box.add_child(_return_button)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status_label)


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
		button.disabled = int(_remaining[key]) <= 0 or _testing
		_inventory_box.add_child(button)
	_selection_label.text = "未选中元件"
	if is_instance_valid(_selection):
		var edit_hint := "设计者预置，已锁定"
		if _placed.has(_selection):
			if _selection is StoneBlock:
				edit_hint = "不可拖动，可旋转、回收"
			else:
				edit_hint = "可移动、旋转、回收"
		_selection_label.text = "%s：%s" % [
			_selection.name,
			edit_hint,
		]
	_wire_controls.visible = is_instance_valid(_selected_link) and not _testing
	if _wire_controls.visible:
		for child in _wire_controls.get_children():
			for control in child.get_children():
				_sync_wire_control(control)
			_sync_wire_control(child)
	_test_button.visible = not _testing
	_return_button.visible = _testing
	_status_label.text = "空格发射；返回搭建可调整元件。" if _testing else (
		"点击场景放置：%s" % _placing_key if not _placing_key.is_empty() else
		"先选元件，再点场景放置。预置物体不可修改。"
	)
	if _wiring_source != null:
		_status_label.text = "点击允许连接的机关，完成电线。"
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
			or other is Line2D or other is Polygon2D
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
		if block == null or block is ActionLink or block is Line2D or block is Polygon2D:
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
	_refresh_ui()


func _rotate_selected(degrees: float) -> void:
	if not _placed.has(_selection):
		return
	_selection.rotation += deg_to_rad(degrees)
	_sync_placed_origin(_selection)
	_refresh_ui()


func _recycle_selected() -> void:
	if not _placed.has(_selection):
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
	_refresh_ui()


func _begin_wire() -> void:
	if _manager.build_wire_limit <= _links.size() or not is_instance_valid(_selection):
		return
	if not (_selection is TriggerSwitch or _selection is PressureSensor):
		_status_label.text = "请选择触发开关或压力传感器。"
		return
	if not _placed.has(_selection) and not _manager.build_wire_sources.has(
		str(_blocks.get_path_to(_selection))):
		_status_label.text = "设计者尚未开放这个预置开关的接线权限。"
		return
	_placing_key = ""
	_wiring_source = _selection
	_refresh_ui()


func _try_connect(source: Node2D, target: Node2D) -> void:
	if target == null or target == source or not _can_wire_target(target):
		_status_label.text = "这个目标未开放玩家接线。"
		return
	if _link_for_target(target) != null or _any_existing_link(target):
		_status_label.text = "该机关已有电线。"
		return
	var link := ACTION_LINK_SCENE.instantiate() as ActionLink
	link.name = _unique_name("PlayerWire")
	_blocks.add_child(link)
	link.target_node = link.get_path_to(target)
	link.resolve_target()
	var signal_name: StringName = &"active_changed" if source is TriggerSwitch else &"pressed_changed"
	if source.connect(signal_name, Callable(link, ActionLink.METHOD_NAME)) != OK:
		link.queue_free()
		return
	_links.append(link)
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color(1.0, 0.65, 0.25)
	_blocks.add_child(line)
	_wire_lines[link] = line
	_select(target)
	_status_label.text = "已连接。选择“设置机关运动终点”指定动作。"


func _can_wire_target(target: Node2D) -> bool:
	if _placed.has(target):
		return true
	return _manager.build_wire_targets.has(str(_blocks.get_path_to(target)))


func _any_existing_link(target: Node2D) -> bool:
	for child in _blocks.get_children():
		var link := child as ActionLink
		if link != null and link.get_target() == target:
			return true
	return false


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


func _remove_selected_wire() -> void:
	if is_instance_valid(_selected_link):
		_remove_link(_selected_link)
	_selected_link = null
	_refresh_ui()


func _remove_link(link: ActionLink) -> void:
	var source := _source_for_link(link)
	if source != null:
		var signal_name: StringName = &"active_changed" if source is TriggerSwitch else &"pressed_changed"
		var callback := Callable(link, ActionLink.METHOD_NAME)
		if source.is_connected(signal_name, callback):
			source.disconnect(signal_name, callback)
	if _wire_lines.has(link):
		(_wire_lines[link] as Node).queue_free()
		_wire_lines.erase(link)
	_links.erase(link)
	link.queue_free()


func _sync_placed_origin(block: Node2D) -> void:
	if block is StoneBlock:
		(block as StoneBlock).set_build_origin()
	for link in _links:
		if is_instance_valid(link) and link.get_target() == block:
			link.sync_origin_from_target()


func _start_test() -> void:
	_cancel_tool()
	_dragging = false
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	_manager.reset_level()
	_testing = true
	_bounds_outline.visible = false
	_level_root.process_mode = Node.PROCESS_MODE_INHERIT
	_refresh_ui()


func _return_to_build() -> void:
	_manager.reset_level()
	_level_root.process_mode = Node.PROCESS_MODE_DISABLED
	_testing = false
	_bounds_outline.visible = true
	_refresh_ui()


func _unique_name(base: String) -> String:
	var result := base
	var index := 2
	while _blocks.has_node(result):
		result = "%s%d" % [base, index]
		index += 1
	return result
