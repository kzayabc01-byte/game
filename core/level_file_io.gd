class_name LevelFileIO
extends RefCounted

## 关卡文件读写（关卡编辑器的序列化核心，纯静态工具类）：
## 把一棵活关卡树（level_base 实例 + Blocks 下的积木实例 + 信号连接）
## 序列化成标准 .tscn 文本，与现有关卡管线（主菜单扫描 / LevelManager / 测试）完全兼容。
## 规则：
##   * 只输出「实例根 + 属性覆盖 + [connection] 连接」，不输出任何编辑器节点；
##   * 属性覆盖 = 活节点 vs 未进树的同场景默认实例（_ready 不跑）的 diff；
##   * 连接 = 对关卡子树内省 get_signal_connection_list()，两端都必须来自积木场景。
## 编辑器里的电线（WireLayer）永远只存在于编辑器场景，不会被写进关卡文件。

const BASE_SCENE_DEFAULT := "res://scenes/levels/level_base.tscn"
const LEVELS_DIR := "res://scenes/levels"

## 电线兼容表：源信号 -> 允许连到的目标方法（电线 = ActionLink 节点，入口统一 _on_signal）
const WIRE_TABLE := {
	&"active_changed": [&"_on_signal"],
	&"pressed_changed": [&"_on_signal"],
}

const FLOAT_TOLERANCE := 1e-6
const LEVEL_METADATA_KEYS: Array[StringName] = [
	&"level_name", &"level_id", &"schema_version", &"publication_state", &"chapter", &"order_in_chapter",
	&"difficulty", &"mechanic_tags",
		&"level_kind", &"build_item_keys", &"build_item_counts",
		&"build_bounds", &"build_wire_limit", &"build_wire_targets",
		&"build_aimable_sources",
		&"build_wire_sources",
]

static var _queued_level_to_edit: String = ""


## 主菜单与编辑器之间的一次性关卡路径交接。只接受 levels 目录中的现有关卡。
static func queue_level_for_edit(path: String) -> bool:
	var prefix := LEVELS_DIR + "/"
	if not path.begins_with(prefix) or not FileAccess.file_exists(path):
		return false
	_queued_level_to_edit = path
	return true


## 取出后立即清空，避免下一次打开编辑器时误载入旧关卡。
static func take_level_to_edit() -> String:
	var path := _queued_level_to_edit
	_queued_level_to_edit = ""
	return path


