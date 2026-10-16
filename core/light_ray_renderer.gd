class_name LightRayRenderer
extends Node2D

## 光线可视化（占位实现）：把光线系统算出的折线画出来。
## 后续接入美术时，用粒子 / Shader 替换这里的绘制即可，
## 光线计算（RayCaster）不受影响。

var ray_color: Color = Color(1.0, 0.85, 0.3)
var ray_width: float = 3.0
var glow_width: float = 12.0

var _segment_sets: Array[PackedVector2Array] = []


## 由光线系统每帧调用：传入每条光线的折线顶点（世界坐标）
func set_segments(segment_sets: Array[PackedVector2Array]) -> void:
	_segment_sets = segment_sets
	queue_redraw()


func _draw() -> void:
	for segments in _segment_sets:
		if segments.size() < 2:
			continue
		var local_points := PackedVector2Array()
		for point in segments:
			local_points.append(to_local(point))
		draw_polyline(local_points, Color(ray_color, 0.22), glow_width)
		draw_polyline(local_points, ray_color, ray_width)
		var tip := local_points[local_points.size() - 1]
		draw_circle(tip, glow_width * 0.5, Color(ray_color, 0.3))
