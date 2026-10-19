class_name MainMenu
extends Control

## 主菜单：自动扫描 scenes/levels/ 下的关卡场景生成按钮。
##
## 加新关卡 = 把文件放进 scenes/levels/，再在编辑器里填好 LevelManager 的 level_name，
## 不用改本文件。
##   * 顺序：按文件名排序，约定 level_NN_说明.tscn（NN 两位数）
##   * 显示名：优先读关卡里 LevelManager.level_name；没填就按文件名兜底
##   * level_base.tscn 这类模板不会被当成关卡（前缀后必须是数字）

const LEVEL_DIR := "res://scenes/levels"
const LEVEL_PREFIX := "level_"

@onready var _level_list: VBoxContainer = %LevelList
@onready var _status_label: Label = %StatusLabel

var _levels: Array[String] = []


func _ready() -> void:
	GameEvents.level_completed.connect(_on_level_completed)
	_levels = _discover_levels()
	_create_level_buttons()
	%QuitButton.pressed.connect(_on_quit_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


## 扫描关卡目录，按文件名排序（level_01 → level_02 → …）
func _discover_levels() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(LEVEL_DIR)
	if dir == null:
		push_warning("找不到关卡目录：%s" % LEVEL_DIR)
		return result

	var names: Array[String] = []
	for entry in dir.get_files():
		var file_name := entry.trim_suffix(".remap")  # 导出后资源名可能带 .remap
		if not file_name.ends_with(".tscn"):
			continue
		if not file_name.begins_with(LEVEL_PREFIX):
			continue
		var short := file_name.trim_prefix(LEVEL_PREFIX)
		if short.is_empty() or not short.substr(0, 1).is_valid_int():
			continue  # level_base.tscn 之类的模板不算关卡
		if not names.has(file_name):
			names.append(file_name)

	names.sort()
	for file_name in names:
		result.append(LEVEL_DIR + "/" + file_name)
	return result


func _create_level_buttons() -> void:
	if _levels.is_empty():
		var empty := Label.new()
		empty.text = "没有找到关卡：把 level_XX.tscn 放进 scenes/levels/"
		_level_list.add_child(empty)
		return

	for index in _levels.size():
		var button := Button.new()
		button.text = "%d · %s" % [index + 1, _level_title(_levels[index])]
		button.custom_minimum_size = Vector2(320.0, 48.0)
		button.pressed.connect(_on_level_pressed.bind(index))
		_level_list.add_child(button)

	# 关卡编辑器入口：只出现在 debug 构建（玩家正式版看不到）
	if OS.is_debug_build():
		var editor_button := Button.new()
		editor_button.text = "关卡编辑器（仅 debug 构建）"
		editor_button.custom_minimum_size = Vector2(320.0, 48.0)
		editor_button.pressed.connect(func() -> void:
			get_tree().change_scene_to_file("res://scenes/editor/level_editor.tscn"))
		_level_list.add_child(editor_button)


## 关卡显示名：优先读关卡里 LevelManager 的 level_name，没填就按文件名兜底
func _level_title(path: String) -> String:
	var from_scene := _title_from_scene(path)
	if not from_scene.is_empty():
		return from_scene
	return _title_from_file(path)


## 从场景数据里读 LevelManager.level_name（不实例化场景，避免跑关卡逻辑）
func _title_from_scene(path: String) -> String:
	var packed := load(path) as PackedScene
	if packed == null:
		return ""
	var state := packed.get_state()
	if state == null:
		return ""
	for node_index in state.get_node_count():
		for prop_index in state.get_node_property_count(node_index):
			if state.get_node_property_name(node_index, prop_index) != "level_name":
				continue
			var value: Variant = state.get_node_property_value(node_index, prop_index)
			if value is String and not (value as String).is_empty():
				return value
	return ""


## 文件名兜底：level_02_镜子迷宫.tscn → "镜子迷宫"；level_03.tscn → "关卡 3"
func _title_from_file(path: String) -> String:
	var short := path.get_file().get_basename().trim_prefix(LEVEL_PREFIX)
	var parts := short.split("_", false)
	if parts.size() >= 2:
		return " · ".join(parts.slice(1))
	if parts.size() == 1:
		return "关卡 %s" % parts[0]
	return path.get_file()


func _on_level_pressed(index: int) -> void:
	get_tree().change_scene_to_file(_levels[index])


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_level_completed(level_name: String) -> void:
	_status_label.text = "最近完成：%s" % level_name
