extends "res://tests/unit/test_world_fixture.gd"
## M2_PLAN 2.1「主機離線＝世界凍結」、4.8：restart_world() 後世界時間、屍體（含授權名單與剩餘時間）、信件（含已讀）、
## PK 基準與 stamp、任務、角色位置、禁止名單都在；隊伍消失；關服時進行中的戰鬥 ABORTED、不扣死亡

func _find_corpse(cid: String) -> Dictionary:
	for c in ws.world.get("corpses", []):
		if c is Dictionary and str(c.get("id", "")) == cid:
			return c
	return {}

func test_world_state_survives_restart() -> void:
	if not game_ok():
		return
	var a = make_char("持久甲")
	var a_id := str(a.id)
	goto("xx_square")
	ok("quest_accept", { "npc": "n_wujieshan", "quest": "q_rabbit" })
	goto("xx_inn")
	a.pk = 2
	if "pk_stamp_s" in a:
		a.set("pk_stamp_s", 42.0)
	a.morality = -30
	var b := add_player("持久乙")
	var b_ident := identity_of(b)
	var b_id := str(session_of(b).character.id)
	# 屍體：用乙的角色做一具，加上授權名單
	var uid := give("c_qiyao", 2) if tables().get("items", {}).has("c_qiyao") else ""
	var items: Array = []
	if uid != "":
		for it in a.inventory.items:
			if str(it.get("uid", "")) == uid:
				items.append(it.duplicate(true))
	var corpse_id: String = host().corpses.create(session_of(b).character, "xw_road", items)
	var corpse := _find_corpse(corpse_id)
	corpse["authorized"] = [a_id]
	corpse["public_notified"] = false
	var corpse_created := float(corpse["created_s"])
	# 信件：一封已讀、一封未讀（寄給離線也收得到，存在 world.json）
	ws.world["mail"] = [
		{ "id": "ml_aaaa0001", "to_char": b_id, "to_name": "持久乙", "from_char": a_id, "from_name": "持久甲",
			"text": "已讀的信", "sent_s": ws.world_time(), "read": true },
		{ "id": "ml_aaaa0002", "to_char": a_id, "to_name": "持久甲", "from_char": b_id, "from_name": "持久乙",
			"text": "未讀的信", "sent_s": ws.world_time(), "read": false },
	]
	# 禁止名單
	ws.world["known_identities"]["local_0000000000000000000000000000beef"] = { "banned": true, "last_name": "壞人" }
	ws.advance(30.0)
	var t_before: float = ws.world_time()
	var n_items := 0
	for it in corpse["items"]:
		n_items += int(it.get("n", 1))
	restart_world()
	# 世界時間不倒退（主機離線時不前進）
	assert_true(ws.world_time() >= t_before, "world time %f >= %f" % [ws.world_time(), t_before])
	assert_true(ws.world_time() < t_before + 5.0, "world frozen while host was down")
	# 屍體：同 id、同件數、授權名單、建立時間（剩餘時間不變）
	var c2 := _find_corpse(corpse_id)
	assert_false(c2.is_empty(), "corpse survives")
	if not c2.is_empty():
		var n2 := 0
		for it in c2["items"]:
			n2 += int(it.get("n", 1))
		assert_eq(n2, n_items, "corpse item count")
		assert_eq(c2.get("authorized", []), [a_id], "authorized list")
		assert_eq(c2.get("public_notified", null), false)
		assert_true(absf(float(c2["created_s"]) - corpse_created) < 0.001, "created_s kept → same time left")
		assert_eq(typeof(c2["created_s"]), TYPE_FLOAT)
	# 信件（含已讀）
	var mails: Array = ws.world.get("mail", [])
	assert_eq(mails.size(), 2, "mail kept")
	if mails.size() == 2:
		assert_eq(mails[0]["read"], true)
		assert_eq(mails[1]["read"], false)
		assert_eq(typeof(mails[0]["sent_s"]), TYPE_FLOAT)
		assert_eq(str(mails[1]["text"]), "未讀的信")
	# 禁止名單
	assert_eq(ws.validate_hello(777, { "protocol": Protocol.VERSION, "game_version": Protocol.GAME_VERSION,
		"content_hash": GameData.content_hash, "identity": "local_0000000000000000000000000000beef",
		"display_name": "x" }), "banned")
	# 角色：位置、PK 基準與 stamp、善惡、任務
	assert_eq(ch(), null, "nobody selected after restart")
	ok("char_select", { "char_id": a_id })
	assert_eq(s().room_id(), "xx_inn", "location kept")
	assert_eq(int(ch().pk), 2, "pk base kept")
	if "pk_stamp_s" in ch():
		assert_true(absf(float(ch().get("pk_stamp_s")) - 42.0) < 0.001, "pk_stamp_s kept")
	assert_eq(int(ch().morality), -30)
	assert_true(ch().quests.get("active", {}).has("q_rabbit"), "quest kept")
	# 隊伍不存檔：重開後一律沒有隊伍
	assert_eq(sheet().get("party", null), {}, "no party after restart")
	assert_eq(sheet().get("pending", {}).get("party_invite", null), {}, "no pending invite")
	assert_eq(sheet().get("pending", {}).get("challenges", null), [], "no pending challenge")
	# 舊 peer 都消失；乙重新連線後可以選回角色
	assert_false(ws.sessions.has(b), "old peers gone")
	var b2 := connect_player("持久乙", b_ident)
	assert_true(send_as(b2, "char_select", { "char_id": b_id }).get("ok", false), "remote reselects")

