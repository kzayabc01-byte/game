@tool
class_name ActionLink
extends Node2D

## 电线（动作连线）：关卡里不可见的节点，把「开关信号」翻译成「机关动作」。
## 开关 ON → 机关从原位运动到动作位（move_offset 位移 + rotate_degrees 旋转，同一动画）；
## OFF → restore_on_off 为真时回原位，否则停在当前位；
## repeat 为真时 ON 期间在原位↔动作位往返循环。
## 保存进关卡文件的就是这个节点（target_node + 动作参数）加一条开关信号连接；
## 游戏里无外观 → 电线只对创作者可见（编辑器 WireLayer 把它画成曲线）。
## 按 R 重置：机关回原位；若开关仍然 ON（光一直照着 / 重物一直压着）会延迟复查重放。

const RESETTABLE_GROUP := "resettables"
const METHOD_NAME := &"_on_signal"

@export var target_node: NodePath
@export var move_offset: Vector2 = Vector2(0, -60)
@export var rotate_degrees: float = 0.0
@export var duration: float = 0.8
@export var repeat: bool = false
@export var restore_on_off: bool = true

var _target: Node2D = null
var _origin_position := Vector2.ZERO
var _origin_rotation := 0.0
var _active := false
var _tween: Tween = null


func _enter_tree() -> void:
	add_to_group(RESETTABLE_GROUP)


func _ready() -> void:
	resolve_target()


## 编辑器在进树后才设置 target_node（_ready 已跑过）：补一次解析
func resolve_target() -> void:
	_target = get_node_or_null(target_node) as Node2D
	if is_instance_valid(_target):
		_origin_position = _target.position
		_origin_rotation = _target.rotation


## 电线目标机关（编辑器画线用）
func get_target() -> Node2D:
	return _target


func is_active() -> bool:
	return _active


## 开关信号入口：active_changed / pressed_changed 都连到这里
func _on_signal(active: bool) -> void:
	if _active == active:
		return
	_active = active
	_apply()


func reset_state() -> void:
	_active = false
	_kill_tween()
	if is_instance_valid(_target):
		_target.position = _origin_position
		_target.rotation = _origin_rotation
	# 重置时开关可能仍处于 ON 且不会重发信号（状态没变）：延迟复查一次
	call_deferred("_recheck_source")


## 通过入向连接找到开关并查询其当前状态（重置后重新同步用）。
## 手改关卡可能把多个开关接到同一条电线上：任一开关 ON 即算 ON。
func _recheck_source() -> void:
	var found := false
	var any_active := false
	for conn in get_incoming_connections():
		var sig: Signal = conn.get("signal")
		if sig.get_object() == null:
			continue
		var source := sig.get_object() as Node
		if source == null:
			continue
		if source.has_method(&"is_active"):
			found = true
			any_active = any_active or bool(source.call(&"is_active"))
		elif source.has_method(&"is_pressed"):
			found = true
			any_active = any_active or bool(source.call(&"is_pressed"))
	if found:
		_on_signal(any_active)


func _apply() -> void:
	if not is_instance_valid(_target):
		return
	_kill_tween()
	var action_position := _origin_position + move_offset
	var action_rotation := _origin_rotation + deg_to_rad(rotate_degrees)
	var time := maxf(duration, 0.01)
	if _active:
		_tween = create_tween()
		if repeat:
			# 循环：原位 → 动作位 → 原位，无限往返
			_tween.set_loops()
			_tween.tween_property(_target, "position", action_position, time) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_tween.parallel().tween_property(_target, "rotation", action_rotation, time) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_tween.tween_property(_target, "position", _origin_position, time) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_tween.parallel().tween_property(_target, "rotation", _origin_rotation, time) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			_tween.tween_property(_target, "position", action_position, time) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_tween.parallel().tween_property(_target, "rotation", action_rotation, time) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif restore_on_off:
		_tween = create_tween()
		_tween.tween_property(_target, "position", _origin_position, time) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween.parallel().tween_property(_target, "rotation", _origin_rotation, time) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# restore_on_off 为假且 OFF：停在当前位（半路断开也停，tween 已 kill）


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
