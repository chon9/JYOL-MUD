extends "res://tests/unit/test_world_fixture.gd"
## 故事包第四輪審查修正的回歸測試（方法名 test_story_review4_*；--filter=story_review4 可單跑）。
## - 對話走到結束節點，主機就收掉游標（遊蕩惡人不再把聊完天的玩家當成忙碌）
## - give 動作給的可賣物品（韋小寶的金戒指）放棄重接不能再拿；任務物品（信、令牌）照常重給；杉木不能賣
## - auto_dialogue：目前那句的選項全上鎖時送選單（滅絕師太）；兩條任務同時在一位 NPC 身上也送選單
## - 追擊戰不把新手隊友拉進去
## - 新手歡迎風聲不重複登入補送的那一則；大理出生優先雲兒；WorldIndex.hops
## - 環境句同一句對同一個人一段時間內不重複
## - 武當 太極拳與太極劍／龍門遺案 的任務門檻照 2001-08-07 原文
## - 勞德諾、豬哥義、朱珠、崔叟、婦人依這位玩家做過的事換話；大理老人不問女性玩家是不是武當的人

func before_each() -> void:
	world_name = "w_story_review4"
	super.before_each()

# ---------------------------------------------------------------- 對話游標
func test_story_review4_end_node_clears_cursor() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_minfang")
	ok("quest_accept", { "npc": "n_xx_yuner", "quest": "q_yuner" })
	assert_false(s().dialogue.is_empty(), "offer 開著")
	ok("dialogue_choose", { "npc": "n_xx_yuner", "quest": "q_yuner", "node": "n0", "choice": "c_ask" })
	ok("dialogue_choose", { "npc": "n_xx_yuner", "quest": "q_yuner", "node": "n1", "choice": DialogueTree.NEXT_CHOICE })
	clear_events()
	ok("dialogue_choose", { "npc": "n_xx_yuner", "quest": "q_yuner", "node": "n2", "choice": "c_help" })
	ws.flush()
	var d := evs(Protocol.E_DIALOGUE)
	assert_eq(d.size(), 1, "送出結束節點 n3")
	if d.size() > 0:
		assert_true(bool(d[0].get("p", {}).get("end", false)), "n3 是結束節點")
	assert_true(s().dialogue.is_empty(), "結束節點送出後游標已收掉（審查：原本留著 {dlg: d_offer, node: n3}）")
	assert_true(ch().quests["active"].has("q_yuner"), "接到任務")
	assert_true(host().wander._idle(s()), "遊蕩惡人眼中玩家是閒著的")
	assert_eq(evs(Protocol.E_DIALOGUE_CLOSE).size(), 0, "不另送 dialogue_close（客戶端「結束」直接收起）")
	assert_true(send("dialogue_close").get("ok", false), "客戶端再按結束也不報錯")

