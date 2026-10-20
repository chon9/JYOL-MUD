extends "res://tests/unit/test_world_fixture.gd"
## STORY_PLAN §9.1 test_world_quest_v2：用小型測試任務（fixture，不依賴內容碎片）走完整的主機路徑：
## offer → accept；TALK（對話樹、變數、上鎖／隱藏選項、resume）／DELIVER／COLLECT／BUY（之前買的不算）／KILL／
## FIGHT（勝、逃、敗）／REACH／WAIT（快轉）／STATE／ESCORT；條件分支與結局獎勵（lilian、learn）；fail；冷卻與 max；
## appear 隨時辰變化與 npc_here；房間動作；中途存檔 → 重新載入 → 繼續（含護送）。
## 測試方法名一律 test_story_*（--filter=story 可單跑）。

const QID := "q_t_story"
const QREP := "q_t_rep"

func before_each() -> void:
	world_name = "w_story_v2"
	super.before_each()

# ---------------------------------------------------------------- fixture
static func fixture_quest() -> Dictionary:
	return {
		"id": QID, "name": "測試故事", "chapter": "測試章", "giver": "n_wujieshan", "era": "1.0A", "src": "proposal",
		"text": "測試用的故事任務。", "requires": [], "give_items": [{ "id": "i_letter", "n": 1 }],
		"repeat": { "max": 1, "cooldown_days": 0 }, "abandon": true, "party_credit": true,
		"start": "s_talk", "offer": "d_offer",
		"stages": [
			{ "id": "s_talk", "title": "找張無忌", "log": "去客棧二樓找張無忌。", "hint_room": "xx_inn_2f",
				"objectives": [{ "id": "o_zh", "type": "TALK", "npc": "n_zhangwuji", "dialogue": "d_zhang", "text": "和張無忌說話" }],
				"next": "s_deliver" },
			{ "id": "s_deliver", "title": "送饅頭", "log": "",
				"objectives": [{ "id": "o_dv", "type": "DELIVER", "npc": "n_xx_pharmacist", "item": "c_mantou", "count": 2, "text": "交 2 個饅頭" }],
				"next": "s_collect" },
			{ "id": "s_collect", "title": "備水買藥", "log": "",
				"objectives": [{ "id": "o_col", "type": "COLLECT", "item": "c_water", "count": 2, "text": "帶 2 份清水" },
					{ "id": "o_buy", "type": "BUY", "item": "c_qiyao", "count": 1, "npc": "n_xx_pharmacist", "text": "買金創藥" }],
				"next": "s_kill" },
			{ "id": "s_kill", "title": "打兔子", "log": "",
				"objectives": [{ "id": "o_k", "type": "KILL", "monster": "m_rabbit", "count": 2, "text": "擊敗野兔 2 隻" }],
				"next": "s_fight" },
			{ "id": "s_fight", "title": "一戰", "log": "",
				"room_actions": [
					{ "id": "a_f", "room": "xx_street", "label": "打兔子", "repeat": true,
						"do": [{ "do": "fight", "monsters": ["m_rabbit"], "obj": "o_f" }] },
					{ "id": "a_once", "room": "xx_street", "label": "撿水", "repeat": false,
						"do": [{ "do": "give", "item": "c_water", "n": 1 }] },
					{ "id": "a_night", "room": "xx_street", "label": "夜裡才有", "hours": ["子"], "do": [] }],
				"objectives": [{ "id": "o_f", "type": "FIGHT", "win": "WIN_OR_FLEE", "text": "打一場" }],
				"next": "s_reach" },
			{ "id": "s_reach", "title": "到驛站", "log": "",
				"objectives": [{ "id": "o_r", "type": "REACH", "room": "xx_station", "text": "到驛站" }], "next": "s_wait" },
			{ "id": "s_wait", "title": "等半天", "log": "",
				"objectives": [{ "id": "o_w", "type": "WAIT", "days": 0.5, "text": "等半天" }], "next": "s_state" },
			{ "id": "s_state", "title": "名聲", "log": "",
				"objectives": [{ "id": "o_s", "type": "STATE", "requires": [{ "type": "fame_min", "value": 50 }], "text": "名聲 50" }],
				"next": "s_escort" },
			{ "id": "s_escort", "title": "護送", "log": "",
				"on_enter": [{ "do": "escort_start", "npc": "n_zhangwuji" }],
				"objectives": [{ "id": "o_e", "type": "ESCORT", "npc": "n_zhangwuji", "to_room": "xx_station", "text": "帶張無忌到驛站" }],
				"on_complete": [{ "do": "escort_end", "npc": "n_zhangwuji" }],
				"next": [{ "if": [{ "type": "quest_var", "quest": QID, "var": "pick", "value": "a" }], "goto": "END:a" },
					{ "goto": "END:b" }] },
		],
		"dialogues": {
			"d_offer": { "start": "n0", "nodes": {
				"n0": { "speaker": "npc", "text": "{name}，幫個忙？", "choices": [
					{ "id": "c_yes", "label": "好", "do": [{ "do": "accept" }], "goto": "n1" },
					{ "id": "c_no", "label": "不要", "goto": "END" }] },
				"n1": { "speaker": "npc", "text": "謝了。", "goto": "END" } } },
			"d_zhang": { "start": "n0", "resume": "n_back", "nodes": {
				"n0": { "speaker": "npc", "text": "你是誰？", "goto": "n_pick" },
				"n_back": { "speaker": "npc", "text": "又是你。", "goto": "n_pick" },
				"n_pick": { "speaker": "player", "text": "我來……", "choices": [
					{ "id": "c_a", "label": "選甲", "do": [{ "do": "var", "name": "pick", "value": "a" }, { "do": "reward", "lilian": 3 },
						{ "do": "complete", "obj": "o_zh" }], "goto": "n_end" },
					{ "id": "c_b", "label": "選乙", "do": [{ "do": "var", "name": "pick", "value": "b" }, { "do": "complete", "obj": "o_zh" }],
						"goto": "n_end" },
					{ "id": "c_lock", "label": "高手才能選", "requires": [{ "type": "skill_min", "skill": "basic_fist", "value": 200 }], "goto": "END" },
					{ "id": "c_hide", "label": "隱藏", "requires": [{ "type": "fame_min", "value": 99999 }], "hide_if_locked": true, "goto": "END" },
					{ "id": "c_take", "label": "給我十顆藥", "do": [{ "do": "take", "item": "c_qiyao", "n": 10 }, { "do": "var", "name": "took", "value": true }],
						"goto": "END" },
					{ "id": "c_fail", "label": "搞砸", "do": [{ "do": "fail", "reason": "" }], "goto": "END" }] },
				"n_end": { "speaker": "n_wujieshan", "text": "好。", "goto": "END" } } },
		},
		"outcomes": {
			"a": { "label": "選了甲", "rewards": { "money": 7, "lilian": 5, "learn": { "basic_fist": 3 }, "items": [{ "id": "c_mantou", "n": 1 }] } },
			"b": { "label": "選了乙", "rewards": { "money": 1 } },
		},
		"rumors": { "first": "rmr_t_first", "each": "rmr_t_each" },
	}

