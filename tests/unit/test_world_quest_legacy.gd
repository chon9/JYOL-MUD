extends "res://tests/unit/test_world_fixture.gd"
## STORY_PLAN §9.1 test_world_quest_legacy：既有（舊 steps 格式）任務經正規化後照舊可做——
## 大兔皮、種稻、送信、剿滅山賊、岳不群考驗、M3a 各派任務，逐條走完整的主機路徑；舊存檔中途接著做。方法名 test_story_*。

func before_each() -> void:
	world_name = "w_story_legacy"
	super.before_each()

func _legacy_ids() -> Array:
	var out: Array = []
	for qid in tables()["quests"]:
		if bool(tables()["quests"][qid].get("_legacy", false)):
			out.append(qid)
	out.sort()
	return out

## 依任務的 requires 把角色調到符合（門派、技能、旗標、善惡、時辰）
func _satisfy(qid: String) -> void:
	var c = ch()
	for cond in tables()["quests"][qid].get("requires", []):
		match str(cond.get("type", "")):
			"sect":
				c.sect = str(cond["sect"])
			"no_sect":
				c.sect = ""
			"skill_min":
				c.skills.set_level(str(cond["skill"]), maxi(int(cond["value"]), c.skills.level(str(cond["skill"]))), tables())
			"quest_flag":
				c.flags[str(cond["flag"])] = true
			"morality_min":
				c.morality = maxi(c.morality, int(cond["value"]))
			"gender":
				c.gender = str(cond["value"])
			"hour_in":
				set_shichen(WorldClock.SHICHEN.find(str(cond["hours"][0])))

func _npc_room(npc_id: String) -> String:
	return host().index.room_of_npc(npc_id)

func _run_one(qid: String) -> void:
	var row: Dictionary = tables()["quests"][qid]
	_satisfy(qid)
	var giver := str(row["giver"])
	goto(_npc_room(giver))
	var r := send("quest_accept", { "npc": giver, "quest": qid })
	if not assert_true(r.get("ok", false), "%s accept: %s" % [qid, str(r)]):
		return
	var before := QuestState.done_count(ch().quests, qid)
	var guard := 0
	while ch().quests["active"].has(qid) and guard < 10:
		guard += 1
		var st: Dictionary = ch().quests["active"][qid]
		var stage := QuestDef.stage(row, str(st["stage"]))
		var o: Dictionary = stage["objectives"][0]
		match str(o["type"]):
			"KILL":
				var kills: Array = []
				for i in int(o.get("count", 1)):
					kills.append(str(o["monster"]))
				host().quests.on_kills(s(), kills)
			"DELIVER":
				var need := int(o.get("count", 1)) - item_count(str(o["item"]))
				if need > 0:
					give(str(o["item"]), need)
				goto(_npc_room(str(o["npc"])))
				ok("quest_turn_in", { "npc": str(o["npc"]), "quest": qid })
			"TALK":
				goto(_npc_room(str(o["npc"])))
				ok("quest_turn_in", { "npc": str(o["npc"]), "quest": qid })
			"REACH":
				goto(str(o["room"]))
	assert_false(ch().quests["active"].has(qid), qid + " 走完")
	assert_eq(QuestState.done_count(ch().quests, qid), before + 1, qid + " 完成一次")
	assert_eq(QuestState.done_entry(ch().quests, qid)["outcome"], "default", qid)

func test_story_all_legacy_quests_still_playable() -> void:
	if not game_ok():
		return
	var ids := _legacy_ids()
	assert_true(ids.size() >= 14, "既有任務都正規化成舊格式標記：%s" % str(ids))
	for qid in ids:
		# 每條任務用新角色，避免門派等條件互相干擾
		ws.stop()
		remote.clear()
		assert_eq(ws.start("%s_%d" % [world_name, ids.find(qid)]), OK)
		cs.begin_local_session()
		if ws.sessions.has(1):
			ws.sessions[1].rate_limiter = TokenBucket.new(1000000.0, 1000000.0)
		ws.flush()
		make_char("舊任務%d" % ids.find(qid), "xixia")
		ch().combat_xp = 50000
		_run_one(qid)

func test_story_legacy_rewards_unchanged() -> void:
	if not game_ok():
		return
	make_char("兔皮客")
	goto("xx_square")
	ok("quest_accept", { "npc": "n_wujieshan", "quest": "q_rabbit" })
	give("r_bigrabbitskin")
	var money := int(ch().money)
	var lp := int(ch().learn_points)
	ok("quest_turn_in", { "npc": "n_wujieshan", "quest": "q_rabbit" })
	assert_eq(int(ch().money), money + 100)
	assert_eq(int(ch().learn_points), lp + 25)
	assert_eq(int(lastp("reward").get("money", 0)), 100)
	assert_eq(lastp("quest_complete").get("outcome_label", "x"), "", "舊任務沒有結局名")

func test_story_old_save_continues() -> void:
	if not game_ok():
		return
	make_char("舊檔俠", "dali")
	var cid := str(ch().id)
	goto("dl_yamen")
	ok("quest_accept", { "npc": "n_dl_bukuai", "quest": "q_bandit" })
	# 模擬 M1 存檔：舊格式 { step, counts }、done: int
	ch().quests = { "active": { "q_bandit": { "step": 0, "counts": { "m_bandit": 2 } } }, "done": { "q_rabbit": 1 } }
	ws.save_now()
	restart_world()
	ok("char_select", { "char_id": cid })
	assert_eq(str(ch().quests["active"]["q_bandit"]["stage"]), "step_0", "Character.from_dict 遷移")
	assert_eq(int(ch().quests["active"]["q_bandit"]["objs"]["o"]), 2)
	assert_eq(QuestState.done_count(ch().quests, "q_rabbit"), 1)
	host().quests.on_kills(s(), ["m_bandit"])
	assert_eq(str(ch().quests["active"]["q_bandit"]["stage"]), "step_1", "第 3 隻 → 下一步")
	ok("quest_turn_in", { "npc": "n_dl_bukuai", "quest": "q_bandit" })
	assert_eq(QuestState.done_count(ch().quests, "q_bandit"), 1)

func test_story_in_memory_legacy_state_tolerated() -> void:
	if not game_ok():
		return
	make_char()
	# 舊程式碼／測試直接寫舊格式進記憶體：引擎入口自動轉
	ch().quests["active"]["q_rabbit"] = { "step": 0, "counts": {} }
	goto("xx_square")
	give("r_bigrabbitskin")
	ok("quest_turn_in", { "npc": "n_wujieshan", "quest": "q_rabbit" })
	assert_eq(QuestState.done_count(ch().quests, "q_rabbit"), 1)
