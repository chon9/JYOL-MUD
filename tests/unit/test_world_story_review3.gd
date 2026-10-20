extends "res://tests/unit/test_world_fixture.gd"
## 故事包第三輪審查修正的回歸測試（方法名 test_story_review3_*；--filter=story_review3 可單跑）。
## - 藍鳳凰：第一次完成「基本毒術升一級」（2001）；再做照台免給熟練 +50、不再升級；基本毒術 ≥ 30 接不了（台免門檻）
## - 放棄任務不能重領中途獎勵（reward 動作、learn add）；完成後下一輪照常發；存檔往返保留
## - 血海魔功：1.0A 列用 2001 門檻（拿到 1 級的人練得動）；2002-08 的門檻在 xkd 資料片
## - 依性別的稱呼佔位字（{honorific} 等）；初次見面的 NPC 不用角色名稱呼
## - 環境句 first_visit：新手第一次走上西大街一定聽到惡人警告；站久了也會聽到閒話
## - 新角色第一次登入有一則「他自己接得了」的風聲
## - 遊蕩惡人：每個惡人自己的警告句；冷卻到期會清掉；對話中被略過、對話結束後再判定

func before_each() -> void:
	world_name = "w_story_review3"
	super.before_each()

# ---------------------------------------------------------------- 藍鳳凰
func _lanfeng_finish() -> void:
	assert_true(host().quests.debug_stage(s(), "q_lanfeng", "s_return").get("ok", false), "debug_stage s_return")
	host().quests._mark_complete(s(), "q_lanfeng", "o_return")
	host().quests._settle(s(), "q_lanfeng")

func test_story_review3_lanfeng_first_level_then_repeat_prof() -> void:
	if not game_ok():
		return
	make_char()
	ch().skills.set_level("basic_poison", 3, tables())
	_lanfeng_finish()
	assert_false(ch().quests["active"].has("q_lanfeng"), "finished")
	assert_eq(QuestState.last_outcome(ch().quests, "q_lanfeng"), "default")
	assert_eq(int(ch().skills.level("basic_poison")), 4, "第一次：基本毒術升一級（2001）")
	# 冷卻過後再做：台免的熟練 +50，不再升一級
	ch().quests["cd"].erase("q_lanfeng")
	var prof0 := int(ch().skills.prof("basic_poison"))
	_lanfeng_finish()
	assert_eq(QuestState.last_outcome(ch().quests, "q_lanfeng"), "repeat", "第二次走 repeat 結局")
	var lv := int(ch().skills.level("basic_poison"))
	assert_true(lv == 4 and int(ch().skills.prof("basic_poison")) > prof0 or lv == 5 and int(ch().skills.prof("basic_poison")) < prof0,
		"熟練 +50（剛好升級也只能是熟練溢出）：lv %d prof %d -> %d" % [lv, prof0, int(ch().skills.prof("basic_poison"))])
	var rp: Dictionary = tables()["quests"]["q_lanfeng"]["outcomes"]["repeat"]
	assert_eq(int(rp["rewards"]["skill_prof"]["basic_poison"]), 50)
	assert_true((rp["rewards"].get("learn_add", {}) as Dictionary).is_empty(), "repeat 不升級")
	assert_eq(str(rp.get("src", "")), "later")

func test_story_review3_lanfeng_gate_basic_poison_below_30() -> void:
	if not game_ok():
		return
	make_char()
	ch().attrs["luck"] = 25
	ch().skills.set_level("basic_poison", 29, tables())
	assert_eq(host().quests.can_accept(s(), "q_lanfeng"), "", "29 級還接得了")
	ch().skills.set_level("basic_poison", 30, tables())
	assert_eq(host().quests.can_accept(s(), "q_lanfeng"), "req_skill_max", "台免：基本毒術 < 30 才接得了")
	var d := Requirements.describe({ "type": "skill_max", "skill": "basic_poison", "value": 29 }, tables())
	assert_true(d.contains("29") and d.contains("以下"), d)
	assert_true(tables()["text_templates"].has("err_req_skill_max"))

