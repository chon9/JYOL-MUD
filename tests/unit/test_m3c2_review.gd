extends "res://tests/unit/test_world_fixture.gd"
## M3c2 審查的回歸測試（節奏、防刷、雜務資料、經濟、介面小項）：
## - 新手期另看實戰（novice_xp_below）與雜務＋切磋學點的一輩子上限（novice_lp_cap）；老手學新武功不吃新手加速
## - 切磋一場最多 Learning.SPAR_LP_MAX 學點（新角色不會一場 75）
## - 少林幫農、學佛（研究 mengpai/1）、煮飯改由火工頭陀給；雜務 +30 熟練度標【待考證】；雜務的任務目標不再「撿柴：撿柴」
## - 打獵 10 級的額外掉落、製作窗的賣價小字
## - 學藝視窗的新手加速只寫一行（不帶【設計提案】）

const A := preload("res://tests/unit/test_m3c_npc_attack.gd")

func _join(sect := "wudang") -> bool:
	if not game_ok():
		return false
	if make_char("審查弟子", "dali") == null:
		return false
	ws.options["sect_hostile_entry"] = false
	ch().sect = sect
	ch().morality = 100
	host().sects.on_join(s(), sect, str(tables()["sects"][sect].get("head_npc", "")))
	make_strong()
	clear_events()
	return true

# ---------------------------------------------------------------- 新手期（審查 #4）

func test_rules_have_novice_xp_and_lifetime_cap() -> void:
	var rp: Dictionary = tables()["rule_profiles"]
	for pid in ["classic_standard", "later_official", "friends_casual", "classic_strict"]:
		var r: Dictionary = rp[pid]["rules"]
		assert_true(int(r.get("novice_xp_below", 0)) > 0, "%s novice_xp_below" % pid)
		assert_true(int(r.get("novice_lp_cap", 0)) > 0, "%s novice_lp_cap" % pid)
	assert_true(DataSchema.RULE_DEFAULTS.has("novice_xp_below") and DataSchema.RULE_DEFAULTS.has("novice_lp_cap"))

func test_veteran_learning_new_skill_gets_no_novice_bonus() -> void:
	var ch := Character.new()
	var rules := { "novice_learn_pct": 3000, "novice_jing_pct": 10, "novice_learn_below": 40, "novice_xp_below": 30000 }
	ch.combat_xp = 1000
	assert_eq(float(Learning.novice_mults(ch, "basic_parry", rules)["prof"]), 30.0, "novice")
	ch.combat_xp = 30000
	assert_eq(float(Learning.novice_mults(ch, "basic_parry", rules)["prof"]), 1.0, "veteran: no bonus even at level 0")
	assert_eq(float(Learning.novice_mults(ch, "basic_parry", rules)["jing"]), 1.0)

func test_is_novice_needs_low_xp_and_sect_switch_does_not_reset() -> void:
	var ch := Character.new()
	ch.sect = "shaolin"
	var rules := { "novice_learn_below": 40, "novice_xp_below": 30000 }
	assert_true(Learning.is_novice(ch, tables(), rules), "fresh disciple")
	ch.combat_xp = 50000   # 老手換門派：本派武功 0 級，但實戰很高
	assert_false(Learning.is_novice(ch, tables(), rules), "veteran who switched sects")
	ch.combat_xp = 0
	ch.skills.set_level("sl_changquan", 39, tables())   # 把本派武功壓在 39：實戰低還是新手，但有一輩子上限（下一個測試）
	assert_true(Learning.is_novice(ch, tables(), rules))

func test_lifetime_cap_stops_chore_lp() -> void:
	var ch := Character.new()
	ch.sect = "shaolin"
	var rules := { "chore_xuedian": true, "novice_learn_below": 40, "novice_xp_below": 30000, "novice_lp_cap": 100 }
	var chore := { "lp": 60, "decay_pct": [100, 60, 30, 0] }
	var g := Learning.chore_lp(chore, 0, ch, tables(), rules)
	assert_eq(int(g["lp"]), 60)
	Learning.note_novice_lp(ch, 60)
	g = Learning.chore_lp(chore, 0, ch, tables(), rules)
	assert_eq(int(g["lp"]), 40, "clamped to what is left of the lifetime cap")
	Learning.note_novice_lp(ch, 40)
	g = Learning.chore_lp(chore, 0, ch, tables(), rules)
	assert_eq(int(g["lp"]), 0)
	assert_eq(str(g["why"]), "novice", "cap reached → treated like the end of the novice period")

