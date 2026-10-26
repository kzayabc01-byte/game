@tool
class_name LevelMarker
extends Control

signal activated(path: String)

const RING := preload("res://assets/ui/level_select/ring.svg")
const LOCKED_RING := preload("res://assets/ui/level_select/ring_locked.svg")
const DOT := preload("res://assets/ui/level_select/center_dot.svg")
const SELECTED_DOT := preload("res://assets/ui/level_select/center_selected.svg")

@export_range(1, 99) var level_number: int = 1:
	set(value):
		level_number = value
		_update_if_ready()
@export var level_title: String = "关卡名称":
	set(value):
		level_title = value
		_update_if_ready()
@export_file("*.tscn") var level_path: String = ""
@export var level_id: String = ""
@export var locked: bool = false:
	set(value):
		locked = value
		_update_if_ready()
@export var completed: bool = false:
	set(value):
		completed = value
		_update_if_ready()
@export var placeholder: bool = false:
	set(value):
		placeholder = value
		_update_if_ready()
@export var highlighted: bool = false:
	set(value):
		highlighted = value
		_update_if_ready()
@export var preview_name: bool = false:
	set(value):
		preview_name = value
		_update_if_ready()

@onready var _hit: Button = $HitButton
@onready var _visual: Control = $HitButton/Visual
@onready var _ring: TextureRect = $HitButton/Visual/Ring
@onready var _selected_ring: TextureRect = $HitButton/Visual/SelectedRing
@onready var _center_dot: TextureRect = $HitButton/Visual/CenterDot
@onready var _lock_icon: TextureRect = $HitButton/Visual/LockIcon
@onready var _orbit: Node2D = $HitButton/Visual/OrbitPivot
@onready var _number: Label = $NumberLabel
@onready var _name: Label = $NameLabel
@onready var _underline: TextureRect = $NameUnderline
@onready var _animation: AnimationPlayer = $AnimationPlayer

var _hovered := false
var _focused := false
var _feedback: Tween


func _ready() -> void:
	apply_state()
	if Engine.is_editor_hint():
		return
	_hit.mouse_entered.connect(set_hovered.bind(true))
	_hit.mouse_exited.connect(set_hovered.bind(false))
	_hit.focus_entered.connect(_set_focused.bind(true))
	_hit.focus_exited.connect(_set_focused.bind(false))
	_hit.button_down.connect(_on_button_down)
	_hit.button_up.connect(_on_button_up)
	_hit.pressed.connect(_on_pressed)


func configure(record: Dictionary, is_locked: bool, is_completed: bool, is_current: bool) -> void:
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	_visual.scale = Vector2.ONE
	level_id = str(record.get("level_id", ""))
	level_path = str(record.get("path", ""))
	level_title = str(record.get("title", "尚未开放"))
	placeholder = record.is_empty()
	locked = is_locked or placeholder
	completed = is_completed
	highlighted = is_current
	_hovered = false
	_focused = false
	apply_state()


func _update_if_ready() -> void:
	if is_node_ready():
		apply_state()


func apply_state() -> void:
	if not is_node_ready():
		return
	_hit.disabled = locked or placeholder
	_hit.tooltip_text = ""
	_ring.texture = LOCKED_RING if locked or placeholder else RING
	_center_dot.texture = SELECTED_DOT if highlighted else DOT
	_center_dot.visible = completed or highlighted
	_lock_icon.visible = locked or placeholder
	_number.text = "%02d" % level_number
	_number.add_theme_color_override("font_color", Color("999b96") if locked or placeholder else Color("303638"))
	_name.text = "尚未开放" if placeholder else level_title
	_name.add_theme_color_override("font_color", Color("999b96") if locked or placeholder else Color("303638"))
	_update_emphasis()


func set_hovered(value: bool) -> void:
	_hovered = value
	_update_emphasis()
	_animate_scale(1.08 if value and not locked and not placeholder else 1.0)


func _set_focused(value: bool) -> void:
	_focused = value
	_update_emphasis()


func _update_emphasis() -> void:
	var show_name := _hovered or _focused or (Engine.is_editor_hint() and preview_name)
	_name.visible = show_name
	_underline.visible = show_name
	var emphasized := (highlighted or _hovered or _focused) and not locked and not placeholder
	_selected_ring.visible = emphasized
	_orbit.visible = emphasized
	if not Engine.is_editor_hint():
		if emphasized and not _animation.is_playing():
			_animation.play("orbit")
		elif not emphasized:
			_animation.stop()


func _animate_scale(value: float) -> void:
	if Engine.is_editor_hint():
		return
	if _feedback != null and _feedback.is_valid():
		_feedback.kill()
	_feedback = create_tween()
	_feedback.tween_property(_visual, "scale", Vector2.ONE * value, 0.12).set_trans(Tween.TRANS_SINE)


func _on_button_down() -> void:
	_animate_scale(0.96)


func _on_button_up() -> void:
	_animate_scale(1.08 if _hovered else 1.0)


func _on_pressed() -> void:
	if locked or placeholder or level_path.is_empty():
		return
	activated.emit(level_path)
