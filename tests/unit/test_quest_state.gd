extends "res://tests/test_case.gd"
## STORY_PLAN §9.1 test_quest_state：舊存檔遷移（{step,counts}、done:int）；目標進度計算。方法名 test_story_*。

const F := preload("res://tests/unit/test_character_fixtures.gd")
const V2 := preload("res://tests/unit/test_world_quest_v2.gd")

func test_story_migrate_legacy_save() -> void:
	var old := { "active": { "q_bandit": { "step": 1, "counts": { "m_bandit": 3 } }, "q_rabbit": { "step": 0, "counts": {} } },
		"done": { "q_rice": 2, "q_letter": 0 } }
	var m := QuestState.migrate(old)
	assert_eq(m["active"]["q_bandit"], { "v": 2, "stage": "step_1", "objs": { "o": 3 }, "vars": {},
		"since_world_s": 0.0, "stage_since_world_s": 0.0, "escort": "" })
	assert_eq(m["active"]["q_rabbit"]["objs"], {}, "沒有計數 → 空")
	assert_eq(m["done"]["q_rice"], { "n": 2, "outcome": "default", "world_s": 0.0, "failed": 0 })
	assert_false(m["done"].has("q_letter"), "0 次的舊紀錄丟掉")
	assert_eq(m["cd"], {})
	assert_true(old["active"]["q_bandit"].has("step"), "輸入不動")

func test_story_migrate_json_floats_and_idempotent() -> void:
	var cur := { "active": { "q": { "v": 2, "stage": "s", "objs": { "o": 2.0 }, "vars": { "n": 3.0, "f": 1.5, "s": "x", "b": true },
		"since_world_s": 5, "stage_since_world_s": 6.0, "escort": "n_a" } },
		"done": { "q2": { "n": 1.0, "outcome": "abao", "world_s": 9.0, "failed": 2.0 } }, "cd": { "q2": 100 } }
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(cur))
	var m := QuestState.migrate(parsed)
	assert_type(m["active"]["q"]["objs"]["o"], TYPE_INT)
	assert_type(m["active"]["q"]["vars"]["n"], TYPE_INT)
	assert_type(m["active"]["q"]["vars"]["f"], TYPE_FLOAT)
	assert_eq(m["active"]["q"]["vars"]["b"], true)
	assert_eq(m["active"]["q"]["escort"], "n_a")
	assert_type(m["done"]["q2"]["n"], TYPE_INT)
	assert_eq(m["done"]["q2"]["outcome"], "abao")
	assert_eq(m["cd"]["q2"], 100.0)
	assert_eq(QuestState.migrate(m), m, "新格式再遷移不變")

func test_story_ensure_in_place_and_queries() -> void:
	var q := { "active": { "q_bandit": { "step": 0, "counts": { "m_bandit": 1 } } }, "done": { "q_rice": 1 } }
	assert_eq(QuestState.done_count(q, "q_rice"), 1, "查詢可讀舊格式")
	assert_eq(QuestState.active_entry(q, "q_bandit")["stage"], "step_0")
	QuestState.ensure(q)
	assert_eq(q["active"]["q_bandit"]["stage"], "step_0")
	assert_eq(q["done"]["q_rice"]["n"], 1)
	assert_true(q.has("cd"))
	q["done"]["q_rice"]["outcome"] = "li"
	assert_eq(QuestState.last_outcome(q, "q_rice"), "li")
	assert_eq(QuestState.last_outcome(q, "q_none"), "")
	assert_true(QuestState.is_active(q, "q_bandit"))
	assert_false(QuestState.is_active(q, "q_rice"))
	assert_true(QuestState.value_eq(1, 1.0))
	assert_true(QuestState.value_eq("a", "a"))
	assert_false(QuestState.value_eq("1", 2))
	assert_true(QuestState.value_eq(true, true))