static func fixture_repeat() -> Dictionary:
	return {
		"id": QREP, "name": "測試跑腿", "chapter": "測試章", "giver": "n_xx_station", "era": "1.0A", "src": "proposal",
		"text": "", "repeat": { "max": 2, "cooldown_days": 1 },
		"stages": [{ "id": "s1", "title": "回話", "objectives": [{ "id": "o", "type": "TALK", "npc": "n_xx_station", "text": "回話" }], "next": "END" }],
		"outcomes": { "default": { "label": "", "rewards": { "lilian": 2 } } },
	}

## 把 fixture 任務塞進生效表（after_each 的 _restore_rules 會重建生效表，不會留下來）
func install(rows: Array = []) -> void:
	if rows.is_empty():
		rows = [fixture_quest(), fixture_repeat()]
	for r in rows:
		var row := QuestDef.normalize(r)
		tables()["quests"][str(row["id"])] = row
		var giver: Dictionary = tables()["npcs"][str(row["giver"])]
		var qs: Array = (giver.get("quests", []) as Array).duplicate()
		if not qs.has(str(row["id"])):
			qs.append(str(row["id"]))
		giver["quests"] = qs

func st() -> Dictionary:
	return ch().quests["active"].get(QID, {})

func stage() -> String:
	return str(st().get("stage", ""))

