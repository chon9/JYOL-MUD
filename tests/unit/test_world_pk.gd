extends "res://tests/unit/test_pk_world_base.gd"
## WP-PK 整合（M2_PLAN 6.1）：叫戰、強制 PK、PK 模式、PK值／殺氣／善惡、pk_kill、守衛、系統開關、房間視圖標記。
## 走完整 intent 路徑（多個假遠端 session，WP-HOST 4.6.10）；PvP 戰鬥由 WP-PARTY 的 start_pvp 開。

func before_each() -> void:
	world_name = "w_pk"
	super.before_each()

func _pair(room := "xw_road") -> Array:
	var a := add("甲俠")
	var b := add("乙俠")
	goto_p(a, room)
	goto_p(b, room)
	return [a, b]

# ================================================================== 叫戰
func test_challenge_reason_order() -> void:
	if not deps_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	ws.options["pk_mode"] = "OFF"
	assert_eq(reason_p(a, "challenge", { "target": cid(b) }), "pk_disabled")
	ws.options["pk_mode"] = "CLASSIC"
	assert_eq(reason_p(a, "challenge", { "target": cid(a) }), "bad_target")
	assert_eq(reason_p(a, "challenge", { "target": "ch_nobody00" }), "target_not_here")
	goto_p(b, "xw_grass")
	assert_eq(reason_p(a, "challenge", { "target": cid(b) }), "target_not_here", "other room")
	goto_p(a, "xx_square")
	goto_p(b, "xx_square")
	assert_eq(reason_p(a, "challenge", { "target": cid(b) }), "pk_not_allowed_here", "city: pk_allowed false")
	goto_p(a, "xw_road")
	goto_p(b, "xw_road")
	host().battles.start(sess(b), ["m_rabbit"], "ENCOUNTER")
	ws.flush()
	assert_eq(reason_p(a, "challenge", { "target": cid(b) }), "target_busy")
	host().battles.abort_all()
	ws.flush()
	if host().get("party") != null and ws.has_intent_handler("party_invite"):
		ok_p(a, "party_invite", { "target": cid(b) })
		ok_p(b, "party_reply", { "from": cid(a), "accept": true })
		assert_eq(reason_p(a, "challenge", { "target": cid(b) }), "target_in_party")
		ok_p(b, "party_leave")
	ok_p(a, "challenge", { "target": cid(b) })
	assert_eq(reason_p(a, "challenge", { "target": cid(b) }), "challenge_pending")
	var c := add("丙俠")
	goto_p(c, "xw_road")
	ok_p(c, "set_pref", { "key": "accept_challenge", "value": false })
	assert_eq(reason_p(a, "challenge", { "target": cid(c) }), "challenge_refused")
	assert_true(evs_p(c, "challenge_request").is_empty(), "refused silently")

func test_challenge_events_sheet_and_decline() -> void:
	if not deps_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	ok_p(a, "challenge", { "target": cid(b) })
	assert_eq(lastp_p(a, "challenge_sent").get("name", ""), "乙俠")
	var req := lastp_p(b, "challenge_request")
	assert_eq(req.get("name", ""), "甲俠")
	assert_eq(req.get("from_char", ""), cid(a))
	assert_eq(int(req.get("ttl", 0)), int(ws.options.get("pending_ttl_real_s", 60)))
	settle()
	var pend: Array = sheet_p(b).get("pending", {}).get("challenges", [])
	assert_eq(pend.size(), 1, "sheet.pending.challenges")
	if pend.size() == 1:
		assert_eq(pend[0].get("from_char", ""), cid(a))
		assert_true(int(pend[0].get("left_s", 0)) > 0)
	ok_p(b, "challenge_reply", { "from": cid(a), "accept": false })
	assert_eq(lastp_p(a, "challenge_declined").get("name", ""), "乙俠")
	settle()
	assert_eq(sheet_p(b).get("pending", {}).get("challenges", []).size(), 0)
	assert_eq(reason_p(b, "challenge_reply", { "from": cid(a), "accept": true }), "no_challenge")

