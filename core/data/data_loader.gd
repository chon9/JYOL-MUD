class_name DataLoader
extends RefCounted
## 載入 res://data/*.json（TECH_ARCH 5、13.5）。不依賴任何 Autoload，可在 --script 模式使用。

const FILES := ["eras", "rule_profiles", "attributes", "basic_skills", "sects", "sect_rules",
	"martial_arts", "masters", "regions", "npcs", "monsters", "items", "quests", "status_effects",
	"text_templates", "life_skills",
	# STORY_PLAN §8.1：WP-MERGE 從碎片建立的四個新表（都要有 era）
	"rumors", "wanderers", "ambient", "reactions",
	# M3B_PLAN §4.2、§4.7：WP-MERGE 從碎片建立的兩個新表（都要有 era）
	"sect_ranks", "escort_routes",
	# M3C_PLAN §9.4：WP-LOOT 的掉落表（檔案不存在時是空表）
	"loot_tables"]
## 選填的表：檔案不存在時是空表、不算錯誤（舊資料夾、測試用的小資料夾）
const OPTIONAL_FILES := ["rumors", "wanderers", "ambient", "reactions", "sect_ranks", "escort_routes", "loot_tables"]
## M3B_PLAN §4.4：房間的 desc_1_0b 在這個 era 生效時取代 desc
const DESC_ERA_FIELDS := { "1.0B": "desc_1_0b" }
const NO_ERA_TABLES := ["eras", "rule_profiles"]
const SERVER_OPTIONS_FILE := "server_options.default.json"

var all_tables: Dictionary = {}      # table -> {id -> row}，全部 era（5.5.4）
var all_maps: Dictionary = {}        # region_id -> map dict，全部 era
var patches: Dictionary = {}         # era_id -> Array[row]
var server_options_default: Dictionary = {}
var errors: PackedStringArray = []
var activate_errors: PackedStringArray = []
var content_hash := ""
var file_count := 0

## 載入全部 era 的資料；篩選交給 activate()
func load_all(dir: String = "res://data") -> bool:
	errors.clear()
	all_tables.clear()
	all_maps.clear()
	patches.clear()
	file_count = 0
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)

	for table_name in FILES:
		if table_name in OPTIONAL_FILES and not FileAccess.file_exists("%s/%s.json" % [dir, table_name]):
			all_tables[table_name] = {}
			continue
		var parsed: Variant = _read_json("%s/%s.json" % [dir, table_name], hasher)
		if parsed == null:
			all_tables[table_name] = {}
			continue
		all_tables[table_name] = _index_rows(table_name, parsed, "%s.json" % table_name)

	for f in _sorted_json_files(dir + "/maps"):
		var m: Variant = _read_json("%s/maps/%s" % [dir, f], hasher)
		if m == null:
			continue
		if not (m is Dictionary):
			errors.append("maps/%s: not an object" % f)
			continue
		DataSchema.coerce("maps", m)
		var rid: String = m.get("region_id", "")
		if rid == "" or all_maps.has(rid):
			errors.append("maps/%s: empty or duplicate region_id '%s'" % [f, rid])
			continue
		if not m.has("era"):
			errors.append("maps/%s: missing era" % f)
			continue
		all_maps[rid] = m

	for f in _sorted_json_files(dir + "/patches"):
		var p: Variant = _read_json("%s/patches/%s" % [dir, f], hasher)
		if p == null:
			continue
		var era_id: String = p.get("era", "") if p is Dictionary else ""
		if era_id == "":
			errors.append("patches/%s: missing era" % f)
			continue
		var prows: Variant = p.get("rows", [])
		if prows is Array:
			for pr in prows:
				# merge 的欄位照目標表的整數欄位轉型（例如 travel[].price）
				if pr is Dictionary and pr.get("set") is Dictionary:
					DataSchema.coerce(str(pr.get("target_table", "")), pr["set"])
		patches[era_id] = prows if prows is Array else []

	var so: Variant = _read_json("%s/%s" % [dir, SERVER_OPTIONS_FILE], hasher)
	if so is Dictionary:
		DataSchema.coerce("server_options", so)
		server_options_default = so

	content_hash = "sha256:" + hasher.finish().hex_encode()
	return errors.is_empty()

func _read_json(path: String, hasher: HashingContext) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("missing: " + path)
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("empty: " + path)
		return null
	# 換行統一成 LF 再算雜湊，避免 git autocrlf 讓兩台電腦的 content_hash 不同
	text = text.replace("\r\n", "\n")
	hasher.update(path.get_file().to_utf8_buffer())
	hasher.update(text.to_utf8_buffer())
	file_count += 1
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data

func _index_rows(table_name: String, parsed: Variant, label: String) -> Dictionary:
	var by_id := {}
	if not (parsed is Dictionary) or not (parsed.get("rows") is Array):
		errors.append("%s: expected { table, version, rows: [] }" % label)
		return by_id
	if parsed.get("table", "") != table_name:
		errors.append("%s: table field '%s' != '%s'" % [label, parsed.get("table", ""), table_name])
	for row in parsed["rows"]:
		if not (row is Dictionary):
			errors.append("%s: row is not an object" % label)
			continue
		DataSchema.coerce(table_name, row)
		var id: Variant = row.get("id", "")
		if typeof(id) != TYPE_STRING or id == "" or by_id.has(id):
			errors.append("%s: empty or duplicate id '%s'" % [table_name, str(id)])
			continue
		if not (table_name in NO_ERA_TABLES) and not row.has("era"):
			errors.append("%s.%s: missing era" % [table_name, id])
			continue
		by_id[id] = row
	return by_id