# ---------------------------------------------------------------- give 動作與放棄
func test_story_review4_ring_not_farmable_by_abandon() -> void:
	if not game_ok():
		return
	make_char("峨嵋測試", "dali", { "wit": 5 }, "F")
	ch().sect = "emei"
	var row: Dictionary = tables()["quests"]["q_em_baifang"]
	var give_ring := [{ "do": "give", "item": "a_em_wxb_jiezhi", "n": 1 }]
	var rings: Array = []
	for round in 3:
		assert_true(host().quests.debug_stage(s(), "q_em_baifang", str(row["start"])).get("ok", false), "accept round %d" % round)
		host().quests._run_actions(s(), "q_em_baifang", "", give_ring)
		rings.append(item_count("a_em_wxb_jiezhi"))
		ch().inventory.remove_item_id("a_em_wxb_jiezhi", item_count("a_em_wxb_jiezhi"))   # 拿去賣了
		ok("quest_abandon", { "quest": "q_em_baifang" })
	assert_eq(rings, [1, 0, 0], "賣掉戒指再放棄重接：不再給第二枚")
	# 沒賣、放棄時被收回 → 重接照樣給（不是玩家留著的）
	assert_true(host().quests.debug_stage(s(), "q_em_baifang", str(row["start"])).get("ok", false))
	host().quests._run_actions(s(), "q_em_baifang", "", give_ring)
	assert_eq(item_count("a_em_wxb_jiezhi"), 0, "上一輪賣掉的那枚抵掉這一次")
	ch().quests.get("paid", {}).erase("q_em_baifang")
	ok("quest_abandon", { "quest": "q_em_baifang" })
	ch().quests.get("paid", {}).erase("q_em_baifang")
	assert_true(host().quests.debug_stage(s(), "q_em_baifang", str(row["start"])).get("ok", false))
	host().quests._run_actions(s(), "q_em_baifang", "", give_ring)
	assert_eq(item_count("a_em_wxb_jiezhi"), 1)
	ok("quest_abandon", { "quest": "q_em_baifang" })
	assert_eq(item_count("a_em_wxb_jiezhi"), 0, "放棄時收回")
	assert_true(host().quests.debug_stage(s(), "q_em_baifang", str(row["start"])).get("ok", false))
	host().quests._run_actions(s(), "q_em_baifang", "", give_ring)
	assert_eq(item_count("a_em_wxb_jiezhi"), 1, "收回過的那枚：重接照樣給")

func test_story_review4_quest_items_still_regiven_after_abandon() -> void:
	if not game_ok():
		return
	make_char()
	ch().sect = "wudang"
	for i in 2:
		assert_true(host().quests.debug_stage(s(), "q_wd_longmen", "s_orphan").get("ok", false))
		host().quests._run_actions(s(), "q_wd_longmen", "", [{ "do": "give", "item": "i_wd_longmenling", "n": 1 }])
		assert_eq(item_count("i_wd_longmenling"), 1, "任務物品不記帳，每一輪都拿得到（round %d）" % i)
		ch().inventory.remove_item_id("i_wd_longmenling", 1)   # 弄丟了
		ok("quest_abandon", { "quest": "q_wd_longmen" })

func test_story_review4_shanmu_not_sellable() -> void:
	if not game_ok():
		return
	assert_true(bool(tables()["items"]["r_shanmu"].get("no_sell", false)), "杉木不能賣（砍一段賣一段的漏洞）")
	assert_false(host().quests._ledger_item("i_wd_longmenling"), "任務物品不記帳")
	assert_true(host().quests._ledger_item("a_em_wxb_jiezhi"), "金戒指記帳")

# ---------------------------------------------------------------- auto_dialogue
func test_story_review4_locked_objective_shows_menu() -> void:
	if not game_ok():
		return
	make_char("峨嵋測試", "dali", { "wit": 5 }, "F")
	ch().sect = "emei"
	assert_true(host().quests.debug_stage(s(), "q_em_shandu", "s_jiuyang").get("ok", false))
	goto(host().index.room_of_npc("n_em_miejue"))
	for i in 2:
		clear_events()
		ok("talk", { "npc": "n_em_miejue" })
		ws.flush()
		assert_eq(evs(Protocol.E_NPC_MENU).size(), 1, "九陽不到 10：送選單（教學、叛派、其他任務點得到）round %d" % i)
		assert_eq(evs(Protocol.E_DIALOGUE).size(), 0, "不直接開只剩上鎖選項的對話")
	ch().skills.set_level("em_jiuyang", 10, tables())
	clear_events()
	ok("talk", { "npc": "n_em_miejue" })
	ws.flush()
	assert_eq(evs(Protocol.E_DIALOGUE).size(), 1, "九陽到 10：直接開對話")

