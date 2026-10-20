extends "res://tests/unit/test_world_fixture.gd"
## WP-NPCPK（M3C_PLAN §5.3、§12.1）：npc_attack 的驗證順序與全部原因碼；npc_busy 附 battle_id；KILL 後消失（view 不列、
## npc_here 不在）、到時重生；CHALLENGE 不消失；善惡殺氣每殺一個只算一次（怪物列給的 vs 本系統補的 GUARD）；
## 兩名玩家先後攻擊同一 NPC；城內守衛（§5.5）：殺居民 1 名、殺守衛 2 名、城外不觸發、guards_enabled 關不觸發；
## 房間 view 的 npcs[].atk 與 npc_menu.attack 形狀；孫婆婆每次都是 6 人（第二輪審查拿掉 group_repeat；引擎的 group_repeat 用改過的資料列測）。
## 本檔另提供其他 M3c NPC 測試共用的靜態輔助（win／lose：直接用 BattleRules.kill 結束戰鬥，不靠擲骰）。

# ---------------------------------------------------------------- 共用輔助（static：其他測試檔以 preload 呼叫）
static func battle_entry(t, peer := 1) -> Dictionary:
	var sess: Session = t.ws.sessions.get(peer)
	if sess == null or sess.battle_id == 0:
		return {}
	return t.host().battles.active.get(sess.battle_id, {})

static func unit_of(b: Battle, peer: int) -> BattleUnit:
	for u in b.units:
		if u.is_player() and int(u.peer) == peer:
			return u
	return null

## 結束 peer 目前的戰鬥：win＝把對方全部打倒（擊殺者是自己）；否則自己倒下
static func finish(t, peer := 1, win := true) -> void:
	var sess: Session = t.ws.sessions.get(peer)
	var entry := battle_entry(t, peer)
	if entry.is_empty():
		return
	var b: Battle = entry["battle"]
	var me := unit_of(b, peer)
	if win:
		for u in b.units:
			if u.side != me.side and u.is_active():
				BattleRules.kill(b, u, me)
	else:
		var foe: BattleUnit = null
		for u in b.units:
			if u.side != me.side and u.is_active():
				foe = u
		BattleRules.kill(b, me, foe)
	b._check_end(t.host().tables)   # 結果只在有人行動後才判定：直接判一次
	var n := 0
	while sess.battle_id == int(b.id) and n < 100:
		t.ws.advance(0.1)
		n += 1

static func npc_ids_in_view(v: Dictionary) -> Array:
	var out: Array = []
	for n in v.get("npcs", []):
		out.append(str(n.get("id", "")))
	return out

static func npc_entry(v: Dictionary, nid: String) -> Dictionary:
	for n in v.get("npcs", []):
		if str(n.get("id", "")) == nid:
			return n
	return {}

static func advance_shichen(t, n: float) -> void:
	var span := WorldClock.shichen_len(t.host().day_s()) * n
	t.ws.world["world_time_s"] = t.ws.world_time() + span + 1.0
	t.host()._minute_jobs()
	t.ws.flush()

# ---------------------------------------------------------------- 場景
func _setup(city := "dali", room := "dl_square") -> bool:
	if not game_ok():
		return false
	ws.options["sect_hostile_entry"] = false
	if make_char("動手俠客", city) == null:
		return false
	make_strong()
	# M3c 第二輪審查：新手（實戰 < newbie_pk_protect_xp）在預設規則下不招官兵（newbie_guard_spare）；這些測試要的是老手
	ch().combat_xp = 5000
	goto(room)
	clear_events()
	return true

func _attack(nid: String, mode := "") -> Dictionary:
	var args := { "npc": nid }
	if mode != "":
		args["mode"] = mode
	return send("npc_attack", args)

func _system():
	return host().get("npcpk")

# ---------------------------------------------------------------- 驗證順序
func test_system_loaded() -> void:
	if not game_ok():
		return
	assert_true(_system() != null, "GameHost.npcpk loaded (M3C_SYSTEMS)")
	assert_true(Protocol.is_known("npc_attack"))

