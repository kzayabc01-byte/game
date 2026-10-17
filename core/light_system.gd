class_name LightSystem
extends Node

## 光线系统（总控代码）：
## 1. 自动收集场景里所有光源与机关（按组名，无需手动连线）
## 2. 每物理帧计算光线路径（反射 + 机关命中）
## 3. 把光照状态同步给每个机关，并交给渲染器绘制
## 用法：每个关卡场景放一个本节点即可（level_base 已放好）。

@export var ray_color: Color = Color(1.0, 0.85, 0.3)
@export var ray_width: float = 3.0
@export var glow_width: float = 12.0

## 每个光源每帧最多计算多少段光路（分束会消耗预算，防性能爆炸）
@export var max_segments_per_source: int = 24

var _sources: Array[LightSource] = []
var _receivers: Array[LightReceiver] = []
var _lit_receivers: Dictionary = {}
var _renderer: LightRayRenderer


func _ready() -> void:
	_renderer = LightRayRenderer.new()
	_renderer.name = "RayRenderer"
	_renderer.ray_color = ray_color
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
	var hit_receivers: Array[LightReceiver] = []
	var segment_sets: Array[PackedVector2Array] = []
	for source in _sources:
		var traces := RayCaster.trace_multi(
			space,
			source.global_position,
			source.get_light_direction(),
			max_segments_per_source
		)
		for trace in traces:
			segment_sets.append(trace.segments)
			for hit in trace.receiver_hits:
				var receiver := hit.receiver as LightReceiver
				if receiver != null and not hit_receivers.has(receiver):
					hit_receivers.append(receiver)
	_renderer.set_segments(segment_sets)
	_sync_receivers(hit_receivers, delta)


func _sync_receivers(hit_receivers: Array[LightReceiver], delta: float) -> void:
	# 多个光源取并集：只要被任意光源照到就算被照亮
	var lit_now: Dictionary = {}
	for receiver in hit_receivers:
		lit_now[receiver] = true
		if not _lit_receivers.has(receiver):
			receiver.apply_lit(true)
		receiver.on_light_frame(delta)
	for key in _lit_receivers.keys():
		var receiver := key as LightReceiver
		if receiver != null and not lit_now.has(receiver):
			receiver.apply_lit(false)
	_lit_receivers = lit_now
