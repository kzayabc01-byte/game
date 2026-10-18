class_name LightRayRenderer
extends Node2D

## 光线可视化（占位实现）：把光线系统算出的光束画出来，每束用自己的颜色。
## 后续接入美术时，用粒子 / Shader 替换这里的绘制即可，
## 光线计算（RayCaster）不受影响。

var ray_width: float = 3.0
var glow_width: float = 12.0

var _traces: Array = []


## 由光线系统每帧调用：传入本次追踪的所有光束（含颜色，世界坐标）
func set_traces(traces: Array) -> void:
	_traces = traces
	queue_redraw()


func _draw() -> void:
	for trace in _traces:
		var segments: PackedVector2Array = trace.segments
		if segments.size() < 2:
			continue
		var color: Color = trace.color
		var local_points := PackedVector2Array()
		for point in segments:
			local_points.append(to_local(point))
		draw_polyline(local_points, Color(color, 0.22), glow_width)
		draw_polyline(local_points, color, ray_width)
		var tip := local_points[local_points.size() - 1]
		draw_circle(tip, glow_width * 0.5, Color(color, 0.3))