func test_reason_codes_in_order() -> void:
	if not _setup():
		return
	# 1. 規則關
	GameData.rules["npc_attack"] = false
	assert_eq(str(_attack("n_na_dl_xiaohai").get("reason", "")), "npc_attack_off")
	GameData.rules["npc_attack"] = true
	# 2. 不在這間
	assert_eq(str(_attack("n_xx_guard").get("reason", "")), "not_here")
	# 3. 受保護／via 不允許
	assert_eq(str(_attack("n_lj_baiyong").get("reason", "")), "npc_not_attackable", "quest NPC has no attack")
	assert_eq(str(_attack("n_dl_cunmin", "MIEPAI").get("reason", "")), "npc_not_attackable", "CTRL-only NPC via menu")
	# 4. 安全的房間
	var room: Dictionary = host().index.room("dl_square")
	room["safe"] = true
	assert_eq(str(_attack("n_na_dl_xiaohai").get("reason", "")), "npc_safe_room")
	room.erase("safe")
	# 5. 坐牢（SectSystem.jail_gate 先擋）
	ch().jail = { "sect": "wudang", "room": "wd_siguo", "until_online_s": ch().online_s + 9999.0, "reason": "BREACH",
		"rule": "", "days": 1, "notified": true, "scope": "SECT" }
	assert_eq(str(_attack("n_na_dl_xiaohai").get("reason", "")), "jailed")
	ch().jail = {}
	# 參數
	assert_eq(str(_attack("n_na_dl_xiaohai", "KILL").get("reason", "")), "bad_value:mode")
	# 7. requires（滅派要不是本派）：在武當山門的武當弟子
	goto("wd_gate")
	ch().sect = "wudang"
	assert_eq(str(_attack("n_wd_zhike", "MIEPAI").get("reason", "")), "req_sect_not")
	assert_eq(str(_attack("n_wd_zhike").get("reason", "")), "npc_not_attackable", "滅派 NPC is menu-only")
	ch().sect = ""
	# 戰鬥中（IDLE 旗標）
	goto("dl_square")
	start_battle(["m_rabbit"])
	assert_eq(str(_attack("n_na_dl_xiaohai").get("reason", "")), "in_battle")
	finish(self)

func test_view_entry_and_menu_shapes() -> void:
	if not _setup():
		return
	host().flush_session(s(), true)
	ws.flush()
	var v := view()
	var kid := npc_entry(v, "n_na_dl_xiaohai")
	assert_false(kid.is_empty(), "new NPC placed in dl_square")
	var a: Variant = kid.get("atk", null)
	assert_true(a is Dictionary, "atk on attackable NPC")
	for k in ["mode", "category", "align", "sect", "menu_label", "warn"]:
		assert_true((a as Dictionary).has(k), "atk." + k)
	assert_eq(str(a["mode"]), "KILL")
	assert_eq(str(a["category"]), "CHILD")
	assert_eq(str(a["align"]), "GOOD")
	assert_true(str(a["warn"]).contains("善惡"), "warn mentions morality")
	assert_true(npc_entry(v, "n_lj_baiyong").has("atk") and npc_entry(v, "n_lj_baiyong")["atk"] == null, "protected → null")
	# npc_menu.attack：只有 via 含 MENU 的 NPC
	var m0: Dictionary = host().npcs.menu(s(), "n_na_dl_xiaohai")
	assert_eq(m0.get("attack", null), {}, "CTRL-only → {}")
	goto("wd_gate")
	var m1: Dictionary = host().npcs.menu(s(), "n_wd_zhike")
	assert_eq(str(m1["attack"].get("label", "")), "滅派")
	assert_eq(m1["attack"].get("ok", false), true, "no-sect char may 滅派")
	assert_true(str(m1["attack"].get("warn", "")).contains("公敵"))
	ch().sect = "wudang"
	var m2: Dictionary = host().npcs.menu(s(), "n_wd_zhike")
	assert_eq(m2["attack"].get("ok", true), false)
	assert_eq(str(m2["attack"].get("reason", "")), "req_sect_not")
	ch().sect = ""
	# 規則關：view 不給 atk
	GameData.rules["npc_attack"] = false
	assert_eq(_system().view_entry(s(), "n_wd_beizhong"), null)
	GameData.rules["npc_attack"] = true