# ---------------------------------------------------------------- 放棄不能重領
func test_story_review3_abandon_does_not_repay_mid_quest_rewards() -> void:
	if not game_ok():
		return
	make_char()
	var rw := [{ "do": "reward", "rewards": { "money": 200 } }]
	for round in 3:
		assert_true(host().quests.debug_stage(s(), "q_em_baifang", "s_hufei").get("ok", false), "accept round %d" % round)
		var m0 := int(ch().money)
		host().quests._run_actions(s(), "q_em_baifang", "", rw)
		if round == 0:
			assert_eq(int(ch().money) - m0, 200, "第一次照發")
		else:
			assert_eq(int(ch().money) - m0, 0, "放棄後重接：同一筆中途獎勵不再發（round %d）" % round)
		ok("quest_abandon", { "quest": "q_em_baifang" })
	# 同一輪裡第二筆一樣的獎勵（抵掉的只有上一輪領過的次數）
	assert_true(host().quests.debug_stage(s(), "q_em_baifang", "s_hufei").get("ok", false))
	var m1 := int(ch().money)
	host().quests._run_actions(s(), "q_em_baifang", "", rw)
	host().quests._run_actions(s(), "q_em_baifang", "", rw)
	assert_eq(int(ch().money) - m1, 200, "上一輪領過一次：這一輪第一筆抵掉、第二筆照發")

func test_story_review3_abandon_repeatable_daily_reward_then_complete_pays_again() -> void:
	if not game_ok():
		return
	make_char()
	ch().sect = "wudang"
	var rw := [{ "do": "reward", "rewards": { "skill_prof": { "xiayi": 250 } } }]
	assert_true(host().quests.debug_stage(s(), "q_chendabao", "s_zeitou").get("ok", false))
	var p0 := int(ch().skills.prof("xiayi")) + int(ch().skills.level("xiayi")) * 100000
	host().quests._run_actions(s(), "q_chendabao", "", rw)
	var p1 := int(ch().skills.prof("xiayi")) + int(ch().skills.level("xiayi")) * 100000
	assert_true(p1 > p0, "第一次俠義照發")
	ok("quest_abandon", { "quest": "q_chendabao" })
	assert_true(ch().quests.has(QuestState.PAID_KEY), "放棄時記下已領的中途獎勵")
	# 存檔往返保留
	var back: Dictionary = QuestState.migrate(JSON.parse_string(JSON.stringify(ch().quests)))
	assert_eq(back.get(QuestState.PAID_KEY, {}), ch().quests[QuestState.PAID_KEY], "paid 存檔往返")
	assert_true(host().quests.debug_stage(s(), "q_chendabao", "s_zeitou").get("ok", false))
	host().quests._run_actions(s(), "q_chendabao", "", rw)
	var p2 := int(ch().skills.prof("xiayi")) + int(ch().skills.level("xiayi")) * 100000
	assert_eq(p2, p1, "重接後不再發")
	# 完成之後清掉，下一輪（冷卻過後）照常發
	host().quests._finish(s(), "q_chendabao", "default")
	assert_false(ch().quests.get(QuestState.PAID_KEY, {}).has("q_chendabao"), "完成時清掉")
	ch().quests["cd"].erase("q_chendabao")
	assert_true(host().quests.debug_stage(s(), "q_chendabao", "s_zeitou").get("ok", false))
	var p3 := int(ch().skills.prof("xiayi")) + int(ch().skills.level("xiayi")) * 100000
	host().quests._run_actions(s(), "q_chendabao", "", rw)
	assert_true(int(ch().skills.prof("xiayi")) + int(ch().skills.level("xiayi")) * 100000 > p3, "下一輪照常發")

