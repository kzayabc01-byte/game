class_name LightRayRenderer
extends Node2D

## 光线可视化（占位实现）：把光线系统算出的折线画出来，每段可不同颜色。
## 后续接入美术时，用粒子 / Shader 替换这里的绘制即可，
## 光线计算（RayCaster）不受影响。

const DEFAULT_COLOR := Color(1.0, 0.85, 0.3)

var ray_width: float = 3.0
var glow_width: float = 12.0

var _segment_sets: Array[PackedVector2Array] = []
var _segment_colors: Array[Array] = []  # 与 _segment_sets 一一对应：Array[Color]


## 由光线系统每帧调用：传入每条光线的折线顶点（世界坐标）与每段颜色
func set_segments(segment_sets: Array[PackedVector2Array], segment_colors: Array[Array] = []) -> void:
	_segment_sets = segment_sets
	_segment_colors = segment_colors
	queue_redraw()


func _draw() -> void:
	for index in _segment_sets.size():
		var segments := _segment_sets[index]
		var colors: Array = _segment_colors[index] if index < _segment_colors.size() else []
		if segments.size() < 2:
			continue
		for segment_index in segments.size() - 1:
			var start := to_local(segments[segment_index])
			var end := to_local(segments[segment_index + 1])
			var color := DEFAULT_COLOR
			if segment_index < colors.size():
				color = colors[segment_index]
			draw_line(start, end, Color(color, 0.22), glow_width)
			draw_line(start, end, color, ray_width)
			if segment_index == segments.size() - 2:
				draw_circle(end, glow_width * 0.5, Color(color, 0.3))
