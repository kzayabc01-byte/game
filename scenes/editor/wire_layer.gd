class_name WireLayer
extends Node2D

## 电线层（仅编辑器）：把「开关 → 机关」的电线节点（ActionLink）画成曲线，方便确认谁触发谁。
## 电线本身 = 关卡里的 ActionLink 节点（存动作参数 + 一条开关信号连接），
## 这个层只是视觉：不属于关卡子树，游戏里没有它 → 电线永远不出现在正式关卡里。
## 撤销/重做会整体换掉关卡子树 → clear() + rebuild_from_level() 重新内省连接。

const SAMPLE_COUNT := 24
const HIT_DISTANCE := 8.0
const PORT_OFFSET := 26.0

## 电线颜色按信号区分：触发开关橙色 / 压力传感器蓝色
const SIGNAL_COLORS := {
	&"active_changed": Color(1.0, 0.62, 0.2),
	&"pressed_changed": Color(0.25, 0.65, 1.0),
}
const WIRE_COLOR_FALLBACK := Color(0.7, 0.7, 0.75)

## 每条线：{"link": ActionLink, "source": Node, "target": Node2D, "signal": StringName}
var _wires: Array[Dictionary] = []

## 高亮的目标积木（拖线中合法目标提示）
var _highlight: Node2D = null

## 选中信号源时提示其出线端口（编辑器 select 时设置；积木被删/换子树后自动失效）
var _source_hint: Node2D = null

## 拖线中的橡皮线预览
var preview_active := false
var preview_from := Vector2.ZERO
var preview_to := Vector2.ZERO

var selected_index: int = -1:
	set(value):
		selected_index = value
		queue_redraw()


func _process(_delta: float) -> void:
	# 关卡子树被换掉时旧节点已销毁：静默丢弃死线（连接随节点一起没了）
	for i in range(_wires.size() - 1, -1, -1):
		var wire: Dictionary = _wires[i]
		if not is_instance_valid(wire["link"]) or not is_instance_valid(wire["source"]) \
				or not is_instance_valid(wire["target"]):
			_wires.remove_at(i)
			if selected_index == i:
				selected_index = -1
			elif selected_index > i:
				selected_index -= 1
	if not _wires.is_empty() or preview_active or _highlight != null or _source_hint != null:
		queue_redraw()


func _draw() -> void:
	for i in _wires.size():
		_draw_wire(i)
	if preview_active:
		_draw_preview()
	if _highlight != null and is_instance_valid(_highlight):
		draw_arc(_highlight.global_position, 44.0, 0.0, TAU, 40, Color(0.4, 1.0, 0.5, 0.8), 3.0)
	if _source_hint != null and is_instance_valid(_source_hint):
		_draw_source_hint()


## 建立一条电线记录。连接（开关信号 → link._on_signal）由编辑器先 connect 好，这里只建档画线。
func add_wire(link: ActionLink, source: Node, signal_name: StringName) -> bool:
	if link == null or source == null:
		return false
	if not LevelFileIO.is_valid_wire(signal_name, ActionLink.METHOD_NAME):
		return false
	if has_wire(link, source, signal_name):
		return false
	var target := link.get_target()
	if target == null:
		return false
	_wires.append({
		"link": link, "source": source, "target": target, "signal": signal_name,
	})
	queue_redraw()
	return true


## 断开并删除一条线（连同电线节点一起删掉）。index 越界返回 false。
func remove_wire(index: int) -> bool:
	if index < 0 or index >= _wires.size():
		return false
	var wire: Dictionary = _wires[index]
	var link := wire["link"] as ActionLink
	var source := wire["source"] as Node
	if is_instance_valid(source) and source.is_connected(wire["signal"], Callable(link, ActionLink.METHOD_NAME)):
		source.disconnect(wire["signal"], Callable(link, ActionLink.METHOD_NAME))
	if is_instance_valid(link):
		if link.is_editor_preview_active():
			link.set_editor_preview_active(false)
		link.queue_free()
	_wires.remove_at(index)
	if selected_index == index:
		selected_index = -1
	elif selected_index > index:
		selected_index -= 1
	queue_redraw()
	return true


