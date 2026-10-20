extends "res://tests/unit/test_world_fixture.gd"
## STORY_PLAN §9.1 test_world_quest_party：兩個 session 同隊：KILL／FIGHT 各自計分、solo 不拉隊友也不計、
## 中途加入的不計 FIGHT；兩人同任務不同階段時 appear 各自不同；對話游標互不干擾。方法名 test_story_*。

const V2 := preload("res://tests/unit/test_world_quest_v2.gd")
const QID := "q_t_story"

func before_each() -> void:
	world_name = "w_story_party"
	super.before_each()

func install(q: Dictionary = {}) -> void:
	for r in [q if not q.is_empty() else V2.fixture_quest(), V2.fixture_repeat()]:
		var row := QuestDef.normalize(r)
		tables()["quests"][str(row["id"])] = row
		var giver: Dictionary = tables()["npcs"][str(row["giver"])]
		var qs: Array = (giver.get("quests", []) as Array).duplicate()
		if not qs.has(str(row["id"])):
			qs.append(str(row["id"]))
		giver["quests"] = qs

func _strengthen(c) -> void:
	for a in ["str", "agi", "con", "guts", "cal"]:
		c.attrs[a] = 120
	for sk in ["basic_fist", "basic_blade", "basic_dodge", "basic_parry"]:
		c.skills.set_level(sk, 60, tables())
	c.clamp_vitals(tables(), ws.options)
	Survival.rest_full(c, tables(), ws.options)

func _cid(peer: int) -> String:
	return str(session_of(peer).character.id)

func _form_party(p2: int) -> void:
	ok("party_invite", { "target": _cid(p2) })
	assert_true(send_as(p2, "party_reply", { "from": str(ch().id), "accept": true }).get("ok", false), "party_reply")

func _stage_of(o: Session) -> String:
	return str(o.character.quests["active"].get(QID, {}).get("stage", ""))

func _setup_two(stage: String) -> int:
	make_char("甲俠")
	make_strong()
	var p2 := add_player("乙俠")
	_strengthen(session_of(p2).character)
	_form_party(p2)
	for o in [s(), session_of(p2)]:
		assert_true(host().quests.debug_stage(o, QID, stage).get("ok", false), "debug_stage")
	return p2

func test_story_party_kill_each_counts() -> void:
	if not game_ok():
		return
	install()
	var p2 := _setup_two("s_kill")
	goto("xx_street")
	goto_as(p2, "xx_street")
	var bid := start_battle(["m_rabbit", "m_rabbit"])
	assert_eq(host().battles.humans(bid), 2, "同房隊友被拉進來")
	var res := drive_battle("fight")
	assert_eq(res.get("result", ""), "VICTORY", str(res))
	assert_eq(_stage_of(s()), "s_fight", "甲：兩隻都算（不限最後一擊）")
	assert_eq(_stage_of(session_of(p2)), "s_fight", "乙：同場隊友各自得分")

func test_story_party_credit_false_only_own_kills() -> void:
	if not game_ok():
		return
	var q := V2.fixture_quest()
	q["party_credit"] = false
	install(q)
	make_char()
	host().quests.debug_stage(s(), QID, "s_kill")
	host().quests.on_battle_settled(s(), { "per": "VICTORY", "party_kills": ["m_rabbit", "m_rabbit"] })
	assert_eq(int(ch().quests["active"][QID]["objs"].get("o_k", 0)), 0, "party_credit false：隊友的擊殺不算")
	install()
	host().quests.on_battle_settled(s(), { "per": "VICTORY", "party_kills": ["m_rabbit"] })
	assert_eq(int(ch().quests["active"][QID]["objs"].get("o_k", 0)), 1, "party_credit true：算")
	host().quests.on_battle_settled(s(), { "per": "FLED", "party_kills": ["m_rabbit"] })
	assert_eq(int(ch().quests["active"][QID]["objs"].get("o_k", 0)), 1, "沒打贏不算")