func accept_story() -> void:
	goto("xx_square")
	ok("quest_talk", { "npc": "n_wujieshan", "quest": QID })
	var d := lastp("dialogue")
	ok("dialogue_choose", { "npc": "n_wujieshan", "quest": QID, "node": str(d["node"]), "choice": "c_yes" })

func choose(npc: String, choice: String) -> Dictionary:
	var d := lastp("dialogue")
	return send("dialogue_choose", { "npc": npc, "quest": QID, "node": str(d.get("node", "")), "choice": choice })

# ---------------------------------------------------------------- 接任務與對話
func test_story_offer_then_accept() -> void:
	if not game_ok():
		return
	install()
	make_char("故事俠")
	goto("xx_square")
	ok("talk", { "npc": "n_wujieshan" })
	var states := {}
	for q in lastp("npc_menu")["quests"]:
		states[q["id"]] = q
	assert_eq(states[QID]["state"], "AVAILABLE")
	assert_eq(states[QID]["chapter"], "測試章")
	clear_events()
	ok("quest_talk", { "npc": "n_wujieshan", "quest": QID })
	assert_false(ch().quests["active"].has(QID), "offer 對話開著時還沒接")
	var d := lastp("dialogue")
	assert_eq(d["npc"], "n_wujieshan")
	assert_eq(d["quest_name"], "測試故事")
	assert_eq(d["text"], "故事俠，幫個忙？", "{name} 代換")
	assert_eq(d["speaker_name"], host().npc_name("n_wujieshan"))
	assert_eq(d["choices"].size(), 2)
	assert_false(bool(d["end"]))
	assert_eq(s().dialogue.get("node", ""), "n0")
	# 游標不符 → dialogue_stale
	assert_eq(reason("dialogue_choose", { "npc": "n_wujieshan", "quest": QID, "node": "n1", "choice": "c_yes" }), "dialogue_stale")
	assert_eq(reason("dialogue_choose", { "npc": "n_xx_station", "quest": QID, "node": "n0", "choice": "c_yes" }), "dialogue_stale")
	ok("dialogue_choose", { "npc": "n_wujieshan", "quest": QID, "node": "n0", "choice": "c_yes" })
	assert_true(ch().quests["active"].has(QID), "accept 動作才真的接")
	assert_eq(stage(), "s_talk")
	assert_eq(item_count("i_letter"), 1, "give_items")
	assert_false(last("quest_accept").is_empty())
	assert_eq(lastp("quest_stage").get("stage_title", ""), "找張無忌")
	# 下一個節點只有 goto END → 合成的「繼續」選項不出現，end = true
	d = lastp("dialogue")
	assert_eq(d["node"], "n1")
	assert_true(bool(d["end"]))
	# 第四輪審查：結束節點送出後主機已收掉游標（客戶端「結束」不送東西）；再送 dialogue_close 也回 ok、不另發事件
	assert_true(s().dialogue.is_empty(), "結束節點後游標已收掉")
	ok("dialogue_close")
	assert_true(s().dialogue.is_empty())
	assert_true(last("dialogue_close").is_empty(), "沒有開著的對話：不送 dialogue_close")
	assert_eq(reason("dialogue_choose", { "npc": "n_wujieshan", "quest": QID, "node": "n1", "choice": "x" }), "dialogue_none")
	# 角色表
	var row: Dictionary = {}
	for q in sheet()["quests"]:
		if q["id"] == QID:
			row = q
	assert_eq(row.get("chapter", ""), "測試章")
	assert_eq(row.get("stage", ""), "s_talk")
	assert_eq(row.get("stage_title", ""), "找張無忌")
	assert_eq(row.get("hint_room", ""), "xx_inn_2f")
	assert_eq(row.get("objectives", []), [{ "text": "和張無忌說話", "have": 0, "need": 1, "done": false }])

