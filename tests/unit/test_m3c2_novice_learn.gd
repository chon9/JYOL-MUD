extends "res://tests/unit/test_world_fixture.gd"
## M3C2_PLAN §2.4、§10.1（WP-PACE）：新手學藝加速 Learning.novice_mults／Learning.learn。
## 倍率（熟練 × novice_learn_pct/100、精 × novice_jing_pct/100、最少 1）、門檻 novice_learn_below（40）、
## 只影響向師父學（自修、秘笈不變）、classic_strict 不變、res.novice。

func _rules(lp := 1000, jp := 30, below := 40) -> Dictionary:
	var r: Dictionary = GameData.rules.duplicate(true)
	r["novice_learn_pct"] = lp
	r["novice_jing_pct"] = jp
	r["novice_learn_below"] = below
	return r

func _shaolin() -> bool:
	if not game_ok():
		return false
	if make_char("新手學藝", "xixia") == null:
		return false
	ch().sect = "shaolin"
	host().sects.on_join(s(), "shaolin", "n_sl_xuanci")
	ch().learn_points = 1000
	ch().combat_xp = 20000
	Survival.rest_full(ch(), tables(), ws.options)
	ch().vitals["neili"] = 200   # 佛法的修練消耗內力（sect_skill_train_cost）
	ch().vitals["jing"] = 200
	return true

func _wc() -> Dictionary:
	return Learning.wit_cost(int(ch().effective_attrs(tables(), ws.options)["wit"]))

func test_profiles() -> void:
	var rp: Dictionary = tables()["rule_profiles"]
	assert_eq(int(rp["classic_strict"]["rules"]["novice_learn_pct"]), 100)
	assert_eq(int(rp["classic_strict"]["rules"]["novice_jing_pct"]), 100)
	assert_false(rp["classic_strict"]["rules"]["chore_xuedian"])
	assert_false(rp["classic_strict"]["rules"]["spar_rewards"])
	for p in ["classic_standard", "later_official", "friends_casual"]:
		assert_true(int(rp[p]["rules"]["novice_learn_pct"]) > 100, p)
		assert_true(int(rp[p]["rules"]["novice_jing_pct"]) < 100, p)
		assert_eq(int(rp[p]["rules"]["novice_learn_below"]), 40, p)
		assert_true(rp[p]["rules"]["chore_xuedian"], p)
		assert_true(rp[p]["rules"]["spar_rewards"], p)
	assert_eq(int(DataSchema.RULE_DEFAULTS["novice_learn_pct"]), 100, "預設＝關")
	assert_false(DataSchema.RULE_DEFAULTS["chore_xuedian"])

func test_mults() -> void:
	if not _shaolin():
		return
	var m := Learning.novice_mults(ch(), "foxa", _rules(1000, 30))
	assert_eq(float(m["prof"]), 10.0)
	assert_eq(float(m["jing"]), 0.3)
	ch().skills.set_level("foxa", 40, tables())
	m = Learning.novice_mults(ch(), "foxa", _rules(1000, 30))
	assert_eq(float(m["prof"]), 1.0, "≥ 40：沒有加速")
	m = Learning.novice_mults(ch(), "basic_inner", {})
	assert_eq(float(m["prof"]), 1.0, "規則缺：沒有加速")

func test_learn_applies_mults() -> void:
	if not _shaolin():
		return
	var wc := _wc()
	var jing0 := int(ch().vitals["jing"])
	var res := Learning.learn(ch(), "n_sl_zhike", "foxa", 3, tables(), ws.options, _rules(1000, 30))
	assert_true(res["ok"], str(res))
	assert_true(bool(res["novice"]), "res.novice")
	assert_eq(int(res["prof_gain"]), 3 * int(wc["prof"]) * 10, "熟練 × 10")
	assert_eq(int(res["jing_cost"]), 3 * maxi(1, roundi(int(wc["jing"]) * 0.3)), "精 × 0.3")
	assert_eq(jing0 - int(ch().vitals["jing"]), int(res["jing_cost"]))
	assert_eq(int(res["lp_cost"]), 3, "學點仍是每次 1")

