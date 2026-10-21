class_name LevelEditor
extends Control

## 游戏内关卡编辑器（v1）：拖放 / 缩放 / 旋转积木，用「电线」连接触发机关与机关，
## 保存为标准 level_NN.tscn，与现有关卡管线完全兼容。
##
## 核心保证：
##   * 电线 = 关卡里的电线节点（ActionLink：动作参数 + 一条开关信号连接）；
##     视觉层（WireLayer）只属于编辑器场景，游戏里没有它 → 电线天然不可见
##   * 三元模型：开关（触发/压力感应）→ 电线（移多少/转多少/时长/循环/恢复）
##     → 任意可动作积木（镜面、墙体等，目标本身不负责感知）
##   * 六步加载管线：捕获干净属性 → 中和（process DISABLED + 关相机）→ 进树 →
##     编辑器相机 → deferred 清理（LevelManager UI / 蚕茧连接）→ 回写属性
##   * 撤销/重做 = 序列化快照 → user:// 临时文件重载换子树（50 步）
##   * 关卡边界固定 1152×648；编辑相机可缩放 / 平移，但不会写入关卡
##   * 实时验证会运行光线、重力和机关，退出时恢复进入前快照
##   * 试玩留在编辑器，允许修改已有积木/电线，退出时只保留主动编辑
##
## 快捷键：箭头 微移（Shift=32px）· Q/E 旋转 ±15°（Shift=1°）· Del 删除
##          滚轮缩放 · 中键/右键拖动画布 · Ctrl+D 复制 · Ctrl+Z/Y 撤销重做
##          Ctrl+S/O/N · Esc 取消选中/退出试玩或验证/返回主菜单

const LEVELS_DIR := "res://scenes/levels"
const BASE_SCENE := "res://scenes/levels/level_base.tscn"
const ACTION_LINK_SCENE := "res://blocks/action_link/action_link.tscn"
const MENU_SCENE := "res://scenes/LevelSelectPage/LevelSelectPage.tscn"
const UNDO_LIMIT := 50
const GRID_SIZE := 32.0
const VIEW_RECT := Rect2(0, 0, 1152, 648)
const UNDO_SWAP_PATH := "user://editor_undo_swap.tscn"
const MIN_VIEW_ZOOM := 0.5
const MAX_VIEW_ZOOM := 4.0
const VIEW_ZOOM_STEP := 1.2

@onready var _ray_renderer: LightRayRenderer = $World/RayRenderer
@onready var _wire_layer: WireLayer = $World/WireLayer
@onready var _level_holder: Node2D = $World/LevelRoot
@onready var _gizmo: SelectionGizmo = $World/Gizmo
@onready var _editor_camera: Camera2D = $EditorCamera
@onready var _ui: CanvasLayer = $UI

# ---------- 关卡状态 ----------
var _level_root: Node = null
var _level_base_path := BASE_SCENE
var _current_path := ""
var _selection: Node2D = null
var _dirty := false
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []

# ---------- 电线拖拽状态 ----------
var _wire_dragging := false
var _wire_drag_source: Node2D = null
var _wire_drag_signal := &""

# ---------- 键盘连按合并 ----------
var _nudge_undo_open := false
var _nudge_timeout := 0.0

var _show_ray_preview := true
var _view_panning := false
var _pan_button: MouseButton = MOUSE_BUTTON_NONE
var _validation_mode := false
var _validation_snapshot: Dictionary = {}
var _validation_dirty := false
var _playtest_mode := false
var _playtest_snapshot: Dictionary = {}
var _playtest_dirty := false
var _playtest_edits: Dictionary = {}
var _playtest_initial_transforms: Dictionary = {}
var _gizmo_start_transform: Dictionary = {}
var _playtest_aim_source: LightSource = null
var _coverage_lit_start := 0.0
var _coverage_lit_end := 360.0
var _preview_source: Node2D = null

# ---------- UI 引用（代码构建） ----------
var _inspector_content: VBoxContainer = null
var _status_label: Label = null
var _zoom_label: Label = null
var _palette_panel: PanelContainer = null
var _inspector_panel: PanelContainer = null
var _validation_toggle: CheckButton = null
var _play_button: Button = null
var _coverage_toggle: CheckButton = null
var _coverage_config_button: Button = null
var _coverage_dialog: ConfirmationDialog = null
var _coverage_start_spin: SpinBox = null
var _coverage_end_spin: SpinBox = null
var _toolbar_edit_controls: Array[BaseButton] = []
var _save_dialog: ConfirmationDialog = null
var _save_name_edit: LineEdit = null
var _save_title_edit: LineEdit = null
var _next_level_option: OptionButton = null
var _open_dialog: FileDialog = null
var _confirm_dialog: ConfirmationDialog = null
var _confirm_callback: Callable = Callable()
# Inspector 变换控件（变换提交后刷新值用）
var _spin_x: SpinBox = null
var _spin_y: SpinBox = null
var _spin_rotation: SpinBox = null
var _spin_scale_x: SpinBox = null
var _spin_scale_y: SpinBox = null


func _ready() -> void:
	_editor_camera.make_current()
	_gizmo.view_rect = VIEW_RECT
	_gizmo.transform_started.connect(_on_gizmo_transform_started)
	_gizmo.transform_committed.connect(_on_gizmo_transform_committed)
	_build_ui()
	var queued_path := LevelFileIO.take_level_to_edit()
	if queued_path.is_empty() or not open_level(queued_path):
		new_level()


func _exit_tree() -> void:
	if _view_panning:
		_end_view_pan()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _view_panning:
		_end_view_pan()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_playtest_aim_source = null


# ============================================================
# 程序化 API（UI 与测试共用）
# ============================================================

## 新建空白关卡（有未保存改动时弹确认框）
func new_level() -> void:
	if _playtest_mode:
		return
	if not _dirty:
		_do_new_level()
		return
	_show_confirm("新建关卡会丢弃未保存的改动，继续吗？", _do_new_level)


## 打开关卡文件（有未保存改动时弹确认框，确认后才真的打开）
func open_level(path: String) -> bool:
	if _playtest_mode:
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	if _dirty:
		_show_confirm("打开会丢弃未保存的改动，继续吗？", func() -> void: _do_open(path, packed))
		return true
	_do_open(path, packed)
	return true


## 保存到当前路径；新关卡弹另存为对话框
func save() -> bool:
	if _playtest_mode:
		return false
	if _current_path.is_empty():
		save_as()
		return false
	return _write_current()


## 弹出另存为对话框（文件名 / 关卡名 / 下一关）
func save_as() -> void:
	if _level_root == null or _playtest_mode:
		return
	_save_name_edit.text = LevelFileIO.suggest_file_name()
	var manager := _level_root.get_node_or_null("LevelManager")
	_save_title_edit.text = str(manager.get("level_name")) if manager != null else ""
	_next_level_option.select(0)
	_save_dialog.popup_centered()


## 在画面位置生成一块积木（scene_path 见 PaletteData）。返回新节点，失败返回 null。
func spawn_block(
	scene_path: String, world_position: Vector2,
	block_name: String = "", preset: Dictionary = {}, entry_key: String = "",
) -> Node2D:
	if _level_root == null or _playtest_mode:
		return null
	_push_undo()
	var block := _spawn_block_impl(scene_path, world_position, preset, entry_key)
	if block == null:
		return null
	if block_name != "":
		block.name = block_name
	select(block)
	_update_status()
	return block


## 选中一个积木（null 取消选中）
func select(node: Node2D) -> void:
	if _selection == node:
		return
	_restore_wire_previews()
	_selection = node
	_wire_layer.selected_index = -1
	_gizmo.set_target(node)
	_wire_layer.set_source_hint(node if node != null and _source_signal_of(node) != &"" else null)
	_rebuild_inspector()


func clear_selection() -> void:
	_restore_wire_previews()
	_selection = null
	_wire_layer.selected_index = -1
	_gizmo.set_target(null)
	_wire_layer.set_source_hint(null)
	_rebuild_inspector()


## 选中一条电线（Del 断开）
func select_wire(index: int) -> void:
	if _wire_layer.selected_index != index:
		_restore_wire_previews()
	_selection = null
	_gizmo.set_target(null)
	_wire_layer.set_source_hint(null)
	_wire_layer.selected_index = index
	_rebuild_inspector()


func delete_selected() -> void:
	if _selection == null or _playtest_mode:
		return
	_push_undo()
	var node := _selection
	# 传送门按“一对”删除：只删一扇会留下吞光的坏门
	var partner: Node2D = null
	if node is Portal:
		var linked := (node as Portal).linked_portal
		if linked != null and is_instance_valid(linked) and _level_root.is_ancestor_of(linked):
			partner = linked
	clear_selection()
	_wire_layer.remove_wires_touching(node)
	node.free()
	if partner != null:
		_wire_layer.remove_wires_touching(partner)
		partner.free()
	_update_status()


func duplicate_selected() -> void:
	if _selection == null or _playtest_mode or _selection.scene_file_path.is_empty():
		return
	# 传送门复制 = 复制“一对”：只复制一扇会让副本指回原来的另一半
	if _selection is Portal:
		var portal_entry := PaletteData.find_entry_for(_selection.scene_file_path, _selection.name)
		if portal_entry.is_empty():
			portal_entry = {"path": _selection.scene_file_path, "key": "portal", "pair_gap": 260.0}
		spawn_pair(portal_entry, _selection.position + Vector2(GRID_SIZE, GRID_SIZE))
		return
	var source := _selection
	_push_undo()
	var copy := _spawn_block_impl(source.scene_file_path, Vector2.ZERO)
	LevelFileIO.copy_props(source, copy, true)
	copy.position = source.position + Vector2(GRID_SIZE, GRID_SIZE)
	select(copy)
	_update_status()


