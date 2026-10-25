class_name LevelManager
extends Node

## 关卡管理器：连接蚕茧、处理胜利与重置、显示界面提示。
## 用法：每个关卡场景放一个本节点（level_base 已放好），
## 在检查器里设置 level_name 和 next_level_scene。

enum PublicationState { DRAFT, PUBLISHED }
enum LevelKind { FIXED, BUILD }

@export var level_name: String = "关卡 1"
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

const LEVEL_SELECT_SCENE := "res://scenes/LevelSelectPage/LevelSelectPage.tscn"

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
	if SceneTransition.is_transitioning():
		return
	if _light_system.is_pulse_active():
		return
	if event.is_action_pressed("ui_cancel"):
		if _player_builder != null and not _player_builder.is_testing() and not _pause_menu.visible:
			if _player_builder.cancel_active_tool():
				get_viewport().set_input_as_handled()
				return
		_set_paused(not _pause_menu.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_level") and not _pause_menu.visible:
		reset_level()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_SPACE:
		return
	var can_fire := _player_builder == null or _player_builder.is_testing()
	if can_fire and not _pause_menu.visible and not _won and _light_system.request_fire():
		get_viewport().set_input_as_handled()


func _set_paused(should_pause: bool) -> void:
	_pause_menu.visible = should_pause
	get_tree().paused = should_pause
	if should_pause:
		_resume_button.grab_focus()


func _on_resume_pressed() -> void:
	_set_paused(false)


func _on_restart_pressed() -> void:
	SceneTransition.restart_current_scene()


func _on_select_pressed() -> void:
	LevelSelectPage.open_workshop_on_entry = false
	SceneTransition.change_to_file(LEVEL_SELECT_SCENE)


func _on_home_pressed() -> void:
	SceneTransition.change_to_packed(main_menu_scene)


## 重置整个关卡：光源回到初始角度，机关回到初始状态
func reset_level() -> void:
	_won = false
	_win_label.hide()
	_light_system.reset_state()
	get_tree().call_group("resettables", "reset_state")
	GameEvents.game_reset.emit()


func _on_cocoon_activated() -> void:
	if _won:
		return
	_won = true
	if publication_state == PublicationState.PUBLISHED:
		ProgressStore.award_clear()
		_refresh_progress_ui()
	GameEvents.level_completed.emit(level_name)
	_win_label.text = "%s 完成！获得 50 金币" % level_name if publication_state == PublicationState.PUBLISHED else "%s 完成！" % level_name
	_win_label.show()
	if next_level_scene != null:
		await get_tree().create_timer(1.5, false).timeout
		if _won and is_inside_tree():
			get_tree().change_scene_to_packed(next_level_scene)


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
