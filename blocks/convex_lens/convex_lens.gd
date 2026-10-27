@tool
class_name ConvexLens
extends OpticalSurface

## 凸透镜（聚光）：光线穿过时被聚焦 —— **能量放大、光柱变细，方向不变**。碰撞层 4。
##
## 玩法：只有经过它增强的光（能量 ≥ 冰川的 required_energy）才能融化冰川；
## 凹透镜分出来的弱光则永远融不动。于是“聚光还是分光”变成真正的取舍。
##
## 参数：
##   focus_gain  能量倍数（默认 1.8；多枚叠加，受 RayCaster.MAX_ENERGY=4 限制）
##   beam_narrow 光柱宽度倍数（默认 0.45，越小越细）
##   attenuation 额外能量损耗（默认 0）

@export var focus_gain: float = 1.8
@export_range(0.05, 1.0) var beam_narrow: float = 0.45
@export_range(0.0, 0.9) var attenuation: float = 0.0


func _enter_tree() -> void:
	collision_layer = RayCaster.LAYER_REFRACT
	collision_mask = 0


func on_ray(in_dir: Vector2, _normal: Vector2, hit_pos: Vector2, energy: float) -> Array[Dictionary]:
	var out_energy := minf(energy * focus_gain, RayCaster.MAX_ENERGY) * (1.0 - attenuation)
	if out_energy < RayCaster.MIN_ENERGY:
		return []
	var out := OpticalSurface.make_ray(
			hit_pos + in_dir * RayCaster.BOUNCE_OFFSET, in_dir, out_energy)
	out["width"] = beam_narrow   # 约定：宽度字段是“倍数”，多枚透镜会继续变细
	out["break"] = true          # 宽度变了，必须断开折线渲染器才会换线宽
	return [out]


func _draw() -> void:
	var art := get_node_or_null("Art") as Sprite2D
	if art != null and art.texture != null:
		return
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(24.0, 96.0)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0
	var color := Color(0.45, 0.95, 0.85, 0.95)

	# 贴图缺失时仍提供可读的编辑器占位轮廓。
	var outline := PackedVector2Array([
		Vector2(-half.x * 0.17, -half.y), Vector2(half.x * 0.17, -half.y),
		Vector2(half.x * 0.67, -half.y * 0.75), Vector2(half.x, 0.0),
		Vector2(half.x * 0.67, half.y * 0.75), Vector2(half.x * 0.17, half.y),
		Vector2(-half.x * 0.17, half.y), Vector2(-half.x * 0.67, half.y * 0.75),
		Vector2(-half.x, 0.0), Vector2(-half.x * 0.67, -half.y * 0.75),
		Vector2(-half.x * 0.17, -half.y),
	])
	draw_polyline(outline, color, 2.0, true)
