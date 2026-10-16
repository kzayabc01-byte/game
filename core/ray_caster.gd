class_name RayCaster
extends RefCounted

## 光线物理计算（静态工具类）：
## 从起点沿方向追踪光线，遇镜面反射、遇遮光物停下，
## 沿途收集被扫过的机关接收区（接收区透明，不阻挡光线）。
## 组员一般不需要直接使用本类，写机关只需继承 LightReceiver。

const LAYER_OPAQUE := 1        # 碰撞层 1：遮光物（墙体 / 门板）
const LAYER_MIRROR := 2        # 碰撞层 2：镜面
const LAYER_RECEIVER := 4      # 碰撞层 3：机关接收区

const MASK_BLOCKING := LAYER_OPAQUE | LAYER_MIRROR
const MASK_RECEIVER := LAYER_RECEIVER

const DEFAULT_MAX_BOUNCES := 12
const DEFAULT_MAX_LENGTH := 3000.0
const BOUNCE_OFFSET := 0.5     # 反射后把起点推出镜面一点，避免再次命中自己
const SCAN_STEP := 0.1         # 收集接收区时沿光线前进的最小步长


class ReceiverHit:
	## 一段光线扫过的一个机关接收区
	var receiver: Area2D
	var position: Vector2


class LightTrace:
	## 一次完整追踪的结果：折线顶点 + 沿途命中的接收区
	var segments: PackedVector2Array = PackedVector2Array()
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
		_scan_receivers(space, result, current_origin, endpoint)
		result.segments.append(endpoint)
		remaining -= current_origin.distance_to(endpoint)
		if not hit_mirror or remaining <= 0.0:
			break
		current_direction = current_direction.bounce(mirror_normal)
		current_origin = endpoint + mirror_normal * BOUNCE_OFFSET
	return result


static func _scan_receivers(
	space: PhysicsDirectSpaceState2D,
	result: LightTrace,
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
		result.receiver_hits.append(entry)
		scan_origin = hit.position + direction * SCAN_STEP
