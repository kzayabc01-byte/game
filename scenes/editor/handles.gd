class_name SelectionGizmo
extends Node2D

## 选中积木的变换手柄（仅编辑器）：
## - 主体拖动 = 整体移动（32px 网格吸附）
## - 4 角方块 = 对角锚点缩放（防零除，最小 0.1）
## - 顶部圆钮 = 绕积木中心旋转（15° 吸附）
## - 背景 32px 网格（随「网格吸附」开关一起显示）
## 拖动经 transform_started（压撤销点）/ transform_committed 汇报给编辑器；
## 编辑器负责输入分派，本类只认 hit_test / begin_drag / update_drag / end_drag。

signal transform_started
signal transform_committed

enum DragMode { NONE, MOVE, SCALE_TL, SCALE_TR, SCALE_BL, SCALE_BR, ROTATE }

const GRID_SIZE := 32.0
const HANDLE_SIZE := 7.0
const KNOB_DISTANCE := 44.0
const ROTATE_SNAP_DEGREES := 15.0
const MIN_SCALE := 0.1
const SCALE_SNAP_STEP := 0.01
const ACCENT_COLOR := Color(0.35, 0.8, 1.0)
const HANDLE_COLOR := Color(1, 1, 1)

## 关卡画面区域（网格覆盖范围），编辑器启动时设置
var view_rect := Rect2(0, 0, 1152, 648):
	set(value):
		view_rect = value
		queue_redraw()

var grid_snap_enabled := true:
	set(value):
		grid_snap_enabled = value
		queue_redraw()

var angle_snap_enabled := true

var _target: Node2D = null
var _target_size := Vector2(64, 64)
var _drag_mode := DragMode.NONE
var _drag_start_mouse := Vector2.ZERO
var _drag_start_position := Vector2.ZERO
var _drag_start_scale := Vector2.ONE
var _drag_start_rotation := 0.0
var _drag_start_pointer_angle := 0.0
# 缩放锚点（对角，世界坐标）与角点全量局部偏移（含起始缩放，未含旋转）
var _scale_anchor_world := Vector2.ZERO
var _scale_anchor_full := Vector2.ZERO
var _scale_corner_full := Vector2.ZERO


func set_target(node: Node2D) -> void:
	if _target == node:
		return
	if _drag_mode != DragMode.NONE:
		_end_drag()
	_target = node
	_target_size = PaletteData.entry_size(node.scene_file_path) if node != null else Vector2(64, 64)
	queue_redraw()


func get_target() -> Node2D:
	return _target


func is_dragging() -> bool:
	return _drag_mode != DragMode.NONE


## 命中测试：点中旋转钮 > 缩放柄 > 主体。返回 DragMode，没有命中返回 NONE。
func hit_test(world_point: Vector2) -> DragMode:
	if _target == null or not is_instance_valid(_target):
		return DragMode.NONE
	var corners := _corners_world()
	var knob_center := _knob_center(corners)
	if world_point.distance_to(knob_center) <= KNOB_DISTANCE * 0.5:
		return DragMode.ROTATE
	var modes: Array[DragMode] = [
		DragMode.SCALE_TL, DragMode.SCALE_TR, DragMode.SCALE_BR, DragMode.SCALE_BL,
	]
	for i in corners.size():
		if world_point.distance_to(corners[i]) <= HANDLE_SIZE + 5.0:
			return modes[i]
	if _point_in_rotated_rect(world_point):
		return DragMode.MOVE
	return DragMode.NONE


## 开始拖动（命中后调用），成功后发 transform_started
func begin_drag(mode: DragMode, world_point: Vector2) -> bool:
	if _target == null or not is_instance_valid(_target) or mode == DragMode.NONE:
		return false
	_drag_mode = mode
	_drag_start_mouse = world_point
	_drag_start_position = _target.position
	_drag_start_scale = _target.scale
	_drag_start_rotation = _target.rotation
	if mode == DragMode.ROTATE:
		_drag_start_pointer_angle = (world_point - _target.global_position).angle()
	elif mode != DragMode.MOVE:
		# 锚点 = 对角（世界坐标，拖动全程不动）
		var own_index := 0
		match mode:
			DragMode.SCALE_TL: own_index = 0
			DragMode.SCALE_TR: own_index = 1
			DragMode.SCALE_BR: own_index = 2
			DragMode.SCALE_BL: own_index = 3
		var anchor_base := _corner_base((own_index + 2) % 4)
		var drag_corner_base := _corner_base(own_index)
		_scale_anchor_full = anchor_base * _drag_start_scale
		_scale_corner_full = drag_corner_base * _drag_start_scale
		_scale_anchor_world = _target.global_position \
				+ _scale_anchor_full.rotated(_drag_start_rotation)
	transform_started.emit()
	queue_redraw()
	return true