func test_host_chore_counts_toward_lifetime_cap() -> void:
	if not _join("shaolin"):
		return
	host().rules["novice_lp_cap"] = 10
	ch().counters["novice_lp"] = 0
	goto("sl_court")
	ok("quest_accept", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_saodi" })
	ok("story_act", { "act": "q_ch_sl_saodi:a_work" })
	var lp0: int = ch().learn_points
	ok("quest_turn_in", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_saodi" })
	assert_eq(int(ch().learn_points) - lp0, 10, "only 10 LP left in the lifetime cap")
	assert_eq(int(ch().counters.get("novice_lp", 0)), 10)

# ---------------------------------------------------------------- 切磋（審查 #3）

func test_spar_lp_per_fight_capped() -> void:
	if not _join("wudang"):
		return
	ch().combat_xp = 0
	goto("wd_square")
	Survival.rest_full(ch(), tables(), ws.options)
	var lp0: int = ch().learn_points
	ok("fight", { "npc": "n_wd_spar" })
	A.finish(self, 1, true)
	var got := int(ch().learn_points) - lp0
	assert_true(got > 0 and got <= Learning.SPAR_LP_MAX, "spar LP %d ≤ %d" % [got, Learning.SPAR_LP_MAX])
	assert_eq(Learning.spar_lp(75), Learning.SPAR_LP_MAX)
	assert_eq(int(ch().counters.get("novice_lp", 0)), got, "counts toward the lifetime cap")

# ---------------------------------------------------------------- 雜務資料（審查 #8、介面 #11）

func _quest(qid: String) -> Dictionary:
	return tables()["quests"].get(qid, {})

func test_shaolin_bangnong_and_xuefo_built() -> void:
	var bn := _quest("q_ch_sl_bangnong")
	var xf := _quest("q_ch_sl_xuefo")
	assert_false(bn.is_empty(), "幫農")
	assert_false(xf.is_empty(), "學佛")
	assert_eq(str(bn["chore"]["sect"]), "shaolin")
	assert_eq(int(bn["chore"]["cost"]["jing"]), 10, "研究：幫農 精 10")
	assert_true(bn["outcomes"]["default"]["rewards"]["skill_prof"].has("life_farming"))
	assert_eq(int(xf["chore"]["cost"]["shen"]), 15, "研究：學佛 神 15")
	assert_eq(str(bn["giver"]), "n_ch_sl_wunong")
	assert_eq(str(tables()["npcs"]["n_ch_sl_wunong"]["room"]), "sl_caiyuan")
	assert_eq(str(_quest("q_ch_sl_zhufan")["giver"]), "n_ch_sl_huogong", "煮飯：火工頭陀")
	assert_eq(str(tables()["npcs"]["n_ch_sl_huogong"]["name"]), "火工頭陀")

func test_shaolin_bangnong_flow() -> void:
	if not _join("shaolin"):
		return
	ch().skills.set_level("life_farming", 5, tables())
	goto("sl_caiyuan")
	ok("quest_accept", { "npc": "n_ch_sl_wunong", "quest": "q_ch_sl_bangnong" })
	ok("story_act", { "act": "q_ch_sl_bangnong:a_work" })
	var lp0: int = ch().learn_points
	var p0: int = ch().skills.prof("life_farming")
	ok("quest_turn_in", { "npc": "n_ch_sl_wunong", "quest": "q_ch_sl_bangnong" })
	assert_true(int(ch().learn_points) > lp0, "LP")
	assert_true(ch().skills.prof("life_farming") > p0, "農夫熟練")

func test_chore_prof_amounts_tagged_unverified() -> void:
	for qid in tables()["quests"]:
		var q: Dictionary = tables()["quests"][qid]
		if not (q.get("chore") is Dictionary) or not str(qid).begins_with("q_ch_"):
			continue   # 既有的早晚課、馬屁、練毒：熟練數字原本就標【設計提案】
		var sp: Variant = q.get("outcomes", {}).get("default", {}).get("rewards", {}).get("skill_prof", {})
		if sp is Dictionary and not (sp as Dictionary).is_empty():
			assert_true(str(q.get("src_note", "")).contains("【待考證】"), "%s src_note marks the proficiency amount" % qid)
			assert_true(str(q["chore"].get("src_note", "")).contains("【待考證】"), "%s chore.src_note" % qid)

func test_chore_work_stage_title_differs_from_quest_name() -> void:
	for qid in tables()["quests"]:
		var q: Dictionary = tables()["quests"][qid]
		if str(q.get("group", "")) != "sect_chores":
			continue
		for st in q.get("stages", []):
			if st is Dictionary:
				assert_true(str(st.get("title", "")) != str(q.get("name", "")), "%s stage %s title repeats the quest name" % [qid, str(st.get("id", ""))])

# ---------------------------------------------------------------- 經濟（審查 #5、#6、介面 #2）

func test_hunting_extra_drops_need_level() -> void:
	var row: Dictionary = tables()["life_skills"]["life_hunting"]
	var lv10 := {}
	for d in row["hunt"]["drops"]:
		if 10 >= int(d.get("min_level", 1)):
			lv10[str(d["item"])] = true
	for iid in ["r_yerou", "r_shoupi", "r_pork"]:
		assert_false(lv10.has(iid), "%s not from a level-10 hunter" % iid)
	assert_true(int(row["jing_cost"]) >= 13)

func test_craft_products_excludes_gathered_items() -> void:
	var cp := EconModel.craft_products(tables(), ["life_farming", "life_weaving", "life_tailoring"], ["life_farming"])
	assert_false(cp.has("r_ma"), "種麻收的麻是原料")
	assert_true(cp.has("a_cubudaopao"), "粗布道袍 is a crafted product")

func test_craft_window_value_text() -> void:
	var items := { "o": { "price": 100 }, "i": { "price": 10 }, "t_x": { "price": 999 } }
	var v := EconUi.recipe_values({ "inputs": [{ "item": "i", "n": 2 }, { "item": "t_x", "n": 1 }], "output": { "item": "o", "n": 1 } }, items)
	assert_eq(int(v["out"]), 30)
	assert_eq(int(v["inputs"]), 6, "tools not counted")
	assert_eq(EconUi.values_text(v), "收購價約 30 兩（材料約 6 兩）")
	assert_eq(EconUi.values_text({ "out": 0, "inputs": 0 }), "")

# ---------------------------------------------------------------- 介面（審查 介面 #9）

func test_learn_dialog_novice_header_no_internal_tag() -> void:
	var r := { "novice_learn_pct": 3000, "novice_jing_pct": 10, "novice_learn_below": 40, "novice_xp_below": 30000 }
	assert_false(LearnDialog.novice_tip(r).contains("【"), "no internal tag in player text")
	assert_false(LearnDialog.novice_header(r).contains("【"))
	assert_true(LearnDialog.novice_header(r).contains("40"))
	assert_true(LearnDialog.novice_applies("ART", 10, r, 1000))
	assert_false(LearnDialog.novice_applies("ART", 10, r, 30000), "veteran")
