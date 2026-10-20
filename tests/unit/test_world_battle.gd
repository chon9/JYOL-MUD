extends "res://tests/unit/test_world_fixture.gd"
## 遇敵 → 開戰 → s2c_battle_open → battle_cmd 打贏 → 獎勵入帳、KILL 任務計數、角色表更新；逃跑無獎勵
## （M1_PLAN 6.1 test_world_battle）

func before_each() -> void:
	world_name = "w_battle"
	super.before_each()

func test_encounter_by_walking() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_road")
	var met := false
	for i in 200:
		var r := send("move", { "dir": "E" if str(ch().location["room"]) == "xw_road" else "W" })
		assert_true(r.get("ok", false), str(r))
		if s().battle_id != 0:
			met = true
			break
	assert_true(met, "met a monster within 200 steps")
	if not met:
		return
	var enc := lastp("encounter")
	assert_eq(last("encounter").get("ch", ""), "BATTLE")
	assert_true(str(enc.get("monsters", "")) != "")
	assert_true(str(enc.get("clock", "")).ends_with("刻"))
	var st: Dictionary = cs.battle_state
	assert_eq(int(st.get("bid", 0)), s().battle_id)
	assert_eq(int(st.get("w", 0)), 12)
	assert_eq(int(st.get("h", 0)), 8)
	assert_true(int(st.get("my_uid", 0)) > 0)
	assert_true(bool(st.get("wait_mode", false)), "wait mode on by default")
	assert_eq(sheet()["in_battle"], true)
	# 戰鬥中不能做別的事
	assert_eq(reason("move", { "dir": "W" }), "in_battle")
	assert_eq(reason("meditate"), "in_battle")
	assert_eq(reason("battle_cmd", { "battle_id": s().battle_id + 99, "cmd": "DEFEND" }), "battle_not_found")
	make_strong()
	var res := drive_battle("fight")
	assert_true(res.get("result", "") in ["VICTORY", "FLED", "DEFEAT"], str(res))
	assert_eq(sheet()["in_battle"], false)
	assert_true(cs.battle_state.is_empty(), "battle_state cleared on close")

func test_victory_rewards_and_kill_quest() -> void:
	if not game_ok():
		return
	make_char("剿匪俠", "dali")
	goto("dl_yamen")
	ok("quest_accept", { "npc": "n_dl_bukuai", "quest": "q_bandit" })
	goto("dlw_forest")
	make_strong()
	var xp := int(ch().combat_xp)
	var lp := int(ch().learn_points)
	start_battle(["m_bandit"])
	assert_true(s().battle_id != 0)
	assert_false(cs.battle_state.is_empty())
	var bevents := []
	for e in events:
		if e.get("ch", "") == "BATTLE":
			bevents.append(e)
			assert_true(e.has("seq") and e.has("t"), "forwarded battle events get seq and t")
	assert_false(bevents.is_empty(), "battle start events forwarded")
	var res := drive_battle("fight")
	assert_eq(res.get("result", ""), "VICTORY", str(res))
	assert_eq(res.get("you_died", true), false)
	assert_true(int(res["rewards"]["combat_xp"]) > 0)
	assert_eq(int(ch().combat_xp), xp + int(res["rewards"]["combat_xp"]))
	assert_eq(int(ch().learn_points), lp + int(res["rewards"]["learn_points"]))
	assert_false(last("battle_victory").is_empty())
	assert_eq(int(lastp("battle_reward").get("combat_xp", -1)), int(res["rewards"]["combat_xp"]))
	# 故事包（STORY_PLAN §4.7、§4.12）：舊任務正規化成階段 step_<i>、目標 "o"；計數在 objs
	assert_eq(int(ch().quests["active"]["q_bandit"].get("objs", {}).get("o", 0)), 1, "KILL counted")
	assert_eq(int(sheet()["combat_xp"]), int(ch().combat_xp), "sheet refreshed after battle")
	assert_eq(sheet()["in_battle"], false)
	# 戰鬥結束後氣寫回角色（不會是戰前的滿值以外的亂數）
	assert_true(int(ch().vitals["qi"]) >= 1)

func test_flee_gives_no_rewards() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_grass")
	ch().attrs["agi"] = 150     # 跑得比較快
	ch().vitals["qi"] = int(ch().derived(tables(), ws.options)["qi_max"])
	var xp := int(ch().combat_xp)
	start_battle(["m_wolf"])
	var res := drive_battle("flee", 1500.0)
	if res.get("result", "") == "FLED":
		assert_eq(int(res["rewards"]["combat_xp"]), 0)
		assert_eq(int(ch().combat_xp), xp)
		assert_false(last("battle_fled").is_empty())
	else:
		assert_true(res.get("result", "") in ["DEFEAT"], "fled or died: %s" % str(res))

func test_wait_mode_timeout_auto_defends() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_grass")
	start_battle(["m_rabbit"])
	var bid := s().battle_id
	# 什麼都不送：等待模式逾時後自動防守（battle_timeout）
	var t := 0.0
	while last("battle_timeout").is_empty() and t < 120.0 and s().battle_id == bid:
		ws.advance(0.5)
		t += 0.5
	assert_false(last("battle_timeout").is_empty(), "battle_timeout after %.1f s" % t)

## 斷線不中止戰鬥：自動防守打到分出勝負並結算（新手打野狼必死 → 回出生地、存檔），不能靠拔線逃過死亡
func test_disconnect_resolves_battle_with_penalty() -> void:
	if not game_ok():
		return
	var c = make_char()
	goto("xw_grass")
	start_battle(["m_wolf"])
	assert_eq(host().battles.active.size(), 1)
	var ident: String = s().identity
	ws.on_peer_disconnected(1)
	assert_eq(host().battles.active.size(), 0, "battle resolved")
	assert_eq(int(c.dead_count), 1, "auto-DEFEND newbie dies to the wolf")
	var r: Dictionary = sm.load_character(world_name, ident, str(c.id))
	assert_true(r["ok"])
	assert_eq(int(r["data"]["dead_count"]), 1, "death saved")
	assert_true(str(r["data"]["location"]["room"]) != "xw_grass", "respawned elsewhere")

func test_smoke_reduces_encounters() -> void:
	if not game_ok():
		return
	make_char()
	var uid := give("c_smoke")
	ok("use_item", { "item_uid": uid })
	assert_true(float(ch().buffs.get("smoke_until_s", 0.0)) > ws.world_time() + 200.0)
	assert_eq(item_count("c_smoke"), 0)
