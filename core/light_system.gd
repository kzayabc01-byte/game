class_name LightSystem
extends Node

## 光线系统（总控代码）：
## 1. 自动收集场景里所有光源与机关（按组名，无需手动连线）
## 2. 每物理帧计算光线路径（反射 / 折射 / 分光 / 传送 / 变色）
## 3. 把光照状态同步给每个机关，并交给渲染器绘制
## 用法：每个关卡场景放一个本节点即可（level_base 已放好）。

const COVERAGE_STEP_DEGREES := 2
const PULSE_SECONDS := 0.45

signal pulse_finished

@export var ray_width: float = 3.0
@export var glow_width: float = 12.0
@export var pulse_mode: bool = false

var full_coverage_enabled := false
var lit_start_degrees := 0.0
var lit_end_degrees := 360.0

var _sources: Array[LightSource] = []
var _receivers: Array[LightReceiver] = []
var _lit_receivers: Dictionary = {}
var _renderer: LightRayRenderer
var _pending_fire := false
var _pulse_active := false
var _pulse_elapsed := 0.0
var _pulse_hits: Dictionary = {}
var _previous_process_mode: ProcessMode = Node.PROCESS_MODE_INHERIT
var _preview_length := 240.0


func _ready() -> void:
	_renderer = LightRayRenderer.new()
	_renderer.name = "RayRenderer"
	_renderer.ray_width = ray_width
	_renderer.glow_width = glow_width
	add_child(_renderer)
	_preview_length = ProgressStore.get_hint_length()
	_refresh_nodes()
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if _pulse_active or _pending_fire:
		get_tree().paused = false


func _process(delta: float) -> void:
	if not _pulse_active:
		return
	_pulse_elapsed += delta
	_renderer.visible_fraction = minf(_pulse_elapsed / PULSE_SECONDS, 1.0)
	_renderer.queue_redraw()
	if _pulse_elapsed >= PULSE_SECONDS:
		_finish_pulse()


func request_fire() -> bool:
	if not pulse_mode or _pulse_active or _pending_fire:
		return false
	_pending_fire = true
	_previous_process_mode = process_mode
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	return true


func is_pulse_active() -> bool:
	return _pulse_active or _pending_fire


func refresh_hint_length() -> void:
	_preview_length = ProgressStore.get_hint_length()


func reset_state() -> void:
	var was_firing := _pulse_active or _pending_fire
	_pending_fire = false
	if was_firing:
		get_tree().paused = false
		process_mode = _previous_process_mode
	_pulse_active = false
	_pulse_hits.clear()
	_renderer.visible_fraction = 1.0
	_sync_receivers({}, 0.0)


func _refresh_nodes() -> void:
	_sources.clear()
	for node in get_tree().get_nodes_in_group(LightSource.SOURCE_GROUP):
		_sources.append(node as LightSource)
	_receivers.clear()
	for node in get_tree().get_nodes_in_group(LightReceiver.RECEIVER_GROUP):
		_receivers.append(node as LightReceiver)


func _on_node_added(_node: Node) -> void:
	# 支持运行时动态生成光源/机关（一般用不到，但保证不丢）
	_refresh_nodes()


func _physics_process(delta: float) -> void:
	if _pulse_active:
		return
	if _pending_fire:
		_pending_fire = false
		_start_pulse()
		return
	var space := get_viewport().find_world_2d().direct_space_state
	var hit_colors: Dictionary = {}  # LightReceiver -> Array[Color]（可能被多条光/多个颜色命中）
	var segment_sets: Array[PackedVector2Array] = []
	var segment_colors: Array[Array] = []  # 与 segment_sets 一一对应
	var width_scales: Array[float] = []   # 与 segment_sets 一一对应（凸透镜聚焦后变细）
	for source in _sources:
		if not is_instance_valid(source):
			continue
		for direction in get_emission_directions(source.get_light_direction()):
			var traces := RayCaster.trace_all(
				space,
				source.global_position,
				direction,
				source.get_light_color(),
				source.max_bounces,
				_preview_length if pulse_mode else RayCaster.DEFAULT_MAX_LENGTH,
				RayCaster.DEFAULT_MAX_RAYS, not pulse_mode
			)
			_collect_traces(traces, hit_colors, segment_sets, segment_colors, width_scales)
	_renderer.preview_mode = pulse_mode
	_renderer.visible_fraction = 1.0
	_renderer.set_segments(segment_sets, segment_colors, width_scales)
	if not pulse_mode:
		_sync_receivers(hit_colors, delta)


