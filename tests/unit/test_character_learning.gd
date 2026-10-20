extends "res://tests/test_case.gd"
## WP-CHAR：4.3 熟練度曲線、4.5 悟性表與學武驗證順序、自修、16 套上限、生活技能。

const F := preload("res://tests/unit/test_character_fixtures.gd")

var t: Dictionary
var o: Dictionary
var r: Dictionary

func before_each() -> void:
	t = F.tables()
	o = F.options()
	r = F.rules()

func _shaolin() -> Character:
	var c := F.new_char()
	c.sect = "shaolin"
	c.combat_xp = 100000
	return c

# ------------------------------------------------------------ 曲線

func _levels(skill: String) -> Array:
	return [1, 2, 5, 10].map(func(L): return SkillBook.prof_for_level(skill, L, t))

func test_curve_cubic() -> void:
	assert_eq(_levels("basic_fist"), [1, 8, 113, 900], "CUBIC 0.9")
	assert_eq(_levels("hs_jianfa"), [1, 7, 100, 800], "ART difficulty 0.8")
	assert_eq(_levels("foxa"), [1, 8, 125, 1000], "SECT 1.0")

func test_curve_quartic() -> void:
	assert_eq(_levels("basic_inner"), [1, 13, 500, 8000])

func test_curve_literacy() -> void:
	assert_eq(_levels("basic_literacy"), [90, 250, 1350, 6450])

func test_curve_life() -> void:
	assert_eq(_levels("life_farming"), [2, 8, 50, 200])

func test_level_for_prof_and_set_level() -> void:
	assert_eq(SkillBook.level_for_prof("basic_fist", 0, t), 0)
	assert_eq(SkillBook.level_for_prof("basic_fist", 112, t), 4)
	assert_eq(SkillBook.level_for_prof("basic_fist", 113, t), 5)
	assert_eq(SkillBook.level_for_prof("foxa", 999999999, t), 100, "sect cap 100")
	var b := SkillBook.new()
	b.set_level("basic_inner", 5, t)
	assert_eq(b.entries["basic_inner"], { "level": 5, "prof": 500 })
	b.set_level("basic_inner", 0, t)
	assert_false(b.has("basic_inner"))

func test_add_prof_cap_level_keeps_prof() -> void:
	var b := SkillBook.new()
	var res := b.add_prof("basic_fist", 1000, t, 5)
	assert_eq(res, { "before": 0, "after": 5, "prof": 1000 })
	res = b.add_prof("basic_fist", 0, t, 20)
	assert_eq(res["after"], 10, "raised cap releases stored prof")

func test_kind_and_name() -> void:
	assert_eq(SkillBook.kind_of("basic_fist", t), "BASIC")
	assert_eq(SkillBook.kind_of("sl_changquan", t), "ART")
	assert_eq(SkillBook.kind_of("foxa", t), "SECT")
	assert_eq(SkillBook.kind_of("life_farming", t), "LIFE")
	assert_eq(SkillBook.kind_of("nope", t), "")
	assert_eq(SkillBook.skill_name("foxa", t), "佛法")
	assert_eq(SkillBook.skill_name("life_farming", t), "種田")

func test_special_arts_and_highest() -> void:
	var b := SkillBook.new()
	b.set_level("sl_changquan", 20, t)
	b.set_level("sl_luohanquan", 20, t)
	b.set_level("sl_xinfa", 5, t)
	b.set_level("mon_bite", 50, t)
	b.set_level("basic_fist", 90, t)
	assert_eq(b.special_arts(t), ["sl_changquan", "sl_luohanquan", "sl_xinfa"], "monster_only excluded")
	assert_eq(b.highest_special_art(t), "sl_changquan", "tie → id order")
	b.add_prof("sl_luohanquan", 1, t, 250)
	assert_eq(b.highest_special_art(t), "sl_luohanquan", "tie → prof")
	assert_eq(SkillBook.new().highest_special_art(t), "")
	assert_eq(b.best_level_in_category("INNER", t), 5)

# ------------------------------------------------------------ 悟性表

func test_wit_cost_table() -> void:
	assert_eq(Learning.wit_cost(21), { "jing": 10, "prof": 11 })
	assert_eq(Learning.wit_cost(30), { "jing": 5, "prof": 15 })
	assert_eq(Learning.wit_cost(40), { "jing": 2, "prof": 20 })
	assert_eq(Learning.wit_cost(25), { "jing": 8, "prof": 13 }, "interp 21-30")
	assert_eq(Learning.wit_cost(15), { "jing": 13, "prof": 8 }, "below 21")
	assert_eq(Learning.wit_cost(3), { "jing": 15, "prof": 5 }, "clamped low")
	assert_eq(Learning.wit_cost(35), { "jing": 4, "prof": 18 }, "interp 30-40")
	assert_eq(Learning.wit_cost(50), { "jing": 1, "prof": 25 }, "above 40")

