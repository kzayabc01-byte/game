class_name WireLayer
extends Node2D

## 电线层（仅编辑器）：把「触发机关 → 机关」的真实信号连接画成电线，方便确认谁触发谁。
## 线只是视觉层：连接本身存在于关卡节点上，保存时只写 [connection] 条目；
## 这个层不属于关卡子树，游戏里没有它 → 电线永远不出现在正式关卡里。
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

## 每条线：{"source": Node, "target": Node, "signal": StringName,
##          "method": StringName, "callable": Callable}
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
		if not is_instance_valid(wire["source"]) or not is_instance_valid(wire["target"]):
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


## 建立一条电线：校验 WIRE_TABLE 兼容表 → 真实 connect → 建档画线。失败返回 false。
func add_wire(source: Node, target: Node, signal_name: StringName, method_name: StringName) -> bool:
	if not LevelFileIO.is_valid_wire(signal_name, method_name):
		return false
	if has_wire(source, target, signal_name, method_name):
		return false
	if not source.has_signal(signal_name) or not target.has_method(method_name):
		return false
	var callback := Callable(target, method_name)
	if source.connect(signal_name, callback) != OK:
		return false
	_wires.append({
		"source": source, "target": target,
		"signal": signal_name, "method": method_name, "callable": callback,
	})
	queue_redraw()
	return true


## 断开并删除一条线。index 越界返回 false。
func remove_wire(index: int) -> bool:
	if index < 0 or index >= _wires.size():
		return false
	var wire: Dictionary = _wires[index]
	var source := wire["source"] as Node
	if is_instance_valid(source) and source.is_connected(wire["signal"], wire["callable"]):
		source.disconnect(wire["signal"], wire["callable"])
	_wires.remove_at(index)
	if selected_index == index:
		selected_index = -1
	elif selected_index > index:
		selected_index -= 1
	queue_redraw()
	return true


func has_wire(source: Node, target: Node, signal_name: StringName, method_name: StringName) -> bool:
	return find_wire(source, target, signal_name, method_name) >= 0


func find_wire(source: Node, target: Node, signal_name: StringName, method_name: StringName) -> int:
	for i in _wires.size():
		var wire: Dictionary = _wires[i]
		if wire["source"] == source and wire["target"] == target \
				and wire["signal"] == signal_name and wire["method"] == method_name:
			return i
	return -1


## 删除所有碰到 node 的电线（删除积木前调用）
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


## 关卡子树换新后重建线记录：内省全部积木信号连接，按 WIRE_TABLE 过滤。
## 连接已经随关卡文件加载存在，这里只建档，不重复 connect。
func rebuild_from_level(level_root: Node) -> void:
	_wires.clear()
	selected_index = -1
	for node in LevelFileIO.walk_instance_roots(level_root):
		for sig in node.get_signal_list():
			var signal_name: StringName = sig["name"]
			for conn in node.get_signal_connection_list(signal_name):
				var callback: Callable = conn["callable"]
				var target := callback.get_object() as Node
				if target == null or target.scene_file_path == "":
					continue
				var method_name := callback.get_method()
				if method_name.is_empty():
					continue
				if not LevelFileIO.is_valid_wire(signal_name, method_name):
					continue
				_wires.append({
					"source": node, "target": target,
					"signal": signal_name, "method": method_name, "callable": callback,
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
