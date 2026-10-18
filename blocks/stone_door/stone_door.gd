@tool
class_name StoneDoor
extends LightReceiver

## 石门机关：厚重石闸，被光照到（或外部机关通电）后缓缓升起。
## - HOLD_OPEN：光照保持门开，光离开门就关闭
## - TOGGLE：照到一次就保持打开，按 R 重置才关闭
## - set_external_open(value)：外部开关入口（压力传感器 pressed_changed / 触发机关 active_changed 连线用）
## 结构：根节点 = 感光区（碰撞层 3）；DoorPlate = 石门板（碰撞层 1）。
## 注意：外部开关状态不在这里重置——信号源（传感器/触发机关）重置时会重发当前状态。

enum DoorMode { HOLD_OPEN, TOGGLE }

@export var mode: DoorMode = DoorMode.HOLD_OPEN
@export var open_offset: Vector2 = Vector2(0, -60)
@export var move_speed: float = 80.0  # 石门比普通门慢，更"重"

@onready var _plate: AnimatableBody2D = $DoorPlate

var _latched: bool = false
var _external_open: bool = false
var _closed_position: Vector2


func _ready() -> void:
	_closed_position = _plate.position


func _process(delta: float) -> void:
	var target := _closed_position + open_offset if _should_open() else _closed_position
	_plate.position = _plate.position.move_toward(target, move_speed * delta)
	queue_redraw()


## 石门是否已完全打开（供测试 / 关卡逻辑查询）
func is_open() -> bool:
	return _plate.position.distance_to(_closed_position) > 1.0


## 外部开关入口：压力传感器 pressed_changed / 触发机关 active_changed 连线用
func set_external_open(value: bool) -> void:
	_external_open = value


func _should_open() -> bool:
	if mode == DoorMode.TOGGLE:
		return _latched or _external_open
	return is_lit() or _external_open


func on_lit() -> void:
	if mode == DoorMode.TOGGLE:
		_latched = true


func reset_state() -> void:
	_latched = false
	_plate.position = _closed_position


func _draw() -> void:
	# 占位外观：灰色石门板（随 _plate 移动）+ 蓝色感光区
	var plate_shape := _plate.get_node("CollisionShape2D") as CollisionShape2D
	if plate_shape.shape is RectangleShape2D:
		var size: Vector2 = (plate_shape.shape as RectangleShape2D).size
		var center := _plate.position
		draw_rect(Rect2(center - size / 2.0, size), Color(0.38, 0.36, 0.33))
		draw_rect(Rect2(center - size / 2.0, size), Color(0.62, 0.58, 0.52), false, 2.0)
		draw_line(center + Vector2(-size.x * 0.3, -size.y * 0.15), center + Vector2(size.x * 0.3, -size.y * 0.15), Color(0.5, 0.47, 0.42), 2.0)
		draw_line(center + Vector2(-size.x * 0.3, size.y * 0.15), center + Vector2(size.x * 0.3, size.y * 0.15), Color(0.5, 0.47, 0.42), 2.0)
	var sensor_shape := get_node_or_null("SensorShape") as CollisionShape2D
	if sensor_shape != null and sensor_shape.shape is CircleShape2D:
		draw_circle(Vector2.ZERO, (sensor_shape.shape as CircleShape2D).radius, Color(0.25, 0.5, 0.7, 0.35))
