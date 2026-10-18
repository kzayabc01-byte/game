@tool
class_name ColorSensor
extends LightReceiver

## 【颜色组 · 颜色感应机关】照到的光里包含 match_color 颜色才算「匹配」。
##
## 用法：
##   1. 拖进关卡，检查器里改 match_color = 要认的颜色
##   2. color_filter = true（默认）：颜色不符不触发；false = 任何颜色都触发
##   3. 用 is_matched() / 信号 matched_changed 驱动门、灯、平台等
##      （参考 blocks/light_door/ 的做法：把状态接到门板子节点上）
##
## 其他不同外观的颜色机关：同样继承 LightReceiver，直接复用 matches_color() 判色，
## 不要自己用 == 比颜色（浮点误差会误判）。

signal matched_changed(matched: bool)

@export var match_color: Color = Color.RED
@export var color_filter: bool = true

var _matched: bool = false


## 当前是否处于「颜色匹配」状态
func is_matched() -> bool:
	return _matched


func _check_match() -> void:
	var now := is_lit() and (not color_filter or matches_color(match_color))
	if now == _matched:
		return
	_matched = now
	matched_changed.emit(now)
	queue_redraw()


func on_lit() -> void:
	_check_match()


func on_unlit() -> void:
	_check_match()


func on_light_frame(_delta: float) -> void:
	_check_match()


func reset_state() -> void:
	if _matched:
		_matched = false
		matched_changed.emit(false)
	queue_redraw()


func _draw() -> void:
	# 占位外观：感应圈染成 match_color；匹配时变亮；关闭滤色时中心加个点作提示
	var sensor_shape := get_node_or_null("SensorShape") as CollisionShape2D
	var radius := 20.0
	if sensor_shape != null and sensor_shape.shape is CircleShape2D:
		radius = (sensor_shape.shape as CircleShape2D).radius
	var fill_alpha := 0.75 if _matched else 0.28
	draw_circle(Vector2.ZERO, radius, Color(match_color, fill_alpha))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(match_color, 0.9), 2.0)
	if not color_filter:
		draw_circle(Vector2.ZERO, radius * 0.35, Color(match_color, 0.9))
