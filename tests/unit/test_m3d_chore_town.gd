extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §6.1、§6.3、§10.1（WP-ERRANDS）：chore 欄位通用化。
## chore.kind TOWN：任何人、學點不受新手期與規則 chore_xuedian 限制、照樣每日遞減、不算進新手期一輩子上限；
## decay_all：遞減也縮放銀兩、名聲、歷練（含任務中途的 reward 動作）；結局 no_chore 不算一次；
## 城鎮學點任務（送便當、鬥酒、李大嬸）；M3c2 的 SECT 雜務行為不變（test_m3c2_chores 照過，這裡另抽查）。

const A := preload("res://tests/unit/test_m3c_npc_attack.gd")

func _char(city := "xixia") -> bool:
	if not game_ok():
		return false
	if make_char("跑腿的人", city) == null:
		return false
	ws.options["encounters_enabled"] = false
	Survival.rest_full(ch(), tables(), ws.options)
	clear_events()
	return true

## 撥到下一個遊戲日的開頭（子時換日；再撥時辰）
func _to_day_start() -> void:
	var day: float = host().day_s()
	ws.world["world_time_s"] = (floorf(ws.world_time() / day) + 1.0) * day + 1.0
	ws.advance(0.1)

func _pick(npc: String, qid: String, node: String, choice: String) -> void:
	ok("dialogue_choose", { "npc": npc, "quest": qid, "node": node, "choice": choice })

func _chore_n(qid: String) -> int:
	var cd: Variant = ch().counters.get("chore_day", {})
	return int((cd as Dictionary).get("n", {}).get(qid, 0)) if cd is Dictionary else 0

## 送一次西夏便當（午時接）；回傳學點增加量
func _biandang_xx() -> int:
	var lp0 := int(ch().learn_points)
	goto("xx_minfang")
	ok("quest_accept", { "npc": "n_er_xx_funv", "quest": "q_er_biandang_xx" })
	_pick("n_er_xx_funv", "q_er_biandang_xx", "n0", "c_yes")
	assert_eq(item_count("i_er_biandang"), 1, "拿到便當")
	goto("hf_paddy")
	ok("quest_talk", { "npc": "n_er_xx_nongfu", "quest": "q_er_biandang_xx" })
	_pick("n_er_xx_nongfu", "q_er_biandang_xx", "n0", "c_give")
	assert_eq(item_count("i_er_biandang"), 0, "便當交出去了")
	assert_false(QuestState.is_active(ch().quests, "q_er_biandang_xx"), "完成")
	return int(ch().learn_points) - lp0

# ---------------------------------------------------------------- 純邏輯
func test_static_helpers() -> void:
	var c := { "kind": "TOWN", "lp": 50, "decay_pct": [100, 60, 30, 10, 0] }
	assert_true(QuestSystem.is_town(c))
	assert_false(QuestSystem.is_town({ "sect": "shaolin", "lp": 30 }), "沒寫 kind ＝ SECT")
	var got: Array = []
	for n in 6:
		got.append(int(QuestSystem.town_lp(c, n)["lp"]))
	assert_eq(got, [50, 30, 15, 5, 0, 0])
	assert_eq(str(QuestSystem.town_lp(c, 4)["why"]), "daily")
	assert_eq(str(QuestSystem.town_lp({ "kind": "TOWN", "lp": 0, "decay_pct": [100, 0] }, 1)["why"]), "", "lp 本來就是 0：不提示")
	var rw := QuestSystem.scale_decay_all({ "money": 200, "fame": 8, "lilian": 5, "combat_xp": 3, "learn_points": 7, "morality": 5 }, 60)
	assert_eq(int(rw["money"]), 120)
	assert_eq(int(rw["fame"]), 4, "floor(8 × 0.6)")
	assert_eq(int(rw["lilian"]), 3)
	assert_eq(int(rw["combat_xp"]), 1)
	assert_eq(int(rw["learn_points"]), 4)
	assert_eq(int(rw["morality"]), 5, "善惡不縮放")
	assert_eq(int(QuestSystem.scale_decay_all({ "money": -40 }, 0)["money"]), -40, "負值（代價）不縮放")
	assert_eq(QuestSystem.chore_pct({ "decay_pct": [100, 60] }, 9), 60, "超過長度用最後一個")

