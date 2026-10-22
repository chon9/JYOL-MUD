extends "res://tests/unit/test_m3d_arts_base.gd"
## 0.7.0.1：四門「資料裡有、學不到」的武功接上取得途徑，與相關修正的回歸測試。
## - 劈石破玉拳（華山）：華山心法 30、儒風 10 → 自修 1–10 → 梁發教到 100（17173 2003-10-21）
## - 佛光普照掌（峨嵋）：任務「滅絕師太的絕學」靜玄 → 周芷若的信 → 張無忌 → 回答問題 → 打贏周芷若 → 鐵指環 → 滅絕 1 級 → 自修到 80
## - 四象掌（峨嵋）：佛光 50 → 羅煞劍 → 郭襄 1 級 → 郭襄教到 10 → 自修；先拿了羅煞劍的人可以「再訪郭襄」
## - 九陰真經（古墓）：【設計提案】任務「王重陽遺刻」（小梅房裡的石壁）→ 1 級 → 自修到 60，沒有師父
## - 飛星術（星宿，1.0B）：任務「捉拿叛徒」丁春秋 → 紅衣女子 → 大理北門外大道 4 個星宿叛徒 → 丁春秋 1 級 → 丁春秋教到 100
## - 蘭劍：1.0B 世界定性教到 60，八荒六合唯我獨尊功才練得到蘭劍教的 70
## - 玩家文字沒有開發標記；武功與師父列的 quest_flag 都有任務給（data_lint 0.7.0.1 區塊）

const DataLint := preload("res://tools/data_lint.gd")

## 自修到 target 級（每輪回滿精、補學點）；回 false＝卡住
func study_to(skill: String, target: int) -> bool:
	for i in 600:
		if lv(skill) >= target:
			return true
		Survival.rest_full(ch(), tables(), ws.options)
		ch().learn_points = 100000
		var r := Learning.self_study(ch(), skill, 500, tables(), ws.options, host().rules)
		if not bool(r.get("ok", false)):
			return assert_true(false, "self_study %s stuck at %d: %s" % [skill, lv(skill), str(r.get("reason", ""))])
	return assert_true(lv(skill) >= target, "%s reached %d (got %d)" % [skill, target, lv(skill)])

## 向師父學到 target 級
func learn_to(npc: String, skill: String, target: int) -> bool:
	for i in 600:
		if lv(skill) >= target:
			return true
		Survival.rest_full(ch(), tables(), ws.options)
		ch().learn_points = 100000
		var r := Learning.learn(ch(), npc, skill, 500, tables(), ws.options, host().rules)
		if not bool(r.get("ok", false)):
			return assert_true(false, "learn %s from %s stuck at %d: %s" % [skill, npc, lv(skill), str(r.get("reason", ""))])
	return assert_true(lv(skill) >= target, "%s reached %d" % [skill, target])

func chk(npc: String, skill: String) -> String:
	return Learning.check_master(ch(), npc, skill, tables(), ws.options, host().rules)

# ======================================================================== 劈石破玉拳

func test_pishiquan_liangfa_route() -> void:
	if join_char("huashan", "劈石少俠", "M") == null:
		return
	ch().attrs["wit"] = 40
	set_skills({ "hs_xinfa": 29, "rufeng": 10 })
	var r := Learning.self_study(ch(), "hs_pishiquan", 1, tables(), ws.options, host().rules)
	assert_eq(str(r.get("reason", "")), "req_skill_min", "華山心法 29 → 還不能練")
	set_skills({ "hs_xinfa": 30 })
	assert_eq(chk("n_liangfa", "hs_pishiquan"), "need_self_study", "1–10 自修")
	assert_true(study_to("hs_pishiquan", 10), "自修到 10")
	assert_eq(chk("n_liangfa", "hs_pishiquan"), "", "10 級起梁發教")
	assert_true(learn_to("n_liangfa", "hs_pishiquan", 12), "梁發教")
	set_skills({ "hs_pishiquan": 100 })
	assert_eq(chk("n_liangfa", "hs_pishiquan"), "cap_master", "梁發教到 100")
	assert_false(str(tables()["martial_arts"]["hs_pishiquan"]["desc"]).contains("桃谷"), "說明不再提不存在的桃谷六仙任務")

