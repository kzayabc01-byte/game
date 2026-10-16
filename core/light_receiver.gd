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

var _is_lit: bool = false


func _enter_tree() -> void:
	add_to_group(RECEIVER_GROUP)
	add_to_group(RESETTABLE_GROUP)
	collision_layer = RayCaster.LAYER_RECEIVER
	collision_mask = 0


## 当前是否被光线照到
func is_lit() -> bool:
	return _is_lit


## 由光线系统调用（组员不要手动调用）：设置光照状态
func apply_lit(value: bool) -> void:
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
