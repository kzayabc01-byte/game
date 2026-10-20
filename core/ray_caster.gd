class_name RayCaster
extends RefCounted

## 光线物理计算（静态工具类）：
## 从起点沿方向追踪光线：镜面反射、光路表面（OpticalSurface.on_ray 契约）偏折/分光/传送、
## 遮光物停下；沿途收集被扫过的机关接收区（接收区透明，不阻挡光线）。
## 分光（凹透镜）会把一条光线变成多条。
## 两条入口：
##   trace_all   —— 完整路径折线（一条光路一份结果，携带颜色，光线系统用它）
##   trace_multi —— 每段一份结果 + 总段数预算（光路组契约测试用它）
## 组员一般不需要直接使用本类，写机关只需继承 LightReceiver / OpticalSurface。

const LAYER_OPAQUE := 1        # 碰撞层 1：遮光物（墙体 / 石块）
const LAYER_MIRROR := 2        # 碰撞层 2：镜面
const LAYER_RECEIVER := 4      # 碰撞层 3：机关接收区
const LAYER_REFRACT := 8       # 碰撞层 4：折射体（偏转 / 分光 / 变色 / 融化，见 RefractSurface）
const LAYER_PORTAL := 16       # 碰撞层 5：传送门

## 光路契约里的名字（LAYER_OPTIC = 折射体层，与 LAYER_REFRACT 同义）
const LAYER_OPTIC := LAYER_REFRACT

const MASK_BLOCKING := LAYER_OPAQUE | LAYER_MIRROR | LAYER_REFRACT | LAYER_PORTAL
const MASK_RECEIVER := LAYER_RECEIVER

const DEFAULT_MAX_BOUNCES := 12
const DEFAULT_MAX_LENGTH := 3000.0
const DEFAULT_MAX_RAYS := 32    # 分光后光线总数的安全上限，防止镜子+透镜组合爆炸
const DEFAULT_MAX_SEGMENTS := 32  # 单条光源的总段数预算（trace_multi 按段扣）
const DEFAULT_MAX_SPLIT := 8    # 单次表面命中最多生成多少条子光线（防分束爆炸）
const MIN_ENERGY := 0.15        # 低于此能量的光线直接丢弃（契约：光源 1.0）
const BOUNCE_OFFSET := 0.5      # 续接后把起点推出表面一点，避免再次命中自己
const SCAN_STEP := 0.1          # 收集接收区时沿光线前进的最小步长


class ReceiverHit:
	## 一段光线扫过的一个机关接收区
	var receiver: Area2D
	var position: Vector2
	var color: Color = Color.WHITE  # 命中瞬间该光线的颜色


class LightTrace:
	## 一次追踪的结果：折线顶点 + 每段颜色 + 沿途命中的接收区
	var segments: PackedVector2Array = PackedVector2Array()
	var segment_colors: Array[Color] = []  # segment_colors[i] = segments[i]→segments[i+1] 的颜色
	var receiver_hits: Array[ReceiverHit] = []


class _PendingRay:
	## 队列中待推进的一条光线（分光后一条会变成多条）
	var origin: Vector2
	var direction: Vector2
	var color: Color = Color.WHITE
	var energy: float = 1.0
	var bounces_left: int = 0
	var length_left: float = 0.0
	var segments: PackedVector2Array = PackedVector2Array()
	var segment_colors: Array[Color] = []
	var hits: Array[ReceiverHit] = []
	var visited: Dictionary = {}  # 已进入过的表面（防传送门成环死循环）


## 追踪光线（可能经分光变成多条），每条结果是一条完整光路。
## color 沿路径传播：变色机关改写它，接收区记录命中时的颜色。
static func trace_all(
	space: PhysicsDirectSpaceState2D,
	origin: Vector2,
	direction: Vector2,
	color: Color = Color.WHITE,
	max_bounces: int = DEFAULT_MAX_BOUNCES,
	max_length: float = DEFAULT_MAX_LENGTH,
	max_rays: int = DEFAULT_MAX_RAYS
) -> Array[LightTrace]:
	return _trace(space, origin, direction, color, 1.0, false, 0, max_bounces, max_length, max_rays)


## 契约版追踪（光路组）：每段一份结果，总段数预算 max_segments。
## 与 trace_all 的区别：分光/折射/传送后，子光线从出射点开始一份新折线（不重复前缀）。
static func trace_multi(
	space: PhysicsDirectSpaceState2D,
	origin: Vector2,
	direction: Vector2,
	max_segments: int = DEFAULT_MAX_SEGMENTS,
	max_length: float = DEFAULT_MAX_LENGTH
) -> Array[LightTrace]:
	return _trace(space, origin, direction, Color.WHITE, 1.0, true, max_segments,
			DEFAULT_MAX_BOUNCES, max_length, DEFAULT_MAX_RAYS)


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


