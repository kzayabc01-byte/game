extends Node
## 防止机关场景退回旧图集、占位绘制或与碰撞不一致的完整图片轮廓。

const CONVEX_SCENE: PackedScene = preload("res://blocks/convex_lens/convex_lens.tscn")
const CONCAVE_SCENE: PackedScene = preload("res://blocks/concave_lens/concave_lens.tscn")
const MIRROR_SCENE: PackedScene = preload("res://blocks/mirror/mirror.tscn")
const STONE_SCENE: PackedScene = preload("res://blocks/stone_block/stone_block.tscn")
const SHORT_SLOPE_SCENE: PackedScene = preload("res://blocks/dark_slope/dark_slope_short.tscn")
const BASE_SCENE: PackedScene = preload("res://scenes/levels/level_base.tscn")

var _failed: int = 0


func _ready() -> void:
	_check_sprite(CONVEX_SCENE, "res://assets/mechanisms/optics/convex_lens.png", "凸透镜直接使用独立贴图")
	_check_sprite(CONCAVE_SCENE, "res://assets/mechanisms/optics/concave_lens.png", "凹透镜直接使用独立贴图")
	_check_sprite(MIRROR_SCENE, "res://assets/mechanisms/props/mirror_panel_clean.png", "镜面直接使用清理贴图")
	_check_stone_outline()
	_check_slope_outline()
	_check_background()
	print("TEST RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(0 if _failed == 0 else 1)


func _check_sprite(scene: PackedScene, expected_path: String, label: String) -> void:
	var root := scene.instantiate()
	var art := root.get_node_or_null("Art") as Sprite2D
	var correct := art != null and art.texture != null and art.texture.resource_path == expected_path
	_check(label, correct)
	root.free()


func _check_stone_outline() -> void:
	var root := STONE_SCENE.instantiate()
	var collision := root.get_node("CollisionShape2D") as CollisionShape2D
	var visual := root.get_node("Visual") as Polygon2D
	var shape := collision.shape as ConvexPolygonShape2D
	_check("石块使用不规则凸多边形碰撞", shape != null and shape.points.size() >= 6)
	_check("石块显示与碰撞共用轮廓", shape != null and shape.points == visual.polygon)
	root.free()


func _check_slope_outline() -> void:
	var root := SHORT_SLOPE_SCENE.instantiate()
	var collision := root.get_node("CollisionPolygon2D") as CollisionPolygon2D
	var visual := root.get_node("Visual") as Polygon2D
	_check("斜坡显示与碰撞共用轮廓", collision.polygon == visual.polygon)
	root.free()


func _check_background() -> void:
	var root := BASE_SCENE.instantiate()
	var texture_rect := root.get_node_or_null("Background/Texture") as TextureRect
	var correct := texture_rect != null and texture_rect.texture != null \
			and texture_rect.texture.resource_path == "res://assets/mechanisms/textures/light_background.png"
	_check("游玩关卡使用浅色背景材质", correct)
	root.free()


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  [OK]   %s" % label)
		return
	_failed += 1
	print("  [FAIL] %s" % label)
