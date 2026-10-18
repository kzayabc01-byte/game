@tool
class_name ColorChanger
extends OpticalSurface

## 【颜色组 · 变色机关】变色片：把照到它的光染成 recolor 颜色再射出去。
## 不改方向、不衰减（薄片思路：光只穿一次、只变一次色）。
##
## 用法：拖进关卡，检查器里改 recolor = 想要的颜色（默认红色）。
## recolor 设为透明 = 不变色（等价于纯玻璃片）。
## 依赖契约：出射光线可选 "color" 字段（OpticalSurface v1 扩展，框架已支持）。


func _enter_tree() -> void:
	collision_layer = RayCaster.LAYER_OPTIC
	collision_mask = 0


@export var recolor: Color = Color(1, 0, 0, 1):
	set(value):
		recolor = value
		queue_redraw()


func on_ray(in_dir: Vector2, _normal: Vector2, hit_pos: Vector2, energy: float) -> Array[Dictionary]:
	var origin := hit_pos + in_dir * RayCaster.BOUNCE_OFFSET
	if recolor.a > 0.0:
		return [OpticalSurface.make_ray(origin, in_dir, energy, recolor)]
	return [OpticalSurface.make_ray(origin, in_dir, energy)]


func _draw() -> void:
	# 占位外观：半透明色片 + 描边，颜色随 recolor
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(64.0, 8.0)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0
	var tint := recolor if recolor.a > 0.0 else Color(0.8, 0.8, 0.8)

	draw_rect(Rect2(-half, size), Color(tint, 0.4))
	draw_rect(Rect2(-half, size), Color(tint, 0.9), false, 2.0)