# ---------------------------------------------------------------- KILL：消失、重生、善惡一次、守衛
func test_kill_child_disappears_guard_and_respawns() -> void:
	if not _setup():
		return
	var mo0 := int(ch().morality)
	var ki0 := int(ch().killing_intent)
	var r := ok("npc_attack", { "npc": "n_na_dl_xiaohai" })
	assert_true(int(r.get("battle_id", 0)) > 0, "battle_id returned")
	assert_false(evs("na_attack_start").is_empty())
	var entry := battle_entry(self)
	assert_eq(str(entry.get("kind", "")), "NPC_ATTACK")
	var main: BattleUnit = null
	for u in (entry["battle"] as Battle).units:
		if str(u.spec.get("npc", "")) == "n_na_dl_xiaohai":
			main = u
	assert_true(main != null, "main unit tagged with npc")
	assert_eq(str(main.spec.get("ref", "")), "n_na_dl_xiaohai", "ref = npc id (portrait)")
	assert_eq(str(main.spec.get("monster_row", "")), "m_npc_child", "monster_row = attack.monster")
	assert_eq(main.unit_name(), "小孩")
	finish(self)
	assert_eq(int(ch().morality) - mo0, -20, "child: morality −20 once")
	assert_eq(int(ch().killing_intent) - ki0, 20, "child: killing intent +20 once")
	assert_false(evs("na_npc_killed").is_empty())
	assert_false(evs("morality_change").is_empty())
	# 城內殺善方 → 1 名守城官兵（GUARD 戰）
	assert_false(evs("na_guard_alarm").is_empty(), "guard alarm in Dali")
	var g := battle_entry(self)
	assert_eq(str(g.get("kind", "")), "GUARD")
	var guards := 0
	for u in (g["battle"] as Battle).units:
		if not u.is_player():
			guards += 1
	assert_eq(guards, 1)
	finish(self)
	# 消失：npc_here、view、talk
	assert_true(_system().npc_down("n_na_dl_xiaohai"))
	assert_eq(host().npc_here(s(), "n_na_dl_xiaohai"), "not_here")
	host().flush_session(s(), true)
	ws.flush()
	assert_false("n_na_dl_xiaohai" in npc_ids_in_view(view()), "dead child not listed")
	assert_eq(reason("talk", { "npc": "n_na_dl_xiaohai" }), "not_here")
	assert_eq(reason("npc_attack", { "npc": "n_na_dl_xiaohai" }), "not_here")
	var down: Dictionary = ws.world.get("npc_down", {})
	assert_eq(str(down["n_na_dl_xiaohai"].get("by", "")), str(ch().id))
	# 3 時辰後重生
	clear_events()
	advance_shichen(self, 1.0)
	assert_true(_system().npc_down("n_na_dl_xiaohai"), "still down after 1 shichen")
	advance_shichen(self, 2.0)
	assert_false(_system().npc_down("n_na_dl_xiaohai"), "back after 3 shichen")
	assert_false(evs("na_npc_back").is_empty(), "room told na_npc_back")
	host().flush_session(s(), true)
	ws.flush()
	assert_true("n_na_dl_xiaohai" in npc_ids_in_view(view()), "listed again")

func test_challenge_npc_never_disappears() -> void:
	if not _setup():
		return
	var mo0 := int(ch().morality)
	ok("npc_attack", { "npc": "n_dl_cunmin" })
	finish(self)
	assert_eq(int(ch().morality) - mo0, -10, "civilian −10")
	assert_false(evs("na_npc_routed").is_empty())
	assert_true(evs("na_npc_killed").is_empty())
	assert_false(_system().npc_down("n_dl_cunmin"))
	assert_eq(host().npc_here(s(), "n_dl_cunmin"), "")
	finish(self)   # 守衛戰
	assert_true(send("talk", { "npc": "n_dl_cunmin" }).get("ok", false), "still talkable")

func test_lost_fight_changes_nothing() -> void:
	if not _setup("dali", "dl_wuguan"):
		return
	var mo0 := int(ch().morality)
	ok("npc_attack", { "npc": "n_dl_wushi" })
	finish(self, 1, false)
	assert_eq(int(ch().morality), mo0, "lost: no morality")
	assert_false(_system().npc_down("n_dl_wushi"))
	assert_true(evs("na_guard_alarm").is_empty(), "no guards when the player loses")
	goto("dl_wuguan")
	assert_true(send("learn_list", { "npc": "n_dl_wushi" }).get("ok", false), "wushi still teaches")

func test_guard_kill_system_deltas_and_two_guards() -> void:
	if not _setup("xixia", "xx_gate_e"):
		return
	var mo0 := int(ch().morality)
	var ki0 := int(ch().killing_intent)
	ok("npc_attack", { "npc": "n_xx_guard" })
	var units: Array = (battle_entry(self)["battle"] as Battle).units.filter(func(u): return not u.is_player())
	assert_eq(units.size(), 2, "guard ×2")
	finish(self)
	# m_city_guard 沒有給善惡（no_rewards）→ 本系統依 GUARD 類別補 −5／+10，只算一次
	assert_eq(int(ch().morality) - mo0, -5)
	assert_eq(int(ch().killing_intent) - ki0, 10)
	assert_true(_system().npc_down("n_xx_guard"))
	var g := battle_entry(self)
	assert_eq(str(g.get("kind", "")), "GUARD")
	assert_eq((g["battle"] as Battle).units.filter(func(u): return not u.is_player()).size(), 2, "killing a guard → 2 guards")
	finish(self)