func test_story_decline_and_quest_accept_opens_offer() -> void:
	if not game_ok():
		return
	install()
	make_char()
	goto("xx_square")
	ok("quest_accept", { "npc": "n_wujieshan", "quest": QID })
	assert_false(ch().quests["active"].has(QID), "有 offer 的任務：quest_accept 也先開 offer 對話")
	ok("dialogue_choose", { "npc": "n_wujieshan", "quest": QID, "node": "n0", "choice": "c_no" })
	assert_false(ch().quests["active"].has(QID))
	assert_true(s().dialogue.is_empty(), "goto END 關掉對話")

func test_story_dialogue_locks_vars_resume_take() -> void:
	if not game_ok():
		return
	install()
	make_char()
	accept_story()
	goto("xx_inn_2f")
	clear_events()
	ok("talk", { "npc": "n_zhangwuji" })
	assert_true(evs("npc_menu").is_empty(), "目前目標在此 NPC 且有對話 → 直接開對話，不另開選單")
	var d := lastp("dialogue")
	assert_eq(d["node"], "n0")
	assert_eq(d["text"], "你是誰？")
	assert_eq(d["choices"], [{ "id": "_next", "label": "（繼續）", "locked": false, "why": "" }])
	ok("dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n0", "choice": "_next" })
	d = lastp("dialogue")
	assert_eq(d["node"], "n_pick")
	assert_eq(d["speaker_name"], str(ch().name), "speaker player")
	var by_id := {}
	for c in d["choices"]:
		by_id[c["id"]] = c
	assert_false(by_id.has("c_hide"), "hide_if_locked")
	assert_true(bool(by_id["c_lock"]["locked"]))
	assert_true(str(by_id["c_lock"]["why"]).contains("200"), str(by_id["c_lock"]["why"]))
	assert_false(bool(by_id["c_a"]["locked"]))
	assert_eq(reason("dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n_pick", "choice": "c_lock" }), "choice_locked")
	# take 不夠 → 整個選項不執行（var took 也不設）
	assert_eq(reason("dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n_pick", "choice": "c_take" }), "quest_incomplete")
	assert_false(st()["vars"].has("took"))
	# 關掉再開 → 從 resume 開始
	ok("dialogue_close")
	ok("quest_talk", { "npc": "n_zhangwuji", "quest": QID })
	assert_eq(lastp("dialogue")["node"], "n_back")
	ok("dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n_back", "choice": "_next" })
	var lil := int(ch().lilian)
	ok("dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n_pick", "choice": "c_a" })
	assert_eq(st()["vars"]["pick"], "a")
	assert_eq(int(ch().lilian), lil + 3, "reward 動作立即給")
	assert_eq(stage(), "s_deliver", "complete → 階段完成 → next")
	d = lastp("dialogue")
	assert_eq(d["node"], "n_end", "對話在階段推進後照常往下")
	assert_eq(d["speaker_name"], host().npc_name("n_wujieshan"), "speaker 可以是其他 NPC id")
	# 移動清掉游標
	ok("move", { "dir": "D" })
	assert_true(s().dialogue.is_empty())

