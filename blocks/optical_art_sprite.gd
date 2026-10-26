@tool
extends Sprite2D

## 让可编辑的美术贴图跟随积木碰撞尺寸；只缩放外观，不修改光学碰撞。
@export var collision_path: NodePath = NodePath("../CollisionShape2D")
@export var size_multiplier := Vector2.ONE
@export var rotate_texture_quarter_turn := false

var _last_fit := Vector2.ZERO
var _last_texture_size := Vector2.ZERO
var _last_quarter_turn := false


func _ready() -> void:
	_fit_art()


func _process(_delta: float) -> void:
	_fit_art()


func _fit_art() -> void:
	var collision := get_node_or_null(collision_path) as CollisionShape2D
	if collision == null or not collision.shape is RectangleShape2D or texture == null:
		return
	var fitted_size := (collision.shape as RectangleShape2D).size * size_multiplier
	var source_size := texture.get_size()
	if fitted_size == _last_fit and source_size == _last_texture_size \
			and rotate_texture_quarter_turn == _last_quarter_turn:
		return
	_last_fit = fitted_size
	_last_texture_size = source_size
	_last_quarter_turn = rotate_texture_quarter_turn
	rotation = PI * 0.5 if rotate_texture_quarter_turn else 0.0
	if rotate_texture_quarter_turn:
		scale = Vector2(fitted_size.y / source_size.x, fitted_size.x / source_size.y)
	else:
		scale = fitted_size / source_size