func test_challenge_expires_in_real_seconds() -> void:
	if not deps_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	ok_p(a, "challenge", { "target": cid(b) })
	var ttl := float(ws.options.get("pending_ttl_real_s", 60))
	var scale := float(ws.time_scale)
	ws.advance(ttl * scale - 2.0)
	assert_true(evs_p(a, "challenge_expired").is_empty(), "not yet")
	ws.advance(3.0)
	assert_eq(evs_p(a, "challenge_expired").size(), 1)
	assert_eq(reason_p(b, "challenge_reply", { "from": cid(a), "accept": true }), "no_challenge")

func test_challenge_accept_opens_pvp_and_kill_gives_no_pk() -> void:
	if not deps_ok(true):
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	var watcher := add("看客")
	goto_p(watcher, "xx_square")
	make_strong_p(a)
	make_weak_p(b)
	ok_p(a, "challenge", { "target": cid(b) })
	ok_p(b, "challenge_reply", { "from": cid(a), "accept": true })
	assert_eq(str(bopen_p(a).get("kind", "")), "CHALLENGE")
	assert_eq(int(bopen_p(a).get("my_side", -1)), 0)
	assert_eq(int(bopen_p(b).get("my_side", -1)), 1, "challenged player is side 1")
	assert_false(lastp_p(a, "challenge_start").is_empty(), "challenge_start to room")
	assert_false(lastp_p(b, "challenge_start").is_empty())
	var bid := sess(a).battle_id
	assert_true(bid != 0 and bid == sess(b).battle_id, "same battle")
	drive_bid(bid, { a: "fight", b: "defend" })
	assert_eq(int(chr(a).pk_value()), 0, "challenge kill: no PK")
	assert_eq(int(chr(a).killing_intent), 100, "+100 killing intent")
	assert_eq(int(chr(a).morality), 0, "challenge: morality unchanged")
	assert_false(lastp_p(a, "pk_kill").is_empty(), "pk_kill to the killer")
	assert_false(lastp_p(b, "pk_kill").is_empty(), "pk_kill to the victim")
	assert_true(lastp_p(watcher, "pk_kill").is_empty(), "challenge kill is not broadcast to everyone (M2 review)")

# ================================================================== 強制 PK
func test_force_pk_reason_order_and_modes() -> void:
	if not deps_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	ws.options["pk_mode"] = "OFF"
	assert_eq(reason_p(a, "force_pk", { "target": cid(b) }), "pk_disabled")
	ws.options["pk_mode"] = "CHALLENGE_ONLY"
	assert_eq(reason_p(a, "force_pk", { "target": cid(b) }), "pk_challenge_only")
	ws.options["pk_mode"] = "CLASSIC"
	assert_eq(reason_p(a, "force_pk", { "target": cid(a) }), "bad_target")
	assert_eq(reason_p(a, "force_pk", { "target": "ch_nobody00" }), "target_not_here")
	goto_p(a, "xx_gate_e")
	goto_p(b, "xx_gate_e")
	assert_eq(reason_p(a, "force_pk", { "target": cid(b) }), "pk_not_allowed_here")
	goto_p(a, "xw_road")
	goto_p(b, "xw_road")
	host().battles.start(sess(b), ["m_rabbit"], "ENCOUNTER")
	assert_eq(reason_p(a, "force_pk", { "target": cid(b) }), "target_busy")
	host().battles.abort_all()
	ws.flush()
	chr(b).combat_xp = 100
	ws.options["newbie_pk_protect_xp"] = 500
	assert_eq(reason_p(a, "force_pk", { "target": cid(b) }), "target_newbie_protected")
	host().regions.mark_room_dirty("xw_road")
	settle()
	assert_true(bool(view_p(a).get("players", []).filter(func(x): return x.get("char_id", "") == cid(b))
		.map(func(x): return x.get("newbie", false)).has(true)), "view marks newbie")

