@tool
class_name ConcaveLens
extends OpticalSurface

## 凹透镜（分束）：光线穿过时分成 split_count 束，扇面以入射方向为中心。碰撞层 4。
##
## 每束能量乘以 energy_falloff —— 分得越多越暗。
## 所以“聚光打怪 / 分光同时开门”天然是一个取舍，不用额外写规则。
## 最配“多个感光区必须同时点亮”的关卡（AND 门）。

@export_range(2, 5) var split_count: int = 3
@export var fan_degrees: float = 30.0
@export_range(0.1, 1.0) var energy_falloff: float = 0.6
@export_range(0.0, 0.9) var attenuation: float = 0.0


func on_ray(in_dir: Vector2, _normal: Vector2, hit_pos: Vector2, energy: float) -> Array[Dictionary]:
	var rays: Array[Dictionary] = []
	var count := maxi(split_count, 2)
	var out_energy := energy * (1.0 - attenuation) * energy_falloff
	if out_energy < RayCaster.MIN_ENERGY:
		return rays

	var step := fan_degrees / float(count - 1)
	var start := -fan_degrees * 0.5
	for index in count:
		var dir := in_dir.rotated(deg_to_rad(start + step * float(index)))
		rays.append(OpticalSurface.make_ray(
			hit_pos + dir * RayCaster.BOUNCE_OFFSET, dir, out_energy))
	return rays


func _draw() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(24.0, 96.0)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0
	var color := Color(0.55, 0.85, 0.95, 0.9)

	# 凹透镜：左右表面向内侧凹陷（中间薄、上下厚）。
	# 表面是一段大半径圆弧：由弦高公式反推圆心偏移与半径，弧线端点落在上下边。
	var sagitta := half.x * 0.66
	var center_offset := sagitta * 0.5 - (half.y * half.y) / (2.0 * sagitta)
	var arc_radius := absf(center_offset - sagitta)
	var arc_angle := atan2(half.y, absf(center_offset))
	draw_arc(Vector2(-half.x + center_offset, 0.0), arc_radius,
			-arc_angle, arc_angle, 18, color, 2.0)
	draw_arc(Vector2(half.x - center_offset, 0.0), arc_radius,
			PI - arc_angle, PI + arc_angle, 18, color, 2.0)
	draw_line(Vector2(-half.x, -half.y), Vector2(half.x, -half.y), color, 2.0)
	draw_line(Vector2(-half.x, half.y), Vector2(half.x, half.y), color, 2.0)

	# 分束示意
	var count := maxi(split_count, 2)
	var step := fan_degrees / float(count - 1)
	var start := -fan_degrees * 0.5
	for index in count:
		var dir := Vector2.RIGHT.rotated(deg_to_rad(start + step * float(index)))
		draw_line(Vector2.ZERO, dir * (half.x + 42.0), Color(1.0, 0.85, 0.3, 0.55), 1.5)