func test_no_guards_outside_city_or_when_disabled() -> void:
	if not _setup("xixia", "xw_grass"):
		return
	ok("npc_attack", { "npc": "n_na_xw_yang" })
	finish(self)
	assert_true(evs("na_guard_alarm").is_empty(), "wild: no guards")
	assert_eq(s().battle_id, 0)
	ws.options["guards_enabled"] = false
	goto("xx_minfang")
	clear_events()
	ok("npc_attack", { "npc": "n_na_xx_jumin" })
	finish(self)
	assert_true(evs("na_guard_alarm").is_empty(), "guards_enabled false")
	assert_eq(s().battle_id, 0)
	ws.options["guards_enabled"] = true

func test_villain_raises_morality() -> void:
	if not _setup("xixia", "xx_street"):
		return
	ch().morality = 0
	ok("npc_attack", { "npc": "n_na_xx_eba" })
	finish(self)
	assert_eq(int(ch().morality), 10, "villain +10")
	assert_true(evs("na_guard_alarm").is_empty(), "no guards for villains")

# ---------------------------------------------------------------- 多人
func test_two_players_same_npc() -> void:
	if not _setup():
		return
	var b := add_player("後到者", "dali")
	goto_as(b, "dl_square")
	var r := ok("npc_attack", { "npc": "n_na_dl_xiaohai" })
	var bid := int(r.get("battle_id", 0))
	var rb := send_as(b, "npc_attack", { "npc": "n_na_dl_xiaohai" })
	assert_eq(str(rb.get("reason", "")), "npc_busy")
	assert_eq(int(rb.get("battle_id", 0)), bid, "npc_busy carries battle_id")
	finish(self)
	assert_eq(reason_as(b, "npc_attack", { "npc": "n_na_dl_xiaohai" }), "not_here", "already killed")
	# 鎖已解：同一位 CHALLENGE NPC 可以再打（B 先打）
	finish(self)   # A 的守衛戰
	var rc := send_as(b, "npc_attack", { "npc": "n_dl_cunmin" })
	assert_true(rc.get("ok", false), "B attacks civilian: %s" % str(rc))
	assert_eq(reason("npc_attack", { "npc": "n_dl_cunmin" }), "npc_busy")

## M3c 第二輪審查：2001 規則（動手＝古墓公敵，回到墓口就被執法弟子截殺）下走不到 2002 的「之後 4 個」→ 資料拿掉 group_repeat，
## 每次都是孫婆婆＋5；引擎仍支援 group_repeat（用暫時改過的資料列測）
func test_sunpopo_group_six_then_four() -> void:
	if not _setup("xixia", "gm_entrance"):
		return
	var row: Dictionary = host().npc_row("n_gm_sunpopo")
	assert_false((row.get("attack", {}) as Dictionary).has("group_repeat"), "孫婆婆沒有 group_repeat（2001 規則）")
	ok("npc_attack", { "npc": "n_gm_sunpopo", "mode": "MIEPAI" })
	var n1: int = (battle_entry(self)["battle"] as Battle).units.filter(func(u): return not u.is_player()).size()
	assert_eq(n1, 6, "first time: 孫婆婆 + 5")
	assert_true(ch().sect_enemies.has("gumu"), "滅派＝古墓公敵")
	finish(self)
	if s().battle_id != 0:
		finish(self)
	goto("gm_entrance")
	assert_eq(reason("npc_attack", { "npc": "n_gm_sunpopo", "mode": "MIEPAI" }), "npc_routed")
	advance_shichen(self, 3.2)
	ok("npc_attack", { "npc": "n_gm_sunpopo", "mode": "MIEPAI" })
	var n2: int = (battle_entry(self)["battle"] as Battle).units.filter(func(u): return not u.is_player()).size()
	assert_eq(n2, 6, "second time: still 孫婆婆 + 5")
	finish(self)
	if s().battle_id != 0:
		finish(self)
	# 引擎：有 group_repeat 的資料列 → 計次（_miepai_bump），第二次起改用那一組
	var a: Dictionary = (row["attack"] as Dictionary)
	a["group_repeat"] = [{ "monster": "m_npc_gm_dizi", "count": [3, 3] }]
	var counts: Array = []
	for i in 2:
		goto("gm_entrance")
		advance_shichen(self, 3.2)
		ok("npc_attack", { "npc": "n_gm_sunpopo", "mode": "MIEPAI" })
		counts.append((battle_entry(self)["battle"] as Battle).units.filter(func(u): return not u.is_player()).size())
		finish(self)
		if s().battle_id != 0:
			finish(self)
	a.erase("group_repeat")
	assert_eq(counts, [6, 4], "group_repeat: 6 the first counted time, then 孫婆婆 + 3")

