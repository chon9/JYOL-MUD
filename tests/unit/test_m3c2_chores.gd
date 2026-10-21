extends "res://tests/unit/test_world_fixture.gd"
## M3C2_PLAN §2.3、§2.5、§10.1（WP-PACE）：門派雜務。
## 接／做／交、時辰窗外不能接、冷卻、代價不足 chore_tired（任務留著）、同一遊戲日遞減 100/60/30/0、換日重設、
## 最高本派武功 ≥ 40 後學點 0（熟練照給）、classic_strict 學點 0 但熟練照給、prof_below、每派至少一件全天雜務做得完。

const A := preload("res://tests/unit/test_m3c_npc_attack.gd")

## 每派一件「全天」雜務：[門派, 任務, 給的人, 給的人房間, 做事房間（"" ＝ 不用房間動作）]
const ALLDAY := [
	["shaolin", "q_ch_sl_saodi", "n_ch_sl_kanshui", "sl_court", "sl_court"],
	["wudang", "q_ch_wd_taqiang", "n_wd_yulianzhou", "wd_tanqiang", "wd_tanqiang"],
	["emei", "q_ch_em_chanding", "n_em_jingxuan", "em_dadian", "em_dadian"],
	["huashan", "q_ch_hs_tiaoqi", "n_ch_hs_yejing", "hs_hall", "hs_hall"],
	["quanzhen", "q_ch_qz_dujing", "n_qz_xiazhicheng", "qz_reading", "qz_reading"],
	["gumu", "q_ch_gm_hanyu", "n_gm_hanyu", "gm_hanyu", "gm_hanyu"],
	["hengshan", "q_ch_hg_tiaoqi", "n_hg_dingjing", "hg_houshan", "hg_houshan"],
	["lingjiu", "q_ch_lj_dingzuo", "n_lj_lanjian", "lj_east", "lj_east"],
	["xingxiu", "q_ch_xh_anqi", "n_xh_canjizi", "xh_mid1", "xh_mid1"],
	["xuedao", "q_ch_xd_pizhi", "n_xd_shengdi", "xd_yard", "xd_yard"],
	["gaibang", "q_ch_gb_jianchai", "n_gb_zhanggun", "gb_yuan", "gb_yuan"],
]

func _join(sect: String, city := "xixia", gender := "M") -> bool:
	if not game_ok():
		return false
	if make_char("雜務弟子", city, { "wit": 5 }, gender) == null:
		return false
	ws.options["sect_hostile_entry"] = false
	ch().sect = sect
	host().sects.on_join(s(), sect, str(tables()["sects"][sect].get("head_npc", "")))
	Survival.rest_full(ch(), tables(), ws.options)
	ch().money = 0
	clear_events()
	return true

## 把世界時間撥到某一個遊戲日的開頭（之後再用 set_shichen 撥時辰）
func _to_day_start() -> void:
	var day: float = host().day_s()
	var now: float = ws.world_time()
	ws.world["world_time_s"] = (floorf(now / day) + 1.0) * day + 1.0
	ws.advance(0.1)

func _clear_cd(qid: String) -> void:
	QuestState.ensure(ch().quests)
	(ch().quests["cd"] as Dictionary).erase(qid)

## 接 → （房間動作）→ 交；回傳交差的結果
func _do_chore(qid: String, giver: String, groom: String, wroom: String) -> Dictionary:
	goto(groom)
	ok("quest_accept", { "npc": giver, "quest": qid })
	if wroom != "":
		goto(wroom)
		ok("story_act", { "act": qid + ":a_work" })
	goto(groom)
	return send("quest_turn_in", { "npc": giver, "quest": qid })

## 資料裡這件雜務第 nth 次（同一遊戲日）的學點
func _lp(qid: String, nth := 1) -> int:
	var c: Dictionary = tables()["quests"][qid]["chore"]
	var dp: Array = c.get("decay_pct", [100])
	var pct := int(dp[mini(nth - 1, dp.size() - 1)])
	return int(floor(int(c["lp"]) * pct / 100.0))

func _lp_gain(qid: String, giver: String, groom: String, wroom: String) -> int:
	var lp0: int = ch().learn_points
	var r := _do_chore(qid, giver, groom, wroom)
	assert_true(r.get("ok", false), "%s turn in: %s" % [qid, str(r.get("reason", ""))])
	return int(ch().learn_points) - lp0