func test_town_rows_shape() -> void:
	var qs: Dictionary = tables()["quests"]
	for qid in ["q_er_kezhene", "q_er_zhugeyi", "q_er_biandang_xx", "q_er_biandang_dl", "q_er_zuigui", "q_ym_douji"]:
		var c: Dictionary = qs[qid].get("chore", {})
		assert_eq(str(c.get("kind", "")), "TOWN", "%s chore.kind" % qid)
		assert_eq(int(qs[qid]["repeat"]["max"]), 0, "%s 可重複" % qid)
		var dp: Array = c["decay_pct"]
		assert_true(int(dp[dp.size() - 1]) <= 30, "%s 遞減到底 ≤ 30" % qid)
	assert_true(bool(qs["q_er_kezhene"]["chore"]["decay_all"]))
	assert_true(bool(qs["q_er_zhugeyi"]["chore"]["decay_all"]))
	assert_false(qs["q_ym_douji"]["outcomes"]["win"]["rewards"].has("learn_points"), "鬥酒學點改由 chore.lp")
	assert_true(bool(qs["q_ym_douji"]["outcomes"]["drunk"].get("no_chore", false)))

# ---------------------------------------------------------------- 送便當：遞減、不受新手期
func test_biandang_decay_and_day_reset() -> void:
	if not _char():
		return
	_to_day_start()
	set_shichen(6)   # 午
	var got: Array = []
	for i in 5:
		got.append(_biandang_xx())
	assert_eq(got, [50, 30, 15, 5, 0], "學點 50 遞減 100/60/30/10/0")
	assert_eq(_chore_n("q_er_biandang_xx"), 5, "counters.chore_day")
	assert_false(evs("ch_no_lp").is_empty(), "遞減到 0 → ch_no_lp")
	assert_eq(str(lastp("ch_no_lp").get("why", "")), "daily")
	assert_true(str(lastp("ch_no_lp").get("text", "")).contains("跑了好幾趟"), "城鎮用自己的提示文字（不是師兄）")
	assert_eq(int(ch().counters.get("novice_lp", 0)), 0, "TOWN 學點不算進新手期一輩子上限")
	_to_day_start()
	set_shichen(6)
	assert_eq(_biandang_xx(), 50, "換日重設")

func test_biandang_only_at_noon() -> void:
	if not _char():
		return
	set_shichen(5)   # 巳
	goto("xx_minfang")
	assert_eq(reason("quest_accept", { "npc": "n_er_xx_funv", "quest": "q_er_biandang_xx" }), "req_hour_in")
	set_shichen(6)
	goto("xx_minfang")
	ok("quest_accept", { "npc": "n_er_xx_funv", "quest": "q_er_biandang_xx" })

func test_town_ignores_novice_window() -> void:
	if not _char():
		return
	ch().combat_xp = 500000   # 早就不是新手（novice_xp_below）
	ch().sect = "shaolin"
	ch().skills.set_level("sl_changquan", 80, tables())
	assert_false(Learning.is_novice(ch(), tables(), host().rules), "前提：不是新手")
	_to_day_start()
	set_shichen(6)
	assert_eq(_biandang_xx(), 50, "TOWN 學點照給")

func test_town_ignores_chore_xuedian_rule() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	if not _char():
		return
	assert_false(host().rules.get("chore_xuedian", true), "前提：classic_strict 關掉門派雜務學點")
	_to_day_start()
	set_shichen(6)
	assert_eq(_biandang_xx(), 50, "TOWN 學點是原作獎勵，不受 chore_xuedian 限制")

