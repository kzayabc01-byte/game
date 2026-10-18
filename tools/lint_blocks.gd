extends SceneTree

## 积木校验器：扫描 blocks\* 下每个积木，检查“根节点类型 / 碰撞层 / 脚本 / 命名”。
## 运行：godot --headless --path . --script res://tools/lint_blocks.gd
## 退出码：0 = 全部正常，1 = 有错误。

const BLOCKS_DIR := "res://blocks"
const LAYER_OPAQUE := 1
const LAYER_MIRROR := 2
const LAYER_OPTIC := 8    # 层 4：折射体 / 凹透镜 / 冰川
const LAYER_PORTAL := 16  # 层 5：传送门

var _errors: int = 0
var _warnings: int = 0


func _initialize() -> void:
	print("")
	print("  ===== 积木检查 =====")
	print("")

	var dir := DirAccess.open(BLOCKS_DIR)
	if dir == null:
		printerr("  打不开目录：%s" % BLOCKS_DIR)
		quit(1)
		return

	var folders: Array[String] = []
	for entry in dir.get_directories():
		if entry.begins_with("_") or entry.begins_with("."):
			continue
		folders.append(entry)
	folders.sort()

	var class_names := {}
	for folder in folders:
		_check_block(folder, class_names)

	print("")
	if _errors == 0 and _warnings == 0:
		print("  结果：%d 个积木，全部正常。" % folders.size())
	elif _errors == 0:
		print("  结果：%d 个积木，%d 个警告，0 个错误。" % [folders.size(), _warnings])
	else:
		print("  结果：%d 个积木，%d 个错误，%d 个警告。" % [folders.size(), _errors, _warnings])
	print("")

	quit(1 if _errors > 0 else 0)


func _check_block(folder: String, class_names: Dictionary) -> void:
	var block_dir := BLOCKS_DIR + "/" + folder
	var scene_path := block_dir + "/" + folder + ".tscn"
	var script_path := block_dir + "/" + folder + ".gd"

	if not folder.is_valid_identifier():
		_warn(folder, "文件夹名不是合法的标识符（建议小写+下划线）")
	if not ResourceLoader.exists(scene_path):
		_error(folder, "缺少场景文件：%s/%s.tscn" % [folder, folder])
		return
	if not ResourceLoader.exists(script_path):
		_warn(folder, "缺少同名脚本：%s/%s.gd" % [folder, folder])

	var script := load(script_path) as Script
	if script != null:
		var gname := String(script.get_global_name())
		if gname.is_empty():
			_warn(folder, "脚本没有 class_name，组员用不了类型提示")
		elif class_names.has(gname):
			_error(folder, "class_name 重复：%s（另一个是 %s）" % [gname, class_names[gname]])
		else:
			class_names[gname] = folder

	var packed := load(scene_path) as PackedScene
	if packed == null:
		_error(folder, "场景加载失败：%s" % scene_path)
		return

	var node := packed.instantiate()
	if node == null:
		_error(folder, "场景实例化失败（可能有脚本报错）")
		return

	_classify(folder, node)
	node.free()


func _classify(folder: String, node: Node) -> void:
	if node is OpticalSurface:
		_classify_optical(folder, node)
		return

	if node is LightReceiver:
		var shapes := _count_shapes(node)
		if shapes == 0:
			_error(folder, "机关缺少 CollisionShape2D（感光区）")
		else:
			_ok(folder, "机关 · 感光区形状 %d 个" % shapes)
		return

	if node is StaticBody2D or node is AnimatableBody2D:
		var layer: int = node.collision_layer
		var opaque := (layer & LAYER_OPAQUE) != 0
		var mirror := (layer & LAYER_MIRROR) != 0
		if opaque and mirror:
			_warn(folder, "同时占了「遮光物」和「镜面」两层，光线行为可能不符合预期")
		elif opaque:
			_ok(folder, "遮光物 · 层 1")
		elif mirror:
			_ok(folder, "镜面 · 层 2")
		else:
			_error(folder, "碰撞层 %d 不对：遮光物应放层 1，镜面应放层 2，折射类应放层 4" % layer)
		return

	if node is LightSource:
		_ok(folder, "光源")
		return

	if node is Area2D:
		if node is PressureSensor:
			_ok(folder, "压力传感器（重物压住发信号，不感光） · mask 1")
			return
		_error(folder, "Area2D 但没继承 LightReceiver：机关请 extends LightReceiver")
		return

	if node is Node2D or node is Node:
		_warn(folder, "未分类的积木（根节点 %s），确认它确实是关卡组件" % node.get_class())
		return


## 光路表面（OpticalSurface）：折射类放层 4，传送门放层 5
func _classify_optical(folder: String, node: Node) -> void:
	var layer: int = (node as CollisionObject2D).collision_layer
	if _count_shapes(node) == 0:
		_error(folder, "光路积木缺少 CollisionShape2D（光线打不到它）")
		return

	if node is Portal:
		if (layer & LAYER_PORTAL) == 0:
			_error(folder, "传送门应放层 5（当前碰撞层 %d）" % layer)
		elif not (node as Portal).is_linked():
			_warn(folder, "传送门没有预配 linked_portal（运行时会自动连最近的同类门）")
		else:
			_ok(folder, "传送门 · 层 5")
		return

	if (layer & LAYER_OPTIC) == 0:
		_error(folder, "折射类应放层 4（当前碰撞层 %d）" % layer)
		return

	if node is Glacier:
		_ok(folder, "冰川（折射 + 可融化） · 层 4")
	elif node is ConcaveLens:
		_ok(folder, "凹透镜（分 %d 束） · 层 4" % (node as ConcaveLens).split_count)
	elif node is RefractSurface:
		_ok(folder, "折射介质（偏折 %.0f°） · 层 4" % (node as RefractSurface).bend_degrees)
	else:
		_ok(folder, "光路表面 · 层 4")


func _count_shapes(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			count += 1
		count += _count_shapes(child)
	return count


func _ok(folder: String, msg: String) -> void:
	print("  [OK]   %s —— %s" % [folder, msg])


func _warn(folder: String, msg: String) -> void:
	_warnings += 1
	print("  [警告] %s —— %s" % [folder, msg])


func _error(folder: String, msg: String) -> void:
	_errors += 1
	printerr("  [错误] %s —— %s" % [folder, msg])
