extends "res://tests/test_case.gd"
## M3A_PLAN 3.7 的新條件型別（純角色判定＋主機 ctx）與 DataSchema 的條件欄位檢查。

func _tables() -> Dictionary:
	return {
		"items": { "i_letter": { "id": "i_letter", "name": "引薦書" } },
		"sects": { "wudang": { "id": "wudang", "name": "武當" } },
		"npcs": { "n_qz_qiuchuji": { "id": "n_qz_qiuchuji", "name": "丘處機" } },
	}

func _ch() -> Character:
	var c := Character.new()
	c.id = "ch_req"
	return c

func _chk(conds: Array, c: Character, ctx: Dictionary = {}) -> String:
	return Requirements.check(conds, c, _tables(), {}, {}, ctx)

func test_has_item() -> void:
	var c := _ch()
	assert_eq(_chk([ { "type": "has_item", "item": "i_letter" } ], c), "req_has_item")
	c.inventory.items.append({ "uid": "it_1", "id": "i_letter", "n": 1, "born_s": 0.0 })
	assert_eq(_chk([ { "type": "has_item", "item": "i_letter" } ], c), "", "n 預設 1")
	assert_eq(_chk([ { "type": "has_item", "item": "i_letter", "n": 2 } ], c), "req_has_item")
	c.inventory.items[0]["n"] = 2
	assert_eq(_chk([ { "type": "has_item", "item": "i_letter", "n": 2.0 } ], c), "", "JSON 浮點數")

func test_any_of() -> void:
	var c := _ch()
	var cond := { "type": "any_of", "options": [
		[ { "type": "sect", "sect": "wudang" } ],
		[ { "type": "no_sect" }, { "type": "has_item", "item": "i_letter" } ],
		[ { "type": "no_sect" }, { "type": "quest_flag", "flag": "wd_recommended" } ] ] }
	assert_eq(_chk([cond], c), "req_any_of")
	c.flags["wd_recommended"] = true
	assert_eq(_chk([cond], c), "", "第三組成立")
	c.flags = {}
	c.sect = "wudang"
	assert_eq(_chk([cond], c), "", "第一組成立")
	c.sect = "emei"
	c.flags["wd_recommended"] = true
	assert_eq(_chk([cond], c), "req_any_of", "第三組要 no_sect")
	assert_eq(_chk([ { "type": "any_of", "options": [] } ], c), "req_any_of", "空的 any_of 不成立")
	assert_eq(_chk([ { "type": "any_of", "options": "x" } ], c), "req_any_of")
	# 巢狀（2 層）照樣能判定
	var nested := { "type": "any_of", "options": [ [ { "type": "any_of", "options": [ [ { "type": "sect", "sect": "emei" } ] ] } ] ] }
	assert_eq(_chk([nested], c), "")

func test_enemy_pk_killing() -> void:
	var c := _ch()
	assert_eq(_chk([ { "type": "enemy_of", "sect": "wudang" } ], c), "req_enemy_of")
	c.sect_enemies = ["wudang"]
	assert_eq(_chk([ { "type": "enemy_of", "sect": "wudang" } ], c), "")
	assert_eq(_chk([ { "type": "pk_min", "value": 1 } ], c), "req_pk_min")
	c.pk = 2
	c.pk_stamp_s = c.online_s
	assert_eq(_chk([ { "type": "pk_min", "value": 1 } ], c), "")
	c.online_s += 1800.0 * 2
	assert_eq(_chk([ { "type": "pk_min", "value": 1 } ], c), "req_pk_min", "用 pk_value（遞減後）")
	assert_eq(_chk([ { "type": "killing_intent_min", "value": 2001 } ], c), "req_killing_intent_min")
	c.killing_intent = 2001
	assert_eq(_chk([ { "type": "killing_intent_min", "value": 2001 } ], c), "")

func test_sect_master() -> void:
	var c := _ch()
	assert_eq(_chk([ { "type": "sect_master", "npc": "n_qz_qiuchuji" } ], c), "req_sect_master")
	c.sect_master = "n_qz_qiuchuji"
	assert_eq(_chk([ { "type": "sect_master", "npc": "n_qz_qiuchuji" } ], c), "")
	assert_eq(_chk([ { "type": "sect_master", "npc": "n_qz_majue" } ], c), "req_sect_master")

