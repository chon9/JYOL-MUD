extends "res://tests/test_case.gd"
## STORY_PLAN §9.1 test_quest_def：既有任務（舊 steps 格式）正規化成第 2 版的結果；validate 抓得到各種錯誤列。
## 方法名 test_story_*（--filter=story）。

const V2 := preload("res://tests/unit/test_world_quest_v2.gd")

func _tables() -> Dictionary:
	return GameData.tables

func test_story_legacy_rows_normalize() -> void:
	var raw: Dictionary = GameData.loader.all_tables["quests"]
	assert_true(raw.size() >= 14, "既有任務")
	for qid in raw:
		var row: Dictionary = raw[qid]
		if not row.has("steps"):
			continue
		var q := QuestDef.normalize(row)
		assert_eq(int(q["v"]), 2, qid)
		assert_true(bool(q["_legacy"]), qid)
		assert_eq((q["stages"] as Array).size(), (row["steps"] as Array).size(), qid + " 每步一個階段")
		assert_eq(q["start"], "step_0", qid)
		assert_true(q["outcomes"].has("default"), qid)
		assert_eq(q["steps"], row["steps"], qid + " 舊欄位保留")
		assert_eq(QuestDef.validate(row, _tables()), PackedStringArray(), qid + " 舊列通過 validate")
		assert_eq(QuestDef.validate(q, _tables()), PackedStringArray(), qid + " 正規化後也通過")
	# 生效視圖裡已經是第 2 版
	for qid in GameData.tables["quests"]:
		assert_true(GameData.tables["quests"][qid].has("stages"), qid + " 生效表已正規化")

func test_story_legacy_bandit_shape() -> void:
	var q := QuestDef.normalize(GameData.loader.all_tables["quests"]["q_bandit"])
	assert_eq(q["stages"][0]["id"], "step_0")
	assert_eq(q["stages"][0]["objectives"][0]["id"], "o")
	assert_eq(q["stages"][0]["objectives"][0]["type"], "KILL")
	assert_eq(q["stages"][0]["objectives"][0]["monster"], "m_bandit")
	assert_eq(int(q["stages"][0]["objectives"][0]["count"]), 3)
	assert_eq(q["stages"][0]["next"], [{ "goto": "step_1" }])
	assert_eq(q["stages"][1]["objectives"][0]["npc"], "n_dl_bukuai")
	assert_eq(q["stages"][1]["next"], [{ "goto": "END:default" }])
	assert_eq(int(q["outcomes"]["default"]["rewards"]["morality"]), 10)
	assert_eq(q["repeat"], { "max": 1, "cooldown_days": 0.0 })
	assert_true(bool(q["party_credit"]), "舊任務正規化時 party_credit 預設 true（行為變更）")
	var letter := QuestDef.normalize(GameData.loader.all_tables["quests"]["q_letter"])
	assert_eq(letter["repeat"], { "max": 0, "cooldown_days": 0.0 }, "repeatable: true → 無限")
	assert_eq(letter["stages"][0]["objectives"][0]["item"], "i_letter")
	assert_true(bool(letter["stages"][0]["objectives"][0]["consume"]))
	var hs := QuestDef.normalize(GameData.loader.all_tables["quests"]["q_hs_kaoyan"])
	assert_eq(hs["outcomes"]["default"]["rewards"]["flags"], ["hs_trial_passed"])

func test_story_fixture_validates() -> void:
	var errs := QuestDef.validate(V2.fixture_quest(), _tables())
	assert_eq(errs, PackedStringArray(), "\n".join(errs))
	assert_eq(QuestDef.validate(V2.fixture_repeat(), _tables()), PackedStringArray())

func _bad(mut: Callable) -> PackedStringArray:
	var q := V2.fixture_quest()
	mut.call(q)
	return QuestDef.validate(q, _tables())

func _has_err(errs: PackedStringArray, needle: String) -> bool:
	for e in errs:
		if needle in e:
			return true
	fail("expected an error containing '%s' in %s" % [needle, str(errs)])
	return false