## 0.7.0.1 審查：劈石破玉拳 10 級只有低階的「開碑手」，主招「劈石破玉」30 級才開（威力見 balance_sim arts_pishi_power）
func test_pishiquan_moves_tiered() -> void:
	if not game_ok():
		return
	var mv: Array = tables()["martial_arts"]["hs_pishiquan"]["moves"]
	var by_lv := {}
	for m in mv:
		by_lv[int(m["unlock_level"])] = m
	assert_true(by_lv.has(10) and by_lv.has(30), str(by_lv.keys()))
	assert_true(int(by_lv[10]["power"]) <= 34, "10 級那招不超過其他門派第一門進階拳爪（天羅地網勢掌法 34）")
	assert_eq(str(by_lv[30]["name"]), "劈石破玉")
	for m in mv:
		assert_true(int(m["power"]) <= 40, "%s 威力 %d" % [m["id"], int(m["power"])])

# ======================================================================== 佛光普照掌

func _emei_foguang_ready() -> bool:
	if join_char("emei", "峨嵋少女", "F") == null:
		return false
	set_skills({ "em_jinding": 60, "em_jiuyang": 60, "duane": 60, "basic_inner": 60 })
	for a in ["str", "wit", "con"]:
		ch().attrs[a] = 20
	return true

## 從靜玄接任務走到滅絕傳 1 級（全部經 intent）
func _play_tiezhihuan() -> bool:
	var Q := "q_em_tiezhihuan"
	goto("em_dadian")
	ok("quest_talk", { "npc": "n_em_jingxuan", "quest": Q })
	ok("dialogue_choose", { "npc": "n_em_jingxuan", "quest": Q, "node": "n0", "choice": "c_yes" })
	if not assert_eq(qstage(Q), "s_zhou", "接下任務"):
		return false
	goto("em_zhou")
	ok("quest_talk", { "npc": "n_em_zhouzhiruo", "quest": Q })
	ok("dialogue_choose", { "npc": "n_em_zhouzhiruo", "quest": Q, "node": "n0", "choice": "c_ok" })
	assert_eq(item_count("i_em_zhou_xin"), 1, "周芷若的信")
	assert_eq(qstage(Q), "s_zhang")
	goto("xx_inn_2f")
	ok("quest_talk", { "npc": "n_zhangwuji", "quest": Q })
	ok("dialogue_choose", { "npc": "n_zhangwuji", "quest": Q, "node": "n0", "choice": "c_give" })
	assert_eq([item_count("i_em_zhou_xin"), item_count("i_em_zhang_huixin")], [0, 1], "信換回信")
	assert_eq(qstage(Q), "s_answer")
	goto("em_zhou")
	# 答錯 → 停在原階段，再找她一次重答
	ok("quest_talk", { "npc": "n_em_zhouzhiruo", "quest": Q })
	ok("dialogue_choose", { "npc": "n_em_zhouzhiruo", "quest": Q, "node": "n0", "choice": "c_q1b" })
	assert_eq(qstage(Q), "s_answer", "答錯不前進")
	assert_eq(item_count("i_em_zhang_huixin"), 1, "答錯不收回信")
	ok("quest_talk", { "npc": "n_em_zhouzhiruo", "quest": Q })
	ok("dialogue_choose", { "npc": "n_em_zhouzhiruo", "quest": Q, "node": "n0", "choice": "c_q1a" })
	ok("dialogue_choose", { "npc": "n_em_zhouzhiruo", "quest": Q, "node": "n1", "choice": "c_q2a" })
	ok("dialogue_choose", { "npc": "n_em_zhouzhiruo", "quest": Q, "node": "n2", "choice": "c_q3a" })
	assert_eq(qstage(Q), "s_duel", "三題都對 → 過招")
	assert_eq(item_count("i_em_zhang_huixin"), 0, "回信交給她")
	# 先不打 → 還在 s_duel；再找她 → 開打、打贏 → 鐵指環
	ok("quest_talk", { "npc": "n_em_zhouzhiruo", "quest": Q })
	ok("dialogue_choose", { "npc": "n_em_zhouzhiruo", "quest": Q, "node": "n0", "choice": "c_wait" })
	assert_eq(s().battle_id, 0)
	assert_eq(qstage(Q), "s_duel")
	ok("quest_talk", { "npc": "n_em_zhouzhiruo", "quest": Q })
	ok("dialogue_choose", { "npc": "n_em_zhouzhiruo", "quest": Q, "node": "n0", "choice": "c_fight" })
	if not assert_true(s().battle_id != 0, "和周芷若開打"):
		return false
	win_battle()
	assert_eq(qstage(Q), "s_miejue", "打贏 → 見滅絕")
	assert_eq(item_count("i_em_tiezhihuan"), 1, "鐵指環")
	goto("em_miejue")
	ok("quest_talk", { "npc": "n_em_miejue", "quest": Q })
	ok("dialogue_choose", { "npc": "n_em_miejue", "quest": Q, "node": "n0", "choice": "c_give" })
	assert_eq(str(qdone(Q).get("outcome", "")), "default")
	assert_true(bool(ch().flags.get("em_foguang_ok", false)), "旗標 em_foguang_ok")
	assert_eq(item_count("i_em_tiezhihuan"), 0, "鐵指環收回")
	return assert_eq(lv("em_foguang"), 1, "滅絕傳 1 級")

