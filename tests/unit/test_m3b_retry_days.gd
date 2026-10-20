extends "res://tests/unit/test_world_fixture.gd"
## M3b 審查：任務房間動作的 fight retry_days（2001-11-03 丐幫一袋「逃跑要再等一天」）：
## 沒打贏（逃走、戰敗）→ 同一個動作要等 retry_days 個遊戲日；打贏照常完成 FIGHT 目標。

const QID := "q_t_retry"

func before_each() -> void:
	world_name = "w_m3b_retry"
	super.before_each()

func _install() -> bool:
	if not game_ok() or make_char("重試俠") == null:
		return false
	GameData.tables["quests"][QID] = { "id": QID, "name": "測重試", "chapter": "", "group": "test", "giver": "",
		"era": "1.0A", "src": "proposal", "text": "", "requires": [], "give_items": [], "repeat": { "max": 1 },
		"abandon": true, "party_credit": true, "start": "s1",
		"stages": [ { "id": "s1", "title": "打", "log": "", "hint_room": "xx_square",
			"objectives": [ { "id": "o1", "type": "FIGHT", "win": "WIN", "text": "打贏" } ],
			"room_actions": [ { "id": "a1", "room": "xx_square", "label": "挑戰", "hours": [], "requires": [], "repeat": true,
				"do": [ { "do": "fight", "monsters": ["m_rabbit"], "retry_days": 1, "obj": "o1" } ] } ],
			"next": "END" } ],
		"outcomes": { "default": { "label": "完", "rewards": {}, "src": "proposal" } } }
	host().quests._do_accept(s(), QID)
	goto("xx_square")
	return QuestState.is_active(ch().quests, QID)

func test_flee_waits_a_day() -> void:
	if not _install():
		return
	var r := send("story_act", { "act": QID + ":a1" })
	assert_true(r.get("ok", false), "開打：%s" % str(r))
	var bid := s().battle_id
	assert_true(bid != 0, "進入戰鬥")
	var entry: Dictionary = host().battles.active.get(bid, {})
	var tag: Dictionary = entry.get("opts", {}).get("quest_tag", {})
	assert_eq(str(tag.get("act", "")), "a1", "quest_tag 記著房間動作")
	assert_eq(float(tag.get("retry_days", 0)), 1.0)
	# 結束這場（不經戰鬥結算），再用「逃走」的結算餵給任務系統
	host().battles.active[bid]["battle"].abort()
	ws.advance(0.3)
	s().battle_id = 0
	host().quests.on_battle_settled(s(), { "per": "FLED", "result": "FLED", "quest_tag": tag, "died": false })
	ws.flush()
	assert_false(last("quest_retry_tomorrow").is_empty(), "提示明天再來")
	assert_eq(reason("story_act", { "act": QID + ":a1" }), "quest_not_now", "逃走後當天不能再挑戰")
	# 過一個遊戲日
	ws.world["world_time_s"] = ws.world_time() + host().day_s() + 1.0
	r = send("story_act", { "act": QID + ":a1" })
	assert_true(r.get("ok", false), "隔天可以再來：%s" % str(r))
