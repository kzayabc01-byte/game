class_name PaletteData
extends RefCounted

## 积木面板静态目录：编辑器从这里的 12 个条目生成面板（中文标签、分类、场景路径）
## 和 Inspector 的属性迷你面板（props 描述每个导出属性怎么编辑）。
## preset 是可选的生成预设：调色板点生成时应用（变色片是折射面的预设）。

const CATEGORY_OPTICS := "光学"
const CATEGORY_SWITCH := "开关"
const CATEGORY_TERRAIN := "地形"
const CATEGORIES: Array[String] = [CATEGORY_OPTICS, CATEGORY_SWITCH, CATEGORY_TERRAIN]

## props 条目：{"name": StringName, "label": String, "kind": StringName,
##             "options": Array[String]（仅 enum），以及可选的 min/max/step/suffix}
static var _entries: Array[Dictionary] = [
	# ---------- 光学 ----------
	{
		"key": "light_source", "label": "光源", "category": CATEGORY_OPTICS,
		"path": "res://blocks/light_source/light_source.tscn", "size": Vector2(64, 64),
		"props": [
			{"name": &"max_bounces", "label": "最大反射次数", "kind": &"int"},
			{"name": &"rotate_step_degrees", "label": "旋转步进(°)", "kind": &"float"},
			{"name": &"fine_step_degrees", "label": "微调步进(°)", "kind": &"float"},
			{"name": &"light_color", "label": "光线颜色", "kind": &"color"},
		],
	},
	{
		"key": "cocoon", "label": "蚕茧", "category": CATEGORY_OPTICS,
		"path": "res://blocks/cocoon/cocoon.tscn", "size": Vector2(44, 44), "props": [],
	},
	{
		"key": "mirror", "label": "镜面", "category": CATEGORY_OPTICS,
		"path": "res://blocks/mirror/mirror.tscn", "size": Vector2(64, 24), "props": [],
	},
	{
		"key": "refract_surface", "label": "折射面", "category": CATEGORY_OPTICS,
		"path": "res://blocks/refract_surface/refract_surface.tscn", "size": Vector2(96, 24),
		"props": [
			{
				"name": &"bend_degrees", "label": "折射偏角", "kind": &"float",
				"min": -180.0, "max": 180.0, "step": 1.0, "suffix": "°",
			},
		],
	},
	{
		"key": "color_changer", "label": "变色片", "category": CATEGORY_OPTICS,
		"path": "res://blocks/refract_surface/refract_surface.tscn", "size": Vector2(96, 24),
		"props": [
			{"name": &"recolor", "label": "改色", "kind": &"bool"},
			{"name": &"output_color", "label": "输出颜色", "kind": &"color"},
			{
				"name": &"bend_degrees", "label": "折射偏角", "kind": &"float",
				"min": -180.0, "max": 180.0, "step": 1.0, "suffix": "°",
			},
			{"name": &"attenuation", "label": "衰减率", "kind": &"float"},
		],
		"preset": {"recolor": true, "output_color": Color(1.0, 0.25, 0.25)},
	},
	{
		"key": "concave_lens", "label": "凹透镜", "category": CATEGORY_OPTICS,
		"path": "res://blocks/concave_lens/concave_lens.tscn", "size": Vector2(24, 96),
		"props": [
			{"name": &"split_count", "label": "分光数", "kind": &"int"},
			{"name": &"fan_degrees", "label": "展开角度(°)", "kind": &"float"},
			{"name": &"energy_falloff", "label": "能量衰减", "kind": &"float"},
			{"name": &"attenuation", "label": "衰减率", "kind": &"float"},
		],
	},
	{
		"key": "portal", "label": "传送门", "category": CATEGORY_OPTICS,
		"path": "res://blocks/portal/portal.tscn", "size": Vector2(24, 96),
		# 传送门永远成对生成：一次点两个，面对面摆好并自动配对
		"spawn_pair": true, "pair_gap": 260.0,
		"props": [
			{"name": &"pair_id", "label": "配对编号", "kind": &"text"},
			{"name": &"one_way", "label": "单向", "kind": &"bool"},
			{"name": &"mirror_out", "label": "镜像出射", "kind": &"bool"},
			{
				"name": &"length", "label": "门面长度", "kind": &"float",
				"min": 16.0, "max": 400.0, "step": 8.0,
			},
			{
				"name": &"thickness", "label": "厚度", "kind": &"float",
				"min": 2.0, "max": 64.0, "step": 2.0,
			},
		],
	},
	{
		"key": "glacier", "label": "冰川", "category": CATEGORY_OPTICS,
		"path": "res://blocks/glacier/glacier.tscn", "size": Vector2(64, 64),
		"props": [
			{"name": &"melt_seconds", "label": "融化时间(秒)", "kind": &"float"},
			{"name": &"melt_efficiency", "label": "融化效率", "kind": &"float"},
		],
	},
	# ---------- 开关 ----------
	{
		"key": "trigger_switch", "label": "触发开关", "category": CATEGORY_SWITCH,
		"path": "res://blocks/trigger_switch/trigger_switch.tscn", "size": Vector2(40, 40),
		"props": [
			{"name": &"latch", "label": "自锁", "kind": &"bool"},
			{"name": &"match_color", "label": "颜色感应", "kind": &"bool"},
			{"name": &"color_filter", "label": "感应颜色", "kind": &"color"},
		],
	},
	{
		"key": "pressure_sensor", "label": "压力传感器", "category": CATEGORY_SWITCH,
		"path": "res://blocks/pressure_sensor/pressure_sensor.tscn", "size": Vector2(56, 56), "props": [],
	},
	# ---------- 地形 ----------
	{
		"key": "wall", "label": "墙体", "category": CATEGORY_TERRAIN,
		"path": "res://blocks/wall/wall.tscn", "size": Vector2(64, 64), "props": [],
	},
	{
		"key": "stone_block", "label": "石块", "category": CATEGORY_TERRAIN,
		"path": "res://blocks/stone_block/stone_block.tscn", "size": Vector2(64, 64), "props": [],
	},
]


static func get_entries() -> Array[Dictionary]:
	return _entries


## 按场景路径查条目（Inspector 判断选中块类型用），找不到返回空字典
static func find_entry(scene_path: String) -> Dictionary:
	for entry in _entries:
		if entry["path"] == scene_path:
			return entry
	return {}


## 同场景多个条目时（变色片=折射面），
## 用积木名（生成时以 key 命名）区分：名字匹配的条目优先。
static func find_entry_for(scene_path: String, node_name: String = "") -> Dictionary:
	var fallback: Dictionary = {}
	for entry in _entries:
		if entry["path"] != scene_path:
			continue
		if fallback.is_empty():
			fallback = entry
		var key: String = entry["key"]
		if not node_name.is_empty() and node_name.begins_with(key.to_pascal_case()):
			return entry
	return fallback


static func entry_label(scene_path: String) -> String:
	var entry := find_entry(scene_path)
	return str(entry.get("label", "")) if not entry.is_empty() else scene_path.get_file().get_basename()


## 积木名义包围盒（选中框 / 拾取判定用），未登记的场景回退 64×64
static func entry_size(scene_path: String) -> Vector2:
	var entry := find_entry(scene_path)
	var size: Vector2 = entry.get("size", Vector2(64, 64))
	return size if size.x > 0.0 and size.y > 0.0 else Vector2(64, 64)


static func entries_in_category(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _entries:
		if entry["category"] == category:
			result.append(entry)
	return result
