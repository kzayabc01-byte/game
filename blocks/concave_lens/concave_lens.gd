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
	var art := get_node_or_null("Art") as Sprite2D
	if art != null and art.texture != null:
		return
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(24.0, 96.0)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0
	var color := Color(0.55, 0.85, 0.95, 0.9)

	# 贴图缺失时仍提供可读的编辑器占位轮廓。
	var outline := PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x * 0.58, -half.y * 0.66), Vector2(half.x * 0.34, 0.0),
		Vector2(half.x * 0.58, half.y * 0.66), Vector2(half.x, half.y),
		Vector2(-half.x, half.y), Vector2(-half.x * 0.58, half.y * 0.66),
		Vector2(-half.x * 0.34, 0.0), Vector2(-half.x * 0.58, -half.y * 0.66),
		Vector2(-half.x, -half.y),
	])
	draw_polyline(outline, color, 2.0, true)