func test_battle_aborted_on_shutdown_without_death() -> void:
	if not game_ok():
		return
	var a = make_char("持久甲")
	goto("xw_grass")
	var a_id := str(a.id)
	var dead_before := int(a.dead_count)
	var corpses_before: int = ws.world.get("corpses", []).size()
	var xp_before := int(a.combat_xp)
	a.vitals["qi"] = 1   # 快死了：如果關服時照常結算就會死
	var bid := start_battle(["m_wolf"])
	assert_true(bid != 0, "battle started")
	assert_eq(s().battle_id, bid)
	restart_world()
	assert_eq(str(cs.last_battle_result.get("result", "")), "ABORTED", "battle aborted on shutdown")
	assert_eq(ws.world.get("corpses", []).size(), corpses_before, "no corpse from aborted battle")
	ok("char_select", { "char_id": a_id })
	assert_eq(int(ch().dead_count), dead_before, "no death penalty")
	assert_eq(int(ch().combat_xp), xp_before, "no rewards")
	assert_eq(s().battle_id, 0, "not in battle after restart")
	assert_eq(s().room_id(), "xw_grass", "still where the battle was")

func test_host_closing_broadcast_on_stop() -> void:
	if not game_ok():
		return
	make_char("持久甲")
	var b := add_player("持久乙")
	clear_events_for(b)
	clear_events()
	ws.stop()
	assert_eq(evs_for(b, "host_closing").size(), 1, "remote told before shutdown")
	assert_eq(evs("host_closing").size(), 1, "local told too")
	assert_true(cs.host_closing, "ClientState flag")
	assert_eq(ws.start(world_name), OK)
	cs.begin_local_session()

func test_coerce_world_fills_m2_fields() -> void:
	var d := { "schema_version": 1, "corpses": [{ "id": "cp_1", "created_s": 5 }], "known_identities": { "x": {} } }
	var out: Dictionary = sm._coerce_world(d)
	assert_eq(out["mail"], [])
	assert_eq(out["corpses"][0]["authorized"], [])
	assert_eq(out["corpses"][0]["public_notified"], false)
	assert_eq(typeof(out["corpses"][0]["created_s"]), TYPE_FLOAT)
	assert_eq(out["known_identities"]["x"]["banned"], false)
