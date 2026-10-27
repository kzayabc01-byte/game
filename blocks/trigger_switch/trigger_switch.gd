@tool
class_name TriggerSwitch
extends LightReceiver

## 触发机关：最简感光开关，给别的机关当"开关信号源"。
## - latch=false（默认）：光照着就激活，光离开就关闭（active_changed 跟随光照）
## - latch=true：照到一次就保持激活，按 R 重置才关闭
## 用法：关卡里用编辑器把 active_changed 拖线连到电线（ActionLink）的 _on_signal，
## 机关动作（移多少/转多少/时长/循环/恢复）在电线上配置。重置时重发当前状态，让电线恢复一致。

signal active_changed(active: bool)

@export var latch: bool = false
@export_category("视觉 / Visual")
@export_color_no_alpha var inactive_color: Color = MechanismPalette.ORANGE_GLOW:
	set(value):
		inactive_color = value
		queue_redraw()
@export_color_no_alpha var active_color: Color = MechanismPalette.CYAN_GLOW:
	set(value):
		active_color = value
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var color_concentration: float = 0.88:
	set(value):
		color_concentration = value
		queue_redraw()
@export_range(0.0, 2.0, 0.01) var glow_strength: float = 0.72:
	set(value):
		glow_strength = value
		queue_redraw()

var _latched: bool = false
var _active: bool = false


func _ready() -> void:
	lit_changed.connect(_on_lit_changed)


## 当前开关是否激活（= 光照着，或已锁存）
func is_active() -> bool:
	return _active


## 关卡编辑器的瞬时验证状态；不改变光照、自锁或序列化数据。
func set_editor_preview_active(active: bool) -> void:
	_active = active
	queue_redraw()


func on_lit() -> void:
	if latch:
		_latched = true
	_update_active()


func on_unlit() -> void:
	_update_active()


func reset_state() -> void:
	_latched = false
	_update_active()


func _update_active() -> void:
	var now := is_lit() or _latched
	if now == _active:
		return
	_active = now
	active_changed.emit(now)
	queue_redraw()


func _on_lit_changed(_value: bool) -> void:
	queue_redraw()


func _draw() -> void:
	var shape_node := get_node_or_null("SensorShape") as CollisionShape2D
	var size := Vector2(40, 40)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var radius := minf(size.x, size.y) * 0.5
	var state_color := active_color if _active else inactive_color
	var accent := MechanismPalette.concentrate(
		MechanismPalette.MUTED_SURFACE, state_color, color_concentration)
	if _active and is_lit():
		accent = accent.lerp(get_light_color(), 0.16)
	draw_circle(Vector2.ZERO, radius, MechanismPalette.DARK_SURFACE)
	draw_arc(Vector2.ZERO, radius - 1.5, 0.0, TAU, 40, Color(accent, 0.3 + glow_strength * 0.28), 5.0)
	draw_arc(Vector2.ZERO, radius - 4.0, 0.0, TAU, 40, accent, 2.0)
	draw_circle(Vector2.ZERO, radius * 0.43, accent.darkened(0.08))
	draw_circle(Vector2(-radius * 0.13, -radius * 0.13), radius * 0.12, Color(MechanismPalette.LIGHT_EDGE, 0.72))
