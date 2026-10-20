extends Node
## 本機存檔（資料根目錄見 core/util/data_root.gd；TECH_ARCH 8.1、8.3、13.6）：原子寫入 + 5 份輪替備份、載入失敗自動退回備份。
## 不依賴其他 Autoload，單元測試可以直接 new() 並改 root_dir。

const BAK_COUNT := 5
const WORLD_SCHEMA_VERSION := 1
const CHARACTER_SCHEMA_VERSION := 1

var root_dir := "user://"
var profile := "default"
var last_error := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root_dir = DataRoot.root()   # --data-root ＞ data_root.txt ＞ user://；bot 沒指定時用測試根目錄（不碰玩家的存檔）
	print("[SaveManager] data root: %s" % ProjectSettings.globalize_path(root_dir))
	var args := CliArgs.current()
	if args.get("profile") is String and args["profile"] != "":
		profile = _safe_name(args["profile"])

# ---------- 路徑（8.1） ----------
func _p(rel: String) -> String:
	return root_dir.path_join(rel)

func settings_path() -> String:
	return _p("settings.json")

func identity_path() -> String:
	return _p("profiles/%s/identity.json" % profile)

func world_dir(world_id: String) -> String:
	return _p("worlds/%s" % _safe_name(world_id))

func world_path(world_id: String) -> String:
	return world_dir(world_id).path_join("world.json")

func options_path(world_id: String) -> String:
	return world_dir(world_id).path_join("options.json")

func character_path(world_id: String, identity: String, char_id: String) -> String:
	return world_dir(world_id).path_join("characters/%s/%s.json" % [_safe_name(identity), _safe_name(char_id)])

func characters_dir(world_id: String, identity: String) -> String:
	return world_dir(world_id).path_join("characters/%s" % _safe_name(identity))

func passport_path(world_id: String, char_id: String) -> String:
	return _p("passports/%s/%s.json" % [_safe_name(world_id), _safe_name(char_id)])

## 路徑的一段：validate_filename 不擋「.」「..」，開頭的點一律換成「_」，免得 "../settings" 之類跳出資料夾
## （M2 第三輪審查：主機送來的護照 world_id／char_id 能讓客戶端覆寫 settings.json）
static func _safe_name(s: String) -> String:
	var out := s.strip_edges().validate_filename().replace(" ", "_")
	var dots := 0
	while dots < out.length() and out[dots] == ".":
		dots += 1
	if dots > 0:
		out = "_".repeat(dots) + out.substr(dots)
	return out if out != "" else "_"

# ---------- 原子寫入（8.3） ----------
## 寫 X.tmp → 舊備份往後推（保留 5 份）→ X 改名成 X.bak1 → X.tmp 改名成 X。
## Windows 上 rename 不保證覆寫既有檔（17 #16），所以目的地一律先刪除。
func write_json_atomic(path: String, data: Variant) -> Error:
	last_error = ""
	var abs_path := ProjectSettings.globalize_path(path)
	var err := DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	if err != OK:
		return _err(err, "mkdir failed: " + abs_path.get_base_dir())
	var tmp := abs_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _err(FileAccess.get_open_error(), "open tmp failed: " + tmp)
	f.store_string(JSON.stringify(data, "\t"))
	f.flush()
	var write_err := f.get_error()
	f.close()
	if write_err != OK:
		DirAccess.remove_absolute(tmp)
		return _err(write_err, "write tmp failed: " + tmp)

	var oldest := "%s.bak%d" % [abs_path, BAK_COUNT]
	if FileAccess.file_exists(oldest):
		DirAccess.remove_absolute(oldest)
	for i in range(BAK_COUNT - 1, 0, -1):
		var src := "%s.bak%d" % [abs_path, i]
		if FileAccess.file_exists(src):
			err = DirAccess.rename_absolute(src, "%s.bak%d" % [abs_path, i + 1])
			if err != OK:
				return _err(err, "rotate %s failed" % src)
	if FileAccess.file_exists(abs_path):
		err = DirAccess.rename_absolute(abs_path, abs_path + ".bak1")
		if err != OK:
			return _err(err, "backup current failed")
	err = DirAccess.rename_absolute(tmp, abs_path)
	if err != OK:
		# 盡量還原：把 bak1 改回本體
		if FileAccess.file_exists(abs_path + ".bak1") and not FileAccess.file_exists(abs_path):
			DirAccess.rename_absolute(abs_path + ".bak1", abs_path)
		return _err(err, "commit tmp failed")
	return OK

