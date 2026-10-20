extends "res://tests/unit/test_world_sect_fixture.gd"
## 思過處（M3A_PLAN 6.3、6.6）：違反門規押入、指令封鎖清單、頻道限制、走不出去、期滿出獄（公敵清除）、贖人、
## 公敵死亡被抓、坐牢中不踩地雷也不能偵察。

func before_each() -> void:
	world_name = "w_jail"
	super.before_each()

func _jailed_member():
	install_sect()
	var c = member("思過俠")
	var r := join_via_npc()
	assert_true(r.get("ok", false), "join: %s" % str(r))
	clear_events()
	c.killing_intent = 2500
	sects().check_state(s(), "TICK")
	ws.flush()
	return c

func test_breach_jails_member() -> void:
	if not game_ok():
		return
	var c = _jailed_member()
	assert_true(c.is_jailed(), "jailed")
	assert_eq(s().room_id(), JAIL, "押進思過處")
	var b := lastp(Protocol.E_SECT_BREACH)
	assert_eq(str(b.get("outcome", "")), "JAIL")
	assert_eq(int(b.get("days", 0)), 1)
	assert_eq(str(b.get("enforcer", "")), "測看守")
	var j := lastp(Protocol.E_JAIL_IN)
	assert_eq(int(j.get("days", 0)), 1)
	assert_eq(str(j.get("room_name", "")), "測派思過處")
	assert_true(float(c.jail_left_s()) > 7000.0, "刑期 1 遊戲日（上線秒）")
	assert_eq(str(c.jail.get("reason", "")), "BREACH")
	assert_eq(str(c.jail.get("rule", "")), "ts_r_killing")
	refresh_sheet()
	var js: Variant = sheet().get("jail")
	assert_true(js is Dictionary, "角色表 jail")
	assert_eq(str(js.get("room_name", "")), "測派思過處")
	# 只觸發一次：再檢查不會再押一次、也不會再送 sect_breach
	clear_events()
	sects().check_state(s(), "TICK")
	ws.flush()
	assert_eq(evs(Protocol.E_SECT_BREACH).size(), 0, "STATE 規則只在轉換時觸發")

func test_jailed_intent_gate() -> void:
	if not game_ok():
		return
	var c = _jailed_member()
	assert_true(c.is_jailed())
	assert_eq(reason("move", { "dir": "W" }), "jailed", "走不出去")
	assert_eq(reason("join_sect", { "npc": HEAD }), "jailed")
	assert_eq(reason("learn_list", { "npc": HEAD }), "jailed")
	assert_eq(reason("drop_item", { "item_uid": "x" }), "jailed")
	assert_eq(reason("quest_accept", { "npc": HEAD, "quest": "q" }), "jailed")
	ok("look")
	ok("talk", { "npc": JAILER })
	assert_eq(reason("talk", { "npc": HEAD }), "not_here", "talk 只限同房間")
	# 研究 jy1-2-5-4：坐牢不能練功、打坐、運功、換裝（M3a 審查 A8）；吃喝（use_item）是【設計提案】的放行
	assert_eq(reason("meditate", {}), "jailed")
	assert_eq(reason("exert", { "stat": "jing" }), "jailed")
	assert_eq(reason("self_study", { "skill": "basic_fist" }), "jailed")
	assert_eq(reason("unequip", { "slot": "WEAPON" }), "jailed")
	assert_ne_jailed("use_item", { "item_uid": "x" })
	assert_ne_jailed("mail_list", {})
	assert_ne_jailed("quest_abandon", { "quest": "q_none" })
	# 頻道：只留傳音入密、輕聲細語
	assert_eq(reason("chat", { "text": "放我出去", "ch": "CHAT_WORLD" }), "jailed")
	assert_eq(reason("chat", { "text": "放我出去", "ch": "CHAT_PARTY" }), "jailed")
	ok("chat", { "text": "好冷", "ch": "CHAT_SAY" })
	# 角色管理不受影響
	ok("char_list")

func assert_ne_jailed(kind: String, args: Dictionary) -> void:
	assert_true(reason(kind, args) != "jailed", "%s 坐牢中可用" % kind)

func test_served_release_and_enemy_clear() -> void:
	if not game_ok():
		return
	var c = _jailed_member()
	clear_events()
	fast_forward(7300.0)
	assert_false(c.is_jailed(), "期滿出獄")
	assert_eq(s().room_id(), GATE, "送回山門")
	var o := lastp(Protocol.E_JAIL_OUT)
	assert_eq(str(o.get("why", "")), "served")
	assert_eq(str(c.sect), SID, "BREACH 坐牢不會被逐出")
	# 公敵被抓：期滿後改過自新
	c.sect = ""
	c.sect_enemies = [SID]
	var cap: Dictionary = sects().capture_on_death(s(), c, { "kind": "MONSTER", "killed_by": { "kind": "MONSTER", "ref": GUARD } })
	assert_true(bool(cap.get("jail", false)), "被本派怪殺死的公敵被抓")
	assert_eq(str(c.jail.get("reason", "")), "ENEMY")
	assert_true(c.jail_left_s() > 3 * 7200.0 - 1.0, "公敵 3 遊戲日")
	fast_forward(1.0)
	assert_eq(s().room_id(), JAIL, "下一秒送進思過處（戰後）")
	assert_eq(evs(Protocol.E_JAIL_IN).size() >= 1, true)
	fast_forward(3 * 7200.0 + 5.0)
	assert_false(c.is_jailed())
	assert_false(c.sect_enemies.has(SID), "公敵身分清除")

