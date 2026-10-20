extends "res://tests/test_case.gd"
## Character 的 M3a 欄位（M3A_PLAN 3.11）：讀舊檔補預設、存讀往返、坐牢與戰後狀態方法、to_combatant 新欄位。

func _tables() -> Dictionary:
	return GameData.tables

func test_old_file_gets_defaults() -> void:
	var c := Character.from_dict({ "schema_version": 1, "id": "ch_old", "name": "舊檔" })
	assert_eq(c.sect_master, "")
	assert_eq(c.sect_record, Character.default_sect_record())
	assert_eq(c.jail, {})
	assert_eq(c.conditions, {})
	assert_false(c.is_jailed())
	var d := c.to_dict()
	assert_eq(d["schema_version"], 1, "存檔格式維持 1（SaveManager、Passport 只認 1）")
	assert_eq(d["data_version"], Character.DATA_VERSION)
	assert_eq(Character.DATA_VERSION, 3, "M3B_PLAN §4.12：2 → 3")

func test_roundtrip_m3a_fields() -> void:
	var c := Character.new()
	c.id = "ch_rt"
	c.online_s = 100.0
	c.sect = "quanzhen"
	c.sect_master = "n_qz_qiuchuji"
	c.sect_record["breached"] = { "qz_r_morality": true }
	c.add_sect_history("quanzhen", "JOIN")
	c.jail = { "sect": "quanzhen", "room": "qz_siguo", "until_online_s": 7300.0, "reason": "BREACH", "rule": "qz_r_x",
		"days": 1, "notified": true, "scope": "SECT" }   # M3B_PLAN §5.1.4：jail 多記 scope
	c.add_condition("poison", 3, 6, 220.0)
	var parsed: Variant = JSON.parse_string(JSON.stringify(c.to_dict()))
	var c2 := Character.from_dict(parsed)
	assert_eq(c2.to_dict(), c.to_dict(), "JSON 往返")
	assert_type(c2.conditions["poison"]["level"], TYPE_INT)
	assert_type(c2.conditions["poison"]["ticks_left"], TYPE_INT)
	assert_type(c2.jail["until_online_s"], TYPE_FLOAT)
	assert_true(c2.is_jailed())
	assert_eq(c2.jail_left_s(), 7200.0)

func test_condition_methods() -> void:
	var c := Character.new()
	c.add_condition("poison", 2, 4, 50.0)
	assert_eq(c.condition_level("poison"), 2)
	c.add_condition("poison", 1, 8, 999.0)
	assert_eq(c.condition_level("poison"), 2, "LEVEL_MAX：取較高等級")
	assert_eq(int(c.conditions["poison"]["ticks_left"]), 8, "較多次數")
	assert_eq(float(c.conditions["poison"]["next_online_s"]), 50.0, "發作時刻沿用舊的")
	c.add_condition("poison", 0, 3, 1.0)
	assert_eq(c.condition_level("poison"), 2, "等級 0 不加")
	assert_true(c.clear_condition("poison"))
	assert_false(c.clear_condition("poison"))
	assert_eq(c.condition_level("poison"), 0)

func test_history_capped() -> void:
	var c := Character.new()
	for i in 25:
		c.add_sect_history("shaolin", "JOIN")
	assert_eq((c.sect_record["history"] as Array).size(), Character.SECT_HISTORY_MAX)

func test_to_combatant_new_fields() -> void:
	var tb := _tables()
	var c := Character.new()
	c.id = "ch_cb"
	c.gender = "F"
	c.sect = ""
	c.party_id = "pt_1"
	for k in Character.ATTR_IDS:
		c.attrs[k] = 20
	# 用藥：取一個 usable_in_battle 的物品
	var med := ""
	for iid in tb.get("items", {}):
		var r: Dictionary = tb["items"][iid]
		if bool(r.get("usable", false)) and bool(r.get("usable_in_battle", false)) and not (r.get("effects", []) as Array).is_empty():
			med = str(iid)
			break
	if med != "":
		c.inventory.items.append({ "uid": "it_med", "id": med, "n": 2, "born_s": 0.0 })
	c.add_condition("poison", 2, 4, 10.0)
	var spec := c.to_combatant(tb, GameData.default_server_options(), 0, 1)
	assert_eq(spec["gender"], "F")
	assert_eq(spec["sect"], "")
	assert_eq(spec["party_id"], "pt_1")
	var ca: Dictionary = spec["cmd_arts"]
	for k in ["POISON", "MEDIC", "HIDDEN", "FORMATION", "INNER", "ACUPOINT"]:
		assert_true(ca.has(k) and ca[k] is Array, "cmd_arts." + k)
	assert_eq(spec["hidden_items"], [])
	if med != "":
		assert_eq((spec["battle_items"] as Array).size(), 1)
		assert_eq(str(spec["battle_items"][0]["uid"]), "it_med")
		assert_eq(int(spec["battle_items"][0]["n"]), 2)
	assert_eq(int(spec["statuses"]["poison"]["level"]), 2)

func test_cmd_arts_and_hidden_items_with_fake_rows() -> void:
	var tb := {
		"martial_arts": {
			"a_poison": { "id": "a_poison", "category": "POISON" },
			"a_inner_lo": { "id": "a_inner_lo", "category": "INNER" },
			"a_inner_hi": { "id": "a_inner_hi", "category": "INNER" },
			"a_zhemei": { "id": "a_zhemei", "category": "FIST", "acupoint": true },
			"a_stab": { "id": "a_stab", "category": "STAB" },
			"a_mon": { "id": "a_mon", "category": "POISON", "monster_only": true },
		},
		"items": { "h_dart": { "id": "h_dart", "name": "金錢鏢", "effects": [ { "type": "hidden", "value": 8 } ] } },
		"basic_skills": {}, "sects": {}, "life_skills": {},
	}
	var c := Character.new()
	c.skills.entries = { "a_poison": { "level": 5, "prof": 0 }, "a_inner_lo": { "level": 3, "prof": 0 },
		"a_inner_hi": { "level": 9, "prof": 0 }, "a_zhemei": { "level": 1, "prof": 0 }, "a_stab": { "level": 2, "prof": 0 },
		"a_mon": { "level": 9, "prof": 0 } }
	var ca := c.cmd_arts(tb)
	assert_eq(ca["POISON"], ["a_poison"], "monster_only 不算")
	assert_eq(ca["INNER"], ["a_inner_hi", "a_inner_lo"], "內功依等級高到低")
	assert_eq(ca["ACUPOINT"], ["a_zhemei"])
	assert_has(CharData.BATTLE_CATEGORIES, "STAB")
	c.inventory.items.append({ "uid": "it_d", "id": "h_dart", "n": 7, "born_s": 0.0 })
	assert_eq(c.hidden_items(tb), [ { "uid": "it_d", "item_id": "h_dart", "name": "金錢鏢", "n": 7, "dmg": 8 } ])