func has_wire(link: ActionLink, source: Node, signal_name: StringName) -> bool:
	return find_wire(link, source, signal_name) >= 0


func find_wire(link: ActionLink, source: Node, signal_name: StringName) -> int:
	for i in _wires.size():
		var wire: Dictionary = _wires[i]
		if wire["link"] == link and wire["source"] == source and wire["signal"] == signal_name:
			return i
	return -1


## 删除所有碰到 node 的电线（删除积木前调用，电线节点一并释放）
func remove_wires_touching(node: Node) -> int:
	var removed := 0
	for i in range(_wires.size() - 1, -1, -1):
		var wire: Dictionary = _wires[i]
		if wire["source"] == node or wire["target"] == node:
			remove_wire(i)
			removed += 1
	return removed


func get_wires() -> Array[Dictionary]:
	return _wires.duplicate()


func get_wire_count() -> int:
	return _wires.size()


## 命中检测：返回距点击点 8px 内的电线下标，没有返回 -1
func hit_test(point: Vector2) -> int:
	for i in _wires.size():
		var wire: Dictionary = _wires[i]
		var source := wire["source"] as Node2D
		var target := wire["target"] as Node2D
		if source == null or target == null:
			continue
		var points := _bezier_points(_port_position(source, true), _port_position(target, false))
		for j in points.size() - 1:
			if _point_to_segment_distance(point, points[j], points[j + 1]) < HIT_DISTANCE:
				return i
	return -1


## 关卡子树换新后重建线记录：遍历电线节点（ActionLink）+ 入向连接。
## 连接已经随关卡文件加载存在，这里只建档，不重复 connect。
func rebuild_from_level(level_root: Node) -> void:
	_wires.clear()
	selected_index = -1
	for node in LevelFileIO.walk_instance_roots(level_root):
		if not node is ActionLink:
			continue
		var link := node as ActionLink
		var source: Node = null
		var signal_name := StringName()
		for conn in node.get_incoming_connections():
			var sig: Signal = conn.get("signal")
			var callback: Callable = conn.get("callable")
			if callback.get_object() != link or callback.get_method() != ActionLink.METHOD_NAME:
				continue
			source = sig.get_object() as Node
			signal_name = sig.get_name()
			break
		if source == null or signal_name == StringName() or not LevelFileIO.is_valid_wire(signal_name, ActionLink.METHOD_NAME):
			# 悬空电线（没有入向连接的孤儿节点）：编辑器里清掉，文件里不写
			link.queue_free()
			continue
		var target := link.get_target()
		if target == null:
			link.queue_free()
			continue
		_wires.append({
			"link": link, "source": source, "target": target, "signal": signal_name,
		})
	queue_redraw()


func clear() -> void:
	_wires.clear()
	selected_index = -1
	queue_redraw()


## 拖线中的橡皮线：active=false 结束预览
func set_preview(active: bool, from: Vector2 = Vector2.ZERO, to: Vector2 = Vector2.ZERO) -> void:
	preview_active = active
	preview_from = from
	preview_to = to
	queue_redraw()


## 拖线中合法目标高亮（null 取消）
func set_highlight_target(node: Node2D) -> void:
	if _highlight == node:
		return
	_highlight = node
	queue_redraw()


## 选中信号源时提示出线端口（null 取消提示）
func set_source_hint(node: Node2D) -> void:
	if _source_hint == node:
		return
	_source_hint = node
	queue_redraw()


# ---------- 内部实现 ----------


## 端口世界坐标（源在右侧 / 目标在左侧，随节点旋转）。编辑器拖线起点也用这个公式。
static func port_position(node: Node2D, is_source: bool) -> Vector2:
	var direction := Vector2.RIGHT if is_source else Vector2.LEFT
	return node.global_position + direction.rotated(node.rotation) * PORT_OFFSET


