extends Control

const LEVEL_SELECT_SCENE := "res://scenes/LevelSelectPage/LevelSelectPage.tscn"
const LEVEL_DIR := "res://scenes/levels/"

func _ready() -> void:
	$MenuGroup/StartButton.pressed.connect(_on_start_pressed)
	$MenuGroup/SelectButton.pressed.connect(_on_select_pressed)
	$WorkshopButton.pressed.connect(_on_workshop_pressed)
	$MenuGroup/ExitButton.pressed.connect(_on_exit_pressed)
	$WorkshopButton.visible = OS.is_debug_build()


func _on_start_pressed() -> void:
	var first_path := ""
	var first_chapter := 100
	var first_order := 100
	for file_name in LevelFileIO.scan_levels():
		var path := LEVEL_DIR + file_name
		var metadata := LevelFileIO.read_level_metadata(path)
		if int(metadata.get(&"publication_state", LevelManager.PublicationState.DRAFT)) \
				!= LevelManager.PublicationState.PUBLISHED:
			continue
		var chapter := maxi(int(metadata.get(&"chapter", 1)), 1)
		var order := maxi(int(metadata.get(&"order_in_chapter", 1)), 1)
		if first_path.is_empty() or chapter < first_chapter \
				or (chapter == first_chapter and order < first_order) \
				or (chapter == first_chapter and order == first_order and path < first_path):
			first_path = path
			first_chapter = chapter
			first_order = order
	if first_path.is_empty():
		_open_level_select(false)
	else:
		get_tree().change_scene_to_file(first_path)


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
