extends "res://tests/unit/test_world_fixture.gd"
## M3B_PLAN §2、§11.1：era 決定與遷移。
## 新世界預設 1.0A+1.0B；classic_strict 只 1.0A；--eras 優先；既有世界不被改；pending_eras 下次開服套用；
## 1.0A 世界沒有 1.0B 的東西、出生城只有兩座；desc_1_0b 只在 1.0B 換上；伺服器設定 enable_era_1_0b 只能開不能關。

func before_each() -> void:
	world_name = "w_m3b_era"
	super.before_each()

func test_defaults_file() -> void:
	var so: Dictionary = GameData.default_server_options()
	assert_eq(so.get("enabled_eras"), ["1.0A", "1.0B"], "server_options.default.enabled_eras（O1、E1）")
	assert_eq(so.get("pending_eras"), [])
	assert_eq(str(so.get("jail_location", "")), "AUTO")
	assert_eq(str(so.get("gb_assembly", "")), "DAILY")
	assert_eq(so.get("seize_enabled"), true)
	for k in ["bank_capacity", "bank_money_cap", "consign_fee_base", "consign_fee_per_weight", "consign_hold_days",
			"guild_signers", "org_found_fame", "org_signer_fame", "org_found_fee", "org_member_max", "org_petition_days"]:
		assert_true(so.has(k), "§4.11 選項 " + k)
		assert_type(so[k], TYPE_INT, k)
	var rp: Dictionary = GameData.loader.all_tables.get("rule_profiles", {})
	assert_eq(rp["classic_strict"].get("default_eras"), ["1.0A"], "classic_strict 的 default_eras")
	for id in ["classic_standard", "later_official", "friends_casual"]:
		assert_false(rp[id].has("default_eras"), id + " 不加 default_eras")

func test_decide_new_world_eras() -> void:
	if not game_ok():
		return
	var so: Dictionary = GameData.default_server_options()
	var d: Dictionary = ws.decide_new_world_eras("", so)
	assert_eq(d["eras"], ["1.0A", "1.0B"], "預設 1.0A＋1.0B")
	assert_eq(str(d["source"]), "default")
	var strict := so.duplicate(true)
	strict["rule_profile"] = { "preset": "classic_strict", "overrides": {} }
	d = ws.decide_new_world_eras("", strict)
	assert_eq(d["eras"], ["1.0A"], "classic_strict → 只 1.0A")
	assert_eq(str(d["source"]), "preset")
	d = ws.decide_new_world_eras("1.0A,1.0B", strict)
	assert_eq(d["eras"], ["1.0A", "1.0B"], "--eras 永遠優先")
	assert_eq(str(d["source"]), "cli")
	d = ws.decide_new_world_eras("1.0A", so)
	assert_eq(d["eras"], ["1.0A"])
	d = ws.decide_new_world_eras("1.0B", so)
	assert_true(str(d["error"]) != "", "缺 base era → 錯誤")

func test_new_world_gets_both_eras() -> void:
	if not game_ok():
		return
	assert_eq(ws.world.get("enabled_eras"), ["1.0A", "1.0B"], "新世界 world.enabled_eras")
	assert_eq(GameData.enabled_eras, ["1.0A", "1.0B"])
	assert_true(tables()["regions"].has("jingcheng"), "1.0B 的京城生效")