static func _trace(
	space: PhysicsDirectSpaceState2D,
	origin: Vector2,
	direction: Vector2,
	color: Color,
	energy: float,
	per_segment: bool,
	budget: int,
	max_bounces: int,
	max_length: float,
	max_rays: int
) -> Array[LightTrace]:
	var traces: Array[LightTrace] = []
	var queue: Array[_PendingRay] = []
	var first := _PendingRay.new()
	first.origin = origin
	first.direction = direction.normalized()
	first.color = color
	first.energy = energy
	first.bounces_left = max_bounces
	first.length_left = max_length
	first.segments.append(origin)
	queue.append(first)
	var budget_state := {"left": budget}
	while not queue.is_empty():
		if per_segment:
			if budget_state["left"] <= 0:
				break
		elif traces.size() >= max_rays:
			break
		var ray := queue.pop_front() as _PendingRay
		_advance_ray(space, ray, queue, traces, budget_state, per_segment)
	return traces


## 推进一条光线一段：找最近的阻挡面 → 扫沿途接收区 → 反射续接 / 契约分发 / 停止
static func _advance_ray(
	space: PhysicsDirectSpaceState2D,
	ray: _PendingRay,
	queue: Array[_PendingRay],
	traces: Array[LightTrace],
	budget_state: Dictionary,
	per_segment: bool
) -> void:
	if per_segment:
		if budget_state["left"] <= 0:
			return
		budget_state["left"] -= 1
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
		_finish_ray(traces, ray, per_segment)
		return
	var collider := hit.collider as CollisionObject2D
	if collider == null:
		_finish_ray(traces, ray, per_segment)
		return
	if collider.collision_layer & LAYER_MIRROR:
		# 镜面：反射照旧由本类处理，同一份折线继续累积
		var next_direction := ray.direction.bounce(hit.normal)
		queue.append(_continue_ray(ray, endpoint + hit.normal * BOUNCE_OFFSET,
				next_direction, ray.color, ray.energy, false))
	elif collider.has_method("on_ray"):
		# 光路表面（折射/分光/传送门/冰川……）：出射光线由表面自己决定
		_spawn_from_surface(ray, collider, hit.normal, endpoint, queue, per_segment)
		_finish_ray(traces, ray, per_segment)
	else:
		_finish_ray(traces, ray, per_segment)  # 遮光物：光线到此为止


## 把一次表面命中的出射光线放进待处理队列（光路契约分发）
static func _spawn_from_surface(
	ray: _PendingRay,
	surface: Object,
	normal: Vector2,
	hit_pos: Vector2,
	queue: Array[_PendingRay],
	per_segment: bool
) -> void:
	# 同一条光线以同一方向再次进入同一表面 = 传送门成环，直接丢弃
	var key := "%d@%d" % [surface.get_instance_id(), int(ray.direction.angle() * 1000.0)]
	if ray.visited.has(key):
		return
	ray.visited[key] = true

	var outs: Array = surface.call("on_ray", ray.direction, normal, hit_pos, ray.energy)
	var spawned := 0
	for out in outs:
		if spawned >= DEFAULT_MAX_SPLIT:
			break
		if typeof(out) != TYPE_DICTIONARY:
			continue
		var out_dir: Vector2 = out.get("dir", Vector2.ZERO)
		var out_energy: float = float(out.get("energy", ray.energy))
		if out_dir.length_squared() < 0.000001 or out_energy < MIN_ENERGY:
			continue
		var out_color: Color = out.get("color", ray.color)  # 契约扩展字段：变色机关用
		var out_origin: Vector2 = out.get("origin", hit_pos)
		# 传送门会在出射光线里标 teleport：这里必须断成两份折线，
		# 否则渲染器会把“进 A”和“出 B”连成一条穿过整个场景的直线。
		var breaks_path := bool(out.get("teleport", false))
		queue.append(_continue_ray(ray, out_origin, out_dir, out_color, out_energy,
				per_segment or breaks_path))
		spawned += 1


## 复制当前光线并续接一段。fresh=true 时子光线从出射点开始一份新折线
## （trace_multi 的按段语义）；否则保留已走过的路径与命中记录（trace_all 的整路语义）。
static func _continue_ray(
	ray: _PendingRay,
	origin: Vector2,
	direction: Vector2,
	color: Color,
	energy: float,
	fresh: bool
) -> _PendingRay:
	var next := _PendingRay.new()
	next.origin = origin
	next.direction = direction.normalized()
	next.color = color
	next.energy = energy
	next.bounces_left = ray.bounces_left - 1
	next.length_left = ray.length_left
	next.visited = ray.visited.duplicate()
	if fresh:
		next.segments.append(origin)
	else:
		next.segments = ray.segments.duplicate()
		next.segment_colors = ray.segment_colors.duplicate()
		next.hits = ray.hits.duplicate()
	return next


static func _finish_ray(traces: Array[LightTrace], ray: _PendingRay, per_segment: bool) -> void:
	if per_segment and ray.segments.size() < 2:
		return
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
