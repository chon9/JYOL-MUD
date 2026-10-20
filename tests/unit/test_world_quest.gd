extends "res://tests/unit/test_world_fixture.gd"
## 5.7 每個任務的完整流程；放棄收回任務物品（M1_PLAN 6.1 test_world_quest）

func before_each() -> void:
	world_name = "w_quest"
	super.before_each()

## STORY_PLAN §4.14：quests_done 改成 [{ id, name, chapter, outcome_label, n }]
func done_ids() -> Array:
	var out: Array = []
	for d in sheet().get("quests_done", []):
		out.append(str(d.get("id", "")) if d is Dictionary else str(d))
	return out

func test_q_rabbit() -> void:
	if not game_ok():
		return
	make_char()
	assert_eq(reason("quest_accept", { "npc": "n_taoyun", "quest": "q_rabbit" }), "not_here")
	assert_eq(reason("quest_accept", { "npc": "n_wujieshan", "quest": "q_rice" }), "quest_unknown")
	ok("quest_accept", { "npc": "n_wujieshan", "quest": "q_rabbit" })
	assert_eq(reason("quest_accept", { "npc": "n_wujieshan", "quest": "q_rabbit" }), "quest_active")
	var ids := []
	for q in sheet()["quests"]:
		ids.append(q["id"])
	assert_has(ids, "q_rabbit")
	assert_eq(lastp("quest_accept").get("quest_name", ""), "狩獵事件：大兔皮")
	assert_eq(reason("quest_turn_in", { "npc": "n_wujieshan", "quest": "q_rabbit" }), "quest_incomplete")
	ok("talk", { "npc": "n_wujieshan" })
	assert_eq(lastp("npc_menu")["quests"][0]["state"], "ACTIVE")
	give("r_bigrabbitskin")
	ok("talk", { "npc": "n_wujieshan" })
	assert_eq(lastp("npc_menu")["quests"][0]["state"], "READY")
	var money := int(ch().money)
	var lp := int(ch().learn_points)
	ok("quest_turn_in", { "npc": "n_wujieshan", "quest": "q_rabbit" })
	assert_eq(int(ch().money), money + 100)
	assert_eq(int(ch().learn_points), lp + 25)
	assert_eq(item_count("r_bigrabbitskin"), 0)
	assert_has(done_ids(), "q_rabbit")
	assert_false(last("quest_complete").is_empty())
	assert_eq(int(lastp("reward").get("money", 0)), 100)
	assert_eq(reason("quest_accept", { "npc": "n_wujieshan", "quest": "q_rabbit" }), "quest_done")
	assert_eq(reason("quest_turn_in", { "npc": "n_wujieshan", "quest": "q_rabbit" }), "quest_not_active")

func test_q_rice() -> void:
	if not game_ok():
		return
	make_char("稻農", "dali")
	goto("dlw_paddy")
	ok("quest_accept", { "npc": "n_taoyun", "quest": "q_rice" })
	give("r_rice", 4)
	assert_eq(reason("quest_turn_in", { "npc": "n_taoyun", "quest": "q_rice" }), "quest_incomplete")
	give("r_rice", 2)
	var xp := int(ch().combat_xp)
	var prof := int(ch().skills.prof("life_farming"))
	ok("quest_turn_in", { "npc": "n_taoyun", "quest": "q_rice" })
	assert_eq(item_count("r_rice"), 1)
	assert_eq(int(ch().combat_xp), xp + 10)
	assert_eq(int(ch().skills.prof("life_farming")), prof + 10, "skill_prof reward")
	assert_eq(QuestState.done_count(ch().quests, "q_rice"), 1)

func test_q_letter_round_trip_and_repeat() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_station")
	ok("quest_accept", { "npc": "n_xx_station", "quest": "q_letter" })
	assert_eq(item_count("i_letter"), 1, "give_items")
	assert_eq(lastp("item_gain").get("item_name", ""), host().item_name("i_letter"))
	assert_eq(reason("drop_item", { "item_uid": first_uid("i_letter") }), "not_droppable")
	assert_eq(reason("quest_turn_in", { "npc": "n_xx_station", "quest": "q_letter" }), "quest_incomplete")
	# 信要親自走到大理驛站才能交（WORLD_2001 §5.1；馬車預設關閉）
	assert_eq(reason("travel", { "npc": "n_xx_station", "dest": "dl_station" }), "stagecoach_disabled")
	assert_eq(reason("quest_turn_in", { "npc": "n_dl_station", "quest": "q_letter" }), "not_here")
	goto("dl_gate_n")
	assert_eq(reason("quest_turn_in", { "npc": "n_dl_station", "quest": "q_letter" }), "not_here")
	goto("dl_station")
	ok("talk", { "npc": "n_dl_station" })
	var states := {}
	for q in lastp("npc_menu")["quests"]:
		states[q["id"]] = q["state"]
	assert_eq(states.get("q_letter", ""), "READY", "turn-in target lists the quest")
	assert_eq(states.get("q_letter_dl", ""), "AVAILABLE")
	var money := int(ch().money)
	var fame := int(ch().fame)
	ok("quest_turn_in", { "npc": "n_dl_station", "quest": "q_letter" })
	assert_eq(int(ch().money), money + 100)
	assert_eq(int(ch().fame), fame + 2)
	assert_eq(item_count("i_letter"), 0)
	# 可重複；大理也有一條
	ok("quest_accept", { "npc": "n_dl_station", "quest": "q_letter_dl" })
	assert_eq(item_count("i_letter"), 1)
	goto("xx_station")
	ok("quest_turn_in", { "npc": "n_xx_station", "quest": "q_letter_dl" })
	ok("quest_accept", { "npc": "n_xx_station", "quest": "q_letter" })
	assert_eq(QuestState.done_count(ch().quests, "q_letter"), 1)