func update_drag(world_point: Vector2) -> void:
	if _drag_mode == DragMode.NONE or _target == null:
		return
	match _drag_mode:
		DragMode.MOVE:
			var delta := world_point - _drag_start_mouse
			var new_position := _drag_start_position + delta
			if grid_snap_enabled:
				new_position = new_position.snapped(Vector2(GRID_SIZE, GRID_SIZE))
			_target.position = new_position
		DragMode.ROTATE:
			var pointer_angle := (world_point - _target.global_position).angle()
			var new_rotation := _drag_start_rotation + pointer_angle - _drag_start_pointer_angle
			if angle_snap_enabled:
				new_rotation = snappedf(new_rotation, deg_to_rad(ROTATE_SNAP_DEGREES))
			_target.rotation = new_rotation
		_:
			_apply_scale(world_point)
	queue_redraw()


func end_drag() -> void:
	_end_drag()


# ---------- 内部实现 ----------


func _end_drag() -> void:
	if _drag_mode == DragMode.NONE:
		return
	_drag_mode = DragMode.NONE
	transform_committed.emit()
	queue_redraw()


## 本地基角（未缩放）：0=左上 1=右上 2=右下 3=左下
func _corner_base(index: int) -> Vector2:
	var half := _target_size * 0.5
	match index:
		0: return Vector2(-half.x, -half.y)
		1: return Vector2(half.x, -half.y)
		2: return Vector2(half.x, half.y)
		_: return Vector2(-half.x, half.y)


func _corners_world() -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in 4:
		result.append(_target.global_position
				+ (_corner_base(i) * _target.scale).rotated(_target.rotation))
	return result


func _knob_center(corners: PackedVector2Array) -> Vector2:
	var top_center := (corners[0] + corners[1]) * 0.5
	return top_center + Vector2.UP.rotated(_target.rotation) * KNOB_DISTANCE


func _point_in_rotated_rect(world_point: Vector2) -> bool:
	var local := (world_point - _target.global_position).rotated(-_target.rotation)
	local.x /= _target.scale.x
	local.y /= _target.scale.y
	var half := _target_size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y


func _apply_scale(world_point: Vector2) -> void:
	# 鼠标转目标本地系（去旋转），求相对锚点的分量比 → 新缩放；
	# 分母是「角点全量 - 锚点全量」，恒非零（对角 + 最小缩放钳制）
	var mouse_local := (world_point - _target.global_position).rotated(-_target.rotation)
	var ratio := (mouse_local - _scale_anchor_full) / (_scale_corner_full - _scale_anchor_full)
	var new_scale := _drag_start_scale * ratio
	new_scale.x = maxf(new_scale.x, MIN_SCALE)
	new_scale.y = maxf(new_scale.y, MIN_SCALE)
	new_scale = new_scale.snapped(Vector2(SCALE_SNAP_STEP, SCALE_SNAP_STEP))
	# 缩放绕锚点进行：锚点不动，位置随之修正
	_target.scale = new_scale
	_target.position = _scale_anchor_world \
			- (_scale_anchor_full * (new_scale / _drag_start_scale)).rotated(_target.rotation)


func _draw() -> void:
	_draw_grid()
	if _target == null or not is_instance_valid(_target):
		return
	var corners := _corners_world()
	# 选中框：半透明填充 + 描边
	var fill := Color(ACCENT_COLOR, 0.08)
	draw_colored_polygon(corners, fill)
	for i in 4:
		draw_line(corners[i], corners[(i + 1) % 4], ACCENT_COLOR, 1.5)
	# 中心十字
	draw_line(_target.global_position - Vector2(6, 0), _target.global_position + Vector2(6, 0), ACCENT_COLOR, 1.5)
	draw_line(_target.global_position - Vector2(0, 6), _target.global_position + Vector2(0, 6), ACCENT_COLOR, 1.5)
	# 4 角缩放柄
	for corner in corners:
		_draw_handle(corner, HANDLE_COLOR)
	# 旋转钮：上缘 → 圆钮
	var top_center := (corners[0] + corners[1]) * 0.5
	var knob_center := _knob_center(corners)
	draw_line(top_center, knob_center, ACCENT_COLOR, 1.5)
	draw_circle(knob_center, 8.0, ACCENT_COLOR)
	draw_circle(knob_center, 3.5, Color(0.1, 0.15, 0.2))


func _draw_handle(center: Vector2, color: Color) -> void:
	draw_rect(Rect2(center - Vector2(HANDLE_SIZE, HANDLE_SIZE),
			Vector2(HANDLE_SIZE, HANDLE_SIZE) * 2.0), Color(0.05, 0.06, 0.08), true)
	draw_rect(Rect2(center - Vector2(HANDLE_SIZE, HANDLE_SIZE) * 0.7,
			Vector2(HANDLE_SIZE, HANDLE_SIZE) * 1.4), color, true)


func _draw_grid() -> void:
	if not grid_snap_enabled:
		return
	var grid_color := Color(0.3, 0.36, 0.45, 0.25)
	var end := view_rect.end
	for x in range(0, int(end.x) + 1, GRID_SIZE):
		draw_line(Vector2(x, view_rect.position.y), Vector2(x, end.y), grid_color, 1.0)
	for y in range(0, int(end.y) + 1, GRID_SIZE):
		draw_line(Vector2(view_rect.position.x, y), Vector2(end.x, y), grid_color, 1.0)
