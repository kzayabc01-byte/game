@tool
class_name LightDoor
extends Node2D

## 光门机关：纯执行器，自己不会感光也不会动。
## 动作（移多少 / 转多少 / 时长 / 循环 / 恢复）全部由连接它的电线（ActionLink）决定，
## 电线把门整体从原位移到动作位，DoorPlate 跟随。
## 结构：根节点 = 位置锚点；DoorPlate = 遮光门板（碰撞层 1）。

@onready var _plate: StaticBody2D = $DoorPlate

var _origin_position := Vector2.ZERO
var _origin_rotation := 0.0


func _ready() -> void:
	_origin_position = position
	_origin_rotation = rotation


## 门是否离开原位（供测试 / 关卡逻辑查询；电线位移或旋转任一发生即算开）
func is_open() -> bool:
	return position.distance_to(_origin_position) > 1.0 \
			or absf(angle_difference(rotation, _origin_rotation)) > 0.01


func _draw() -> void:
	# 占位外观：黄色门板（DoorPlate 常驻本地偏移，整体随根节点移动）
	var plate_shape := _plate.get_node("CollisionShape2D") as CollisionShape2D
	if plate_shape.shape is RectangleShape2D:
		var size: Vector2 = (plate_shape.shape as RectangleShape2D).size
		var center := _plate.position
		draw_rect(Rect2(center - size / 2.0, size), Color(0.55, 0.45, 0.2))
		draw_rect(Rect2(center - size / 2.0, size), Color(0.95, 0.78, 0.35), false, 2.0)
