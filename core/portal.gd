@tool
class_name Portal
extends OpticalSurface

## 【组员接口】传送门基类（碰撞层 5）：一对**平面**，从 A 面射入 → 从 B 面的
## 对应位置、对应方向射出。
##
## 几何约定（就是你看到的那个薄片）：
##   平面法线 n = 本地 +X（get_normal），平面切向 t = 本地 +Y（get_tangent）。
##   本地形状默认 16×96：长边是“平面”（可调 length），法线方向留一点厚度方便命中。
##
## 映射规则（A → B）：
##   1. 入射方向在 A 的局部坐标里分解为 (切向 du, 法向 dv)；
##   2. 到 B 时切向保留、法向取反：(du, -dv)；
##      —— 所以“从 A 的正面射入”必然“从 B 的正面射出”，两边一致；
##   3. 命中点的切向偏移 u 也保留：打在 A 面上方 20px，就从 B 面上方 20px 出来；
##      门有多长，能接住的命中点就有多宽 —— 整块门面都能传送；
##   4. mirror_out = true 时切向同时取反（u → -u、du → -du），做“不可能光路”。
##
## 配对（决定跟谁成对）：
##   - linked_portal：显式指定（关卡里最稳，推荐）；
##   - pair_id：给一对门填同一个 id，运行时会自动配对（多对门同场时不串门），
##     同时这个 id 会显示在门上，方便玩家看出对应关系；
##   - 两者都没有时，auto_link 才会退化为“最近的同类门”（自由放置兜底）。
##   没配对的门会**吞掉光线**，并在门的占位外观上画红叉。
##
## 每条光线对每个门只会穿越一次（防环由 RayCaster 负责）。

signal teleported(from: Portal, to: Portal)

const PORTAL_GROUP := "portals"
const MIN_NORMAL_COMPONENT := 0.0001  # 贴着平面滑过时不传送，避免抖动

@export var linked_portal: Portal
@export var pair_id: StringName = &""
@export var mirror_out: bool = false
## true = 只允许从正面（法线反方向）射入；从背面射入会被吞掉
@export var one_way: bool = false
@export_range(0.0, 0.9) var energy_cost: float = 0.2
@export var auto_link: bool = true
## 门面长度（沿切向）：整条都能传送
@export var length: float = 96.0
## 法线方向厚度：给“擦着门边飞过”的光留一点容错
@export var thickness: float = 16.0

var _warned_unlinked: bool = false


func _enter_tree() -> void:
	add_to_group(PORTAL_GROUP)
	collision_layer = RayCaster.LAYER_PORTAL
	collision_mask = 0


func _ready() -> void:
	_apply_shape()
	if Engine.is_editor_hint():
		return
	# 显式配对：把对端也指回来，避免“只有一边认人”的半截状态
	if linked_portal != null and linked_portal != self:
		if linked_portal.linked_portal == null:
			linked_portal.linked_portal = self
		return
	_try_auto_pair()


## 让碰撞体跟 length / thickness 保持一致（运行时执行，避免弄脏编辑器里的场景）
func _apply_shape() -> void:
	if Engine.is_editor_hint():
		return
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is RectangleShape2D:
		return
	(shape_node.shape as RectangleShape2D).size = Vector2(maxf(thickness, 2.0), maxf(length, 8.0))


# ---------- 平面几何 ----------

## 平面法线（本地 +X）在世界坐标下的方向：正面朝这边
func get_normal() -> Vector2:
	return Vector2.RIGHT.rotated(global_rotation)


## 平面切向（本地 +Y）在世界坐标下的方向
func get_tangent() -> Vector2:
	return Vector2.DOWN.rotated(global_rotation)


## 兼容旧名字（旧代码/文档里叫 facing）
func get_facing() -> Vector2:
	return get_normal()


func is_linked() -> bool:
	return linked_portal != null and linked_portal != self and is_instance_valid(linked_portal)


# ---------- A → B 映射 ----------

