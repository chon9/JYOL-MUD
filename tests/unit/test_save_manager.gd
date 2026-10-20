extends "res://tests/test_case.gd"
## SaveManager：原子寫入、5 份備份輪替、損壞時退回備份（TECH_ARCH 8.3、13.6、17 #16）

const SaveManagerScript := preload("res://autoload/save_manager.gd")

var sm: Node
var dir := ""

func before_each() -> void:
	sm = SaveManagerScript.new()
	dir = temp_dir("save")
	sm.root_dir = dir

func after_each() -> void:
	sm.free()
	remove_dir_recursive(dir)

func _read(path: String) -> Variant:
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(abs_path))

func test_first_write_creates_file_without_backup() -> void:
	var p: String = dir.path_join("a/b/x.json")
	assert_eq(sm.write_json_atomic(p, { "n": 1 }), OK)
	assert_eq(int(_read(p)["n"]), 1)
	assert_false(FileAccess.file_exists(ProjectSettings.globalize_path(p + ".bak1")), "no bak1 yet")
	assert_false(FileAccess.file_exists(ProjectSettings.globalize_path(p + ".tmp")), "tmp removed")

func test_backup_rotation_keeps_five() -> void:
	var p: String = dir.path_join("world.json")
	for i in range(1, 8):   # 7 次寫入：本體 = 7，bak1..bak5 = 6..2
		assert_eq(sm.write_json_atomic(p, { "n": i }), OK, "write %d" % i)
	assert_eq(int(_read(p)["n"]), 7, "current")
	for k in range(1, 6):
		var b: Variant = _read("%s.bak%d" % [p, k])
		assert_true(b != null, "bak%d exists" % k)
		if b != null:
			assert_eq(int(b["n"]), 7 - k, "bak%d" % k)
	assert_false(FileAccess.file_exists(ProjectSettings.globalize_path(p + ".bak6")), "no bak6")
	assert_false(FileAccess.file_exists(ProjectSettings.globalize_path(p + ".tmp")), "no tmp left")

func test_fallback_to_backup_when_corrupt() -> void:
	var p: String = dir.path_join("w.json")
	sm.write_json_atomic(p, { "n": 1 })
	sm.write_json_atomic(p, { "n": 2 })
	var f := FileAccess.open(ProjectSettings.globalize_path(p), FileAccess.WRITE)
	f.store_string("{ broken json")
	f.close()
	var r: Dictionary = sm.read_json_with_fallback(p)
	assert_true(r["ok"])
	assert_eq(int(r["data"]["n"]), 1)
	assert_true(str(r["source"]).ends_with(".bak1"), "source " + str(r["source"]))

func test_fallback_fails_when_nothing_readable() -> void:
	var r: Dictionary = sm.read_json_with_fallback(dir.path_join("missing.json"))
	assert_false(r["ok"])

func test_world_round_trip_and_schema_fallback() -> void:
	var w: Dictionary = sm.new_world("w_test", "測試世界", "sha256:x", { "enabled_eras": ["1.0A"] })
	assert_eq(w["world_secret"].length(), 64, "32-byte secret hex")
	assert_eq(sm.save_world(w), OK)
	var r: Dictionary = sm.load_world("w_test")
	assert_true(r["ok"])
	assert_eq(r["data"]["world_name"], "測試世界")
	assert_type(r["data"]["schema_version"], TYPE_INT)
	assert_type(r["data"]["lineage"], TYPE_INT)
	# 寫入一份不認得的 schema_version：載入時要退回 bak1
	var future := w.duplicate(true)
	future["schema_version"] = 99
	sm.save_world(future)
	var r2: Dictionary = sm.load_world("w_test")
	assert_true(r2["ok"])
	assert_eq(r2["data"]["schema_version"], 1)
	assert_true(str(r2["source"]).ends_with(".bak1"))

func test_local_identity_is_stable_per_profile() -> void:
	sm.profile = "alice"
	var a1: String = sm.local_identity()
	var a2: String = sm.local_identity()
	sm.profile = "bob"
	var b: String = sm.local_identity()
	assert_true(a1.begins_with("local_"))
	assert_eq(a1, a2)
	assert_true(a1 != b)

func test_paths_follow_layout() -> void:
	assert_true(sm.world_path("w1").ends_with("worlds/w1/world.json"))
	assert_true(sm.character_path("w1", "steam_123", "ch_1").ends_with("worlds/w1/characters/steam_123/ch_1.json"))
	assert_true(sm.world_path("../evil").find("/../") == -1, "path traversal sanitized")

# ---------- M1：角色檔（M1_PLAN 3.5.6、3.10） ----------
const IDENT := "local_0123456789abcdef0123456789abcdef"

func _char(id: String, n := 1) -> Dictionary:
	return { "schema_version": 1, "id": id, "identity": IDENT, "name": "測試%d" % n, "money": 100 + n }

func test_character_paths() -> void:
	assert_true(sm.characters_dir("w1", IDENT).ends_with("worlds/w1/characters/" + IDENT))
	assert_true(sm.character_path("w1", IDENT, "ch_0000abcd").begins_with(sm.characters_dir("w1", IDENT)))

func test_character_save_load_round_trip() -> void:
	assert_eq(sm.save_character("w1", IDENT, _char("ch_00000001")), OK)
	var r: Dictionary = sm.load_character("w1", IDENT, "ch_00000001")
	assert_true(r["ok"])
	assert_eq(r["data"]["name"], "測試1")
	assert_eq(int(r["data"]["money"]), 101)
	assert_false(sm.load_character("w1", IDENT, "ch_missing")["ok"])