func test_story_review3_abandon_does_not_repay_learn_add() -> void:
	if not game_ok():
		return
	make_char()
	ch().skills.set_level("basic_poison", 2, tables())
	var act := [{ "do": "learn", "skill": "basic_poison", "add": 1 }]
	assert_true(host().quests.debug_stage(s(), "q_lanfeng", "s_collect").get("ok", false))
	host().quests._run_actions(s(), "q_lanfeng", "", act)
	assert_eq(int(ch().skills.level("basic_poison")), 3)
	ok("quest_abandon", { "quest": "q_lanfeng" })
	assert_true(host().quests.debug_stage(s(), "q_lanfeng", "s_collect").get("ok", false))
	host().quests._run_actions(s(), "q_lanfeng", "", act)
	assert_eq(int(ch().skills.level("basic_poison")), 3, "放棄後重接：learn add 不再升")

func test_story_review3_baifang_quiz_money_not_farmable_by_abandon() -> void:
	if not game_ok():
		return
	make_char("峨嵋測試", "dali", { "wit": 5 }, "F")
	ch().sect = "emei"
	var row: Dictionary = tables()["quests"]["q_em_baifang"]
	var pay: Array = []
	# 找出對話裡發錢的中途獎勵（韋小寶的考題 200 兩）
	for dn in row.get("dialogues", {}):
		for nid in row["dialogues"][dn].get("nodes", {}):
			var n: Dictionary = row["dialogues"][dn]["nodes"][nid]
			for c in n.get("choices", []):
				for a in c.get("do", []):
					if a is Dictionary and str(a.get("do", "")) == "reward" and int(a.get("rewards", {}).get("money", 0)) > 0:
						pay.append(a)
	assert_true(pay.size() >= 1, "q_em_baifang 有發錢的中途獎勵")
	if pay.is_empty():
		return
	var gained: Array = []
	for round in 3:
		assert_true(host().quests.debug_stage(s(), "q_em_baifang", str(row["start"])).get("ok", false))
		var m0 := int(ch().money)
		host().quests._run_actions(s(), "q_em_baifang", "", [pay[0]])
		gained.append(int(ch().money) - m0)
		ok("quest_abandon", { "quest": "q_em_baifang" })
	assert_eq(gained, [int(pay[0]["rewards"]["money"]), 0, 0], "一次性任務：放棄重接不能重領")

# ---------------------------------------------------------------- 血海魔功
func test_story_review3_xuehai_2001_gates_on_1_0a_row() -> void:
	if not game_ok():
		return
	var row: Dictionary = tables()["martial_arts"]["xd_xuehai"]
	var types := {}
	for c in row["requires"]:
		types[str(c.get("type", "")) + ":" + str(c.get("skill", ""))] = int(c.get("value", 0))
	assert_eq(types.get("skill_min:basic_inner"), 60)
	assert_eq(types.get("skill_min:basic_blade"), 50)
	assert_eq(types.get("skill_min:weihe"), 50)
	assert_false(types.has("combat_xp_min:"), "2002-08 的實戰 300 萬不在 1.0A 列")
	assert_false(types.has("morality_max:"), "善惡 −900 不在 1.0A 列")
	# 拿到 1 級的人（照 q_xd_xuehai 的 2001 門檻）練得動
	make_char()
	var c = ch()
	c.sect = "xuedao"
	c.flags["xd_xuehai_lv1"] = true
	c.skills.set_level("basic_inner", 60, tables())
	c.skills.set_level("basic_blade", 50, tables())
	c.skills.set_level("weihe", 50, tables())
	c.skills.set_level("xd_xuehai", 1, tables())
	assert_eq(Requirements.check(row["requires"], c, tables(), ws.options, host().rules), "", "2001 門檻夠了就能自修")
	# 2002-08 的數字移到 xkd 資料片
	var later: Dictionary = GameData.loader.activate(["1.0A", "1.0B", "gmdk", "xkd"])
	var lrow: Dictionary = later.get("martial_arts", {}).get("xd_xuehai", {})
	var has_xp := false
	for cc in lrow.get("requires", []):
		if str(cc.get("type", "")) == "combat_xp_min" and int(cc.get("value", 0)) == 3000000:
			has_xp = true
	assert_true(has_xp, "xkd 起照 2002-08 門檻")

