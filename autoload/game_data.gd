extends Node
## 唯讀資料登錄表（TECH_ARCH 4.2 #1、13.5）。

signal activated(enabled_eras: Array)

var loader := DataLoader.new()
var load_ok := false
var load_errors: PackedStringArray = []
var content_hash := ""

var tables: Dictionary = {}          # 生效視圖：table -> {id -> row}（含 "maps"）
var rules: Dictionary = {}           # 展開後的 rule_profile（5.6）
var enabled_eras: Array = []
var activate_errors: PackedStringArray = []

func _ready() -> void:
	reload()

func reload(dir: String = "res://data") -> bool:
	load_ok = loader.load_all(dir)
	load_errors = loader.errors.duplicate()
	content_hash = loader.content_hash
	for e in load_errors:
		push_error("[GameData] " + e)
	var so := default_server_options()
	activate(so.get("enabled_eras", ["1.0A"]), so.get("rule_profile", {}))
	return load_ok

func default_server_options() -> Dictionary:
	return loader.server_options_default.duplicate(true)

## 開世界（主機）或收到 s2c_welcome（客戶端）時呼叫。
## rule_profile 可以是 {preset, overrides}，也可以是已展開的開關字典。
func activate(p_enabled_eras: Array, rule_profile: Dictionary = {}) -> bool:
	var eras: Dictionary = loader.all_tables.get("eras", {})
	activate_errors = DataLoader.validate_enabled_eras(eras, p_enabled_eras)
	if not activate_errors.is_empty():
		for e in activate_errors:
			push_error("[GameData] " + e)
		return false
	enabled_eras = p_enabled_eras.duplicate()
	tables = loader.activate(enabled_eras)
	activate_errors.append_array(loader.activate_errors)
	if rule_profile.has("preset") or rule_profile.has("overrides"):
		rules = DataLoader.expand_rule_profile(loader.all_tables.get("rule_profiles", {}), rule_profile)
	else:
		rules = DataLoader.expand_rule_profile({}, { "overrides": rule_profile })
	activated.emit(enabled_eras)
	return activate_errors.is_empty()

func get_row(table: String, id: String) -> Dictionary:
	return tables.get(table, {}).get(id, {})

func template(key: String) -> Dictionary:
	return get_row("text_templates", key)
