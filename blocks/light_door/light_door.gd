@tool
class_name LightDoor
extends LightReceiver

## 【示例机关 · 接口模板】门：被光照到后打开（收起门板）。
## - HOLD_OPEN：光照保持门开，光离开门就关闭
## - TOGGLE：照到一次就保持打开，按 R 重置才关闭
## 结构：根节点 = 感光区（碰撞层 3）；DoorPlate = 遮光门板（碰撞层 1）。
## 组员复制本文件夹改个类名，替换 on_lit / on_unlit 里的逻辑即可。

enum DoorMode { HOLD_OPEN, TOGGLE }

@export var mode: DoorMode = DoorMode.TOGGLE
@export var open_offset: Vector2 = Vector2(0, -60)
@export var move_speed: float = 160.0

@onready var _plate: AnimatableBody2D = $DoorPlate

var _latched: bool = false
var _closed_position: Vector2


func _ready() -> void:
	_closed_position = _plate.position


func _process(delta: float) -> void:
	var target := _closed_position + open_offset if _should_open() else _closed_position
	_plate.position = _plate.position.move_toward(target, move_speed * delta)
	queue_redraw()


func _should_open() -> bool:
	if mode == DoorMode.TOGGLE:
		return _latched
	return is_lit()


func on_lit() -> void:
	if mode == DoorMode.TOGGLE:
		_latched = true


func reset_state() -> void:
	_latched = false
	_plate.position = _closed_position


func _draw() -> void:
	# 占位外观：黄色门板（随 _plate 移动）+ 蓝色感光区
	var plate_shape := _plate.get_node("CollisionShape2D") as CollisionShape2D
	if plate_shape.shape is RectangleShape2D:
		var size: Vector2 = (plate_shape.shape as RectangleShape2D).size
		var center := _plate.position
		draw_rect(Rect2(center - size / 2.0, size), Color(0.55, 0.45, 0.2))
		draw_rect(Rect2(center - size / 2.0, size), Color(0.95, 0.78, 0.35), false, 2.0)
	var sensor_shape := get_node_or_null("SensorShape") as CollisionShape2D
	if sensor_shape != null and sensor_shape.shape is CircleShape2D:
		draw_circle(Vector2.ZERO, (sensor_shape.shape as CircleShape2D).radius, Color(0.25, 0.5, 0.7, 0.35))