func test_party_size_and_hour_need_ctx() -> void:
	var c := _ch()
	assert_eq(_chk([ { "type": "party_size_min", "value": 1 } ], c), "req_party_size_min", "沒有 ctx：不成立")
	assert_eq(_chk([ { "type": "party_size_min", "value": 3 } ], c, { "party_size": 3 }), "")
	assert_eq(_chk([ { "type": "party_size_min", "value": 3 } ], c, { "party_size": 2 }), "req_party_size_min")
	assert_eq(_chk([ { "type": "hour_in", "hours": ["卯", "午"] } ], c), "", "沒有 ctx：成立")
	assert_eq(_chk([ { "type": "hour_in", "hours": ["卯", "午"] } ], c, { "shichen": "午" }), "")
	assert_eq(_chk([ { "type": "hour_in", "hours": ["卯", "午"] } ], c, { "shichen": "子" }), "req_hour_in")
	# any_of 內層也拿得到 ctx
	var cond := { "type": "any_of", "options": [ [ { "type": "hour_in", "hours": ["子"] } ] ] }
	assert_eq(_chk([cond], c, { "shichen": "子" }), "")
	assert_eq(_chk([cond], c, { "shichen": "丑" }), "req_any_of")

func test_ok_helper_and_describe() -> void:
	var c := _ch()
	assert_true(Requirements.ok([], c, _tables(), {}, {}))
	for cond in [ { "type": "has_item", "item": "i_letter", "n": 2 }, { "type": "enemy_of", "sect": "wudang" },
			{ "type": "pk_min", "value": 1 }, { "type": "killing_intent_min", "value": 5 },
			{ "type": "sect_master", "npc": "n_qz_qiuchuji" }, { "type": "party_size_min", "value": 3 },
			{ "type": "hour_in", "hours": ["卯"] },
			{ "type": "any_of", "options": [ [ { "type": "no_sect" } ], [ { "type": "sect", "sect": "wudang" } ] ] } ]:
		var text := Requirements.describe(cond, _tables())
		assert_true(text != "" and text != "特殊條件", "describe %s -> %s" % [str(cond["type"]), text])
	assert_true(Requirements.describe({ "type": "has_item", "item": "i_letter" }, _tables()).contains("引薦書"))
	assert_true(Requirements.describe({ "type": "sect_master", "npc": "n_qz_qiuchuji" }, _tables()).contains("丘處機"))

func test_schema_lists_new_types() -> void:
	for t in ["has_item", "any_of", "enemy_of", "pk_min", "killing_intent_min", "sect_master", "party_size_min", "hour_in"]:
		assert_has(DataSchema.REQUIRE_TYPES, t)
		assert_true(DataSchema.REQUIRE_FIELDS_BY_TYPE.has(t), "fields " + t)
	assert_eq(DataSchema.check_conditions([ { "type": "has_item", "item": "x" } ], "t").size(), 0)
	assert_eq(DataSchema.check_conditions([ { "type": "has_item" } ], "t").size(), 1, "缺 item")
	assert_eq(DataSchema.check_conditions([ { "type": "nope" } ], "t").size(), 1)
	assert_eq(DataSchema.check_conditions([ { "type": "hour_in", "hours": ["卯", "X"] } ], "t").size(), 1, "不合法的時辰")
	var ok2 := [ { "type": "any_of", "options": [ [ { "type": "sect", "sect": "a" } ], [ { "type": "no_sect" } ] ] } ]
	assert_eq(DataSchema.check_conditions(ok2, "t").size(), 0)
	var bad_inner := [ { "type": "any_of", "options": [ [ { "type": "sect" } ] ] } ]
	assert_eq(DataSchema.check_conditions(bad_inner, "t").size(), 1, "內層條件也檢查")
	var deep := [ { "type": "any_of", "options": [ [ { "type": "any_of", "options": [ [ { "type": "no_sect" } ] ] } ] ] } ]
	assert_eq(DataSchema.check_conditions(deep, "t").size(), 1, "最多 2 層")

func test_rule_defaults_and_profiles() -> void:
	assert_eq(DataSchema.RULE_DEFAULTS["sect_violation_mode"], "JAIL")
	assert_eq(DataSchema.RULE_DEFAULTS["later_battle_cmds"], true)
	assert_eq(DataSchema.RULE_ENUMS["sect_violation_mode"], ["JAIL", "EXPEL", "BAN"])
	var profiles: Dictionary = GameData.loader.all_tables.get("rule_profiles", {})
	var want := { "classic_strict": ["EXPEL", false], "classic_standard": ["JAIL", true],
		"later_official": ["JAIL", true], "friends_casual": ["BAN", true] }
	for id in want:
		var r: Dictionary = profiles[id]["rules"]
		assert_eq(r.get("sect_violation_mode"), want[id][0], id)
		assert_eq(r.get("later_battle_cmds"), want[id][1], id)
	var so: Dictionary = GameData.default_server_options()
	for k in ["jail_breach_days", "jail_enemy_days", "ban_days", "jail_ransom"]:
		assert_type(so.get(k), TYPE_INT, k)
	assert_eq(int(so["jail_breach_days"]), 1)
	assert_eq(int(so["jail_enemy_days"]), 3)
	assert_eq(int(so["ban_days"]), 1)
	assert_eq(int(so["jail_ransom"]), 100000)
	assert_eq(so.get("sect_hostile_entry"), true)
	assert_eq(so.get("poison_flare_enabled"), true)