func test_foguang_requires() -> void:
	if not _emei_foguang_ready():
		return
	set_skills({ "duane": 59 })
	assert_eq(host().quests._can_accept(s(), "q_em_tiezhihuan"), "req_skill_min", "斷惡 60")
	set_skills({ "duane": 60 })
	ch().attrs["con"] = 19
	assert_eq(host().quests._can_accept(s(), "q_em_tiezhihuan"), "req_attr_min", "根骨 20")
	ch().attrs["con"] = 20
	assert_eq(host().quests._can_accept(s(), "q_em_tiezhihuan"), "")
	assert_true("q_em_tiezhihuan" in tables()["npcs"]["n_em_jingxuan"]["quests"], "靜玄給任務")

func test_foguang_quest_and_self_study() -> void:
	if not _emei_foguang_ready():
		return
	if not _play_tiezhihuan():
		return
	ch().attrs["wit"] = 40
	assert_eq(chk("n_em_miejue", "em_foguang"), "cap_master", "滅絕只教 1 級")
	assert_true(study_to("em_foguang", 50), "佛光自修到 50")
	assert_eq(Learning.self_study_cap(ch(), "em_foguang", tables(), host().rules), 80, "自修上限 80")
	assert_eq(host().quests._can_accept(s(), "q_em_tiezhihuan"), "quest_done", "一次性")

## 0.7.0.1 二審：周芷若是真正的單打——不拉隊友，隊友也不能中途 battle_join（party_only）
func test_zhou_duel_party_only() -> void:
	if not _emei_foguang_ready():
		return
	var Q := "q_em_tiezhihuan"
	var p2 := add_player("峨嵋師姐")
	ok("party_invite", { "target": str(session_of(p2).character.id) })
	assert_true(send_as(p2, "party_reply", { "from": str(ch().id), "accept": true }).get("ok", false), "組隊")
	goto("em_dadian")
	ok("quest_talk", { "npc": "n_em_jingxuan", "quest": Q })
	ok("dialogue_choose", { "npc": "n_em_jingxuan", "quest": Q, "node": "n0", "choice": "c_yes" })
	ch().quests["active"][Q]["stage"] = "s_duel"   # 測試捷徑：直接到過招階段（前面幾步見 _play_tiezhihuan）
	goto("em_zhou")
	goto_as(p2, "em_zhou")
	ok("quest_talk", { "npc": "n_em_zhouzhiruo", "quest": Q })
	ok("dialogue_choose", { "npc": "n_em_zhouzhiruo", "quest": Q, "node": "n0", "choice": "c_fight" })
	var bid := s().battle_id
	if not assert_true(bid != 0, "和周芷若開打"):
		return
	assert_eq(session_of(p2).battle_id, 0, "同房的隊友沒被拉進場")
	var entry: Dictionary = host().battles.active[bid]
	assert_true(bool(entry.get("opts", {}).get("party_only", false)), "party_only")
	assert_eq(reason_as(p2, "battle_join", { "battle_id": bid }), "join_not_allowed", "隊友不能中途加入幫忙")
	assert_eq(session_of(p2).battle_id, 0)
	win_battle()
	assert_eq(qstage(Q), "s_miejue", "單打贏了 → 見滅絕")

func test_foguang_era_1_0a() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])
	for t in [["quests", "q_em_tiezhihuan"], ["items", "i_em_tiezhihuan"], ["monsters", "m_em_zhouzhiruo"]]:
		assert_true(tables()[t[0]].has(t[1]), "%s.%s 是 1.0A（官方 2001-12-06 已存在）" % t)

# ======================================================================== 四象掌（整條鏈，佛光不靠 set_skills）

func _luosha_to_guoxiang() -> bool:
	var Q := "q_ar_em_luosha"
	ch().combat_xp = 300000
	goto("ym_gate")
	ok("quest_accept", { "npc": "n_ar_ym_shouwei", "quest": Q })
	ok("quest_talk", { "npc": "n_ar_ym_shouwei", "quest": Q })
	ok("dialogue_choose", { "npc": "n_ar_ym_shouwei", "quest": Q, "node": "n0", "choice": "c_help" })
	if not assert_true(s().battle_id != 0, "守關開打"):
		return false
	win_battle()
	ok("quest_talk", { "npc": "n_ar_ym_shouwei", "quest": Q })
	ok("dialogue_choose", { "npc": "n_ar_ym_shouwei", "quest": Q, "node": "n0", "choice": "c_refuse" })
	goto("zn_pomiao")
	ok("quest_talk", { "npc": "n_ar_guoxiang", "quest": Q })
	return assert_eq(qstage(Q), "s_guoxiang")