func test_story_review4_two_quests_on_one_npc_show_menu() -> void:
	if not game_ok():
		return
	make_char()
	# 兩條任務的目前目標都在雲兒身上：q_yuner 的 s_choose、孤鴻子的家書（找出一條在雲兒身上有對話目標的其他任務）
	var other := ""
	var other_stage := ""
	for qid in tables()["quests"]:
		if qid == "q_yuner":
			continue
		for st in host().quests.quest_row(qid).get("stages", []):
			for o in st.get("objectives", []):
				if str(o.get("npc", "")) == "n_xx_yuner" and str(o.get("dialogue", "")) != "" and other == "":
					other = qid
					other_stage = str(st["id"])
	assert_true(other != "", "有另一條任務的目標在雲兒身上")
	if other == "":
		return
	assert_true(host().quests.debug_stage(s(), "q_yuner", "s_choose").get("ok", false))
	assert_true(host().quests.debug_stage(s(), other, other_stage).get("ok", false))
	goto("xx_minfang")
	clear_events()
	ok("talk", { "npc": "n_xx_yuner" })
	ws.flush()
	assert_eq(evs(Protocol.E_DIALOGUE).size(), 0, "兩條任務都能談：不替玩家挑")
	assert_eq(evs(Protocol.E_NPC_MENU).size(), 1, "送選單，兩條任務都點得到")
	var ids: Array = host().quests.menu_entries(s(), "n_xx_yuner").map(func(e): return str(e.get("id", "")))
	assert_true(ids.has("q_yuner") and ids.has(other), str(ids))

# ---------------------------------------------------------------- 追擊戰不拉新手
func test_story_review4_chase_does_not_pull_newbie_party_member() -> void:
	if not game_ok():
		return
	make_char()
	ch().combat_xp = 5000
	var p2 := add_player("新手隊友")
	var p3 := add_player("老手隊友")
	session_of(p3).character.combat_xp = 5000
	for p in [p2, p3]:
		ok("party_invite", { "target": str(session_of(p).character.id) })
		assert_true(send_as(p, "party_reply", { "from": str(ch().id), "accept": true }).get("ok", false))
	goto("xw_grass")
	goto_as(p2, "xw_grass")
	goto_as(p3, "xw_grass")
	var bid := int(host().wander._start_chase(s(), "w_nanhai"))
	assert_true(bid != 0, "開了追擊戰")
	assert_eq(s().battle_id, bid)
	assert_eq(session_of(p2).battle_id, 0, "實戰未滿保護線的新手隊友不被拉進不能逃的追擊戰")
	assert_eq(session_of(p3).battle_id, bid, "老手隊友照樣一起入場")

# ---------------------------------------------------------------- 傳聞
func test_story_review4_welcome_skips_replayed_rumor() -> void:
	if not game_ok():
		return
	make_char()
	var r = host().rumor
	# 每日預告剛好是文泰來（西夏出生的人最容易抽到的那則）
	r.flush()
	assert_true(r.post(RumorSystem.KIND_FORESHADOW, "rmr_q_wentailai_fs", { "quest_name": "x" }), "每日預告")
	ws.flush()
	ch().ext.get_or_add("ambient", {}).erase(RumorSystem.WELCOME_KEY)
	for i in 20:
		var row: Dictionary = r.pick_foreshadow("", s(), { "q_wentailai": true })
		assert_true(str(row.get("quest", "")) != "q_wentailai", "skip 生效")
	clear_events()
	assert_true(r.welcome_foreshadow(s()))
	ws.flush()
	var got := evs(Protocol.E_RUMOR)
	assert_eq(got.size(), 1)
	if got.size() > 0:
		assert_true(str(got[0].get("p", {}).get("text_key", "")) != "rmr_q_wentailai_fs", "歡迎風聲不重複登入補送的那一則")
	assert_eq(r._quest_of_text("rmr_q_wentailai_fs"), "q_wentailai")

