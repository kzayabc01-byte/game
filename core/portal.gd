@tool
class_name Portal
extends StaticBody2D

## 【组员接口】传送门基类：光线命中后从 linked_portal 的位置继续，
## 方向按两扇门的相对旋转换算（进 A 的角度 = 出 B 的角度），双向互传。
## 用法：新建场景，根节点选 StaticBody2D，挂上「继承本类」的脚本，
## 再加一个 CollisionShape2D（碰撞层自动设为传送门，第 5 层）。
## 关卡里放两扇门，把彼此的 linked_portal 互指即可；不配对的门会吞掉光线。

@export var linked_portal: Portal


func _enter_tree() -> void:
	collision_layer = RayCaster.LAYER_PORTAL
	collision_mask = 0


func _draw() -> void:
	# 占位外观：紫色门面 + 中心旋涡
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(20, 64)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0
	draw_rect(Rect2(-half, size), Color(0.6, 0.35, 0.9, 0.35))
	draw_rect(Rect2(-half, size), Color(0.8, 0.6, 1.0), false, 2.0)
	draw_circle(Vector2.ZERO, minf(half.x, half.y) * 0.4, Color(0.85, 0.65, 1.0, 0.5))