func test_story_character_from_dict_migrates() -> void:
	var c := F.new_char()
	var d := c.to_dict()
	d["quests"] = { "active": { "q_bandit": { "step": 1, "counts": { "m_bandit": 3 } } }, "done": { "q_rabbit": 1 } }
	d.erase("lilian")
	d.erase("ext")
	var c2 := Character.from_dict(d)
	assert_eq(c2.quests["active"]["q_bandit"]["stage"], "step_1")
	assert_eq(c2.quests["done"]["q_rabbit"]["n"], 1)
	assert_eq(c2.lilian, 0, "舊檔沒有 lilian")
	assert_eq(c2.ext, {})
	# 遷移後的條件判定
	assert_true(Requirements.ok([{ "type": "quest_done", "quest": "q_rabbit" }], c2, F.tables(), F.options(), F.rules()))
	assert_true(Requirements.ok([{ "type": "quest_active", "quest": "q_bandit" }], c2, F.tables(), F.options(), F.rules()))
	assert_true(Requirements.ok([{ "type": "quest_stage", "quest": "q_bandit", "stage": ["step_0", "step_1"] }], c2, F.tables(), F.options(), F.rules()))
	assert_false(Requirements.ok([{ "type": "quest_stage", "quest": "q_bandit", "stage": "step_0" }], c2, F.tables(), F.options(), F.rules()))
	assert_true(Requirements.ok([{ "type": "quest_outcome", "quest": "q_rabbit", "outcome": "default" }], c2, F.tables(), F.options(), F.rules()))

func test_story_new_condition_types() -> void:
	var c := F.new_char()
	var t := F.tables()
	c.quests["active"]["q_t"] = { "v": 2, "stage": "s", "objs": {}, "vars": { "pick": "abao", "n": 2 }, "since_world_s": 0.0,
		"stage_since_world_s": 0.0, "escort": "" }
	assert_true(Requirements.ok([{ "type": "quest_var", "quest": "q_t", "var": "pick", "value": "abao" }], c, t, F.options(), F.rules()))
	assert_false(Requirements.ok([{ "type": "quest_var", "quest": "q_t", "var": "pick", "value": "li" }], c, t, F.options(), F.rules()))
	assert_true(Requirements.ok([{ "type": "quest_var", "quest": "q_t", "var": "n", "value": 2.0 }], c, t, F.options(), F.rules()))
	assert_false(Requirements.ok([{ "type": "quest_var", "quest": "q_t", "var": "zz", "value": "" }], c, t, F.options(), F.rules()))
	c.lilian = 10
	c.fame = 100
	c.combat_xp = 400
	assert_true(Requirements.ok([{ "type": "lilian_min", "value": 10 }, { "type": "fame_min", "value": 100 },
		{ "type": "combat_xp_max", "value": 499 }], c, t, F.options(), F.rules()))
	assert_eq(Requirements.check([{ "type": "lilian_min", "value": 11 }], c, t, F.options(), F.rules()), "req_lilian_min")
	assert_eq(Requirements.check([{ "type": "combat_xp_max", "value": 399 }], c, t, F.options(), F.rules()), "req_combat_xp_max")
	for cond in [{ "type": "lilian_min", "value": 5 }, { "type": "fame_min", "value": 5 }, { "type": "combat_xp_max", "value": 5 },
			{ "type": "quest_active", "quest": "q_rabbit" }, { "type": "quest_stage", "quest": "q_rabbit", "stage": "a" },
			{ "type": "quest_var", "quest": "q_rabbit", "var": "a", "value": 1 }, { "type": "quest_outcome", "quest": "q_rabbit", "outcome": "x" }]:
		assert_true(Requirements.describe(cond, t) != "特殊條件", str(cond))
		assert_eq(DataSchema.check_conditions([cond], "t"), PackedStringArray(), str(cond))

func test_story_objective_progress() -> void:
	var c := F.new_char()
	var t := GameData.tables
	var def := QuestDef.normalize(V2.fixture_quest())
	var st := { "stage": "s_collect", "objs": { "o_buy": 0 } }
	c.inventory.add("c_water", 1, t, 0.0, 9999, func(): return "it_t1")
	var p := QuestState.objective_progress(def, st, c, t)
	assert_eq(p, [{ "id": "o_col", "text": "帶 2 份清水", "have": 1, "need": 2, "done": false },
		{ "id": "o_buy", "text": "買金創藥", "have": 0, "need": 1, "done": false }])
	st = { "stage": "s_deliver", "objs": {} }
	assert_eq(QuestState.objective_progress(def, st, c, t)[0]["have"], 0)
	st["objs"]["o_dv"] = 1
	assert_eq(QuestState.objective_progress(def, st, c, t)[0], { "id": "o_dv", "text": "交 2 個饅頭", "have": 2, "need": 2, "done": true })
	st = { "stage": "s_kill", "objs": { "o_k": 5 } }
	assert_eq(QuestState.objective_progress(def, st, c, t)[0]["have"], 2, "不超過 need")
	st = { "stage": "s_reach", "objs": {} }
	assert_eq(QuestState.objective_progress(def, st, c, t)[0], { "id": "o_r", "text": "到驛站", "have": 0, "need": 1, "done": false })
	assert_eq(QuestState.objective_progress(def, { "stage": "nope" }, c, t), [])