func test_force_pk_kill_effects() -> void:
	if not deps_ok(true):
		return
	use_preset("classic_strict")
	ws.options["newbie_pk_protect_xp"] = 0
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	var watcher := add("旁觀")
	goto_p(watcher, "xx_square")
	make_strong_p(a)
	make_weak_p(b)
	ok_p(a, "force_pk", { "target": cid(b) })
	assert_eq(str(bopen_p(a).get("kind", "")), "FORCED")
	assert_eq(int(bopen_p(b).get("my_side", -1)), 1)
	assert_false(lastp_p(b, "force_pk_start").is_empty())
	drive_bid(sess(a).battle_id, { a: "fight", b: "defend" })
	settle()
	assert_eq(int(chr(a).pk_value()), 1, "PK value 1")
	assert_eq(int(sheet_p(a).get("pk", -1)), 1, "sheet PK value 1")
	assert_eq(int(chr(a).killing_intent), 100)
	assert_eq(int(chr(a).morality), -10, "forced kill of non-evil")
	assert_eq(int(lastp_p(a, "pk_value_up").get("pk", 0)), 1)
	assert_eq(int(lastp_p(a, "morality_change").get("delta", 0)), -10)
	assert_eq(int(lastp_p(a, "killing_intent_change").get("delta", 0)), 100)
	for who in [a, b, watcher]:
		var k := lastp_p(who, "pk_kill")
		assert_eq(str(k.get("atk_name", "")), "甲俠", "pk_kill to peer %d" % who)
		assert_eq(str(k.get("def_name", "")), "乙俠")
	assert_true(bool(sess(b).character.dead_count >= 1), "victim died")
	# 死者的屍體在 xw_road（classic_strict 一律留屍體）
	var found := false
	for c in ws.world.get("corpses", []):
		if str(c.get("char_id", "")) == cid(b) and str(c.get("room", "")) == "xw_road":
			found = true
	assert_true(found, "victim corpse at the PK spot")

## M2 第三輪審查：被強制 PK 的人反殺出手者是自衛，不是惡意 PK——PK值不加、善惡不變、不廣播全服、不會被通緝
func test_force_pk_victim_counter_kill_is_self_defence() -> void:
	if not deps_ok(true):
		return
	use_preset("classic_strict")
	ws.options["newbie_pk_protect_xp"] = 0
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	var watcher := add("旁觀")
	goto_p(watcher, "xx_square")
	make_weak_p(a)
	make_strong_p(b)
	ok_p(a, "force_pk", { "target": cid(b) })
	assert_eq(int(bopen_p(a).get("my_side", -1)), 0, "attacker side 0")
	drive_bid(sess(a).battle_id, { a: "defend", b: "fight" })
	settle()
	assert_true(int(chr(a).dead_count) >= 1, "attacker died")
	assert_eq(int(chr(b).pk_value()), 0, "defender: no PK value")
	assert_eq(int(chr(b).morality), 0, "defender: morality unchanged")
	assert_eq(int(chr(b).killing_intent), 100, "defender: killing intent like a challenge kill")
	assert_true(lastp_p(b, "pk_value_up").is_empty(), "no pk_value_up")
	assert_true(lastp_p(b, "morality_change").is_empty(), "no morality_change")
	assert_false(lastp_p(a, "pk_kill").is_empty(), "the two parties still learn of the kill")
	assert_false(lastp_p(b, "pk_kill").is_empty())
	assert_true(lastp_p(watcher, "pk_kill").is_empty(), "self-defence kill is not broadcast")
	assert_eq(MoralityPk.guard_count(int(chr(b).pk_value()), int(chr(b).morality)), 0, "defender not wanted by guards")

## M2 第三輪審查：PvP 戰鬥事件不能洩漏敵方玩家的內力（battle_rest 的 neili／neili_gain）
func test_pvp_events_do_not_leak_enemy_neili() -> void:
	if not deps_ok(true):
		return
	ws.options["newbie_pk_protect_xp"] = 0
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	chr(b).vitals["neili"] = 0
	ok_p(a, "force_pk", { "target": cid(b) })
	var bid := sess(a).battle_id
	drive_for(bid, { a: "defend", b: "rest" }, 60.0)
	var mine := evs_p(b, "battle_rest")
	var seen := evs_p(a, "battle_rest")
	assert_false(mine.is_empty(), "the resting player gets battle_rest")
	assert_false(seen.is_empty(), "the enemy still sees that he rested")
	if not mine.is_empty():
		assert_true((mine[0].get("p", {}) as Dictionary).has("neili"), "own event keeps neili")
	for e in seen:
		var ep: Dictionary = e.get("p", {})
		assert_false(ep.has("neili") or ep.has("neili_gain"), "enemy's battle_rest has no neili: %s" % str(ep))
		assert_true(ep.has("qi_gain"), "public fields stay")
	host().battles.abort_all()
	ws.flush()