## 不进场景树读取关卡目录所需元数据，避免触发游戏逻辑。
static func read_level_metadata(path: String) -> Dictionary:
	var packed := ResourceLoader.load(
			path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return {}
	var level_root := packed.instantiate()
	var manager := level_root.get_node_or_null("LevelManager") as LevelManager
	if manager == null:
		level_root.free()
		return {}
	var result := {
		&"level_name": manager.level_name,
		&"level_id": manager.level_id,
		&"schema_version": manager.schema_version,
		&"publication_state": int(manager.publication_state),
		&"chapter": manager.chapter,
		&"order_in_chapter": manager.order_in_chapter,
		&"difficulty": manager.difficulty,
		&"mechanic_tags": manager.mechanic_tags.duplicate(),
		&"level_kind": int(manager.level_kind),
	}
	level_root.free()
	return result


## 工坊发布只改变同一关卡的目录元数据，不复制或移动关卡文件。
static func update_level_metadata(path: String, values: Dictionary) -> Error:
	var packed := ResourceLoader.load(
			path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return ERR_FILE_NOT_FOUND
	var level_root := packed.instantiate()
	var manager := level_root.get_node_or_null("LevelManager") as LevelManager
	if manager == null:
		level_root.free()
		return ERR_INVALID_DATA
	for key in LEVEL_METADATA_KEYS:
		if values.has(key):
			manager.set(key, values[key])
	if manager.level_id.is_empty():
		manager.level_id = create_level_id()
	var base_path := get_base_scene_path_from_file(path)
	var text := serialize_level(level_root, base_path)
	level_root.free()
	var error := write_text(path, text)
	if error == OK:
		ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	return error


## 返回发布阻断项；空数组表示关卡具备进入“开始游戏”的最低结构。
static func validate_level_for_publication(path: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var packed := ResourceLoader.load(
			path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		errors.append("关卡文件无法载入")
		return errors
	var level_root := packed.instantiate()
	errors = LevelValidator.validate(level_root)
	level_root.free()
	return errors


## 把整棵关卡树序列化成 .tscn 文本
static func serialize_level(level_root: Node, base_scene_path: String = BASE_SCENE_DEFAULT) -> String:
	var ext_map: Dictionary = {}  # path -> {id, key}
	_ext_id(base_scene_path, "base", ext_map)
	for node in walk_instance_roots(level_root):
		if node.scene_file_path != "":
			_ext_id(node.scene_file_path, "", ext_map)
	var manager := level_root.get_node_or_null("LevelManager")
	if manager != null:
		var next_scene: PackedScene = manager.get("next_level_scene")
		if next_scene != null:
			_ext_id(next_scene.resource_path, "next", ext_map)

	var lines: Array[String] = []
	lines.append("[gd_scene load_steps=%d format=3]" % (ext_map.size() + 1))
	lines.append("")
	for path in _sorted_ext_paths(ext_map):
		lines.append("[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [
			path, ext_map[path]["id"],
		])
	lines.append("")
	lines.append("[node name=\"%s\" instance=ExtResource(\"%s\")]" % [level_root.name, ext_map[base_scene_path]["id"]])
	lines.append("")

	# base 内部节点（Camera2D / Blocks / LightSystem / LevelManager）只输出被覆盖的属性
	var base_default := (load(base_scene_path) as PackedScene).instantiate()
	for child in level_root.get_children():
		if child.scene_file_path == "":
			_append_node_block(lines, child, level_root, ext_map, base_default.get_node_or_null(NodePath(child.name)))
	base_default.free()

	# 积木实例（含嵌套实例）：节点 + 属性覆盖
	for node in walk_instance_roots(level_root):
		var fresh := (load(node.scene_file_path) as PackedScene).instantiate()
		_append_node_block(lines, node, level_root, ext_map, fresh)
		fresh.free()

	# 信号连接（按源路径排序，保证输出确定性）
	var connections := _collect_connections(level_root)
	connections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["from"] != b["from"]:
			return a["from"] < b["from"]
		if a["signal"] != b["signal"]:
			return String(a["signal"]) < String(b["signal"])
		return String(a["method"]) < String(b["method"]))
	if not connections.is_empty():
		lines.append("")
		for conn in connections:
			lines.append("[connection signal=\"%s\" from=\"%s\" to=\"%s\" method=\"%s\"]" % [
				conn["signal"], conn["from"], conn["to"], conn["method"],
			])
	return "\n".join(lines) + "\n"


static func create_level_id() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var parts: Array[String] = []
	for value in bytes:
		parts.append("%02x" % value)
	return "%s-%s-%s-%s-%s" % [
		"".join(parts.slice(0, 4)), "".join(parts.slice(4, 6)),
		"".join(parts.slice(6, 8)), "".join(parts.slice(8, 10)),
		"".join(parts.slice(10, 16)),
	]


## 进树前捕获积木实例的全部可存储属性（抵消 _ready 副作用，如传送门自动配对）
static func capture_props(level_root: Node) -> Dictionary:
	var result: Dictionary = {}
	for node in walk_instance_roots(level_root):
		var props: Dictionary = {}
		for prop in node.get_property_list():
			if not _is_storable(prop):
				continue
			props[prop.name] = node.get(prop.name)
		if not props.is_empty():
			result[_relative_path(level_root, node)] = props
	return result


## 进树之后把捕获的属性表回写（在 deferred 清理里调用）
static func restore_props(level_root: Node, props: Dictionary) -> void:
	for path in props:
		var node := level_root.get_node_or_null(NodePath(path))
		if node == null:
			continue
		var values: Dictionary = props[path]
		for prop in values:
			node.set(prop, values[prop])


## 把 from 的全部可存储属性复制到 to（编辑器复制积木用）；
## except_transform=true 跳过位置/旋转/缩放（复制后要偏移摆放）
static func copy_props(from: Node, to: Node, except_transform: bool = false) -> void:
	var transform_props := [&"position", &"rotation", &"scale"]
	for prop in from.get_property_list():
		if not _is_storable(prop):
			continue
		if except_transform and transform_props.has(prop["name"]):
			continue
		to.set(prop["name"], from.get(prop["name"]))


## 从关卡文件文本解析基座场景路径（打开关卡时用）
static func get_base_scene_path_from_file(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return BASE_SCENE_DEFAULT
	var id_to_path: Dictionary = {}
	var ext_re := RegEx.new()
	ext_re.compile("\\[ext_resource\\s+type=\"PackedScene\"[^\\]]*path=\"([^\"]+)\"[^\\]]*id=\"([^\"]+)\"\\]")
	for m in ext_re.search_all(text):
		id_to_path[m.get_string(2)] = m.get_string(1)
	var node_re := RegEx.new()
	node_re.compile("\\[node\\s+name=\"[^\"]+\"\\s+instance=ExtResource\\(\"([^\"]+)\"\\)\\]")
	for m in node_re.search_all(text):
		if id_to_path.has(m.get_string(1)):
			return id_to_path[m.get_string(1)]
	return BASE_SCENE_DEFAULT


## 从关卡文件文本解析根节点名
static func read_root_name(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	var re := RegEx.new()
	re.compile("\\[node\\s+name=\"([^\"]+)\"\\s+instance=ExtResource\\(\"[^\"]+\"\\)\\]")
	var m := re.search(text)
	if m != null:
		return m.get_string(1)
	return path.get_file().get_basename()


## 扫描关卡目录，返回按文件名排序的关卡文件名列表（主菜单同款规则）
static func scan_levels(dir: String = LEVELS_DIR) -> Array[String]:
	var result: Array[String] = []
	var handle := DirAccess.open(dir)
	if handle == null:
		return result
	for entry in handle.get_files():
		if not entry.ends_with(".tscn"):
			continue
		if not entry.begins_with("level_"):
			continue
		var short := entry.trim_prefix("level_")
		if short.is_empty() or not short.substr(0, 1).is_valid_int():
			continue
		result.append(entry)
	result.sort()
	return result


## 建议下一个关卡文件名（扫描现有编号 +1）
static func suggest_file_name(dir: String = LEVELS_DIR) -> String:
	var max_number := 0
	for entry in scan_levels(dir):
		var short := entry.trim_prefix("level_")
		var digits := ""
		for i in short.length():
			if short[i].is_valid_int():
				digits += short[i]
			else:
				break
		if digits != "":
			max_number = maxi(max_number, digits.to_int())
	return "level_%02d_说明.tscn" % (max_number + 1)


## 校验关卡文件名：level_NN.tscn 或 level_NN_说明.tscn
static func validate_file_name(file_name: String) -> bool:
	var re := RegEx.new()
	re.compile("^level_\\d{2}(_.*)?\\.tscn$")
	return re.search(file_name) != null


static func write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


static func is_valid_wire(signal_name: StringName, method_name: StringName) -> bool:
	var methods: Array = WIRE_TABLE.get(signal_name, [])
	return methods.has(method_name)


# ---------- 内部实现 ----------


## 收集关卡内所有积木实例根（scene_file_path 非空 = 来自积木场景的实例根），深度优先
static func walk_instance_roots(level_root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in level_root.get_children():
		_walk_instance_roots_recursive(child, result)
	return result


static func _walk_instance_roots_recursive(node: Node, result: Array[Node]) -> void:
	if node.scene_file_path != "":
		result.append(node)
	for child in node.get_children():
		_walk_instance_roots_recursive(child, result)


static func _ext_id(path: String, forced_key: String, ext_map: Dictionary) -> String:
	if not ext_map.has(path):
		var key := forced_key
		if key.is_empty():
			key = path.get_file().get_basename().to_snake_case()
		var base_key := key
		var suffix := 2
		var used: Array = []
		for entry in ext_map.values():
			used.append(entry["key"])
		while used.has(key):
			key = "%s_%d" % [base_key, suffix]
			suffix += 1
		ext_map[path] = {"id": "%d_%s" % [ext_map.size() + 1, key], "key": key}
	return ext_map[path]["id"]


static func _sorted_ext_paths(ext_map: Dictionary) -> Array[String]:
	var paths: Array[String] = []
	for path in ext_map:
		paths.append(path)
	paths.sort_custom(func(a: String, b: String) -> bool:
		return String(ext_map[a]["id"]).get_slice("_", 0).to_int() \
				< String(ext_map[b]["id"]).get_slice("_", 0).to_int())
	return paths


static func _append_node_block(
	lines: Array[String], node: Node, level_root: Node, ext_map: Dictionary, default_node: Node
) -> void:
	var block: Array[String] = []
	if node.scene_file_path != "":
		# 积木实例根
		block.append("[node name=\"%s\" parent=\"%s\" instance=ExtResource(\"%s\")]" % [
			node.name, _relative_path(level_root, node.get_parent()), _ext_id(node.scene_file_path, "", ext_map),
		])
	else:
		# base 内部节点（LevelManager 等）：只有出现覆盖时才输出
		block.append("[node name=\"%s\" parent=\".\" index=\"%d\"]" % [node.name, node.get_index()])
	var overrides := _diff_overrides(node, default_node, level_root, ext_map)
	if node.scene_file_path == "" and overrides.is_empty():
		return
	block.append_array(overrides)
	lines.append_array(block)


static func _diff_overrides(
	node: Node, default_node: Node, level_root: Node, ext_map: Dictionary
) -> Array[String]:
	var result: Array[String] = []
	if default_node == null:
		return result
	for prop in node.get_property_list():
		if not _is_storable(prop):
			continue
		# 编辑器预览时会禁用关卡相机、停摆关卡根节点；这些不是关卡内容，不能写进文件
		if prop.name == "enabled" and node is Camera2D:
			continue
		if prop.name == "process_mode" and node == level_root:
			continue
		var live: Variant = node.get(prop.name)
		var baseline: Variant = default_node.get(prop.name)
		if _values_equal(live, baseline):
			continue
		var text := _format_value(live, level_root, ext_map)
		if text == "":
			continue
		result.append("%s = %s" % [prop.name, text])
	return result


static func _collect_connections(level_root: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in walk_instance_roots(level_root):
		for sig in node.get_signal_list():
			var signal_name: StringName = sig["name"]
			for conn in node.get_signal_connection_list(signal_name):
				var callback: Callable = conn["callable"]
				var target := callback.get_object() as Node
				if target == null or target == node:
					continue
				if target.scene_file_path == "":
					continue  # 目标是基座内部节点（如 LevelManager 接蚕茧），不属于关卡连线
				var method_name := callback.get_method()
				if method_name.is_empty():
					continue
				result.append({
					"from": _relative_path(level_root, node),
					"signal": signal_name,
					"to": _relative_path(level_root, target),
					"method": method_name,
				})
	return result


static func _is_storable(prop: Dictionary) -> bool:
	if prop["name"] == "script":
		return false
	# 传送门的运行时配对引用不落盘：持久化只认 pair_id（读回来才是可靠的）
	if prop["name"] == "linked_portal":
		return false
	var usage: int = prop["usage"]
	if usage & PROPERTY_USAGE_STORAGE == 0:
		return false
	if usage & PROPERTY_USAGE_READ_ONLY != 0:
		return false
	return true


static func _values_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT:
			return absf(a - b) < FLOAT_TOLERANCE
		TYPE_OBJECT:
			if a is PackedScene:
				if b is PackedScene:
					return a.resource_path == b.resource_path
				return false
			return a == b
		_:
			return a == b


static func _format_value(value: Variant, level_root: Node, ext_map: Dictionary) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			return _format_float(value)
		TYPE_STRING:
			return "\"%s\"" % String(value).c_escape()
		TYPE_STRING_NAME:
			# 传送门配对编号等 StringName 属性（Godot 自己写 &"..."）
			return "&\"%s\"" % String(value).c_escape()
		TYPE_VECTOR2:
			return "Vector2(%s, %s)" % [_format_float(value.x), _format_float(value.y)]
		TYPE_RECT2:
			return "Rect2(%s, %s, %s, %s)" % [
				_format_float(value.position.x), _format_float(value.position.y),
				_format_float(value.size.x), _format_float(value.size.y),
			]
		TYPE_COLOR:
			return "Color(%s, %s, %s, %s)" % [
				_format_float(value.r), _format_float(value.g),
				_format_float(value.b), _format_float(value.a),
			]
		TYPE_NODE_PATH:
			return "NodePath(\"%s\")" % String(value).c_escape()
		TYPE_PACKED_STRING_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append("\"%s\"" % String(item).c_escape())
			return "PackedStringArray(%s)" % ", ".join(parts)
		TYPE_PACKED_INT32_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append(str(item))
			return "PackedInt32Array(%s)" % ", ".join(parts)
		TYPE_OBJECT:
			if value is PackedScene:
				if value.resource_path.is_empty():
					return "null"
				return "ExtResource(\"%s\")" % _ext_id(value.resource_path, "next", ext_map)
			if value is Node:
				return "NodePath(\"%s\")" % _relative_path(level_root, value as Node).c_escape()
			return ""
		_:
			return ""


static func _format_float(value: float) -> String:
	# 最多 6 位小数、去掉末尾 0；整数值不带小数点（与 Godot 编辑器写出的 .tscn 风格一致）
	if not is_finite(value):
		return "0"
	var text := String.num(value, 6)
	if text.ends_with(".0"):
		text = text.trim_suffix(".0")
	if text == "" or text == "-":
		text += "0"
	return text


## 名字链相对路径（与 .tscn 里 from="Blocks/Mirror" 同款），不依赖节点进树
static func _relative_path(level_root: Node, node: Node) -> String:
	var parts: Array[String] = []
	var current := node
	while current != null and current != level_root:
		parts.append(current.name)
		current = current.get_parent()
	parts.reverse()
	return "/".join(parts)
