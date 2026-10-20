extends "res://tests/unit/test_sect_m3b_fixture.gd"
## M3B_PLAN §5.1.4、§11.1：京城監獄（監獄一般化）。
## AUTO 解析；AUTO 下違規仍關各派思過處（審查修正：京城監獄位置【待考證】，不取代 1.0A 思過處）、公敵被抓關京城監獄；
## 選項 CAPITAL：違規在有執法者時進京城監獄、無執法者 BAN；出獄到衙門；贖人；沒有京城監獄時退回各派思過處。

func before_each() -> void:
	world_name = "w_capjail"
	super.before_each()

func _member(loc := "CAPITAL"):
	install_sect()
	install_capital_jail()
	ws.options["jail_location"] = loc
	var c = member("京獄俠")
	var r := join_via_npc()
	assert_true(r.get("ok", false), "join: %s" % str(r))
	clear_events()
	return c

func test_auto_resolution() -> void:
	if not game_ok():
		return
	install_sect()
	ws.options["jail_location"] = "AUTO"
	assert_eq(sects().jail_location_resolved(), "SECT", "沒有京城監獄 → 各派思過處")
	install_capital_jail()
	ws.options["jail_location"] = "AUTO"
	assert_eq(sects().capital_jail_room(), CAP_JAIL)
	assert_eq(sects().jail_location_resolved(), "CAPITAL", "有京城監獄 → 公敵 CAPITAL")
	assert_eq(sects().breach_jail_resolved(), "SECT", "AUTO：違反門規仍關各派思過處")
	assert_eq(sects().jail_room_for(SID, "BREACH"), JAIL, "AUTO：違規 → 本派思過處")
	assert_eq(sects().jail_room_for(SID, "ENEMY"), CAP_JAIL, "AUTO：公敵 → 京城監獄")
	assert_eq(str(ws.world_info().get("jail_breach_resolved", "")), "SECT", "world_info jail_breach_resolved")
	ws.options["jail_location"] = "SECT"
	assert_eq(sects().jail_room_for(SID, "ENEMY"), JAIL, "SECT：公敵也關思過處")
	assert_eq(sects().jail_location_resolved(), "SECT")
	ws.options["jail_location"] = "CAPITAL"
	assert_eq(sects().jail_location_resolved(), "CAPITAL")
	assert_eq(sects().breach_jail_resolved(), "CAPITAL")
	assert_eq(str(ws.world_info().get("jail_location_resolved", "")), "CAPITAL", "world_info")
	assert_eq(sects().jail_room_for(SID, "BREACH"), CAP_JAIL, "有執法者：違規關京城監獄")
	assert_eq(sects().jail_room_for(SID, "ENEMY"), CAP_JAIL)

func test_breach_with_enforcer_goes_to_capital_jail() -> void:
	if not game_ok():
		return
	var c = _member()
	c.killing_intent = 2500
	sects().check_state(s(), "TICK")
	ws.flush()
	assert_true(c.is_jailed())
	assert_eq(s().room_id(), CAP_JAIL, "押進京城監獄")
	assert_eq(str(c.jail.get("scope", "")), "CAPITAL")
	assert_eq(str(lastp(Protocol.E_SECT_BREACH).get("outcome", "")), "JAIL")
	var jin := last(Protocol.E_JAIL_IN)
	if jin.is_empty():
		jin = last(Protocol.E_JAIL_IN_CAPITAL)
	assert_false(jin.is_empty(), "jail_in（或京城變體）")
	assert_eq(str(jin.get("p", {}).get("scope", "")), "CAPITAL")
	refresh_sheet()
	assert_eq(str(sheet().get("jail", {}).get("scope", "")), "CAPITAL", "角色表 jail.scope")
	assert_eq(reason("move", { "dir": "S" }), "jailed")
	# 期滿出獄 → 衙門
	clear_events()
	fast_forward(c.jail_left_s() + 1.0)
	assert_false(c.is_jailed())
	assert_eq(s().room_id(), CAP_YAMEN, "出獄送到 jail_release_to（京城衙門）")
	var out := last(Protocol.E_JAIL_OUT)
	if out.is_empty():
		out = last(Protocol.E_JAIL_OUT_CAPITAL)
	assert_eq(str(out.get("p", {}).get("scope", "")), "CAPITAL")

