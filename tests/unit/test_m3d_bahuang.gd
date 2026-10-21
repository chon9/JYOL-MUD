extends "res://tests/unit/test_m3d_arts_base.gd"
## M3D_PLAN §4.3（C3，WP-ARTS）：靈鷲 八荒六合唯我獨尊功——服侍童姥 → 無涯子 → 西夏虛竹 → 回童姥（旗標＋1 級）
## → 自修 1–40 → 蘭劍教 41–70；童姥的師父列 cap 1。

const Q := "q_ar_lj_bahuang"
const ART := "lj_bahuang"

func _lj() -> bool:
	if join_char("lingjiu", "靈鷲女弟子", "F") == null:
		return false
	set_skills({ "lj_xiaoyao": 80, "dingxing": 50 })
	ensure_giver("n_lj_tonglao", Q)
	return true

func test_data_rows() -> void:
	if not game_ok():
		return
	assert_eq(str(tables()["martial_arts"][ART]["era"]), "1.0B")
	assert_eq(int(tables()["martial_arts"][ART]["self_study_until"]), 40)
	assert_eq(int(tables()["masters"]["ms_lj_tonglao_bahuang"]["cap"]), 1, "童姥只給 1 級（任務給）")
	assert_eq(int(tables()["masters"]["ms_ar_lj_lanjian_bahuang"]["cap"]), 70)
	assert_eq(str(tables()["masters"]["ms_ar_lj_lanjian_bahuang"]["npc_id"]), "n_lj_lanjian")
	assert_eq(str(tables()["npcs"]["n_ar_lj_wuyazi"]["room"]), "ts_hut")

func test_requires_refused() -> void:
	if not _lj():
		return
	set_skills({ "dingxing": 49 })
	assert_eq(host().quests._can_accept(s(), Q), "req_skill_min", "定性 50")

func test_flow() -> void:
	if not _lj():
		return
	goto("lj_hall")
	ok("quest_talk", { "npc": "n_lj_tonglao", "quest": Q })
	ok("dialogue_choose", { "npc": "n_lj_tonglao", "quest": Q, "node": "n0", "choice": "c_serve" })
	assert_eq(qstage(Q), "s_wuyazi")
	# 順序不能跳：還沒找無涯子，童姥那裡沒有可交的目標
	goto("ts_hut")
	ok("quest_talk", { "npc": "n_ar_lj_wuyazi", "quest": Q })
	ok("dialogue_choose", { "npc": "n_ar_lj_wuyazi", "quest": Q, "node": "n0", "choice": "c_ok" })
	assert_eq(qstage(Q), "s_xuzhu")
	goto("xx_yamen")
	ok("quest_talk", { "npc": "n_xx_xuzhu", "quest": Q })
	ok("dialogue_choose", { "npc": "n_xx_xuzhu", "quest": Q, "node": "n0", "choice": "c_ok" })
	assert_eq(qstage(Q), "s_back")
	goto("lj_hall")
	ok("quest_talk", { "npc": "n_lj_tonglao", "quest": Q })
	ok("dialogue_choose", { "npc": "n_lj_tonglao", "quest": Q, "node": "n0", "choice": "c_ok" })
	assert_eq(str(qdone(Q).get("outcome", "")), "default")
	assert_true(bool(ch().flags.get("lj_bahuang_learned", false)))
	assert_eq(lv(ART), 1, "回童姥 → 1 級")

func test_self_study_then_lanjian() -> void:
	if not _lj():
		return
	ch().flags["lj_bahuang_learned"] = true
	set_skills({ ART: 1 })
	var chk := func(npc: String) -> String:
		return Learning.check_master(ch(), npc, ART, tables(), ws.options, host().rules)
	assert_eq(chk.call("n_lj_lanjian"), "need_self_study", "1–40 自修")
	assert_eq(chk.call("n_lj_tonglao"), "need_self_study", "童姥也不教（只給 1 級）")
	var r := Learning.self_study(ch(), ART, 1, tables(), ws.options, host().rules)
	assert_true(bool(r["ok"]), "自修 %s" % str(r))
	set_skills({ ART: 40 })
	assert_eq(chk.call("n_lj_lanjian"), "", "40 級起蘭劍教")
	assert_eq(chk.call("n_lj_tonglao"), "cap_master", "童姥 cap 1")
	set_skills({ ART: 70 })
	assert_eq(chk.call("n_lj_lanjian"), "cap_master", "蘭劍教到 70")

func test_era_1_0a() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])
	assert_false(tables()["martial_arts"].has(ART), "八荒 1.0B")
	assert_false(tables()["masters"].has("ms_lj_tonglao_bahuang"), "童姥的八荒師父列跟著 1.0B（不留懸空參照）")
	assert_false(tables()["quests"].has(Q))
