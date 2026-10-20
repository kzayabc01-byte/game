class_name LightSystem
extends Node

## 光线系统（总控代码）：
## 1. 自动收集场景里所有光源与机关（按组名，无需手动连线）
## 2. 每物理帧计算光线路径（反射 / 折射 / 分光 / 传送 / 变色）
## 3. 把光照状态同步给每个机关，并交给渲染器绘制
## 用法：每个关卡场景放一个本节点即可（level_base 已放好）。

@export var ray_width: float = 3.0
@export var glow_width: float = 12.0

var _sources: Array[LightSource] = []
var _receivers: Array[LightReceiver] = []
var _lit_receivers: Dictionary = {}
var _renderer: LightRayRenderer


func _ready() -> void:
	_renderer = LightRayRenderer.new()
	_renderer.name = "RayRenderer"
	_renderer.ray_width = ray_width
	_renderer.glow_width = glow_width
	add_child(_renderer)
	_refresh_nodes()
	get_tree().node_added.connect(_on_node_added)


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
	var space := get_viewport().find_world_2d().direct_space_state
	var hit_colors: Dictionary = {}  # LightReceiver -> Array[Color]（可能被多条光/多个颜色命中）
	var segment_sets: Array[PackedVector2Array] = []
	var segment_colors: Array[Array] = []  # 与 segment_sets 一一对应
	for source in _sources:
		var traces := RayCaster.trace_all(
			space,
			source.global_position,
			source.get_light_direction(),
			source.get_light_color(),
			source.max_bounces
		)
		for trace in traces:
			segment_sets.append(trace.segments)
			segment_colors.append(trace.segment_colors)
			for hit in trace.receiver_hits:
				var receiver := hit.receiver as LightReceiver
				if receiver == null:
					continue
				if not hit_colors.has(receiver):
					hit_colors[receiver] = []
				var colors: Array = hit_colors[receiver]
				if not colors.has(hit.color):
					colors.append(hit.color)
	_renderer.set_segments(segment_sets, segment_colors)
	_sync_receivers(hit_colors, delta)


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