func test_biandang_dali() -> void:
	if not _char("dali"):
		return
	_to_day_start()
	set_shichen(6)
	var lp0 := int(ch().learn_points)
	goto("dl_square")
	ok("quest_accept", { "npc": "n_dl_furen", "quest": "q_er_biandang_dl" })
	_pick("n_dl_furen", "q_er_biandang_dl", "n0", "c_yes")
	goto("dlw_paddy")
	ok("quest_talk", { "npc": "n_sm_qiaofu_dl", "quest": "q_er_biandang_dl" })
	_pick("n_sm_qiaofu_dl", "q_er_biandang_dl", "n0", "c_give")
	assert_eq(int(ch().learn_points) - lp0, 50)
	assert_eq(_chore_n("q_er_biandang_dl"), 1)
	assert_eq(_chore_n("q_er_biandang_xx"), 0, "兩城的便當分開計數")

# ---------------------------------------------------------------- decay_all：柯鎮惡 → 郭靖
func test_kezhene_decay_all() -> void:
	if not _char():
		return
	ch().fame = 500
	ch().lilian = 500
	_to_day_start()
	var fames: Array = []
	var lils: Array = []
	for i in 7:
		var f0 := int(ch().fame)
		var l0 := int(ch().lilian)
		goto("mw_snow")
		ok("quest_accept", { "npc": "n_er_kezhene", "quest": "q_er_kezhene" })
		_pick("n_er_kezhene", "q_er_kezhene", "n0", "c_ask")
		_pick("n_er_kezhene", "q_er_kezhene", "n1", "c_yes")
		assert_eq(item_count("i_er_ke_xin"), 1, "柯鎮惡的信")
		goto("zn_bridge")
		ok("quest_talk", { "npc": "n_er_guojing", "quest": "q_er_kezhene" })
		_pick("n_er_guojing", "q_er_kezhene", "n0", "c_give")
		assert_eq(item_count("i_er_ke_xin"), 0)
		fames.append(int(ch().fame) - f0)
		lils.append(int(ch().lilian) - l0)
	assert_eq(fames, [5, 5, 4, 3, 2, 1, 0], "名聲 100/100/80/60/40/20/0%")
	assert_eq(lils, [20, 20, 16, 12, 8, 4, 0], "歷練同樣遞減")
	assert_true(evs("ch_no_lp").is_empty(), "lp 本來就是 0：不送沒有學點的提示")

# ---------------------------------------------------------------- 鬥酒：TOWN 學點 40、醉倒不算
func _douji(win: bool) -> Dictionary:
	goto("xx_inn")
	set_shichen(7)   # 未
	goto("xx_inn")
	ok("quest_accept", { "npc": "n_xx_qiaofeng", "quest": "q_ym_douji" })
	_pick("n_xx_qiaofeng", "q_ym_douji", "n0", "c_ask")
	_pick("n_xx_qiaofeng", "q_ym_douji", "n1", "c_yes")
	if win:
		ch().skills.set_level("basic_inner", 50, tables())
	else:
		for at in ["con", "str"]:
			ch().attrs[at] = 10
		ch().skills.set_level("basic_inner", 0, tables())
	var lp0 := int(ch().learn_points)
	var lil0 := int(ch().lilian)
	ok("story_act", { "act": "q_ym_douji:a_pour" })
	return { "lp": int(ch().learn_points) - lp0, "lilian": int(ch().lilian) - lil0,
		"outcome": str(QuestState.done_entry(ch().quests, "q_ym_douji").get("outcome", "")) }

func test_douji_win_town_lp_in_strict() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	if not _char():
		return
	var d := _douji(true)
	assert_eq(str(d["outcome"]), "win")
	assert_eq(int(d["lp"]), 40, "鬥酒學點 40（TOWN，strict 照給）")
	assert_eq(int(d["lilian"]), 3, "歷練 3")
	assert_eq(_chore_n("q_ym_douji"), 1)