func test_character_load_falls_back_on_bad_schema() -> void:
	sm.save_character("w1", IDENT, _char("ch_00000002", 1))
	var future := _char("ch_00000002", 2)
	future["schema_version"] = 7
	sm.save_character("w1", IDENT, future)
	var r: Dictionary = sm.load_character("w1", IDENT, "ch_00000002")
	assert_true(r["ok"])
	assert_eq(r["data"]["name"], "測試1", "schema 7 treated as corrupt, bak1 used")
	assert_true(str(r["source"]).ends_with(".bak1"))

func test_list_character_ids() -> void:
	assert_eq(sm.list_character_ids("w1", IDENT), [])
	sm.save_character("w1", IDENT, _char("ch_000000b2"))
	sm.save_character("w1", IDENT, _char("ch_000000a1"))
	sm.save_character("w1", IDENT, _char("ch_000000a1"))   # 產生 .bak1，不得重複列出
	assert_eq(sm.list_character_ids("w1", IDENT), ["ch_000000a1", "ch_000000b2"])
	assert_eq(sm.list_character_ids("w1", "local_ffffffffffffffffffffffffffffffff"), [])

func test_delete_character_moves_to_deleted() -> void:
	sm.save_character("w1", IDENT, _char("ch_000000c3"))
	sm.save_character("w1", IDENT, _char("ch_000000c3"))
	sm.save_character("w1", IDENT, _char("ch_000000d4"))
	assert_eq(sm.delete_character("w1", IDENT, "ch_000000c3"), OK)
	assert_eq(sm.list_character_ids("w1", IDENT), ["ch_000000d4"])
	var del_dir := ProjectSettings.globalize_path(sm.characters_dir("w1", IDENT)).path_join("deleted")
	var files := DirAccess.get_files_at(del_dir)
	assert_eq(files.size(), 2, "main + bak1 moved: %s" % str(files))
	for f in files:
		assert_true(f.begins_with("ch_000000c3_"), f)
	assert_false(sm.load_character("w1", IDENT, "ch_000000c3")["ok"])
	assert_true(sm.delete_character("w1", IDENT, "ch_000000c3") != OK, "second delete fails")

func test_new_world_has_m1_fields_and_old_files_are_upgraded() -> void:
	var w: Dictionary = sm.new_world("w_m1", "M1", "sha256:x", {})
	assert_eq(w["char_names"], {})
	assert_eq(w["corpses"], [])
	assert_eq(w["clock_last_night"], false)
	assert_eq(w["id_counter"], 0)
	var old := w.duplicate(true)
	old.erase("char_names")
	old.erase("clock_last_night")
	old.erase("id_counter")
	sm.save_world(old)
	var r: Dictionary = sm.load_world("w_m1")
	assert_true(r["ok"])
	assert_eq(r["data"]["char_names"], {})
	assert_eq(r["data"]["id_counter"], 0)
	assert_type(r["data"]["id_counter"], TYPE_INT)
	assert_eq(r["data"]["clock_last_night"], false)

# ---------- M2_PLAN 4.6.9：角色護照（客戶端） ----------
func test_passport_save_load_list() -> void:
	assert_eq(sm.list_passports("w1"), [], "none yet")
	assert_eq(sm.load_passport("w1", "ch_a")["ok"], false)
	assert_eq(sm.save_passport("w1", "ch_b", { "v": 1, "char_id": "ch_b" }), OK)
	assert_eq(sm.save_passport("w1", "ch_a", { "v": 1, "char_id": "ch_a" }), OK)
	assert_eq(sm.save_passport("w1", "ch_a", { "v": 1, "char_id": "ch_a", "saved_s": 5.0 }), OK)   # 第二次 → .bak1
	assert_eq(sm.save_passport("w2", "ch_c", { "v": 1 }), OK)
	assert_eq(sm.list_passports("w1"), ["ch_a", "ch_b"], "sorted, no .bak/.tmp")
	assert_eq(sm.list_passports("w2"), ["ch_c"])
	var r: Dictionary = sm.load_passport("w1", "ch_a")
	assert_true(r["ok"])
	assert_eq(float(r["data"]["saved_s"]), 5.0)
	assert_true(sm.passport_path("w1", "ch_a").begins_with(dir.path_join("passports/w1")))
	assert_eq(sm.save_passport("", "ch_a", {}), ERR_INVALID_PARAMETER)
	# 本體壞掉 → 退回備份
	var f := FileAccess.open(ProjectSettings.globalize_path(sm.passport_path("w1", "ch_a")), FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	var r2: Dictionary = sm.load_passport("w1", "ch_a")
	assert_true(r2["ok"], "fallback to bak1")
	assert_eq(str(r2["data"]["char_id"]), "ch_a")

## M2 第三輪審查：主機送來的 world_id／char_id 不能讓路徑跳出 passports 資料夾（"../settings" 覆寫 settings.json）
func test_safe_name_blocks_dot_segments() -> void:
	assert_eq(SaveManagerScript._safe_name(".."), "__")
	assert_eq(SaveManagerScript._safe_name("."), "_")
	assert_eq(SaveManagerScript._safe_name(".hidden"), "_hidden")
	assert_eq(SaveManagerScript._safe_name("w_1"), "w_1", "normal names unchanged")
	var p: String = sm.passport_path("..", "settings")
	assert_false(p.contains("/../"), "no parent segment: " + p)
	assert_true(p.contains("passports/"), p)
