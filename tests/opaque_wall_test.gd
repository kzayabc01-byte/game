extends Node

const OPAQUE_WALL_SCENE: PackedScene = preload("res://blocks/opaque_wall/opaque_wall.tscn")
const WALL_SCENE: PackedScene = preload("res://blocks/wall/wall.tscn")
const SWITCH_SCENE: PackedScene = preload("res://blocks/trigger_switch/trigger_switch.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run()


func _run() -> void:
	var blocks := Node2D.new()
	add_child(blocks)
	var opaque_wall := OPAQUE_WALL_SCENE.instantiate() as OpaqueWallBlock
	blocks.add_child(opaque_wall)
	var regular_wall := WALL_SCENE.instantiate() as WallBlock
	regular_wall.position = Vector2(0.0, 200.0)
	blocks.add_child(regular_wall)
	var trigger := SWITCH_SCENE.instantiate() as TriggerSwitch
	trigger.position = Vector2(0.0, 100.0)
	blocks.add_child(trigger)

	_check("固定遮光墙在编辑器元件列表中", not PaletteData.find_entry(
			OPAQUE_WALL_SCENE.resource_path).is_empty())
	_check("固定遮光墙使用遮光层", opaque_wall.collision_layer == RayCaster.LAYER_OPAQUE)
	_check("普通墙仍可接线", WireService.is_target(regular_wall))
	_check("固定遮光墙不是电线目标", not WireService.is_target(opaque_wall))
	_check("固定遮光墙拒绝机关电线", WireService.create_wire(blocks, trigger, opaque_wall) == null)

	var manager := LevelManager.new()
	manager.level_kind = LevelManager.LevelKind.BUILD
	manager.build_wire_limit = 1
	manager.build_item_keys = PackedStringArray(["opaque_wall"])
	manager.build_item_counts = PackedInt32Array([1])
	manager.build_wire_sources = PackedStringArray(["TriggerSwitch"])
	var errors := LevelValidator.validate_build(manager, blocks)
	_check("仅提供固定遮光墙时不误判为可接线目标",
			errors.has("已提供电线，但没有可用目标：开放预置元件接线，或提供元件库存"))
	manager.build_wire_targets = PackedStringArray(["OpaqueWall"])
	errors = LevelValidator.validate_build(manager, blocks)
	_check("校验拒绝把预置固定遮光墙开放为电线目标",
			errors.has("允许接线的预置目标无效：OpaqueWall"))
	manager.free()

	await get_tree().physics_frame
	await get_tree().physics_frame
	var trace := RayCaster.trace(get_viewport().world_2d.direct_space_state,
			Vector2(-100.0, 0.0), Vector2.RIGHT, 0, 200.0)
	_check("光线在固定遮光墙表面停止",
			trace.segments.size() == 2
			and absf(trace.segments[1].x + 32.0) < 2.0)
	if _failures.is_empty():
		print("TEST RESULT: PASS")
		get_tree().quit(0)
	else:
		print("TEST RESULT: FAIL: ", ", ".join(_failures))
		get_tree().quit(1)


func _check(message: String, condition: bool) -> void:
	if condition:
		print("TEST: ", message, ": PASS")
	else:
		_failures.append(message)
		print("TEST: ", message, ": FAIL")
