class_name LevelManager
extends Node

## 关卡会话协调器：入口权限、阶段、胜利、重置。结算展示由 LevelResultView 负责。
## 用法：每个关卡场景放一个本节点（level_base 已放好），
## 正式关卡顺序由章节目录决定；旧 next_level_scene 仅保留文件兼容。

signal completed(completed_level_name: String)

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
const WORKSHOP_SCENE := "res://scenes/LevelSelectPage/LevelSelectPage.tscn"

var _hud: LevelHudView
var _light_system: LightSystem
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _resume_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/ResumeButton
@onready var _restart_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/RestartButton
@onready var _select_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/SelectButton
@onready var _home_button: Button = $PauseMenu/Center/PanelContainer/Padding/Buttons/HomeButton
var _won: bool = false
var _player_builder: PlayerBuilder = null
var run_mode: LevelRunContext.Mode = LevelRunContext.Mode.PREVIEW
var _level_root: Node
var _result_view: LevelResultView


func _ready() -> void:
	_level_root = owner
	_light_system = _level_root.get_node("LightSystem") as LightSystem
	if run_mode == LevelRunContext.Mode.AUTHORING:
		for child in get_children():
			if child is CanvasLayer:
				(child as CanvasLayer).hide()
		set_process_input(false)
		set_process_unhandled_input(false)
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	run_mode = LevelRunContext.take(_level_root.scene_file_path)
	_hud = LevelHudView.new()
	_hud.configure(get_node("LevelHUD") as CanvasLayer, _can_record_progress())
	_hud.upgrade_requested.connect(_on_upgrade_pressed)
	_pause_menu.hide()
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_resume_button.pressed.connect(_on_resume_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_select_button.pressed.connect(_on_select_pressed)
	_home_button.pressed.connect(_on_home_pressed)
	_result_view = LevelResultView.new()
	_result_view.name = "LevelResult"
	add_child(_result_view)
	_result_view.next_requested.connect(_on_result_next)
	_result_view.retry_requested.connect(_on_restart_pressed)
	_result_view.return_requested.connect(_on_select_pressed)
	if run_mode == LevelRunContext.Mode.PREVIEW:
		_select_button.text = "返回工坊"
	_refresh_progress_ui()
	if level_kind == LevelKind.BUILD:
		_player_builder = PlayerBuilder.new()
		_player_builder.name = "PlayerBuilder"
		add_child(_player_builder)
		_player_builder.configure(self, _level_root as Node2D)
	# 延后到所有节点 ready 之后再连接蚕茧，避免错过任何蚕茧
	call_deferred("_connect_cocoons")


func _connect_cocoons() -> void:
	if run_mode == LevelRunContext.Mode.AUTHORING:
		return
	for node in _level_root.find_children("*", "", true, false):
		var cocoon := node as Cocoon
		if cocoon != null and not cocoon.activated.is_connected(_on_cocoon_activated):
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
	if SceneTransition.is_transitioning():
		return
	LevelRunContext.prepare(_level_root.scene_file_path, run_mode)
	SceneTransition.restart_current_scene()


func _on_select_pressed() -> void:
	if SceneTransition.is_transitioning():
		return
	LevelRunContext.clear()
	SceneTransition.change_to_file(
		WORKSHOP_SCENE if run_mode == LevelRunContext.Mode.PREVIEW else LEVEL_SELECT_SCENE)


func _on_home_pressed() -> void:
	LevelRunContext.clear()
	SceneTransition.change_to_packed(main_menu_scene)


## 重置整个关卡：光源回到初始角度，机关回到初始状态
func reset_level() -> void:
	_won = false
	if _hud != null:
		_hud.reset()
	if is_instance_valid(_result_view):
		_result_view.hide()
	_light_system.reset_state()
	for node in _level_root.find_children("*", "", true, false):
		if node.is_in_group("resettables") and node.has_method("reset_state"):
			node.call("reset_state")
	GameEvents.game_reset.emit()


func _on_cocoon_activated() -> void:
	if _won or run_mode == LevelRunContext.Mode.AUTHORING:
		return
	_won = true
	var official: bool = _can_record_progress()
	var next_level := ChapterCatalog.next_official(level_id) if official else {}
	var newly_unlocked_chapter := false
	if not next_level.is_empty() and next_level["chapter"] != chapter:
		newly_unlocked_chapter = not ChapterCatalog.is_unlocked(next_level["level_id"])
	var saved := true
	if official:
		saved = ProgressStore.record_official_clear(level_id)
		_refresh_progress_ui()
	if official:
		GameEvents.level_completed.emit(level_name)
	completed.emit(level_name)
	var detail: String = "获得 50 金币" if official and saved else "预览完成 · 不记录正式进度和金币"
	if official and not saved:
		detail = "存档失败：进度和金币未保存"
	elif newly_unlocked_chapter and saved:
		detail += " · 已解锁第 %d 章" % next_level["chapter"]
	if not saved or (not next_level.is_empty() and not ChapterCatalog.is_unlocked(next_level["level_id"])):
		next_level = {}
	_result_view.show_result("%s 完成！" % level_name, detail, next_level,
		"返回章节" if official else "返回工坊", chapter)


func _can_record_progress() -> bool:
	return (
		is_instance_valid(_level_root)
		and LevelRunContext.can_record(run_mode, level_id, _level_root.scene_file_path)
	)


func _on_result_next(path: String) -> void:
	if SceneTransition.is_transitioning() or not FileAccess.file_exists(path):
		return
	LevelRunContext.prepare(path, LevelRunContext.Mode.OFFICIAL)
	SceneTransition.change_to_file(path)


func _on_upgrade_pressed() -> void:
	if not _can_record_progress():
		return
	if ProgressStore.buy_hint_upgrade():
		_light_system.refresh_hint_length()
	_refresh_progress_ui()


func _refresh_progress_ui() -> void:
	if _hud == null:
		return
	_hud.show_progress(ProgressStore.get_coins(), ProgressStore.get_hint_length(),
		ProgressStore.get_hint_level() >= ProgressStore.MAX_HINT_LEVEL,
		ProgressStore.UPGRADE_COST, ProgressStore.HINT_LENGTH_STEP)
