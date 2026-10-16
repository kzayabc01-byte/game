class_name RayCaster
extends RefCounted

## 光线物理计算（静态工具类）：
## 从起点沿方向追踪光线：镜面反射、折射面偏转/分光/变色、传送门传送、
## 遮光物停下；沿途收集被扫过的机关接收区（接收区透明，不阻挡光线）。
## 分光（凹透镜）会把一条光线变成多条，trace_all 返回全部结果。
## 组员一般不需要直接使用本类，写机关只需继承 LightReceiver / RefractSurface / Portal。

const LAYER_OPAQUE := 1        # 碰撞层 1：遮光物（墙体 / 门板）
const LAYER_MIRROR := 2        # 碰撞层 2：镜面
const LAYER_RECEIVER := 4      # 碰撞层 3：机关接收区
const LAYER_REFRACT := 8       # 碰撞层 4：折射面（光线穿过并偏转 / 分光 / 变色）
const LAYER_PORTAL := 16       # 碰撞层 5：传送门

const MASK_BLOCKING := LAYER_OPAQUE | LAYER_MIRROR | LAYER_REFRACT | LAYER_PORTAL
const MASK_RECEIVER := LAYER_RECEIVER

const DEFAULT_MAX_BOUNCES := 12
const DEFAULT_MAX_LENGTH := 3000.0
const DEFAULT_MAX_RAYS := 32    # 分光后光线总数的安全上限，防止镜子+透镜组合爆炸
const BOUNCE_OFFSET := 0.5      # 续接后把起点推出表面一点，避免再次命中自己
const SCAN_STEP := 0.1          # 收集接收区时沿光线前进的最小步长


class ReceiverHit:
	## 一段光线扫过的一个机关接收区
	var receiver: Area2D
	var position: Vector2
	var color: Color = Color.WHITE  # 命中瞬间该光线的颜色


class LightTrace:
	## 一条光线的完整路径：折线顶点 + 每段颜色 + 沿途命中的接收区
	var segments: PackedVector2Array = PackedVector2Array()
	var segment_colors: Array[Color] = []  # segment_colors[i] = segments[i]→segments[i+1] 的颜色
	var receiver_hits: Array[ReceiverHit] = []


class _PendingRay:
	## 队列中待推进的一条光线（分光后一条会变成多条）
	var origin: Vector2
	var direction: Vector2
	var color: Color = Color.WHITE
	var bounces_left: int = 0
	var length_left: float = 0.0
	var segments: PackedVector2Array = PackedVector2Array()
	var segment_colors: Array[Color] = []
	var hits: Array[ReceiverHit] = []


## 追踪光线（可能经分光变成多条）。color 沿路径传播：
## 变色机关改写它，接收区记录命中时的颜色。
static func trace_all(
	space: PhysicsDirectSpaceState2D,
	origin: Vector2,
	direction: Vector2,
	color: Color = Color.WHITE,
	max_bounces: int = DEFAULT_MAX_BOUNCES,
	max_length: float = DEFAULT_MAX_LENGTH,
	max_rays: int = DEFAULT_MAX_RAYS
) -> Array[LightTrace]:
	var traces: Array[LightTrace] = []
	var queue: Array[_PendingRay] = []
	var first := _PendingRay.new()
	first.origin = origin
	first.direction = direction.normalized()
	first.color = color
	first.bounces_left = max_bounces
	first.length_left = max_length
	first.segments.append(origin)
	queue.append(first)
	while not queue.is_empty() and traces.size() < max_rays:
		var ray := queue.pop_front() as _PendingRay
		_advance_ray(space, ray, queue, traces)
	return traces


## 兼容旧接口：单光线追踪（忽略分光，取第一条光线）
static func trace(
	space: PhysicsDirectSpaceState2D,
	origin: Vector2,
	direction: Vector2,
	max_bounces: int = DEFAULT_MAX_BOUNCES,
	max_length: float = DEFAULT_MAX_LENGTH
) -> LightTrace:
	var traces := trace_all(space, origin, direction, Color.WHITE, max_bounces, max_length)
	return traces[0] if not traces.is_empty() else LightTrace.new()