func test_sixiang_full_chain_past_level_1() -> void:
	if not _emei_foguang_ready():
		return
	if not _play_tiezhihuan():
		return
	ch().attrs["wit"] = 40
	ch().attrs["luck"] = 20
	assert_true(study_to("em_foguang", 50), "佛光自修到 50（不用 set_skills）")
	if not _luosha_to_guoxiang():
		return
	ok("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": "q_ar_em_luosha", "node": "n0", "choice": "c_learn" })
	assert_eq(str(qdone("q_ar_em_luosha").get("outcome", "")), "sixiang")
	assert_eq(lv("em_sixiang"), 1, "郭襄給 1 級")
	assert_true(learn_to("n_ar_guoxiang", "em_sixiang", 10), "郭襄教到 10")
	assert_eq(chk("n_ar_guoxiang", "em_sixiang"), "cap_master")
	assert_true(study_to("em_sixiang", 12), "10 級以後自修（四象掌不再卡在 1 級）")

func test_sixiang_return_visit() -> void:
	if not _emei_foguang_ready():
		return
	set_skills({ "em_foguang": 10, "duane": 10 })
	ch().attrs["luck"] = 20
	if not _luosha_to_guoxiang():
		return
	assert_false(bool(send("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": "q_ar_em_luosha", "node": "n0", "choice": "c_learn" }).get("ok", false)),
		"佛光不夠學不了")
	ok("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": "q_ar_em_luosha", "node": "n0", "choice": "c_sword" })
	assert_eq(str(qdone("q_ar_em_luosha").get("outcome", "")), "sword")
	var H := "q_ar_em_sixiang_hui"
	assert_eq(host().quests._can_accept(s(), H), "req_skill_min", "佛光還不到 50")
	set_skills({ "em_foguang": 50, "duane": 60 })
	assert_eq(host().quests._can_accept(s(), H), "")
	ok("quest_talk", { "npc": "n_ar_guoxiang", "quest": H })
	ok("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": H, "node": "n0", "choice": "c_ask" })
	assert_eq(qstage(H), "s_learn")
	ok("quest_talk", { "npc": "n_ar_guoxiang", "quest": H })
	assert_eq(item_count("i_ar_luoshajian"), 1, "回訪前劍還在身上")
	ok("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": H, "node": "n0", "choice": "c_ok" })
	assert_eq(str(qdone(H).get("outcome", "")), "default")
	assert_true(bool(ch().flags.get("em_sixiang_ok", false)))
	assert_eq(lv("em_sixiang"), 1, "回訪學到四象掌 1 級")
	assert_eq(item_count("i_ar_luoshajian"), 0, "0.7.0.1 二審：郭襄收回羅煞劍（劍與四象掌二選一）")
	assert_eq(chk("n_ar_guoxiang", "em_sixiang"), "", "之後郭襄照教")

func test_sixiang_return_visit_not_for_learned_or_outsiders() -> void:
	if not _emei_foguang_ready():
		return
	set_skills({ "em_foguang": 50, "duane": 60 })
	ch().attrs["luck"] = 20
	var H := "q_ar_em_sixiang_hui"
	assert_eq(host().quests._can_accept(s(), H), "req_quest_outcome", "沒做羅煞劍不能回訪")
	ch().quests["done"]["q_ar_em_luosha"] = { "n": 1, "outcome": "sixiang", "world_s": 0.0, "failed": 0 }
	ch().flags["em_sixiang_ok"] = true
	assert_eq(host().quests._can_accept(s(), H), "req_quest_outcome", "在羅煞劍學到四象掌的人不用回訪")
	# 0.7.0.1 審查：結局是拿劍、但已經有 em_sixiang_ok（例如回訪做過了）→ 擋在 not_flag，不是結局
	ch().quests["done"]["q_ar_em_luosha"] = { "n": 1, "outcome": "sword", "world_s": 0.0, "failed": 0 }
	assert_eq(host().quests._can_accept(s(), H), "req_not_flag", "已經有 em_sixiang_ok 的人不能回訪")
	ch().flags.erase("em_sixiang_ok")
	assert_eq(host().quests._can_accept(s(), H), "req_has_item", "0.7.0.1 二審：劍不在身上（賣掉、弄丟）→ 不能回訪")
	give("i_ar_luoshajian", 1)
	assert_eq(host().quests._can_accept(s(), H), "", "拿劍、劍還帶著、還沒學到 → 可以回訪")
	# 不是峨嵋弟子（例如拼酒贏到劍的人）→ 擋在門派
	ch().sect = "huashan"
	assert_eq(host().quests._can_accept(s(), H), "req_sect", "非峨嵋弟子不能回訪")

