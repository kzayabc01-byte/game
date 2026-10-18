@tool
class_name TriggerSwitch
extends LightReceiver

## 触发机关：最简感光开关，给别的机关当"开关信号源"。
## - latch=false（默认）：光照着就激活，光离开就关闭（active_changed 跟随光照）
## - latch=true：照到一次就保持激活，按 R 重置才关闭
## 用法：关卡里用编辑器信号面板把 active_changed 连给石门 set_external_open /
## 移动底座 set_enabled 等入口。重置时本机关会重发当前状态，让连线机关恢复一致。

signal active_changed(active: bool)

@export var latch: bool = false

var _latched: bool = false
var _active: bool = false


func _ready() -> void:
	lit_changed.connect(_on_lit_changed)


## 当前开关是否激活（= 光照着，或已锁存）
func is_active() -> bool:
	return _active


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
	# 占位外观：感光板，激活时亮起命中颜色
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(40, 40)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0
	var glow := get_light_color() if _active else Color(0.32, 0.35, 0.42)
	draw_rect(Rect2(-half, size), Color(0.12, 0.13, 0.17))
	draw_rect(Rect2(-half, size), Color(glow, 0.8), false, 3.0)
	draw_circle(Vector2.ZERO, minf(half.x, half.y) * 0.35, glow if _active else Color(0.25, 0.28, 0.34))