func test_story_validate_catches_errors() -> void:
	_has_err(_bad(func(q): q["steps"] = []), "mutually exclusive")
	_has_err(_bad(func(q): q["start"] = "nope"), "start 'nope'")
	_has_err(_bad(func(q): q["stages"][0]["next"] = "s_missing"), "s_missing")
	_has_err(_bad(func(q): q["stages"][0]["next"] = "END:zzz"), "END:zzz")
	_has_err(_bad(func(q): q["stages"][8]["next"] = [{ "if": [{ "type": "fame_min", "value": 1 }], "goto": "END:a" }]), "unconditional")
	_has_err(_bad(func(q): q["stages"][0]["objectives"][0]["type"] = "DANCE"), "bad objective type")
	_has_err(_bad(func(q): q["stages"][0]["objectives"][0]["npc"] = "n_nobody"), "n_nobody")
	_has_err(_bad(func(q): q["stages"][1]["objectives"][0]["item"] = "i_nothing"), "i_nothing")
	_has_err(_bad(func(q): q["stages"][3]["objectives"][0]["monster"] = "m_none"), "m_none")
	_has_err(_bad(func(q): q["stages"][5]["objectives"][0]["room"] = "zz_room"), "zz_room")
	_has_err(_bad(func(q): q["stages"][4]["objectives"][0]["win"] = "MAYBE"), "FIGHT win")
	_has_err(_bad(func(q): q["stages"][4]["room_actions"][0]["do"][0]["monsters"] = ["m_zz_nope"]), "m_zz_nope")
	_has_err(_bad(func(q): q["stages"][4]["room_actions"][2]["hours"] = ["午時"]), "bad shichen")
	_has_err(_bad(func(q): q["dialogues"]["d_zhang"]["start"] = "nx"), "start node 'nx'")
	_has_err(_bad(func(q): q["dialogues"]["d_zhang"]["nodes"]["n0"]["goto"] = "n_gone"), "n_gone")
	_has_err(_bad(func(q): q["dialogues"]["d_zhang"]["nodes"]["n_pick"]["choices"][0]["do"].append({ "do": "dance" })), "unknown action")
	_has_err(_bad(func(q): q["dialogues"]["d_zhang"]["nodes"]["n_pick"]["choices"][0]["do"].append({ "do": "complete", "obj": "o_none" })), "o_none")
	_has_err(_bad(func(q): q["dialogues"]["d_zhang"]["nodes"]["n_pick"]["choices"][0]["do"].append({ "do": "flag", "flag": "x" })), "flag 'x'")
	_has_err(_bad(func(q): q["dialogues"]["d_zhang"]["nodes"]["n_pick"]["choices"][0]["do"].append({ "do": "learn", "skill": "no_skill", "level": 1 })), "no_skill")
	_has_err(_bad(func(q): q["dialogues"]["d_zhang"]["nodes"]["n_pick"]["choices"][1]["id"] = "c_a"), "duplicate")
	_has_err(_bad(func(q): q["outcomes"]["a"]["rewards"]["gold"] = 1), "unknown reward key")
	_has_err(_bad(func(q): q["outcomes"].erase("b")), "END:b")
	_has_err(_bad(func(q): q["offer"] = "d_none"), "offer dialogue")
	_has_err(_bad(func(q): q["requires"] = [{ "type": "quest_stage", "quest": "q_x" }]), "missing field 'stage'")

func test_story_validate_graph() -> void:
	# 走不到的階段
	_has_err(_bad(func(q): q["stages"].append({ "id": "s_orphan", "objectives": [{ "id": "o", "type": "REACH", "room": "xx_square" }], "next": "END:a" })), "unreachable")
	# 死循環：兩個階段互相指、沒有出口
	var loop := {
		"id": "q_t_loop", "name": "迴圈", "giver": "n_wujieshan", "era": "1.0A",
		"stages": [
			{ "id": "s1", "objectives": [{ "id": "o", "type": "REACH", "room": "xx_square" }], "next": "s2" },
			{ "id": "s2", "objectives": [{ "id": "o", "type": "REACH", "room": "xx_inn" }], "next": "s1" }],
		"outcomes": {},
	}
	_has_err(QuestDef.validate(loop, _tables()), "never reach END")
	assert_eq(QuestDef.validate({ "id": "q_x" }, _tables()).size(), 1, "沒有 stages 也沒有 steps")

func test_story_normalize_defaults() -> void:
	var q := QuestDef.normalize({ "id": "q_min", "stages": [
		{ "id": "a", "objectives": [{ "id": "o", "type": "TALK", "npc": "n_wujieshan" }] },
		{ "id": "b", "objectives": [{ "id": "o", "type": "TALK", "npc": "n_wujieshan" }] }] })
	assert_eq(q["start"], "a")
	assert_eq(q["stages"][0]["next"], [{ "goto": "b" }], "沒寫 next → 下一個階段")
	assert_eq(q["stages"][1]["next"], [{ "goto": "END:default" }], "最後一個 → END")
	assert_eq(q["repeat"], { "max": 1, "cooldown_days": 0.0 })
	assert_true(bool(q["abandon"]))
	assert_true(bool(q["party_credit"]))
	assert_eq(QuestDef.norm_goto("END"), "END:default")
	assert_true(QuestDef.is_end("END:x"))
	assert_eq(QuestDef.outcome_of("END:x"), "x")
	assert_eq(QuestDef.outcome_of("END"), "default")
	assert_true(QuestDef.flag_name_ok("hs_qizong"))
	assert_true(QuestDef.flag_name_ok("lf_done"))
	assert_false(QuestDef.flag_name_ok("x"))
	assert_false(QuestDef.flag_name_ok("_x"))
