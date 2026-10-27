class_name WireService
extends RefCounted

## 编辑器与玩家搭建共用的接线生命周期；调用方额外提供玩家权限限制。

const LINK_SCENE: PackedScene = preload("res://blocks/action_link/action_link.tscn")


static func source_signal(node: Node) -> StringName:
	if not is_instance_valid(node):
		return &""
	if node is TriggerSwitch:
		return &"active_changed"
	if node is PressureSensor:
		return &"pressed_changed"
	return &""


static func is_target(node: Node) -> bool:
	return (
		is_instance_valid(node) and node is Node2D
		and not node is ActionLink and not node is OpaqueWallBlock
		and not node.is_queued_for_deletion()
		and not node.scene_file_path.is_empty()
	)


static func find_target_link(blocks: Node, target: Node2D) -> ActionLink:
	for child in blocks.find_children("*", "", true, false):
		var link: ActionLink = child as ActionLink
		if link == null or link.is_queued_for_deletion():
			continue
		if link.get_node_or_null(link.target_node) == target:
			return link
	return null


static func connection_error(blocks: Node, source: Node2D, target: Node2D) -> String:
	if not is_instance_valid(blocks):
		return "关卡尚未载入。"
	if source_signal(source).is_empty() or source.is_queued_for_deletion():
		return "请选择触发开关或压力传感器。"
	if target is OpaqueWallBlock:
		return "固定遮光墙不能连接电线。"
	if not is_target(target):
		return "请选择有效的目标元件。"
	if source == target:
		return "开关不能连接自己。"
	if not blocks.is_ancestor_of(source) or not blocks.is_ancestor_of(target):
		return "不能跨关卡连接电线。"
	if find_target_link(blocks, target) != null:
		return "该机关已有电线，请先拆除原连接。"
	return ""


static func create_wire(blocks: Node, source: Node2D, target: Node2D) -> ActionLink:
	if not connection_error(blocks, source, target).is_empty():
		return null
	var link: ActionLink = LINK_SCENE.instantiate() as ActionLink
	var wire_name: String = "Wire"
	var suffix: int = 2
	while blocks.has_node(NodePath(wire_name)):
		wire_name = "Wire%d" % suffix
		suffix += 1
	link.name = wire_name
	blocks.add_child(link)
	link.target_node = link.get_path_to(target)
	link.resolve_target()
	if source.connect(source_signal(source), Callable(link, ActionLink.METHOD_NAME)) != OK:
		link.queue_free()
		return null
	return link


static func remove_wire(link: ActionLink) -> void:
	if not is_instance_valid(link) or link.is_queued_for_deletion():
		return
	# 先断信号再复位，避免释放延迟期间再次触发或留下运动中的 Tween。
	for connection in link.get_incoming_connections():
		var wire_signal: Signal = connection["signal"]
		var callback: Callable = connection["callable"]
		if callback.get_method() == ActionLink.METHOD_NAME and wire_signal.is_connected(callback):
			wire_signal.disconnect(callback)
	link.set_editor_preview_active(false)
	link.queue_free()
