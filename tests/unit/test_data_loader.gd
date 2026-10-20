extends "res://tests/test_case.gd"
## DataLoader：float→int 轉型、era 篩選、era_until、patch、enabled_eras 驗證、rule_profile 展開（TECH_ARCH 5、13.5）

const FIXTURE := "res://tests/fixtures/data_min"

var loader: DataLoader

func before_each() -> void:
	loader = DataLoader.new()
	loader.load_all(FIXTURE)

func test_fixture_loads_without_errors() -> void:
	assert_eq(loader.errors.size(), 0, "errors: %s" % ", ".join(loader.errors))
	assert_true(loader.content_hash.begins_with("sha256:"), "hash prefix")
	assert_eq(loader.content_hash.length(), 7 + 64, "hash length")

func test_content_hash_is_stable() -> void:
	var other := DataLoader.new()
	other.load_all(FIXTURE)
	assert_eq(other.content_hash, loader.content_hash)

func test_content_hash_differs_between_data_sets() -> void:
	var real := DataLoader.new()
	real.load_all("res://data")
	assert_true(real.content_hash != loader.content_hash)

func test_int_fields_are_coerced() -> void:
	var ma: Dictionary = loader.all_tables["martial_arts"]["sl_changquan"]
	assert_type(ma["self_study_until"], TYPE_INT, "self_study_until")
	assert_type(ma["moves"][0]["power"], TYPE_INT, "moves[].power")
	assert_type(ma["moves"][0]["unlock_level"], TYPE_INT, "moves[].unlock_level")
	assert_type(ma["difficulty"], TYPE_FLOAT, "difficulty stays float")
	assert_type(ma["moves"][0]["status_chance"], TYPE_FLOAT, "status_chance stays float")
	assert_type(loader.all_tables["eras"]["1.0B"]["order"], TYPE_INT, "eras.order")
	assert_type(loader.all_tables["rule_profiles"]["classic_standard"]["rules"]["xuedian_cap"], TYPE_INT, "xuedian_cap")
	var sl: Dictionary = loader.all_tables["sects"]["shaolin"]
	assert_type(sl["join_requires"][0]["value"], TYPE_INT, "join_requires[].value")
	assert_eq(sl["join_requires"][0]["value"], -99)
	assert_type(sl["sect_skill_effect"]["value"], TYPE_FLOAT, "nested effect value stays float")
	assert_type(loader.all_tables["regions"]["r_a"]["suggested_xp"][1], TYPE_INT, "suggested_xp[]")

func test_maps_and_server_options_are_coerced() -> void:
	var m: Dictionary = loader.all_maps["r_a"]
	assert_type(m["escape_tiles_hint"], TYPE_INT, "escape_tiles_hint")
	var room: Dictionary = m["rooms"][0]
	assert_type(room["encounter"]["table"][0]["w"], TYPE_INT, "rooms[].encounter.table[].w")
	assert_type(room["encounter"]["table"][0]["count"][1], TYPE_INT, "rooms[].encounter.table[].count[]")
	assert_type(room["encounter"]["rate"], TYPE_FLOAT, "encounter rate stays float")
	assert_type(room["requires"][0]["value"], TYPE_INT, "rooms[].requires[].value")
	assert_type(loader.server_options_default["max_players"], TYPE_INT, "max_players")
	assert_type(loader.server_options_default["rule_profile"]["overrides"]["xuedian_cap"], TYPE_INT, "override cap")

func test_coerce_paths_directly() -> void:
	var row := { "stats": { "qi": 250.0, "str": 18.0 }, "drops": [ { "min": 1.0, "max": 2.0, "chance": 0.5 } ] }
	DataSchema.coerce("monsters", row)
	assert_type(row["stats"]["qi"], TYPE_INT, "stats.*")
	assert_type(row["drops"][0]["max"], TYPE_INT, "drops[].max")
	assert_type(row["drops"][0]["chance"], TYPE_FLOAT, "chance stays float")

func test_activate_base_era_only() -> void:
	var view := loader.activate(["1.0A"])
	assert_has(view["sects"], "shaolin")
	assert_not_has(view["sects"], "gaibang", "1.0B row filtered:")
	assert_not_has(view["martial_arts"], "gb_xianglong")
	assert_has(view["npcs"], "n_old")
	assert_not_has(view["npcs"], "n_new")
	assert_has(view["maps"], "r_a")
	assert_eq(view["npcs"]["n_patch"]["region"], "r_a", "patch not applied without 1.0B")
	assert_eq(loader.activate_errors.size(), 0, "activate errors: %s" % ", ".join(loader.activate_errors))