static func _sorted_json_files(dir: String) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		# 匯出版中檔名可能帶 .remap／.import
		var name := f.trim_suffix(".remap").trim_suffix(".import")
		if name.ends_with(".json") and not (name in out):
			out.append(name)
	out.sort()
	return out

## 依世界的 enabled_eras 產生生效視圖（5.5.2、5.5.3）；主機與客戶端呼叫同一個函式
func activate(enabled_eras: Array) -> Dictionary:
	activate_errors.clear()
	var on := {}
	for e in enabled_eras:
		on[e] = true
	var view := {}
	for table_name in all_tables:
		var by_id := {}
		for id in all_tables[table_name]:
			var row: Dictionary = all_tables[table_name][id]
			if table_name in NO_ERA_TABLES or row_active(row, on):
				by_id[id] = row.duplicate(true)   # 複製，patch 不會改到原始資料
		view[table_name] = by_id
	var maps := {}
	for rid in all_maps:
		if row_active(all_maps[rid], on):
			maps[rid] = all_maps[rid].duplicate(true)
			_filter_exits(maps[rid], on)
			apply_era_desc(maps[rid], on)
	view["maps"] = maps
	activate_errors.append_array(PatchApplier.apply(view, all_tables.get("eras", {}), on, patches))
	normalize_quests(view)
	activate_errors.append_array(DataSchema.check_references(view))
	return view

## STORY_PLAN §4.12：生效視圖裡的任務列一律正規化成第 2 版（舊 steps → stages），引擎只處理新格式
static func normalize_quests(view: Dictionary) -> void:
	var q: Variant = view.get("quests", {})
	if not (q is Dictionary):
		return
	for id in q:
		if q[id] is Dictionary:
			q[id] = QuestDef.normalize(q[id])

## 出口層級的 era（WORLD_2001 §6.2）：出口可帶 era／era_until；沒帶 era 的出口一律保留
static func exit_active(ex: Dictionary, on: Dictionary) -> bool:
	var era := str(ex.get("era", ""))
	if era != "" and not on.has(era):
		return false
	var until := str(ex.get("era_until", ""))
	return until == "" or not on.has(until)

static func _filter_exits(m: Dictionary, on: Dictionary) -> void:
	var rooms: Variant = m.get("rooms", [])
	if not (rooms is Array):
		return
	for room in rooms:
		if not (room is Dictionary) or not (room.get("exits") is Array):
			continue
		var kept: Array = []
		for ex in room["exits"]:
			if not (ex is Dictionary) or exit_active(ex, on):
				kept.append(ex)
		room["exits"] = kept

## M3B_PLAN §4.4：1.0A 房間提到 1.0B 出口的描述（desc_1_0b）只在 1.0B 生效時換上；1.0A 世界照舊用 desc
static func apply_era_desc(m: Dictionary, on: Dictionary) -> void:
	var rooms: Variant = m.get("rooms", [])
	if not (rooms is Array):
		return
	for room in rooms:
		if not (room is Dictionary):
			continue
		for era in DESC_ERA_FIELDS:
			var f: String = DESC_ERA_FIELDS[era]
			if on.has(era) and str(room.get(f, "")) != "":
				room["desc"] = str(room[f])

static func row_active(row: Dictionary, on: Dictionary) -> bool:
	if not on.has(row.get("era", "")):
		return false
	var until: String = row.get("era_until", "")
	return until == "" or not on.has(until)

## enabled_eras 的合法性：含 base era、對 requires 封閉、id 都存在（5.5.2）
static func validate_enabled_eras(eras: Dictionary, enabled: Array) -> PackedStringArray:
	var errs := PackedStringArray()
	for e in enabled:
		if not eras.has(e):
			errs.append("unknown era '%s'" % str(e))
	for id in eras:
		if eras[id].get("base", false) and not (id in enabled):
			errs.append("base era '%s' must be enabled" % id)
	for e in enabled:
		if not eras.has(e):
			continue
		for req in eras[e].get("requires", []):
			if not (req in enabled):
				errs.append("era '%s' requires '%s'" % [e, req])
	return errs

## 某個 era 加上它的 requires 閉包（data_lint 用）
static func era_closure(eras: Dictionary, era_id: String) -> Array:
	var out: Array = []
	var stack: Array = [era_id]
	while not stack.is_empty():
		var e: String = stack.pop_back()
		if e in out or not eras.has(e):
			continue
		out.append(e)
		stack.append_array(eras[e].get("requires", []))
	for id in eras:
		if eras[id].get("base", false) and not (id in out):
			out.append(id)
	return out

## 展開 rule_profile：預設值 → 預設組合 rules → overrides（5.6）
static func expand_rule_profile(profiles: Dictionary, cfg: Dictionary) -> Dictionary:
	var rules: Dictionary = DataSchema.RULE_DEFAULTS.duplicate(true)
	var preset: String = cfg.get("preset", "")
	if profiles.has(preset):
		rules.merge(profiles[preset].get("rules", {}), true)
	rules.merge(cfg.get("overrides", {}), true)
	if typeof(rules["xuedian_cap"]) == TYPE_FLOAT:
		rules["xuedian_cap"] = int(rules["xuedian_cap"])
	return rules