func test_existing_world_keeps_eras_and_pending_applies_next_start() -> void:
	if not game_ok():
		return
	# 把這個世界改成 1.0A-only 的舊世界（options.json 也沒有 enabled_eras）
	ws.world["enabled_eras"] = ["1.0A"]
	ws.options.erase("enabled_eras")
	ws.options.erase("pending_eras")
	sm.save_options(ws.world_id, ws.options)
	ws.save_now()
	restart_world()
	assert_eq(ws.world.get("enabled_eras"), ["1.0A"], "既有世界的 era 不被新預設改掉")
	assert_eq(ws.options.get("enabled_eras"), ["1.0A"], "options 補預設值時不覆寫 enabled_eras")
	assert_eq(GameData.enabled_eras, ["1.0A"])
	assert_false(tables()["regions"].has("jingcheng"), "1.0A 世界沒有京城")
	# 1.0A 世界的出生城只有西夏、大理
	var cities: Array = []
	for c in ws.world_info().get("birth_cities", []):
		cities.append(str(c["id"]))
	assert_eq(cities, ["dali", "xixia"])
	# 主機在伺服器設定打開 1.0B：下次開服生效
	var adm = host().admin
	assert_eq(adm.current_value("enable_era_1_0b"), "off")
	ok("server_opts_set", { "key": "enable_era_1_0b", "value": "on" })
	assert_eq(ws.options.get("pending_eras"), ["1.0A", "1.0B"])
	assert_eq(ws.world.get("enabled_eras"), ["1.0A"], "執行中不重建")
	assert_eq(adm.current_value("enable_era_1_0b"), "pending")
	assert_eq(reason("server_opts_set", { "key": "enable_era_1_0b", "value": "on" }), "bad_value:value", "已排定不能再改")
	assert_eq(ws.world_info().get("pending_eras"), ["1.0A", "1.0B"])
	restart_world()
	assert_eq(ws.world.get("enabled_eras"), ["1.0A", "1.0B"], "開服時套用 pending_eras")
	assert_eq(ws.options.get("pending_eras"), [], "清掉 pending_eras")
	assert_eq(GameData.enabled_eras, ["1.0A", "1.0B"])
	assert_eq(host().admin.current_value("enable_era_1_0b"), "enabled")
	var row: Dictionary = {}
	for r in host().admin.snapshot()["editable"]:
		if str(r["key"]) == "enable_era_1_0b":
			row = r
	assert_true(bool(row.get("locked", false)), "已開放：灰掉")
	assert_eq(reason("server_opts_set", { "key": "enable_era_1_0b", "value": "off" }), "bad_value:value", "不能關")

func test_one_a_world_has_no_one_b_content() -> void:
	if not game_ok():
		return
	assert_true(GameData.activate(["1.0A"], {}))
	var tb := tables()
	for rid in tb["regions"]:
		assert_true(str(tb["regions"][rid].get("era", "")) == "1.0A", "1.0A 世界只有 1.0A 地區：" + str(rid))
	for sid in tb["sects"]:
		assert_true(str(tb["sects"][sid].get("era", "")) == "1.0A", "門派 " + str(sid))
	assert_false(tb.get("life_skills", {}).has("life_carpentry"), "1.0A 世界沒有工匠")
	assert_false(tb.get("sects", {}).has("gaibang"), "1.0A 世界沒有丐幫")
	for id in tb.get("sect_ranks", {}):
		assert_eq(str(tb["sect_ranks"][id].get("era", "")), "1.0A", "sect_ranks " + str(id))

func test_desc_1_0b_applied_only_in_1_0b() -> void:
	var m := { "region_id": "x", "era": "1.0A", "rooms": [ { "id": "r1", "desc": "舊描述", "desc_1_0b": "新描述",
		"exits": [ { "dir": "E", "to": "r2", "era": "1.0B" } ] } ] }
	var a: Dictionary = m.duplicate(true)
	DataLoader.apply_era_desc(a, { "1.0A": true })
	assert_eq(str(a["rooms"][0]["desc"]), "舊描述")
	var b: Dictionary = m.duplicate(true)
	DataLoader.apply_era_desc(b, { "1.0A": true, "1.0B": true })
	assert_eq(str(b["rooms"][0]["desc"]), "新描述")

func test_birth_city_list_uses_effective_regions() -> void:
	if not game_ok():
		return
	# 1.0B 世界：出生城＝生效 regions 中 birth_allowed 的 CITY（合併前京城 birth_allowed 還是 false）
	var cities: Array = []
	for c in ws.world_info().get("birth_cities", []):
		cities.append(str(c["id"]))
	assert_true(cities.has("xixia") and cities.has("dali"))
	var jc: Dictionary = tables()["regions"].get("jingcheng", {})
	assert_eq(cities.has("jingcheng"), bool(jc.get("birth_allowed", false)), "京城看資料的 birth_allowed（O3，WP-C-jingcheng）")
	# 非 CITY 的地區即使 birth_allowed 也不能出生
	tables()["regions"]["xixia_north"] = (tables()["regions"].get("xixia_north", {}) as Dictionary).duplicate()
	tables()["regions"]["xixia_north"]["birth_allowed"] = true
	ok("char_roll")
	assert_eq(reason("char_create", { "name": "野地生", "gender": "M", "birth_month": 1, "birth_city": "xixia_north",
		"alloc": { "wit": 5 } }), "bad_value:birth_city")