# ---------------------------------------------------------------- 各種目標
func test_story_deliver_collect_buy() -> void:
	if not game_ok():
		return
	install()
	make_char()
	ch().money = 1000
	accept_story()
	assert_true(host().quests.debug_stage(s(), QID, "s_deliver").get("ok", false))
	goto("xx_pharmacy")
	give("c_mantou", 1)
	assert_eq(reason("quest_talk", { "npc": "n_xx_pharmacist", "quest": QID }), "quest_incomplete")
	ok("talk", { "npc": "n_xx_pharmacist" })
	var states := {}
	for q in lastp("npc_menu")["quests"]:
		states[q["id"]] = q["state"]
	assert_eq(states.get(QID, ""), "ACTIVE", "物品不夠 → ACTIVE")
	give("c_mantou", 2)
	ok("talk", { "npc": "n_xx_pharmacist" })
	for q in lastp("npc_menu")["quests"]:
		states[q["id"]] = q["state"]
	assert_eq(states.get(QID, ""), "READY")
	ok("quest_turn_in", { "npc": "n_xx_pharmacist", "quest": QID })
	assert_eq(item_count("c_mantou"), 1, "扣 2 個")
	assert_eq(stage(), "s_collect")
	# BUY：本階段開始前買的不算（這裡在本階段才買，所以先確認 COLLECT 不會因 BUY 未完成而推進）
	give("c_water", 2)
	assert_eq(stage(), "s_collect", "COLLECT 達成但 BUY 還沒")
	ok("buy", { "npc": "n_xx_pharmacist", "item": "c_qiyao", "n": 1 })
	assert_eq(stage(), "s_kill", "BUY 完成 → 全部目標完成")
	assert_eq(item_count("c_water"), 2, "COLLECT 不扣")

func test_story_buy_before_stage_does_not_count() -> void:
	if not game_ok():
		return
	install()
	make_char()
	ch().money = 1000
	accept_story()
	goto("xx_pharmacy")
	ok("buy", { "npc": "n_xx_pharmacist", "item": "c_qiyao", "n": 1 })   # 在 s_talk 時買
	host().quests.debug_stage(s(), QID, "s_collect")
	give("c_water", 2)
	assert_eq(stage(), "s_collect", "之前買的不算")
	assert_eq(int(st()["objs"].get("o_buy", 0)), 0)

func test_story_kill_fight_and_room_actions() -> void:
	if not game_ok():
		return
	install()
	make_char()
	make_strong()
	accept_story()
	host().quests.debug_stage(s(), QID, "s_kill")
	host().quests.on_kills(s(), ["m_rabbit"])
	assert_eq(int(st()["objs"]["o_k"]), 1)
	host().quests.on_kills(s(), ["m_rabbit", "m_wolf"])
	assert_eq(stage(), "s_fight")
	# 房間動作：只在 xx_street、時辰對的才出現
	goto("xx_square")
	assert_eq(view().get("story_actions", []), [])
	assert_eq(reason("story_act", { "act": QID + ":a_f" }), "act_not_here")
	assert_eq(reason("story_act", { "act": QID + ":nope" }), "act_unknown")
	assert_eq(reason("story_act", { "act": "nope" }), "act_unknown")
	goto("xx_street")
	var acts: Array = []
	for a in view().get("story_actions", []):
		acts.append(a["act"])
	assert_has(acts, QID + ":a_f")
	assert_has(acts, QID + ":a_once")
	assert_not_has(acts, QID + ":a_night", "時辰不對不出現")
	assert_eq(reason("story_act", { "act": QID + ":a_night" }), "quest_not_now")
	ok("story_act", { "act": QID + ":a_once" })
	assert_eq(item_count("c_water"), 1)
	assert_eq(reason("story_act", { "act": QID + ":a_once" }), "act_unknown", "repeat: false 用過就消失")
	ws.flush()
	acts.clear()
	for a in view().get("story_actions", []):
		acts.append(a["act"])
	assert_not_has(acts, QID + ":a_once")
	# FIGHT：逃走也算（WIN_OR_FLEE）
	ok("story_act", { "act": QID + ":a_f" })
	assert_true(s().battle_id != 0)
	assert_eq(str(host().battles.active[s().battle_id]["kind"]), "QUEST")
	var res := drive_battle("flee")
	assert_eq(res.get("result", ""), "FLED", str(res))
	assert_eq(stage(), "s_reach", "WIN_OR_FLEE：逃走也完成")

