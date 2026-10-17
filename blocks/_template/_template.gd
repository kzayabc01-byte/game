class_name BlockTemplate
extends LightReceiver

## 【积木模板 · 机关类】新机关从这里复制（推荐用 tools\tasks\90_新建积木.bat 自动生成）。
##
## 改动清单：
##   1. 类名改成你自己的（全项目唯一，建议带前缀：RotatingMirror、TimedDoor……）
##   2. 调 SensorShape 的大小/位置 = 感光区范围（别把光源整个包进去）
##   3. 实现 on_lit() / on_unlit()；有持久状态的实现 reset_state()（按 R 会调用）
##   4. 需要挡光的部分做成子节点（碰撞层 1），本节点自己是层 3，别混
##
## 本类的 _draw() 只是占位外观，接美术时换成 Sprite2D / AnimatedSprite2D 即可。

signal poked


func _ready() -> void:
	lit_changed.connect(_on_lit_changed)
	queue_redraw()


func _on_lit_changed(_is_lit: bool) -> void:
	queue_redraw()


## 光线照到（上升沿，只触发一次）
func on_lit() -> void:
	poked.emit()


## 光线离开（下降沿，只触发一次）
func on_unlit() -> void:
	pass


## 持续照射时每物理帧调用（可选）
func on_light_frame(_delta: float) -> void:
	pass


## 按 R 重置关卡时恢复初始状态（有状态才需要实现）
func reset_state() -> void:
	queue_redraw()


func _draw() -> void:
	var color := Color(0.35, 0.85, 0.95, 0.9) if is_lit() else Color(0.32, 0.44, 0.52, 0.9)
	draw_rect(Rect2(-24.0, -24.0, 48.0, 48.0), color, false, 2.0)
	draw_circle(Vector2.ZERO, 6.0, color)
