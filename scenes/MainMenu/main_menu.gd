extends Control

const LEVEL_SELECT_SCENE := "res://scenes/LevelSelectPage/LevelSelectPage.tscn"

func _ready() -> void:
	$MenuGroup/StartButton.pressed.connect(_on_start_pressed)
	$MenuGroup/SelectButton.pressed.connect(_on_select_pressed)
	$WorkshopButton.pressed.connect(_on_workshop_pressed)
	$MenuGroup/ExitButton.pressed.connect(_on_exit_pressed)
	$WorkshopButton.visible = OS.is_debug_build()


func _on_start_pressed() -> void:
	_open_level_select(false)


func _on_select_pressed() -> void:
	_open_level_select(false)


func _on_workshop_pressed() -> void:
	_open_level_select(true)


func _open_level_select(workshop: bool) -> void:
	LevelSelectPage.open_workshop_on_entry = workshop
	if get_tree().change_scene_to_file(LEVEL_SELECT_SCENE) != OK:
		LevelSelectPage.open_workshop_on_entry = false


func _on_exit_pressed() -> void:
	get_tree().quit()
