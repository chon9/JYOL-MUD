extends "res://tests/test_case.gd"
## WP-CHAR：Character 模型的序列化往返、預設值、金錢／學點、獎勵、戰鬥結果套用、快照形狀。

const F := preload("res://tests/unit/test_character_fixtures.gd")

func _json_roundtrip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))

func test_roundtrip_identity() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.skills.set_level("basic_inner", 3, t)
	# STORY_PLAN §4.7：新格式（舊格式的遷移在 test_quest_state）
	c.quests["active"]["q_bandit"] = { "v": 2, "stage": "step_0", "objs": { "o": 2 }, "vars": { "pick": "abao", "n": 3, "ok": true },
		"since_world_s": 1.5, "stage_since_world_s": 2.5, "escort": "n_x" }
	c.quests["done"]["q_rabbit"] = { "n": 1, "outcome": "default", "world_s": 3.5, "failed": 0 }
	c.quests["cd"]["q_rabbit"] = 99.5
	c.lilian = 12
	c.ext = { "ambient": { "deeds": { "fame_100": true } } }
	c.flags["hs_trial_passed"] = true
	c.counters["med_uses"] = [1.5, 2.5]
	var d := c.to_dict()
	var c2 := Character.from_dict(d)
	assert_eq(c2.to_dict(), d, "from_dict(to_dict) identity")

func test_roundtrip_through_json_restores_ints() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.skills.set_level("basic_fist", 7, t)
	c.quests["active"]["q_bandit"] = { "v": 2, "stage": "step_1", "objs": { "o": 3 }, "vars": { "k": 4 },
		"since_world_s": 0.0, "stage_since_world_s": 0.0, "escort": "" }
	c.quests["done"]["q_rabbit"] = { "n": 2, "outcome": "default", "world_s": 0.0, "failed": 1 }
	c.lilian = 5
	var d := c.to_dict()
	var parsed := _json_roundtrip(d)
	assert_type(parsed["combat_xp"], TYPE_FLOAT, "json makes floats")
	var c2 := Character.from_dict(parsed)
	assert_eq(c2.to_dict(), d, "json roundtrip equals original")
	assert_type(c2.vitals["qi"], TYPE_INT)
	assert_type(c2.attrs["str"], TYPE_INT)
	assert_type(c2.skills.entries["basic_fist"]["level"], TYPE_INT)
	assert_type(c2.inventory.items[0]["n"], TYPE_INT)
	assert_type(c2.quests["active"]["q_bandit"]["objs"]["o"], TYPE_INT)
	assert_type(c2.quests["active"]["q_bandit"]["vars"]["k"], TYPE_INT, "整數值的變數讀回 int")
	assert_type(c2.quests["done"]["q_rabbit"]["n"], TYPE_INT)
	assert_type(c2.lilian, TYPE_INT)
	assert_type(c2.birth_month, TYPE_INT)
	assert_eq(d["schema_version"], 1)

func test_from_dict_fills_defaults() -> void:
	var c := Character.from_dict({ "id": "ch_deadbeef", "name": "甲" })
	assert_eq(c.id, "ch_deadbeef")
	assert_eq(c.attrs.size(), 7)
	assert_eq(c.vitals.keys().size(), 6)
	assert_eq(c.location, { "region": "", "room": "" })
	assert_eq(c.respawn, { "region": "", "room": "" })
	assert_eq(c.quests, { "active": {}, "done": {}, "cd": {} })
	assert_eq(c.lilian, 0)
	assert_eq(c.ext, {})
	assert_eq(c.buffs, { "smoke_until_s": 0.0 })
	assert_eq(c.inventory.equipped, Inventory.empty_equipped())   # M3c：8 個裝備欄
	assert_eq(c.dormant, {})
	assert_eq(c.sect, "")
	assert_true(c.counters.has("last_meditate_s") and c.counters.has("med_uses")
		and c.counters.has("last_birthday_year") and c.counters.has("last_meal_key"), "counters defaults")
	var d := c.to_dict()
	for k in ["schema_version", "id", "identity", "name", "gender", "birth_month", "birth_city", "created_s",
			"online_s", "attrs", "vitals", "combat_xp", "learn_points", "lili", "fame", "morality",
			"killing_intent", "pk", "money", "sect", "sect_enemies", "skills", "inventory", "location",
			"respawn", "quests", "flags", "buffs", "qi_bonus", "cultivations", "counters", "dead_count", "dormant"]:
		assert_has(d, k, "to_dict key")

