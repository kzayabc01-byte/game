@tool
class_name OpaqueWallBlock
extends WallBlock

## 不参与机关接线的遮光墙；使用与普通机关墙体相同的物理遮光层。


func _draw() -> void:
	# 材质填充由 Visual 负责；这里只画固定地形的冷色外轮廓。
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is RectangleShape2D:
		return
	var size: Vector2 = (shape_node.shape as RectangleShape2D).size
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, Color(0.36, 0.43, 0.5), false, 2.0)
