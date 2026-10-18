class_name RayCaster
extends RefCounted

## 光线物理计算（静态工具类）：
## 从起点沿方向追踪光线，遇镜面反射、遇遮光物停下，
## 沿途收集被扫过的机关接收区（接收区透明，不阻挡光线）。
## 颜色随光路传播：每条 LightTrace 一个颜色；光路表面出射光线可携带 "color" 改色。
## 组员一般不需要直接使用本类，写机关只需继承 LightReceiver。

const LAYER_OPAQUE := 1        # 碰撞层 1：遮光物（墙体 / 门板）
const LAYER_MIRROR := 2        # 碰撞层 2：镜面
const LAYER_RECEIVER := 4      # 碰撞层 3：机关接收区
const LAYER_OPTIC := 8         # 碰撞层 4：折射体 / 凹透镜 / 冰川（OpticalSurface）
const LAYER_PORTAL := 16       # 碰撞层 5：传送门（OpticalSurface）

const MASK_BLOCKING := LAYER_OPAQUE | LAYER_MIRROR | LAYER_OPTIC | LAYER_PORTAL
const MASK_RECEIVER := LAYER_RECEIVER

const DEFAULT_MAX_BOUNCES := 12
const DEFAULT_MAX_LENGTH := 3000.0
const DEFAULT_MAX_SEGMENTS := 32   # 单条光源的总段数预算（分束后按段扣）
const DEFAULT_MAX_SPLIT := 8       # 单次命中最多生成多少条子光线（防分束爆炸）
const MIN_ENERGY := 0.15           # 低于此能量的光线直接丢弃
const BOUNCE_OFFSET := 0.5     # 反射后把起点推出镜面一点，避免再次命中自己
const SCAN_STEP := 0.1         # 收集接收区时沿光线前进的最小步长


class ReceiverHit:
	## 一段光线扫过的一个机关接收区（含照到它的光色）
	var receiver: Area2D
	var position: Vector2
	var color: Color = Color.WHITE


class LightTrace:
	## 一次完整追踪的结果：折线顶点 + 颜色 + 沿途命中的接收区
	var segments: PackedVector2Array = PackedVector2Array()
	var color: Color = Color.WHITE
	var receiver_hits: Array[ReceiverHit] = []


static func trace(
	space: PhysicsDirectSpaceState2D,
	origin: Vector2,
	direction: Vector2,
	max_bounces: int = DEFAULT_MAX_BOUNCES,
	max_length: float = DEFAULT_MAX_LENGTH
) -> LightTrace:
	var result := LightTrace.new()
	var current_origin := origin
	var current_direction := direction.normalized()
	var remaining := max_length
	result.segments.append(current_origin)
	for _bounce in max_bounces + 1:
		var segment_end := current_origin + current_direction * remaining
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters2D.create(current_origin, segment_end, MASK_BLOCKING)
		)
		var endpoint := segment_end
		var mirror_normal := Vector2.ZERO
		var hit_mirror := false
		if not hit.is_empty():
			endpoint = hit.position
			var collider := hit.collider as CollisionObject2D
			if collider != null and collider.collision_layer & LAYER_MIRROR:
				hit_mirror = true
				mirror_normal = hit.normal
		_scan_receivers(space, result, current_origin, endpoint, Color.WHITE)
		result.segments.append(endpoint)
		remaining -= current_origin.distance_to(endpoint)
		if not hit_mirror or remaining <= 0.0:
			break
		current_direction = current_direction.bounce(mirror_normal)
		current_origin = endpoint + mirror_normal * BOUNCE_OFFSET
	return result


