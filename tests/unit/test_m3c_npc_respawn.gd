extends "res://tests/unit/test_world_fixture.gd"
## WP-NPCPK（M3C_PLAN §5.3、§9.1、§12.1）：world.npc_down 存檔、主機重開後照舊、到時重生；npc_respawn_pct 縮放；
## 類別預設重生（動物 1 時辰、惡人 6 時辰）；debug_set npc_respawn_now（只在 --debug-intents）。

const A := preload("res://tests/unit/test_m3c_npc_attack.gd")

func _setup(city: String, room: String) -> bool:
	if not game_ok():
		return false
	ws.options["sect_hostile_entry"] = false
	ws.options["guards_enabled"] = false
	if make_char("重生測試", city) == null:
		return false
	make_strong()
	goto(room)
	clear_events()
	return true

func _near(a: float, b: float, eps: float, msg: String) -> void:
	assert_true(absf(a - b) <= eps, "%s: %.3f vs %.3f" % [msg, a, b])

func _sys():
	return host().get("npcpk")

func _kill(nid: String) -> void:
	ok("npc_attack", { "npc": nid })
	A.finish(self)

func _left_shichen(nid: String) -> float:
	var e: Dictionary = ws.world.get("npc_down", {}).get(nid, {})
	return (float(e.get("until_s", 0.0)) - ws.world_time()) / WorldClock.shichen_len(host().day_s())

func test_down_survives_restart_then_respawns() -> void:
	if not _setup("dali", "dl_square"):
		return
	_kill("n_na_dl_xiaohai")
	assert_true(_sys().npc_down("n_na_dl_xiaohai"))
	var cid := str(ch().id)
	ws.save_now()
	restart_world()
	ok("char_select", { "char_id": cid })
	ws.flush()
	assert_true(ws.world.get("npc_down", {}).has("n_na_dl_xiaohai"), "world.json keeps npc_down")
	assert_true(_sys().npc_down("n_na_dl_xiaohai"), "still down after restart")
	host().flush_session(s(), true)
	ws.flush()
	assert_false("n_na_dl_xiaohai" in A.npc_ids_in_view(view()))
	clear_events()
	A.advance_shichen(self, 3.0)
	assert_false(_sys().npc_down("n_na_dl_xiaohai"), "respawned at the saved time")
	assert_false(ws.world.get("npc_down", {}).has("n_na_dl_xiaohai"), "entry removed")
	assert_false(evs("na_npc_back").is_empty())

func test_category_defaults() -> void:
	if not _setup("xixia", "xw_grass"):
		return
	_kill("n_na_xw_yang")
	_near(_left_shichen("n_na_xw_yang"), 1.0, 0.01, "animal: 1 時辰")
	goto("xx_street")
	_kill("n_na_xx_eba")
	_near(_left_shichen("n_na_xx_eba"), 6.0, 0.01, "villain: 6 時辰")

func test_respawn_pct_scales() -> void:
	if not _setup("xixia", "xx_minfang"):
		return
	ws.options["npc_respawn_pct"] = 200
	_kill("n_na_xx_jumin")
	_near(_left_shichen("n_na_xx_jumin"), 6.0, 0.01, "civilian 3 × 200%")
	_sys().respawn_now("n_na_xx_jumin")
	ws.options["npc_respawn_pct"] = 10
	_kill("n_na_xx_jumin")
	_near(_left_shichen("n_na_xx_jumin"), 0.3, 0.01, "civilian 3 × 10%")
	ws.options["npc_respawn_pct"] = 5   # 低於下限 → 夾到 10%
	_sys().respawn_now("*")
	_kill("n_na_xx_jumin")
	_near(_left_shichen("n_na_xx_jumin"), 0.3, 0.01, "clamped to 10%")
	ws.options["npc_respawn_pct"] = 100

func test_debug_set_respawn_now() -> void:
	if not _setup("xixia", "xx_minfang"):
		return
	_kill("n_na_xx_jumin")
	var dbg: GDScript = load("res://server/intents/intents_debug.gd")
	var r: Dictionary = dbg.call("apply", host(), s(), "npc_respawn_now", "n_na_xx_jumin")
	assert_true(r.get("ok", false), str(r))
	assert_false(_sys().npc_down("n_na_xx_jumin"))

func test_debug_set_m3c_keys() -> void:
	if not _setup("xixia", "xw_grass"):
		return
	var dbg: GDScript = load("res://server/intents/intents_debug.gd")
	for k in ["appearance", "give_item", "loot_force", "rng_seed", "battle_monster", "encounter_next", "npc_respawn_now", "divine_grant"]:
		assert_true(k in dbg.get("KEYS"), k)
	var r: Dictionary = dbg.call("apply", host(), s(), "give_item", "c_mantou:3")
	assert_true(r.get("ok", false), str(r))
	assert_eq(int(ch().inventory.count("c_mantou")) >= 3, true)
	assert_eq(str(dbg.call("apply", host(), s(), "give_item", "no_such:1").get("reason", "")), "bad_value:value")
	r = dbg.call("apply", host(), s(), "rng_seed", 4242)
	assert_true(r.get("ok", false))
	assert_eq(int(ws.rng.seed), 4242)
	# encounter_next：下一次可遇敵的移動必定遇敵（不看 encounters_enabled）
	ws.options["encounters_enabled"] = false
	r = dbg.call("apply", host(), s(), "encounter_next", true)
	assert_true(r.get("ok", false))
	assert_true(host().regions.roll_encounter(s()), "forced encounter")
	assert_true(s().battle_id != 0)
	A.finish(self)
	assert_false(host().regions.roll_encounter(s()), "flag used up")
	ws.options["encounters_enabled"] = true
	# battle_monster：目前房間開一場 FIGHT
	r = dbg.call("apply", host(), s(), "battle_monster", "m_rabbit")
	assert_true(r.get("ok", false))
	assert_eq(str(A.battle_entry(self).get("kind", "")), "FIGHT")
	A.finish(self)
	assert_eq(str(dbg.call("apply", host(), s(), "battle_monster", "m_nope").get("reason", "")), "bad_value:value")
