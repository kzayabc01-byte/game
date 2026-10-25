class_name ProgressStore
extends RefCounted

## Persistent currency and aim-preview upgrades for published levels.

static var save_path := "user://player_progress.json"
const CLEAR_REWARD := 50
const UPGRADE_COST := 100
const BASE_HINT_LENGTH := 240.0
const HINT_LENGTH_STEP := 120.0
const MAX_HINT_LEVEL := 6


static func get_coins() -> int:
	return maxi(int(_read().get("coins", 0)), 0)


static func get_hint_level() -> int:
	return clampi(int(_read().get("hint_level", 0)), 0, MAX_HINT_LEVEL)


static func get_hint_length() -> float:
	return BASE_HINT_LENGTH + HINT_LENGTH_STEP * float(get_hint_level())


static func award_clear() -> bool:
	var data := _read()
	data["coins"] = maxi(int(data.get("coins", 0)), 0) + CLEAR_REWARD
	return _write(data)


static func buy_hint_upgrade() -> bool:
	var data := _read()
	var coins := maxi(int(data.get("coins", 0)), 0)
	var level := clampi(int(data.get("hint_level", 0)), 0, MAX_HINT_LEVEL)
	if coins < UPGRADE_COST or level >= MAX_HINT_LEVEL:
		return false
	data["coins"] = coins - UPGRADE_COST
	data["hint_level"] = level + 1
	return _write(data)


static func _read() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


static func _write(data: Dictionary) -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	return file.get_error() == OK
