extends "res://tests/unit/test_m3d_arts_base.gd"
## M3D_PLAN §4.1（C1，WP-ARTS）：全真 重陽劍法鏈——山居隱士（教到 20）→ 自修到 30 → 三瓶狀元紅換推薦信 → 漱流隱士（30→40）
## → 雲遊道士要拂塵（40→60）→ 60 以上自修到 100。條件不足被拒、逐步完成、師父 cap、自修分段、1.0A 視圖沒有這條鏈。

const Q := "q_ar_qz_chongyang"
const ART := "qz_chongyang"
const REQ_SKILLS := { "qz_xinfa": 70, "basic_sword": 60, "basic_inner": 60, "yangsheng": 80 }

func _qz() -> bool:
	if join_char("quanzhen") == null:
		return false
	set_skills(REQ_SKILLS)
	return true

func _check(npc: String) -> String:
	return Learning.check_master(ch(), npc, ART, tables(), ws.options, host().rules)

func _study() -> Dictionary:
	ch().learn_points = 5000
	Survival.rest_full(ch(), tables(), ws.options)
	return Learning.self_study(ch(), ART, 1, tables(), ws.options, host().rules)

func test_data_rows() -> void:
	if not game_ok():
		return
	var a: Dictionary = tables()["martial_arts"][ART]
	assert_eq(str(a["era"]), "1.0B")
	assert_eq(int(a["self_study_cap"]), 100)
	for mid in ["ms_ar_qz_shanju", "ms_ar_qz_shuliu", "ms_ar_qz_yunyou"]:
		assert_true(tables()["masters"].has(mid), mid)
	assert_eq(int(tables()["masters"]["ms_ar_qz_shanju"]["cap"]), 20)
	assert_eq(int(tables()["masters"]["ms_ar_qz_shuliu"]["cap"]), 40)
	assert_eq(int(tables()["masters"]["ms_ar_qz_yunyou"]["cap"]), 60)
	assert_eq(str(tables()["npcs"]["n_ar_qz_shanju"]["room"]), "zn_river")
	assert_eq(str(tables()["npcs"]["n_ar_qz_shuliu"]["room"]), "dlw_river")
	assert_eq(str(tables()["npcs"]["n_ar_qz_yunyou"]["room"]), "em_road1")
	assert_eq(int(tables()["items"]["i_ar_zhuangyuanhong"]["price"]), 60)

func test_requires_refused() -> void:
	if join_char("quanzhen") == null:
		return
	set_skills({ "qz_xinfa": 69, "basic_sword": 60, "basic_inner": 60, "yangsheng": 80 })
	assert_eq(host().quests._can_accept(s(), Q), "req_skill_min", "全真心法 69 不夠")
	set_skills({ "qz_xinfa": 70 })
	assert_eq(host().quests._can_accept(s(), Q), "")
	ch().sect = "wudang"
	assert_eq(host().quests._can_accept(s(), Q), "req_sect", "不是全真弟子")

