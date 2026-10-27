class_name LevelRunContext
extends RefCounted

## 一次性入口凭证：关卡是否已发布与本次运行是否正式游玩是两件事。

enum Mode {
	AUTHORING,
	PREVIEW,
	OFFICIAL,
}

static var _pending_path: String = ""
static var _pending_mode: Mode = Mode.PREVIEW


static func prepare(path: String, mode: Mode) -> void:
	_pending_path = path
	_pending_mode = mode


static func take(path: String) -> Mode:
	var mode: Mode = _pending_mode if path == _pending_path else Mode.PREVIEW
	clear()
	return mode


static func clear() -> void:
	_pending_path = ""
	_pending_mode = Mode.PREVIEW


static func can_record(mode: Mode, level_id: String, path: String) -> bool:
	return (
		mode == Mode.OFFICIAL
		and ChapterCatalog.is_official_path(level_id, path)
		and ChapterCatalog.is_unlocked(level_id)
	)
