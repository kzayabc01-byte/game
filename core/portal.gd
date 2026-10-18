@tool
class_name Portal
extends OpticalSurface

## 【组员接口】传送门基类（碰撞层 5）：光线从 A 进、从 B 出。一对门互设 linked_portal。
## 出射方向默认“保角”：按两个门的旋转差旋转入射方向（进 A 的角度 = 出 B 的角度）；
## 打开 mirror_out 则按出口法线镜像（能做“不可能光路”）。
## 每条光线对每个门只会穿越一次（防环由 RayCaster 负责）。
## 自由放置时按“一对”作为一件道具，放下后靠 auto_link 自动互链。

signal teleported(from: Portal, to: Portal)

const PORTAL_GROUP := "portals"

@export var linked_portal: Portal
@export var mirror_out: bool = false
@export_range(0.0, 0.9) var energy_cost: float = 0.2
@export var auto_link: bool = true


func _enter_tree() -> void:
	add_to_group(PORTAL_GROUP)
	collision_layer = RayCaster.LAYER_PORTAL
	collision_mask = 0


func _ready() -> void:
	if not Engine.is_editor_hint() and auto_link and linked_portal == null:
		_auto_link_nearest()


## 门的“正面”方向（本地 +X）在世界坐标下的朝向
func get_facing() -> Vector2:
	return Vector2.RIGHT.rotated(global_rotation)


func is_linked() -> bool:
	return linked_portal != null and linked_portal != self


## 计算从本门进入后、从另一门出来的方向
func get_exit_direction(in_dir: Vector2) -> Vector2:
	if not is_linked():
		return Vector2.ZERO
	var out_dir := in_dir.rotated(linked_portal.global_rotation - global_rotation)
	if mirror_out:
		out_dir = out_dir.bounce(linked_portal.get_facing())
	return out_dir


## 光路契约入口：没配对的坏门吞掉光线（比穿透更安全，避免玩家白忙）
func on_ray(in_dir: Vector2, _normal: Vector2, _hit_pos: Vector2, energy: float) -> Array[Dictionary]:
	if not is_linked():
		return []
	var out_dir := get_exit_direction(in_dir)
	var out_energy := energy * (1.0 - energy_cost)
	if out_dir.length_squared() < 0.000001 or out_energy < RayCaster.MIN_ENERGY:
		return []
	# 从出口沿出射方向推出去一点，避免立刻又命中自己
	var exit_pos := linked_portal.global_position + out_dir * 1.0
	teleported.emit(self, linked_portal)
	return [OpticalSurface.make_ray(exit_pos, out_dir, out_energy)]


func _auto_link_nearest() -> void:
	var best: Portal = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(PORTAL_GROUP):
		var other := node as Portal
		if other == null or other == self or other.is_linked():
			continue
		var dist := global_position.distance_squared_to(other.global_position)
		if dist < best_dist:
			best_dist = dist
			best = other
	if best != null:
		linked_portal = best
		best.linked_portal = self


func _draw() -> void:
	var color := Color(0.72, 0.45, 1.0, 0.95)
	# 门框（竖直椭圆环）
	draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 24, color, 3.0)
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 20, Color(0.72, 0.45, 1.0, 0.35), 6.0)
	# 朝向箭头
	draw_line(Vector2.ZERO, get_facing() * 36.0, Color(1.0, 1.0, 1.0, 0.75), 2.0)
	draw_line(get_facing() * 36.0, get_facing() * 26.0 + get_facing().orthogonal() * 7.0,
			Color(1.0, 1.0, 1.0, 0.75), 2.0)
	draw_line(get_facing() * 36.0, get_facing() * 26.0 - get_facing().orthogonal() * 7.0,
			Color(1.0, 1.0, 1.0, 0.75), 2.0)
	# 与另一端相连的虚线（编辑器里一眼看出配对关系）
	if is_linked():
		draw_dashed_line(Vector2.ZERO, to_local(linked_portal.global_position),
				Color(0.72, 0.45, 1.0, 0.35), 1.5, 8.0)
