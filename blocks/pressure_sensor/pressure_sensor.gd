@tool
class_name PressureSensor
extends Area2D

## 压力传感器：有重物（heavy_objects 组的石块）压住时发出 pressed_changed 信号。
## 不是感光机关（不继承 LightReceiver，见开发指南"常见坑"）。
## 用法：关卡里用编辑器信号面板把 pressed_changed 连给石门 set_external_open /
## 移动底座 set_enabled 等入口。重置时重发当前状态，让连线机关恢复一致。
## 实现：每物理帧轮询重叠物体（重物瞬移/重置时 body_entered 可能漏发，轮询最可靠）。

signal pressed_changed(pressed: bool)

const HEAVY_GROUP := "heavy_objects"
const RESETTABLE_GROUP := "resettables"

var _pressed: bool = false


func _enter_tree() -> void:
	add_to_group(RESETTABLE_GROUP)
	collision_layer = 0
	collision_mask = RayCaster.LAYER_OPAQUE  # 只检测遮光物层的重物（再按组过滤）


## 当前是否被重物压住
func is_pressed() -> bool:
	return _pressed


func reset_state() -> void:
	# 重发当前状态：重物可能没动，但连线的机关（石门等）重置后需要重新同步
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
	# 占位外观：压力板，压下时指示灯亮
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var size := Vector2(56, 56)
	if shape_node != null and shape_node.shape is RectangleShape2D:
		size = (shape_node.shape as RectangleShape2D).size
	var half := size / 2.0
	draw_rect(Rect2(-half, size), Color(0.16, 0.17, 0.2))
	draw_rect(Rect2(-half, size), Color(0.5, 0.53, 0.6), false, 2.0)
	var lamp := Color(0.95, 0.5, 0.25) if _pressed else Color(0.35, 0.38, 0.44)
	draw_circle(Vector2.ZERO, minf(half.x, half.y) * 0.25, lamp)
