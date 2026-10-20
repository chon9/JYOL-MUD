class_name MapMemory
extends RefCounted
## 大地圖迷霧：每個角色到過的房間，只存在本機資料根目錄（DataRoot）（純外觀，不是權威資料；刪掉只會讓地圖重新變黑）。
## 檔案：<資料根目錄>/map_memory/<char_id>.json，內容 { "visited": [room_id, ...] }。

const DEFAULT_DIR := "user://map_memory"

var dir := DEFAULT_DIR      # 預設跟著 --data-root（DataRoot.path("map_memory")）
var char_id := ""
var visited: Dictionary = {}     # room_id -> true

func _init(p_dir: String = "") -> void:
	dir = p_dir if p_dir != "" else DataRoot.path("map_memory")

## 換角色：載入該角色的紀錄；沒選角（char_id 空）時只記在記憶體。換角前尚未有 char_id 時記下的房間會併入。
func set_char(p_char_id: String) -> void:
	var cid := _safe(p_char_id)
	if cid == char_id:
		return
	var pending := visited if char_id == "" else {}
	char_id = cid
	visited = {}
	if char_id != "":
		_load()
	if not pending.is_empty():
		var changed := false
		for k in pending:
			if not visited.has(k):
				visited[k] = true
				changed = true
		if changed:
			save()

## 記下一個房間；有新增回 true（並寫檔）
func mark(room_id: String) -> bool:
	if room_id == "" or visited.has(room_id):
		return false
	visited[room_id] = true
	save()
	return true

func has(room_id: String) -> bool:
	return visited.has(room_id)

func path() -> String:
	return "%s/%s.json" % [dir, char_id]

func save() -> void:
	if char_id == "":
		return
	var abs_dir := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var ids: Array = visited.keys()
	ids.sort()
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		push_warning("[MapMemory] cannot write %s (%s)" % [path(), error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify({ "visited": ids }))
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(path()):
		return
	var txt := FileAccess.get_file_as_string(path())
	var data: Variant = JSON.parse_string(txt)
	if not (data is Dictionary) or not (data.get("visited") is Array):
		push_warning("[MapMemory] ignoring malformed %s" % path())
		return
	for id in data["visited"]:
		if id is String and id != "":
			visited[id] = true

## char_id 只用英數、底線、減號，避免路徑穿越
static func _safe(s: String) -> String:
	var out := ""
	for ch in s:
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
	return out
