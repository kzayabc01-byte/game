@tool
class_name RefractSurface
extends OpticalSurface

## 【组员接口】折射面基类（碰撞层 4）：光线穿过时偏转 / 分光 / 变色。
## 用法：新建场景，根节点选 StaticBody2D，挂上「继承本类」的脚本，
## 再加一个 CollisionShape2D（碰撞层由基类自动设置）。
## 参数覆盖三种机关：
##   折射介质：调 bend_degrees（光线穿过偏转指定角度，正 = 顺时针）
##   凹透镜：  开 split（一束光分成 ±bend_degrees 两束）
##   变色机关：开 recolor（光线穿过时颜色变为 output_color）
## 进阶：mode 选 SNELL 按折射率偏折；attenuation 控制能量损耗（契约：折射 ×0.95）。

enum BendMode { FIXED, SNELL }

## FIXED = 恒定偏折（好教学）；SNELL = 按折射率计算（进阶关卡）
@export var mode: BendMode = BendMode.FIXED
## 穿过后的偏转角度（度）：正 = 顺时针，负 = 逆时针
@export var bend_degrees: float = 20.0
## SNELL 模式下的折射率（空气 n1 = 1）
@export var ior: float = 1.5
## 能量损耗比例：出射能量 = 入射 ×(1-attenuation)
@export_range(0.0, 0.9) var attenuation: float = 0.05
## true = 一束光分成两束（±bend_degrees，用于凹透镜）
@export var split: bool = false
## true = 光线穿过时改色（用于变色机关）
@export var recolor: bool = false
## 改色后的颜色（recolor 为 true 时生效）
@export var output_color: Color = Color(1.0, 0.3, 0.3)


func _enter_tree() -> void:
	collision_layer = RayCaster.LAYER_REFRACT
	collision_mask = 0


## 光路契约入口（由 RayCaster 调用）：返回 0..N 条出射光线
func on_ray(in_dir: Vector2, normal: Vector2, hit_pos: Vector2, energy: float) -> Array[Dictionary]:
	var out_energy := energy * (1.0 - attenuation)
	if out_energy < RayCaster.MIN_ENERGY:
		return []
	var rays: Array[Dictionary] = []
	if split:
		var split_energy := out_energy * 0.6  # 契约：分束 ×0.6
		if split_energy < RayCaster.MIN_ENERGY:
			return []
		var half := deg_to_rad(bend_degrees)
		for rotated_by in [half, -half]:
			var dir := in_dir.rotated(rotated_by)
			rays.append(_make_out(hit_pos, dir, split_energy))
		return rays
	rays.append(_make_out(hit_pos, _bend(in_dir, normal), out_energy))
	return rays


func _make_out(hit_pos: Vector2, out_dir: Vector2, out_energy: float) -> Dictionary:
	var out := OpticalSurface.make_ray(
			hit_pos + out_dir * RayCaster.BOUNCE_OFFSET, out_dir, out_energy)
	if recolor:
		out["color"] = output_color  # 契约扩展字段：RayCaster 会把它带给后续光线
	return out


## 计算偏折后的出射方向（子类可重写，冰川就靠这个扩展）
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
	# 材质填充由 Visual 子节点负责；这里保留边线和偏折方向示意。
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(96.0, 8.0)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0

	draw_rect(Rect2(-half, size), Color(0.70, 0.90, 1.00, 0.9), false, 2.0)

	# 法线小标记
	draw_line(Vector2.ZERO, Vector2.UP * (half.y + 18.0), Color(0.70, 0.90, 1.00, 0.5), 1.5)

	# 入射/出射示意
	var in_dir := Vector2.RIGHT
	draw_line(-in_dir * 34.0, Vector2.ZERO, Color(1.0, 0.85, 0.3, 0.85), 2.0)
	if split:
		var half_bend := deg_to_rad(bend_degrees)
		draw_line(Vector2.ZERO, in_dir.rotated(half_bend) * 60.0, Color(1.0, 0.85, 0.3, 0.85), 2.0)
		draw_line(Vector2.ZERO, in_dir.rotated(-half_bend) * 60.0, Color(1.0, 0.85, 0.3, 0.85), 2.0)
		return
	var out_dir := _bend(in_dir, Vector2.UP)
	draw_line(Vector2.ZERO, out_dir * 60.0, Color(1.0, 0.85, 0.3, 0.85), 2.0)
	if mode == BendMode.FIXED and not is_zero_approx(bend_degrees):
		draw_arc(Vector2.ZERO, 40.0, minf(in_dir.angle(), out_dir.angle()),
				maxf(in_dir.angle(), out_dir.angle()), 12, Color(1.0, 0.85, 0.3, 0.35), 1.5)
