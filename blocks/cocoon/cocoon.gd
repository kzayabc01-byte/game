@tool
class_name Cocoon
extends LightReceiver

## 结束点（蚕茧）：被光线照到的瞬间激发，触发关卡胜利。
## 直接拖进关卡即可，自动加入 cocoons 组。

signal activated

const COCOON_GROUP := "cocoons"


func _ready() -> void:
	add_to_group(COCOON_GROUP)


func on_lit() -> void:
	queue_redraw()
	activated.emit()


func on_unlit() -> void:
	queue_redraw()


func _draw() -> void:
	# 占位外观：茧形（外壳圆 + 丝线弧 + 内核），照亮后变亮
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var radius := 22.0
	if shape_node != null and shape_node.shape is CircleShape2D:
		radius = (shape_node.shape as CircleShape2D).radius
	var shell_color := Color(0.32, 0.38, 0.3, 0.6)
	var core_color := Color(0.9, 0.92, 0.75)
	if is_lit():
		shell_color = Color(0.55, 0.75, 0.4, 0.8)
		core_color = Color(1.0, 1.0, 0.6)
	draw_circle(Vector2.ZERO, radius, shell_color)
	for index in 5:
		var angle := TAU * index / 5.0
		draw_arc(Vector2.ZERO, radius * 0.72, angle, angle + PI * 0.35, 8, Color(0.75, 0.8, 0.65, 0.8), 1.5)
	draw_circle(Vector2.ZERO, radius * 0.5, core_color)
