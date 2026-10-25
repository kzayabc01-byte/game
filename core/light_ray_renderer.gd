class_name LightRayRenderer
extends Node2D

## 光线可视化（占位实现）：把光线系统算出的折线画出来，每段可不同颜色，每条可不同宽度。
## 后续接入美术时，用粒子 / Shader 替换这里的绘制即可，
## 光线计算（RayCaster）不受影响。

const DEFAULT_COLOR := Color(1.0, 0.85, 0.3)

var ray_width: float = 3.0
var glow_width: float = 12.0
var preview_mode := false
var visible_fraction := 1.0

var _segment_sets: Array[PackedVector2Array] = []
var _segment_colors: Array[Array] = []  # 与 _segment_sets 一一对应：Array[Color]
var _width_scales: Array[float] = []    # 与 _segment_sets 一一对应：光柱宽度倍数


## 由光线系统每帧调用：传入每条光线的折线顶点（世界坐标）、每段颜色、宽度倍数
func set_segments(
	segment_sets: Array[PackedVector2Array],
	segment_colors: Array[Array] = [],
	width_scales: Array[float] = []
) -> void:
	_segment_sets = segment_sets
	_segment_colors = segment_colors
	_width_scales = width_scales
	queue_redraw()


func _draw() -> void:
	for index in _segment_sets.size():
		var segments := _segment_sets[index]
		var colors: Array = _segment_colors[index] if index < _segment_colors.size() else []
		var scale: float = _width_scales[index] if index < _width_scales.size() else 1.0
		var core_width := ray_width * scale
		var halo_width := glow_width * scale
		if segments.size() < 2:
			continue
		var total_length := 0.0
		for length_index in segments.size() - 1:
			total_length += segments[length_index].distance_to(segments[length_index + 1])
		var remaining := total_length * clampf(visible_fraction, 0.0, 1.0)
		for segment_index in segments.size() - 1:
			var start := to_local(segments[segment_index])
			var segment_length := segments[segment_index].distance_to(segments[segment_index + 1])
			if remaining <= 0.0:
				break
			var end := to_local(segments[segment_index].move_toward(
				segments[segment_index + 1], minf(remaining, segment_length)))
			remaining -= segment_length
			var color := DEFAULT_COLOR
			if segment_index < colors.size():
				color = colors[segment_index]
			if preview_mode:
				var direction := (end - start).normalized()
				var distance := start.distance_to(end)
				var dash_start := 0.0
				while dash_start < distance:
					var dash_end := minf(dash_start + 9.0, distance)
					draw_line(start + direction * dash_start,
						start + direction * dash_end, Color(color, 0.6), core_width)
					dash_start += 15.0
			else:
				draw_line(start, end, Color(color, 0.22), halo_width)
				draw_line(start, end, color, core_width)
			if not preview_mode and segment_index == segments.size() - 2:
				draw_circle(end, halo_width * 0.5, Color(color, 0.3))
