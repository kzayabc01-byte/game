class_name LevelManager
extends Node

## 关卡管理器：连接蚕茧、处理胜利与重置、显示界面提示。
## 用法：每个关卡场景放一个本节点（level_base 已放好），
## 正式关卡顺序由章节目录决定；旧 next_level_scene 仅保留文件兼容。

enum PublicationState { DRAFT, PUBLISHED }
enum LevelKind { FIXED, BUILD }

@export var level_name: String = "关卡 1"
@export var level_id: String = ""
@export var schema_version: int = 1
@export var publication_state: PublicationState = PublicationState.DRAFT
@export_range(1, 99, 1) var chapter: int = 1
@export_range(1, 99, 1) var order_in_chapter: int = 1
@export_range(1, 5, 1) var difficulty: int = 1
@export var mechanic_tags: PackedStringArray = []
@export var level_kind: LevelKind = LevelKind.FIXED
@export var build_item_keys: PackedStringArray = []
@export var build_item_counts: PackedInt32Array = []
@export var build_bounds: Rect2 = Rect2(48.0, 96.0, 1056.0, 500.0)
@export_range(0, 20, 1) var build_wire_limit: int = 0
@export var build_wire_targets: PackedStringArray = []
@export var build_wire_sources: PackedStringArray = []
@export var build_aimable_sources: PackedStringArray = []
@export var next_level_scene: PackedScene
@export var main_menu_scene: PackedScene = preload("res://scenes/MainMenu/MainMenu.tscn")

const LEVEL_SELECT_SCENE := "res://scenes/LevelSelectPage/LevelSelectMap.tscn"

@onready var _win_label: Label = $LevelHUD/WinLabel
@onready var _hint_label: Label = $LevelHUD/HintLabel
@onready var _coins_label: Label = $LevelHUD/CoinsLabel
@onready var _upgrade_button: Button = $LevelHUD/UpgradeButton
@onready var _light_system: LightSystem = $"../LightSystem"
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _resume_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/ResumeButton
@onready var _restart_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/RestartButton
@onready var _select_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/SelectButton
@onready var _home_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/HomeButton
var _won: bool = false
var _player_builder: PlayerBuilder = null
var _result_layer: CanvasLayer = null
var _result_screen: CenterContainer = null
var _result_title: Label = null
var _result_detail: Label = null
var _result_actions: VBoxContainer = null