func test_story_party_fight_room_action_both_complete() -> void:
	if not game_ok():
		return
	install()
	var p2 := _setup_two("s_fight")
	goto("xx_street")
	goto_as(p2, "xx_street")
	ok("story_act", { "act": QID + ":a_f" })
	var bid := s().battle_id
	assert_true(bid != 0)
	assert_eq(session_of(p2).battle_id, bid, "隊友被拉進任務戰鬥")
	var tag: Dictionary = host().battles.active[bid]["opts"]["quest_tag"]
	assert_eq(tag["quest"], QID)
	assert_eq((tag["members"] as Array).size(), 2)
	var res := drive_battle("fight")
	assert_eq(res.get("result", ""), "VICTORY", str(res))
	assert_eq(_stage_of(s()), "s_reach")
	assert_eq(_stage_of(session_of(p2)), "s_reach", "隊友自己的目標符合 → 也完成")

func test_story_party_fight_solo_and_mid_join() -> void:
	if not game_ok():
		return
	var q := V2.fixture_quest()
	q["stages"][4]["room_actions"][0]["do"][0]["solo"] = true
	install(q)
	var p2 := _setup_two("s_fight")
	goto("xx_street")
	goto_as(p2, "xx_street")
	ok("story_act", { "act": QID + ":a_f" })
	assert_eq(session_of(p2).battle_id, 0, "solo：不拉隊友")
	drive_battle("fight")
	assert_eq(_stage_of(s()), "s_reach")
	assert_eq(_stage_of(session_of(p2)), "s_fight", "solo：隊友不計")
	# 非 solo，但乙中途加入 → 不計
	install()
	host().quests.debug_stage(s(), QID, "s_fight")
	goto_as(p2, "xx_square")
	ok("story_act", { "act": QID + ":a_f" })
	var bid := s().battle_id
	goto_as(p2, "xx_street")
	var j := send_as(p2, "battle_join", { "battle_id": bid })
	if j.get("ok", false):
		drive_battle("fight")
		assert_eq(_stage_of(session_of(p2)), "s_fight", "中途加入的玩家不計 FIGHT")
	else:
		drive_battle("fight")
	assert_eq(_stage_of(s()), "s_reach")

func test_story_party_appear_per_player() -> void:
	if not game_ok():
		return
	install()
	tables()["npcs"]["n_zhangwuji"]["appear"] = { "requires": [{ "type": "quest_stage", "quest": QID, "stage": "s_talk" }] }
	make_char("甲俠")
	var p2 := add_player("乙俠")
	host().quests.debug_stage(s(), QID, "s_talk")
	goto("xx_inn_2f")
	goto_as(p2, "xx_inn_2f")
	host().push_view(session_of(p2))
	ws.flush()
	var a_ids: Array = []
	for n in view().get("npcs", []):
		a_ids.append(n["id"])
	var b_ids: Array = []
	for n in view_for(p2).get("npcs", []):
		b_ids.append(n["id"])
	assert_has(a_ids, "n_zhangwuji", "甲在 s_talk → 看得到")
	assert_not_has(b_ids, "n_zhangwuji", "乙沒接 → 看不到")
	assert_eq(reason_as(p2, "talk", { "npc": "n_zhangwuji" }), "not_here")

func test_story_party_dialogue_cursors_independent() -> void:
	if not game_ok():
		return
	install()
	var p2 := _setup_two("s_talk")
	goto("xx_inn_2f")
	goto_as(p2, "xx_inn_2f")
	ok("quest_talk", { "npc": "n_zhangwuji", "quest": QID })
	assert_true(send_as(p2, "quest_talk", { "npc": "n_zhangwuji", "quest": QID }).get("ok", false))
	assert_eq(s().dialogue.get("node", ""), "n0")
	assert_eq(session_of(p2).dialogue.get("node", ""), "n0")
	ok("dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n0", "choice": "_next" })
	assert_eq(s().dialogue.get("node", ""), "n_pick")
	assert_eq(session_of(p2).dialogue.get("node", ""), "n0", "乙的游標不動")
	assert_eq(reason_as(p2, "dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n_pick", "choice": "c_a" }),
		"dialogue_stale", "乙不能用甲的節點")
	ok("dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n_pick", "choice": "c_a" })
	assert_true(send_as(p2, "dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n0", "choice": "_next" }).get("ok", false))
	assert_true(send_as(p2, "dialogue_choose", { "npc": "n_zhangwuji", "quest": QID, "node": "n_pick", "choice": "c_b" }).get("ok", false))
	assert_eq(ch().quests["active"][QID]["vars"]["pick"], "a")
	assert_eq(session_of(p2).character.quests["active"][QID]["vars"]["pick"], "b", "兩人的變數各自的")
	assert_false(evs_for(p2, "dialogue").is_empty(), "乙收到自己的對話事件")