## 多分支追踪：在 trace() 的基础上支持「光路表面」（OpticalSurface）。
## 反射照旧由本类处理；折射 / 分束 / 传送由表面自己的 on_ray() 返回出射光线。
## 返回若干条折线（分束 = 多条），顺序按产生先后；每条折线自带颜色（trace.color）。
## 旧接口 trace() 原样保留，只有镜面链路的关卡行为完全不变。
static func trace_multi(
	space: PhysicsDirectSpaceState2D,
	origin: Vector2,
	direction: Vector2,
	max_segments: int = DEFAULT_MAX_SEGMENTS,
	max_length: float = DEFAULT_MAX_LENGTH,
	start_color: Color = Color.WHITE
) -> Array[LightTrace]:
	var traces: Array[LightTrace] = []
	var queue: Array[Dictionary] = [
		{
			"origin": origin,
			"dir": direction.normalized(),
			"energy": 1.0,
			"visited": {},
			"color": start_color,
		}
	]
	var budget := maxi(max_segments, 1)

	while not queue.is_empty() and budget > 0:
		var ray: Dictionary = queue.pop_front()
		var trace := LightTrace.new()
		var current_origin: Vector2 = ray["origin"]
		var current_direction: Vector2 = ray["dir"]
		var energy: float = ray["energy"]
		var visited: Dictionary = ray["visited"]
		var color: Color = ray["color"]
		trace.color = color
		var remaining: float = max_length
		var bounces := 0

		trace.segments.append(current_origin)
		while budget > 0 and bounces <= DEFAULT_MAX_BOUNCES:
			bounces += 1
			budget -= 1

			var segment_end := current_origin + current_direction * remaining
			var hit := space.intersect_ray(
				PhysicsRayQueryParameters2D.create(current_origin, segment_end, MASK_BLOCKING)
			)
			if hit.is_empty():
				trace.segments.append(segment_end)
				_scan_receivers(space, trace, current_origin, segment_end, color)
				break

			var endpoint: Vector2 = hit.position
			var collider := hit.collider as CollisionObject2D
			var normal: Vector2 = hit.normal
			trace.segments.append(endpoint)
			_scan_receivers(space, trace, current_origin, endpoint, color)
			remaining -= current_origin.distance_to(endpoint)

			if collider == null or remaining <= 0.0:
				break
			if collider.collision_layer & LAYER_MIRROR:
				current_direction = current_direction.bounce(normal)
				current_origin = endpoint + normal * BOUNCE_OFFSET
				continue
			if collider.has_method("on_ray"):
				_spawn_children(collider, current_direction, normal, endpoint, energy, color, visited, queue)
				break
			break  # 遮光物：光线到此为止

		if trace.segments.size() >= 2:
			traces.append(trace)

	return traces


## 把一次表面命中的出射光线放进待处理队列（内部使用）
static func _spawn_children(
	surface: Object,
	in_dir: Vector2,
	normal: Vector2,
	hit_pos: Vector2,
	energy: float,
	color: Color,
	visited: Dictionary,
	queue: Array[Dictionary]
) -> void:
	# 同一条光线以同一方向再次进入同一表面 = 传送门成环，直接丢弃
	var key := "%d@%d" % [surface.get_instance_id(), int(in_dir.angle() * 1000.0)]
	if visited.has(key):
		return
	visited[key] = true

	var outs: Array = surface.call("on_ray", in_dir, normal, hit_pos, energy)
	var spawned := 0
	for out in outs:
		if spawned >= DEFAULT_MAX_SPLIT:
			break
		if typeof(out) != TYPE_DICTIONARY:
			continue
		var out_dir: Vector2 = out.get("dir", Vector2.ZERO)
		var out_energy: float = float(out.get("energy", energy))
		var out_color: Color = out.get("color", color)
		if out_dir.length_squared() < 0.000001 or out_energy < MIN_ENERGY:
			continue
		queue.append({
			"origin": out.get("origin", hit_pos),
			"dir": out_dir.normalized(),
			"energy": out_energy,
			"visited": visited.duplicate(),
			"color": out_color,
		})
		spawned += 1


static func _scan_receivers(
	space: PhysicsDirectSpaceState2D,
	result: LightTrace,
	from: Vector2,
	to: Vector2,
	color: Color
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
		entry.color = color
		result.receiver_hits.append(entry)
		scan_origin = hit.position + direction * SCAN_STEP
