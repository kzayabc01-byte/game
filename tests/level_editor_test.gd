extends Node

## 关卡编辑器 API 测试（验证门 2）：headless 实例化编辑器场景，
## 验证六步挂载中和、生成/命名、电线连线序列化、撤销复原、删除/复制。
## 跑法：godot --headless --path . res://tests/level_editor_test.tscn

const WALL_SCENE := "res://blocks/wall/wall.tscn"
const SWITCH_SCENE := "res://blocks/trigger_switch/trigger_switch.tscn"
const MOVING_SCENE := "res://blocks/moving_base/moving_base.tscn"
const REFRACT_SCENE := "res://blocks/refract_surface/refract_surface.tscn"

var _failures: Array[String] = []
var _editor: LevelEditor = null


func _ready() -> void:
	# 看门狗：_run 中途崩溃时 quit 不会执行，保证进程必定退出而不是挂死
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("TEST RESULT: FAIL（90 秒超时，测试脚本崩溃或挂起）")
		get_tree().quit(1))
	_run()


func _check(message: String, condition: bool) -> void:
	if condition:
		print("  [OK]   ", message)
	else:
		_failures.append(message)
		print("  [FAIL] ", message)


func _run() -> void:
	var packed := load("res://scenes/editor/level_editor.tscn") as PackedScene
	_check("编辑器场景可加载", packed != null)
	if packed == null:
		_finish()
		return
	_editor = packed.instantiate() as LevelEditor
	add_child(_editor)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. 场景结构
	_check("编辑器节点树齐全",
			_editor.get_node_or_null("World/RayRenderer") != null
			and _editor.get_node_or_null("World/WireLayer") != null
			and _editor.get_node_or_null("World/LevelRoot") != null
			and _editor.get_node_or_null("World/Gizmo") != null
			and _editor.get_node_or_null("EditorCamera") != null
			and _editor.get_node_or_null("UI") != null)

	# 2. new_level 中和（六步管线）
	var root := _editor.get_level_root()
	_check("new_level 挂载了关卡根", root != null)
	_check("关卡根 process 已停摆", root != null and root.process_mode == Node.PROCESS_MODE_DISABLED)
	var level_camera := root.get_node_or_null("Camera2D") as Camera2D
	_check("关卡相机已禁用", level_camera != null and not level_camera.enabled)

	# 3. 生成与命名
	var wall1 := _editor.spawn_block(WALL_SCENE, Vector2(100, 100))
	var wall2 := _editor.spawn_block(WALL_SCENE, Vector2(200, 200))
	_check("生成第一块墙体命名 Wall", wall1 != null and wall1.name == "Wall")
	_check("生成第二块墙体命名 Wall2", wall2 != null and wall2.name == "Wall2")
	_check("积木挂在 Blocks 下", wall1 != null and wall1.get_parent() == root.get_node("Blocks"))

	# 4. 微移 + 撤销复原（撤销会换子树，引用全部重取）
	_editor.select(wall1)
	_editor.nudge_selected(Vector2(32, 0))
	_check("微移生效", wall1.position == Vector2(132, 100))
	_check("撤销成功", _editor.undo())
	root = _editor.get_level_root()
	wall1 = root.get_node("Blocks/Wall") as Node2D
	_check("撤销后位置复原", wall1 != null and wall1.position == Vector2(100, 100))

	# 5. 电线连线
	var trigger := _editor.spawn_block(SWITCH_SCENE, Vector2(300, 300))
	var moving := _editor.spawn_block(MOVING_SCENE, Vector2(400, 300))
	_check("连线成功", _editor.connect_wire(trigger, moving))
	_check("电线数 1", _editor.get_wire_count() == 1)
	_check("重复连线到同一机关被拒绝", not _editor.connect_wire(trigger, moving))
	_check("电线数仍为 1", _editor.get_wire_count() == 1)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check("底座在编辑器里不漂移", moving != null and moving.position == Vector2(400, 300))

	# 6. 序列化内容
	var text := _editor.serialize()
	_check("序列化含正确电线连接行", text.contains(
			"[connection signal=\"active_changed\" from=\"Blocks/TriggerSwitch\" to=\"Blocks/Wire\" method=\"_on_signal\"]"))
	_check("序列化含电线节点目标", text.contains("target_node = NodePath(\"../MovingBase\")"))
	_check("输出不含编辑器节点", not text.contains("WireLayer") and not text.contains("LevelEditor")
			and not text.contains("Gizmo") and not text.contains("EditorCamera")
			and not text.contains("RayRenderer"))

	# 7. 产物可载入、连接表正确
	var out_path := "user://editor_test_level.tscn"
	_check("写临时关卡文件", LevelFileIO.write_text(out_path, text) == OK)
	var reloaded_packed := load(out_path) as PackedScene
	_check("产物可载入", reloaded_packed != null)
	var reloaded := reloaded_packed.instantiate()
	var reloaded_trigger := reloaded.get_node("Blocks/TriggerSwitch")
	_check("重载后连接表正确", reloaded_trigger != null
			and reloaded_trigger.get_signal_connection_list(&"active_changed").size() == 1)
	var reloaded_wire := reloaded.get_node_or_null("Blocks/Wire")
	_check("重载后电线节点存在", reloaded_wire != null
			and reloaded_wire is ActionLink
			and (reloaded_wire as ActionLink).target_node == NodePath("../MovingBase"))
	_check("重载后 4 块积木 + 1 条电线", LevelFileIO.walk_instance_roots(reloaded).size() == 5)
	reloaded.free()

	# 8. 删除
	wall2 = root.get_node("Blocks/Wall2") as Node2D
	_check("删除前 Wall2 存在", wall2 != null)
	_editor.select(wall2)
	_editor.delete_selected()
	_check("删除后序列化不含 Wall2", not _editor.serialize().contains("name=\"Wall2\""))

	# 9. 复制
	wall1 = root.get_node("Blocks/Wall") as Node2D
	_editor.select(wall1)
	_editor.duplicate_selected()
	var blocks := root.get_node("Blocks")
	_check("复制后 Blocks 下有两块墙体", blocks.has_node("Wall") and blocks.has_node("Wall2"))
	var copy := blocks.get_node("Wall2") as Node2D
	_check("复制体偏移 32px", copy != null and copy.position == Vector2(132, 132))

	# 10. 颜色积木预设（变色片 = 折射面改色预设；颜色感应开关 = 触发开关颜色感应预设）
	var changer := _editor.spawn_block(
			REFRACT_SCENE, Vector2(500, 500), "", {"recolor": true}, "color_changer")
	_check("变色片预设生效", changer != null and changer.recolor and changer.name == "ColorChanger")
	var color_entry := PaletteData.find_entry_for(REFRACT_SCENE, "ColorChanger")
	_check("预设条目按名字区分", color_entry.get("key", "") == "color_changer")
	var plain_entry := PaletteData.find_entry_for(REFRACT_SCENE, "RefractSurface")
	_check("普通折射面不受预设影响", plain_entry.get("key", "") == "refract_surface")
	var color_trigger := _editor.spawn_block(
			SWITCH_SCENE, Vector2(600, 500), "",
			{"match_color": true, "color_filter": Color(1.0, 0.25, 0.25)}, "color_trigger")
	_check("颜色感应预设生效", color_trigger != null and color_trigger.match_color)
	_check("感应开关命名 ColorTrigger", color_trigger != null and color_trigger.name == "ColorTrigger")

	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("TEST RESULT: PASS")
		get_tree().quit(0)
	else:
		print("TEST RESULT: FAIL（%d 项）" % _failures.size())
		get_tree().quit(1)