## 推进一条光线一段：找最近的阻挡面 → 扫沿途接收区 → 续接 / 分光 / 停止
static func _advance_ray(
	space: PhysicsDirectSpaceState2D,
	ray: _PendingRay,
	queue: Array[_PendingRay],
	traces: Array[LightTrace]
) -> void:
	var endpoint := ray.origin + ray.direction * ray.length_left
	var hit := space.intersect_ray(
		PhysicsRayQueryParameters2D.create(ray.origin, endpoint, MASK_BLOCKING)
	)
	if not hit.is_empty():
		endpoint = hit.position
	_scan_receivers(space, ray, ray.origin, endpoint)
	ray.segments.append(endpoint)
	ray.segment_colors.append(ray.color)
	ray.length_left -= ray.origin.distance_to(endpoint)
	if hit.is_empty() or ray.length_left <= 0.0 or ray.bounces_left <= 0:
		_finish_ray(traces, ray)
		return
	var collider := hit.collider as CollisionObject2D
	if collider == null:
		_finish_ray(traces, ray)
		return
	var layers := collider.collision_layer
	if layers & LAYER_MIRROR:
		var next_direction := ray.direction.bounce(hit.normal)
		queue.append(_continue_ray(ray, endpoint + hit.normal * BOUNCE_OFFSET, next_direction, ray.color))
	elif layers & LAYER_REFRACT:
		_continue_refract(ray, collider, endpoint, queue)
	elif layers & LAYER_PORTAL:
		_continue_portal(ray, collider, queue, traces)
	else:
		_finish_ray(traces, ray)


static func _continue_refract(
	ray: _PendingRay,
	collider: CollisionObject2D,
	endpoint: Vector2,
	queue: Array[_PendingRay]
) -> void:
	# 折射面：光线穿过。规范折射面（RefractSurface）可偏转 / 分光 / 变色；
	# 其他折射层物体视为透明直穿。
	var surface := collider as RefractSurface
	if surface == null:
		queue.append(_continue_ray(ray, endpoint + ray.direction * BOUNCE_OFFSET, ray.direction, ray.color))
		return
	var next_color := surface.output_color if surface.recolor else ray.color
	var bend := deg_to_rad(surface.bend_degrees)
	if surface.split:
		queue.append(_continue_ray(ray, endpoint + ray.direction.rotated(bend) * BOUNCE_OFFSET, ray.direction.rotated(bend), next_color))
		queue.append(_continue_ray(ray, endpoint + ray.direction.rotated(-bend) * BOUNCE_OFFSET, ray.direction.rotated(-bend), next_color))
	else:
		queue.append(_continue_ray(ray, endpoint + ray.direction.rotated(bend) * BOUNCE_OFFSET, ray.direction.rotated(bend), next_color))


static func _continue_portal(
	ray: _PendingRay,
	collider: CollisionObject2D,
	queue: Array[_PendingRay],
	traces: Array[LightTrace]
) -> void:
	# 传送门：光线从 linked_portal 的位置继续，方向按两扇门的相对旋转换算
	# （进 A 的角度 = 出 B 的角度）。未配对的传送门会把光线吞掉。
	var portal := collider as Portal
	var linked := portal.linked_portal if portal != null else null
	if linked == null:
		_finish_ray(traces, ray)
		return
	var next_direction := ray.direction.rotated(linked.global_rotation - portal.global_rotation)
	queue.append(_continue_ray(ray, linked.global_position + next_direction * BOUNCE_OFFSET, next_direction, ray.color))


## 复制当前光线并续接一段（保留已走过的路径与命中记录，供分光后各支路共用）
static func _continue_ray(ray: _PendingRay, origin: Vector2, direction: Vector2, color: Color) -> _PendingRay:
	var next := _PendingRay.new()
	next.origin = origin
	next.direction = direction.normalized()
	next.color = color
	next.bounces_left = ray.bounces_left - 1
	next.length_left = ray.length_left
	next.segments = ray.segments.duplicate()
	next.segment_colors = ray.segment_colors.duplicate()
	next.hits = ray.hits.duplicate()
	return next


static func _finish_ray(traces: Array[LightTrace], ray: _PendingRay) -> void:
	var trace := LightTrace.new()
	trace.segments = ray.segments
	trace.segment_colors = ray.segment_colors
	trace.receiver_hits = ray.hits
	traces.append(trace)


static func _scan_receivers(
	space: PhysicsDirectSpaceState2D,
	ray: _PendingRay,
	from: Vector2,
	to: Vector2
) -> void:
	# 收集 [from, to] 这段自由光线扫过的所有接收区（按从近到远顺序）
	if from.distance_squared_to(to) < 0.01:
		return
	var direction := (to - from).normalized()
	var scan_origin := from
	var excluded: Array[RID] = []
	while scan_origin.distance_squared_to(to) >= 0.01:
		var query := PhysicsRayQueryParameters2D.create(scan_origin, to, MASK_RECEIVER, excluded)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return
		var collider := hit.collider as Area2D
		if collider == null:
			return
		excluded.append(collider.get_rid())
		var entry := ReceiverHit.new()
		entry.receiver = collider
		entry.position = hit.position
		entry.color = ray.color
		ray.hits.append(entry)
		scan_origin = hit.position + direction * SCAN_STEP
