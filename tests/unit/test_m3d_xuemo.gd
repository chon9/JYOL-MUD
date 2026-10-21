extends "res://tests/unit/test_m3d_arts_base.gd"
## M3D_PLAN §4.8（C8，WP-ARTS）：血刀 血魔刀法——條件（血海試鍊做完、威嚇 90、基內 100、基刀 100、血海 30、善惡 ≤ −900、實戰 10 萬）
## → 五個線人（只在這個階段出現）→ 老祖給刀訣 → 帶著刀訣在血刀門口累計停留 2 個時辰（離開就暫停）→ 悟得、1 級、收回刀訣
## → 自修到 10 → 血魔老祖教到 70。

const Q := "q_ar_xd_xuemo"
const ART := "xd_xuemo"
const INFORMANTS := ["n_ar_xd_inf_heilong", "n_ar_xd_baoxiang", "n_ar_xd_inf_dali", "n_ar_dingbusan", "n_ar_dingbusi", "n_ar_laokelian"]

func _xd() -> bool:
	if join_char("xuedao") == null:
		return false
	ch().morality = -950
	ch().combat_xp = 100000
	set_skills({ "weihe": 90, "basic_inner": 100, "basic_blade": 100, "xd_xuehai": 30 })
	ch().quests["done"]["q_xd_xuehai"] = { "n": 1, "outcome": "default", "world_s": host().now_s(), "failed": 0 }
	ensure_giver("n_xd_laozu", Q)
	return true

func _shichen(n: float) -> void:
	ws.world["world_time_s"] = ws.world_time() + WorldClock.shichen_len(host().day_s()) * n
	ws.advance(0.1)

func _accept() -> void:
	goto("xd_hall")
	ok("quest_talk", { "npc": "n_xd_laozu", "quest": Q })
	ok("dialogue_choose", { "npc": "n_xd_laozu", "quest": Q, "node": "n0", "choice": "c_yes" })

func test_data_rows() -> void:
	if not game_ok():
		return
	var a: Dictionary = tables()["martial_arts"][ART]
	assert_eq(str(a["category"]), "BLADE")
	assert_eq(int(a["self_study_until"]), 10)
	var bleed := false
	var widest := ""
	for m in a["moves"]:
		if str(m["status"]) == "bleed":
			bleed = true
		widest = str(m["aoe"])
	assert_true(bleed, "招式帶流血")
	assert_eq(widest, "CROSS_L", "最後一招範圍最大（練到 70「全屏」）")
	assert_eq(int(tables()["masters"]["ms_ar_xd_xuemo"]["cap"]), 70)
	assert_eq(str(tables()["npcs"]["n_ar_xd_xuemo_laozu"]["room"]), "xd_pool")

func test_requires_refused() -> void:
	if not _xd():
		return
	assert_eq(host().quests._can_accept(s(), Q), "")
	ch().quests["done"].erase("q_xd_xuehai")
	assert_eq(host().quests._can_accept(s(), Q), "req_quest_done", "先做完血海魔功的試鍊")
	ch().quests["done"]["q_xd_xuehai"] = { "n": 1, "outcome": "default", "world_s": 0.0, "failed": 0 }
	ch().morality = -899
	assert_eq(host().quests._can_accept(s(), Q), "req_morality_max", "善惡 ≤ −900")
	ch().morality = -950
	set_skills({ "weihe": 89 })
	assert_eq(host().quests._can_accept(s(), Q), "req_skill_min", "威嚇 90")

func test_informants_only_in_stage() -> void:
	if not _xd():
		return
	goto("zn_road1")
	assert_eq(host().npc_here(s(), "n_ar_dingbusan"), "not_here", "還沒接任務：線人不在")
	_accept()
	goto("zn_road1")
	assert_eq(host().npc_here(s(), "n_ar_dingbusan"), "", "五個線人階段：在")

func test_full_flow_and_walk() -> void:
	if not _xd():
		return
	_accept()
	assert_eq(qstage(Q), "s_inform")
	for npc in INFORMANTS:
		goto(str(tables()["npcs"][npc]["room"]))
		ok("quest_talk", { "npc": npc, "quest": Q })
		ok("dialogue_choose", { "npc": npc, "quest": Q, "node": "n0", "choice": "c_ask" })
	assert_eq(qstage(Q), "s_laozu", "問完六人（五路線人）")
	goto("xd_hall")
	ok("quest_talk", { "npc": "n_xd_laozu", "quest": Q })
	ok("dialogue_choose", { "npc": "n_xd_laozu", "quest": Q, "node": "n0", "choice": "c_ok" })
	assert_eq(qstage(Q), "s_walk")
	assert_eq(item_count(ArtsRules.XUEMO_ITEM), 1, "拿到刀訣")
	# 在血刀門口待 1 個時辰：還沒悟
	goto("xd_gate")
	_shichen(1.0)
	state_check()
	assert_eq(qstage(Q), "s_walk", "1 個時辰還不夠")
	assert_false(bool(ch().flags.get(ArtsRules.XUEMO_FLAG, false)))
	# 離開就暫停：在別處過 5 個時辰不算
	goto("xd_hall")
	_shichen(5.0)
	goto("xd_gate")
	_shichen(0.5)
	assert_false(bool(ch().flags.get(ArtsRules.XUEMO_FLAG, false)), "離開的時間不算（累計 1.5 個時辰）")
	clear_events()
	_shichen(0.6)
	assert_true(bool(ch().flags.get(ArtsRules.XUEMO_FLAG, false)), "累計滿 2 個時辰：悟出刀訣")
	assert_false(evs(Protocol.E_AR_XUEMO_ENLIGHTENED).is_empty(), "ar_xuemo_enlightened")
	state_check()
	assert_eq(str(qdone(Q).get("outcome", "")), "default")
	assert_true(bool(ch().flags.get("xd_xuemo_ok", false)))
	assert_eq(lv(ART), 1, "1 級")
	assert_eq(item_count(ArtsRules.XUEMO_ITEM), 0, "收回刀訣")

func test_walk_needs_daojue() -> void:
	if not _xd():
		return
	_accept()
	ch().quests["active"][Q]["stage"] = "s_walk"
	goto("xd_gate")
	_shichen(3.0)
	assert_false(bool(ch().flags.get(ArtsRules.XUEMO_FLAG, false)), "沒帶刀訣不算")

func test_self_study_then_master() -> void:
	if not _xd():
		return
	ch().flags["xd_xuemo_ok"] = true
	set_skills({ ART: 1 })
	var chk := func() -> String:
		return Learning.check_master(ch(), "n_ar_xd_xuemo_laozu", ART, tables(), ws.options, host().rules)
	assert_eq(chk.call(), "need_self_study", "自修到 10")
	assert_true(bool(Learning.self_study(ch(), ART, 1, tables(), ws.options, host().rules)["ok"]))
	set_skills({ ART: 10 })
	assert_eq(chk.call(), "", "10 級起血魔老祖教")
	set_skills({ ART: 70 })
	assert_eq(chk.call(), "cap_master", "教到 70")

func test_era_1_0a() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])
	assert_false(tables()["martial_arts"].has(ART))
	assert_false(tables()["quests"].has(Q))
	for n in INFORMANTS + ["n_ar_xd_xuemo_laozu"]:
		assert_false(tables()["npcs"].has(n), n)
	assert_true(tables()["npcs"].has("n_ar_xd_xuechi"), "血池（1.0A）還在")
