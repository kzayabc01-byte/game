extends Node2D
## 运行时材质总览：实例化真实机关场景，避免预览与游戏内资源引用不一致。

const WALL_SCENE: PackedScene = preload("res://blocks/wall/wall.tscn")
const OPAQUE_WALL_SCENE: PackedScene = preload("res://blocks/opaque_wall/opaque_wall.tscn")
const STONE_SCENE: PackedScene = preload("res://blocks/stone_block/stone_block.tscn")
const SHORT_SLOPE_SCENE: PackedScene = preload("res://blocks/dark_slope/dark_slope_short.tscn")
const LONG_SLOPE_SCENE: PackedScene = preload("res://blocks/dark_slope/dark_slope_long.tscn")
const MIRROR_SCENE: PackedScene = preload("res://blocks/mirror/mirror.tscn")
const CONVEX_SCENE: PackedScene = preload("res://blocks/convex_lens/convex_lens.tscn")
const CONCAVE_SCENE: PackedScene = preload("res://blocks/concave_lens/concave_lens.tscn")
const REFRACT_SCENE: PackedScene = preload("res://blocks/refract_surface/refract_surface.tscn")
const GLACIER_SCENE: PackedScene = preload("res://blocks/glacier/glacier.tscn")
const LIGHT_SOURCE_SCENE: PackedScene = preload("res://blocks/light_source/light_source.tscn")
const TRIGGER_SCENE: PackedScene = preload("res://blocks/trigger_switch/trigger_switch.tscn")
const SENSOR_SCENE: PackedScene = preload("res://blocks/pressure_sensor/pressure_sensor.tscn")
const PORTAL_SCENE: PackedScene = preload("res://blocks/portal/portal.tscn")


func _ready() -> void:
	_add_block(WALL_SCENE, Vector2(90.0, 145.0), "机关墙")
	_add_block(OPAQUE_WALL_SCENE, Vector2(200.0, 145.0), "遮光墙")
	var stone := _add_block(STONE_SCENE, Vector2(310.0, 145.0), "石块") as StoneBlock
	stone.gravity_enabled = false
	_add_block(SHORT_SLOPE_SCENE, Vector2(470.0, 145.0), "短斜坡")
	_add_block(LONG_SLOPE_SCENE, Vector2(720.0, 145.0), "长斜坡")

	_add_block(MIRROR_SCENE, Vector2(90.0, 390.0), "镜面")
	_add_block(CONVEX_SCENE, Vector2(205.0, 390.0), "凸透镜")
	_add_block(CONCAVE_SCENE, Vector2(300.0, 390.0), "凹透镜")
	_add_block(REFRACT_SCENE, Vector2(420.0, 390.0), "折射板")
	_add_block(GLACIER_SCENE, Vector2(560.0, 390.0), "冰川")
	var source := _add_block(LIGHT_SOURCE_SCENE, Vector2(670.0, 390.0), "光源") as LightSource
	source.follow_mouse = false
	_add_block(TRIGGER_SCENE, Vector2(770.0, 390.0), "未激活")
	var active_switch := _add_block(TRIGGER_SCENE, Vector2(850.0, 390.0), "已激活") as TriggerSwitch
	active_switch.set_editor_preview_active(true)
	var sensor := _add_block(SENSOR_SCENE, Vector2(940.0, 390.0), "压力板") as PressureSensor
	sensor.set_editor_preview_active(true)
	sensor.set_physics_process(false)
	var portal_a := _add_block(PORTAL_SCENE, Vector2(1030.0, 390.0), "传送门") as Portal
	var portal_b := _add_block(PORTAL_SCENE, Vector2(1100.0, 390.0), "") as Portal
	portal_a.pair_id = &"A"
	portal_b.pair_id = &"A"
	portal_a.linked_portal = portal_b
	portal_b.linked_portal = portal_a
	portal_a.queue_redraw()
	portal_b.queue_redraw()


func _add_block(scene: PackedScene, at: Vector2, caption: String) -> Node2D:
	var block := scene.instantiate() as Node2D
	block.position = at
	$Items.add_child(block)
	if not caption.is_empty():
		_add_caption(at + Vector2(0.0, 78.0), caption)
	return block


func _add_caption(at: Vector2, caption: String) -> void:
	var label := Label.new()
	label.position = at - Vector2(55.0, 12.0)
	label.size = Vector2(110.0, 28.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.1, 0.13, 0.17))
	label.add_theme_font_size_override("font_size", 16)
	label.text = caption
	$Labels.add_child(label)