func test_jing_min_one() -> void:
	if not _shaolin():
		return
	var res := Learning.learn(ch(), "n_sl_zhike", "foxa", 2, tables(), ws.options, _rules(1000, 1))
	assert_eq(int(res["jing_cost"]), 2, "精最少 1")

func test_threshold_40() -> void:
	if not _shaolin():
		return
	ch().skills.set_level("basic_inner", 40, tables())
	var wc := _wc()
	var res := Learning.learn(ch(), "n_sl_huizhen", "basic_inner", 2, tables(), ws.options, _rules(1000, 30))
	assert_true(res["ok"], str(res))
	assert_false(bool(res["novice"]))
	assert_eq(int(res["prof_gain"]), 2 * int(wc["prof"]), "40 級起回到原值")
	assert_eq(int(res["jing_cost"]), 2 * int(wc["jing"]))

func test_crossing_threshold_mid_batch() -> void:
	if not _shaolin():
		return
	ch().skills.set_level("basic_inner", 39, tables())
	ch().skills.entries["basic_inner"]["prof"] = SkillBook.prof_for_level("basic_inner", 40, tables()) - 1
	var wc := _wc()
	var res := Learning.learn(ch(), "n_sl_huizhen", "basic_inner", 10, tables(), ws.options, _rules(1000, 30))
	assert_true(res["ok"], str(res))
	assert_eq(int(ch().skills.level("basic_inner")), 40, "第一次就跨過 40")
	assert_eq(int(res["prof_gain"]), int(wc["prof"]) * 10 + 9 * int(wc["prof"]), "跨過門檻後回到原值（每次重算）")
	assert_eq(int(res["jing_cost"]), maxi(1, roundi(int(wc["jing"]) * 0.3)) + 9 * int(wc["jing"]))

func test_classic_strict_unchanged() -> void:
	if not _shaolin():
		return
	var strict: Dictionary = tables()["rule_profiles"]["classic_strict"]["rules"]
	var wc := _wc()
	var res := Learning.learn(ch(), "n_sl_zhike", "foxa", 2, tables(), ws.options, strict)
	assert_false(bool(res["novice"]))
	assert_eq(int(res["prof_gain"]), 2 * int(wc["prof"]))
	assert_eq(int(res["jing_cost"]), 2 * int(wc["jing"]))

func test_self_study_not_affected() -> void:
	if not _shaolin():
		return
	ch().skills.set_level("basic_inner", 5, tables())
	var eff: Dictionary = ch().effective_attrs(tables(), ws.options)
	var res := Learning.self_study(ch(), "basic_inner", 2, tables(), ws.options, _rules(1000, 30))
	assert_true(res["ok"], str(res))
	assert_eq(int(res["prof_gain"]), 2 * floori(int(eff["wit"]) / 4.0), "自修不受影響")
	assert_false(bool(res.get("novice", false)))

func test_host_learn_uses_server_rules() -> void:
	if not _shaolin():
		return
	goto("sl_wuchang")
	var p0: int = ch().skills.prof("basic_inner")
	ok("learn", { "npc": "n_sl_huizhen", "skill": "basic_inner", "times": 1 })
	var wc := _wc()
	var pct := int(host().rules.get("novice_learn_pct", 100))
	assert_eq(int(ch().skills.prof("basic_inner")) - p0, roundi(int(wc["prof"]) * pct / 100.0), "主機用伺服器規則（classic_standard）")

func test_learn_dialog_tag() -> void:
	var r := { "novice_learn_pct": 1000, "novice_jing_pct": 30, "novice_learn_below": 40 }
	assert_true(LearnDialog.novice_applies("SECT", 10, r))
	assert_true(LearnDialog.novice_applies("BASIC", 39, r))
	assert_false(LearnDialog.novice_applies("BASIC", 40, r))
	assert_false(LearnDialog.novice_applies("LIFE", 1, r), "生活技能不加速")
	assert_false(LearnDialog.novice_applies("ART", 1, { "novice_learn_pct": 100, "novice_jing_pct": 100 }), "strict 不顯示")
	assert_true("10" in LearnDialog.novice_tip(r))
