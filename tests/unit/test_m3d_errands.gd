extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §6.2、§10.1（WP-ERRANDS）：丐幫跑腿。
## 柯鎮惡 → 郭靖的門檻與 1.0B；豬哥義 → 三八紅（粗話被拒、客氣才收、200 兩＋名聲 8、遞減含中途的 200 兩）；
## 酒鬼燒刀子酒（學點 5、拒絕被偷 40 兩、身上不夠就偷光、不算一次）；
## 武林帖（3 遊戲日冷卻、冷卻中帖子不扣、依實戰分級、只能在野外或城裡、輸了帖子用掉不設冷卻）。

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

func _to_day_start() -> void:
	var day: float = host().day_s()
	ws.world["world_time_s"] = (floorf(ws.world_time() / day) + 1.0) * day + 1.0
	ws.advance(0.1)

func _pick(npc: String, qid: String, node: String, choice: String) -> void:
	ok("dialogue_choose", { "npc": npc, "quest": qid, "node": node, "choice": choice })

func _clear_cd(qid: String) -> void:
	QuestState.ensure(ch().quests)
	(ch().quests["cd"] as Dictionary).erase(qid)

func _today() -> int:
	return int(host().clock().get("day", 0))

# ---------------------------------------------------------------- 柯鎮惡
func test_kezhene_threshold() -> void:
	if not _char():
		return
	goto("mw_snow")
	ch().fame = 499
	ch().lilian = 600
	assert_eq(reason("quest_accept", { "npc": "n_er_kezhene", "quest": "q_er_kezhene" }), "req_fame_min", "名聲不到 500")
	ch().fame = 600
	ch().lilian = 499
	assert_eq(reason("quest_accept", { "npc": "n_er_kezhene", "quest": "q_er_kezhene" }), "req_lilian_min", "歷練不到 500")
	ch().lilian = 500
	ok("quest_accept", { "npc": "n_er_kezhene", "quest": "q_er_kezhene" })
	_pick("n_er_kezhene", "q_er_kezhene", "n0", "c_ask")
	_pick("n_er_kezhene", "q_er_kezhene", "n1", "c_yes")
	assert_true(QuestState.is_active(ch().quests, "q_er_kezhene"), "門檻到了就能接")

func test_kezhene_is_1_0b_only() -> void:
	if not _char():
		return
	use_eras(["1.0A"])
	assert_false(tables()["npcs"].has("n_er_kezhene"), "1.0A 世界沒有柯鎮惡")
	assert_false(tables()["quests"].has("q_er_kezhene"))
	assert_false(tables()["npcs"].has("n_er_guojing"))
	assert_true(tables()["quests"].has("q_er_zhugeyi"), "豬哥義 → 三八紅是 1.0A")

# ---------------------------------------------------------------- 豬哥義 → 三八紅
func _zhugeyi_run(rude_first: bool) -> Dictionary:
	var m0 := int(ch().money)
	var f0 := int(ch().fame)
	goto("xx_square")
	ok("quest_accept", { "npc": "n_xx_zhugeyi", "quest": "q_er_zhugeyi" })
	_pick("n_xx_zhugeyi", "q_er_zhugeyi", "n0", "c_yes")
	assert_eq(item_count("i_er_zgy_baofu"), 1, "包袱")
	goto("dl_fangzhi")
	if rude_first:
		ok("quest_talk", { "npc": "n_er_sanbahong", "quest": "q_er_zhugeyi" })
		_pick("n_er_sanbahong", "q_er_zhugeyi", "n0", "c_rude")
		assert_eq(item_count("i_er_zgy_baofu"), 1, "粗話：她不收")
		assert_eq(int(ch().money), m0, "粗話：沒錢")
		assert_eq(str(ch().quests["active"]["q_er_zhugeyi"]["stage"]), "s_deliver", "還在送包袱")
	ok("quest_talk", { "npc": "n_er_sanbahong", "quest": "q_er_zhugeyi" })
	_pick("n_er_sanbahong", "q_er_zhugeyi", "n0", "c_polite")
	var mid_money := int(ch().money) - m0
	assert_eq(item_count("i_er_zgy_baofu"), 0, "包袱交出去")
	assert_eq(item_count("i_er_kuanyi"), 1, "拿到寬衣")
	goto("xx_square")
	ok("quest_talk", { "npc": "n_xx_zhugeyi", "quest": "q_er_zhugeyi" })
	_pick("n_xx_zhugeyi", "q_er_zhugeyi", "n0", "c_give")
	assert_eq(item_count("i_er_kuanyi"), 0, "寬衣交回去")
	assert_false(QuestState.is_active(ch().quests, "q_er_zhugeyi"))
	return { "money": mid_money, "fame": int(ch().fame) - f0 }