# ---------------------------------------------------------------- 稱呼
func test_story_review3_gender_address_tokens() -> void:
	if not game_ok():
		return
	make_char("女俠客", "xixia", { "wit": 5 }, "F")
	assert_eq(GameHost.fill_address("這位{honorific}、{shidi}、{shaoxia}、{gege}", ch()), "這位姑娘、師妹、女俠、姊姊")
	clear_events()
	host().tell(s(), Protocol.CH_SCENE, "talk_n_xx_qiaofeng", { "npc_name": "喬峰" })
	ws.flush()
	var p := lastp("talk_n_xx_qiaofeng")
	assert_eq(str(p.get("honorific", "")), "姑娘", "模板有 {honorific} 時主機補上稱呼")
	# 男女都能接的任務：初次見面不用角色名稱呼
	for qid in ["q_liu_jinpen", "q_xingxia"]:
		var t := JSON.stringify(tables()["quests"][qid].get("dialogues", {}))
		assert_false(t.contains("這位{name}") or t.contains("你這{name}"), qid + " 不用角色名當稱呼")
	for key in ["talk_n_lj_baiyong", "talk_n_dl_licaifeng", "talk_n_dl_wangdafu"]:
		var self_t := str(tables()["text_templates"][key].get("self", ""))
		assert_false(self_t.contains("妳") or self_t.contains("姑娘") or self_t.contains("小師父"), key + " 公開場合不分性別")

# ---------------------------------------------------------------- 環境句
func test_story_review3_newbie_hears_street_warning_on_first_visit() -> void:
	if not game_ok():
		return
	make_char()
	set_shichen(6)   # 午時（白天）
	ws.options["ambient_lines"] = true
	var amb = host().ambient
	goto("xx_square")
	amb.on_enter_room(s())
	clear_events()
	goto("xx_street")
	amb.on_enter_room(s())
	ws.flush()
	assert_eq(evs("amb_xx_street_newbie_warn").size(), 1, "第一次走上西大街一定聽到警告（不擲骰）")
	clear_events()
	goto("xx_square")
	goto("xx_street")
	var got: Dictionary = amb.first_visit_line(s())
	assert_true(got.is_empty() or str(got.get("id", "")) != "amb_xx_street_newbie_warn", "第一次之後就照權重")

func test_story_review3_idle_line_after_standing_still() -> void:
	if not game_ok():
		return
	make_char()
	set_shichen(6)
	var amb = host().ambient
	goto("xx_square")
	amb.tick(0.0)
	amb.tick(0.0)
	clear_events()
	var sent := false
	for i in 40:
		ws.world["world_time_s"] = ws.world_time() + float(host().world_span(AmbientSystem.IDLE_LINE_REAL_S)) + 1.0
		amb._next_line_s.erase(s().peer_id)
		if amb._maybe_idle_line(s()):
			sent = true
			break
	assert_true(sent, "站在西夏廣場不動，過一陣子也會聽到閒話")

func test_story_review3_dali_newbie_has_story_hook() -> void:
	if not game_ok():
		return
	make_char("大理新手", "dali")
	set_shichen(6)
	goto("dl_square")
	var hook: Dictionary = host().ambient.first_visit_line(s())
	assert_eq(str(hook.get("id", "")), "amb_dl_hook_yuner", "大理出生的新手第一次在城裡走動就聽到雲兒的事")

