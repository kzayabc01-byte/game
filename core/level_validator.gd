class_name LevelValidator
extends RefCounted

## 校验设计数据，不进入场景树、不运行机关；草稿允许带问题保存，发布必须通过。


static func validate(level_root: Node) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not is_instance_valid(level_root):
		return errors
	var manager: LevelManager = level_root.get_node_or_null("LevelManager") as LevelManager
	var blocks: Node = level_root.get_node_or_null("Blocks")
	if manager == null:
		errors.append("缺少 LevelManager")
		return errors
	if blocks == null:
		errors.append("缺少 Blocks 元件容器")
		return errors
	if manager.level_name.strip_edges().is_empty():
		errors.append("关卡名称不能为空")
	if manager.chapter < 1 or manager.order_in_chapter < 1:
		errors.append("章节和章节内顺序必须大于 0")
	var has_source: bool = false
	var has_goal: bool = false
	var targets: Dictionary = {}
	for node in blocks.find_children("*", "", true, false):
		has_source = has_source or node is LightSource
		has_goal = has_goal or node is Cocoon
		var link: ActionLink = node as ActionLink
		if link == null or link.is_queued_for_deletion():
			continue
		var target: Node = link.get_node_or_null(link.target_node)
		if not WireService.is_target(target) or not blocks.is_ancestor_of(target):
			errors.append("电线 %s 的目标不存在或不是本关元件" % link.name)
		elif targets.has(target):
			errors.append("元件 %s 被多条电线控制" % target.name)
		else:
			targets[target] = true
		var source_count: int = 0
		for connection in link.get_incoming_connections():
			var wire_signal: Signal = connection["signal"]
			var callback: Callable = connection["callable"]
			if callback.get_method() != ActionLink.METHOD_NAME:
				continue
			var source: Node = wire_signal.get_object() as Node
			if (
				not WireService.source_signal(source).is_empty()
				and wire_signal.get_name() == WireService.source_signal(source)
				and blocks.is_ancestor_of(source) and source != target
			):
				source_count += 1
		if source_count != 1:
			errors.append("电线 %s 必须连接一个有效开关" % link.name)
		if link.move_speed <= 0.0 or link.rotate_speed <= 0.0:
			errors.append("电线 %s 的运动速度必须大于 0" % link.name)
	if not has_source:
		errors.append("至少需要一个预置光源")
	if not has_goal:
		errors.append("至少需要一个通关目标")
	errors.append_array(validate_build(manager, blocks))
	return errors


static func validate_build(manager: LevelManager, blocks: Node) -> PackedStringArray:
	var errors: PackedStringArray = []
	if manager.level_kind != LevelManager.LevelKind.BUILD:
		return errors
	if manager.build_bounds.size.x <= 0.0 or manager.build_bounds.size.y <= 0.0:
		errors.append("搭建区域宽度和高度必须大于 0")
	if manager.build_wire_limit < 0:
		errors.append("玩家电线数量不能为负数")
	if manager.build_item_keys.size() != manager.build_item_counts.size():
		errors.append("可用元件种类与数量不匹配")
	var entries: Dictionary = {}
	for entry in PaletteData.get_entries():
		entries[str(entry["key"])] = entry
	var seen: Dictionary = {}
	var supplied_sources: int = 0
	var supplied_targets: int = 0
	for index in manager.build_item_keys.size():
		var key: String = manager.build_item_keys[index]
		if not entries.has(key):
			errors.append("未知的搭建元件：%s" % key)
			continue
		if seen.has(key):
			errors.append("搭建库存重复配置：%s" % key)
		seen[key] = true
		if index >= manager.build_item_counts.size():
			continue
		var count: int = manager.build_item_counts[index]
		if count <= 0:
			errors.append("元件 %s 的库存必须大于 0（不用请移除）" % key)
			continue
		if bool((entries[key] as Dictionary).get("wire_target", true)):
			supplied_targets += count
		if key in ["trigger_switch", "pressure_sensor"]:
			supplied_sources += count
	var sources: Array[Node] = []
	var targets: Array[Node] = []
	for path in manager.build_wire_sources:
		var node: Node = _resolve_block(blocks, path)
		if WireService.source_signal(node).is_empty():
			errors.append("允许出线的预置开关无效：%s" % path)
		elif not sources.has(node):
			sources.append(node)
	for path in manager.build_wire_targets:
		var node: Node = _resolve_block(blocks, path)
		if not WireService.is_target(node):
			errors.append("允许接线的预置目标无效：%s" % path)
		elif WireService.find_target_link(blocks, node as Node2D) != null:
			errors.append("允许玩家接线的 %s 已被预置电线占用" % path)
		elif not targets.has(node):
			targets.append(node)
	for path in manager.build_aimable_sources:
		if not _resolve_block(blocks, path) is LightSource:
			errors.append("允许瞄准的光源无效：%s" % path)
	if manager.build_wire_limit > 0:
		if sources.is_empty() and supplied_sources == 0:
			errors.append("已提供电线，但没有可用开关：开放预置开关出线，或提供开关库存")
		if targets.is_empty() and supplied_targets == 0:
			errors.append("已提供电线，但没有可用目标：开放预置元件接线，或提供元件库存")
		if supplied_sources == 0 and supplied_targets == 0 and sources.size() == 1 and targets.size() == 1 and sources[0] == targets[0]:
			errors.append("唯一开关与目标是同一个元件，不能自连接")
	return errors


static func _resolve_block(blocks: Node, path: String) -> Node:
	if path.is_empty() or path.begins_with("/") or path.contains(":"):
		return null
	var node: Node = blocks.get_node_or_null(NodePath(path))
	return node if is_instance_valid(node) and blocks.is_ancestor_of(node) else null