func nudge_selected(delta: Vector2, push_undo := true) -> void:
	if _selection == null:
		return
	if push_undo:
		_push_undo()
	_selection.position += delta
	if _playtest_mode:
		var authored_position: Vector2 = _playtest_authored_transform(_selection, &"position")
		_record_playtest_property(_selection, &"position", authored_position + delta)
	_refresh_inspector_transform()
	_on_selected_transform_changed()


func rotate_selected(degrees: float, push_undo := true) -> void:
	if _selection == null:
		return
	if push_undo:
		_push_undo()
	_selection.rotation += deg_to_rad(degrees)
	if _playtest_mode:
		var authored_rotation: float = _playtest_authored_transform(_selection, &"rotation")
		_record_playtest_property(_selection, &"rotation", authored_rotation + deg_to_rad(degrees))
	_refresh_inspector_transform()
	_on_selected_transform_changed()


func scale_selected(factor: Vector2, push_undo := true) -> void:
	if _selection == null:
		return
	if push_undo:
		_push_undo()
	_selection.scale = Vector2(
		maxf(_selection.scale.x * factor.x, SelectionGizmo.MIN_SCALE),
		maxf(_selection.scale.y * factor.y, SelectionGizmo.MIN_SCALE)
	)
	if _playtest_mode:
		var authored_scale: Vector2 = _playtest_authored_transform(_selection, &"scale")
		_record_playtest_property(_selection, &"scale", Vector2(
			maxf(authored_scale.x * factor.x, SelectionGizmo.MIN_SCALE),
			maxf(authored_scale.y * factor.y, SelectionGizmo.MIN_SCALE),
		))
	_refresh_inspector_transform()
	_on_selected_transform_changed()


## 改选中块的属性（Inspector 控件内部传 push_undo=false，自己管撤销点）
func set_selected_property(prop_name: StringName, value: Variant, push_undo := true) -> void:
	if _selection == null:
		return
	if push_undo:
		_push_undo()
	_selection.set(prop_name, value)
	_record_playtest_property(_selection, prop_name, value)
	_selection.queue_redraw()
	# 传送门：编号要同步给配对的那扇门，否则玩家会看到两个不一样的号
	if _selection is Portal:
		var portal := _selection as Portal
		if prop_name == &"pair_id":
			var partner := portal.linked_portal
			if partner != null and is_instance_valid(partner):
				partner.pair_id = value
				_record_playtest_property(partner, &"pair_id", value)
				partner.queue_redraw()
		elif prop_name == &"length" or prop_name == &"thickness":
			portal.apply_shape()
	if _show_ray_preview:
		_refresh_ray_preview()
	_update_status()


## 连接一条电线：在目标机关旁生成电线节点（ActionLink），把开关信号连到它的 _on_signal。
## 动作参数（移多少/转多少/时长/循环/恢复）随后在电线 Inspector 里配。
func connect_wire(
	source: Node2D, target: Node2D,
	signal_name: StringName = &"", method_name: StringName = &"",
) -> bool:
	if _playtest_mode:
		return false
	if source == null or target == null or source == target:
		return false
	if signal_name == &"":
		signal_name = _source_signal_of(source)
	if signal_name == &"" or not _is_valid_wire_target(target, signal_name):
		return false
	# 一个机关只能接一条电线：两条电线会各自 tween 同一目标，互相抢位置
	if _has_wire_to_target(target):
		return false
	_push_undo()
	var link := _spawn_link_for(target)
	if link == null:
		return false
	if source.connect(signal_name, Callable(link, ActionLink.METHOD_NAME)) != OK:
		link.queue_free()
		return false
	if not _wire_layer.add_wire(link, source, signal_name):
		source.disconnect(signal_name, Callable(link, ActionLink.METHOD_NAME))
		link.queue_free()
		return false
	_rebuild_inspector()
	_update_status()
	return true


func undo() -> bool:
	if _playtest_mode or _undo_stack.is_empty():
		return false
	_redo_stack.append(_capture_state())
	var previous: Dictionary = _undo_stack.pop_back()
	_restore_state(previous)
	_dirty = true
	_update_status()
	return true


func redo() -> bool:
	if _playtest_mode or _redo_stack.is_empty():
		return false
	_undo_stack.append(_capture_state())
	var next: Dictionary = _redo_stack.pop_back()
	_restore_state(next)
	_dirty = true
	_update_status()
	return true


## 当前关卡树的序列化文本（保存与快照共用）
func serialize() -> String:
	if _level_root == null:
		return ""
	# 动作位预览只影响编辑画面：序列化前暂时还原，完成后继续显示预览。
	var previewed_links := _suspend_wire_previews()
	var text := LevelFileIO.serialize_level(_level_root, _level_base_path)
	_resume_wire_previews(previewed_links)
	return text


func get_level_root() -> Node:
	return _level_root


func get_current_path() -> String:
	return _current_path


func get_wire_count() -> int:
	return _wire_layer.get_wire_count()


func get_view_zoom() -> float:
	return _editor_camera.zoom.x


func get_view_center() -> Vector2:
	return _editor_camera.position


func screen_to_world(screen_position: Vector2) -> Vector2:
	return _to_world(screen_position)


## 视图导航只改变编辑相机，不进入撤销栈，也不会写进关卡文件。
func set_view_zoom(value: float, screen_anchor := Vector2(-1.0, -1.0)) -> void:
	var target_zoom := clampf(value, MIN_VIEW_ZOOM, MAX_VIEW_ZOOM)
	if is_equal_approx(target_zoom, get_view_zoom()):
		_update_zoom_label()
		return
	var anchor := screen_anchor
	if anchor.x < 0.0 or anchor.y < 0.0:
		anchor = get_viewport_rect().size * 0.5
	var anchor_before := _to_world(anchor)
	_editor_camera.zoom = Vector2.ONE * target_zoom
	_editor_camera.force_update_scroll()
	var anchor_after := _to_world(anchor)
	_editor_camera.position += anchor_before - anchor_after
	_clamp_view_center()
	_editor_camera.force_update_scroll()
	_update_zoom_label()


func pan_view(screen_delta: Vector2) -> void:
	_editor_camera.position -= screen_delta / _editor_camera.zoom
	_clamp_view_center()
	_editor_camera.force_update_scroll()


func reset_view() -> void:
	_view_panning = false
	_pan_button = MOUSE_BUTTON_NONE
	_editor_camera.position = VIEW_RECT.get_center()
	_editor_camera.zoom = Vector2.ONE
	_editor_camera.force_update_scroll()
	_update_zoom_label()


func is_validation_mode() -> bool:
	return _validation_mode


func is_playtest_mode() -> bool:
	return _playtest_mode


## 测试光区以世界正右为 0°；只能在开启覆盖前设置。
func set_full_coverage_light_range(start_degrees: float, end_degrees: float) -> bool:
	if _coverage_toggle != null and _coverage_toggle.button_pressed:
		return false
	_coverage_lit_start = clampf(start_degrees, 0.0, 360.0)
	_coverage_lit_end = clampf(end_degrees, 0.0, 360.0)
	if _coverage_config_button != null:
		_coverage_config_button.text = "有光 %d°→%d°" % [
			roundi(_coverage_lit_start), roundi(_coverage_lit_end),
		]
	return true


## 试玩期间可编辑现有节点；结束时只保留主动修改的属性，不保存物理/动画位移。
func set_playtest_mode(active: bool) -> bool:
	if _level_root == null or (active and _validation_mode):
		return false
	if active == _playtest_mode:
		return true
	if active:
		_enter_playtest_mode()
	else:
		_exit_playtest_mode()
	return _playtest_mode == active


## 在编辑器内运行真实光线、重力与机关；退出后恢复进入前的关卡快照。
func set_validation_mode(active: bool) -> bool:
	if active == _validation_mode or _level_root == null or (active and _playtest_mode):
		return active == _validation_mode
	if active:
		_enter_validation_mode()
	else:
		_exit_validation_mode()
	return _validation_mode == active


## 不运行动画，直接预览某个开关的全部出线动作；不会污染保存结果。
func preview_trigger_source(source: Node2D, active: bool) -> bool:
	if source == null or not is_instance_valid(source) or _source_signal_of(source) == &"":
		return false
	if active:
		_stop_trigger_preview()
		_suspend_wire_previews()
		_preview_source = source
		_set_source_preview_visual(source, true)
	else:
		if _preview_source == source:
			_set_source_preview_visual(source, false)
			_preview_source = null
	var found_wire := false
	for wire in _wire_layer.get_wires():
		if wire["source"] != source:
			continue
		var link := wire["link"] as ActionLink
		if link != null:
			found_wire = link.set_editor_preview_active(active) or found_wire
	_wire_layer.queue_redraw()
	if _show_ray_preview:
		_refresh_ray_preview()
	return found_wire or _source_signal_of(source) != &""


# ============================================================
# 生命周期
# ============================================================

func _process(delta: float) -> void:
	if _nudge_undo_open:
		_nudge_timeout -= delta
		if _nudge_timeout <= 0.0:
			_nudge_undo_open = false
	if _validation_mode or _playtest_mode or _level_root == null or not _show_ray_preview:
		return
	_refresh_ray_preview()


func _unhandled_input(event: InputEvent) -> void:
	if _level_root == null:
		return
	if _validation_mode:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			set_validation_mode(false)
			get_viewport().set_input_as_handled()
			return
		if _handle_view_input(event):
			get_viewport().set_input_as_handled()
		return
	if (_playtest_mode and event is InputEventKey and event.pressed
			and event.keycode == KEY_ESCAPE):
		set_playtest_mode(false)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		if _handle_key(event):
			get_viewport().set_input_as_handled()
		return
	if _handle_view_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_world(event.position)
		else:
			_release_world(event.position)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event.position)