func test_story_review4_daily_avoids_welcomed_quest() -> void:
	if not game_ok():
		return
	make_char()
	var r = host().rumor
	r._welcomed["q_wentailai"] = host().now_s()
	var c: Dictionary = host().clock()
	for i in 10:
		r.flush()
		ws.world.get("rumors", []).clear()
		clear_events()
		if r.maybe_foreshadow(c):
			ws.flush()
			for e in evs(Protocol.E_RUMOR):
				assert_true(str(e.get("p", {}).get("text_key", "")) != "rmr_q_wentailai_fs", "剛對新手講過的事件，當天的全服預告先避開")

func test_story_review4_dali_newbie_welcome_prefers_yuner() -> void:
	if not game_ok():
		return
	make_char("大理新手", "dali")
	var r = host().rumor
	assert_eq(str(RumorSystem.WELCOME_PREFER.get("dali", "")), "q_yuner")
	for i in 5:
		ch().ext.get_or_add("ambient", {}).erase(RumorSystem.WELCOME_KEY)
		clear_events()
		assert_true(r.welcome_foreshadow(s()))
		ws.flush()
		var got := evs(Protocol.E_RUMOR)
		assert_eq(str(got[-1].get("p", {}).get("text_key", "")) if got.size() > 0 else "", "rmr_q_yuner_foreshadow", "大理出生的新手先聽到雲兒的事")

func test_story_review4_world_index_hops() -> void:
	if not game_ok():
		return
	var idx: WorldIndex = host().index
	assert_eq(idx.hops("xx_square", "xx_square"), 0)
	assert_eq(idx.hops("xx_square", "xx_gate_e"), 1)
	assert_eq(idx.hops("xx_square", "xx_minfang"), 2)
	assert_eq(idx.hops("xx_square", "no_such_room"), -1)
	assert_eq(idx.hops("xx_square", "dl_square", 3), -1, "超過上限回 -1")
	assert_true(idx.hops("xx_square", "dl_square") > 3)

# ---------------------------------------------------------------- 環境句不重複
func test_story_review4_ambient_line_no_repeat() -> void:
	if not game_ok():
		return
	make_char()
	ch().combat_xp = 5000
	set_shichen(10)   # 戌時
	var amb = host().ambient
	goto("xw_grass")
	var first: Dictionary = amb.pick_line(s())
	if first.is_empty():
		return   # 這裡此刻沒有環境句（資料變了）
	var only_one: bool = amb.candidates(s()).size() == 1
	assert_true(amb._send_line(s(), first))
	var again: Dictionary = amb.pick_line(s())
	assert_true(again.is_empty() or str(again.get("id", "")) != str(first.get("id", "")), "同一句不馬上再出現")
	if only_one:
		assert_true(again.is_empty(), "這一區只有一句：先安靜")
	ws.world["world_time_s"] = ws.world_time() + float(host().world_span(AmbientSystem.LINE_NO_REPEAT_REAL_S)) + 1.0
	assert_false(amb.pick_line(s()).is_empty(), "過了一段時間又聽得到")

# ---------------------------------------------------------------- 武當門檻
func test_story_review4_wudang_gates_follow_2001_08_07() -> void:
	if not game_ok():
		return
	var lm: Array = tables()["quests"]["q_wd_longmen"]["requires"]
	var tj: Array = tables()["quests"]["q_wd_taiji"]["requires"]
	var want_lm := { "wit": 25, "cal": 25 }
	var want_tj := { "str": 26, "cal": 22, "agi": 22, "con": 22 }
	for pair in [[lm, want_lm, "龍門遺案 = 真武七截陣 悟25 定25"], [tj, want_tj, "太極拳 臂26 定22 機22 根22"]]:
		var got := {}
		for c in pair[0]:
			if str(c.get("type", "")) == "attr_min":
				got[str(c["attr"])] = int(c["value"])
		assert_eq(got, pair[1], pair[2])
	make_char()
	ch().sect = "wudang"
	for k in ch().attrs:
		ch().attrs[k] = 20
	ch().attrs["wit"] = 25
	ch().attrs["cal"] = 25
	assert_eq(host().quests.can_accept(s(), "q_wd_longmen"), "", "悟25 定25 就接得了龍門遺案（2001 真武七截陣門檻）")

