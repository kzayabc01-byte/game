@tool
class_name RefractSurface
extends OpticalSurface

## 折射介质：光线穿过时按固定角度（或斯涅尔定律）偏折。碰撞层 4。
##
## 用法：拖进关卡，旋转本节点 = 改变偏折方向；检查器里选模式、调角度。
##   FIXED —— 恒定偏折：出射方向 = 入射方向旋转 bend_degrees（好教学，推荐先用这个）
##   SNELL —— 按折射率计算：入射角越大偏折越大（进阶关卡再用）
##
## 做成“薄片”：光线只穿一次、只偏折一次，玩家算得清；
## 厚砖会让光进出各偏一次，新手很难预期。

enum BendMode { FIXED, SNELL }

@export var mode: BendMode = BendMode.FIXED
@export var bend_degrees: float = 20.0
@export var ior: float = 1.5
@export_range(0.0, 0.9) var attenuation: float = 0.05


func on_ray(in_dir: Vector2, normal: Vector2, hit_pos: Vector2, energy: float) -> Array[Dictionary]:
	var out_dir := _bend(in_dir, normal)
	var out_energy := energy * (1.0 - attenuation)
	if out_energy < RayCaster.MIN_ENERGY:
		return []
	return [OpticalSurface.make_ray(hit_pos + out_dir * RayCaster.BOUNCE_OFFSET, out_dir, out_energy)]


## 计算偏折后的出射方向（子类可重写，冰川/变色片就靠这个扩展）
func _bend(in_dir: Vector2, normal: Vector2) -> Vector2:
	if mode == BendMode.FIXED:
		return in_dir.rotated(deg_to_rad(bend_degrees))

	# 斯涅尔：n1 = 1（空气），n2 = ior
	var n := normal
	if n.dot(in_dir) > 0.0:
		n = -n
	var cos_i := clampf(-in_dir.dot(n), -1.0, 1.0)
	var sin_t := sqrt(maxf(0.0, 1.0 - cos_i * cos_i)) / maxf(ior, 0.001)
	if sin_t >= 1.0:
		return in_dir.bounce(n)  # 理论上的全反射兜底
	var cos_t := sqrt(1.0 - sin_t * sin_t)
	return (in_dir / ior + n * (cos_i / ior - cos_t)).normalized()


func _draw() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(96.0, 8.0)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0

	# 玻璃薄片
	draw_rect(Rect2(-half, size), Color(0.45, 0.75, 0.9, 0.35))
	draw_rect(Rect2(-half, size), Color(0.70, 0.90, 1.00, 0.9), false, 2.0)

	# 法线小标记
	draw_line(Vector2.ZERO, Vector2.UP * (half.y + 18.0), Color(0.70, 0.90, 1.00, 0.5), 1.5)

	# 入射/出射示意（编辑器里能一眼看出偏折方向）
	var in_dir := Vector2.RIGHT
	var out_dir := _bend(in_dir, Vector2.UP)
	draw_line(-in_dir * 34.0, Vector2.ZERO, Color(1.0, 0.85, 0.3, 0.85), 2.0)
	draw_line(Vector2.ZERO, out_dir * 60.0, Color(1.0, 0.85, 0.3, 0.85), 2.0)
	if mode == BendMode.FIXED and not is_zero_approx(bend_degrees):
		draw_arc(Vector2.ZERO, 40.0, minf(in_dir.angle(), out_dir.angle()),
				maxf(in_dir.angle(), out_dir.angle()), 12, Color(1.0, 0.85, 0.3, 0.35), 1.5)
