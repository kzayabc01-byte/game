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
@export var main_menu_scene: PackedScene = preload("res://scenes/MainMenu/MainMenu.tscn")

const LEVEL_SELECT_SCENE := "res://scenes/LevelSelectPage/LevelSelectPage.tscn"

@onready var _win_label: Label = $LevelHUD/WinLabel
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _resume_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/ResumeButton
@onready var _restart_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/RestartButton
@onready var _select_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/SelectButton
@onready var _home_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/HomeButton
var _won: bool = false


func _ready() -> void:
	_win_label.hide()
	_pause_menu.hide()
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_resume_button.pressed.connect(_on_resume_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_select_button.pressed.connect(_on_select_pressed)
	_home_button.pressed.connect(_on_home_pressed)
	# 延后到所有节点 ready 之后再连接蚕茧，避免错过任何蚕茧
	call_deferred("_connect_cocoons")


func _connect_cocoons() -> void:
	for node in get_tree().get_nodes_in_group(Cocoon.COCOON_GROUP):
		var cocoon := node as Cocoon
		if cocoon != null:
			cocoon.activated.connect(_on_cocoon_activated)


func _input(event: InputEvent) -> void:
	if SceneTransition.is_transitioning():
		return
	if event.is_action_pressed("ui_cancel"):
		_set_paused(not _pause_menu.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_level") and not _pause_menu.visible:
		reset_level()


func _set_paused(should_pause: bool) -> void:
	_pause_menu.visible = should_pause
	get_tree().paused = should_pause
	if should_pause:
		_resume_button.grab_focus()


func _on_resume_pressed() -> void:
	_set_paused(false)


func _on_restart_pressed() -> void:
	SceneTransition.restart_current_scene()


func _on_select_pressed() -> void:
	LevelSelectPage.open_workshop_on_entry = false
	SceneTransition.change_to_file(LEVEL_SELECT_SCENE)


func _on_home_pressed() -> void:
	SceneTransition.change_to_packed(main_menu_scene)


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
		await get_tree().create_timer(1.5, false).timeout
		get_tree().change_scene_to_packed(next_level_scene)
