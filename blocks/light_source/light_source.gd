@tool
class_name LightSource
extends Node2D

## 初始点（光源）：玩家按住拖拽旋转；Q/E 步进旋转；Shift+Q/E 精细旋转。
## 直接拖进关卡即可，自动加入 light_sources 组。
## 在编辑器里旋转本节点 = 设置光线的初始方向；读数以世界正右为 0°。

signal direction_changed(angle: float)

const SOURCE_GROUP := "light_sources"
const RESETTABLE_GROUP := "resettables"

const GRAB_RADIUS := 30.0   # 多近可以按住拖拽
const BASE_RADIUS := 16.0   # 占位外观半径
const ANGLE_FONT_SIZE := 12
const ANGLE_LABEL_OFFSET := Vector2(0.0, -36.0)

@export var max_bounces: int = 12
@export var rotate_step_degrees: float = 5.0
@export var fine_step_degrees: float = 1.0
@export var light_color: Color = Color(1.0, 0.85, 0.3)  # 初始光线颜色（触发机关可选颜色过滤）
@export var follow_mouse: bool = false
@export_category("视觉 / Visual")
@export_color_no_alpha var accent_color: Color = MechanismPalette.CYAN_GLOW:
	set(value):
		accent_color = value
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var color_concentration: float = 0.82:
	set(value):
		color_concentration = value
		queue_redraw()
@export_range(0.0, 2.0, 0.01) var glow_strength: float = 0.75:
	set(value):
		glow_strength = value
		queue_redraw()

var _initial_rotation: float = 0.0
var _aim_offset_degrees := 0.0
static var _selected_source_id: int = 0


func _enter_tree() -> void:
	add_to_group(SOURCE_GROUP)
	add_to_group(RESETTABLE_GROUP)


func _ready() -> void:
	_initial_rotation = rotation
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()


## 光线系统从这里取光线方向
func get_light_direction() -> Vector2:
	return Vector2.RIGHT.rotated(rotation)


## 光线系统从这里取光线颜色
func get_light_color() -> Color:
	return light_color


## 世界正右为 0°；屏幕顺时针方向递增。
func get_world_angle_degrees() -> float:
	return wrapf(rad_to_deg(global_rotation), 0.0, 360.0)


func get_angle_label_text() -> String:
	var degrees := posmod(roundi(get_world_angle_degrees()), 360)
	return "%d°" % degrees


func select_for_aim() -> void:
	_selected_source_id = get_instance_id()


func reset_state() -> void:
	rotation = _initial_rotation
	_aim_offset_degrees = 0.0
	direction_changed.emit(rotation)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed and global_position.distance_to(get_global_mouse_position()) <= GRAB_RADIUS:
		_selected_source_id = get_instance_id()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not follow_mouse:
		return
	if not _is_selected_source():
		return
	_aim_at(get_global_mouse_position())
	var step := rotate_step_degrees
	if Input.is_physical_key_pressed(KEY_SHIFT):
		step = fine_step_degrees
	if Input.is_action_just_pressed("rotate_cw"):
		_rotate_by(step)
	if Input.is_action_just_pressed("rotate_ccw"):
		_rotate_by(-step)


func _is_selected_source() -> bool:
	var selected := instance_from_id(_selected_source_id) as LightSource
	if selected == null or not selected.is_inside_tree():
		var sources := get_tree().get_nodes_in_group(SOURCE_GROUP)
		if not sources.is_empty():
			_selected_source_id = (sources[0] as Node).get_instance_id()
	return _selected_source_id == get_instance_id()


func _rotate_by(degrees: float) -> void:
	_aim_offset_degrees += degrees
	_aim_at(get_global_mouse_position())


func _aim_at(target: Vector2) -> void:
	var previous := rotation
	rotation = (target - global_position).angle() + deg_to_rad(_aim_offset_degrees)
	if not is_equal_approx(previous, rotation):
		direction_changed.emit(rotation)


func _draw() -> void:
	var accent := MechanismPalette.concentrate(
		MechanismPalette.MUTED_SURFACE, accent_color, color_concentration)
	draw_circle(Vector2.ZERO, BASE_RADIUS, MechanismPalette.DARK_SURFACE)
	draw_arc(Vector2.ZERO, BASE_RADIUS, 0.0, TAU, 32, Color(accent, 0.34 + glow_strength * 0.26), 5.0)
	draw_arc(Vector2.ZERO, BASE_RADIUS - 3.0, 0.0, TAU, 32, accent, 2.0)
	draw_circle(Vector2.ZERO, BASE_RADIUS * 0.43, light_color)
	draw_line(Vector2.ZERO, Vector2.RIGHT * (BASE_RADIUS + 12.0), light_color, 4.0)
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var label_text := get_angle_label_text()
	var text_size := font.get_string_size(
		label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ANGLE_FONT_SIZE
	)
	# 抵消光源旋转，避免角度读数随箭头一起倒转。
	draw_set_transform(ANGLE_LABEL_OFFSET, -global_rotation, Vector2.ONE)
	var plate := Rect2(
		Vector2(-text_size.x * 0.5 - 5.0, -text_size.y * 0.5 - 3.0),
		text_size + Vector2(10.0, 6.0)
	)
	draw_rect(plate, Color(0.05, 0.06, 0.08, 0.82))
	draw_string(
		font, Vector2(-text_size.x * 0.5, text_size.y * 0.34), label_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, ANGLE_FONT_SIZE, Color(1.0, 0.93, 0.72)
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