## 0.7.0.1 審查：合格的峨嵋弟子在郭襄那裡選不到羅煞劍（研究：二選一），不能先拿劍再回訪補學四象掌
func test_luosha_sword_only_for_unqualified_emei() -> void:
	if not _emei_foguang_ready():
		return
	set_skills({ "em_foguang": 50, "duane": 60 })
	ch().attrs["luck"] = 20
	if not _luosha_to_guoxiang():
		return
	var r := send("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": "q_ar_em_luosha", "node": "n0", "choice": "c_sword" })
	assert_false(bool(r.get("ok", false)), "合格的峨嵋弟子選不到羅煞劍")
	assert_eq(qstage("q_ar_em_luosha"), "s_guoxiang", "沒有前進")
	assert_eq(item_count("i_ar_luoshajian"), 0)
	ok("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": "q_ar_em_luosha", "node": "n0", "choice": "c_learn" })
	assert_eq(str(qdone("q_ar_em_luosha").get("outcome", "")), "sixiang")
	assert_eq(host().quests._can_accept(s(), "q_ar_em_sixiang_hui"), "req_quest_outcome", "學到了就沒有回訪")

## 三項裡只差一項（福緣 19）→ 學不了四象掌、可以拿劍；福緣夠了以後回訪
func test_luosha_sword_when_only_luck_short() -> void:
	if not _emei_foguang_ready():
		return
	set_skills({ "em_foguang": 50, "duane": 60 })
	ch().attrs["luck"] = 19
	if not _luosha_to_guoxiang():
		return
	assert_false(bool(send("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": "q_ar_em_luosha", "node": "n0", "choice": "c_learn" }).get("ok", false)),
		"福緣 19 學不了")
	ok("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": "q_ar_em_luosha", "node": "n0", "choice": "c_sword" })
	assert_eq(str(qdone("q_ar_em_luosha").get("outcome", "")), "sword")
	assert_eq(host().quests._can_accept(s(), "q_ar_em_sixiang_hui"), "req_attr_min", "福緣還不夠")
	ch().attrs["luck"] = 20
	assert_eq(host().quests._can_accept(s(), "q_ar_em_sixiang_hui"), "", "福緣夠了 → 回訪")

## 0.7.0.1 二審：故意在合格之前先去拿劍（或卸下加福緣的裝備去拿劍），合格後回訪 → 要把劍還給郭襄，最後只留四象掌；
## 劍不交出去（選「捨不得」）就學不到；身上沒有劍連任務都接不到
func test_sixiang_return_visit_takes_sword_back() -> void:
	if not _emei_foguang_ready():
		return
	set_skills({ "em_foguang": 50, "duane": 60 })
	ch().attrs["luck"] = 19   # 例如卸下 +福緣 的戒指
	if not _luosha_to_guoxiang():
		return
	ok("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": "q_ar_em_luosha", "node": "n0", "choice": "c_sword" })
	assert_eq(item_count("i_ar_luoshajian"), 1)
	ch().attrs["luck"] = 20   # 戒指戴回去
	var H := "q_ar_em_sixiang_hui"
	assert_eq(host().quests._can_accept(s(), H), "")
	ok("quest_talk", { "npc": "n_ar_guoxiang", "quest": H })
	ok("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": H, "node": "n0", "choice": "c_ask" })
	ok("quest_talk", { "npc": "n_ar_guoxiang", "quest": H })
	ok("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": H, "node": "n0", "choice": "c_keep" })
	assert_eq(qstage(H), "s_learn", "捨不得劍 → 任務留著")
	assert_eq([item_count("i_ar_luoshajian"), lv("em_sixiang")], [1, 0], "劍還在、沒學到")
	# 劍不在身上（例如存進錢莊）→ 選項上鎖、送出也失敗，沒有前進
	var uid := first_uid("i_ar_luoshajian")
	ch().inventory.remove_item_id("i_ar_luoshajian", 1)
	ok("quest_talk", { "npc": "n_ar_guoxiang", "quest": H })
	assert_false(bool(send("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": H, "node": "n0", "choice": "c_ok" }).get("ok", false)),
		"沒帶劍 → 不傳掌")
	assert_eq(lv("em_sixiang"), 0)
	send("dialogue_close")
	give("i_ar_luoshajian", 1)
	ok("quest_talk", { "npc": "n_ar_guoxiang", "quest": H })
	ok("dialogue_choose", { "npc": "n_ar_guoxiang", "quest": H, "node": "n0", "choice": "c_ok" })
	assert_eq(lv("em_sixiang"), 1, "還劍 → 四象掌 1 級")
	assert_eq(item_count("i_ar_luoshajian"), 0, "最後只留四象掌，沒有兩樣都拿")
	assert_true(uid != "")