func test_debug_respawn_now() -> void:
	if not _setup():
		return
	ok("npc_attack", { "npc": "n_na_dl_xiaohai" })
	finish(self)
	finish(self)
	assert_true(_system().npc_down("n_na_dl_xiaohai"))
	_system().respawn_now("*")
	assert_false(_system().npc_down("n_na_dl_xiaohai"))

# ---------------------------------------------------------------- M3c 審查（第一輪）回歸
## 組隊：A 邀 peer p 入隊
func _party_with(p: int) -> void:
	ok("party_invite", { "target": str(session_of(p).character.id) })
	assert_true(send_as(p, "party_reply", { "from": str(ch().id), "accept": true }).get("ok", false), "party_reply")

## CHALLENGE 打贏後，同一批人要等重生時間（3 時辰）才能再找他動手；沒參戰的人不受影響
func test_challenge_routed_cooldown() -> void:
	if not _setup():
		return
	var b := add_player("旁人", "dali")
	goto_as(b, "dl_square")
	ok("npc_attack", { "npc": "n_dl_cunmin" })
	finish(self)
	if s().battle_id != 0:
		finish(self)   # 城內守衛
	goto("dl_square")
	assert_true(_system().routed_left(ch(), "n_dl_cunmin") > 0.0)
	assert_eq(reason("npc_attack", { "npc": "n_dl_cunmin" }), "npc_routed", "cannot farm right away")
	assert_true(send_as(b, "npc_attack", { "npc": "n_dl_cunmin" }).get("ok", false), "someone else can still fight him")
	finish(self, b)
	if session_of(b).battle_id != 0:
		finish(self, b)
	advance_shichen(self, 3.2)
	goto("dl_square")
	assert_true(send("npc_attack", { "npc": "n_dl_cunmin" }).get("ok", false), "after the respawn time: ok again")
	finish(self)

## 非 no_rewards 列：最後一擊者打完已不在場（逃走）→ 戰鬥獎勵沒給他善惡；本系統要照怪物列補上（訊息與實際一致）
func test_killer_gone_still_gets_morality() -> void:
	if not _setup():
		return
	var b := add_player("同伴", "dali")
	goto_as(b, "dl_square")
	_party_with(b)
	var bid := int(ok("npc_attack", { "npc": "n_na_dl_xiaohai" }).get("battle_id", 0))
	assert_true(send_as(b, "battle_join", { "battle_id": bid }).get("ok", false), "B joins")
	var mo_a := int(ch().morality)
	var mo_b := int(session_of(b).character.morality)
	var entry := battle_entry(self)
	var bt: Battle = entry["battle"]
	var ua := unit_of(bt, 1)
	var npc_u: BattleUnit = null
	for u in bt.units:
		if not u.is_player():
			npc_u = u
	BattleRules.kill(bt, npc_u, ua)
	ua.state = BattleUnit.FLED   # A 得手後逃走
	bt._check_end(host().tables)
	var n := 0
	while session_of(b).battle_id == bid and n < 100:
		ws.advance(0.1)
		n += 1
	assert_eq(int(ch().morality) - mo_a, -20, "killer who left still pays −20 (and is told so)")
	assert_eq(int(session_of(b).character.morality), mo_b, "the survivor who did not kill pays nothing")
	if s().battle_id != 0:
		finish(self)

## 結束後的善惡、殺氣等一律存檔（以前線上的殺手只靠定時存檔，主機當掉就沒了）
func test_npc_kill_effects_saved_for_online_killer() -> void:
	if not _setup("xixia", "xx_gate_e"):
		return
	var g := ""
	for nid in ["n_xx_guard"]:
		if host().npc_here(s(), nid) == "":
			g = nid
	if g == "":
		return
	var mo0 := int(ch().morality)
	ok("npc_attack", { "npc": g })
	finish(self)
	assert_true(int(ch().morality) < mo0, "guard kill lowers morality (category fallback)")
	var saved = host().char_store.load_char(s().identity, str(ch().id))
	assert_eq(int(saved.morality), int(ch().morality), "saved right away")
	if s().battle_id != 0:
		finish(self)
