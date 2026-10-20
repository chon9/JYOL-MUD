class_name UiSettings
extends RefCounted
## 介面設定（settings.json 的 ui.*、hotbar.*；AUTHENTIC_UI_SPEC §6.2、§8.6、§10、§12.2）。
## 讀寫都合併整個 settings.json（BgmPlayer 也寫同一個檔的 music_*），所以只改自己的鍵。
## 測試可以設 path_override 指到暫存檔，或設 memory_only = true 完全不碰磁碟。

const DEFAULT_PATH := "user://settings.json"
const DEFAULTS := {
	"ui.atb_list": false,             # 戰鬥右側時間棒清單（原作沒有；輔助功能，預設關）
	"ui.damage_text": true,           # 損血顯示（單位腰部 cur/max）
	"ui.minimap": true,               # 小地圖（可完全關掉，給想要「純原作」的玩家）
	"ui.minimap_collapsed": false,
	"ui.chat_overlay": true,          # 螢幕對話開關
	"ui.grid_lines": true,            # 戰場淡格線
	"ui.battle_auto_return": true,    # 戰鬥結束自動返回
	"ui.scale": 1.0,                  # 介面縮放 0.9／1.0／1.15
	"ui.lanterns_collapsed": false,
	"ui.show_names": true,            # 顯示名稱（系統開關；M2_PLAN D5：純客戶端設定）
	"ui.talk_channel": "輕聲細語",     # 上次選的發話頻道（AUTHENTIC_UI_SPEC §9.2：預設輕聲細語）
	"ui.pk_key": "ctrl",
	"nav.auto_resume": true,          # 趕路遇敵獲勝後繼續趕路（M3C_PLAN §4.4；預設開）              # 強制 PK 的連結鍵 ctrl／alt／shift（M2_PLAN 5.2：2001 年叫「連結鍵」，可改鍵）
}

static var path_override := ""
static var memory_only := false
static var _cache: Dictionary = {}
static var _loaded := false

static func _path() -> String:
	if path_override != "":
		return path_override
	return DataRoot.path("settings.json")

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_cache = {}
	if memory_only:
		return
	var p := _path()
	if FileAccess.file_exists(p):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			_cache = d

## 重新從磁碟讀（測試或別的模組改過檔案後）
static func reload() -> void:
	_loaded = false
	_load()

static func reset_for_tests(mem_only: bool = true) -> void:
	memory_only = mem_only
	path_override = ""
	_cache = {}
	_loaded = mem_only

## key 用點號分層（"ui.atb_list"、"hotbar.ch_1"）
static func get_value(key: String, fallback: Variant = null) -> Variant:
	_load()
	var node: Variant = _cache
	for part in key.split("."):
		if not (node is Dictionary) or not (node as Dictionary).has(part):
			return DEFAULTS.get(key, fallback) if fallback == null else fallback
		node = node[part]
	return node

static func get_bool(key: String) -> bool:
	return bool(get_value(key, DEFAULTS.get(key, false)))

static func set_value(key: String, value: Variant) -> void:
	_load()
	var parts := key.split(".")
	var node: Dictionary = _cache
	for i in parts.size() - 1:
		var p := parts[i]
		if not (node.get(p) is Dictionary):
			node[p] = {}
		node = node[p]
	node[parts[parts.size() - 1]] = value
	_save()

static func _save() -> void:
	if memory_only:
		return
	# 先合併磁碟上別人（BgmPlayer）寫的鍵，再整個寫回
	var p := _path()
	var disk: Dictionary = {}
	if FileAccess.file_exists(p):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			disk = d
	for k in _cache:
		disk[k] = _cache[k]
	_cache = disk
	var dir := p.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(disk, "  "))