func _start_pulse() -> void:
	_sync_receivers({}, 0.0)
	var space := get_viewport().find_world_2d().direct_space_state
	var segment_sets: Array[PackedVector2Array] = []
	var segment_colors: Array[Array] = []
	var width_scales: Array[float] = []
	_pulse_hits.clear()
	for source in _sources:
		if not is_instance_valid(source):
			continue
		for direction in get_emission_directions(source.get_light_direction()):
			var traces := RayCaster.trace_all(
				space, source.global_position, direction, source.get_light_color(),
				source.max_bounces
			)
			_collect_traces(traces, _pulse_hits, segment_sets, segment_colors, width_scales)
	_renderer.preview_mode = false
	_renderer.visible_fraction = 0.0
	_renderer.set_segments(segment_sets, segment_colors, width_scales)
	_pulse_elapsed = 0.0
	_pulse_active = true


func _finish_pulse() -> void:
	_pulse_active = false
	get_tree().paused = false
	process_mode = _previous_process_mode
	for node in get_tree().get_nodes_in_group("resettables"):
		var glacier := node as Glacier
		if glacier != null:
			glacier.commit_pulse_hit(PULSE_SECONDS)
	_sync_receivers(_pulse_hits, PULSE_SECONDS)
	_pulse_hits.clear()
	pulse_finished.emit()


func _collect_traces(
	traces: Array[RayCaster.LightTrace], hit_colors: Dictionary,
	segment_sets: Array[PackedVector2Array], segment_colors: Array[Array],
	width_scales: Array[float]
) -> void:
	for trace in traces:
		segment_sets.append(trace.segments)
		segment_colors.append(trace.segment_colors)
		width_scales.append(trace.width_scale)
		for hit in trace.receiver_hits:
			var receiver := hit.receiver as LightReceiver
			if receiver == null:
				continue
			if not hit_colors.has(receiver):
				hit_colors[receiver] = []
			var colors: Array = hit_colors[receiver]
			if not colors.has(hit.color):
				colors.append(hit.color)


## 编辑器测试专用；非导出属性不会进入关卡文件。
func configure_full_coverage(enabled: bool, lit_start: float, lit_end: float) -> void:
	full_coverage_enabled = enabled
	lit_start_degrees = clampf(lit_start, 0.0, 360.0)
	lit_end_degrees = clampf(lit_end, 0.0, 360.0)


## 测试光区使用世界方向：正右为 0°，顺时针增加；0°→360° 为整圈。
func get_emission_directions(forward: Vector2) -> Array[Vector2]:
	var directions: Array[Vector2] = []
	if not full_coverage_enabled:
		directions.append(forward)
		return directions
	var span := fposmod(lit_end_degrees - lit_start_degrees, 360.0)
	if is_zero_approx(span) and not is_equal_approx(lit_start_degrees, lit_end_degrees):
		span = 360.0
	for index in range(ceili(span / float(COVERAGE_STEP_DEGREES))):
		var angle_degrees := lit_start_degrees + float(index * COVERAGE_STEP_DEGREES)
		directions.append(Vector2.RIGHT.rotated(deg_to_rad(angle_degrees)))
	return directions


func _sync_receivers(hit_colors: Dictionary, delta: float) -> void:
	# 多个光源 / 分光取并集；普通触发机关可按自身属性过滤颜色。
	var lit_now: Dictionary = {}
	for key in hit_colors:
		var receiver := key as LightReceiver
		if receiver == null:
			continue
		var colors: Array = hit_colors[key]
		var accepted_color := Color.WHITE
		var accepted := false
		for variant in colors:
			var color := variant as Color
			if receiver.accepts(color):
				accepted_color = color
				accepted = true
				break
		if not accepted:
			continue
		lit_now[receiver] = true
		receiver.apply_lit(true, accepted_color)
		receiver.on_light_frame(delta)
	for key in _lit_receivers.keys():
		var receiver := key as LightReceiver
		if receiver != null and not lit_now.has(receiver):
			receiver.apply_lit(false)
	_lit_receivers = lit_now