func _err(err: Error, msg: String) -> Error:
	last_error = "%s (%s)" % [msg, error_string(err)]
	push_warning("[SaveManager] " + last_error)
	return err if err != OK else FAILED

## 讀取 JSON；本體壞掉時依序嘗試 bak1 → bak5（8.3）。
## 回傳 { ok, data, source }，source 是實際讀到的檔案路徑。
func read_json_with_fallback(path: String, validator: Callable = Callable()) -> Dictionary:
	var abs_path := ProjectSettings.globalize_path(path)
	var candidates: Array = [abs_path]
	for i in range(1, BAK_COUNT + 1):
		candidates.append("%s.bak%d" % [abs_path, i])
	for c in candidates:
		if not FileAccess.file_exists(c):
			continue
		var text := FileAccess.get_file_as_string(c)
		var json := JSON.new()
		if text.is_empty() or json.parse(text) != OK:
			push_warning("[SaveManager] unreadable: " + c)
			continue
		if validator.is_valid() and not bool(validator.call(json.data)):
			push_warning("[SaveManager] rejected by validator: " + c)
			continue
		if c != abs_path:
			push_warning("[SaveManager] using backup: " + c)
		return { "ok": true, "data": json.data, "source": c }
	return { "ok": false, "data": null, "source": "" }

func read_json(path: String) -> Variant:
	var r := read_json_with_fallback(path)
	return r["data"]

# ---------- 世界存檔（8.2，M0 stub） ----------
func world_exists(world_id: String) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(world_path(world_id)))

## 本體或任何一份備份存在（用來區分「沒有這個世界」與「存檔全部讀不了」）
func world_files_exist(world_id: String) -> bool:
	var abs_path := ProjectSettings.globalize_path(world_path(world_id))
	if FileAccess.file_exists(abs_path):
		return true
	for i in range(1, BAK_COUNT + 1):
		if FileAccess.file_exists("%s.bak%d" % [abs_path, i]):
			return true
	return false

func save_world(world: Dictionary) -> Error:
	return write_json_atomic(world_path(world.get("world_id", "")), world)

## 回傳 { ok, data, source }；schema_version 不認得的檔案視同損壞，改讀備份
func load_world(world_id: String) -> Dictionary:
	var r := read_json_with_fallback(world_path(world_id), _is_valid_world)
	if r["ok"]:
		r["data"] = _coerce_world(r["data"])
	return r

static func _is_valid_world(d: Variant) -> bool:
	return d is Dictionary and int(d.get("schema_version", -1)) == WORLD_SCHEMA_VERSION

static func _coerce_world(d: Dictionary) -> Dictionary:
	d["schema_version"] = int(d.get("schema_version", 0))
	d["lineage"] = int(d.get("lineage", 0))
	d["world_time_s"] = float(d.get("world_time_s", 0.0))
	# M1 新增欄位（M1_PLAN 3.10.2）：舊檔載入時補齊
	if not (d.get("char_names") is Dictionary):
		d["char_names"] = {}
	if not (d.get("corpses") is Array):
		d["corpses"] = []
	d["clock_last_night"] = bool(d.get("clock_last_night", false))
	d["id_counter"] = int(d.get("id_counter", 0))
	# M2 新增欄位（M2_PLAN 4.8）：schema_version 不升，舊檔載入時補預設值、數字轉回 int／float
	if not (d.get("mail") is Array):
		d["mail"] = []
	var mails: Array = []
	for m in d["mail"]:
		if m is Dictionary:
			m["sent_s"] = float(m.get("sent_s", 0.0))
			m["read"] = m.get("read", false) == true
			mails.append(m)
	d["mail"] = mails
	if not (d.get("known_identities") is Dictionary):
		d["known_identities"] = {}
	for ident in d["known_identities"]:
		var e: Variant = d["known_identities"][ident]
		if e is Dictionary:
			e["banned"] = e.get("banned", false) == true
	for c in d["corpses"]:
		if c is Dictionary:
			if not (c.get("authorized") is Array):
				c["authorized"] = []
			c["public_notified"] = c.get("public_notified", false) == true
			if c.has("created_s"):
				c["created_s"] = float(c["created_s"])
	return d

