class_name ReplayStorage
extends RefCounted
## Replay file management. Replays live as JSON in user:// and are capped to a
## small ring so a long session cannot fill the disk.

const DIR := "user://replays"
const MAX_FILES := 20

static var selected_path: String = ""


static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)


static func save(data: ReplayData) -> String:
	ensure_dir()
	var mode := _safe(data.mode)
	var stamp := int(Time.get_unix_time_from_system())
	var path := DIR.path_join("replay_%d_%s.json" % [stamp, mode])
	var serial := 1
	while FileAccess.file_exists(path):
		path = DIR.path_join("replay_%d_%s_%d.json" % [stamp, mode, serial])
		serial += 1
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(data.to_dict(), "\t"))
	file.close()
	prune()
	return path


static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	ensure_dir()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.ends_with(".json"):
			var path := DIR.path_join(file)
			var data := load_path(path)
			if data != null:
				out.append({
					"path": path,
					"file": file,
					"mode": data.mode,
					"created": data.created,
					"duration": data.duration,
					"score1": data.score1,
					"score2": data.score2,
					"size": _file_size(path),
					"inputs": data.inputs.size(),
					"snapshots": data.snapshots.size(),
				})
		file = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("created", 0.0)) > float(b.get("created", 0.0))
	)
	return out


static func load_path(path: String) -> ReplayData:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return null
	return ReplayData.from_dict(parsed)


static func delete_path(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


static func prune(limit: int = MAX_FILES) -> void:
	var entries := list()
	if entries.size() <= limit:
		return
	for i in range(limit, entries.size()):
		delete_path(str(entries[i]["path"]))


static func latest_path() -> String:
	var entries := list()
	return str(entries[0]["path"]) if not entries.is_empty() else ""


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var size := f.get_length()
	f.close()
	return size


static func _safe(text: String) -> String:
	var out := ""
	var lower := text.to_lower()
	for i in lower.length():
		var ch := lower[i]
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	if out == "":
		out = "match"
	return out
