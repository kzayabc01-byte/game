@tool
class_name PressureSensor
extends Area2D

## 压力传感器：有重物（heavy_objects 组的石块）压住时发出 pressed_changed 信号。
## 不是感光机关（不继承 LightReceiver，见开发指南"常见坑"）。
## 用法：关卡里用编辑器把 pressed_changed 拖线连到电线（ActionLink）的 _on_signal，
## 机关动作（移多少/转多少/时长/循环/恢复）在电线上配置。重置时重发当前状态，让电线恢复一致。
## 实现：每物理帧轮询重叠物体（重物瞬移/重置时 body_entered 可能漏发，轮询最可靠）。

signal pressed_changed(pressed: bool)

const HEAVY_GROUP := "heavy_objects"
const RESETTABLE_GROUP := "resettables"

@export_category("视觉 / Visual")
@export_color_no_alpha var inactive_color: Color = MechanismPalette.ORANGE_GLOW:
	set(value):
		inactive_color = value
		queue_redraw()
@export_color_no_alpha var active_color: Color = MechanismPalette.CYAN_GLOW:
	set(value):
		active_color = value
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var color_concentration: float = 0.82:
	set(value):
		color_concentration = value
		queue_redraw()
@export_range(0.0, 2.0, 0.01) var glow_strength: float = 0.58:
	set(value):
		glow_strength = value
		queue_redraw()

var _pressed: bool = false


func _enter_tree() -> void:
	add_to_group(RESETTABLE_GROUP)
	collision_layer = 0
	collision_mask = RayCaster.LAYER_OPAQUE  # 只检测遮光物层的重物（再按组过滤）


## 当前是否被重物压住
func is_pressed() -> bool:
	return _pressed


## 关卡编辑器的瞬时验证状态；不依赖物理重叠，也不会写入关卡。
func set_editor_preview_active(active: bool) -> void:
	_pressed = active
	queue_redraw()


func reset_state() -> void:
	# 重发当前状态：重物可能没动，但被电线驱动的目标重置后需要重新同步
	pressed_changed.emit(_pressed)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var heavy_count := 0
	for body in get_overlapping_bodies():
		if body.is_in_group(HEAVY_GROUP):
			heavy_count += 1
	var now := heavy_count > 0
	if now == _pressed:
		return
	_pressed = now
	pressed_changed.emit(now)
	queue_redraw()


func _draw() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(56, 56)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var radius := minf(size.x, size.y) * 0.5
	var state_color := active_color if _pressed else inactive_color
	var accent := MechanismPalette.concentrate(
		MechanismPalette.MUTED_SURFACE, state_color, color_concentration)
	draw_circle(Vector2.ZERO, radius, MechanismPalette.DARK_SURFACE)
	draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 40, Color(accent, 0.38 + glow_strength * 0.25), 5.0)
	draw_arc(Vector2.ZERO, radius - 6.0, 0.0, TAU, 40, accent, 2.0)
	draw_circle(Vector2.ZERO, radius * 0.56, MechanismPalette.MUTED_SURFACE)
	draw_circle(Vector2.ZERO, radius * 0.28, accent)
	var notch_y := -radius * 0.72
	for index in 4:
		var notch_x := lerpf(-radius * 0.42, radius * 0.42, float(index) / 3.0)
		draw_line(Vector2(notch_x, notch_y - 2.0), Vector2(notch_x, notch_y + 3.0), accent, 1.5)