# ============================================================
# 键盘
# ============================================================

func _handle_key(event: InputEventKey) -> bool:
	if event.keycode == KEY_ESCAPE:
		_escape_pressed()
		return true
	# 焦点守卫：属性面板等控件持焦点时，其余快捷键全部让位
	if _ui_has_focus():
		return false
	if _playtest_mode and event.keycode not in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_Q, KEY_E]:
		return false
	match event.keycode:
		KEY_LEFT:
			_nudge_key(Vector2.LEFT, event.shift_pressed)
		KEY_RIGHT:
			_nudge_key(Vector2.RIGHT, event.shift_pressed)
		KEY_UP:
			_nudge_key(Vector2.UP, event.shift_pressed)
		KEY_DOWN:
			_nudge_key(Vector2.DOWN, event.shift_pressed)
		KEY_Q:
			_rotate_key(-1.0, event.shift_pressed)
		KEY_E:
			_rotate_key(1.0, event.shift_pressed)
		KEY_DELETE:
			_delete_pressed()
		KEY_D:
			if event.ctrl_pressed:
				duplicate_selected()
		KEY_Z:
			if event.ctrl_pressed:
				if event.shift_pressed:
					redo()
				else:
					undo()
		KEY_Y:
			if event.ctrl_pressed:
				redo()
		KEY_S:
			if event.ctrl_pressed:
				save()
		KEY_O:
			if event.ctrl_pressed:
				_open_dialog.popup_centered()
		KEY_N:
			if event.ctrl_pressed:
				new_level()
		_:
			return false
	return true


## 按住不放会来一串 echo：合并成一次撤销操作
func _nudge_key(direction: Vector2, large: bool) -> void:
	if _selection == null:
		return
	if not _nudge_undo_open:
		_push_undo()
		_nudge_undo_open = true
	_nudge_timeout = 0.8
	nudge_selected(direction * (GRID_SIZE if large else 1.0), false)


func _rotate_key(sign: float, fine: bool) -> void:
	if _selection == null:
		return
	if not _nudge_undo_open:
		_push_undo()
		_nudge_undo_open = true
	_nudge_timeout = 0.8
	rotate_selected(sign * (1.0 if fine else 15.0), false)


func _delete_pressed() -> void:
	if _wire_layer.selected_index >= 0:
		_on_wire_delete_pressed(_wire_layer.selected_index)
	elif _selection != null:
		delete_selected()


func _escape_pressed() -> void:
	if _view_panning:
		_end_view_pan()
		return
	if _wire_dragging:
		_cancel_wire_drag()
		return
	if _wire_layer.selected_index >= 0:
		_restore_wire_previews()
		_wire_layer.selected_index = -1
		_rebuild_inspector()
		return
	if _selection != null:
		clear_selection()
		return
	if _dirty:
		_show_confirm("返回关卡选择？未保存的改动会丢失。", _go_to_menu)
	else:
		_go_to_menu()


# ============================================================
# 鼠标
# ============================================================