func test_story_fight_win_rules() -> void:
	assert_true(QuestSystem.win_ok("WIN", "VICTORY"))
	assert_false(QuestSystem.win_ok("WIN", "FLED"))
	assert_false(QuestSystem.win_ok("WIN", "DEFEAT"))
	assert_true(QuestSystem.win_ok("WIN_OR_FLEE", "FLED"))
	assert_false(QuestSystem.win_ok("WIN_OR_FLEE", "DEFEAT"))
	assert_true(QuestSystem.win_ok("ANY", "DEFEAT"))
	assert_false(QuestSystem.win_ok("ANY", "ABORTED"))

func test_story_fight_win_victory_and_defeat() -> void:
	if not game_ok():
		return
	var q := fixture_quest()
	q["stages"][4]["room_actions"][0]["do"][0]["no_flee"] = true
	q["stages"][4]["objectives"][0]["win"] = "WIN"
	install([q, fixture_repeat()])
	make_char()
	make_strong()
	accept_story()
	host().quests.debug_stage(s(), QID, "s_fight")
	goto("xx_street")
	# 戰敗（摘要直接餵）：WIN 不算
	host().quests.on_battle_settled(s(), { "per": "DEFEAT", "quest_tag": { "quest": QID, "obj": "o_f", "by": str(ch().id), "members": [str(ch().id)] } })
	assert_eq(stage(), "s_fight")
	ok("story_act", { "act": QID + ":a_f" })
	var res := drive_battle("fight")
	assert_eq(res.get("result", ""), "VICTORY", str(res))
	assert_eq(stage(), "s_reach")

func test_story_reach_wait_state_escort_and_outcome() -> void:
	if not game_ok():
		return
	install()
	make_char("護送俠")
	accept_story()
	ch().quests["active"][QID]["vars"]["pick"] = "a"
	host().quests.debug_stage(s(), QID, "s_reach")
	goto("xx_street")
	assert_eq(stage(), "s_reach")
	goto("xx_square")
	ok("move", { "dir": "S" })
	assert_eq(stage(), "s_wait", "REACH")
	goto("xx_square")   # 離開驛站（ESCORT 的目的地），免得護送一開始就完成
	ws.advance(1.0)
	assert_eq(stage(), "s_wait")
	# WAIT：快轉世界時鐘半天
	host().quests.on_clock(s())
	assert_eq(stage(), "s_wait")
	ws.world["world_time_s"] = ws.world_time() + host().day_s() * 0.5
	host().quests.on_clock(s())
	assert_eq(stage(), "s_state", "WAIT days")
	ch().fame = 49
	host().quests.on_clock(s())
	assert_eq(stage(), "s_state")
	ch().fame = 50
	s().quest_state_check_ms = -100000
	host().push_sheet(s())   # on_sheet → STATE
	assert_eq(stage(), "s_escort")
	assert_eq(st()["escort"], "n_zhangwuji", "on_enter escort_start")
	# 護送：NPC 跟著玩家（view.escort、npc_here）
	goto("xx_square")
	assert_eq(view().get("escort", []), [{ "npc": "n_zhangwuji", "name": host().npc_name("n_zhangwuji") }])
	var found := false
	for n in view().get("npcs", []):
		if n["id"] == "n_zhangwuji":
			found = bool(n.get("escort", false))
	assert_true(found, "護送中的 NPC 出現在玩家所在的房間（escort: true）")
	assert_eq(host().npc_here(s(), "n_zhangwuji"), "")
	var money := int(ch().money)
	var fist := int(ch().skills.level("basic_fist"))
	clear_events()
	ok("move", { "dir": "S" })
	assert_false(ch().quests["active"].has(QID), "ESCORT 完成 → END:a")
	var done := QuestState.done_entry(ch().quests, QID)
	assert_eq(done["outcome"], "a")
	assert_eq(int(done["n"]), 1)
	assert_eq(int(ch().money), money + 7)
	assert_eq(int(ch().skills.level("basic_fist")), maxi(fist, 3), "learn")
	assert_eq(lastp("quest_complete").get("outcome_label", ""), "選了甲")
	assert_eq(int(lastp("reward").get("lilian", 0)), 5)
	assert_eq(host().ws.world["quest_firsts"].get(QID, ""), "護送俠", "全服第一")
	var dl: Array = sheet()["quests_done"]
	var row: Dictionary = {}
	for x in dl:
		if x["id"] == QID:
			row = x
	assert_eq(row, { "id": QID, "name": "測試故事", "chapter": "測試章", "outcome_label": "選了甲", "n": 1 })
	assert_eq(int(sheet()["lilian"]), int(ch().lilian))
	# 一次性：DONE
	goto("xx_square")
	ok("talk", { "npc": "n_wujieshan" })
	var states := {}
	for q in lastp("npc_menu")["quests"]:
		states[q["id"]] = q["state"]
	assert_eq(states.get(QID, ""), "DONE")
	assert_eq(reason("quest_talk", { "npc": "n_wujieshan", "quest": QID }), "quest_done")

