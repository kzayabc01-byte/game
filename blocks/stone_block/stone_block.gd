@tool
class_name StoneBlock
extends CharacterBody2D

## 石块：受重力影响的遮光重物（碰撞层 1），默认不能由玩家拖动。
## 根节点用 CharacterBody2D：重力由代码驱动，并通过运动 API 保留碰撞。
## 自动加入 heavy_objects 组（压力传感器只认这个组的物体）。
## 按 R 重置回到摆放位置。

const HEAVY_GROUP := "heavy_objects"
const RESETTABLE_GROUP := "resettables"
const GRAB_RADIUS := 44.0  # 多近可以按住拖拽

@export var gravity_enabled: bool = true
@export_range(0.0, 4.0, 0.05) var gravity_scale: float = 1.0
@export_range(100.0, 5000.0, 50.0) var terminal_speed: float = 1600.0
@export var player_draggable: bool = false

var _dragging: bool = false
var _grab_offset: Vector2 = Vector2.ZERO
var _drag_target: Vector2 = Vector2.ZERO
var _initial_position: Vector2
var _gravity: Vector2 = Vector2(0.0, 980.0)


func _enter_tree() -> void:
	add_to_group(HEAVY_GROUP)
	add_to_group(RESETTABLE_GROUP)
	collision_layer = RayCaster.LAYER_OPAQUE
	collision_mask = RayCaster.LAYER_OPAQUE


func _ready() -> void:
	_initial_position = position
	var direction: Vector2 = ProjectSettings.get_setting(
			"physics/2d/default_gravity_vector", Vector2.DOWN) as Vector2
	var strength: float = float(ProjectSettings.get_setting(
			"physics/2d/default_gravity", 980.0))
	_gravity = direction.normalized() * strength


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _dragging:
		velocity = Vector2.ZERO
		move_and_collide(_drag_target - global_position)
		return
	if not gravity_enabled:
		velocity = Vector2.ZERO
		return
	velocity += _gravity * gravity_scale * delta
	velocity = velocity.limit_length(terminal_speed)
	move_and_slide()


func reset_state() -> void:
	_dragging = false
	velocity = Vector2.ZERO
	position = _initial_position
	_drag_target = global_position


func set_build_origin() -> void:
	_initial_position = position


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not player_draggable:
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_drag_target = get_global_mouse_position() + _grab_offset
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed and global_position.distance_to(get_global_mouse_position()) <= GRAB_RADIUS:
		_dragging = true
		_grab_offset = global_position - get_global_mouse_position()
		_drag_target = global_position
		velocity = Vector2.ZERO
		get_viewport().set_input_as_handled()
	elif not button.pressed:
		_dragging = false


func _draw() -> void:
	# 材质填充由 Visual 子节点负责；这里保留轮廓和少量裂纹识别特征。
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is ConvexPolygonShape2D:
		return
	var points := (shape_node.shape as ConvexPolygonShape2D).points
	if points.size() < 3:
		return
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(0.54, 0.5, 0.44), 2.0, true)
	draw_line(Vector2(-14.0, 17.0), Vector2(2.0, -13.0), Color(0.45, 0.41, 0.36), 1.5)
	draw_line(Vector2(2.0, -13.0), Vector2(17.0, 6.0), Color(0.45, 0.41, 0.36), 1.5)
