class_name LevelSelectPage
extends Control

## 关卡选择与关卡工坊共用的目录界面。
## 正式关卡只出现在关卡选择；全部草稿与正式关卡都由 debug 工坊统一维护。

const LEVEL_DIR := "res://scenes/levels"
const LEVEL_PREFIX := "level_"
const EDITOR_SCENE := "res://scenes/editor/level_editor.tscn"
const MAIN_MENU_SCENE := "res://scenes/MainMenu/MainMenu.tscn"

static var open_workshop_on_entry := false

@onready var _title_label: Label = $Title
@onready var _subtitle_label: Label = $Subtitle
@onready var _level_list: VBoxContainer = %LevelList
@onready var _status_label: Label = %StatusLabel
@onready var _quit_button: Button = %QuitButton

var _levels: Array[String] = []
var _level_records: Array[Dictionary] = []
var _publish_path := ""
var _publish_dialog: ConfirmationDialog = null
var _publish_name: LineEdit = null
var _publish_chapter: SpinBox = null
var _publish_order: SpinBox = null
var _publish_difficulty: SpinBox = null
var _publish_tags: LineEdit = null


func _ready() -> void:
	GameEvents.level_completed.connect(_on_level_completed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_build_publish_dialog()
	_reload_records()
	if open_workshop_on_entry:
		open_workshop_on_entry = false
		_show_workshop()
	else:
		_show_start_game()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	_go_to_main_menu()


func show_start_game() -> void:
	_show_start_game()


func show_workshop() -> void:
	_show_workshop()


func get_level_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in _level_records:
		result.append(record.duplicate(true))
	return result


## 返回发布阻断项；成功发布时返回空数组。
func publish_level(path: String, metadata: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var title := str(metadata.get(&"level_name", "")).strip_edges()
	var chapter := maxi(int(metadata.get(&"chapter", 1)), 1)
	var order := maxi(int(metadata.get(&"order_in_chapter", 1)), 1)
	if title.is_empty():
		errors.append("关卡名称不能为空")
	for record in _level_records:
		if record[&"path"] == path or not record[&"published"]:
			continue
		if record[&"chapter"] == chapter and record[&"order_in_chapter"] == order:
			errors.append("发布顺序与「%s」重复" % record[&"title"])
	if not errors.is_empty():
		return errors

	var draft_metadata := metadata.duplicate(true)
	draft_metadata[&"level_name"] = title
	draft_metadata[&"chapter"] = chapter
	draft_metadata[&"order_in_chapter"] = order
	draft_metadata[&"difficulty"] = clampi(int(metadata.get(&"difficulty", 1)), 1, 5)
	draft_metadata[&"publication_state"] = LevelManager.PublicationState.DRAFT
	var update_error := LevelFileIO.update_level_metadata(path, draft_metadata)
	if update_error != OK:
		errors.append("保存关卡发布信息失败（错误 %d）" % update_error)
		return errors

	errors = LevelFileIO.validate_level_for_publication(path)
	if not errors.is_empty():
		_reload_records()
		return errors
	update_error = LevelFileIO.update_level_metadata(path, {
		&"publication_state": LevelManager.PublicationState.PUBLISHED,
	})
	if update_error != OK:
		errors.append("发布失败（错误 %d）" % update_error)
	_reload_records()
	return errors


func unpublish_level(path: String) -> bool:
	var error := LevelFileIO.update_level_metadata(path, {
		&"publication_state": LevelManager.PublicationState.DRAFT,
	})
	_reload_records()
	return error == OK


## 复制产生新的草稿关卡，正式关卡和副本不会共享文件。
func duplicate_level_as_draft(path: String) -> String:
	var packed := ResourceLoader.load(
			path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return ""
	var level_root := packed.instantiate()
	var manager := level_root.get_node_or_null("LevelManager") as LevelManager
	if manager == null:
		level_root.free()
		return ""
	var file_name := LevelFileIO.suggest_file_name()
	var target_path := LEVEL_DIR + "/" + file_name
	level_root.name = _root_name_for_file(file_name)
	manager.level_name = "%s 副本" % _level_title(path)
	manager.publication_state = LevelManager.PublicationState.DRAFT
	manager.next_level_scene = null
	var base_path := LevelFileIO.get_base_scene_path_from_file(path)
	var text := LevelFileIO.serialize_level(level_root, base_path)
	level_root.free()
	if LevelFileIO.write_text(target_path, text) != OK:
		return ""
	ResourceLoader.load(target_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	_reload_records()
	return target_path


func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _show_start_game() -> void:
	_title_label.text = "选择关卡"
	_subtitle_label.text = "选择一个正式关卡"
	_clear_level_list()
	var published: Array[Dictionary] = []
	for record in _level_records:
		if record[&"published"]:
			published.append(record)
	published.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a[&"chapter"] != b[&"chapter"]:
			return a[&"chapter"] < b[&"chapter"]
		if a[&"order_in_chapter"] != b[&"order_in_chapter"]:
			return a[&"order_in_chapter"] < b[&"order_in_chapter"]
		return a[&"path"] < b[&"path"])
	if published.is_empty():
		_add_empty_hint("还没有正式关卡。请先在关卡工坊中发布。")
	else:
		var current_chapter := -1
		for record in published:
			if record[&"chapter"] != current_chapter:
				current_chapter = record[&"chapter"]
				_level_list.add_child(_make_section_label("第 %d 章" % current_chapter))
			_level_list.add_child(_make_play_button(record))
	_level_list.add_child(_make_button("← 返回主菜单", _go_to_main_menu, Vector2(320.0, 42.0)))
	_status_label.text = "共 %d 个正式关卡" % published.size()


func _show_workshop() -> void:
	_title_label.text = "关卡工坊"
	_subtitle_label.text = "草稿可以测试，发布后才会进入“开始游戏”"
	_clear_level_list()
	var new_button := _make_button("＋ 新建草稿关卡", _on_new_level_pressed)
	new_button.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	_level_list.add_child(new_button)
	if _level_records.is_empty():
		_add_empty_hint("还没有工坊关卡。")
	else:
		for record in _level_records:
			_level_list.add_child(_make_workshop_card(record))
	_level_list.add_child(_make_button("← 返回主菜单", _go_to_main_menu, Vector2(320.0, 42.0)))
	_status_label.text = "共 %d 个工坊关卡" % _level_records.size()


func _make_play_button(record: Dictionary) -> Button:
	var tags: PackedStringArray = record[&"mechanic_tags"]
	var tag_text := " · ".join(tags)
	var detail := "难度 %d" % record[&"difficulty"]
	if not tag_text.is_empty():
		detail += " · " + tag_text
	var text := "%02d  %s\n%s" % [
		record[&"order_in_chapter"], record[&"title"], detail,
	]
	var button := _make_button(
			text, _on_play_path.bind(record[&"path"]), Vector2(620.0, 64.0))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return button


func _make_workshop_card(record: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760.0, 104.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)
	var badge := Label.new()
	badge.text = "已发布" if record[&"published"] else "草稿"
	badge.add_theme_color_override(
			"font_color", Color(0.45, 0.95, 0.6) if record[&"published"]
			else Color(1.0, 0.75, 0.35))
	header.add_child(badge)
	var name_label := Label.new()
	name_label.text = str(record[&"title"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 18)
	header.add_child(name_label)
	var location := Label.new()
	location.text = "%s · 第%d章 · 顺序%d · 难度%d" % [
		str(record[&"path"]).get_file(), record[&"chapter"],
		record[&"order_in_chapter"], record[&"difficulty"],
	]
	location.add_theme_color_override("font_color", Color(0.62, 0.68, 0.76))
	header.add_child(location)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	actions.add_child(_make_small_button("编辑", _on_edit_path.bind(record[&"path"])))
	actions.add_child(_make_small_button("测试", _on_play_path.bind(record[&"path"])))
	actions.add_child(_make_small_button("复制", _on_duplicate_path.bind(record[&"path"])))
	if record[&"published"]:
		actions.add_child(_make_small_button(
				"撤回发布", _confirm_unpublish.bind(record[&"path"])))
	else:
		var publish_button := _make_small_button(
				"发布为正式关卡", _show_publish_dialog.bind(record[&"path"]))
		publish_button.add_theme_color_override("font_color", Color(0.45, 0.95, 0.6))
		actions.add_child(publish_button)
		var delete_button := _make_small_button(
				"删除", _confirm_delete_level.bind(record[&"path"]))
		delete_button.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
		actions.add_child(delete_button)
	return panel


func _make_button(
	text: String, callback: Callable, minimum_size := Vector2(520.0, 52.0)
) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum_size
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button


func _make_small_button(text: String, callback: Callable) -> Button:
	return _make_button(text, callback, Vector2(104.0, 34.0))


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	return label


func _add_empty_hint(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	_level_list.add_child(label)


func _build_publish_dialog() -> void:
	_publish_dialog = ConfirmationDialog.new()
	_publish_dialog.title = "发布为正式关卡"
	_publish_dialog.ok_button_text = "发布"
	_publish_dialog.confirmed.connect(_on_publish_confirmed)
	add_child(_publish_dialog)
	var form := VBoxContainer.new()
	form.custom_minimum_size = Vector2(460.0, 330.0)
	form.add_theme_constant_override("separation", 8)
	_publish_dialog.add_child(form)

	_publish_name = LineEdit.new()
	_add_labeled_control(form, "正式名称", _publish_name)
	_publish_chapter = _make_metadata_spin(1, 99)
	_add_labeled_control(form, "所属章节", _publish_chapter)
	_publish_order = _make_metadata_spin(1, 99)
	_add_labeled_control(form, "章节内顺序", _publish_order)
	_publish_difficulty = _make_metadata_spin(1, 5)
	_add_labeled_control(form, "难度（1—5）", _publish_difficulty)
	_publish_tags = LineEdit.new()
	_publish_tags.placeholder_text = "镜面, 折射, 电线"
	_add_labeled_control(form, "玩法标签（逗号分隔）", _publish_tags)
	var hint := Label.new()
	hint.text = "发布前会检查光源、通关目标、电线目标和章节顺序。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.66, 0.72, 0.8))
	form.add_child(hint)


func _add_labeled_control(parent: VBoxContainer, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	parent.add_child(control)


func _make_metadata_spin(minimum: float, maximum: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1.0
	spin.update_on_text_changed = true
	return spin


func _show_publish_dialog(path: String) -> void:
	var record := _record_for_path(path)
	if record.is_empty():
		return
	_publish_path = path
	_publish_name.text = record[&"title"]
	_publish_chapter.value = record[&"chapter"]
	_publish_order.value = record[&"order_in_chapter"]
	_publish_difficulty.value = record[&"difficulty"]
	var tags: PackedStringArray = record[&"mechanic_tags"]
	_publish_tags.text = ", ".join(tags)
	_publish_dialog.popup_centered(Vector2i(520, 470))


func _on_publish_confirmed() -> void:
	var errors := publish_level(_publish_path, {
		&"level_name": _publish_name.text,
		&"chapter": int(_publish_chapter.value),
		&"order_in_chapter": int(_publish_order.value),
		&"difficulty": int(_publish_difficulty.value),
		&"mechanic_tags": _parse_tags(_publish_tags.text),
	})
	_show_workshop()
	if errors.is_empty():
		_status_label.text = "已发布正式关卡：%s" % _publish_name.text.strip_edges()
	else:
		_show_message("无法发布", "\n".join(errors))


func _parse_tags(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	var normalized := text.replace("，", ",")
	for part in normalized.split(",", false):
		var tag := part.strip_edges()
		if not tag.is_empty() and not result.has(tag):
			result.append(tag)
	return result


func _confirm_unpublish(path: String) -> void:
	var record := _record_for_path(path)
	var dialog := ConfirmationDialog.new()
	dialog.title = "撤回发布"
	dialog.dialog_text = "撤回「%s」？\n它将从“开始游戏”消失，但仍保留在工坊。" % record.get(&"title", "关卡")
	dialog.ok_button_text = "撤回"
	dialog.confirmed.connect(_unpublish_and_refresh.bind(path, dialog))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _unpublish_and_refresh(path: String, dialog: ConfirmationDialog) -> void:
	var success := unpublish_level(path)
	dialog.queue_free()
	_show_workshop()
	if success:
		_status_label.text = "已撤回发布：%s" % _level_title(path)
	else:
		_status_label.text = "撤回失败：%s" % path.get_file()


func _confirm_delete_level(path: String) -> void:
	var record := _record_for_path(path)
	if record.get(&"published", false):
		_show_message("不能删除", "请先撤回发布，再删除这个关卡。")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "删除草稿关卡"
	dialog.dialog_text = "确定删除「%s」？\n文件 %s 将永久删除，无法撤销。" % [
		record.get(&"title", _level_title(path)), path.get_file(),
	]
	dialog.ok_button_text = "删除"
	dialog.get_ok_button().add_theme_color_override("font_color", Color(0.92, 0.35, 0.3))
	dialog.confirmed.connect(_delete_level.bind(path, dialog))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _delete_level(path: String, dialog: ConfirmationDialog) -> void:
	var success := _delete_level_file(path)
	dialog.queue_free()
	_reload_records()
	_show_workshop()
	if success:
		_status_label.text = "已删除草稿：%s" % path.get_file()
	else:
		_status_label.text = "删除失败：%s" % path.get_file()


func _delete_level_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func _show_message(title: String, message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(480, 260))


func _on_new_level_pressed() -> void:
	LevelFileIO.take_level_to_edit()
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _on_edit_path(path: String) -> void:
	if not LevelFileIO.queue_level_for_edit(path):
		_status_label.text = "无法编辑：关卡文件不存在"
		return
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _on_play_path(path: String) -> void:
	get_tree().change_scene_to_file(path)


func _on_duplicate_path(path: String) -> void:
	var target_path := duplicate_level_as_draft(path)
	_show_workshop()
	if target_path.is_empty():
		_status_label.text = "复制失败：%s" % path.get_file()
	else:
		_status_label.text = "已复制为草稿：%s" % target_path.get_file()


func _reload_records() -> void:
	_levels = _discover_levels()
	_level_records.clear()
	for path in _levels:
		var metadata := LevelFileIO.read_level_metadata(path)
		var tags := PackedStringArray()
		if metadata.has(&"mechanic_tags"):
			tags = metadata[&"mechanic_tags"]
		var publication_state := int(metadata.get(
				&"publication_state", LevelManager.PublicationState.DRAFT))
		_level_records.append({
			&"path": path,
			&"title": _level_title(path),
			&"published": publication_state == LevelManager.PublicationState.PUBLISHED,
			&"chapter": maxi(int(metadata.get(&"chapter", 1)), 1),
			&"order_in_chapter": maxi(int(metadata.get(&"order_in_chapter", 1)), 1),
			&"difficulty": clampi(int(metadata.get(&"difficulty", 1)), 1, 5),
			&"mechanic_tags": tags,
		})


func _discover_levels() -> Array[String]:
	var result: Array[String] = []
	for file_name in LevelFileIO.scan_levels():
		result.append(LEVEL_DIR + "/" + file_name)
	return result


func _record_for_path(path: String) -> Dictionary:
	for record in _level_records:
		if record[&"path"] == path:
			return record
	return {}


func _clear_level_list() -> void:
	for child in _level_list.get_children():
		# pressed 信号回调中，触发按钮本身处于锁定状态，不能立即 free。
		# 先移出容器避免旧、新页面重叠，再在安全时机释放。
		_level_list.remove_child(child)
		child.queue_free()


func _level_title(path: String) -> String:
	var from_scene := _title_from_scene(path)
	if not from_scene.is_empty():
		return from_scene
	return _title_from_file(path)


func _title_from_scene(path: String) -> String:
	var packed := ResourceLoader.load(
			path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
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


func _title_from_file(path: String) -> String:
	var short := path.get_file().get_basename().trim_prefix(LEVEL_PREFIX)
	var parts := short.split("_", false)
	if parts.size() >= 2:
		return " · ".join(parts.slice(1))
	if parts.size() == 1:
		return "关卡 %s" % parts[0]
	return path.get_file()


func _root_name_for_file(file_name: String) -> String:
	var short := file_name.trim_prefix(LEVEL_PREFIX)
	var number_text := short.split("_", false)[0]
	return "Level%02d" % number_text.to_int()


func _on_quit_pressed() -> void:
	_go_to_main_menu()


func _on_level_completed(level_name: String) -> void:
	_status_label.text = "最近完成：%s" % level_name