func test_attr_max_requirement() -> void:
	if join_char("emei", "屬性上限", "F") == null:
		return
	var c := [{ "type": "attr_max", "attr": "luck", "value": 19 }]
	ch().attrs["luck"] = 19
	assert_eq(Requirements.check(c, ch(), tables(), ws.options, host().rules), "")
	ch().attrs["luck"] = 20
	assert_eq(Requirements.check(c, ch(), tables(), ws.options, host().rules), "req_attr_max")
	assert_true(Requirements.describe(c[0], tables()).contains("19 以下"), Requirements.describe(c[0], tables()))
	assert_true("attr_max" in DataSchema.REQUIRE_TYPES)

## 0.7.0.1 審查：任務路線是 2002 資料 → src later（era 仍 1.0A）
func test_tiezhihuan_src_later() -> void:
	if not game_ok():
		return
	var q: Dictionary = tables()["quests"]["q_em_tiezhihuan"]
	assert_eq(str(q.get("src", "")), "later")
	assert_eq(str(q["outcomes"]["default"].get("src", "")), "later")
	assert_eq(str(q.get("era", "")), "1.0A")

# ======================================================================== 九陰真經

func test_jiuyin_wall_route() -> void:
	if join_char("gumu", "古墓少女", "F") == null:
		return
	var Q := "q_gm_jiuyin"
	set_skills({ "basic_inner": 100, "gm_xinfa": 100, "qingxin": 90 })   # 古墓心法 100 本來就要清心 90（本門武功＝清心＋10）
	ch().attrs["luck"] = 29
	ch().attrs["wit"] = 35
	assert_eq(host().quests._can_accept(s(), Q), "req_attr_min", "福緣 30")
	ch().attrs["luck"] = 30
	assert_eq(host().quests._can_accept(s(), Q), "")
	assert_eq(str(tables()["npcs"]["n_gm_shibi"]["room"]), "gm_xiaomei")
	goto("gm_xiaomei")
	ok("quest_talk", { "npc": "n_gm_shibi", "quest": Q })
	ok("dialogue_choose", { "npc": "n_gm_shibi", "quest": Q, "node": "n0", "choice": "c_read" })
	assert_eq(qstage(Q), "s_read")
	ok("quest_talk", { "npc": "n_gm_shibi", "quest": Q })
	ok("dialogue_choose", { "npc": "n_gm_shibi", "quest": Q, "node": "n0", "choice": "c_go" })
	assert_true(bool(ch().flags.get("gm_jiuyin_read", false)), "旗標 gm_jiuyin_read")
	assert_eq(lv("gm_jiuyin"), 1, "石壁給 1 級")
	# 全程自修 1–60，沒有師父
	assert_true(CharData.masters_for_skill(tables(), "gm_jiuyin").is_empty(), "九陰真經沒有師父")
	assert_eq(Learning.self_study_cap(ch(), "gm_jiuyin", tables(), host().rules), 60, "自修到 60")
	ch().attrs["wit"] = 40
	assert_true(study_to("gm_jiuyin", 11), "過了 10 級還能自修（0.7.0.0 卡在 10）")
	set_skills({ "gm_jiuyin": 60 })
	var r := Learning.self_study(ch(), "gm_jiuyin", 1, tables(), ws.options, host().rules)
	assert_eq(str(r.get("reason", "")), "cap_master", "60 級停")

# ======================================================================== 飛星術（1.0B）