func test_from_dict_drops_dangling_equipped_uid() -> void:
	var c := Character.from_dict({ "inventory": { "items": [], "equipped": { "WEAPON": "it_missing", "ARMOR": "" } } })
	assert_eq(c.inventory.equipped["WEAPON"], "")

func test_add_money_cap_and_floor() -> void:
	var c := F.new_char()
	c.money = Character.MONEY_CAP - 10
	assert_eq(c.add_money(50), 10)
	assert_eq(c.money, Character.MONEY_CAP)
	c.money = 30
	assert_eq(c.add_money(-100), -30)
	assert_eq(c.money, 0)

func test_add_learn_points_cap() -> void:
	var c := F.new_char()
	c.learn_points = 65190
	assert_eq(c.add_learn_points(50, { "xuedian_cap": 65200 }), 10)
	assert_eq(c.learn_points, 65200)
	assert_eq(c.add_learn_points(50, { "xuedian_cap": 0 }), 50, "cap 0 = none")
	c.learn_points = 5
	assert_eq(c.add_learn_points(-10, {}), -5)
	assert_eq(c.learn_points, 0)

func test_apply_rewards() -> void:
	var c := F.new_char()
	c.morality = 995
	var got := c.apply_rewards({ "combat_xp": 5, "learn_points": 2, "money": 7, "fame": 1, "morality": 10,
		"killing_intent": 3, "flags": ["hs_trial_passed"] }, F.rules())
	assert_eq(got, { "combat_xp": 5, "learn_points": 2, "money": 7, "fame": 1, "morality": 5, "killing_intent": 3, "lilian": 0 })
	assert_eq(int(c.apply_rewards({ "lilian": 15 }, F.rules())["lilian"]), 15, "STORY_PLAN §4.9：江湖歷練")
	assert_eq(c.lilian, 15)
	assert_eq(c.combat_xp, 5)
	assert_eq(c.learn_points, 102)
	assert_eq(c.money, 107)
	assert_eq(c.morality, 1000)
	assert_eq(c.flags.get("hs_trial_passed"), true)

func test_apply_battle_outcome_writes_vitals_and_weapon() -> void:
	var t := F.tables()
	var c := F.new_char()
	var wuid: String = c.inventory.equipped["WEAPON"]
	c.apply_battle_outcome({ "qi": 50, "neili": 0, "jing": 40, "shen": 30, "weapon_uid": "" }, t, F.options())
	assert_eq(c.vitals["qi"], 50)
	assert_eq(c.vitals["jing"], 40)
	assert_eq(c.vitals["shen"], 30)
	assert_eq(c.inventory.equipped["WEAPON"], "", "unequipped in battle")
	c.apply_battle_outcome({ "qi": 99999, "neili": 0, "jing": 40, "shen": 30, "weapon_uid": wuid }, t, F.options())
	assert_eq(c.inventory.equipped["WEAPON"], wuid)
	assert_eq(c.vitals["qi"], c.derived(t, F.options())["qi_max"], "clamped")

func test_to_combatant_shape() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.sect = "shaolin"
	c.skills.set_level("foxa", 10, t)
	c.skills.set_level("sl_changquan", 10, t)
	c.skills.set_level("sl_xinfa", 6, t)
	c.skills.set_level("basic_fist", 10, t)
	var s := c.to_combatant(t, F.options(), 0, 1)
	for k in ["kind", "ref", "name", "side", "peer", "ai", "attrs", "qi", "qi_max", "neili", "neili_max", "jing",
			"jing_max", "shen", "shen_max", "skills", "arts", "weapon", "weapon_options", "armor_power",
			"effective_inner", "lightness", "sect_skill", "killing_intent", "carry_ratio", "monster_row"]:
		assert_has(s, k, "combatant key")
	assert_eq(s["kind"], "PLAYER")
	assert_eq(s["ref"], "ch_00000001")
	assert_eq(s["arts"], ["sl_changquan"], "INNER arts not usable in 武")
	assert_eq(s["weapon"]["weapon_type"], "BLADE")
	assert_eq(s["weapon"]["atk"], 4)
	assert_eq(s["weapon_options"].size(), 1)
	assert_eq(s["armor_power"], 2)
	assert_eq(s["effective_inner"], 3, "0 + floor(6/2)")
	assert_eq(s["sect_skill"], { "id": "foxa", "effect": "DEFENSE", "level": 10 })
	assert_eq(s["skills"]["foxa"], 10)
	assert_type(s["carry_ratio"], TYPE_FLOAT)
	c.inventory.unequip("WEAPON")
	s = c.to_combatant(t, F.options(), 0, 1)
	assert_eq(s["weapon"], { "uid": "", "item_id": "", "weapon_type": "FIST", "atk": 0, "name": "" })

