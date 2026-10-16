@tool
class_name MirrorBlock
extends StaticBody2D

## 镜面：反射光线（碰撞层 2，正反两面都能反射）。
## 旋转本节点 = 改变镜面朝向。


func _draw() -> void:
	# 占位外观：银色镜面 + 法线小标记
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is RectangleShape2D:
		return
	var size: Vector2 = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0
	draw_rect(Rect2(-half, size), Color(0.55, 0.6, 0.68))
	draw_rect(Rect2(-half, size), Color(0.85, 0.9, 0.95), false, 2.0)
	draw_line(Vector2.ZERO, Vector2.UP * half.y * 0.6, Color(0.9, 0.95, 1.0), 2.0)