func test_feixing_traitor_route() -> void:
	if join_char("xingxiu", "星宿弟子", "M") == null:
		return
	var Q := "q_xh_feixing"
	set_skills({ "xh_xinfa": 50, "chanmei": 40, "basic_poison": 50 })
	ch().morality = -999
	assert_eq(host().quests._can_accept(s(), Q), "req_morality_max", "善惡 −1000")
	ch().morality = -1000
	assert_eq(host().quests._can_accept(s(), Q), "")
	assert_true("QUEST" in tables()["npcs"]["n_xh_dingchunqiu"]["services"], "丁春秋 1.0B 給任務")
	goto("xh_hall")
	ok("quest_talk", { "npc": "n_xh_dingchunqiu", "quest": Q })
	ok("dialogue_choose", { "npc": "n_xh_dingchunqiu", "quest": Q, "node": "n0", "choice": "c_yes" })
	assert_eq(qstage(Q), "s_hongyi")
	goto("xx_street")
	ok("quest_talk", { "npc": "n_xh_hongyinv", "quest": Q })
	ok("dialogue_choose", { "npc": "n_xh_hongyinv", "quest": Q, "node": "n0", "choice": "c_ok" })
	assert_eq(qstage(Q), "s_hunt")
	goto("dlw_road")
	for i in 4:
		Survival.rest_full(ch(), tables(), ws.options)
		ok("story_act", { "act": Q + ":a_hunt" })
		if not assert_true(s().battle_id != 0, "搜捕叛徒開打 %d" % (i + 1)):
			return
		win_battle()
	assert_eq(qstage(Q), "s_back", "四個叛徒")
	assert_eq(int(ch().morality), -1000, "殺叛徒不改善惡")
	goto("xh_hall")
	ok("quest_talk", { "npc": "n_xh_dingchunqiu", "quest": Q })
	ok("dialogue_choose", { "npc": "n_xh_dingchunqiu", "quest": Q, "node": "n0", "choice": "c_learn" })
	assert_true(bool(ch().flags.get("xh_feixing_quest", false)))
	assert_eq(lv("xh_feixing"), 1, "丁春秋傳 1 級")
	assert_eq(chk("n_xh_dingchunqiu", "xh_feixing"), "", "之後丁春秋教")
	assert_true(learn_to("n_xh_dingchunqiu", "xh_feixing", 3), "丁春秋教")

## 0.7.0.1 二審：搜捕叛徒隨按隨打、放棄再接又能重打 → 每隻的獎勵不超過同級距的怪（峨嵋白猿 150／60、楊康 300／90）
func test_feixing_traitor_rewards_not_farmable() -> void:
	if not game_ok():
		return
	var m: Dictionary = tables()["monsters"]["m_xh_pantu"]
	assert_eq(int(m["combat_xp_ref"]), 50000)
	assert_true(int(m["combat_xp"]) >= 150 and int(m["combat_xp"]) <= 250, "實戰 %d ∈ 150–250" % int(m["combat_xp"]))
	assert_true(int(m["learn_points"]) >= 60 and int(m["learn_points"]) <= 80, "學點 %d ∈ 60–80" % int(m["learn_points"]))
	var yang: Dictionary = tables()["monsters"].get("m_qz_yangkang", {})
	if not yang.is_empty():
		assert_true(int(m["combat_xp"]) <= int(yang["combat_xp"]), "不比楊康（實戰參考 4 萬）多")

func test_feixing_era_1_0b_only() -> void:
	if not game_ok():
		return
	assert_eq(str(tables()["martial_arts"]["xh_feixing"]["era"]), "1.0B")
	use_eras(["1.0A"])
	assert_false(tables()["martial_arts"].has("xh_feixing"), "飛星術 1.0B")
	assert_false(tables()["masters"].has("ms_xh_dcq_feixing"), "師父列跟著 1.0B")
	assert_false(tables()["quests"].has("q_xh_feixing"))
	assert_false(tables()["npcs"].has("n_xh_hongyinv"))
	assert_false("q_xh_feixing" in tables()["npcs"]["n_xh_dingchunqiu"].get("quests", []), "1.0A 丁春秋不掛 1.0B 任務")

# ======================================================================== 蘭劍：定性與八荒一致

func test_lanjian_dingxing_matches_bahuang_cap() -> void:
	if join_char("lingjiu", "靈鷲女弟子", "F") == null:
		return
	var bonus := int(tables()["sects"]["lingjiu"]["sect_art_cap_bonus"])
	var dx_cap := int(tables()["masters"]["ms_lj_lanjian_dingxing"]["cap"])
	var bh_cap := int(tables()["masters"]["ms_ar_lj_lanjian_bahuang"]["cap"])
	assert_eq(dx_cap, 60, "1.0B 蘭劍定性教到 60")
	assert_true(bh_cap <= dx_cap + bonus, "蘭劍教的八荒上限 %d ≤ 定性上限 %d ＋ %d" % [bh_cap, dx_cap, bonus])
	set_skills({ "dingxing": 50 })
	assert_eq(chk("n_lj_lanjian", "dingxing"), "", "50 級以後蘭劍還教")
	assert_true(learn_to("n_lj_lanjian", "dingxing", 60), "定性學到 60")
	assert_eq(chk("n_lj_lanjian", "dingxing"), "cap_master", "教到 60")
	ch().flags["lj_bahuang_learned"] = true
	set_skills({ "lj_xiaoyao": 80, "lj_bahuang": 69 })
	assert_eq(chk("n_lj_lanjian", "lj_bahuang"), "", "定性 60 → 八荒能學到 70")
	set_skills({ "lj_bahuang": 70 })
	assert_eq(chk("n_lj_lanjian", "lj_bahuang"), "cap_master", "蘭劍教到 70")
	set_skills({ "dingxing": 50, "lj_bahuang": 60 })
	assert_eq(chk("n_lj_lanjian", "lj_bahuang"), "cap_sect_skill", "定性 50 時停在 60（本門武功＝定性＋10）")