func _handle_view_input(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button != null:
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _wire_dragging or _gizmo.is_dragging():
				return false
			set_view_zoom(get_view_zoom() * VIEW_ZOOM_STEP, button.position)
			return true
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _wire_dragging or _gizmo.is_dragging():
				return false
			set_view_zoom(get_view_zoom() / VIEW_ZOOM_STEP, button.position)
			return true
		if (
			button.button_index != MOUSE_BUTTON_MIDDLE
			and button.button_index != MOUSE_BUTTON_RIGHT
		):
			return false
		if button.pressed:
			if _wire_dragging or _gizmo.is_dragging():
				return false
			_view_panning = true
			_pan_button = button.button_index
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			return true
		if _view_panning and button.button_index == _pan_button:
			_end_view_pan()
			return true
		return false
	var motion := event as InputEventMouseMotion
	if motion != null and _view_panning:
		if not Input.is_mouse_button_pressed(_pan_button):
			_end_view_pan()
			return true
		pan_view(motion.relative)
		return true
	return false


func _end_view_pan() -> void:
	_view_panning = false
	_pan_button = MOUSE_BUTTON_NONE
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _clamp_view_center() -> void:
	_editor_camera.position = Vector2(
		clampf(_editor_camera.position.x, VIEW_RECT.position.x, VIEW_RECT.end.x),
		clampf(_editor_camera.position.y, VIEW_RECT.position.y, VIEW_RECT.end.y),
	)


func _update_zoom_label() -> void:
	if _zoom_label != null and is_instance_valid(_zoom_label):
		_zoom_label.text = "%d%%" % roundi(get_view_zoom() * 100.0)


func _press_world(screen_pos: Vector2) -> void:
	var world_point := _to_world(screen_pos)
	# 点击画面释放 UI 焦点，让快捷键回到编辑器
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	# 1) 选中块是触发源且点在端口上 → 开始拖电线
	if not _playtest_mode and _selection != null and _source_signal_of(_selection) != &"":
		var port := WireLayer.port_position(_selection, true)
		if world_point.distance_to(port) <= 12.0:
			_wire_dragging = true
			_wire_drag_source = _selection
			_wire_drag_signal = _source_signal_of(_selection)
			_wire_layer.set_preview(true, port, world_point)
			return
	# 试玩时在光源中心拖动是瞄准；按住 Shift 才走编辑器的移动手柄。
	if (
			_playtest_mode
			and _selection is LightSource
			and not Input.is_physical_key_pressed(KEY_SHIFT)
			and world_point.distance_to(_selection.global_position) <= LightSource.GRAB_RADIUS
	):
		_playtest_aim_source = _selection as LightSource
		return
	# 2) 变换手柄
	if _selection != null:
		var mode := _gizmo.hit_test(world_point)
		if mode != SelectionGizmo.DragMode.NONE:
			_gizmo.begin_drag(mode, world_point)
			return
	# 3) 拾取积木（后画的在上层，从后往前找）
	var block := _block_at_point(world_point)
	if block != null:
		select(block)
		if _playtest_mode and block is LightSource:
			if Input.is_physical_key_pressed(KEY_SHIFT):
				_gizmo.begin_drag(SelectionGizmo.DragMode.MOVE, world_point)
			else:
				_playtest_aim_source = block as LightSource
		return
	# 4) 电线
	var wire_index := _wire_layer.hit_test(world_point)
	if wire_index >= 0:
		select_wire(wire_index)
		return
	# 5) 空白处
	clear_selection()


func _release_world(screen_pos: Vector2) -> void:
	if _playtest_aim_source != null:
		_playtest_aim_source = null
		return
	var world_point := _to_world(screen_pos)
	if _wire_dragging:
		_wire_dragging = false
		_wire_layer.set_preview(false)
		_wire_layer.set_highlight_target(null)
		var target := _block_at_point(world_point)
		if target != null and target != _wire_drag_source:
			connect_wire(_wire_drag_source, target, _wire_drag_signal)
		return
	if _gizmo.is_dragging():
		_gizmo.end_drag()


func _handle_mouse_motion(screen_pos: Vector2) -> void:
	var world_point := _to_world(screen_pos)
	if _playtest_aim_source != null:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_playtest_aim_source = null
			return
		_aim_playtest_source_at(world_point)
		return
	if _wire_dragging:
		_wire_layer.set_preview(true, WireLayer.port_position(_wire_drag_source, true), world_point)
		var target := _block_at_point(world_point)
		if target != null and target != _wire_drag_source \
				and _is_valid_wire_target(target, _wire_drag_signal) \
				and not _has_wire_to_target(target):
			_wire_layer.set_highlight_target(target)
		else:
			_wire_layer.set_highlight_target(null)
	elif _gizmo.is_dragging():
		_gizmo.update_drag(world_point)


func _aim_playtest_source_at(world_point: Vector2) -> void:
	if not _playtest_mode or not is_instance_valid(_playtest_aim_source):
		return
	if world_point.distance_squared_to(_playtest_aim_source.global_position) < 0.01:
		return
	var previous_rotation := _playtest_aim_source.rotation
	_playtest_aim_source.look_at(world_point)
	if is_equal_approx(_playtest_aim_source.rotation, previous_rotation):
		return
	_record_playtest_property(_playtest_aim_source, &"rotation", _playtest_aim_source.rotation)
	_playtest_aim_source.direction_changed.emit(_playtest_aim_source.rotation)
	_refresh_inspector_transform()
	_on_selected_transform_changed()


func _cancel_wire_drag() -> void:
	_wire_dragging = false
	_wire_layer.set_preview(false)
	_wire_layer.set_highlight_target(null)


# ============================================================
# 关卡挂载（六步管线）
# ============================================================

## 把一棵关卡实例挂进编辑器：中和 → 进树 → 回写干净属性 → 重建电线
func _mount_level(instance: Node) -> void:
	var clean_props := LevelFileIO.capture_props(instance)
	# 中和：整个关卡子树停摆（光线系统/机关/输入全部禁用，_ready 仍会跑）
	instance.process_mode = Node.PROCESS_MODE_DISABLED
	# 关卡自带的相机在进树前关掉，避免夺走编辑器相机的 current
	var level_camera := instance.get_node_or_null("Camera2D") as Camera2D
	if level_camera != null:
		level_camera.enabled = false
	var previous := _level_root
	_level_holder.add_child(instance)
	# 回写干净属性表，抵消 _ready 副作用（传送门自动配对）
	LevelFileIO.restore_props(instance, clean_props)
	_level_root = instance
	clear_selection()
	_editor_camera.make_current()
	_wire_layer.clear()
	_wire_layer.rebuild_from_level(instance)
	_cleanup_level.call_deferred(instance.get_instance_id())
	if previous != null:
		previous.free()
	_update_status()


## deferred：释放游戏内 UI（胜利标签/提示条），断开蚕茧→胜利流程的连接
func _cleanup_level(instance_id: int) -> void:
	var instance := instance_from_id(instance_id) as Node
	if instance == null:
		return
	var manager := instance.get_node_or_null("LevelManager")
	if manager == null:
		return
	for child in manager.get_children():
		if child is CanvasLayer:
			child.free()
	for node in get_tree().get_nodes_in_group(Cocoon.COCOON_GROUP):
		var cocoon := node as Cocoon
		var callback := Callable(manager, "_on_cocoon_activated")
		if cocoon != null and cocoon.activated.is_connected(callback):
			cocoon.activated.disconnect(callback)


func _do_new_level() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	var instance := (load(BASE_SCENE) as PackedScene).instantiate()
	_level_base_path = BASE_SCENE
	_mount_level(instance)
	reset_view()
	_current_path = ""
	_dirty = false
	_update_status()


func _do_open(path: String, packed: PackedScene) -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_level_base_path = LevelFileIO.get_base_scene_path_from_file(path)
	_mount_level(packed.instantiate())
	reset_view()
	_current_path = path
	_dirty = false
	_update_status()


# ============================================================
# 撤销 / 重做
# ============================================================

func _capture_state() -> Dictionary:
	return {"text": serialize(), "base": _level_base_path}


func _push_undo() -> void:
	if _level_root == null or _playtest_mode:
		return
	_undo_stack.append(_capture_state())
	if _undo_stack.size() > UNDO_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()
	_dirty = true


func _record_playtest_property(node: Node, prop_name: StringName, value: Variant) -> void:
	if not _playtest_mode or not is_instance_valid(node):
		return
	if _playtest_edits.is_empty():
		_undo_stack.append(_playtest_snapshot)
		if _undo_stack.size() > UNDO_LIMIT:
			_undo_stack.pop_front()
		_redo_stack.clear()
	var path := str(_level_root.get_path_to(node))
	var props: Dictionary = _playtest_edits.get(path, {})
	props[String(prop_name)] = value
	_playtest_edits[path] = props
	_dirty = true


func _playtest_authored_transform(node: Node2D, prop_name: StringName) -> Variant:
	var path := str(_level_root.get_path_to(node))
	var edits: Dictionary = _playtest_edits.get(path, {})
	if edits.has(String(prop_name)):
		return edits[String(prop_name)]
	var initial: Dictionary = _playtest_initial_transforms.get(path, {})
	return initial.get(String(prop_name), node.get(prop_name))


func _record_playtest_component(node: Node2D, prop_name: StringName, axis: int, value: float) -> void:
	if not _playtest_mode:
		return
	var authored: Vector2 = _playtest_authored_transform(node, prop_name)
	if axis == 0:
		authored.x = value
	else:
		authored.y = value
	_record_playtest_property(node, prop_name, authored)


func _restore_state(state: Dictionary) -> void:
	LevelFileIO.write_text(UNDO_SWAP_PATH, state["text"])
	# 同一路径会被资源缓存，必须忽略缓存强制重读
	var packed := ResourceLoader.load(UNDO_SWAP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		push_error("撤销快照载入失败")
		return
	_level_base_path = state["base"]
	_mount_level(packed.instantiate())


# ============================================================
# 试玩 / 实时验证
# ============================================================

func _enter_playtest_mode() -> void:
	_cancel_wire_drag()
	_end_view_pan()
	_playtest_aim_source = null
	_restore_wire_previews()
	_playtest_snapshot = _capture_state()
	_playtest_dirty = _dirty
	_playtest_edits.clear()
	_playtest_initial_transforms.clear()
	for block in LevelFileIO.walk_instance_roots(_level_root):
		var node := block as Node2D
		if node == null:
			continue
		_playtest_initial_transforms[str(_level_root.get_path_to(node))] = {
			"position": node.position,
			"rotation": node.rotation,
			"scale": node.scale,
		}
	_playtest_mode = true
	_level_root.process_mode = Node.PROCESS_MODE_INHERIT
	var light_system := _level_root.get_node_or_null("LightSystem") as LightSystem
	if light_system != null:
		light_system.call(&"_refresh_nodes")
	var manager := _level_root.get_node_or_null("LevelManager")
	if manager != null:
		manager.process_mode = Node.PROCESS_MODE_DISABLED
	# 游戏态的拖拽/方向快捷键会与编辑手柄冲突；试玩期间统一交给编辑器。
	for block in LevelFileIO.walk_instance_roots(_level_root):
		if block is LightSource:
			block.set_process(false)
		if block is LightSource or block is StoneBlock:
			block.set_process_unhandled_input(false)
	_apply_playtest_ui(true)
	_rebuild_inspector()
	_update_status()


func _exit_playtest_mode() -> void:
	_playtest_aim_source = null
	var selected_path := ""
	if _selection != null and is_instance_valid(_selection):
		selected_path = str(_level_root.get_path_to(_selection))
	_level_root.process_mode = Node.PROCESS_MODE_DISABLED
	_playtest_mode = false
	_apply_playtest_ui(false)
	var snapshot := _playtest_snapshot
	var edits := _playtest_edits.duplicate(true)
	_playtest_snapshot = {}
	_playtest_edits.clear()
	_playtest_initial_transforms.clear()
	_restore_state(snapshot)
	for path in edits:
		var node := _level_root.get_node_or_null(NodePath(path))
		if node == null:
			continue
		var props: Dictionary = edits[path]
		for prop_name in props:
			node.set(StringName(prop_name), props[prop_name])
		if node is Node2D:
			(node as Node2D).queue_redraw()
		if node is Portal:
			(node as Portal).apply_shape()
	for wire in _wire_layer.get_wires():
		var link := wire["link"] as ActionLink
		if link != null:
			link.sync_origin_from_target()
	_dirty = _playtest_dirty or not edits.is_empty()
	if not selected_path.is_empty():
		var selected := _level_root.get_node_or_null(NodePath(selected_path)) as Node2D
		if selected != null:
			select(selected)
	_refresh_ray_preview()
	_update_status()


func _apply_playtest_ui(active: bool) -> void:
	_ray_renderer.visible = not active
	_wire_layer.visible = true
	_gizmo.visible = true
	if _palette_panel != null:
		_palette_panel.visible = not active
	if _inspector_panel != null:
		_inspector_panel.visible = true
	for control in _toolbar_edit_controls:
		if is_instance_valid(control):
			control.disabled = active and control != _play_button
	if _play_button != null:
		_play_button.text = "结束试玩" if active else "试玩"
	if _validation_toggle != null:
		_validation_toggle.disabled = active
	_sync_coverage_ui()


func _enter_validation_mode() -> void:
	_validation_snapshot = _capture_state()
	_validation_dirty = _dirty
	_cancel_wire_drag()
	_end_view_pan()
	clear_selection()
	_validation_mode = true
	_level_root.process_mode = Node.PROCESS_MODE_INHERIT
	var light_system := _level_root.get_node_or_null("LightSystem") as LightSystem
	if light_system != null:
		# 挂载新关卡时旧子树可能尚未释放，验证前重扫可去掉失效的组成员引用。
		light_system.call(&"_refresh_nodes")
	# 关卡管理器会接管 Esc / R 与过关跳转；验证模式只运行物理、光线和机关。
	var manager := _level_root.get_node_or_null("LevelManager")
	if manager != null:
		manager.process_mode = Node.PROCESS_MODE_DISABLED
	_apply_validation_ui(true)
	_update_status()


func _exit_validation_mode() -> void:
	if _level_root != null:
		_level_root.process_mode = Node.PROCESS_MODE_DISABLED
	_validation_mode = false
	_apply_validation_ui(false)
	if not _validation_snapshot.is_empty():
		var snapshot := _validation_snapshot
		_validation_snapshot = {}
		_restore_state(snapshot)
	_dirty = _validation_dirty
	_refresh_ray_preview()
	_update_status()


func _apply_validation_ui(active: bool) -> void:
	_ray_renderer.visible = not active
	_wire_layer.visible = not active
	_gizmo.visible = not active
	if _palette_panel != null:
		_palette_panel.visible = not active
	if _inspector_panel != null:
		_inspector_panel.visible = not active
	for control in _toolbar_edit_controls:
		if is_instance_valid(control):
			control.disabled = active
	if _validation_toggle != null:
		_validation_toggle.set_pressed_no_signal(active)
		_validation_toggle.text = "结束验证" if active else "实时验证"
	_sync_coverage_ui()


func _sync_coverage_ui() -> void:
	var test_active := _playtest_mode or _validation_mode
	if not test_active and _coverage_toggle != null:
		_coverage_toggle.set_pressed_no_signal(false)
		var light_system := _level_root.get_node_or_null("LightSystem") as LightSystem
		if light_system != null:
			light_system.configure_full_coverage(false, _coverage_lit_start, _coverage_lit_end)
	if _coverage_toggle != null:
		_coverage_toggle.disabled = not test_active
	if _coverage_config_button != null:
		_coverage_config_button.disabled = (
			_coverage_toggle != null and _coverage_toggle.button_pressed
		)


func _on_coverage_toggled(enabled: bool) -> void:
	if not (_playtest_mode or _validation_mode):
		_coverage_toggle.set_pressed_no_signal(false)
		return
	var light_system := _level_root.get_node_or_null("LightSystem") as LightSystem
	if light_system != null:
		light_system.configure_full_coverage(
			enabled, _coverage_lit_start, _coverage_lit_end
		)
	_sync_coverage_ui()
	_update_status()


func _stop_trigger_preview() -> void:
	if _preview_source != null and is_instance_valid(_preview_source):
		_set_source_preview_visual(_preview_source, false)
	_preview_source = null


func _set_source_preview_visual(source: Node2D, active: bool) -> void:
	if source.has_method(&"set_editor_preview_active"):
		source.call(&"set_editor_preview_active", active)


# ============================================================
# 保存 / 试玩
# ============================================================

func _write_current() -> bool:
	if LevelFileIO.write_text(_current_path, serialize()) != OK:
		_status_label.text = "保存失败：无法写入 %s" % _current_path
		return false
	_dirty = false
	_update_status()
	return true


func _on_save_dialog_confirmed() -> void:
	var file_name := _save_name_edit.text.strip_edges()
	if not LevelFileIO.validate_file_name(file_name):
		_status_label.text = "文件名不合法：应为 level_NN.tscn 或 level_NN_说明.tscn"
		return
	var manager := _level_root.get_node_or_null("LevelManager")
	if manager != null:
		var title := _save_title_edit.text.strip_edges()
		if not title.is_empty():
			manager.level_name = title
		if _next_level_option.selected > 0:
			manager.next_level_scene = load(LEVELS_DIR + "/"
					+ _next_level_option.get_item_text(_next_level_option.selected))
	# 根名随文件编号（Level06 风格）
	_level_root.name = _root_name_for_file(file_name)
	_current_path = LEVELS_DIR + "/" + file_name
	_write_current()


# ============================================================
# 光线预览
# ============================================================

func _refresh_ray_preview() -> void:
	var space := get_viewport().find_world_2d().direct_space_state
	var segment_sets: Array[PackedVector2Array] = []
	var segment_colors: Array[Array] = []
	for node in get_tree().get_nodes_in_group(LightSource.SOURCE_GROUP):
		var source := node as LightSource
		if source == null or not is_instance_valid(source):
			continue
		for trace in RayCaster.trace_all(
			space, source.global_position, source.get_light_direction(),
			source.get_light_color(), source.max_bounces
		):
			segment_sets.append(trace.segments)
			segment_colors.append(trace.segment_colors)
	_ray_renderer.set_segments(segment_sets, segment_colors)


# ============================================================
# UI 构建
# ============================================================

func _build_ui() -> void:
	_build_toolbar()
	_build_coverage_dialog()
	_build_palette()
	_build_inspector()
	_build_status_bar()
	_build_save_dialog()
	_build_open_dialog()
	_build_confirm_dialog()


func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 80.0
	_ui.add_child(bar)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	bar.add_child(rows)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	rows.add_child(box)
	var coverage_row := HBoxContainer.new()
	coverage_row.add_theme_constant_override("separation", 8)
	rows.add_child(coverage_row)
	var new_button := _make_button("新建", func() -> void: new_level())
	var open_button := _make_button("打开", func() -> void: _open_dialog.popup_centered())
	var save_button := _make_button("保存", func() -> void: save())
	var save_as_button := _make_button("另存为", func() -> void: save_as())
	_play_button = _make_button("试玩", _on_play_pressed)
	_play_button.tooltip_text = "在编辑器内运行关卡；可调整已有积木和电线，结束后保留调整。"
	for button in [new_button, open_button, save_button, save_as_button, _play_button]:
		box.add_child(button)
		_toolbar_edit_controls.append(button)
	_validation_toggle = CheckButton.new()
	_validation_toggle.text = "实时验证"
	_validation_toggle.tooltip_text = "运行光线、重力与机关；结束后恢复进入验证前的设计。"
	_validation_toggle.toggled.connect(func(active: bool) -> void:
		set_validation_mode(active))
	box.add_child(_validation_toggle)
	box.add_child(VSeparator.new())
	var grid_toggle := CheckButton.new()
	grid_toggle.text = "网格吸附"
	grid_toggle.button_pressed = _gizmo.grid_snap_enabled
	grid_toggle.toggled.connect(func(on: bool) -> void: _gizmo.grid_snap_enabled = on)
	box.add_child(grid_toggle)
	_toolbar_edit_controls.append(grid_toggle)
	var angle_toggle := CheckButton.new()
	angle_toggle.text = "角度吸附"
	angle_toggle.button_pressed = _gizmo.angle_snap_enabled
	angle_toggle.toggled.connect(func(on: bool) -> void: _gizmo.angle_snap_enabled = on)
	box.add_child(angle_toggle)
	_toolbar_edit_controls.append(angle_toggle)
	var ray_toggle := CheckButton.new()
	ray_toggle.text = "光线预览"
	ray_toggle.button_pressed = _show_ray_preview
	ray_toggle.toggled.connect(func(on: bool) -> void:
		_show_ray_preview = on
		if not on:
			_ray_renderer.set_segments([], []))
	box.add_child(ray_toggle)
	_toolbar_edit_controls.append(ray_toggle)
	box.add_child(VSeparator.new())
	var zoom_out := _make_button("−", func() -> void:
		set_view_zoom(get_view_zoom() / VIEW_ZOOM_STEP))
	zoom_out.tooltip_text = "缩小画布（也可向下滚轮）"
	box.add_child(zoom_out)
	_zoom_label = Label.new()
	_zoom_label.custom_minimum_size = Vector2(48.0, 0.0)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_zoom_label)
	var zoom_in := _make_button("＋", func() -> void:
		set_view_zoom(get_view_zoom() * VIEW_ZOOM_STEP))
	zoom_in.tooltip_text = "放大画布（也可向上滚轮）"
	box.add_child(zoom_in)
	var reset_button := _make_button("复位视图", reset_view)
	reset_button.tooltip_text = "恢复 100% 并回到关卡中心；中键或右键可拖动画布。"
	box.add_child(reset_button)
	var coverage_label := Label.new()
	coverage_label.text = "测试光线："
	coverage_row.add_child(coverage_label)
	_coverage_config_button = _make_button("有光 0°→360°", func() -> void:
		_coverage_start_spin.value = _coverage_lit_start
		_coverage_end_spin.value = _coverage_lit_end
		_coverage_dialog.popup_centered())
	_coverage_config_button.tooltip_text = "先设置有光角度区间；世界正右为 0°，区间不随光源旋转。"
	coverage_row.add_child(_coverage_config_button)
	_coverage_toggle = CheckButton.new()
	_coverage_toggle.text = "全光线覆盖"
	_coverage_toggle.tooltip_text = "仅试玩/实时验证可用；只在有光区域内每 2° 发射一束。"
	_coverage_toggle.disabled = true
	_coverage_toggle.toggled.connect(_on_coverage_toggled)
	coverage_row.add_child(_coverage_toggle)
	var coverage_hint := Label.new()
	coverage_hint.text = "先调有光区域，再在试玩或实时验证中开启；不写入关卡。"
	coverage_row.add_child(coverage_hint)
	_update_zoom_label()


func _build_coverage_dialog() -> void:
	_coverage_dialog = ConfirmationDialog.new()
	_coverage_dialog.title = "全光线覆盖：设置有光区域"
	_coverage_dialog.ok_button_text = "应用角度"
	_ui.add_child(_coverage_dialog)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(440.0, 0.0)
	_coverage_dialog.add_child(content)
	var explanation := Label.new()
	explanation.text = "角度按世界方向计算：正右 0°、正下 90°，顺时针增加；有光区域不随光源转动。\n0°→360° 表示整圈，起止相同表示无光；起点大于终点时跨过 0°。\n从起点起每 2° 发射一束光，不改变正式关卡光线。"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(explanation)
	var row := HBoxContainer.new()
	content.add_child(row)
	var start_label := Label.new()
	start_label.text = "有光起点"
	row.add_child(start_label)
	_coverage_start_spin = SpinBox.new()
	_coverage_start_spin.min_value = 0.0
	_coverage_start_spin.max_value = 360.0
	_coverage_start_spin.step = 1.0
	_coverage_start_spin.suffix = "°"
	row.add_child(_coverage_start_spin)
	var end_label := Label.new()
	end_label.text = "有光终点"
	row.add_child(end_label)
	_coverage_end_spin = SpinBox.new()
	_coverage_end_spin.min_value = 0.0
	_coverage_end_spin.max_value = 360.0
	_coverage_end_spin.step = 1.0
	_coverage_end_spin.suffix = "°"
	row.add_child(_coverage_end_spin)
	_coverage_dialog.confirmed.connect(func() -> void:
		set_full_coverage_light_range(
			_coverage_start_spin.value, _coverage_end_spin.value
		))


func _build_palette() -> void:
	_palette_panel = PanelContainer.new()
	_palette_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_palette_panel.offset_right = 240.0
	_palette_panel.offset_top = 84.0
	_palette_panel.offset_bottom = -32.0
	_ui.add_child(_palette_panel)
	var scroll := ScrollContainer.new()
	_palette_panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	for category in PaletteData.CATEGORIES:
		var title := Label.new()
		title.text = "■ %s" % category
		title.add_theme_font_size_override("font_size", 16)
		content.add_child(title)
		var grid := GridContainer.new()
		grid.columns = 3
		content.add_child(grid)
		for entry in PaletteData.entries_in_category(category):
			var button := Button.new()
			button.text = entry["label"]
			button.custom_minimum_size = Vector2(64, 36)
			button.pressed.connect(func() -> void: _on_palette_pressed(entry))
			grid.add_child(button)


func _build_inspector() -> void:
	_inspector_panel = PanelContainer.new()
	_inspector_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_inspector_panel.offset_left = -260.0
	_inspector_panel.offset_top = 84.0
	_inspector_panel.offset_bottom = -32.0
	_ui.add_child(_inspector_panel)
	var scroll := ScrollContainer.new()
	_inspector_panel.add_child(scroll)
	_inspector_content = VBoxContainer.new()
	_inspector_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inspector_content)
	_rebuild_inspector()