func new_world(world_id: String, world_name: String, content_hash: String, options: Dictionary) -> Dictionary:
	var secret := Crypto.new().generate_random_bytes(32).hex_encode()
	return {
		"schema_version": WORLD_SCHEMA_VERSION,
		"world_id": world_id,
		"world_name": world_name,
		"world_secret": secret,
		"content_hash": content_hash,
		"game_version": Protocol.GAME_VERSION,
		"world_time_s": 0.0,
		"enabled_eras": options.get("enabled_eras", ["1.0A"]),
		"rule_profile": options.get("rule_profile", { "preset": "classic_standard", "overrides": {} }),
		"rng_state": "",
		"regions": {},
		"corpses": [],
		"mail": [],
		"guilds": [],
		"bounties": [],
		"flags": {},
		"known_identities": {},
		"backup_host": "",
		"lineage": 0,
		"char_names": {},
		"clock_last_night": false,
		"id_counter": 0,
	}

# ---------- 角色檔（M1_PLAN 3.5.6、3.10.1） ----------
func save_character(world_id: String, identity: String, data: Dictionary) -> Error:
	var char_id := str(data.get("id", ""))
	if char_id == "":
		return _err(ERR_INVALID_PARAMETER, "character without id")
	return write_json_atomic(character_path(world_id, identity, char_id), data)

## 回傳 { ok, data, source }；本體壞掉或 schema_version 不是 1 時退回備份
func load_character(world_id: String, identity: String, char_id: String) -> Dictionary:
	return read_json_with_fallback(character_path(world_id, identity, char_id), _is_valid_character)

static func _is_valid_character(d: Variant) -> bool:
	if not (d is Dictionary):
		return false
	if not (typeof(d.get("schema_version")) in [TYPE_INT, TYPE_FLOAT]):
		return false
	return int(d["schema_version"]) == CHARACTER_SCHEMA_VERSION and str(d.get("id", "")) != ""

## 依檔名列出角色 id（不含 deleted/、.bak*、.tmp）；本體不見但備份還在的也列出
func list_character_ids(world_id: String, identity: String) -> Array:
	var out: Array = []
	var dir := ProjectSettings.globalize_path(characters_dir(world_id, identity))
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		var base := f
		var bak := base.rfind(".json.bak")
		if bak != -1:
			base = base.substr(0, bak + 5)
		if not base.ends_with(".json"):
			continue
		var id := base.trim_suffix(".json")
		if id != "" and not (id in out):
			out.append(id)
	out.sort()
	return out

## 不真的刪：本體與 .bak* 移到 characters/<identity>/deleted/<char_id>_<unix>.json
func delete_character(world_id: String, identity: String, char_id: String) -> Error:
	var src := ProjectSettings.globalize_path(character_path(world_id, identity, char_id))
	var dir := src.get_base_dir()
	var del_dir := dir.path_join("deleted")
	var err := DirAccess.make_dir_recursive_absolute(del_dir)
	if err != OK:
		return _err(err, "mkdir failed: " + del_dir)
	var stamp := int(Time.get_unix_time_from_system())
	var dst_base := del_dir.path_join("%s_%d.json" % [_safe_name(char_id), stamp])
	var moved := 0
	var suffixes: Array = [""]
	for i in range(1, BAK_COUNT + 1):
		suffixes.append(".bak%d" % i)
	suffixes.append(".tmp")
	for suf in suffixes:
		var p: String = src + suf
		if not FileAccess.file_exists(p):
			continue
		var dst: String = dst_base + suf
		if FileAccess.file_exists(dst):
			DirAccess.remove_absolute(dst)
		err = DirAccess.rename_absolute(p, dst)
		if err != OK:
			return _err(err, "move to deleted failed: " + p)
		moved += 1
	if moved == 0:
		return _err(ERR_FILE_NOT_FOUND, "no such character: " + char_id)
	return OK