# ---------------------------------------------------------------- 傳聞
func test_story_review3_welcome_foreshadow_once_for_new_character() -> void:
	if not game_ok():
		return
	make_char("大理新人", "dali")
	var r = host().rumor
	ch().ext.get_or_add("ambient", {}).erase(RumorSystem.WELCOME_KEY)
	clear_events()
	assert_true(r.welcome_foreshadow(s()), "新角色送一則風聲")
	ws.flush()
	var got := evs(Protocol.E_RUMOR)
	assert_eq(got.size(), 1)
	var key := str(got[0].get("p", {}).get("text_key", ""))
	var qid := ""
	for rid in tables()["rumors"]:
		if str(tables()["rumors"][rid].get("text", "")) == key:
			qid = str(tables()["rumors"][rid].get("quest", ""))
	assert_true(qid != "" and host().quests.can_accept(s(), qid) == "", "是他自己接得了的事件：%s" % qid)
	assert_false(r.welcome_foreshadow(s()), "每角色一次")
	# 地區權重：給予者在出生城（西夏、大理）的事件比遠方的事件重
	assert_eq(r._local_mult("q_yuner", s()), RumorSystem.CITY_WEIGHT_MULT, "雲兒在西夏城（出生城之一）")
	assert_eq(r._local_mult("q_xingxia", s()), 1, "雁門關的事件不加權")

# ---------------------------------------------------------------- 遊蕩惡人
func test_story_review3_villain_specific_warning_and_cooldown_prune() -> void:
	if not game_ok():
		return
	var w = host().wander
	assert_eq(w.warn_key("w_nanhai"), "villain_warn_w_nanhai")
	assert_eq(w.warn_key("w_unknown"), "villain_warn")
	var st: Dictionary = w.state("w_nanhai")
	var now: float = host().now_s()
	st["cd"]["old_char"] = now - 10.0
	st["cd"]["fresh_char"] = now + 1000.0
	st.get_or_add("cd_newbie", {})["old_newbie"] = now - 1.0
	assert_eq(w.prune_cooldowns(now), 2, "到期的兩筆刪掉")
	assert_false(st["cd"].has("old_char"))
	assert_true(st["cd"].has("fresh_char"), "還沒到期的留著")
	assert_false(st["cd_newbie"].has("old_newbie"))
	st["cd"]["old2"] = now - 5.0
	w._set_cd("w_nanhai", "someone", now)
	assert_false(st["cd"].has("old2"), "_set_cd 順手清到期的")

func test_story_review3_villain_rechecks_player_after_dialogue() -> void:
	if not game_ok():
		return
	make_char()
	ch().combat_xp = 5000
	ch().morality = 10
	var w = host().wander
	set_shichen(10)   # 戌時：夜遊
	ws.options["villain_warn_s"] = 30
	var ag: Dictionary = tables()["wanderers"]["w_nanhai"]["aggro"]
	var chance0 = ag.get("chance_pct", 60)
	ag["chance_pct"] = 100
	w.tick(0.0)
	assert_true(w.place("w_nanhai", "xx_square"), "先把惡人放在別處")
	goto("xw_grass")
	w.tick(0.0)
	ws.flush()
	s().dialogue = { "quest": "q_x", "npc": "n_x", "node": "n0" }   # 正在任務對話
	clear_events()
	assert_true(w.place("w_nanhai", "xw_grass"), "惡人在對話中走進來")
	w.tick(0.0)
	ws.flush()
	assert_eq(evs(Protocol.E_VILLAIN_PROMPT).size(), 0, "對話中不出手")
	s().dialogue = {}
	w.tick(0.0)
	ws.flush()
	var pr := evs(Protocol.E_VILLAIN_PROMPT)
	ag["chance_pct"] = chance0
	assert_eq(pr.size(), 1, "對話結束、人還在同房 → 再判定一次")
	if pr.size() > 0:
		assert_eq(str(pr[0].get("p", {}).get("warn_key", "")), "villain_warn_w_nanhai", "帶這個惡人自己的警告句")
	assert_eq(evs("villain_warn_w_nanhai").size(), 1, "戰報列是南海鱷神自己的警告句")