func _build_status_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -28.0
	_ui.add_child(bar)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	bar.add_child(_status_label)
	_update_status()


func _build_save_dialog() -> void:
	_save_dialog = ConfirmationDialog.new()
	_save_dialog.title = "保存关卡"
	_save_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	_ui.add_child(_save_dialog)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(380, 0)
	_save_dialog.add_child(content)
	var name_label := Label.new()
	name_label.text = "文件名（level_NN_说明.tscn）"
	content.add_child(name_label)
	_save_name_edit = LineEdit.new()
	content.add_child(_save_name_edit)
	var title_label := Label.new()
	title_label.text = "工坊关卡名（发布后显示在开始游戏）"
	content.add_child(title_label)
	_save_title_edit = LineEdit.new()
	content.add_child(_save_title_edit)
	var next_label := Label.new()
	next_label.text = "通关后进入"
	content.add_child(next_label)
	_next_level_option = OptionButton.new()
	_next_level_option.add_item("（无）")
	for entry in LevelFileIO.scan_levels():
		_next_level_option.add_item(entry)
	content.add_child(_next_level_option)
	_save_dialog.confirmed.connect(_on_save_dialog_confirmed)


func _build_open_dialog() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.title = "打开关卡"
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.filters = PackedStringArray(["*.tscn ; 关卡场景"])
	_open_dialog.current_dir = ProjectSettings.globalize_path(LEVELS_DIR)
	_open_dialog.file_selected.connect(_on_open_file_selected)
	_ui.add_child(_open_dialog)