func test_to_sheet_and_summary_shape() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.sect = "shaolin"
	c.skills.set_level("foxa", 10, t)
	c.quests["active"]["q_rabbit"] = { "step": 0, "counts": {} }
	c.quests["done"]["q_bandit"] = 1
	c.respawn = { "region": "xixia", "room": "xx_gate_e" }
	var sh := c.to_sheet(t, F.options(), F.rules())
	for k in ["char_id", "name", "gender", "birth_month", "birth_city", "sect", "sect_name", "attrs", "attrs_base",
			"vitals", "carry", "carry_max", "combat_xp", "learn_points", "learn_points_cap", "lili", "fame",
			"morality", "killing_intent", "pk", "money", "art_level_cap", "weapon_power", "armor_power", "special_arts", "special_arts_max",
			"skills", "inventory", "equipped", "quests", "quests_done", "location", "respawn", "clock",
			"in_battle", "battle_id"]:
		assert_has(sh, k, "sheet key")
	assert_eq(sh["sect_name"], "少林")
	assert_eq(sh["learn_points_cap"], 65200)
	assert_eq(sh["art_level_cap"], 5)
	assert_eq(sh["special_arts_max"], 16)
	assert_eq(sh["skills"][0], { "id": "foxa", "name": "佛法", "kind": "SECT", "category": "", "level": 10, "prof": 1000, "next_prof": 1331 })
	assert_eq(sh["location"], { "region": "xixia", "region_name": "西夏", "room": "xx_square", "room_name": "西夏廣場" })
	assert_eq(sh["respawn"], { "room": "xx_gate_e", "room_name": "西夏東門" })
	assert_eq(sh["quests"][0]["name"], "狩獵事件：大兔皮")
	assert_eq(sh["quests"][0]["giver_name"], "武介山")
	assert_true(str(sh["quests"][0]["text"]).contains("荒草坡"), "sheet carries the quest description")
	assert_eq(sh["quests"][0]["steps"][0], { "text": "交給武介山 1 張大兔皮", "have": 0, "need": 1, "done": false })
	assert_eq(sh["quests_done"], [{ "id": "q_bandit", "name": "剿滅山賊", "chapter": "", "outcome_label": "", "n": 1 }])
	assert_eq(sh["quests"][0]["stage"], "step_0", "STORY_PLAN §4.14 quests 列")
	assert_eq(sh["quests"][0]["objectives"][0], { "text": "交給武介山 1 張大兔皮", "have": 0, "need": 1, "done": false })
	assert_has(sh, "lilian")
	assert_eq(sh["vitals"]["food"], 100)
	var mudao: Dictionary = {}
	for it in sh["inventory"]:
		if it["id"] == "w_mudao":
			mudao = it
	assert_eq(mudao["equipped_slot"], "WEAPON")
	assert_eq(mudao["equippable"], true)
	assert_eq(mudao["tab"], "WEAPON")
	var sm := c.to_summary(t)
	assert_eq(sm, { "char_id": "ch_00000001", "name": "測試俠客", "gender": "M", "sect_name": "少林", "combat_xp": 0, "room_name": "西夏廣場", "look": "shaolin_m" })  # M3c WP-LOOKS：summary 加 look

func test_sheet_kill_step_progress() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.quests["active"]["q_bandit"] = { "step": 0, "counts": { "m_bandit": 2 } }
	var q: Dictionary = c.to_sheet(t, F.options(), F.rules())["quests"][0]
	assert_eq(q["steps"][0]["have"], 2)
	assert_eq(q["steps"][0]["need"], 3)
	assert_eq(q["objectives"].size(), 1, "STORY_PLAN §4.14：只列目前階段的目標")