# ---------------------------------------------------------------- 資料
func test_chore_rows_shape() -> void:
	var qs: Dictionary = tables()["quests"]
	var per := {}
	for qid in qs:
		var c: Variant = qs[qid].get("chore", null)
		if not (c is Dictionary) or str(c.get("kind", "SECT")) == "TOWN":
			continue   # M3d WP-ERRANDS：城鎮任務（chore.kind TOWN，沒有 sect、學點可以 < 10）由 test_m3d_chore_town 檢查
		per[str(c["sect"])] = int(per.get(str(c["sect"]), 0)) + 1
		assert_true(int(c["lp"]) >= 10 and int(c["lp"]) <= 100, "%s lp" % qid)
	for sid in tables()["sects"]:
		assert_true(int(per.get(sid, 0)) >= 3, "%s has >= 3 chores (%d)" % [sid, int(per.get(sid, 0))])
	assert_eq(int(qs["q_xh_maipi"]["outcomes"]["default"]["rewards"].get("learn_points", -1)), 0, "馬屁研習 學點改由 chore.lp")
	assert_eq(int(qs["q_xh_liandu"]["outcomes"]["default"]["rewards"].get("learn_points", -1)), 0)
	assert_eq(int(qs["q_hg_zaowanke"]["chore"]["prof_below"]), 250)