func test_story_branch_b_and_fail() -> void:
	if not game_ok():
		return
	install()
	make_char()
	accept_story()
	goto("xx_inn_2f")
	ok("quest_talk", { "npc": "n_zhangwuji", "quest": QID })
	ok("dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n0", "choice": "_next" })
	ok("dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n_pick", "choice": "c_fail" })
	assert_false(ch().quests["active"].has(QID), "fail")
	assert_eq(item_count("i_letter"), 0, "收回 give_items")
	assert_eq(int(QuestState.done_entry(ch().quests, QID)["failed"]), 1)
	assert_eq(QuestState.done_count(ch().quests, QID), 0)
	assert_false(last("quest_fail").is_empty())
	assert_true(s().dialogue.is_empty())
	# 可以再接，走 b
	accept_story()
	ch().quests["active"][QID]["vars"]["pick"] = "b"
	host().quests.debug_stage(s(), QID, "s_escort")
	goto("xx_station")
	host().quests.on_reach(s())
	assert_eq(QuestState.done_entry(ch().quests, QID)["outcome"], "b")

func test_story_abandon_clears_escort_and_dialogue() -> void:
	if not game_ok():
		return
	install()
	make_char()
	accept_story()
	host().quests.debug_stage(s(), QID, "s_escort")
	assert_eq(host().quests.escort_npcs(ch()), ["n_zhangwuji"])
	ok("quest_abandon", { "quest": QID })
	assert_eq(host().quests.escort_npcs(ch()), [])
	assert_eq(item_count("i_letter"), 0)

# ---------------------------------------------------------------- 冷卻與次數
func test_story_repeat_cooldown_and_max() -> void:
	if not game_ok():
		return
	install()
	make_char()
	goto("xx_station")
	ok("quest_accept", { "npc": "n_xx_station", "quest": QREP })
	ok("quest_turn_in", { "npc": "n_xx_station", "quest": QREP })
	assert_eq(QuestState.done_count(ch().quests, QREP), 1)
	assert_eq(int(ch().lilian), 2)
	assert_eq(reason("quest_accept", { "npc": "n_xx_station", "quest": QREP }), "quest_cooldown")
	ok("talk", { "npc": "n_xx_station" })
	var e: Dictionary = {}
	for q in lastp("npc_menu")["quests"]:
		if q["id"] == QREP:
			e = q
	assert_eq(e.get("state", ""), "COOLDOWN")
	assert_true(float(e.get("cooldown_left_s", 0.0)) > 0.0)
	assert_true(float(sheet()["quest_cd"].get(QREP, 0.0)) > 0.0)
	ws.world["world_time_s"] = ws.world_time() + host().day_s() + 1.0
	ok("quest_accept", { "npc": "n_xx_station", "quest": QREP })
	ok("quest_turn_in", { "npc": "n_xx_station", "quest": QREP })
	ws.world["world_time_s"] = ws.world_time() + host().day_s() + 1.0
	assert_eq(reason("quest_accept", { "npc": "n_xx_station", "quest": QREP }), "quest_done", "max 2")

