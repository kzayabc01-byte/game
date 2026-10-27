@tool
class_name DarkSlopeBlock
extends OpaqueWallBlock
## 与 CollisionPolygon2D 共用同一轮廓的固定斜坡；视觉仅重复铺设深色石材。


func _draw() -> void:
	var collision := get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if collision == null or collision.polygon.size() < 3:
		return
	var outline := collision.polygon.duplicate()
	outline.append(collision.polygon[0])
	draw_polyline(outline, Color(0.34, 0.4, 0.46), 2.0, true)
