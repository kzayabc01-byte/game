@tool
extends Sprite2D

## 让可编辑的美术贴图跟随积木碰撞尺寸；只缩放外观，不修改光学碰撞。
enum FitMode {
	STRETCH,
	CONTAIN,
	COVER,
}

const ADJUSTABLE_SPRITE_SHADER: Shader = preload(
		"res://assets/materials/shaders/adjustable_sprite.gdshader")

@export var collision_path: NodePath = NodePath("../CollisionShape2D")
@export var size_multiplier := Vector2.ONE
@export var rotate_texture_quarter_turn := false
@export var fit_mode: FitMode = FitMode.STRETCH
@export_category("颜色调节 / Color")
@export_color_no_alpha var tint_color: Color = Color.WHITE:
	set(value):
		tint_color = value
		_update_material()
@export_range(0.0, 1.0, 0.01) var color_concentration: float = 0.0:
	set(value):
		color_concentration = value
		_update_material()
@export_range(0.0, 2.0, 0.01) var saturation: float = 1.0:
	set(value):
		saturation = value
		_update_material()
@export_range(0.25, 2.0, 0.01) var brightness: float = 1.0:
	set(value):
		brightness = value
		_update_material()
@export_range(0.25, 2.0, 0.01) var contrast: float = 1.0:
	set(value):
		contrast = value
		_update_material()
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0:
	set(value):
		opacity = value
		_update_material()

var _last_fit := Vector2.ZERO
var _last_texture_size := Vector2.ZERO
var _last_quarter_turn := false
var _last_fit_mode: FitMode = FitMode.STRETCH
var _shader_material: ShaderMaterial


func _ready() -> void:
	_fit_art()
	_update_material()


func _process(_delta: float) -> void:
	_fit_art()


func _fit_art() -> void:
	var collision := get_node_or_null(collision_path) as CollisionShape2D
	if collision == null or not collision.shape is RectangleShape2D or texture == null:
		return
	var fitted_size := (collision.shape as RectangleShape2D).size * size_multiplier
	var source_size := texture.get_size()
	if fitted_size == _last_fit and source_size == _last_texture_size \
			and rotate_texture_quarter_turn == _last_quarter_turn \
			and fit_mode == _last_fit_mode:
		return
	_last_fit = fitted_size
	_last_texture_size = source_size
	_last_quarter_turn = rotate_texture_quarter_turn
	_last_fit_mode = fit_mode
	rotation = PI * 0.5 if rotate_texture_quarter_turn else 0.0
	var effective_source := source_size
	if rotate_texture_quarter_turn:
		effective_source = Vector2(source_size.y, source_size.x)
	var axis_scale := fitted_size / effective_source
	if fit_mode == FitMode.STRETCH:
		scale = Vector2(axis_scale.y, axis_scale.x) if rotate_texture_quarter_turn else axis_scale
		return
	var uniform_scale := minf(axis_scale.x, axis_scale.y)
	if fit_mode == FitMode.COVER:
		uniform_scale = maxf(axis_scale.x, axis_scale.y)
	scale = Vector2.ONE * uniform_scale


func _update_material() -> void:
	if not is_instance_valid(_shader_material):
		_shader_material = ShaderMaterial.new()
		_shader_material.shader = ADJUSTABLE_SPRITE_SHADER
		material = _shader_material
	_shader_material.set_shader_parameter("tint_color", tint_color)
	_shader_material.set_shader_parameter("color_concentration", color_concentration)
	_shader_material.set_shader_parameter("saturation", saturation)
	_shader_material.set_shader_parameter("brightness", brightness)
	_shader_material.set_shader_parameter("contrast", contrast)
	_shader_material.set_shader_parameter("opacity", opacity)