## 出射方向：切向保留、法向取反（镜像模式下切向再取反）
func map_direction(in_dir: Vector2) -> Vector2:
	if not is_linked():
		return Vector2.ZERO
	var du := in_dir.dot(get_tangent())
	var dv := in_dir.dot(get_normal())
	var flip := -1.0 if mirror_out else 1.0
	var exit_portal := linked_portal
	var exit_dir := exit_portal.get_tangent() * (flip * du) + exit_portal.get_normal() * (-dv)
	return exit_dir.normalized()


## 出射点：命中点在 A 平面上的切向偏移，原样搬到 B 平面
func map_point(hit_pos: Vector2) -> Vector2:
	if not is_linked():
		return hit_pos
	var offset := (hit_pos - global_position).dot(get_tangent())
	var flip := -1.0 if mirror_out else 1.0
	return linked_portal.global_position + linked_portal.get_tangent() * (flip * offset)


## 入射方向相对本平面的法向分量：<0 从正面射入，>0 从背面射入
func get_approach_sign(in_dir: Vector2) -> float:
	return in_dir.dot(get_normal())


# ---------- 光路契约 ----------

func on_ray(in_dir: Vector2, _normal: Vector2, hit_pos: Vector2, energy: float) -> Array[Dictionary]:
	if not is_linked():
		_warn_once_unlinked()
		return []  # 没配对：吞掉光线（比穿透安全，避免玩家白忙）

	var approach := get_approach_sign(in_dir)
	if absf(approach) < MIN_NORMAL_COMPONENT:
		return []  # 贴着平面滑过，不传送
	if one_way and approach > 0.0:
		return []  # 只允许从正面进

	var out_dir := map_direction(in_dir)
	var out_energy := energy * (1.0 - energy_cost)
	if out_dir.length_squared() < 0.000001 or out_energy < RayCaster.MIN_ENERGY:
		return []

	var exit_pos := map_point(hit_pos) + out_dir * RayCaster.BOUNCE_OFFSET
	teleported.emit(self, linked_portal)
	var ray := OpticalSurface.make_ray(exit_pos, out_dir, out_energy)
	ray["teleport"] = true  # 告诉光线系统：这里要断开折线，别把 A 和 B 连成一条直线
	return [ray]


# ---------- 配对 ----------

func _try_auto_pair() -> void:
	if pair_id != &"":
		_pair_by_id()
		return
	if auto_link:
		_auto_link_nearest()


func _pair_by_id() -> void:
	var candidates: Array[Portal] = []
	for node in get_tree().get_nodes_in_group(PORTAL_GROUP):
		var other := node as Portal
		if other == null or other == self or other.pair_id != pair_id:
			continue
		if other.is_linked() and other.linked_portal != self:
			continue
		candidates.append(other)
	if candidates.is_empty():
		return  # 不在这里报警：等真的有光线打上来时再提示（on_ray 里）
	# 按节点路径排序，保证同一份关卡每次运行配到同一扇门
	candidates.sort_custom(func(a: Portal, b: Portal) -> bool:
		return String(a.get_path()) < String(b.get_path()))
	linked_portal = candidates[0]
	if linked_portal.linked_portal == null:
		linked_portal.linked_portal = self


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


func _warn_once_unlinked() -> void:
	if _warned_unlinked:
		return
	_warned_unlinked = true
	push_warning("传送门 %s 没有配对（检查 linked_portal 或 pair_id），光线会被它吞掉。" % name)


# ---------- 编号与配对识别 ----------

## 门的编号：优先用 pair_id；否则按节点路径给每对门一个稳定序号（1、2、3…）
func get_pair_label() -> String:
	if pair_id != &"":
		return String(pair_id)
	var index := get_pair_index()
	return str(index) if index > 0 else "?"


## 第几对（未配对为 0）。同一对门拿到同一个数字，且按节点路径稳定排序。
func get_pair_index() -> int:
	if not is_linked():
		return 0
	var target := _pair_key()
	var seen: Dictionary = {}
	var number := 0
	for portal in _sorted_portals():
		if not portal.is_linked():
			continue  # 未配对的门不占编号
		var key := portal._pair_key()
		if not seen.has(key):
			number += 1
			seen[key] = number
		if key == target:
			return int(seen[key])
	return 0