func _build_confirm_dialog() -> void:
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "确认"
	_confirm_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	_ui.add_child(_confirm_dialog)


func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func _show_confirm(text: String, callback: Callable) -> void:
	_confirm_dialog.dialog_text = text
	if _confirm_callback.is_valid():
		_confirm_dialog.confirmed.disconnect(_confirm_callback)
	_confirm_callback = callback
	_confirm_dialog.confirmed.connect(callback)
	_confirm_dialog.popup_centered()


# ============================================================
# Inspector 内容
# ============================================================

func _rebuild_inspector() -> void:
	for child in _inspector_content.get_children():
		# pressed / toggled 回调中当前控件处于锁定状态，不能同步 free。
		_inspector_content.remove_child(child)
		child.queue_free()
	_spin_x = null
	_spin_y = null
	_spin_rotation = null
	_spin_scale_x = null
	_spin_scale_y = null
	if _wire_layer.selected_index >= 0:
		_build_wire_inspector()
	elif _selection == null or not is_instance_valid(_selection):
		var hint := Label.new()
		if _playtest_mode:
			hint.text = "试玩中：点击已有积木或电线修改。\n按住光源拖动可调整方向；\n结束试玩后保留设计改动，\n不会保存重力与机关的临时位移。"
		else:
			hint.text = "未选中积木\n\n点击画面中的积木选中；\n点空白处取消；\n点击电线选中电线。\n\n选中触发开关/压力传感器后，\n从它右侧出现的 ○ 端口\n拖到任意积木上即可连线；\n点击电线可配置机关动作。"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inspector_content.add_child(hint)
	else:
		_build_block_inspector()


func _build_block_inspector() -> void:
	var entry := PaletteData.find_entry_for(_selection.scene_file_path, _selection.name)
	var title := Label.new()
	title.text = "◎ %s" % entry.get("label", PaletteData.entry_label(_selection.scene_file_path))
	title.add_theme_font_size_override("font_size", 18)
	_inspector_content.add_child(title)

	_inspector_content.add_child(_section_label("变换"))
	var transform_grid := GridContainer.new()
	transform_grid.columns = 2
	_inspector_content.add_child(transform_grid)
	_spin_x = _add_spin(transform_grid, "X", _selection.position.x, 1.0, func(v: float) -> void:
		if _selection != null:
			_selection.position.x = v
			_record_playtest_component(_selection, &"position", 0, v)
			_on_selected_transform_changed())
	_spin_y = _add_spin(transform_grid, "Y", _selection.position.y, 1.0, func(v: float) -> void:
		if _selection != null:
			_selection.position.y = v
			_record_playtest_component(_selection, &"position", 1, v)
			_on_selected_transform_changed())
	var display_rotation := rad_to_deg(_selection.rotation)
	if _selection is LightSource:
		display_rotation = (_selection as LightSource).get_world_angle_degrees()
	_spin_rotation = _add_spin(transform_grid, "旋转°", display_rotation, 1.0,
			func(v: float) -> void:
				if _selection != null:
					if _selection is LightSource:
						_selection.global_rotation = deg_to_rad(v)
					else:
						_selection.rotation = deg_to_rad(v)
					_record_playtest_property(_selection, &"rotation", _selection.rotation)
					_on_selected_transform_changed())
	_spin_scale_x = _add_spin(transform_grid, "缩放X", _selection.scale.x, 0.1, func(v: float) -> void:
		if _selection != null:
			_selection.scale.x = maxf(v, SelectionGizmo.MIN_SCALE)
			_record_playtest_component(_selection, &"scale", 0, _selection.scale.x)
			_on_selected_transform_changed())
	_spin_scale_y = _add_spin(transform_grid, "缩放Y", _selection.scale.y, 0.1, func(v: float) -> void:
		if _selection != null:
			_selection.scale.y = maxf(v, SelectionGizmo.MIN_SCALE)
			_record_playtest_component(_selection, &"scale", 1, _selection.scale.y)
			_on_selected_transform_changed())
	if _selection is LightSource:
		var source := _selection as LightSource
		_inspector_content.add_child(_section_label("光源方向"))
		var direction_buttons := HBoxContainer.new()
		var turn_left := _make_button("左转", func() -> void:
			if _selection == source:
				rotate_selected(-maxf(source.rotate_step_degrees, 1.0)))
		turn_left.tooltip_text = "逆时针旋转当前“旋转步进”角度。"
		var turn_right := _make_button("右转", func() -> void:
			if _selection == source:
				rotate_selected(maxf(source.rotate_step_degrees, 1.0)))
		turn_right.tooltip_text = "顺时针旋转当前“旋转步进”角度。"
		direction_buttons.add_child(turn_left)
		direction_buttons.add_child(turn_right)
		_inspector_content.add_child(direction_buttons)
		var source_hint := Label.new()
		source_hint.text = (
			"试玩中：按住光源拖动可瞄准；Shift+拖动可移动。"
			if _playtest_mode else
			"也可拖动顶部旋转柄，或按 Q / E 调整；光路会立即刷新。"
		)
		source_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inspector_content.add_child(source_hint)

	var props: Array = entry.get("props", [])
	if not props.is_empty():
		_inspector_content.add_child(_section_label("属性"))
		var props_grid := GridContainer.new()
		props_grid.columns = 2
		_inspector_content.add_child(props_grid)
		for prop in props:
			_add_prop_control(props_grid, prop)

	var wires := _wires_for_node(_selection)
	if not _playtest_mode and _source_signal_of(_selection) != &"":
		_inspector_content.add_child(_section_label("电线"))
		var hint := Label.new()
		hint.text = "从积木右侧的 ○ 端口\n按住拖到任意积木上连线。\n点击电线可选中，Del 断开。"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		_inspector_content.add_child(hint)
		var preview_source := _selection
		var trigger_preview := CheckButton.new()
		trigger_preview.text = "模拟触发（仅预览）"
		trigger_preview.tooltip_text = "立即显示该开关全部出线的动作结果；不会写入保存文件。"
		trigger_preview.button_pressed = _preview_source == preview_source
		trigger_preview.toggled.connect(func(active: bool) -> void:
			preview_trigger_source(preview_source, active))
		_inspector_content.add_child(trigger_preview)
	if not wires.is_empty() and not _playtest_mode:
		if _source_signal_of(_selection) == &"":
			_inspector_content.add_child(_section_label("电线"))
		for pair in wires:
			_inspector_content.add_child(_make_wire_row(pair["text"], pair["index"]))

	if not _playtest_mode:
		_inspector_content.add_child(HSeparator.new())
		var delete_button := Button.new()
		delete_button.text = "删除这个积木（Del）"
		delete_button.tooltip_text = "同时移除与这个积木相连的电线；可以撤销。"
		delete_button.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
		delete_button.pressed.connect(delete_selected)
		_inspector_content.add_child(delete_button)


