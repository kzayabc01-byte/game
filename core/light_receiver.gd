class_name LightReceiver
extends Area2D

## 【组员接口】所有机关（含蚕茧）的基类。
##
## 用法：
## 1. 新建场景，根节点选 Area2D，挂上「继承本类」的脚本
## 2. 给根节点加 CollisionShape2D —— 形状就是感光区
## 3. 实现 on_lit() / on_unlit()，光线照到/离开时由光线系统自动调用
##
## 颜色支持：received_colors 记录当前照到本机关的所有光色（光线系统维护）；
## 需要认颜色的机关用 matches_color() 判断（带容差，禁止直接用 == 比色）。
##
## 无需手动设置：根节点会自动加入 light_receivers、resettables 组，
## 并自动放到「机关接收区」碰撞层（第 3 层）。

signal lit_changed(is_lit: bool)

const RECEIVER_GROUP := "light_receivers"
const RESETTABLE_GROUP := "resettables"

## 颜色匹配容差：各颜色通道差值在此范围内视为同色（光路运算会产生浮点误差）
const COLOR_MATCH_TOLERANCE := 0.08

var _is_lit: bool = false

## 当前照到本机关的所有光色（光线系统每帧维护，机关代码只读）
var received_colors: Array[Color] = []


func _enter_tree() -> void:
	add_to_group(RECEIVER_GROUP)
	add_to_group(RESETTABLE_GROUP)
	collision_layer = RayCaster.LAYER_RECEIVER
	collision_mask = 0


## 当前是否被光线照到
func is_lit() -> bool:
	return _is_lit


## 由光线系统调用（组员不要手动调用）：设置光照状态与照到的颜色
func apply_lit(value: bool, colors: Array = []) -> void:
	_set_received_colors(colors)
	if value == _is_lit:
		return
	_is_lit = value
	lit_changed.emit(value)
	if value:
		on_lit()
	else:
		on_unlit()


## 照到本机关的光里是否包含 target 颜色（带容差；alpha 不参与比较）
func matches_color(target: Color, tolerance: float = COLOR_MATCH_TOLERANCE) -> bool:
	for color in received_colors:
		if _colors_close(color, target, tolerance):
			return true
	return false


static func _colors_close(a: Color, b: Color, tolerance: float) -> bool:
	return (
		absf(a.r - b.r) <= tolerance
		and absf(a.g - b.g) <= tolerance
		and absf(a.b - b.b) <= tolerance
	)


func _set_received_colors(colors: Array) -> void:
	received_colors.clear()
	for color in colors:
		if color is Color and not received_colors.has(color):
			received_colors.append(color)


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
