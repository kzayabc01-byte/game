@tool
class_name RefractSurface
extends StaticBody2D

## 【组员接口】折射面基类：光线穿过时偏转 / 分光 / 变色。
## 用法：新建场景，根节点选 StaticBody2D，挂上「继承本类」的脚本，
## 再加一个 CollisionShape2D（碰撞层自动设为折射面，第 4 层）。
## 三种机关共用本基类：
##   折射介质：调 bend_degrees（光线穿过偏转指定角度）
##   凹透镜：  开 split（一束光分成 ±bend_degrees 两束）
##   变色机关：开 recolor（光线穿过时颜色变为 output_color）

## 穿过后的偏转角度（度）：正 = 顺时针，负 = 逆时针
@export var bend_degrees: float = 45.0
## true = 一束光分成两束（±bend_degrees，用于凹透镜）
@export var split: bool = false
## true = 光线穿过时改色（用于变色机关）
@export var recolor: bool = false
## 改色后的颜色（recolor 为 true 时生效）
@export var output_color: Color = Color(1.0, 0.3, 0.3)


func _enter_tree() -> void:
	collision_layer = RayCaster.LAYER_REFRACT
	collision_mask = 0


func _draw() -> void:
	# 占位外观：半透明青色介质 + 偏转方向箭头
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(20, 64)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0
	draw_rect(Rect2(-half, size), Color(0.3, 0.7, 0.9, 0.25))
	draw_rect(Rect2(-half, size), Color(0.5, 0.85, 1.0), false, 2.0)
	if recolor:
		draw_circle(Vector2.ZERO, minf(half.x, half.y) * 0.35, Color(output_color, 0.6))
	if split:
		draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(deg_to_rad(bend_degrees)) * 24.0, Color(0.6, 0.9, 1.0), 2.0)
		draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(deg_to_rad(-bend_degrees)) * 24.0, Color(0.6, 0.9, 1.0), 2.0)
	else:
		draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(deg_to_rad(bend_degrees)) * 24.0, Color(0.6, 0.9, 1.0), 2.0)
