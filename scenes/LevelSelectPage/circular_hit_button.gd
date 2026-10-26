@tool
extends Button

## 布局保持矩形，仅让圆盘内接收鼠标；装饰控件均忽略鼠标。
@export var hit_radius: float = 40.0


func _has_point(point: Vector2) -> bool:
	return point.distance_squared_to(size * 0.5) <= hit_radius * hit_radius