## 這個角色在 deleted/ 裡所有封存檔（含 .bakN）中最大的 online_s；沒有封存回 -1.0。
## 護照還原用來擋「刪角後用舊護照還原」（洗 PK、複製物品；M2 審查）。
func deleted_character_online_s(world_id: String, identity: String, char_id: String) -> float:
	var del_dir := ProjectSettings.globalize_path(characters_dir(world_id, identity)).path_join("deleted")
	if not DirAccess.dir_exists_absolute(del_dir):
		return -1.0
	var prefix := _safe_name(char_id) + "_"
	var best := -1.0
	for f in DirAccess.get_files_at(del_dir):
		if not f.begins_with(prefix) or f.ends_with(".tmp"):
			continue
		var rest := f.substr(prefix.length())
		var dot := rest.find(".json")
		if dot <= 0 or not rest.substr(0, dot).is_valid_int():
			continue
		var txt := FileAccess.get_file_as_string(del_dir.path_join(f))
		var d: Variant = JSON.parse_string(txt) if txt != "" else null
		if d is Dictionary and str(d.get("id", "")) == char_id:
			best = maxf(best, float(d.get("online_s", 0.0)))
	return best

# ---------- 角色護照（M2_PLAN 4.6.8、4.6.9；客戶端 <資料根目錄>/passports/<world_id>/<char_id>.json） ----------
func save_passport(world_id: String, char_id: String, passport: Dictionary) -> Error:
	if world_id == "" or char_id == "":
		return _err(ERR_INVALID_PARAMETER, "passport without world_id/char_id")
	return write_json_atomic(passport_path(world_id, char_id), passport)

## { ok, data }；本體壞掉時退回備份
func load_passport(world_id: String, char_id: String) -> Dictionary:
	var r := read_json_with_fallback(passport_path(world_id, char_id),
		func(d: Variant) -> bool: return d is Dictionary)
	return { "ok": bool(r["ok"]), "data": r["data"] if r["ok"] else {} }

## 該世界有護照的 char_id 清單（排序；不含 .bak*、.tmp）
func list_passports(world_id: String) -> Array:
	var out: Array = []
	var dir := ProjectSettings.globalize_path(passport_path(world_id, "x").get_base_dir())
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			var id := f.trim_suffix(".json")
			if id != "" and not (id in out):
				out.append(id)
	out.sort()
	return out

func save_options(world_id: String, options: Dictionary) -> Error:
	return write_json_atomic(options_path(world_id), options)

func load_options(world_id: String) -> Dictionary:
	var d: Variant = read_json(options_path(world_id))
	if d is Dictionary:
		DataSchema.coerce("server_options", d)
		return d
	return {}

# ---------- 本機身分（6.2、8.1） ----------
## 非 Steam 身分：<資料根目錄>/profiles/<profile>/identity.json 的 local_<uuid>
func local_identity() -> String:
	var d: Variant = read_json(identity_path())
	if d is Dictionary and RegEx.create_from_string("^local_[0-9a-f]{32}$").search(str(d.get("local_id", ""))) != null:
		return d["local_id"]
	var id := "local_" + Crypto.new().generate_random_bytes(16).hex_encode()
	write_json_atomic(identity_path(), { "local_id": id })
	return id

func load_settings() -> Dictionary:
	var d: Variant = read_json(settings_path())
	return d if d is Dictionary else {}

func save_settings(settings: Dictionary) -> Error:
	return write_json_atomic(settings_path(), settings)