# ------------------------------------------------------------ 驗證順序

func test_reason_not_taught() -> void:
	assert_eq(Learning.check_master(_shaolin(), "n_zhike", "sl_changquan", t, o, r), "not_taught")

func test_reason_master_requires() -> void:
	var c := F.new_char()
	c.combat_xp = 100000
	assert_eq(Learning.check_master(c, "n_huizhen", "sl_changquan", t, o, r), "req_sect")
	c.sect = "shaolin"
	assert_eq(Learning.check_master(c, "n_huizhen", "sl_changquan", t, o, r), "req_skill_min", "佛法未達 10")
	c.skills.set_level("foxa", 10, t)
	assert_eq(Learning.check_master(c, "n_huizhen", "sl_changquan", t, o, r), "")

func test_reason_art_requires() -> void:
	var c := F.new_char()
	c.sect = "huashan"
	assert_eq(Learning.check_master(c, "n_huizhen", "sl_luohanquan", t, o, r), "req_sect", "art's own requires")

func test_reason_cap_arts16() -> void:
	var c := _shaolin()
	for i in 16:
		var id := "fa_%02d" % i
		t["martial_arts"][id] = { "id": id, "name": id, "category": "FIST", "difficulty": 0.9, "requires": [] }
		c.skills.set_level(id, 1, t)
	assert_eq(c.skills.special_arts(t).size(), 16)
	assert_eq(Learning.check_master(c, "n_huizhen", "sl_luohanquan", t, o, r), "cap_arts16")
	var res := Learning.learn(c, "n_huizhen", "sl_luohanquan", 1, t, o, r)
	assert_eq(res["ok"], false)
	assert_eq(res["reason"], "cap_arts16")
	# 已會的武功不受影響
	t["masters"]["ms_fa"] = { "id": "ms_fa", "npc_id": "n_huizhen", "skill_id": "fa_00", "cap": 100, "price": 0, "requires": [] }
	assert_eq(Learning.check_master(c, "n_huizhen", "fa_00", t, o, r), "")

func test_reason_need_self_study() -> void:
	var c := _shaolin()
	assert_eq(Learning.check_master(c, "n_selfm", "x_selfart", t, o, r), "need_self_study")
	c.skills.set_level("x_selfart", 3, t)
	assert_eq(Learning.check_master(c, "n_selfm", "x_selfart", t, o, r), "")

func test_reason_cap_master_and_cap_xp() -> void:
	var c := _shaolin()
	c.skills.set_level("basic_fist", 30, t)
	assert_eq(Learning.check_master(c, "n_wushi", "basic_fist", t, o, r), "cap_master")
	var n := F.new_char()
	n.skills.set_level("basic_fist", 5, t)
	assert_eq(Learning.check_master(n, "n_wushi", "basic_fist", t, o, r), "cap_xp", "實戰 0 → 上限 5")
	n.skills.set_level("basic_fist", 4, t)
	assert_eq(Learning.check_master(n, "n_wushi", "basic_fist", t, o, r), "")

func test_reason_resources() -> void:
	var c := _shaolin()
	c.learn_points = 0
	assert_eq(Learning.learn(c, "n_wushi", "basic_fist", 1, t, o, r)["reason"], "not_enough_lp")
	c = _shaolin()
	c.vitals["jing"] = 9
	assert_eq(Learning.learn(c, "n_wushi", "basic_fist", 1, t, o, r)["reason"], "not_enough_jing")
	c = _shaolin()
	c.vitals["neili"] = 0
	assert_eq(Learning.learn(c, "n_zhike", "foxa", 1, t, o, r)["reason"], "not_enough_neili")
	c = _shaolin()
	c.sect = ""
	c.vitals["shen"] = 1
	assert_eq(Learning.learn(c, "n_yue", "rufeng", 1, t, o, r)["reason"], "not_enough_shen")
	c = _shaolin()
	c.money = 4
	assert_eq(Learning.learn(c, "n_wushi", "basic_fist", 1, t, o, r)["reason"], "not_enough_money")

