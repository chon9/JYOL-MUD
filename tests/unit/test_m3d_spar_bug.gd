extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §6.5、E6、§10.1（WP-ERRANDS）：陸大有切磋獎勵 BUG。
## 切磋弟子的實戰與學點只給該派弟子：沒門派 0、他派 0、本派照舊；不是本派不計每日場數；
## 華山入門考驗 q_hs_kaoyan（打贏陸大有）照樣完成；每個切磋弟子都對得到一個門派。

const A := preload("res://tests/unit/test_m3c_npc_attack.gd")

func _char(sect := "", city := "xixia") -> bool:
	if not game_ok():
		return false
	if make_char("切磋的人", city) == null:
		return false
	ws.options["encounters_enabled"] = false
	ws.options["sect_hostile_entry"] = false
	if sect != "":
		ch().sect = sect
		ch().morality = 100
		host().sects.on_join(s(), sect, str(tables()["sects"][sect].get("head_npc", "")))
	make_strong()
	clear_events()
	return true

func _spar(npc: String, room: String) -> Dictionary:
	goto(room)
	Survival.rest_full(ch(), tables(), ws.options)
	var xp0 := int(ch().combat_xp)
	var lp0 := int(ch().learn_points)
	ok("fight", { "npc": npc })
	A.finish(self, 1, true)
	return { "xp": int(ch().combat_xp) - xp0, "lp": int(ch().learn_points) - lp0 }

func _spar_n() -> int:
	var sd: Variant = ch().counters.get("spar_day", {})
	return int((sd as Dictionary).get("n", 0)) if sd is Dictionary else 0

func test_spar_sect_mapping() -> void:
	if not game_ok():
		return
	var ss = host().sects
	assert_eq(ss.spar_sect("m_hs_trainee"), "huashan", "陸大有的華山弟子")
	var want := { "m_sl_dizi": "shaolin", "m_wd_dizi": "wudang", "m_em_dizi": "emei", "m_gm_dizi": "gumu", "m_hg_dizi": "hengshan",
		"m_lj_dizi": "lingjiu", "m_qz_dizi": "quanzhen", "m_xh_dizi": "xingxiu", "m_xd_dizi": "xuedao", "m_gb_dizi": "gaibang" }
	for mid in want:
		assert_eq(ss.spar_sect(mid), str(want[mid]), mid)
	assert_eq(ss.spar_sect("m_wolf"), "", "不是切磋弟子")

func test_no_sect_gets_nothing_from_ludayou() -> void:
	if not _char():
		return
	var d := _spar("n_ludayou", "hs_square")
	assert_eq(int(d["xp"]), 0, "沒門派：切磋沒有實戰")
	assert_eq(int(d["lp"]), 0, "沒門派：切磋沒有學點")
	assert_false(evs(Protocol.E_ER_SPAR_NOT_DISCIPLE).is_empty(), "er_spar_not_disciple")
	assert_eq(_spar_n(), 0, "不計每日場數")

func test_other_sect_gets_nothing() -> void:
	if not _char("wudang"):
		return
	var d := _spar("n_ludayou", "hs_square")
	assert_eq(int(d["xp"]) + int(d["lp"]), 0, "武當弟子打華山陸大有：0")
	assert_eq(_spar_n(), 0)
	var d2 := _spar("n_wd_spar", "wd_square")
	assert_true(int(d2["xp"]) > 0 and int(d2["lp"]) > 0, "自己門派的切磋照舊 %s" % str(d2))
	assert_eq(_spar_n(), 1, "本派切磋才計場數")

func test_own_sect_still_rewarded() -> void:
	if not _char("huashan"):
		return
	var d := _spar("n_ludayou", "hs_square")
	assert_true(int(d["xp"]) > 0 and int(d["lp"]) > 0, "華山弟子打陸大有照舊 %s" % str(d))
	assert_true(evs(Protocol.E_ER_SPAR_NOT_DISCIPLE).is_empty())

func test_kaoyan_still_completes_without_sect() -> void:
	if not _char():
		return
	goto("hs_square")
	ch().skills.set_level("basic_inner", 5, tables())
	ch().skills.set_level("basic_literacy", 5, tables())
	ok("quest_accept", { "npc": "n_yuebuqun", "quest": "q_hs_kaoyan" })
	var d := _spar("n_ludayou", "hs_square")
	assert_eq(int(d["xp"]) + int(d["lp"]), 0, "考驗中的切磋也沒有實戰學點")
	assert_eq(str(ch().quests["active"]["q_hs_kaoyan"]["stage"]), "step_1", "FIGHT 目標照樣算")
	ok("quest_turn_in", { "npc": "n_yuebuqun", "quest": "q_hs_kaoyan" })
	assert_eq(ch().flags.get("hs_trial_passed", false), true)
	ok("join_sect", { "npc": "n_yuebuqun" })
	assert_eq(str(ch().sect), "huashan")
	var d2 := _spar("n_ludayou", "hs_square")
	assert_true(int(d2["xp"]) > 0, "入了華山之後再打就有獎勵 %s" % str(d2))

func test_decide_direct() -> void:
	if not _char("emei"):
		return
	var ss = host().sects
	var r: Dictionary = ss.spar_decide(ch(), true, "m_hs_trainee")
	assert_eq(str(r["why"]), "not_disciple")
	assert_false(bool(r["xp"]))
	assert_eq(_spar_n(), 0, "not_disciple 不計場數")
	var r2: Dictionary = ss.spar_decide(ch(), true, "m_em_dizi")
	assert_true(bool(r2["xp"]))
	assert_eq(_spar_n(), 1)
