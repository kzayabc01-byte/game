class_name MainMenu
extends Control

## 主菜单：自动扫描 scenes/levels/ 下的关卡场景生成按钮。
##
## 加新关卡 = 把文件放进 scenes/levels/，再在编辑器里填好 LevelManager 的 level_name，
## 不用改本文件。
##   * 顺序：按文件名排序，约定 level_NN_说明.tscn（NN 两位数）
##   * 显示名：优先读关卡里 LevelManager.level_name；没填就按文件名兜底
##   * level_base.tscn 这类模板不会被当成关卡（前缀后必须是数字）
##   * debug 构建每个关卡旁有「编辑」和「×」：可修改或删除已有文件（正式导出不显示）

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

	# debug 构建给每个关卡配编辑 / 删除按钮；正式导出看不到
	var show_developer_tools := OS.is_debug_build()
	for index in _levels.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var button := Button.new()
		button.text = "%d · %s" % [index + 1, _level_title(_levels[index])]
		button.custom_minimum_size = Vector2(200.0 if show_developer_tools else 320.0, 48.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_level_pressed.bind(index))
		row.add_child(button)
		if show_developer_tools:
			var edit_button := Button.new()
			edit_button.text = "编辑"
			edit_button.custom_minimum_size = Vector2(56.0, 48.0)
			edit_button.tooltip_text = "在关卡编辑器中修改这个关卡"
			edit_button.pressed.connect(_on_edit_level_pressed.bind(index))
			row.add_child(edit_button)
			var delete_button := Button.new()
			delete_button.text = "×"
			delete_button.custom_minimum_size = Vector2(48.0, 48.0)
			delete_button.tooltip_text = "删除这个关卡（关卡文件一并删除）"
			delete_button.pressed.connect(_confirm_delete_level.bind(index))
			row.add_child(delete_button)
		_level_list.add_child(row)

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


func _on_edit_level_pressed(index: int) -> void:
	if index < 0 or index >= _levels.size():
		return
	if not LevelFileIO.queue_level_for_edit(_levels[index]):
		_status_label.text = "无法编辑：关卡文件不存在"
		return
	get_tree().change_scene_to_file("res://scenes/editor/level_editor.tscn")


## 弹确认框：删除会连 scenes/levels/ 里的关卡文件一起删掉
func _confirm_delete_level(index: int) -> void:
	var path := _levels[index]
	var dialog := ConfirmationDialog.new()
	dialog.title = "删除关卡"
	dialog.dialog_text = "确定删除「%s」？\n文件 %s 会从 scenes/levels/ 永久删除，无法撤销。" % [
			_level_title(path), path.get_file()]
	dialog.ok_button_text = "删除"
	dialog.get_ok_button().add_theme_color_override("font_color", Color(0.92, 0.35, 0.3))
	dialog.confirmed.connect(_delete_level.bind(index, dialog))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


## 确认后真正删文件并刷新列表
func _delete_level(index: int, dialog: ConfirmationDialog) -> void:
	var path := _levels[index]
	if _delete_level_file(path):
		_status_label.text = "已删除关卡：%s" % path.get_file()
	else:
		_status_label.text = "删除失败：%s" % path.get_file()
	dialog.queue_free()
	_refresh_level_list()


## 删除关卡文件本身（返回是否成功）；测试也直接调这个
func _delete_level_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func _refresh_level_list() -> void:
	for child in _level_list.get_children():
		child.free()
	_levels = _discover_levels()
	_create_level_buttons()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_level_completed(level_name: String) -> void:
	_status_label.text = "最近完成：%s" % level_name
