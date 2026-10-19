@tool
class_name MovingBase
extends Node2D

## 移动底座：纯执行器，自己不会动。
## 动作（移多少 / 转多少 / 时长 / 循环 / 恢复）全部由连接它的电线（ActionLink）决定——
## 电线移动根节点，挂在上面的镜子 / 门 / 石块等子节点会跟着一起动（位移+旋转同一动画）。
## 结构：根节点 = 平台；子节点 = 想带动的积木。

var _origin_position := Vector2.ZERO


func _ready() -> void:
	_origin_position = position


func _draw() -> void:
	# 占位外观：深色平台（整体随根节点移动/旋转）
	draw_rect(Rect2(-32, -10, 64, 20), Color(0.3, 0.28, 0.25))
	draw_rect(Rect2(-32, -10, 64, 20), Color(0.55, 0.5, 0.45), false, 2.0)