# ---------------------------------------------------------------- appear
func test_story_appear_by_hour() -> void:
	if not game_ok():
		return
	install()
	tables()["npcs"]["n_zhangwuji"]["appear"] = { "hours": ["申", "酉"], "requires": [] }
	make_char()
	goto("xx_inn_2f")
	set_shichen(3)   # 卯
	host().push_view(s())
	ws.flush()
	var ids: Array = []
	for n in view().get("npcs", []):
		ids.append(n["id"])
	assert_not_has(ids, "n_zhangwuji", "卯時不出現")
	assert_eq(reason("talk", { "npc": "n_zhangwuji" }), "not_here")
	set_shichen(8)   # 申
	host().flush_session(s(), true)
	ws.flush()
	ids.clear()
	for n in view().get("npcs", []):
		ids.append(n["id"])
	assert_has(ids, "n_zhangwuji", "申時出現（換時辰重送 view）")
	ok("talk", { "npc": "n_zhangwuji" })

func test_story_appear_by_quest_stage() -> void:
	if not game_ok():
		return
	install()
	tables()["npcs"]["n_zhangwuji"]["appear"] = { "requires": [{ "type": "quest_stage", "quest": QID, "stage": ["s_talk"] }] }
	make_char()
	assert_false(host().quests.npc_visible(ch(), "n_zhangwuji"))
	accept_story()
	assert_true(host().quests.npc_visible(ch(), "n_zhangwuji"))
	host().quests.debug_stage(s(), QID, "s_deliver")
	assert_false(host().quests.npc_visible(ch(), "n_zhangwuji"))

# ---------------------------------------------------------------- 存檔重載
func test_story_save_reload_mid_quest_with_escort() -> void:
	if not game_ok():
		return
	install()
	make_char("重載俠")
	var cid := str(ch().id)
	accept_story()
	ch().quests["active"][QID]["vars"]["pick"] = "a"
	host().quests.debug_stage(s(), QID, "s_kill")
	host().quests.on_kills(s(), ["m_rabbit"])
	host().quests.debug_stage(s(), QID, "s_escort")
	goto("xx_square")
	ws.save_now()
	restart_world()
	install()
	ok("char_select", { "char_id": cid })
	assert_eq(stage(), "s_escort")
	assert_eq(st()["vars"].get("pick", ""), "a", "變數還在")
	assert_eq(st()["escort"], "n_zhangwuji", "護送還在")
	assert_eq(view().get("escort", []).size(), 1, "重載後 NPC 仍跟著")
	ok("move", { "dir": "S" })
	assert_eq(QuestState.done_entry(ch().quests, QID).get("outcome", ""), "a")

# ---------------------------------------------------------------- debug intents
func test_story_debug_intents() -> void:
	if not game_ok():
		return
	ws.stop()
	ws.debug_intents = true
	assert_eq(ws.start(world_name), OK)
	cs.begin_local_session()
	if ws.sessions.has(1):
		ws.sessions[1].rate_limiter = TokenBucket.new(1000000.0, 1000000.0)
	install()
	make_char()
	ok("debug_set", { "key": "quest_stage", "value": QID + ":s_wait" })
	assert_eq(stage(), "s_wait")
	ok("debug_set", { "key": "world_s_add", "value": host().day_s() * 0.6 })
	assert_eq(stage(), "s_state")
	ok("debug_set", { "key": "fame", "value": 60 })
	ok("debug_set", { "key": "lilian", "value": 7 })
	assert_eq(int(ch().lilian), 7)
	ok("debug_set", { "key": "hour", "value": "申" })
	assert_eq(str(host().clock()["shichen_name"]), "申")
	ok("debug_set", { "key": "quest_reset", "value": QID })
	assert_false(ch().quests["active"].has(QID))
	assert_eq(reason("debug_set", { "key": "quest_stage", "value": QID + ":nope" }), "bad_value:value")
	assert_eq(reason("debug_set", { "key": "wander_place", "value": "w_x:nowhere" }), "bad_value:value")
	ok("debug_set", { "key": "rumor_flush", "value": true })
	ws.debug_intents = false