func test_learn_success_costs() -> void:
	var c := _shaolin()
	c.vitals["neili"] = 10
	var res := Learning.learn(c, "n_zhike", "foxa", 3, t, o, r)
	assert_eq(res["ok"], true)
	assert_eq(res["times_done"], 3)
	assert_eq(res["prof_gain"], 33, "wit 21 → 11 per time")
	assert_eq(res["lp_cost"], 3)
	assert_eq(res["jing_cost"], 30)
	assert_eq(res["neili_cost"], 3, "sect skill costs neili 1")
	assert_eq(res["shen_cost"], 0)
	assert_eq(res["level_before"], 0)
	assert_eq(res["level_after"], 3, "33 prof → foxa 3 (27 ≤ 33 < 64)")
	assert_eq(c.learn_points, 97)
	assert_eq(c.vitals["neili"], 7)
	assert_eq(c.vitals["jing"], 92 - 30)

func test_learn_wuguan_price() -> void:
	var c := _shaolin()
	var res := Learning.learn(c, "n_wushi", "basic_fist", 2, t, o, r)
	assert_eq(res["money_cost"], 10)
	assert_eq(c.money, 90)

func test_learn_times_stops_midway() -> void:
	var c := _shaolin()
	c.vitals["jing"] = 35
	var res := Learning.learn(c, "n_wushi", "basic_fist", 10, t, o, r)
	assert_eq(res["ok"], true)
	assert_eq(res["times_done"], 3)
	assert_eq(res["stopped_reason"], "not_enough_jing")
	assert_eq(res["reason"], "")
	assert_eq(c.vitals["jing"], 5)

func test_learn_stops_at_xp_cap() -> void:
	var c := F.new_char()
	c.vitals["jing"] = 999
	c.learn_points = 1000
	var res := Learning.learn(c, "n_huizhen", "basic_inner", 10, t, o, r)
	# 11 熟練度/次；QUARTIC 等級 5 需要 500 → 10 次只有 110 → 等級 3
	assert_eq(res["times_done"], 10)
	assert_eq(res["level_after"], 3)
	c.skills.set_level("basic_inner", 5, t)
	res = Learning.learn(c, "n_huizhen", "basic_inner", 10, t, o, r)
	assert_eq(res["ok"], false)
	assert_eq(res["reason"], "cap_xp")
	# 熟練度超出上限時等級停在上限
	var c2 := F.new_char()
	c2.skills.set_level("basic_fist", 4, t)
	c2.skills.add_prof("basic_fist", 112 - c2.skills.prof("basic_fist"), t, 5)
	c2.vitals["jing"] = 999
	res = Learning.learn(c2, "n_wushi", "basic_fist", 10, t, o, r)
	assert_eq(res["level_after"], 5)
	assert_eq(res["times_done"], 1)
	assert_eq(res["stopped_reason"], "cap_xp")

# ------------------------------------------------------------ 自修

func test_self_study() -> void:
	var c := F.new_char()
	c.combat_xp = 10000
	var res := Learning.self_study(c, "basic_sword", 1, t, o, r)
	assert_eq(res["reason"], "not_known")
	c.skills.set_level("basic_fist", 1, t)
	res = Learning.self_study(c, "basic_fist", 4, t, o, r)
	assert_eq(res["ok"], true)
	assert_eq(res["times_done"], 4)
	assert_eq(res["prof_gain"], 20, "⌊悟性 21/4⌋ = 5 per time")
	assert_eq(res["lp_cost"], 4)
	assert_eq(res["jing_cost"], 40)
	assert_eq(c.skills.prof("basic_fist"), 21)

func test_self_study_until_art() -> void:
	var c := F.new_char()
	c.combat_xp = 10000
	c.vitals["jing"] = 999
	var res := Learning.self_study(c, "x_selfart", 10, t, o, r)
	assert_eq(res["ok"], true, "self_study_until > 0 allows level 0")
	assert_eq(res["level_after"], 3)

func test_cap_sect_skill_shaolin() -> void:
	var c := _shaolin()
	c.skills.set_level("foxa", 10, t)
	c.skills.set_level("sl_changquan", 19, t)
	c.vitals["jing"] = 99999
	c.vitals["neili"] = 99999
	c.learn_points = 99999
	assert_eq(Learning.sect_skill_cap(c, "sl_changquan", t), 20, "佛法 10 + 10")
	assert_eq(Learning.sect_skill_cap(c, "foxa", t), Learning.ABSOLUTE_MAX_LEVEL, "門派技能本身不受限")
	assert_eq(Learning.sect_skill_cap(c, "basic_fist", t), Learning.ABSOLUTE_MAX_LEVEL, "基本功不受限")
	assert_eq(Learning.check_master(c, "n_huizhen", "sl_changquan", t, o, r), "")
	var res := Learning.learn(c, "n_huizhen", "sl_changquan", 500, t, o, r)
	assert_eq(res["ok"], true)
	assert_eq(res["level_after"], 20)
	assert_eq(res["stopped_reason"], "cap_sect_skill")
	assert_eq(Learning.check_master(c, "n_huizhen", "sl_changquan", t, o, r), "cap_sect_skill")
	assert_eq(Learning.self_study(c, "sl_changquan", 1, t, o, r)["reason"], "cap_sect_skill")
	c.skills.set_level("foxa", 11, t)
	assert_eq(Learning.check_master(c, "n_huizhen", "sl_changquan", t, o, r), "", "佛法升級後上限放寬")
	# 非本門弟子（或門派沒有此限制）不受影響
	c.sect = "huashan"
	assert_eq(Learning.sect_skill_cap(c, "sl_changquan", t), Learning.ABSOLUTE_MAX_LEVEL)