func test_zhugeyi_rude_then_polite() -> void:
	if not _char():
		return
	_to_day_start()
	var d := _zhugeyi_run(true)
	assert_eq(int(d["money"]), 200, "客氣：三八紅給 200 兩")
	assert_eq(int(d["fame"]), 8, "寬衣帶回去：名聲 +8")
	assert_eq(reason("quest_accept", { "npc": "n_xx_zhugeyi", "quest": "q_er_zhugeyi" }), Protocol.R_QUEST_COOLDOWN, "冷卻半天")

func test_zhugeyi_decay_all_includes_midway_money() -> void:
	if not _char():
		return
	_to_day_start()
	var got: Array = []
	for i in 4:
		_clear_cd("q_er_zhugeyi")
		var d := _zhugeyi_run(false)
		got.append([int(d["money"]), int(d["fame"])])
	assert_eq(got, [[200, 8], [120, 4], [60, 2], [0, 0]], "同一遊戲日 100/60/30/0%（銀兩與名聲）")

# ---------------------------------------------------------------- 酒鬼
func test_zuigui_refuse_steals_40() -> void:
	if not _char("dali"):
		return
	ch().money = 100
	goto("dl_bank")
	ok("quest_accept", { "npc": "n_er_dl_zuigui", "quest": "q_er_zuigui" })
	_pick("n_er_dl_zuigui", "q_er_zuigui", "n0", "c_no")
	assert_eq(int(ch().money), 60, "拒絕：被偷 40 兩")
	assert_false(evs("er_zuigui_stolen").is_empty())
	assert_false(QuestState.is_active(ch().quests, "q_er_zuigui"), "沒接任務")
	assert_eq(int((ch().counters.get("chore_day", {}) as Dictionary).get("n", {}).get("q_er_zuigui", 0)), 0, "不算一次")
	ch().money = 15
	ok("quest_accept", { "npc": "n_er_dl_zuigui", "quest": "q_er_zuigui" })
	_pick("n_er_dl_zuigui", "q_er_zuigui", "n0", "c_no")
	assert_eq(int(ch().money), 0, "身上不夠就偷光")

func test_zuigui_flow_and_decay() -> void:
	if not _char("dali"):
		return
	ch().money = 1000
	_to_day_start()
	var got: Array = []
	for i in 5:
		_clear_cd("q_er_zuigui")
		goto("dl_inn")
		ok("buy", { "npc": "n_dl_innkeeper", "item": "i_er_shaodaozi", "n": 1 })
		goto("dl_bank")
		var lp0 := int(ch().learn_points)
		ok("quest_accept", { "npc": "n_er_dl_zuigui", "quest": "q_er_zuigui" })
		_pick("n_er_dl_zuigui", "q_er_zuigui", "n0", "c_yes")
		ok("quest_talk", { "npc": "n_er_dl_zuigui", "quest": "q_er_zuigui" })
		_pick("n_er_dl_zuigui", "q_er_zuigui", "n0", "c_give")
		assert_eq(item_count("i_er_shaodaozi"), 0, "酒交出去")
		got.append(int(ch().learn_points) - lp0)
	assert_eq(got, [5, 5, 3, 1, 0], "學點 5，同一遊戲日 100/100/60/30/0%")
	assert_eq(int(tables()["items"]["i_er_shaodaozi"]["price"]), 20, "燒刀子酒 20 兩")

# ---------------------------------------------------------------- 武林帖
func test_wulintie_tiers() -> void:
	assert_eq(ErrandsSystem.wulin_monster(0), "m_er_wulin_1")
	assert_eq(ErrandsSystem.wulin_monster(19999), "m_er_wulin_1")
	assert_eq(ErrandsSystem.wulin_monster(20000), "m_er_wulin_2")
	assert_eq(ErrandsSystem.wulin_monster(99999), "m_er_wulin_2")
	assert_eq(ErrandsSystem.wulin_monster(100000), "m_er_wulin_3")
	assert_eq(ErrandsSystem.wulin_monster(499999), "m_er_wulin_3")
	assert_eq(ErrandsSystem.wulin_monster(500000), "m_er_wulin_4")
	assert_true(ErrandsSystem.wlt_ready(-1, 10), "沒打贏過")
	assert_false(ErrandsSystem.wlt_ready(10, 12), "兩天後還不行")
	assert_true(ErrandsSystem.wlt_ready(10, 13), "三天後可以")

func test_wulintie_shop() -> void:
	if not _char():
		return
	ch().money = 5000
	goto("jc_square")
	ok("buy", { "npc": "n_er_tiefan", "item": "i_er_wulintie", "n": 2 })
	assert_eq(item_count("i_er_wulintie"), 2)
	assert_eq(int(ch().money), 3000, "一張 1000 兩")

func _battle_monster() -> String:
	var entry := A.battle_entry(self, 1)
	if entry.is_empty():
		return ""
	for u in (entry["battle"] as Battle).units:
		if not u.is_player():
			return str(u.spec.get("monster_row", u.spec.get("ref", "")))
	return ""