func _port_position(node: Node2D, is_source: bool) -> Vector2:
	return WireLayer.port_position(node, is_source)


func _bezier_points(from: Vector2, to: Vector2) -> PackedVector2Array:
	# 控制点水平外伸，最短 40px，保证两端口靠很近时曲线也圆润
	var reach := maxf(40.0, absf(to.x - from.x) * 0.5)
	var control_1 := from + Vector2(reach, 0)
	var control_2 := to - Vector2(reach, 0)
	var points := PackedVector2Array()
	for i in SAMPLE_COUNT + 1:
		var t := float(i) / SAMPLE_COUNT
		points.append(from.bezier_interpolate(control_1, control_2, to, t))
	return points


func _draw_wire(index: int) -> void:
	var wire: Dictionary = _wires[index]
	var source := wire["source"] as Node2D
	var target := wire["target"] as Node2D
	if source == null or target == null:
		return
	var from_pos := _port_position(source, true)
	var to_pos := _port_position(target, false)
	var points := _bezier_points(from_pos, to_pos)
	var selected := index == selected_index
	var base_color: Color = SIGNAL_COLORS.get(wire["signal"], WIRE_COLOR_FALLBACK)
	var color := base_color.lightened(0.25) if selected else base_color
	var width := 3.5 if selected else 2.5
	# 深色衬底模拟描边，线在浅色积木上也看得清
	draw_polyline(points, Color(0.05, 0.06, 0.08, 0.55), width + 3.0)
	draw_polyline(points, color, width)
	# 端口圆点：源（右侧）/ 目标（左侧）
	_draw_port(from_pos, base_color, selected)
	_draw_port(to_pos, base_color, selected)
	# 动作参数摘要：贴在曲线中点，编辑时一眼看清这根电线让机关做什么
	var link := wire["link"] as ActionLink
	if link != null:
		_draw_action_summary(link, points[SAMPLE_COUNT / 2])


## 电线中点上的动作摘要（位移/旋转/时长/循环/恢复）
func _draw_action_summary(link: ActionLink, center: Vector2) -> void:
	var parts := PackedStringArray()
	parts.append("移(%d,%d)" % [int(link.move_offset.x), int(link.move_offset.y)])
	if absf(link.rotate_degrees) > 0.01:
		parts.append("转%d°" % int(link.rotate_degrees))
	parts.append("%.1fs" % link.duration)
	if link.repeat:
		parts.append("循环")
	if not link.restore_on_off:
		parts.append("不恢复")
	var text := " ".join(parts)
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var box := Rect2(center - text_size / 2.0 - Vector2(6, 3), text_size + Vector2(12, 6))
	draw_rect(box, Color(0.05, 0.06, 0.08, 0.7))
	draw_rect(box, Color(1, 1, 1, 0.25), false, 1.0)
	draw_string(font, box.position + Vector2(6, 14), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.95, 0.9))


func _draw_port(center: Vector2, color: Color, selected: bool) -> void:
	draw_circle(center, 6.0 if selected else 5.0, color.darkened(0.35))
	draw_circle(center, 3.0, color)


## 选中信号源时的端口提示：呼吸圈 + 说明文字（画在最上层）
func _draw_source_hint() -> void:
	var port := _port_position(_source_hint, true)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	draw_circle(port, 9.0 + pulse * 3.0, Color(1.0, 0.62, 0.2, 0.35))
	draw_circle(port, 5.0, Color(1.0, 0.62, 0.2))
	draw_string(ThemeDB.fallback_font, port + Vector2(14, -16), "拖这里连线",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.5))


func _draw_preview() -> void:
	if preview_from.distance_to(preview_to) < 2.0:
		return
	var points := _bezier_points(preview_from, preview_to)
	var dash := PackedVector2Array()
	for i in range(0, points.size() - 1, 2):
		dash.append(points[i])
		dash.append(points[i + 1])
	draw_multiline(dash, Color(1, 1, 1, 0.7), 2.0)


func _point_to_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(a + segment * t)
