@tool
class_name LevelSelectMap
extends Control

## 固定画布、章节与前八个入口均保存在场景中；脚本负责数据和交互。
const DESIGN_SIZE := Vector2(1672, 941)
const MARKER_SCENE := preload("res://scenes/LevelSelectPage/LevelMarker.tscn")
const MAIN_MENU_SCENE := "res://scenes/MainMenu/MainMenu.tscn"
const SLOT_CENTERS := [Vector2(244, 432), Vector2(424, 386), Vector2(590, 342), Vector2(759, 400), Vector2(930, 472), Vector2(1104, 526), Vector2(1289, 573), Vector2(1480, 604)]

static var remembered_chapter := 1
var active_chapter := 1
var _levels: Array[Dictionary] = []
var _transition: Tween
var _authored_positions: Dictionary = {}
var _editor_signature: Array = []

@onready var _design: Control = $Design
@onready var _map: Control = $Design/MapArea
@onready var _chapter_buttons: HBoxContainer = $Design/ChapterButtons
@onready var _chapter_hint: Label = $Design/ChapterHint


func _ready() -> void:
	resized.connect(_fit_design)
	_fit_design()
	if Engine.is_editor_hint():
		return
	for chapter in range(1, 4):
		for marker in get_chapter_markers(chapter):
			_authored_positions["%d/%s" % [chapter, marker.name]] = marker.position
	$Design/BackButton.pressed.connect(_go_home)
	for number in range(1, 4):
		var button := _chapter_buttons.get_node("Chapter%02dButton" % number) as Button
		button.pressed.connect(select_chapter.bind(number))
	active_chapter = remembered_chapter
	refresh_catalog()


func _fit_design() -> void:
	if not is_instance_valid(_design):
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_design.scale = Vector2.ONE * factor
	_design.position = (size - DESIGN_SIZE * factor) * 0.5


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_map):
		return
	var signature: Array = []
	for chapter in range(1, 4):
		for marker in get_chapter_markers(chapter):
			signature.append(marker.position)
			signature.append(marker.highlighted)
			signature.append(marker.locked)
			signature.append(marker.visible)
	if signature == _editor_signature:
		return
	_editor_signature = signature
	for chapter in range(1, 4):
		_update_connections(chapter)


func refresh_catalog() -> void:
	_levels = ChapterCatalog.get_official_levels()
	var completed_ids: Dictionary = {}
	for record in _levels:
		var id := str(record["level_id"])
		completed_ids[id] = ProgressStore.is_completed(id)
	var current_id := ""
	var unlocked_ids: Dictionary = {}
	for index in _levels.size():
		var id := str(_levels[index]["level_id"])
		var unlocked := index == 0 or bool(completed_ids[id])
		if index > 0:
			unlocked = unlocked or bool(completed_ids[str(_levels[index - 1]["level_id"])])
		unlocked_ids[id] = unlocked
		if current_id.is_empty() and unlocked and not bool(completed_ids[id]):
			current_id = id
	for chapter in range(1, 4):
		var records: Array[Dictionary] = []
		for record in _levels:
			if int(record["chapter"]) == chapter:
				records.append(record)
		var holder := _map.get_node("Chapter%02d/Markers" % chapter) as Control
		var needed := maxi(8, records.size())
		while holder.get_child_count() < needed:
			var extra := MARKER_SCENE.instantiate() as LevelMarker
			extra.name = "Marker%02d" % (holder.get_child_count() + 1)
			holder.add_child(extra)
		var markers := get_chapter_markers(chapter)
		for index in markers.size():
			var marker := markers[index] as LevelMarker
			marker.visible = index < needed
			if not marker.visible:
				continue
			if not marker.activated.is_connected(_on_marker_activated):
				marker.activated.connect(_on_marker_activated)
			marker.level_number = index + 1
			if needed > 8:
				var path_index := float(index) * 7.0 / float(needed - 1)
				var lower := mini(floori(path_index), 6)
				marker.position = SLOT_CENTERS[lower].lerp(SLOT_CENTERS[lower + 1], path_index - lower) - Vector2(48, 48)
			else:
				marker.position = _authored_positions.get("%d/%s" % [chapter, marker.name], marker.position)
			if index < records.size():
				var record := records[index]
				var id := str(record["level_id"])
				marker.configure(record, not bool(unlocked_ids[id]), bool(completed_ids[id]), id == current_id)
			else:
				marker.configure({}, true, false, false)
		_update_connections(chapter)
	select_chapter(active_chapter, false)


func get_chapter_markers(number: int) -> Array:
	var holder := _map.get_node_or_null("Chapter%02d/Markers" % number)
	return holder.get_children() if holder != null else []


func select_chapter(number: int, animate: bool = true) -> void:
	active_chapter = clampi(number, 1, 3)
	remembered_chapter = active_chapter
	if _transition != null and _transition.is_valid():
		_transition.kill()
	for chapter in range(1, 4):
		var page := _map.get_node("Chapter%02d" % chapter) as Control
		page.visible = chapter == active_chapter
		page.modulate.a = 1.0
		var button := _chapter_buttons.get_node("Chapter%02dButton" % chapter) as Button
		var color := Color("f7f4ed") if chapter == active_chapter else Color("929b99")
		button.add_theme_color_override("font_color", color)
		button.get_node("Underline").modulate = color
	if animate:
		var current := _map.get_node("Chapter%02d" % active_chapter) as Control
		current.modulate.a = 0.0
		_transition = create_tween()
		_transition.tween_property(current, "modulate:a", 1.0, 0.22)
	var count := 0
	for record in _levels:
		if int(record["chapter"]) == active_chapter:
			count += 1
	_chapter_hint.text = "第%s章正在制作，敬请期待" % ["一", "二", "三"][active_chapter - 1] if count == 0 else ""
	_chapter_hint.visible = count == 0


func _update_connections(number: int) -> void:
	var routes := _map.get_node("Chapter%02d/Connections" % number) as Line2D
	var markers := get_chapter_markers(number)
	for index in markers.size() - 1:
		var link_name := "Link%02d" % (index + 1)
		var line := routes.get_node_or_null(link_name) as Line2D
		if line == null:
			line = Line2D.new()
			line.name = link_name
			line.width = 1.3
			line.antialiased = true
			routes.add_child(line)
		var first := markers[index] as LevelMarker
		var second := markers[index + 1] as LevelMarker
		line.visible = first.visible and second.visible
		var a := first.position + Vector2(48, 48)
		var b := second.position + Vector2(48, 48)
		var direction := a.direction_to(b)
		line.points = PackedVector2Array([a + direction * (45.0 if first.highlighted else 33.0), b - direction * (45.0 if second.highlighted else 33.0)])
		line.default_color = Color(0.19, 0.21, 0.22, 0.68 if not second.locked else 0.26)


func _on_marker_activated(path: String) -> void:
	if SceneTransition.is_transitioning():
		return
	for record in _levels:
		if record["path"] == path and ChapterCatalog.is_unlocked(record["level_id"]):
			SceneTransition.change_to_file(path)
			return


func _unhandled_input(event: InputEvent) -> void:
	if not Engine.is_editor_hint() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_home()


func _go_home() -> void:
	SceneTransition.change_to_file(MAIN_MENU_SCENE)