## M2 第三輪審查：戰鬥中最後一個真人斷線、當場結算死亡（位置改到重生點）——「離開了」要送到戰場房間，不是重生點
func test_disconnect_mid_battle_announces_leaving_the_battle_room() -> void:
	if not deps_ok(true):
		return
	use_preset("classic_strict")
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	var dest: String = host().respawn_room(chr(a))
	assert_true(dest != "xw_road", "respawn room differs from the battle room")
	var watcher := add("重生點客")
	goto_p(watcher, dest)
	make_weak_p(a)
	host().battles.start(sess(a), ["m_city_guard"], "ENCOUNTER")
	ws.flush()
	assert_true(sess(a).battle_id != 0, "a in battle")
	var an := str(chr(a).name)
	call("drop_player", a)
	settle()
	var at_battle := evs_p(b, "char_left").filter(func(e): return str(e.get("p", {}).get("name", "")) == an)
	var at_respawn := evs_p(watcher, "char_left").filter(func(e): return str(e.get("p", {}).get("name", "")) == an)
	assert_eq(at_battle.size(), 1, "battle room hears that he left")
	assert_eq(at_respawn.size(), 0, "respawn room hears nothing")

func test_effective_kill_kind() -> void:
	assert_eq(PkSystem.effective_kill_kind("FORCED", 0), "FORCED")
	assert_eq(PkSystem.effective_kill_kind("FORCED", 1), "CHALLENGE")
	assert_eq(PkSystem.effective_kill_kind("CHALLENGE", 0), "CHALLENGE")
	assert_eq(PkSystem.effective_kill_kind("CHALLENGE", 1), "CHALLENGE")

func test_pk_value_decays_with_online_time() -> void:
	if not deps_ok():
		return
	var a := add("甲俠")
	var c = chr(a)
	c.add_pk(2)
	sess(a).sheet_dirty = true
	host().flush_session(sess(a), true)
	ws.flush()
	assert_eq(int(sheet_p(a).get("pk", -1)), 2)
	ws.advance(1800.5)
	sess(a).sheet_dirty = true
	host().flush_session(sess(a), true)
	ws.flush()
	assert_eq(int(c.pk_value()), 1, "1800 s online -> -1")
	assert_eq(int(sheet_p(a).get("pk", -1)), 1, "sheet shows current value")

# ================================================================== 守衛
func test_guards_attack_wanted_and_evil() -> void:
	if not deps_ok():
		return
	var a := add("惡徒")
	goto_p(a, "xx_gate_e")
	chr(a).pk = 4
	chr(a).pk_stamp_s = chr(a).online_s
	ok_p(a, "move", { "dir": "E" })
	assert_eq(active_kind(a), "GUARD", "pk 4 leaving the city")
	assert_eq(int(lastp_p(a, "guard_attack").get("n", 0)), 2)
	var st := bopen_p(a)
	var guards := 0
	for u in st.get("units", []):
		if int(u.get("side", 0)) == 1:
			guards += 1
	assert_eq(guards, 2, "two guards in the battle")
	host().battles.abort_all()
	ws.flush()
	var b := add("小惡")
	goto_p(b, "xw_road")
	chr(b).morality = -1
	chr(b).combat_xp = 1000   # M3c 審查：新手（實戰 < 500）善惡負不被追殺；這裡測的是一般玩家
	ok_p(b, "move", { "dir": "W" })
	assert_eq(active_kind(b), "GUARD", "morality -1 entering the city")
	assert_eq(int(lastp_p(b, "guard_attack").get("n", 0)), 1)

func test_guards_not_triggered() -> void:
	if not deps_ok():
		return
	var a := add("良民")
	goto_p(a, "xx_square")
	chr(a).pk = 4
	chr(a).pk_stamp_s = chr(a).online_s
	ok_p(a, "move", { "dir": "E" })    # xx_square → xx_gate_e：城內移動
	assert_true(active_kind(a) != "GUARD", "moving inside the city")
	host().battles.abort_all()
	ws.flush()
	ws.options["guards_enabled"] = false
	goto_p(a, "xx_gate_e")
	send_p(a, "move", { "dir": "E" })
	assert_true(active_kind(a) != "GUARD", "guards disabled")
	assert_true(evs_p(a, "guard_attack").is_empty())