func _ready() -> void:
	_win_label.hide()
	_pause_menu.hide()
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_resume_button.pressed.connect(_on_resume_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_select_button.pressed.connect(_on_select_pressed)
	_home_button.pressed.connect(_on_home_pressed)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_coins_label.visible = publication_state == PublicationState.PUBLISHED
	_upgrade_button.visible = publication_state == PublicationState.PUBLISHED
	_build_result_screen()
	_refresh_progress_ui()
	if level_kind == LevelKind.BUILD:
		_player_builder = PlayerBuilder.new()
		_player_builder.name = "PlayerBuilder"
		add_child(_player_builder)
		_player_builder.configure(self)
	# 延后到所有节点 ready 之后再连接蚕茧，避免错过任何蚕茧
	call_deferred("_connect_cocoons")


func _connect_cocoons() -> void:
	for node in get_tree().get_nodes_in_group(Cocoon.COCOON_GROUP):
		var cocoon := node as Cocoon
		if cocoon != null:
			cocoon.activated.connect(_on_cocoon_activated)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_pause_menu):
		return
	if SceneTransition.is_transitioning():
		return
	if _light_system.is_pulse_active():
		return
	if event.is_action_pressed("ui_cancel"):
		if _won:
			_on_select_pressed()
			get_viewport().set_input_as_handled()
			return
		if _player_builder != null and not _player_builder.is_testing() and not _pause_menu.visible:
			if _player_builder.cancel_active_tool():
				get_viewport().set_input_as_handled()
				return
		_set_paused(not _pause_menu.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_level") and not _pause_menu.visible:
		reset_level()


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(_pause_menu):
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_SPACE:
		return
	var can_fire := _player_builder == null or _player_builder.is_testing()
	if can_fire and not _pause_menu.visible and not _won and _light_system.request_fire():
		get_viewport().set_input_as_handled()


func _set_paused(should_pause: bool) -> void:
	if not is_instance_valid(_pause_menu):
		return
	_pause_menu.visible = should_pause
	get_tree().paused = should_pause
	if should_pause:
		_resume_button.grab_focus()


func _on_resume_pressed() -> void:
	_set_paused(false)


func _on_restart_pressed() -> void:
	SceneTransition.restart_current_scene()


func _on_select_pressed() -> void:
	SceneTransition.change_to_file(LEVEL_SELECT_SCENE)


func _on_home_pressed() -> void:
	SceneTransition.change_to_packed(main_menu_scene)


## 重置整个关卡：光源回到初始角度，机关回到初始状态
func reset_level() -> void:
	_won = false
	_win_label.hide()
	if _result_screen != null:
		_result_screen.hide()
		_result_layer.hide()
	_light_system.reset_state()
	get_tree().call_group("resettables", "reset_state")
	GameEvents.game_reset.emit()


func _on_cocoon_activated() -> void:
	if _won:
		return
	_won = true
	var scene := get_tree().current_scene
	var current_path := scene.scene_file_path if scene != null else ""
	var official := ChapterCatalog.is_official_path(level_id, current_path)
	var next_level := ChapterCatalog.next_official(level_id) if official else {}
	var newly_unlocked_chapter := false
	if not next_level.is_empty() and next_level["chapter"] != chapter:
		newly_unlocked_chapter = not ChapterCatalog.is_unlocked(next_level["level_id"])
	var saved := true
	if official:
		saved = ProgressStore.record_official_clear(level_id)
		_refresh_progress_ui()
	GameEvents.level_completed.emit(level_name)
	_result_title.text = "%s 完成！" % level_name
	_result_detail.text = "获得 50 金币" if official and saved else "关卡完成"
	if official and not saved:
		_result_detail.text = "存档失败：进度和金币未保存"
	elif newly_unlocked_chapter and saved:
		_result_detail.text += " · 已解锁第 %d 章" % next_level["chapter"]
	for child in _result_actions.get_children():
		child.queue_free()
	if official and not next_level.is_empty() and saved:
		var next_title := "下一关"
		if next_level["chapter"] != chapter:
			next_title = "进入第 %d 章" % next_level["chapter"]
		_result_actions.add_child(_make_result_button(
				next_title, _on_result_next.bind(next_level["path"])))
	else:
		_result_actions.add_child(_make_result_button(
				"返回章节" if official else "返回关卡目录", _on_select_pressed))
	_result_actions.add_child(_make_result_button("重玩", _on_restart_pressed))
	if official and not next_level.is_empty() and saved:
		_result_actions.add_child(_make_result_button(
				"返回章节", _on_select_pressed))
	_result_screen.show()
	_result_layer.show()


func _build_result_screen() -> void:
	_result_layer = CanvasLayer.new()
	_result_layer.layer = 30
	_result_layer.hide()
	add_child(_result_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.68)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_layer.add_child(dim)
	_result_screen = CenterContainer.new()
	_result_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_screen.hide()
	_result_layer.add_child(_result_screen)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440.0, 250.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.12, 0.17)
	panel_style.border_color = Color(0.88, 0.70, 0.27)
	panel_style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", panel_style)
	_result_screen.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	_result_title = Label.new()
	_result_title.add_theme_font_size_override("font_size", 28)
	_result_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	layout.add_child(_result_title)
	_result_detail = Label.new()
	_result_detail.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	layout.add_child(_result_detail)
	_result_actions = VBoxContainer.new()
	_result_actions.add_theme_constant_override("separation", 8)
	layout.add_child(_result_actions)


func _make_result_button(title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(360.0, 42.0)
	button.pressed.connect(callback)
	return button


func _on_result_next(path: String) -> void:
	SceneTransition.change_to_file(path)


func _on_upgrade_pressed() -> void:
	if publication_state != PublicationState.PUBLISHED:
		return
	if ProgressStore.buy_hint_upgrade():
		_light_system.refresh_hint_length()
	_refresh_progress_ui()


func _refresh_progress_ui() -> void:
	if _coins_label == null or _upgrade_button == null:
		return
	_coins_label.text = "金币 %d  ·  虚线 %d" % [
		ProgressStore.get_coins(), roundi(ProgressStore.get_hint_length())
	]
	var full := ProgressStore.get_hint_level() >= ProgressStore.MAX_HINT_LEVEL
	_upgrade_button.disabled = full or ProgressStore.get_coins() < ProgressStore.UPGRADE_COST
	_upgrade_button.text = "瞄准提示已满级" if full else "升级虚线 +120  ·  100 金币"
