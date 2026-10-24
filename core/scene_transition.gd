extends CanvasLayer

## 场景切换时保留在画面最上层：先渐隐，再换场景，最后渐显。
@export_range(0.05, 2.0, 0.05) var duration: float = 0.35

@onready var _fade: ColorRect = $Fade

var _busy := false


func is_transitioning() -> bool:
	return _busy


func restart_current_scene() -> void:
	var current := get_tree().current_scene
	if current == null or current.scene_file_path.is_empty():
		push_error("无法重玩：当前关卡没有场景文件路径。")
		return
	change_to_file(current.scene_file_path)


func change_to_file(path: String) -> void:
	if _busy:
		return
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("无法加载场景：" + path)
		return
	change_to_packed(scene)


func change_to_packed(scene: PackedScene) -> void:
	if _busy or scene == null:
		return
	_busy = true
	var transparent := _fade.color
	transparent.a = 0.0
	_fade.color = transparent
	_fade.show()

	var fade_out := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_out.tween_property(_fade, "color:a", 1.0, duration)
	await fade_out.finished

	var was_paused := get_tree().paused
	get_tree().paused = false
	var result := get_tree().change_scene_to_packed(scene)
	if result != OK:
		push_error("切换场景失败，错误码：" + str(result))
		get_tree().paused = was_paused
	else:
		await get_tree().process_frame

	var fade_in := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_in.tween_property(_fade, "color:a", 0.0, duration)
	await fade_in.finished
	_fade.hide()
	_busy = false