func test_lanjian_dingxing_1_0a_unchanged() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])
	assert_eq(int(tables()["masters"]["ms_lj_lanjian_dingxing"]["cap"]), 50, "1.0A 蘭劍定性仍 50（八荒是 1.0B）")
	assert_false(tables()["martial_arts"].has("lj_bahuang"))

# ======================================================================== 開發標記、學不到的武功（data_lint）

func test_no_dev_tags_in_art_desc() -> void:
	if not game_ok():
		return
	for id in tables()["martial_arts"]:
		var d := str(tables()["martial_arts"][id].get("desc", ""))
		assert_eq(DataLint.dev_tag_in(d), "", "martial_arts.%s desc: %s" % [id, d])
	for aid in ["hs_pishiquan", "qz_kongming", "wd_chunyang", "wd_tiyun", "wd_taijiquan", "wd_taijijian", "wd_yitian", "wd_zhenwu"]:
		if tables()["martial_arts"].has(aid):
			assert_false(str(tables()["martial_arts"][aid]["desc"]).contains("（M3"), aid)
	# 偵測器本身
	assert_eq(DataLint.dev_tag_in("桃谷六仙任務取得拳譜後才能修習（M3）。"), "M3")
	assert_eq(DataLint.dev_tag_in("要先完成「太極拳與太極劍」（M3b 開放）。"), "M3b")
	assert_eq(DataLint.dev_tag_in("（M3d WP-LAW；設計提案）"), "M3d")
	assert_eq(DataLint.dev_tag_in("（攻擊 NPC 的戰鬥單位；M3C_PLAN §5.4）"), "M3", "M3C_PLAN 也算")
	assert_eq(DataLint.dev_tag_in("郭襄所創的掌法，太陽、少陰、少陽、太陰四象流轉。"), "")
	assert_eq(DataLint.dev_tag_in("ATM3 HM2"), "", "前面是英數字的不算")

func test_lint_0701_clean_and_detects_regressions() -> void:
	if not game_ok():
		return
	for eras in [["1.0A", "1.0B"], ["1.0A"]]:
		use_eras(eras)
		var errs: PackedStringArray = DataLint._check_0701(tables())
		assert_eq(errs.size(), 0, "%s: %s" % [str(eras), "\n".join(errs)])
	use_eras(["1.0A", "1.0B"])
	# 把劈石破玉拳改回 0.7.0.0 的樣子 → 抓得到
	var v: Dictionary = tables().duplicate(true)
	v["martial_arts"]["hs_pishiquan"]["requires"] = [{ "type": "sect", "sect": "huashan" }, { "type": "quest_flag", "flag": "q_taogu_done" }]
	v["martial_arts"]["hs_pishiquan"]["desc"] = "桃谷六仙任務取得拳譜後才能修習（M3）。"
	var joined := "\n".join(DataLint._check_0701(v))
	assert_true(joined.contains("hs_pishiquan: quest_flag 'q_taogu_done' is never given"), joined)
	assert_true(joined.contains("martial_arts.hs_pishiquan.desc: player text contains dev tag 'M3'"), joined)
	# 拿掉給佛光旗標的任務 → 抓得到
	var v2: Dictionary = tables().duplicate(true)
	v2["quests"].erase("q_em_tiezhihuan")
	assert_true("\n".join(DataLint._check_0701(v2)).contains("em_foguang: quest_flag 'em_foguang_ok'"), "佛光旗標沒人給")
	# 四門武功的旗標都有人給
	var given: Dictionary = DataLint.flags_given(tables())
	for f in ["em_foguang_ok", "gm_jiuyin_read", "xh_feixing_quest", "em_sixiang_ok"]:
		assert_true(given.has(f), "flag %s is given" % f)