func test_activate_with_expansion_and_era_until() -> void:
	var view := loader.activate(["1.0A", "1.0B"])
	assert_has(view["sects"], "gaibang")
	assert_has(view["npcs"], "n_new")
	assert_not_has(view["npcs"], "n_old", "era_until 1.0B removes row:")
	assert_eq(view["npcs"]["n_patch"]["region"], "r_b", "patch merged")
	assert_eq(loader.all_tables["npcs"]["n_patch"]["region"], "r_a", "raw data untouched by patch")
	assert_eq(loader.activate_errors.size(), 0, "activate errors: %s" % ", ".join(loader.activate_errors))

func test_eras_and_rule_profiles_always_present() -> void:
	var view := loader.activate(["1.0A"])
	assert_eq(view["eras"].size(), 3)
	assert_eq(view["rule_profiles"].size(), 2)

func test_validate_enabled_eras() -> void:
	var eras: Dictionary = loader.all_tables["eras"]
	assert_eq(DataLoader.validate_enabled_eras(eras, ["1.0A"]).size(), 0, "base only")
	assert_eq(DataLoader.validate_enabled_eras(eras, ["1.0A", "1.0B", "gmdk"]).size(), 0, "full chain")
	assert_true(DataLoader.validate_enabled_eras(eras, ["1.0B"]).size() > 0, "missing base")
	assert_true(DataLoader.validate_enabled_eras(eras, ["1.0A", "gmdk"]).size() > 0, "requires not closed")
	assert_true(DataLoader.validate_enabled_eras(eras, ["1.0A", "nope"]).size() > 0, "unknown era")

func test_era_closure() -> void:
	var c := DataLoader.era_closure(loader.all_tables["eras"], "gmdk")
	c.sort()
	assert_eq(c, ["1.0A", "1.0B", "gmdk"])

func test_expand_rule_profile() -> void:
	var profiles: Dictionary = loader.all_tables["rule_profiles"]
	var r := DataLoader.expand_rule_profile(profiles, { "preset": "classic_standard", "overrides": { "jail_enabled": false } })
	assert_eq(r["death_rule"], "STANDARD")
	assert_eq(r["jail_enabled"], false)
	assert_eq(r["xuedian_cap"], 65200)
	var partial := DataLoader.expand_rule_profile(profiles, { "preset": "partial", "overrides": {} })
	assert_eq(partial["death_rule"], "CASUAL")
	assert_eq(partial["corpse_window"], "CLASSIC_30", "missing switch gets default")
	var f := DataLoader.expand_rule_profile(profiles, { "preset": "classic_standard", "overrides": { "xuedian_cap": 5.0 } })
	assert_type(f["xuedian_cap"], TYPE_INT, "float override coerced")

func test_duplicate_id_and_missing_era_are_errors() -> void:
	var l := DataLoader.new()
	var rows := { "table": "sects", "version": 1, "rows": [
		{ "id": "a", "era": "1.0A" }, { "id": "a", "era": "1.0A" }, { "id": "b" }, { "era": "1.0A" } ] }
	var by_id := l._index_rows("sects", rows, "sects.json")
	assert_eq(by_id.size(), 1)
	assert_eq(l.errors.size(), 3, "errors: %s" % ", ".join(l.errors))

func test_missing_directory_reports_errors() -> void:
	var l := DataLoader.new()
	assert_false(l.load_all("res://tests/fixtures/does_not_exist"))
	# STORY_PLAN §8.1：四個新表是選填（檔案不存在不算錯）
	assert_true(l.errors.size() >= DataLoader.FILES.size() - DataLoader.OPTIONAL_FILES.size())

func test_reference_to_inactive_row_is_reported() -> void:
	var view := {
		"sects": { "shaolin": { "id": "shaolin" } },
		"martial_arts": { "x": { "id": "x", "sect_id": "gaibang", "moves": [] } },
		"text_templates": {},
	}
	var errs := DataSchema.check_references(view)
	assert_eq(errs.size(), 1)

func test_real_data_loads_and_activates() -> void:
	var real := DataLoader.new()
	assert_true(real.load_all("res://data"), "res://data errors: %s" % ", ".join(real.errors))
	real.activate(real.server_options_default.get("enabled_eras", []))
	assert_eq(real.activate_errors.size(), 0, "activate: %s" % ", ".join(real.activate_errors))
	assert_has(real.all_tables["sects"], "shaolin")
	assert_has(real.all_tables["sects"], "huashan")

func test_game_data_autoload_rejects_bad_eras() -> void:
	var gd: Node = tree.root.get_node("GameData")
	assert_true(gd.load_ok, "GameData loaded")
	assert_false(gd.activate(["1.0B"], {}), "missing base rejected")
	assert_true(gd.activate(["1.0A"], { "preset": "friends_casual", "overrides": {} }), "valid activate")
	assert_eq(gd.rules["death_rule"], "CASUAL")
	gd.activate(["1.0A"], { "preset": "classic_standard", "overrides": {} })
