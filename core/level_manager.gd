class_name LevelManager
extends Node

## 关卡管理器：连接蚕茧、处理胜利与重置、显示界面提示。
## 用法：每个关卡场景放一个本节点（level_base 已放好），
## 在检查器里设置 level_name 和 next_level_scene。

enum PublicationState { DRAFT, PUBLISHED }

@export var level_name: String = "关卡 1"
@export var publication_state: PublicationState = PublicationState.DRAFT
@export_range(1, 99, 1) var chapter: int = 1
@export_range(1, 99, 1) var order_in_chapter: int = 1
@export_range(1, 5, 1) var difficulty: int = 1
@export var mechanic_tags: PackedStringArray = []
@export var next_level_scene: PackedScene
@export var main_menu_scene: PackedScene = preload("res://scenes/main/main.tscn")

var _win_label: Label
var _won: bool = false


func _ready() -> void:
	_create_ui()
	# 延后到所有节点 ready 之后再连接蚕茧，避免错过任何蚕茧
	call_deferred("_connect_cocoons")


func _connect_cocoons() -> void:
	for node in get_tree().get_nodes_in_group(Cocoon.COCOON_GROUP):
		var cocoon := node as Cocoon
		if cocoon != null:
			cocoon.activated.connect(_on_cocoon_activated)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_level"):
		reset_level()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_packed(main_menu_scene)


## 重置整个关卡：光源回到初始角度，机关回到初始状态
func reset_level() -> void:
	_won = false
	_win_label.hide()
	get_tree().call_group("resettables", "reset_state")
	GameEvents.game_reset.emit()


func _on_cocoon_activated() -> void:
	if _won:
		return
	_won = true
	GameEvents.level_completed.emit(level_name)
	_win_label.text = "%s 完成！蚕茧已激发" % level_name
	_win_label.show()
	if next_level_scene != null:
		await get_tree().create_timer(1.5).timeout
		get_tree().change_scene_to_packed(next_level_scene)


func _create_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	_win_label = Label.new()
	_win_label.set_anchors_preset(Control.PRESET_CENTER)
	_win_label.offset_left = -400.0
	_win_label.offset_right = 400.0
	_win_label.offset_top = -70.0
	_win_label.offset_bottom = 70.0
	_win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_win_label.add_theme_font_size_override("font_size", 48)
	_win_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
	_win_label.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.1))
	_win_label.add_theme_constant_override("outline_size", 10)
	_win_label.hide()
	ui.add_child(_win_label)

	var hint := Label.new()
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -44.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "拖拽光源转动方向 · Q/E 微调 · Shift+Q/E 精细微调 · R 重置关卡 · Esc 返回菜单"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.72, 0.75, 0.82))
	ui.add_child(hint)