func test_abandon_takes_back_items() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_station")
	ok("quest_accept", { "npc": "n_xx_station", "quest": "q_letter" })
	assert_eq(item_count("i_letter"), 1)
	ok("quest_abandon", { "quest": "q_letter" })
	assert_eq(item_count("i_letter"), 0)
	assert_false(last("item_lost").is_empty())
	assert_false(last("quest_abandon").is_empty())
	assert_eq(reason("quest_abandon", { "quest": "q_letter" }), "quest_not_active")
	ok("quest_accept", { "npc": "n_xx_station", "quest": "q_letter" })

func test_q_bandit_kill_and_talk() -> void:
	if not game_ok():
		return
	make_char("捕快幫手", "dali")
	goto("dl_yamen")
	ok("quest_accept", { "npc": "n_dl_bukuai", "quest": "q_bandit" })
	assert_eq(reason("quest_turn_in", { "npc": "n_dl_bukuai", "quest": "q_bandit" }), "quest_incomplete")
	# KILL 計數走戰鬥結果的 kills（4.8）：由 QuestSystem.on_kills 推進
	host().quests.on_kills(s(), ["m_bandit", "m_wolf"])
	ws.flush()
	assert_eq(int(ch().quests["active"]["q_bandit"]["objs"]["o"]), 1, "STORY_PLAN §4.12：舊步驟正規化成階段 step_<i>、目標 o")
	assert_eq(int(lastp("quest_progress").get("have", 0)), 1)
	assert_eq(int(lastp("quest_progress").get("need", 0)), 3)
	host().quests.on_kills(s(), ["m_bandit", "m_bandit"])
	assert_eq(str(ch().quests["active"]["q_bandit"]["stage"]), "step_1", "moved to TALK step")
	var lp := int(ch().learn_points)
	var mor := int(ch().morality)
	ok("quest_turn_in", { "npc": "n_dl_bukuai", "quest": "q_bandit" })
	assert_eq(int(ch().learn_points), lp + 30)
	assert_eq(int(ch().morality), mor + 10)
	assert_has(done_ids(), "q_bandit")

func test_q_hs_kaoyan_full_flow() -> void:
	if not game_ok():
		return
	make_char("華山客")
	goto("hs_square")
	assert_true(reason("quest_accept", { "npc": "n_yuebuqun", "quest": "q_hs_kaoyan" }).begins_with("req_"))
	ch().skills.set_level("basic_inner", 5, tables())
	ch().skills.set_level("basic_literacy", 5, tables())
	ok("quest_accept", { "npc": "n_yuebuqun", "quest": "q_hs_kaoyan" })
	make_strong()
	ok("fight", { "npc": "n_ludayou" })
	var res := drive_battle("fight")
	assert_eq(res.get("result", ""), "VICTORY", str(res))
	assert_eq(str(ch().quests["active"]["q_hs_kaoyan"]["stage"]), "step_1", "trainee kill counted (no_rewards monster)")
	ok("quest_turn_in", { "npc": "n_yuebuqun", "quest": "q_hs_kaoyan" })
	assert_eq(ch().flags.get("hs_trial_passed", false), true)
	ok("join_sect", { "npc": "n_yuebuqun" })
	assert_eq(str(ch().sect), "huashan")

func test_quest_full() -> void:
	if not game_ok():
		return
	make_char()
	for i in GameHost.MAX_ACTIVE_QUESTS:
		ch().quests["active"]["q_fake_%d" % i] = { "step": 0, "counts": {} }
	assert_eq(reason("quest_accept", { "npc": "n_wujieshan", "quest": "q_rabbit" }), "quest_full")

## 回歸：鎖住的任務要說出差什麼（擁有者回報藍鳳凰採收毒物只顯示 [LOCKED]）
func test_locked_quest_lists_unmet_requirements() -> void:
	if not game_ok():
		return
	make_char()
	ch().attrs["luck"] = 10
	var entry := {}
	for e in host().quests.menu_entries(s(), "n_lf_lanfenghuang"):
		if str(e.get("id", "")) == "q_lanfeng":
			entry = e
	assert_eq(entry.get("state", ""), "LOCKED")
	assert_true(str(entry.get("locked_why", "")).contains("22"), "說出福緣門檻：%s" % entry.get("locked_why", ""))
	ch().attrs["luck"] = 30
	for e in host().quests.menu_entries(s(), "n_lf_lanfenghuang"):
		if str(e.get("id", "")) == "q_lanfeng":
			assert_eq(e.get("state", ""), "AVAILABLE", "福緣夠了就能接")
			assert_false(e.has("locked_why"))