func test_wulintie_win_cooldown() -> void:
	if not _char():
		return
	assert_true(host().get("errands") != null, "GameHost.errands 載入")
	make_strong()
	ch().combat_xp = 30000
	var uid := give("i_er_wulintie", 3)
	goto("xw_road")   # 野外
	var f0 := int(ch().fame)
	var l0 := int(ch().lilian)
	ok("use_item", { "item_uid": uid })
	assert_true(s().battle_id != 0, "開打")
	assert_eq(_battle_monster(), "m_er_wulin_2", "實戰 3 萬 → 第二階")
	assert_eq(item_count("i_er_wulintie"), 2, "用掉一張")
	assert_false(evs("er_wlt_start").is_empty())
	A.finish(self, 1, true)
	assert_eq(int(ch().fame) - f0, ErrandsSystem.WLT_FAME, "名聲 +60")
	assert_eq(int(ch().lilian) - l0, ErrandsSystem.WLT_LILIAN, "歷練 +200")
	assert_eq(int(ch().counters.get("wulintie_day", -1)), _today(), "記下打贏的遊戲日")
	assert_false(evs("er_wlt_win").is_empty())
	# 冷卻中：帖子不扣
	assert_eq(reason("use_item", { "item_uid": first_uid("i_er_wulintie") }), "wlt_cooldown")
	assert_eq(item_count("i_er_wulintie"), 2, "冷卻中帖子不扣")
	assert_eq(s().battle_id, 0)
	# 三個遊戲日後可以再下帖
	ws.world["world_time_s"] = ws.world_time() + 3.0 * host().day_s()
	ws.advance(0.1)
	Survival.rest_full(ch(), tables(), ws.options)
	goto("xw_road")
	ok("use_item", { "item_uid": first_uid("i_er_wulintie") })
	assert_true(s().battle_id != 0, "三天後再打")

func test_wulintie_loss_no_cooldown() -> void:
	if not _char():
		return
	make_strong()
	give("i_er_wulintie", 2)
	goto("xx_square")   # 城裡也可以
	ok("use_item", { "item_uid": first_uid("i_er_wulintie") })
	assert_eq(_battle_monster(), "m_er_wulin_1", "新手 → 第一階")
	var f0 := int(ch().fame)
	A.finish(self, 1, false)
	assert_eq(int(ch().fame), f0, "輸了沒有名聲")
	assert_eq(item_count("i_er_wulintie"), 1, "帖子已用掉")
	assert_eq(int(ch().counters.get("wulintie_day", -1)), -1, "輸了不設冷卻")
	assert_false(evs("er_wlt_lost").is_empty())

## M3d 審查：武林帖的戰鬥是一個人的挑戰——開戰選項 party_only（不拉隊友、別人不能中途加入）
func test_wulintie_solo_no_join() -> void:
	if not _char():
		return
	make_strong()
	give("i_er_wulintie", 1)
	goto("xw_road")
	ok("use_item", { "item_uid": first_uid("i_er_wulintie") })
	var bid := s().battle_id
	assert_true(bid != 0, "開打")
	var entry: Dictionary = host().battles.active[bid]
	assert_true(bool(entry.get("opts", {}).get("party_only", false)), "party_only：別人不能中途加入")
	assert_false(bool(entry.get("opts", {}).get("pull_party", true)), "不拉隊友")

func test_wulintie_place_rules() -> void:
	if not _char():
		return
	give("i_er_wulintie", 1)
	goto("hs_square")   # 門派地區
	assert_eq(reason("use_item", { "item_uid": first_uid("i_er_wulintie") }), "wlt_place")
	assert_eq(item_count("i_er_wulintie"), 1, "不扣帖子")
	goto("xx_inn")
	assert_eq(s().battle_id, 0)

func test_other_items_fall_through() -> void:
	if not _char():
		return
	var uid := give("c_mantou", 1)
	ch().vitals["food"] = 0
	ok("use_item", { "item_uid": uid })
	assert_true(int(ch().vitals["food"]) > 0, "一般物品照舊使用（鉤子回 {}）")

## M3d 審查第三輪：武林帖的戰鬥被中止（主機關閉 abort_all、逾時）＝沒分勝負 → 帖子退還、不設冷卻、沒有獎勵
func test_wulintie_refund_on_abort() -> void:
	if not _char():
		return
	make_strong()
	give("i_er_wulintie", 1)
	goto("xw_road")
	var f0 := int(ch().fame)
	ok("use_item", { "item_uid": first_uid("i_er_wulintie") })
	assert_true(s().battle_id != 0, "開打")
	assert_eq(item_count("i_er_wulintie"), 0, "開打時帖子先扣")
	host().battles.abort_all()
	ws.flush()
	assert_eq(s().battle_id, 0, "戰鬥中止")
	assert_eq(item_count("i_er_wulintie"), 1, "中止 → 帖子退還")
	assert_eq(int(ch().fame), f0, "沒有名聲")
	assert_eq(int(ch().counters.get("wulintie_day", -1)), -1, "不設冷卻")
	assert_false(evs("er_wlt_refund").is_empty(), "通知退帖")
	assert_true(evs("er_wlt_lost").is_empty(), "不是「輸了」")
