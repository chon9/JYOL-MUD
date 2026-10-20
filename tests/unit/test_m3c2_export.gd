extends "res://tests/unit/test_world_fixture.gd"
## M3C2_PLAN §5.1、§5.2（WP-CARRY）：匯出檔 —— 檔名、內容、目錄只在資料根目錄下、裸護照與匯出檔都能讀。

func before_each() -> void:
	world_name = "w_m3c2_export"
	super.before_each()

func _passport() -> Dictionary:
	return host().make_passport(ch())

func test_file_name_format() -> void:
	var dt := { "year": 2026, "month": 10, "day": 20, "hour": 21, "minute": 5 }
	assert_eq(sm.export_file_name("小明", "jy2001", dt), "小明_jy2001_20261020-2105.jychar.json")
	# 路徑字元一律清掉，不會跳出資料夾
	var n: String = sm.export_file_name("../壞/名", "..\\w", dt)
	assert_false(n.contains("/") or n.contains("\\"), n)
	assert_false(n.begins_with("."), n)

func test_export_writes_under_data_root_with_contents() -> void:
	if not game_ok():
		return
	make_char("匯出俠")
	var pp := _passport()
	var path: String = sm.export_character(pp, { "world_name": "我的江湖", "content_hash": GameData.content_hash })
	assert_true(path != "", "exported: " + str(sm.last_error))
	var root := ProjectSettings.globalize_path(sm.root_dir)
	assert_true(path.begins_with(root.path_join("exports")), "under <root>/exports: %s vs %s" % [path, root])
	assert_true(path.get_file().begins_with("匯出俠_%s_" % ws.world_id), path.get_file())
	assert_true(path.ends_with(".jychar.json"), path)
	assert_true(FileAccess.file_exists(path), "file exists")
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(d is Dictionary, "json")
	assert_eq(str(d["kind"]), "jy_char_export")
	assert_eq(int(d["v"]), 1)
	assert_eq(str(d["game_version"]), BuildInfo.version())
	assert_eq(int(d["protocol"]), Protocol.VERSION)
	assert_eq(str(d["content_fp"]), BuildInfo.fingerprint12(GameData.content_hash))
	assert_eq(str(d["content_fp"]).length(), 12)
	assert_eq(str(d["world_name"]), "我的江湖")
	assert_true(str(d["exported_at"]).length() >= 16, "exported_at")
	assert_eq(str(d["passport"]["char_id"]), str(ch().id))
	assert_eq(Passport.check_format(d["passport"]), "", "passport intact")
	assert_eq(sm.exports_dir(), root.path_join("exports"))

func test_read_export_and_bare_passport() -> void:
	if not game_ok():
		return
	make_char("讀檔俠")
	var pp := _passport()
	var path: String = sm.export_character(pp, { "world_name": "我的江湖", "content_hash": GameData.content_hash })
	var r: Dictionary = sm.read_import_file(path)
	assert_true(r["ok"], "export readable")
	assert_eq(str(r["kind"]), "export")
	assert_eq(str(r["world_name"]), "我的江湖")
	assert_eq(str(r["passport"]["world_name"]), "我的江湖", "world_name carried into passport")
	assert_eq(str(r["passport"]["char_id"]), str(ch().id))
	# 裸護照（passports/<world>/<char>.json）
	assert_eq(sm.save_passport(str(pp["world_id"]), str(pp["char_id"]), pp), OK)
	var r2: Dictionary = sm.read_import_file(sm.passport_path(str(pp["world_id"]), str(pp["char_id"])))
	assert_true(r2["ok"], "bare passport readable")
	assert_eq(str(r2["kind"]), "passport")
	assert_eq(Passport.check_format(r2["passport"]), "")
	# 預覽（客戶端）與主機用同一個 sanitize
	var san := ForeignImport.sanitize(r2["passport"], tables(), GameData.rules, ws.options)
	assert_true(san["ok"], "sanitize bare passport")

func test_unreadable_files() -> void:
	if not game_ok():
		return
	var dir := ProjectSettings.globalize_path(sm.root_dir).path_join("exports")
	DirAccess.make_dir_recursive_absolute(dir)
	var broken := dir.path_join("broken.json")
	var f := FileAccess.open(broken, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	assert_false(sm.read_import_file(broken)["ok"], "broken json")
	assert_eq(str(sm.read_import_file(broken)["error"]), "not_json", "M3c2 審查：原因 not_json")
	var big := dir.path_join("big.json")
	f = FileAccess.open(big, FileAccess.WRITE)
	f.store_string("{\"x\": \"" + "a".repeat(300000) + "\"}")
	f.close()
	var rb: Dictionary = sm.read_import_file(big)
	assert_false(rb["ok"], "too big")
	assert_eq(str(rb["error"]), "too_large")
	assert_false(sm.read_import_file(dir.path_join("missing.json"))["ok"], "missing")
	var other := dir.path_join("other.json")
	f = FileAccess.open(other, FileAccess.WRITE)
	f.store_string("{\"hello\": 1}")
	f.close()
	assert_false(sm.read_import_file(other)["ok"], "not a character file")
	assert_eq(str(sm.read_import_file(other)["error"]), "not_char", "M3c2 審查：原因 not_char")
	# M3c2 審查：檔案 < 256 KB 但護照 var_to_bytes > 64 KB（主機上限）→ passport_too_large，不讓預覽看起來正常
	var fat := dir.path_join("fat.json")
	f = FileAccess.open(fat, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "v": 1, "world_id": "w_x", "char_id": "c", "identity": "local_x", "name": "胖",
		"sig": "x", "saved_s": 1.0, "char": { "pad": "字".repeat(30000) } }))
	f.close()
	var rf: Dictionary = sm.read_import_file(fat)
	assert_false(rf["ok"], "fat passport")
	assert_eq(str(rf["error"]), "passport_too_large")
	# 壞護照不匯出
	assert_eq(sm.export_character({ "v": 1 }, {}), "")
	assert_true(str(sm.last_error) != "", "last_error set")

func test_summary_has_online_s_for_export_freshness() -> void:
	if not game_ok():
		return
	make_char("新鮮俠")
	var row: Dictionary = {}
	for c in cs.char_list:
		if str(c.get("char_id", "")) == str(ch().id):
			row = c
	assert_true(row.has("online_s"), "summary.online_s")
	assert_eq(bool(row.get("foreign", true)), false)
	assert_eq(str(row.get("identity", "")), s().identity)
	assert_eq(bool(row.get("alt", true)), false)
