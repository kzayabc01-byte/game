class_name ChapterCatalog
extends RefCounted

## Official chapters are authored in chapters.cfg; published levels are discovered from res://.

const CONFIG_PATH := "res://chapters.cfg"
const LEVELS_DIR := "res://scenes/levels"


static func get_official_levels() -> Array[Dictionary]:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	var levels: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for file_name in LevelFileIO.scan_levels():
		var path := LEVELS_DIR + "/" + file_name
		var metadata := LevelFileIO.read_level_metadata(path)
		if int(metadata.get(&"publication_state", 0)) != LevelManager.PublicationState.PUBLISHED:
			continue
		var level_id := str(metadata.get(&"level_id", ""))
		if level_id.is_empty() or seen_ids.has(level_id):
			continue
		seen_ids[level_id] = true
		var chapter := maxi(int(metadata.get(&"chapter", 1)), 1)
		var order := maxi(int(metadata.get(&"order_in_chapter", 1)), 1)
		var rank := 1000 + order
		for section in config.get_sections():
			if not section.begins_with("chapter_"):
				continue
			var listed_ids: PackedStringArray = config.get_value(
					section, "level_ids", PackedStringArray())
			var listed_index := listed_ids.find(level_id)
			if listed_index < 0:
				continue
			chapter = maxi(section.trim_prefix("chapter_").to_int(), 1)
			rank = listed_index
			break
		levels.append({
			"path": path,
			"level_id": level_id,
			"title": str(metadata.get(&"level_name", file_name)),
			"chapter": chapter,
			"order": order,
			"rank": rank,
			"difficulty": int(metadata.get(&"difficulty", 1)),
			"mechanic_tags": metadata.get(&"mechanic_tags", PackedStringArray()),
		})
	levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["chapter"] != b["chapter"]:
			return a["chapter"] < b["chapter"]
		if a["rank"] != b["rank"]:
			return a["rank"] < b["rank"]
		return a["path"] < b["path"])
	return levels


static func get_chapter_name(number: int) -> String:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		return str(config.get_value("chapter_%d" % number, "name", "第 %d 章" % number))
	return "第 %d 章" % number


static func find_official(level_id: String) -> Dictionary:
	for level in get_official_levels():
		if level["level_id"] == level_id:
			return level
	return {}


static func is_official_path(level_id: String, path: String) -> bool:
	var level := find_official(level_id)
	return not level.is_empty() and level["path"] == path


static func is_unlocked(level_id: String) -> bool:
	var levels := get_official_levels()
	for index in levels.size():
		if levels[index]["level_id"] == level_id:
			return index == 0 or ProgressStore.is_completed(level_id) or ProgressStore.is_completed(
					levels[index - 1]["level_id"])
	return false


static func next_official(level_id: String) -> Dictionary:
	var levels := get_official_levels()
	for index in levels.size() - 1:
		if levels[index]["level_id"] == level_id:
			return levels[index + 1]
	return {}