func test_douji_drunk_not_counted() -> void:
	if not _char():
		return
	var d := _douji(false)
	assert_eq(str(d["outcome"]), "drunk")
	assert_eq(int(d["lp"]), 0, "醉倒沒有學點")
	assert_eq(_chore_n("q_ym_douji"), 0, "no_chore：醉倒不算一次雜務")

# ---------------------------------------------------------------- 李大嬸（官方晚期獎勵）
func _xiaobao() -> Dictionary:
	var m0 := int(ch().money)
	var lp0 := int(ch().learn_points)
	goto("jc_street")
	ok("quest_accept", { "npc": "n_jc_lidashen", "quest": "q_jc_xiaobao" })
	_pick("n_jc_lidashen", "q_jc_xiaobao", "n0", "_next")
	_pick("n_jc_lidashen", "q_jc_xiaobao", "n1", "c_help")
	goto("jc_zijin")
	ok("quest_talk", { "npc": "n_jc_zijin_guard", "quest": "q_jc_xiaobao" })
	_pick("n_jc_zijin_guard", "q_jc_xiaobao", "n0", "c_ask")
	_pick("n_jc_zijin_guard", "q_jc_xiaobao", "n1", "_next")
	ok("quest_talk", { "npc": "n_jc_xiaobao", "quest": "q_jc_xiaobao" })
	_pick("n_jc_xiaobao", "q_jc_xiaobao", "n0", "c_mom")
	_pick("n_jc_xiaobao", "q_jc_xiaobao", "n1", "c_promise")
	for d in ["SE", "S", "W"]:   # 帶著小保走回京城大街（瞬移會讓護送對象走散）
		ok("move", { "dir": d })
	assert_eq(s().room_id(), "jc_street")
	ok("quest_talk", { "npc": "n_jc_lidashen", "quest": "q_jc_xiaobao" })
	_pick("n_jc_lidashen", "q_jc_xiaobao", "n0", "_next")
	_pick("n_jc_lidashen", "q_jc_xiaobao", "n1", "_next")
	return { "money": int(ch().money) - m0, "lp": int(ch().learn_points) - lp0,
		"outcome": str(QuestState.done_entry(ch().quests, "q_jc_xiaobao").get("outcome", "")) }

func test_xiaobao_young() -> void:
	if not _char():
		return
	ch().combat_xp = 500
	var d := _xiaobao()
	assert_eq(str(d["outcome"]), "young")
	assert_eq(int(d["money"]), 200, "實戰 < 700：200 兩")
	assert_eq(int(d["lp"]), 10, "學點 10")

func test_xiaobao_veteran() -> void:
	if not _char():
		return
	ch().combat_xp = 5000
	var d := _xiaobao()
	assert_eq(str(d["outcome"]), "default")
	assert_eq(int(d["money"]), 100)
	assert_eq(int(d["lp"]), 5)

# ---------------------------------------------------------------- SECT 雜務照舊（抽查）
func test_sect_chore_unchanged() -> void:
	if not _char():
		return
	ws.options["sect_hostile_entry"] = false
	ch().sect = "shaolin"
	host().sects.on_join(s(), "shaolin", str(tables()["sects"]["shaolin"].get("head_npc", "")))
	_to_day_start()
	set_shichen(1)
	goto("sl_court")
	var lp0 := int(ch().learn_points)
	ok("quest_accept", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_saodi" })
	ok("story_act", { "act": "q_ch_sl_saodi:a_work" })
	ok("quest_turn_in", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_saodi" })
	var c: Dictionary = tables()["quests"]["q_ch_sl_saodi"]["chore"]
	assert_eq(int(ch().learn_points) - lp0, int(c["lp"]), "SECT 雜務學點照 M3c2")
	assert_true(int(ch().counters.get("novice_lp", 0)) > 0, "SECT 雜務照樣算進新手期上限")