func test_self_study_caps() -> void:
	var c := F.new_char()
	c.skills.set_level("basic_fist", 5, t)
	assert_eq(Learning.self_study(c, "basic_fist", 1, t, o, r)["reason"], "cap_xp")
	c.combat_xp = 100000
	c.skills.set_level("basic_fist", 30, t)
	assert_eq(Learning.self_study(c, "basic_fist", 1, t, o, r)["reason"], "cap_master", "不超過師父最高 cap")
	c.skills.set_level("hs_jianfa", 1, t)
	c.sect = "huashan"
	assert_eq(Learning.self_study(c, "hs_jianfa", 1, t, o, r)["reason"], "cap_master", "沒有師父 → martial_arts.self_study_cap 0")
	assert_eq(Learning.self_study_cap(c, "basic_fist", t, r), 30)
	assert_eq(Learning.self_study_cap(c, "basic_fist", t, { "self_study_cap": "HJ_1_5X" }), 45)
	assert_eq(Learning.self_study_cap(c, "x_selfart", t, r), 40)

# ------------------------------------------------------------ 生活技能

func test_learn_life() -> void:
	var c := F.new_char()
	var res := Learning.learn_life(c, "n_taoyun", "life_farming", t)
	assert_eq(res, { "ok": true, "reason": "", "money_cost": 50, "tool_item": "t_chutou" })
	assert_eq(c.money, 50)
	assert_eq(c.skills.level("life_farming"), 1)
	assert_eq(Learning.learn_life(c, "n_taoyun", "life_farming", t)["reason"], "already_known")
	assert_eq(Learning.learn_life(c, "n_taoyun", "basic_fist", t)["reason"], "not_taught")
	var poor := F.new_char()
	poor.money = 10
	assert_eq(Learning.learn_life(poor, "n_taoyun", "life_farming", t)["reason"], "not_enough_money")
	var has_tool := F.new_char()
	has_tool.inventory.add("t_chutou", 1, t, 0.0, -1, F.uid_maker())
	assert_eq(Learning.learn_life(has_tool, "n_taoyun", "life_farming", t)["tool_item"], "", "tool not given twice")

func test_practice_life() -> void:
	var c := F.new_char()
	c.skills.set_level("life_farming", 1, t)
	var res := Learning.practice_life(c, "life_farming", true, t)
	assert_eq(res["before"], 1)
	assert_eq(res["after"], 1)
	assert_eq(res["prof"], 7)
	assert_eq(res["gain"], 5)
	res = Learning.practice_life(c, "life_farming", false, t)
	assert_eq(res["prof"], 9)
	assert_eq(res["after"], 2, "LIFE L2 needs 8")
	c.combat_xp = 0
	c.skills.set_level("life_farming", 60, t)
	assert_eq(Learning.practice_life(c, "life_farming", true, t)["after"], 60, "not limited by xp cap")
	assert_true(is_equal_approx(Learning.life_success_chance(0), 0.5))
	assert_true(is_equal_approx(Learning.life_success_chance(100), 0.95))

func test_teach_entries() -> void:
	var c := F.new_char()
	var e := Learning.teach_entries(c, "n_huizhen", t, o, r)
	assert_eq(e.size(), 3)
	var by := {}
	for x in e:
		by[x["skill"]] = x
	assert_eq(by["sl_changquan"]["ok"], false)
	assert_eq(by["sl_changquan"]["reason"], "req_sect")
	assert_eq(by["sl_changquan"]["kind"], "ART")
	assert_eq(by["basic_inner"]["ok"], true)
	assert_eq(by["basic_inner"]["cap"], 140)
	assert_eq(by["basic_inner"]["name"], "基本內功")
	var life := Learning.teach_entries(c, "n_taoyun", t, o, r)
	assert_eq(life[0]["ok"], true)
	assert_eq(life[0]["price"], 50)