func test_capture_rules() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("公敵俠")
	c.sect_enemies = [SID]
	# 敵對入山：公敵走進山門 → SECT_GUARD
	clear_events()
	goto(GATE)
	assert_true(s().battle_id != 0, "公敵入山開戰")
	assert_eq(lastp(Protocol.E_SECT_HOSTILE).get("sect_name", ""), "測派")
	var cap: Dictionary = sects().capture_on_death(s(), c, { "kind": "SECT_GUARD", "died": true })
	assert_true(bool(cap.get("jail", false)), "SECT_GUARD 戰死被抓")
	assert_eq(str(cap.get("room", "")), JAIL)
	# 不是公敵：不抓
	c.jail = {}
	c.sect_enemies = []
	assert_true(sects().capture_on_death(s(), c, { "kind": "MONSTER", "killed_by": { "kind": "MONSTER", "ref": GUARD } }).is_empty())
	# 被該派玩家殺死
	c.sect_enemies = [SID]
	assert_true(bool(sects().capture_on_death(s(), c, { "kind": "FORCED", "killed_by": { "kind": "PLAYER", "ref": "ch_x", "sect": SID } }).get("jail", false)))
	# BAN 模式（friends_casual）不抓
	c.jail = {}
	use_preset("friends_casual")
	install_sect()
	assert_true(sects().capture_on_death(s(), c, { "kind": "MONSTER", "killed_by": { "kind": "MONSTER", "ref": GUARD } }).is_empty(),
		"BAN 模式不押人")

func test_offline_capture_moves_location() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("離線俠")
	c.sect_enemies = [SID]
	var cap: Dictionary = sects().capture_on_death(null, c, { "kind": "MONSTER", "killed_by": { "kind": "MONSTER", "ref": GUARD } })
	assert_true(bool(cap.get("jail", false)))
	assert_eq(str(c.location.get("room", "")), JAIL, "離線者直接改位置")

func test_ransom() -> void:
	if not game_ok():
		return
	var c = _jailed_member()
	var peer := add_player("贖人俠")
	var o := session_of(peer)
	goto_as(peer, JAIL)
	assert_eq(reason_as(peer, "jail_ransom", { "npc": JAILER, "name": "無此人" }), "no_prisoner")
	o.character.money = 50
	assert_eq(reason_as(peer, "jail_ransom", { "npc": JAILER, "name": "思過俠" }), "not_enough_money")
	o.character.money = 150000
	var r := send_as(peer, "jail_ransom", { "npc": JAILER, "name": "思過俠" })
	assert_true(r.get("ok", false), str(r))
	assert_eq(int(o.character.money), 50000)
	assert_false(c.is_jailed(), "贖出")
	assert_eq(s().room_id(), GATE)
	assert_eq(str(lastp(Protocol.E_JAIL_OUT).get("why", "")), "ransom")
	assert_eq(evs_for(peer, Protocol.E_JAIL_RANSOM_PAID).size(), 1)

func test_jailer_menu_lists_prisoners() -> void:
	if not game_ok():
		return
	_jailed_member()
	clear_events()
	ok("talk", { "npc": JAILER })
	var m := lastp(Protocol.E_NPC_MENU)
	var j: Variant = m.get("jail")
	assert_true(j is Dictionary)
	assert_eq(int(j.get("ransom", 0)), 100000)
	assert_eq((j.get("prisoners", []) as Array).size(), 1)
	assert_eq(str(j["prisoners"][0]["name"]), "思過俠")

func test_no_encounter_or_scout_in_jail() -> void:
	if not game_ok():
		return
	var c = _jailed_member()
	# 把思過處改成有遇敵表的房間：坐牢中照樣不踩地雷、不能偵察
	var room: Dictionary = host().index.room(JAIL)
	room["encounter"] = { "rate": 1.0, "table": [ { "monster": "m_rabbit", "w": 1, "count": [1, 1] } ] }
	assert_false(host().regions.roll_encounter(s()), "坐牢不踩地雷")
	assert_false(host().scout.active_here(s()), "坐牢不能偵察")
	c.jail = {}
	assert_true(host().scout.active_here(s()), "放出來就能偵察")

func test_battle_defers_jail() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("戰中俠")
	join_via_npc()
	goto(GATE)
	start_battle(["m_rabbit"])
	assert_true(s().battle_id != 0)
	sects().jail(s(), SID, 1, "BREACH", "ts_r_killing")
	assert_true(c.is_jailed())
	assert_eq(s().room_id(), GATE, "戰鬥中先不送")
	host().battles.abort_all()
	s().battle_id = 0
	fast_forward(1.0)
	assert_eq(s().room_id(), JAIL, "戰後送進思過處")
	assert_eq(evs(Protocol.E_JAIL_IN).size(), 1)

func test_no_enforcer_means_ban() -> void:
	if not game_ok():
		return
	install_sect({ "enforcer": false, "jail_room": "" })
	var c = member("禁武俠")
	join_via_npc()
	clear_events()
	c.killing_intent = 2500
	sects().check_state(s(), "TICK")
	ws.flush()
	assert_false(c.is_jailed())
	assert_eq(str(lastp(Protocol.E_SECT_BREACH).get("outcome", "")), "BAN")
	assert_true(c.ban_left_s() > 7000.0)
	assert_eq(sects().can_teach(s(), HEAD), "sect_banned")
	goto(HALL)
	assert_eq(reason("learn", { "npc": HEAD, "skill": SKILL }), "sect_banned")
	assert_eq(evs(Protocol.E_SECT_STOP_TEACH).size(), 1, "學武被拒的說明")
	fast_forward(7300.0)
	assert_eq(c.ban_left_s(), 0.0)
	assert_eq(sects().can_teach(s(), HEAD), "")
