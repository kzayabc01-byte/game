@tool
class_name WallBlock
extends StaticBody2D

## 机关墙体：完全遮光（碰撞层 1）。
## 摆进关卡后，用缩放（scale）和旋转（rotation）拼出各种墙形。
## 形状尺寸可以直接在检查器里改 CollisionShape2D 的 shape.size（每实例独立）。


func _draw() -> void:
	# 占位外观：深色墙体 + 描边
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is RectangleShape2D:
		return
	var size: Vector2 = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0
	draw_rect(Rect2(-half, size), Color(0.16, 0.18, 0.22))
	draw_rect(Rect2(-half, size), Color(0.45, 0.5, 0.6), false, 2.0)
