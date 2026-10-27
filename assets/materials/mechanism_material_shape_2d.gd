@tool
class_name MechanismMaterialShape2D
extends Polygon2D
## 只使用材质填充既定轮廓，不携带任何机关造型。
## 每个节点拥有独立的 ShaderMaterial，因此 Inspector 中的颜色调节互不影响。

enum MaterialMode {
	MATTE,
	GLASS,
	ICE,
}

const MATERIAL_SHADER: Shader = preload("res://assets/materials/shaders/textured_shape.gdshader")

@export_category("材质纹理 / Material")
@export var material_mode: MaterialMode = MaterialMode.MATTE:
	set(value):
		material_mode = value
		_update_material()
@export var material_texture: Texture2D:
	set(value):
		material_texture = value
		_update_material()
@export_range(16.0, 512.0, 1.0) var tile_size_pixels: float = 96.0:
	set(value):
		tile_size_pixels = value
		_update_material()
@export var material_texture_scale: Vector2 = Vector2.ONE:
	set(value):
		material_texture_scale = value
		_update_material()
@export var material_texture_offset: Vector2 = Vector2.ZERO:
	set(value):
		material_texture_offset = value
		_update_material()
@export_range(0.0, 1.0, 0.001) var texture_midpoint: float = 0.5:
	set(value):
		texture_midpoint = value
		_update_material()
@export_range(0.0, 1.0, 0.01) var texture_detail_strength: float = 0.15:
	set(value):
		texture_detail_strength = value
		_update_material()
@export_group("轮廓适配 / Shape Fit")
@export var shape_size_pixels: Vector2 = Vector2(64.0, 64.0):
	set(value):
		shape_size_pixels = value
		_update_material()
@export var auto_fit_collision_rectangle: bool = false:
	set(value):
		auto_fit_collision_rectangle = value
		set_process(value)
		_fit_collision_rectangle()
@export_node_path("CollisionShape2D") var collision_shape_path: NodePath = NodePath("../CollisionShape2D")
@export_range(0.0, 24.0, 0.5) var corner_cut: float = 0.0:
	set(value):
		corner_cut = value
		_last_fitted_size = Vector2.ZERO
		_fit_collision_rectangle()

@export_category("颜色调节 / Color")
@export_color_no_alpha var base_color: Color = Color(0.5, 0.5, 0.5):
	set(value):
		base_color = value
		_update_material()
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

@export_category("发光 / Glow")
@export_color_no_alpha var emission_color: Color = Color.WHITE:
	set(value):
		emission_color = value
		_update_material()
@export_range(0.0, 2.0, 0.01) var emission_strength: float = 0.0:
	set(value):
		emission_strength = value
		_update_material()
@export_color_no_alpha var edge_highlight_color: Color = Color.WHITE:
	set(value):
		edge_highlight_color = value
		_update_material()
@export_range(0.0, 1.0, 0.01) var edge_highlight_strength: float = 0.0:
	set(value):
		edge_highlight_strength = value
		_update_material()

var _runtime_opacity: float = 1.0
var _shader_material: ShaderMaterial
var _last_fitted_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	set_process(auto_fit_collision_rectangle)
	_fit_collision_rectangle()
	_update_material()


func _process(_delta: float) -> void:
	_fit_collision_rectangle()


func set_runtime_opacity(value: float) -> void:
	_runtime_opacity = clampf(value, 0.0, 1.0)
	_update_material()


func _ensure_material() -> void:
	if is_instance_valid(_shader_material):
		return
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = MATERIAL_SHADER
	material = _shader_material


func _update_material() -> void:
	_ensure_material()
	_shader_material.set_shader_parameter("albedo_texture", material_texture)
	_shader_material.set_shader_parameter("material_mode", material_mode)
	_shader_material.set_shader_parameter("tile_size_pixels", tile_size_pixels)
	_shader_material.set_shader_parameter("texture_scale", material_texture_scale)
	_shader_material.set_shader_parameter("texture_offset", material_texture_offset)
	_shader_material.set_shader_parameter("shape_size_pixels", shape_size_pixels)
	_shader_material.set_shader_parameter("texture_midpoint", texture_midpoint)
	_shader_material.set_shader_parameter("texture_detail_strength", texture_detail_strength)
	_shader_material.set_shader_parameter("base_color", base_color)
	_shader_material.set_shader_parameter("tint_color", tint_color)
	_shader_material.set_shader_parameter("color_concentration", color_concentration)
	_shader_material.set_shader_parameter("saturation", saturation)
	_shader_material.set_shader_parameter("brightness", brightness)
	_shader_material.set_shader_parameter("contrast", contrast)
	_shader_material.set_shader_parameter("opacity", opacity * _runtime_opacity)
	_shader_material.set_shader_parameter("emission_color", emission_color)
	_shader_material.set_shader_parameter("emission_strength", emission_strength)
	_shader_material.set_shader_parameter("edge_highlight_color", edge_highlight_color)
	_shader_material.set_shader_parameter("edge_highlight_strength", edge_highlight_strength)


func _fit_collision_rectangle() -> void:
	if not auto_fit_collision_rectangle or not is_inside_tree():
		return
	var shape_node := get_node_or_null(collision_shape_path) as CollisionShape2D
	if shape_node == null or not shape_node.shape is RectangleShape2D:
		return
	var size: Vector2 = (shape_node.shape as RectangleShape2D).size
	if size.is_equal_approx(_last_fitted_size):
		return
	_last_fitted_size = size
	shape_size_pixels = size
	var half := size * 0.5
	var cut := minf(corner_cut, minf(half.x, half.y))
	if is_zero_approx(cut):
		polygon = PackedVector2Array([
			-half,
			Vector2(half.x, -half.y),
			half,
			Vector2(-half.x, half.y),
		])
		return
	polygon = PackedVector2Array([
		Vector2(-half.x + cut, -half.y),
		Vector2(half.x - cut, -half.y),
		Vector2(half.x, -half.y + cut),
		Vector2(half.x, half.y - cut),
		Vector2(half.x - cut, half.y),
		Vector2(-half.x + cut, half.y),
		Vector2(-half.x, half.y - cut),
		Vector2(-half.x, -half.y + cut),
	])
