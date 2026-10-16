class_name LightReceiver
extends Area2D

## 【组员接口】所有机关（含蚕茧）的基类。
##
## 用法：
## 1. 新建场景，根节点选 Area2D，挂上「继承本类」的脚本
## 2. 给根节点加 CollisionShape2D —— 形状就是感光区
## 3. 实现 on_lit() / on_unlit()，光线照到/离开时由光线系统自动调用
##
## 无需手动设置：根节点会自动加入 light_receivers、resettables 组，
## 并自动放到「机关接收区」碰撞层（第 3 层）。

signal lit_changed(is_lit: bool)

const RECEIVER_GROUP := "light_receivers"
const RESETTABLE_GROUP := "resettables"

## 颜色感应：match_color 为 true 时，只有颜色等于 color_filter 的光才触发本机关
@export var color_filter: Color = Color.WHITE
@export var match_color: bool = false

var _is_lit: bool = false
var _light_color: Color = Color.WHITE


func _enter_tree() -> void:
	add_to_group(RECEIVER_GROUP)
	add_to_group(RESETTABLE_GROUP)
	collision_layer = RayCaster.LAYER_RECEIVER
	collision_mask = 0


## 当前是否被光线照到
func is_lit() -> bool:
	return _is_lit


## 当前照在机关上的光线颜色（可在 on_lit() / on_light_frame() 里读取）
func get_light_color() -> Color:
	return _light_color


## 光线系统用这个判断某条光是否对本机关有效（颜色感应机关靠它过滤）
func accepts(color: Color) -> bool:
	if not match_color:
		return true
	return color.is_equal_approx(color_filter)


## 由光线系统调用（组员不要手动调用）：设置光照状态与命中颜色
func apply_lit(value: bool, color: Color = Color.WHITE) -> void:
	if value:
		_light_color = color
	if value == _is_lit:
		return
	_is_lit = value
	lit_changed.emit(value)
	if value:
		on_lit()
	else:
		on_unlit()


## —— 组员实现以下回调 ——

## 光线照到机关（上升沿，只触发一次）
func on_lit() -> void:
	pass


## 光线离开机关（下降沿，只触发一次）
func on_unlit() -> void:
	pass


## 机关被持续照射时每物理帧调用（做持续效果时用，可选）
func on_light_frame(delta: float) -> void:
	pass


## 按 R 重置关卡时调用，恢复机关初始状态（有状态才需要实现）
func reset_state() -> void:
	pass