func test_chain_flow() -> void:
	if not _qz():
		return
	goto("zn_river")
	ok("quest_talk", { "npc": "n_ar_qz_shanju", "quest": Q })
	ok("dialogue_choose", { "npc": "n_ar_qz_shanju", "quest": Q, "node": "n0", "choice": "c_yes" })
	assert_true(bool(ch().flags.get("qz_chongyang_jian", false)), "接任務就給旗標（山居隱士開始教）")
	assert_eq(qstage(Q), "s_practice")
	# 山居隱士教 1–20
	assert_eq(_check("n_ar_qz_shanju"), "")
	set_skills({ ART: 29 })
	state_check()
	assert_eq(qstage(Q), "s_practice", "29 級還不到")
	set_skills({ ART: 30 })
	state_check()
	assert_eq(qstage(Q), "s_wine", "30 級 → 回去找他")
	# 三瓶狀元紅 → 推薦信
	give("i_ar_zhuangyuanhong", 2)
	qtalk("n_ar_qz_shanju", Q)
	assert_eq(qstage(Q), "s_wine", "只有兩瓶")
	give("i_ar_zhuangyuanhong", 1)
	ok("quest_talk", { "npc": "n_ar_qz_shanju", "quest": Q })
	assert_eq(qstage(Q), "s_shuliu")
	assert_eq(item_count("i_ar_zhuangyuanhong"), 0)
	assert_eq(item_count("i_ar_qz_tuijianxin"), 1, "拿到推薦信")
	# 漱流隱士
	goto("dlw_river")
	assert_eq(_check("n_ar_qz_shuliu"), "req_quest_flag", "還沒交信，漱流不教")
	ok("quest_talk", { "npc": "n_ar_qz_shuliu", "quest": Q })
	assert_eq(qstage(Q), "s_fuchen")
	assert_true(bool(ch().flags.get("qz_cy_shuliu", false)))
	assert_eq(item_count("i_ar_qz_tuijianxin"), 0, "信交出去了")
	assert_eq(_check("n_ar_qz_shuliu"), "", "30 級、交了信 → 漱流教")
	# 雲遊道士
	goto("em_road1")
	give("w_lt_fuchen", 1)
	ok("quest_talk", { "npc": "n_ar_qz_yunyou", "quest": Q })
	assert_eq(str(qdone(Q).get("outcome", "")), "default", "鏈完成")
	assert_true(bool(ch().flags.get("qz_cy_yunyou", false)))
	assert_eq(item_count("w_lt_fuchen"), 0)

func test_master_caps_and_self_study_segments() -> void:
	if not _qz():
		return
	ch().flags["qz_chongyang_jian"] = true
	# 1–20 山居隱士
	assert_eq(_check("n_ar_qz_shanju"), "")
	var r := Learning.learn(ch(), "n_ar_qz_shanju", ART, 1, tables(), ws.options, host().rules)
	assert_true(bool(r["ok"]), "山居隱士教得了 0 級：%s" % str(r))
	set_skills({ ART: 20 })
	assert_eq(_check("n_ar_qz_shanju"), "cap_master", "山居隱士只教到 20")
	# 20→30 自修
	assert_true(bool(_study()["ok"]), "20 級可以自修")
	set_skills({ ART: 29 })
	assert_true(bool(_study()["ok"]), "29 級可以自修")
	set_skills({ ART: 30 })
	assert_eq(str(_study()["reason"]), "req_any_of", "30 級起沒有推薦信：自修也卡住")
	assert_eq(_check("n_ar_qz_shuliu"), "req_quest_flag")
	ch().flags["qz_cy_shuliu"] = true
	assert_eq(_check("n_ar_qz_shuliu"), "", "漱流隱士 30→40")
	assert_true(bool(_study()["ok"]))
	set_skills({ ART: 40 })
	assert_eq(str(_study()["reason"]), "req_any_of", "40 級起要雲遊道士收下拂塵")
	assert_eq(_check("n_ar_qz_shuliu"), "req_any_of", "40 級起武功本身的分段條件就擋住了")
	assert_eq(_check("n_ar_qz_yunyou"), "req_quest_flag")
	ch().flags["qz_cy_yunyou"] = true
	assert_eq(_check("n_ar_qz_shuliu"), "cap_master", "漱流只教到 40")
	assert_eq(_check("n_ar_qz_yunyou"), "")
	set_skills({ ART: 60 })
	assert_eq(_check("n_ar_qz_yunyou"), "cap_master", "雲遊道士只教到 60")
	assert_true(bool(_study()["ok"]), "60 以上自修")
	assert_eq(Learning.self_study_cap(ch(), ART, tables(), host().rules), 100, "自修上限 100")

func test_era_1_0a_has_no_chain() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])
	assert_false(tables()["quests"].has(Q), "1.0A 視圖沒有任務")
	assert_false(tables()["martial_arts"].has(ART), "1.0A 視圖沒有重陽劍法")
	assert_false(tables()["npcs"].has("n_ar_qz_shanju"))
	assert_false(tables()["masters"].has("ms_ar_qz_shanju"))
	assert_true(tables()["items"].has("i_ar_zhuangyuanhong"), "狀元紅只是酒，1.0A 也賣")
