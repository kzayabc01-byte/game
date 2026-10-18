class_name MainMenu
extends Control

## 主菜单：自动按 LEVEL_PATHS 生成关卡按钮。
## 组员做好新关卡后，在下面两个数组里登记一行即可。

const LEVEL_PATHS: Array[String] = [
	"res://scenes/levels/level_01.tscn",
	"res://scenes/levels/level_02.tscn",
]

const LEVEL_NAMES: Array[String] = [
	"示例关卡 · 两段式开门",
	"机关秀 · 实体机关组",
]

@onready var _level_list: VBoxContainer = %LevelList
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	GameEvents.level_completed.connect(_on_level_completed)
	_create_level_buttons()
	%QuitButton.pressed.connect(_on_quit_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _create_level_buttons() -> void:
	for index in LEVEL_PATHS.size():
		var button := Button.new()
		var level_name := "关卡 %d" % (index + 1)
		if index < LEVEL_NAMES.size():
			level_name = LEVEL_NAMES[index]
		button.text = "%d · %s" % [index + 1, level_name]
		button.custom_minimum_size = Vector2(320.0, 48.0)
		button.pressed.connect(_on_level_pressed.bind(index))
		_level_list.add_child(button)


func _on_level_pressed(index: int) -> void:
	get_tree().change_scene_to_file(LEVEL_PATHS[index])


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_level_completed(level_name: String) -> void:
	_status_label.text = "最近完成：%s" % level_name
