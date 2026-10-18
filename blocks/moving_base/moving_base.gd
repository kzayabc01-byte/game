@tool
class_name MovingBase
extends Node2D

## 移动底座：沿 path_a ↔ path_b（本地偏移）往返移动的平台。
## 把镜子 / 门 / 石块等积木挂为它的子节点，它们会跟着一起动（物理自动同步）。
## - start_enabled=false：一开始停住，等触发机关 / 压力传感器用 set_enabled 开启
## - pause_at_ends：到两端停一会儿再折返（秒）
## 按 R 重置回到 path_a，并恢复初始启用状态。

signal end_reached(at_b: bool)

const RESETTABLE_GROUP := "resettables"

@export var path_a: Vector2 = Vector2.ZERO
@export var path_b: Vector2 = Vector2(0, 160)
@export var speed: float = 60.0
@export var pause_at_ends: float = 0.0
@export var start_enabled: bool = true

var _origin: Vector2
var _target: Vector2
var _moving_to_b: bool = true
var _wait: float = 0.0
var _enabled: bool = true


func _enter_tree() -> void:
	add_to_group(RESETTABLE_GROUP)


func _ready() -> void:
	_origin = position
	_target = _origin + path_b
	_moving_to_b = true
	_enabled = start_enabled
	# 编辑器里保持摆放位置不动，运行时才贴到 path_a 起点
	if not Engine.is_editor_hint():
		position = _origin + path_a


## 外部开关入口：触发机关 active_changed / 压力传感器 pressed_changed 连线用
func set_enabled(value: bool) -> void:
	_enabled = value


func reset_state() -> void:
	_enabled = start_enabled
	_target = _origin + path_b
	_moving_to_b = true
	_wait = 0.0
	position = _origin + path_a


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _enabled:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var to_target := _target - position
	var step := speed * delta
	if to_target.length() <= step:
		position = _target
		_wait = pause_at_ends
		end_reached.emit(_moving_to_b)
		_moving_to_b = not _moving_to_b
		_target = _origin + (path_b if _moving_to_b else path_a)
	else:
		position += to_target.normalized() * step


func _draw() -> void:
	# 占位外观：深色平台 + 轨道线（path_a ↔ path_b 本地坐标）
	draw_line(path_a, path_b, Color(0.3, 0.33, 0.4), 2.0)
	draw_rect(Rect2(-32, -10, 64, 20), Color(0.3, 0.28, 0.25))
	draw_rect(Rect2(-32, -10, 64, 20), Color(0.55, 0.5, 0.45), false, 2.0)
	if path_a.length_squared() > 0.01:
		draw_circle(path_a, 5.0, Color(0.5, 0.55, 0.6, 0.6))
	if path_b.length_squared() > 0.01:
		draw_circle(path_b, 5.0, Color(0.5, 0.55, 0.6, 0.6))