func _build_wire_inspector() -> void:
	var index := _wire_layer.selected_index
	var wires := _wire_layer.get_wires()
	if index < 0 or index >= wires.size():
		return
	var wire: Dictionary = wires[index]
	var link := wire["link"] as ActionLink
	if link == null:
		return
	var title := Label.new()
	title.text = "◎ 电线"
	title.add_theme_font_size_override("font_size", 18)
	_inspector_content.add_child(title)
	var info := Label.new()
	info.text = "%s.%s → %s" % [
		(wire["source"] as Node).name, wire["signal"],
		(wire["target"] as Node).name,
	]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector_content.add_child(info)

	_inspector_content.add_child(_section_label("机关动作"))
	var grid := GridContainer.new()
	grid.columns = 2
	_inspector_content.add_child(grid)
	_add_spin(grid, "水平移动 X", link.move_offset.x, 8.0, func(v: float) -> void:
		set_wire_property(index, &"move_offset", Vector2(v, link.move_offset.y), false))
	_add_spin(grid, "垂直移动 Y", link.move_offset.y, 8.0, func(v: float) -> void:
		set_wire_property(index, &"move_offset", Vector2(link.move_offset.x, v), false))
	_add_spin(grid, "旋转°", link.rotate_degrees, 15.0, func(v: float) -> void:
		set_wire_property(index, &"rotate_degrees", v, false))
	_add_spin(grid, "运动时长(秒)", link.duration, 0.1, func(v: float) -> void:
		set_wire_property(index, &"duration", v, false))
	_add_check(grid, "一直重复动作", link.repeat, func(on: bool) -> void:
		set_wire_property(index, &"repeat", on))
	_add_check(grid, "断电后恢复原状", link.restore_on_off, func(on: bool) -> void:
		set_wire_property(index, &"restore_on_off", on))

	if not _playtest_mode:
		var preview_button := Button.new()
		preview_button.text = "预览动作位"
		preview_button.toggle_mode = true
		preview_button.button_pressed = link.is_editor_preview_active()
		preview_button.tooltip_text = "打开后目标立即显示通电后的位移和旋转；关闭即回到原位。"
		preview_button.toggled.connect(func(active: bool) -> void:
			preview_wire_action(index, active))
		_inspector_content.add_child(preview_button)

	var hint := Label.new()
	hint.text = "开关 ON：机关从原位运动到动作位（位移+旋转同一动画）。\n开关 OFF：恢复原状，或停在当前位。\n预览动作位：编辑时直接查看目标结果，保存时不会写入预览位置。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.75, 0.8, 0.7))
	_inspector_content.add_child(hint)
	if not _playtest_mode:
		var delete_button := Button.new()
		delete_button.text = "断开这条电线"
		delete_button.pressed.connect(_on_wire_delete_pressed.bind(index))
		_inspector_content.add_child(delete_button)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
	return label


## 数值控件：focus 时压撤销点，改动走 apply 回调（不进撤销栈，避免拖动刷屏）
func _add_spin(parent: Container, label_text: String, value: float, step: float, apply: Callable) -> SpinBox:
	if label_text != "":
		var label := Label.new()
		label.text = label_text
		parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = -100000.0
	spin.max_value = 100000.0
	spin.step = step
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.update_on_text_changed = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value = value
	spin.value_changed.connect(func(v: float) -> void: apply.call(v))
	spin.focus_entered.connect(_push_undo)
	parent.add_child(spin)
	return spin


## 复选控件：改动走 apply 回调
func _add_check(parent: Container, label_text: String, value: bool, apply: Callable) -> void:
	if label_text != "":
		var label := Label.new()
		label.text = label_text
		parent.add_child(label)
	var check := CheckBox.new()
	check.button_pressed = value
	check.toggled.connect(func(on: bool) -> void: apply.call(on))
	parent.add_child(check)


## 改电线节点（ActionLink）的属性。push=true 时压撤销点
## （SpinBox 由 focus_entered 统一压点，这里传 false 避免刷屏）。
func set_wire_property(index: int, prop_name: StringName, value: Variant, push := true) -> void:
	var wires := _wire_layer.get_wires()
	if index < 0 or index >= wires.size():
		return
	var link := wires[index]["link"] as ActionLink
	if link == null:
		return
	if push:
		_push_undo()
	link.set(prop_name, value)
	_record_playtest_property(link, prop_name, value)
	if link.is_editor_preview_active():
		link.set_editor_preview_active(true)
	_wire_layer.queue_redraw()
	if _show_ray_preview:
		_refresh_ray_preview()
	_update_status()


## 在编辑器中直接查看电线的动作位；关闭预览即恢复目标原位。
func preview_wire_action(index: int, active: bool) -> bool:
	if _playtest_mode:
		return false
	var wires := _wire_layer.get_wires()
	if index < 0 or index >= wires.size():
		return false
	if active:
		_stop_trigger_preview()
		for i in wires.size():
			if i == index:
				continue
			var other := wires[i]["link"] as ActionLink
			if other != null and other.is_editor_preview_active():
				other.set_editor_preview_active(false)
	var link := wires[index]["link"] as ActionLink
	if link == null or not link.set_editor_preview_active(active):
		return false
	_wire_layer.queue_redraw()
	if _show_ray_preview:
		_refresh_ray_preview()
	return true


## 电线动作摘要（Inspector 列表 / 曲线标签用）
func _link_summary(link: ActionLink) -> String:
	var parts := PackedStringArray()
	parts.append("移(%d,%d)" % [int(link.move_offset.x), int(link.move_offset.y)])
	if absf(link.rotate_degrees) > 0.01:
		parts.append("转%d°" % int(link.rotate_degrees))
	parts.append("%.1fs" % link.duration)
	if link.repeat:
		parts.append("循环")
	if not link.restore_on_off:
		parts.append("不恢复")
	return " ".join(parts)


func _add_prop_control(grid: GridContainer, prop: Dictionary) -> void:
	var prop_name: StringName = prop["name"]
	var kind: StringName = prop["kind"]
	var label := Label.new()
	label.text = prop["label"]
	grid.add_child(label)
	match kind:
		&"int":
			var spin := _add_spin(
					grid, "", _selection.get(prop_name), float(prop.get("step", 1.0)),
					func(v: float) -> void:
						set_selected_property(prop_name, int(v), false))
			_configure_prop_spin(spin, prop)
		&"float":
			var spin := _add_spin(
					grid, "", _selection.get(prop_name), float(prop.get("step", 0.1)),
					func(v: float) -> void:
						set_selected_property(prop_name, v, false))
			_configure_prop_spin(spin, prop)
		&"bool":
			var check := CheckBox.new()
			check.button_pressed = _selection.get(prop_name)
			check.toggled.connect(func(on: bool) -> void:
				set_selected_property(prop_name, on))
			grid.add_child(check)
		&"color":
			var picker := ColorPickerButton.new()
			var undo_open := [false]
			picker.color = _selection.get(prop_name)
			picker.color_changed.connect(func(color: Color) -> void:
				if not undo_open[0]:
					_push_undo()
					undo_open[0] = true
				if _selection != null:
					set_selected_property(prop_name, color, false))
			picker.popup_closed.connect(func(_opened: bool) -> void:
				undo_open[0] = false)
			grid.add_child(picker)
		&"vector2":
			var box := HBoxContainer.new()
			var current: Vector2 = _selection.get(prop_name)
			_add_spin(box, "", current.x, 1.0, func(v: float) -> void:
				if _selection != null:
					var vec: Vector2 = _selection.get(prop_name)
					vec.x = v
					set_selected_property(prop_name, vec, false))
			_add_spin(box, "", current.y, 1.0, func(v: float) -> void:
				if _selection != null:
					var vec: Vector2 = _selection.get(prop_name)
					vec.y = v
					set_selected_property(prop_name, vec, false))
			grid.add_child(box)
		&"enum":
			var option := OptionButton.new()
			var options: Array = prop.get("options", [])
			for i in options.size():
				option.add_item(options[i])
			option.select(_selection.get(prop_name))
			option.item_selected.connect(func(index: int) -> void:
				set_selected_property(prop_name, index))
			grid.add_child(option)
		&"text":
			var edit := LineEdit.new()
			edit.text = str(_selection.get(prop_name))
			edit.placeholder_text = str(prop.get("placeholder", ""))
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var commit := func() -> void:
				if _selection == null:
					return
				if str(_selection.get(prop_name)) != edit.text:
					set_selected_property(prop_name, StringName(edit.text))
			edit.text_submitted.connect(func(_t: String) -> void: commit.call())
			edit.focus_exited.connect(func() -> void: commit.call())
			grid.add_child(edit)


func _configure_prop_spin(spin: SpinBox, prop: Dictionary) -> void:
	if prop.has("min"):
		spin.min_value = float(prop["min"])
	if prop.has("max"):
		spin.max_value = float(prop["max"])
	spin.suffix = str(prop.get("suffix", ""))


