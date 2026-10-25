@tool
class_name Glacier
extends RefractSurface

## 冰川：会折射光线的冰，但被**足够强的光**持续照射才会融化；融化后光线直接穿过。碰撞层 4。
##
## 玩法：冰是“会消失的折射体”——想清楚先融哪一块，因为融化会永久改变光路。
## 关键：`required_energy`（默认 1.5）是能量门槛。
##   光源 1.0 的直接光融不动；只有经过**凸透镜**增强（×1.8）的光才够；
##   凹透镜分出来的弱光（×0.6）永远融不动 —— 聚光与分光因此成为取舍。
## 按 R 重置会复原；断光就暂停融化。

signal melted

const RESETTABLE_GROUP := "resettables"

@export var melt_seconds: float = 3.0
@export_range(0.1, 3.0) var melt_efficiency: float = 1.0
## 融化所需的入射能量下限：低于它的光只会穿过/折射，不会融化
@export var required_energy: float = 1.5

var _progress: float = 0.0
var _hit_frame: int = -1
var _hit_energy: float = 0.0
var _melted: bool = false
var _initial_layer: int = 8
var _pulse_pending := false


func _enter_tree() -> void:
	add_to_group(RESETTABLE_GROUP)


func _ready() -> void:
	_initial_layer = collision_layer


## 光线命中：记下“这一帧被照到”，然后照常折射
func on_ray(in_dir: Vector2, normal: Vector2, hit_pos: Vector2, energy: float) -> Array[Dictionary]:
	if _melted:
		return []
	record_ray_hit(energy)
	return super.on_ray(in_dir, normal, hit_pos, energy)


func on_ray_preview(in_dir: Vector2, normal: Vector2, hit_pos: Vector2, energy: float) -> Array[Dictionary]:
	if _melted:
		return []
	return super.on_ray(in_dir, normal, hit_pos, energy)


func record_ray_hit(energy: float) -> void:
	var current_frame := Engine.get_physics_frames()
	_hit_energy = maxf(_hit_energy, energy) if _hit_frame == current_frame else energy
	_hit_frame = current_frame
	_pulse_pending = true
	queue_redraw()


func commit_pulse_hit(pulse_seconds: float) -> void:
	if not _pulse_pending or _melted:
		return
	_pulse_pending = false
	_hit_frame = -1
	if _hit_energy >= required_energy:
		_progress += pulse_seconds * _hit_energy * melt_efficiency / maxf(melt_seconds, 0.01)
		if _progress >= 1.0:
			_melt()
	_hit_energy = 0.0
	queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _melted:
		return
	if Engine.get_physics_frames() - _hit_frame > 2:
		return  # 连续两帧没被照到：融化暂停
	if _hit_energy < required_energy:
		return  # 能量不够（比如没经过凸透镜）：不融化，只透光
	_progress += delta * _hit_energy * melt_efficiency / maxf(melt_seconds, 0.01)
	if _progress >= 1.0:
		_melt()


## 当前是否“被照亮但能量不足”（给外观提示和测试用）
func is_underpowered() -> bool:
	return not _melted and Engine.get_physics_frames() - _hit_frame <= 2 \
			and _hit_energy < required_energy


## 当前融化进度（0..1），给测试和 UI 用
func get_progress() -> float:
	return _progress


func is_melted() -> bool:
	return _melted


func _melt() -> void:
	_melted = true
	_progress = 1.0
	collision_layer = 0  # 光线直接穿过
	_disable_shapes(true)
	queue_redraw()
	melted.emit()


func reset_state() -> void:
	_melted = false
	_progress = 0.0
	_hit_frame = -1
	_hit_energy = 0.0
	_pulse_pending = false
	collision_layer = _initial_layer
	_disable_shapes(false)
	queue_redraw()


func _disable_shapes(disabled: bool) -> void:
	for child in get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred("disabled", disabled)


func _draw() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(64.0, 64.0)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0
	var alpha := 0.75 * (1.0 - _progress)
	var body := Color(0.62, 0.86, 1.0, alpha)

	draw_rect(Rect2(-half, size), body)
	draw_rect(Rect2(-half, size), Color(0.85, 0.95, 1.0, maxf(alpha, 0.15)), false, 2.0)

	if _melted:
		# 化掉之后只剩一圈水痕
		draw_rect(Rect2(-half, size), Color(0.45, 0.6, 0.75, 0.18), false, 1.0)
		return

	# 裂纹随进度变多
	var cracks := int(_progress * 4.0)
	for index in cracks:
		var offset := Vector2(-half.x + size.x * (float(index) + 0.5) / maxf(float(cracks), 1.0), -half.y)
		draw_line(offset, offset + Vector2(size.x * 0.15, size.y * 0.45), Color(0.95, 1.0, 1.0, 0.7), 1.5)

	# 被照亮但能量不够：画一圈橙色警示弧（提示“要用凸透镜聚光”）
	if is_underpowered():
		var radius: float = maxf(half.x, half.y) + 6.0
		for index in 3:
			var start := TAU * float(index) / 3.0
			draw_arc(Vector2.ZERO, radius, start, start + TAU / 6.0, 10,
					Color(1.0, 0.68, 0.25, 0.9), 2.5)