# ---------------------------------------------------------------- 少林挑水：完整流程
func test_shaolin_tiaoshui_flow() -> void:
	if not _join("shaolin"):
		return
	_to_day_start()
	set_shichen(3)   # 卯
	goto("sl_court")
	var lp0: int = ch().learn_points
	var body0: int = ch().skills.prof("basic_body")
	ok("quest_accept", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_tiaoshui" })
	assert_eq(item_count("i_ch_tong"), 1, "給水桶")
	assert_eq(reason("quest_turn_in", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_tiaoshui" }), "quest_incomplete", "還沒挑水")
	goto("sl_zhulin")
	ok("story_act", { "act": "q_ch_sl_tiaoshui:a_work" })
	assert_false(evs("ch_work_sl_tiaoshui").is_empty(), "挑水文字")
	goto("sl_court")
	var jing0 := int(ch().vitals["jing"])
	clear_events()
	ok("quest_turn_in", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_tiaoshui" })
	assert_eq(int(ch().learn_points) - lp0, _lp("q_ch_sl_tiaoshui"), "學點（資料 chore.lp）")
	assert_eq(int(ch().skills.prof("basic_body")) - body0, 30, "基本輕功熟練 +30（<50）")
	assert_eq(jing0 - int(ch().vitals["jing"]), 15, "交差扣精 15")
	assert_eq(item_count("i_ch_tong"), 0, "水桶還回去")
	assert_eq(int(lastp("reward").get("learn_points", 0)), _lp("q_ch_sl_tiaoshui"), "reward 事件")
	assert_eq(int(ch().counters["chore_day"]["n"]["q_ch_sl_tiaoshui"]), 1, "counters.chore_day")
	# 冷卻中
	assert_eq(reason("quest_accept", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_tiaoshui" }), Protocol.R_QUEST_COOLDOWN)

func test_hour_window() -> void:
	if not _join("shaolin"):
		return
	set_shichen(5)   # 巳：挑水只在卯
	goto("sl_court")
	assert_eq(reason("quest_accept", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_tiaoshui" }), "req_hour_in")
	set_shichen(3)
	goto("sl_court")
	ok("quest_accept", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_tiaoshui" })
	# 房間動作也有時辰窗
	set_shichen(4)
	goto("sl_zhulin")
	assert_eq(reason("story_act", { "act": "q_ch_sl_tiaoshui:a_work" }), Protocol.R_QUEST_NOT_NOW)

func test_cooldown_then_again() -> void:
	if not _join("shaolin"):
		return
	_to_day_start()
	set_shichen(1)
	assert_eq(_lp_gain("q_ch_sl_saodi", "n_ch_sl_kanshui", "sl_court", "sl_court"), _lp("q_ch_sl_saodi", 1))
	assert_eq(reason("quest_accept", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_saodi" }), Protocol.R_QUEST_COOLDOWN)
	A.advance_shichen(self, 1.3)   # 冷卻 0.1 遊戲日 ＝ 1.2 個時辰
	goto("sl_court")
	assert_eq(_lp_gain("q_ch_sl_saodi", "n_ch_sl_kanshui", "sl_court", "sl_court"), _lp("q_ch_sl_saodi", 2), "第 2 次 60%")

func test_decay_and_day_reset() -> void:
	if not _join("shaolin"):
		return
	_to_day_start()
	var got: Array = []
	for i in 5:
		_clear_cd("q_ch_sl_saodi")
		got.append(_lp_gain("q_ch_sl_saodi", "n_ch_sl_kanshui", "sl_court", "sl_court"))
	assert_eq(got, [_lp("q_ch_sl_saodi", 1), _lp("q_ch_sl_saodi", 2), _lp("q_ch_sl_saodi", 3), 0, 0], "遞減 100/60/30/0，超過長度用最後一個")
	assert_false(evs("ch_no_lp").is_empty(), "遞減到 0：ch_no_lp")
	assert_eq(str(lastp("ch_no_lp").get("why", "")), "daily")
	assert_true(str(lastp("ch_no_lp").get("text", "")) != "")
	_to_day_start()   # 換日
	_clear_cd("q_ch_sl_saodi")
	assert_eq(_lp_gain("q_ch_sl_saodi", "n_ch_sl_kanshui", "sl_court", "sl_court"), _lp("q_ch_sl_saodi", 1), "換日重設")

func test_chore_tired_keeps_quest() -> void:
	if not _join("shaolin"):
		return
	goto("sl_hall")
	ok("quest_accept", { "npc": "n_ch_sl_jingseng", "quest": "q_ch_sl_dujing" })
	ok("story_act", { "act": "q_ch_sl_dujing:a_work" })
	ch().vitals["shen"] = 5
	var lp0: int = ch().learn_points
	assert_eq(reason("quest_turn_in", { "npc": "n_ch_sl_jingseng", "quest": "q_ch_sl_dujing" }), Protocol.R_CHORE_TIRED)
	assert_true(QuestState.is_active(ch().quests, "q_ch_sl_dujing"), "任務留著")
	assert_eq(item_count("i_ch_jingshu"), 1, "經書還在身上")
	assert_eq(int(ch().learn_points), lp0)
	ch().vitals["shen"] = 50
	ok("quest_turn_in", { "npc": "n_ch_sl_jingseng", "quest": "q_ch_sl_dujing" })
	assert_eq(int(ch().vitals["shen"]), 30, "神 −20")
	assert_eq(int(ch().learn_points) - lp0, _lp("q_ch_sl_dujing"))

func test_novice_over_no_lp_but_prof() -> void:
	if not _join("shaolin"):
		return
	_to_day_start()
	ch().skills.set_level("sl_changquan", 40, tables())
	assert_eq(Learning.highest_sect_art(ch(), tables()), 40)
	var body0: int = ch().skills.prof("basic_body")
	assert_eq(_lp_gain("q_ch_sl_saodi", "n_ch_sl_kanshui", "sl_court", "sl_court"), 0, "40 級後學點 0")
	assert_eq(str(lastp("ch_no_lp").get("why", "")), "novice")
	# 熟練照給（換一件有熟練的：讀經）
	ch().vitals["shen"] = 80
	var lit0: int = ch().skills.prof("basic_literacy")
	assert_eq(_lp_gain("q_ch_sl_dujing", "n_ch_sl_jingseng", "sl_hall", "sl_hall"), 0)
	assert_eq(int(ch().skills.prof("basic_literacy")) - lit0, 30, "熟練照給")
	assert_eq(int(ch().skills.prof("basic_body")), body0)

func test_classic_strict_prof_only() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	if not _join("shaolin"):
		return
	assert_false(host().rules.get("chore_xuedian", true), "classic_strict: chore_xuedian false")
	var lit0: int = ch().skills.prof("basic_literacy")
	assert_eq(_lp_gain("q_ch_sl_dujing", "n_ch_sl_jingseng", "sl_hall", "sl_hall"), 0, "strict：學點 0")
	assert_eq(int(ch().skills.prof("basic_literacy")) - lit0, 30, "strict：熟練照給")
	assert_true(evs("ch_no_lp").is_empty(), "規則關：不另外提示")

func test_prof_below() -> void:
	if not _join("shaolin"):
		return
	ch().skills.set_level("basic_literacy", 50, tables())
	var p0: int = ch().skills.prof("basic_literacy")
	assert_eq(_lp_gain("q_ch_sl_dujing", "n_ch_sl_jingseng", "sl_hall", "sl_hall"), _lp("q_ch_sl_dujing"), "學點照給")
	assert_eq(int(ch().skills.prof("basic_literacy")), p0, "≥ 50 不再加熟練")

func test_life_skill_not_learned_no_prof() -> void:
	if not _join("shaolin"):
		return
	set_shichen(4)   # 辰：砍柴（早上）
	goto("sl_caiyuan")
	ok("quest_accept", { "npc": "n_ch_sl_chaigong", "quest": "q_ch_sl_kanchai" })
	goto("sl_zhulin")
	assert_eq(reason("story_act", { "act": "q_ch_sl_kanchai:a_work" }), "req_has_item", "要帶柴刀")
	give("w_chaidao")
	ok("story_act", { "act": "q_ch_sl_kanchai:a_work" })
	goto("sl_caiyuan")
	ok("quest_turn_in", { "npc": "n_ch_sl_chaigong", "quest": "q_ch_sl_kanchai" })
	assert_eq(int(ch().skills.level("life_woodcut")), 0, "沒學過樵夫：不給樵夫熟練")

func test_huayuan_money_max() -> void:
	if not _join("shaolin"):
		return
	goto("sl_gate")
	ch().money = 5
	assert_eq(reason("quest_accept", { "npc": "n_sl_zhike", "quest": "q_ch_sl_huayuan" }), "req_money_max")
	ch().money = 0
	assert_eq(_lp_gain("q_ch_sl_huayuan", "n_sl_zhike", "sl_gate", "sl_gate"), _lp("q_ch_sl_huayuan"))
	A.advance_shichen(self, 2.0)
	goto("sl_gate")
	assert_eq(reason("quest_accept", { "npc": "n_sl_zhike", "quest": "q_ch_sl_huayuan" }), Protocol.R_QUEST_COOLDOWN, "一天一次")

func test_xuedao_kongxia_dialogue() -> void:
	if not _join("xuedao"):
		return
	ch().morality = -150
	goto("xd_tent")
	ok("quest_accept", { "npc": "n_xd_herder", "quest": "q_ch_xd_kongxia" })
	ok("quest_talk", { "npc": "n_xd_herder", "quest": "q_ch_xd_kongxia" })
	var lp0: int = ch().learn_points
	var mo0: int = ch().morality
	var w0: int = ch().skills.prof("weihe")
	ok("dialogue_choose", { "npc": "n_xd_herder", "quest": "q_ch_xd_kongxia", "node": "n0", "choice": "c_scare" })
	assert_eq(int(ch().learn_points) - lp0, _lp("q_ch_xd_kongxia"))
	assert_eq(int(ch().morality) - mo0, -10)
	assert_eq(int(ch().skills.prof("weihe")) - w0, 20, "威嚇熟練 +20")
	assert_eq(QuestState.done_count(ch().quests, "q_ch_xd_kongxia"), 1)

func test_xingxiu_shoulie_kill() -> void:
	if not _join("xingxiu"):
		return
	ch().morality = -150
	make_strong()
	goto("xh_mid1")
	ok("quest_accept", { "npc": "n_xh_shudouzi", "quest": "q_ch_xh_shoulie" })
	goto("xh_road2")
	for i in 2:
		ok("story_act", { "act": "q_ch_xh_shoulie:a_hunt" })
		A.finish(self, 1, true)
	goto("xh_mid1")
	var lp0: int = ch().learn_points
	ok("quest_turn_in", { "npc": "n_xh_shudouzi", "quest": "q_ch_xh_shoulie" })
	assert_eq(int(ch().learn_points) - lp0, _lp("q_ch_xh_shoulie"))

func test_existing_zaowanke_has_chore_lp() -> void:
	if not _join("hengshan", "xixia", "F"):
		return
	_to_day_start()
	set_shichen(3)   # 卯
	goto("hg_hall")
	var lp0: int = ch().learn_points
	var cb0: int = ch().skills.prof("cibei")
	ok("quest_accept", { "npc": "n_hg_yizhi", "quest": "q_hg_zaowanke" })
	ok("quest_turn_in", { "npc": "n_hg_yizhi", "quest": "q_hg_zaowanke" })
	assert_eq(int(ch().learn_points) - lp0, _lp("q_hg_zaowanke"), "早晚課 chore.lp")
	assert_eq(int(ch().skills.prof("cibei")) - cb0, 15, "既有慈悲 15 照給")

## 每派一件全天雜務：接、做、交都成功，有學點與 reward 事件
func test_every_sect_allday_chore() -> void:
	if not game_ok():
		return
	if make_char("十一派代表", "xixia", { "wit": 5 }, "F") == null:
		return
	ws.options["sect_hostile_entry"] = false
	for row in ALLDAY:
		var sect: String = row[0]
		ch().sect = sect
		ch().morality = -150 if sect in ["xingxiu", "xuedao"] else 100
		host().sects.on_join(s(), sect, str(tables()["sects"][sect].get("head_npc", "")))
		Survival.rest_full(ch(), tables(), ws.options)
		QuestState.ensure(ch().quests)
		ch().counters.erase("chore_day")
		clear_events()
		var lp0: int = ch().learn_points
		var r := _do_chore(str(row[1]), str(row[2]), str(row[3]), str(row[4]))
		assert_true(r.get("ok", false), "%s %s: %s" % [sect, row[1], str(r.get("reason", ""))])
		assert_true(int(ch().learn_points) > lp0, "%s 有學點" % sect)
		assert_false(evs("reward").is_empty(), "%s reward 事件" % sect)
		assert_eq(QuestState.done_count(ch().quests, str(row[1])), 1)