# ---------------------------------------------------------------- NPC 換話
func _talk_key_after(npc: String) -> String:
	return str(host().ambient.talk_key(s(), npc))

func test_story_review4_npcs_react_to_player_deeds() -> void:
	if not game_ok():
		return
	make_char()
	set_shichen(6)
	assert_eq(_talk_key_after("n_xx_laodenuo"), "talk_n_xx_laodenuo")
	ch().quests["done"]["q_hs_spy"] = { "n": 1, "outcome": "default", "world_s": 0.0, "failed": 0 }
	assert_eq(_talk_key_after("n_xx_laodenuo"), "talk_n_xx_laodenuo@q_hs_spy", "拿下勞德諾的人看到他被綁著")
	ch().quests["done"]["q_xd_caihua"] = { "n": 1, "outcome": "zhuzhu", "world_s": 0.0, "failed": 0 }
	assert_eq(_talk_key_after("n_xx_zhugeyi"), "talk_n_xx_zhugeyi@q_caihua")
	assert_eq(_talk_key_after("n_xx_zhuzhu"), "talk_n_xx_zhuzhu@q_caihua")
	assert_eq(_talk_key_after("n_dl_cuisou"), "talk_n_dl_cuisou", "走豬哥義那條路的人，崔叟照舊")
	ch().quests["done"]["q_mailu_shangren"] = { "n": 1, "outcome": "default", "world_s": 0.0, "failed": 0 }
	assert_eq(_talk_key_after("n_dl_furen"), "talk_n_dl_furen@q_mailu", "信送到了，婦人不再說「過了半個月」")
	for k in ["talk_n_xx_laodenuo@q_hs_spy", "talk_n_xx_zhugeyi@q_caihua", "talk_n_xx_zhuzhu@q_caihua", "talk_n_dl_cuisou@q_caihua",
			"talk_n_dl_furen@q_mailu", "talk_n_dl_furen@q_mailu_night", "talk_n_wd_dl_oldman@F"]:
		assert_true(tables()["text_templates"].has(k), k)

func test_story_review4_cuisou_reacts_mid_quest() -> void:
	if not game_ok():
		return
	make_char()
	set_shichen(6)
	assert_true(host().quests.debug_stage(s(), "q_xd_caihua", "s_report").get("ok", false))
	ch().quests["active"]["q_xd_caihua"]["vars"]["route"] = "cuisou"
	assert_eq(_talk_key_after("n_dl_cuisou"), "talk_n_dl_cuisou@q_caihua", "打贏崔叟、還沒回去覆命也算")
	assert_eq(_talk_key_after("n_xx_zhuzhu"), "talk_n_xx_zhuzhu")

func test_story_review4_gender_slips() -> void:
	if not game_ok():
		return
	make_char("女俠", "dali", { "wit": 5 }, "F")
	set_shichen(6)
	assert_eq(_talk_key_after("n_wd_dl_oldman"), "talk_n_wd_dl_oldman@F", "武當只收男弟子：不問女性玩家是不是武當的人")
	var warn := str(tables()["text_templates"]["amb_xx_street_newbie_warn"].get("self", ""))
	assert_false(warn.contains("後生"), "西大街的警告不再一律叫「後生」")
	assert_true(warn.contains("{shaoxia}"))
	var quests_txt := JSON.stringify(tables()["quests"])
	assert_false(quests_txt.contains("伙計"), "台灣用字：夥計")
	var yuner: Dictionary = host().quests.quest_row("q_yuner")
	for st in yuner["stages"]:
		if str(st["id"]) in ["s_abao", "s_thanks"]:
			assert_true(str(st.get("log", "")).contains("野狼"), "%s 提醒城北山坡有野狼" % st["id"])
