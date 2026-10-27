class_name LevelResultView
extends CanvasLayer

signal next_requested(path: String)
signal retry_requested
signal return_requested

var screen: CenterContainer
var _title: Label
var _detail: Label
var _actions: VBoxContainer


func _ready() -> void:
	layer = 30
	hide()
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.68)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	screen = CenterContainer.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.hide()
	add_child(screen)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440.0, 250.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.12, 0.17)
	panel_style.border_color = Color(0.88, 0.70, 0.27)
	panel_style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", panel_style)
	screen.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	layout.add_child(_title)
	_detail = Label.new()
	_detail.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	layout.add_child(_detail)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	layout.add_child(_actions)


func show_result(
	title: String, detail: String, next_level: Dictionary,
	return_title: String, current_chapter: int,
) -> void:
	_title.text = title
	_detail.text = detail
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	if not next_level.is_empty():
		var next_title: String = "下一关"
		if int(next_level["chapter"]) != current_chapter:
			next_title = "进入第 %d 章" % int(next_level["chapter"])
		_actions.add_child(_make_result_button(next_title,
			func() -> void: next_requested.emit(str(next_level["path"]))))
	else:
		_actions.add_child(_make_result_button(return_title, func() -> void: return_requested.emit()))
	_actions.add_child(_make_result_button("重玩", func() -> void: retry_requested.emit()))
	if not next_level.is_empty():
		_actions.add_child(_make_result_button(return_title, func() -> void: return_requested.emit()))
	screen.show()
	show()


func _make_result_button(title: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(360.0, 42.0)
	button.pressed.connect(callback)
	return button
