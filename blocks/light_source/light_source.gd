@tool
class_name LightSource
extends Node2D

## 初始点（光源）：玩家按住拖拽旋转；Q/E 步进旋转；Shift+Q/E 精细旋转。
## 直接拖进关卡即可，自动加入 light_sources 组。
## 在编辑器里旋转本节点 = 设置光线的初始方向。

signal direction_changed(angle: float)

const SOURCE_GROUP := "light_sources"
const RESETTABLE_GROUP := "resettables"

const GRAB_RADIUS := 30.0   # 多近可以按住拖拽
const BASE_RADIUS := 16.0   # 占位外观半径

@export var max_bounces: int = 12
@export var rotate_step_degrees: float = 5.0
@export var fine_step_degrees: float = 1.0
## 本光源发出光束的颜色（变色片可在中途改变颜色）
@export var light_color: Color = Color(1.0, 0.85, 0.3):
	set(value):
		light_color = value
		queue_redraw()

var _dragging: bool = false
var _initial_rotation: float = 0.0


func _enter_tree() -> void:
	add_to_group(SOURCE_GROUP)
	add_to_group(RESETTABLE_GROUP)


func _ready() -> void:
	_initial_rotation = rotation


## 光线系统从这里取光线方向
func get_light_direction() -> Vector2:
	return Vector2.RIGHT.rotated(rotation)


func reset_state() -> void:
	rotation = _initial_rotation
	direction_changed.emit(rotation)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_aim_at(get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed and global_position.distance_to(get_global_mouse_position()) <= GRAB_RADIUS:
		_dragging = true
		get_viewport().set_input_as_handled()
	elif not button.pressed:
		_dragging = false


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var step := rotate_step_degrees
	if Input.is_physical_key_pressed(KEY_SHIFT):
		step = fine_step_degrees
	if Input.is_action_just_pressed("rotate_cw"):
		_rotate_by(step)
	if Input.is_action_just_pressed("rotate_ccw"):
		_rotate_by(-step)


func _rotate_by(degrees: float) -> void:
	rotation += deg_to_rad(degrees)
	direction_changed.emit(rotation)


func _aim_at(target: Vector2) -> void:
	var previous := rotation
	rotation = (target - global_position).angle()
	if not is_equal_approx(previous, rotation):
		direction_changed.emit(rotation)


func _draw() -> void:
	# 占位外观：底座圆环 + 发光核心 + 方向箭头
	draw_circle(Vector2.ZERO, BASE_RADIUS, Color(0.13, 0.14, 0.18))
	draw_arc(Vector2.ZERO, BASE_RADIUS, 0.0, TAU, 24, Color(0.4, 0.42, 0.5), 2.0)
	draw_circle(Vector2.ZERO, BASE_RADIUS * 0.4, light_color)
	draw_line(Vector2.ZERO, Vector2.RIGHT * (BASE_RADIUS + 12.0), light_color, 4.0)