func _make_wire_row(text: String, wire_index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var delete_button := Button.new()
	delete_button.text = "断开"
	delete_button.pressed.connect(_on_wire_delete_pressed.bind(wire_index))
	row.add_child(delete_button)
	return row


func _wires_for_node(node: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var wires := _wire_layer.get_wires()
	for i in wires.size():
		var wire: Dictionary = wires[i]
		var summary := _link_summary(wire["link"] as ActionLink)
		if wire["source"] == node:
			result.append({
				"index": i,
				"text": "输出 → %s（%s）" % [(wire["target"] as Node).name, summary],
			})
		elif wire["target"] == node:
			result.append({
				"index": i,
				"text": "输入 ← %s.%s（%s）" % [(wire["source"] as Node).name, wire["signal"], summary],
			})
	return result


func _on_wire_delete_pressed(index: int) -> void:
	if _playtest_mode:
		return
	_push_undo()
	_wire_layer.remove_wire(index)
	_rebuild_inspector()
	_update_status()


func _refresh_inspector_transform() -> void:
	if _selection == null:
		return
	if _spin_x != null and is_instance_valid(_spin_x):
		_spin_x.set_value_no_signal(_selection.position.x)
	if _spin_y != null and is_instance_valid(_spin_y):
		_spin_y.set_value_no_signal(_selection.position.y)
	if _spin_rotation != null and is_instance_valid(_spin_rotation):
		var display_rotation := rad_to_deg(_selection.rotation)
		if _selection is LightSource:
			display_rotation = (_selection as LightSource).get_world_angle_degrees()
		_spin_rotation.set_value_no_signal(display_rotation)
	if _spin_scale_x != null and is_instance_valid(_spin_scale_x):
		_spin_scale_x.set_value_no_signal(_selection.scale.x)
	if _spin_scale_y != null and is_instance_valid(_spin_scale_y):
		_spin_scale_y.set_value_no_signal(_selection.scale.y)


func _on_selected_transform_changed() -> void:
	if _selection == null or not is_instance_valid(_selection):
		return
	_sync_wire_origins_for(_selection)
	_gizmo.queue_redraw()
	_wire_layer.queue_redraw()
	if _show_ray_preview:
		_refresh_ray_preview()
	_update_status()


func _sync_wire_origins_for(target: Node2D) -> void:
	for wire in _wire_layer.get_wires():
		if wire["target"] != target:
			continue
		var link := wire["link"] as ActionLink
		if link != null:
			link.sync_origin_from_target()


func _suspend_wire_previews() -> Array[ActionLink]:
	var previewed: Array[ActionLink] = []
	for wire in _wire_layer.get_wires():
		var link := wire["link"] as ActionLink
		if link != null and link.is_editor_preview_active():
			link.set_editor_preview_active(false)
			previewed.append(link)
	return previewed


func _resume_wire_previews(links: Array[ActionLink]) -> void:
	for link in links:
		if is_instance_valid(link):
			link.set_editor_preview_active(true)


func _restore_wire_previews() -> void:
	_suspend_wire_previews()
	_stop_trigger_preview()


# ============================================================
# 内部小工具
# ============================================================

func _update_status() -> void:
	var file_name := _current_path.get_file() if not _current_path.is_empty() else "（未保存）"
	var block_count := 0
	if _level_root != null:
		# 电线节点（ActionLink）也是实例根，但它不是积木
		block_count = LevelFileIO.walk_instance_roots(_level_root).size() - get_wire_count()
	if _validation_mode:
		_status_label.text = "实时验证中 ｜ 可拖动光源 ｜ 全光线覆盖仅作测试 ｜ Esc 结束并恢复设计"
		return
	if _playtest_mode:
		_status_label.text = "试玩中 ｜ 拖光源调方向、Shift+拖动位置 ｜ 全光线覆盖仅作测试 ｜ Esc 结束并保留编辑"
		return
	_status_label.text = "文件：%s%s ｜ 积木：%d ｜ 电线：%d ｜ 滚轮缩放 · 中/右键拖动画布 ｜ Ctrl+S 保存" % [
		file_name, " ●" if _dirty else "", block_count, get_wire_count(),
	]


func _to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _ui_has_focus() -> bool:
	return get_viewport().gui_get_focus_owner() != null


func _source_signal_of(node: Node) -> StringName:
	if node.has_signal(&"active_changed"):
		return &"active_changed"
	if node.has_signal(&"pressed_changed"):
		return &"pressed_changed"
	return &""


func _is_valid_wire_target(node: Node, signal_name: StringName) -> bool:
	# 任意积木都可以当电线目标（机关/镜面/石块/蚕茧……），电线节点本身除外
	return node != null and node is Node2D and not node is ActionLink \
			and node.scene_file_path != "" \
			and LevelFileIO.is_valid_wire(signal_name, ActionLink.METHOD_NAME)


## 目标机关是否已经有一条电线（一个目标只允许一条，避免两条电线抢同一个目标）
func _has_wire_to_target(target: Node2D) -> bool:
	for wire in _wire_layer.get_wires():
		if wire["target"] == target:
			return true
	return false


func _block_at_point(world_point: Vector2) -> Node2D:
	if _level_root == null:
		return null
	var blocks := LevelFileIO.walk_instance_roots(_level_root)
	for i in range(blocks.size() - 1, -1, -1):
		var node := blocks[i] as Node2D
		if node == null or node is ActionLink:
			continue
		var size := PaletteData.entry_size(node.scene_file_path)
		var local := (world_point - node.global_position).rotated(-node.rotation)
		local.x /= maxf(absf(node.scale.x), 0.0001)
		local.y /= maxf(absf(node.scale.y), 0.0001)
		var half := size * 0.5
		if absf(local.x) <= half.x and absf(local.y) <= half.y:
			return node
	return null


func _blocks_container() -> Node2D:
	return _level_root.get_node("Blocks") as Node2D


func _unique_block_name(base_name: String) -> String:
	var name := base_name
	var counter := 2
	while _blocks_container().has_node(name):
		name = "%s%d" % [base_name, counter]
		counter += 1
	return name


func _spawn_block_impl(
	scene_path: String, world_position: Vector2,
	preset: Dictionary = {}, entry_key: String = "",
) -> Node2D:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var block := packed.instantiate() as Node2D
	if block == null:
		return null
	var entry := PaletteData.find_entry(scene_path)
	var key: String = entry_key if not entry_key.is_empty() \
			else str(entry.get("key", scene_path.get_file().get_basename()))
	block.name = _unique_block_name(key.to_pascal_case())
	block.position = world_position
	_blocks_container().add_child(block)
	# 进树后 _ready 可能改写属性（如传送门自动配对），位置再贴一次保证准确
	block.position = world_position
	for prop in preset:
		block.set(prop, preset[prop])
	return block


## 生成电线节点（ActionLink）：挂在 Blocks 下，target_node 指向目标机关。
## 先 add_child 再设 target_node——get_path_to 需要双方同树，_ready 已跑过所以补解析。
func _spawn_link_for(target: Node2D) -> ActionLink:
	var packed := load(ACTION_LINK_SCENE) as PackedScene
	if packed == null:
		return null
	var link := packed.instantiate() as ActionLink
	if link == null:
		return null
	link.name = _unique_block_name("Wire")
	_blocks_container().add_child(link)
	link.target_node = link.get_path_to(target)
	link.resolve_target()
	return link


func _root_name_for_file(file_name: String) -> String:
	var digits := file_name.trim_prefix("level_").split("_")[0]
	return "Level" + digits


# ============================================================
# UI 事件转发
# ============================================================

func _on_palette_pressed(entry: Dictionary) -> void:
	if _level_root == null or _validation_mode:
		return
	# 相机移动后仍生成在当前视野中心，避免新积木落在屏外。
	var offset := Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0)) * GRID_SIZE
	var preset: Dictionary = entry.get("preset", {})
	var world_position := _to_world(get_viewport_rect().size * 0.5) + offset
	world_position.x = clampf(world_position.x, VIEW_RECT.position.x, VIEW_RECT.end.x)
	world_position.y = clampf(world_position.y, VIEW_RECT.position.y, VIEW_RECT.end.y)
	# 成对积木（传送门）以当前视野中心为基准生成，并让两扇门留在关卡内。
	if bool(entry.get("spawn_pair", false)):
		var half_gap := float(entry.get("pair_gap", 260.0)) * 0.5
		world_position.x = clampf(world_position.x,
			VIEW_RECT.position.x + half_gap, VIEW_RECT.end.x - half_gap)
		spawn_pair(entry, world_position)
		return
	spawn_block(entry["path"], world_position, "", preset, str(entry["key"]))


## 成对生成（传送门）：只推一次撤销，返回第一扇门。
## 第二扇默认旋转 180°（面对面），这样光从 A 正面进、B 正面出时方向保持一致。
func spawn_pair(entry: Dictionary, world_position: Vector2) -> Node2D:
	if _level_root == null or _playtest_mode:
		return null
	var scene_path := str(entry.get("path", "res://blocks/portal/portal.tscn"))
	var entry_key := str(entry.get("key", "portal"))
	var gap: float = float(entry.get("pair_gap", 260.0))
	_push_undo()
	var first := _spawn_block_impl(scene_path, world_position - Vector2(gap * 0.5, 0.0), {}, entry_key)
	var second := _spawn_block_impl(scene_path, world_position + Vector2(gap * 0.5, 0.0), {}, entry_key)
	if first == null or second == null:
		return first if first != null else second
	second.rotation = PI
	if first is Portal and second is Portal:
		var label := _next_pair_label()
		var portal_a := first as Portal
		var portal_b := second as Portal
		portal_a.pair_id = StringName(label)
		portal_b.pair_id = StringName(label)
		portal_a.linked_portal = portal_b
		portal_b.linked_portal = portal_a
		portal_a.queue_redraw()
		portal_b.queue_redraw()
	select(first)
	_update_status()
	return first


## 下一个可用的配对编号：取现有数字编号的最大值 + 1（与两扇门的距离无关，纯按编号）
func _next_pair_label() -> String:
	var highest := 0
	for node in _blocks_container().get_children():
		var portal := node as Portal
		if portal == null:
			continue
		var text := String(portal.pair_id)
		if text.is_valid_int():
			highest = maxi(highest, text.to_int())
	return str(highest + 1)


func _on_open_file_selected(path: String) -> void:
	if not _dirty:
		_do_open(path, load(path) as PackedScene)
		return
	_show_confirm("打开会丢弃未保存的改动，继续吗？", func() -> void:
		_do_open(path, load(path) as PackedScene))


func _on_play_pressed() -> void:
	set_playtest_mode(not _playtest_mode)


func _on_gizmo_transform_started() -> void:
	if _playtest_mode and _selection != null:
		_gizmo_start_transform = {
			"position": _selection.position,
			"rotation": _selection.rotation,
			"scale": _selection.scale,
		}
	_push_undo()


func _on_gizmo_transform_committed() -> void:
	if _playtest_mode and _selection != null:
		if _selection.position != _gizmo_start_transform.get("position", _selection.position):
			_record_playtest_property(_selection, &"position", _selection.position)
		if _selection.rotation != _gizmo_start_transform.get("rotation", _selection.rotation):
			_record_playtest_property(_selection, &"rotation", _selection.rotation)
		if _selection.scale != _gizmo_start_transform.get("scale", _selection.scale):
			_record_playtest_property(_selection, &"scale", _selection.scale)
		_gizmo_start_transform.clear()
	_refresh_inspector_transform()
	_on_selected_transform_changed()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