## 配对颜色：同一对门同色；未配对固定红色（红色只用来表示“没配对”）
const PAIR_COLORS: Array[Color] = [
	Color(0.45, 0.85, 1.00),  # 天蓝
	Color(0.55, 0.95, 0.55),  # 绿
	Color(0.80, 0.62, 1.00),  # 紫
	Color(1.00, 0.82, 0.40),  # 金
	Color(0.45, 0.95, 0.90),  # 青
	Color(0.95, 0.70, 0.95),  # 粉紫
]


func get_pair_color() -> Color:
	if not is_linked():
		return Color(0.95, 0.30, 0.35, 0.95)
	var index := maxi(get_pair_index() - 1, 0)
	return PAIR_COLORS[index % PAIR_COLORS.size()]


func _pair_key() -> String:
	if not is_linked():
		return "self:%d" % get_instance_id()
	var a := get_instance_id()
	var b := linked_portal.get_instance_id()
	return "pair:%d" % mini(a, b)


func _sorted_portals() -> Array[Portal]:
	var result: Array[Portal] = []
	if not is_inside_tree():
		return result
	for node in get_tree().get_nodes_in_group(PORTAL_GROUP):
		var portal := node as Portal
		if portal != null:
			result.append(portal)
	# 按实例创建顺序排（不用节点名字符串排：@StaticBody2D@10 会排在 @9 前面）
	result.sort_custom(func(a: Portal, b: Portal) -> bool:
		return a.get_instance_id() < b.get_instance_id())
	return result


# ---------- 占位外观 ----------

func _draw() -> void:
	var half_len := maxf(length, 8.0) * 0.5
	var color := get_pair_color()
	var linked := is_linked()

	# 门面：一条长线 + 外发光，长度 = length（整条都能传送）
	draw_line(Vector2(0.0, -half_len), Vector2(0.0, half_len), Color(color, 0.28), 12.0)
	draw_line(Vector2(0.0, -half_len), Vector2(0.0, half_len), color, 5.0)
	draw_line(Vector2(0.0, -half_len), Vector2(0.0, half_len), Color(1, 1, 1, 0.45), 1.5)

	# 法线箭头（指向“正面”）
	var normal := Vector2.RIGHT
	draw_line(Vector2.ZERO, normal * 34.0, Color(1, 1, 1, 0.8), 2.0)
	draw_line(normal * 34.0, normal * 24.0 + normal.orthogonal() * 7.0, Color(1, 1, 1, 0.8), 2.0)
	draw_line(normal * 34.0, normal * 24.0 - normal.orthogonal() * 7.0, Color(1, 1, 1, 0.8), 2.0)

	# 单向标记：背面画一道短横
	if one_way:
		draw_line(Vector2(-10.0, -10.0), Vector2(-2.0, 10.0), Color(1, 0.85, 0.4, 0.9), 2.0)

	# 未配对：红叉
	if not linked:
		draw_line(Vector2(-8.0, -8.0), Vector2(8.0, 8.0), Color(1, 0.35, 0.35, 0.9), 2.0)
		draw_line(Vector2(-8.0, 8.0), Vector2(8.0, -8.0), Color(1, 0.35, 0.35, 0.9), 2.0)

	# 编号：门面外侧角落的小圆牌。用世界朝向绘制，门旋转 180° 时数字也不会倒过来。
	var label := get_pair_label()
	var font := ThemeDB.fallback_font
	if font != null and not label.is_empty():
		draw_set_transform(Vector2(-20.0, -(half_len + 16.0)), -global_rotation, Vector2.ONE)
		draw_circle(Vector2.ZERO, 15.0, Color(0.06, 0.07, 0.10, 0.9))
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24, color, 2.0)
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		draw_string(font, Vector2(-text_size.x * 0.5, text_size.y * 0.34), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 与对端相连的虚线
	if linked:
		draw_dashed_line(Vector2.ZERO, to_local(linked_portal.global_position),
				Color(color, 0.35), 1.5, 8.0)