## M2 第三輪審查：驛站馬車也要跑移動鉤子——通緝犯搭車進出城照樣遇官兵；隊友的隊伍面板更新位置
func test_stagecoach_runs_guard_and_party_hooks() -> void:
	if not deps_ok():
		return
	host().options["stagecoach_enabled"] = true
	var a := add("搭車客")
	var b := add("同伴")
	goto_p(a, "xx_station")
	goto_p(b, "xx_station")
	if host().get("party") != null and ws.has_intent_handler("party_invite"):
		ok_p(a, "party_invite", { "target": cid(b) })
		ok_p(b, "party_reply", { "from": cid(a), "accept": true })
		settle()
	chr(a).money = 1000
	chr(a).pk = 4
	chr(a).pk_stamp_s = chr(a).online_s
	ok_p(a, "travel", { "npc": "n_xx_station", "dest": "dl_station" })
	assert_eq(str(chr(a).location["room"]), "dl_station")
	assert_eq(active_kind(a), "GUARD", "wanted player meets the guards when the coach enters/leaves a city")
	host().battles.abort_all()
	settle()
	if host().get("party") != null and ws.has_intent_handler("party_invite"):
		var mine: Dictionary = {}
		for m in sheet_p(b).get("party", {}).get("members", []):
			if str(m.get("char_id", "")) == cid(a):
				mine = m
		assert_eq(str(mine.get("room_name", "")), host().room_name("dl_station"), "teammate's party panel shows the new room")

## M2 第三輪審查：組隊邀請被拒後也要冷卻（不能連發洗提示）
func test_party_invite_retry_cooldown() -> void:
	if not deps_ok():
		return
	if host().get("party") == null or not ws.has_intent_handler("party_invite"):
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	ok_p(a, "party_invite", { "target": cid(b) })
	ok_p(b, "party_reply", { "from": cid(a), "accept": false })
	assert_eq(reason_p(a, "party_invite", { "target": cid(b) }), "invite_cooldown", "right after a refusal")
	ws.advance(float(ws.options.get("pending_retry_cooldown_real_s", 10)) * float(ws.time_scale) + 1.0)
	ok_p(a, "party_invite", { "target": cid(b) })
	ok_p(b, "party_reply", { "from": cid(a), "accept": true })

# ================================================================== 開關與視圖
func test_set_pref_and_sheet() -> void:
	if not deps_ok():
		return
	var a := add("甲俠")
	ok_p(a, "set_pref", { "key": "accept_challenge", "value": false })
	assert_eq(sheet_p(a).get("prefs", {}).get("accept_challenge", true), false)
	assert_eq(str(lastp_p(a, "pref_changed").get("label", "")), "接受叫戰")
	assert_eq(str(lastp_p(a, "pref_changed").get("state", "")), "關")
	ok_p(a, "set_pref", { "key": "accept_party", "value": false })
	assert_eq(sheet_p(a).get("prefs", {}).get("accept_party", true), false)
	assert_eq(reason_p(a, "set_pref", { "key": "nope", "value": true }), "bad_value:key")

func test_view_player_tags_and_align() -> void:
	if not deps_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	chr(b).morality = -300
	host().regions.mark_room_dirty("xw_road")
	sess(b).sheet_dirty = true
	host().flush_session(sess(a), true)
	host().flush_session(sess(b), true)
	ws.flush()
	var tag := {}
	for x in view_p(a).get("players", []):
		if str(x.get("char_id", "")) == cid(b):
			tag = x
	assert_eq(str(tag.get("align", "")), "EVIL")
	assert_true(tag.has("newbie"))
	assert_eq(str(sheet_p(b).get("align", "")), "EVIL", "sheet align")
	assert_eq(view_p(a).get("pk_allowed", false), true, "xw_road allows PK")

func test_leaving_drops_challenges() -> void:
	if not deps_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	ok_p(a, "challenge", { "target": cid(b) })
	if has_method("drop_player"):
		call("drop_player", a)
		assert_eq(host().pk.pending_for(sess(b)).size(), 0, "challenger left")