func test_breach_without_enforcer_is_ban() -> void:
	if not game_ok():
		return
	var c = _member()
	t()["sects"][SID]["enforcer"] = false
	assert_eq(sects().jail_room_for(SID, "BREACH"), "", "沒有執法者：違規不坐牢")
	assert_eq(sects().effective_mode(SID), "BAN")
	c.killing_intent = 2500
	sects().check_state(s(), "TICK")
	ws.flush()
	assert_false(c.is_jailed())
	assert_true(c.ban_left_s() > 0.0, "改成禁止學武")

func test_enemy_always_capital_even_without_enforcer() -> void:
	if not game_ok():
		return
	var c = _member()
	t()["sects"][SID]["enforcer"] = false
	goto(HALL)
	ok("sect_betray", { "npc": HEAD, "confirm": true })
	assert_true(c.sect_enemies.has(SID))
	var cap: Dictionary = sects().capture_on_death(s(), c,
		{ "kind": "FORCED", "killed_by": { "kind": "PLAYER", "ref": "x", "sect": SID } })
	assert_true(bool(cap.get("jail", false)), "公敵被抓：一律關京城監獄（不看本派有沒有執法者）")
	assert_eq(str(cap.get("room", "")), CAP_JAIL)
	assert_eq(str(c.jail.get("reason", "")), "ENEMY")
	assert_eq(str(c.jail.get("scope", "")), "CAPITAL")
	assert_eq(float(c.jail.get("until_online_s", 0.0)) - c.online_s, 3.0 * host().day_s(), "公敵 3 遊戲日")
	sects().enforce_jail(s())
	assert_eq(s().room_id(), CAP_JAIL)
	# 出獄改過自新（移出公敵）、叛徒記號不消
	fast_forward(c.jail_left_s() + 1.0)
	assert_false(c.sect_enemies.has(SID))
	assert_true(c.sect_traitor.has(SID))
	assert_eq(s().room_id(), CAP_YAMEN)

func test_ransom_at_capital_jailer() -> void:
	if not game_ok():
		return
	var c = _member()
	c.killing_intent = 2500
	sects().check_state(s(), "TICK")
	ws.flush()
	assert_true(c.is_jailed())
	var p := add_player("京贖人")
	goto_as(p, CAP_GATE)
	session_of(p).character.money = 200000
	clear_events_for(p)
	var r := send_as(p, "talk", { "npc": CAP_JAILER })
	assert_true(r.get("ok", false))
	var menus := evs_for(p, "npc_menu")
	assert_false(menus.is_empty())
	var jm: Variant = menus[menus.size() - 1].get("p", {}).get("jail")
	assert_true(jm is Dictionary and (jm.get("prisoners", []) as Array).size() == 1, "看守人列出京城監獄的犯人")
	var rr := send_as(p, "jail_ransom", { "npc": CAP_JAILER, "name": "京獄俠" })
	assert_true(rr.get("ok", false), "贖人：%s" % str(rr))
	assert_false(c.is_jailed())
	assert_eq(s().room_id(), CAP_YAMEN, "贖出來也送到衙門")

func test_sect_mode_keeps_m3a_behaviour() -> void:
	if not game_ok():
		return
	var c = _member()
	ws.options["jail_location"] = "SECT"
	c.killing_intent = 2500
	sects().check_state(s(), "TICK")
	ws.flush()
	assert_eq(s().room_id(), JAIL, "SECT：各派思過處")
	assert_eq(str(c.jail.get("scope", "")), "SECT")
	fast_forward(c.jail_left_s() + 1.0)
	assert_eq(s().room_id(), GATE, "思過處出獄送回山門")

func test_old_jail_record_defaults_to_sect_scope() -> void:
	var c := Character.from_dict({ "id": "ch_x", "jail": { "sect": "shaolin", "room": "sl_siguo", "until_online_s": 10.0,
		"reason": "BREACH" } })
	assert_eq(str(c.jail.get("scope", "")), "SECT", "舊存檔的 jail 沒有 scope → SECT")

func test_auto_breach_goes_to_sect_jail_even_with_capital() -> void:
	if not game_ok():
		return
	var c = _member("AUTO")
	c.killing_intent = 2500
	sects().check_state(s(), "TICK")
	ws.flush()
	assert_true(c.is_jailed())
	assert_eq(s().room_id(), JAIL, "AUTO：1.0B 世界違反門規仍關本派思過處（1.0A 已證實）")
	assert_eq(str(c.jail.get("scope", "")), "SECT")
