extends "res://tests/unit/test_world_fixture.gd"
## M2_PLAN 6.1 test_world_party：組隊 intent 走完整主機路徑；遇敵拉入同房閒置隊友（不同房、戰鬥中的不拉）；
## battle_join 驗證順序的全部原因碼；勝利時每人實戰 = 單人 × 1/√n（含中途加入者）；
## 斷線後重連 char_select 接回同一場；room_battles；PvP（start_pvp）的開場、結算與 on_pvp_end 摘要。

## 假的 PkSystem：只記下 on_pvp_end 的摘要（真正的 PK 規則由 WP-PK 測）
class FakePk extends RefCounted:
	var host = null
	var summaries: Array = []
	func on_pvp_end(summary: Dictionary) -> void:
		summaries.append(summary.duplicate(true))

func before_each() -> void:
	world_name = "w_party"
	super.before_each()

func _cid(peer: int) -> String:
	var o := session_of(peer)
	return str(o.character.id) if o != null and o.character != null else ""

func _strengthen(c) -> void:
	for a in ["str", "agi", "con", "guts", "cal"]:
		c.attrs[a] = 120
	for sk in ["basic_fist", "basic_blade", "basic_dodge", "basic_parry"]:
		c.skills.set_level(sk, 60, tables())
	c.clamp_vitals(tables(), ws.options)
	Survival.rest_full(c, tables(), ws.options)

## 本機玩家（peer 1）當領隊，把 peers 依序拉進隊伍
func _form_party(peers: Array) -> void:
	for p in peers:
		ok("party_invite", { "target": _cid(p) })
		var r := send_as(p, "party_reply", { "from": str(ch().id), "accept": true })
		assert_true(r.get("ok", false), "party_reply as %d: %s" % [p, str(r)])

func _entry(bid: int) -> Dictionary:
	return host().battles.active.get(bid, {})

func _unit_of(bid: int, peer: int):
	var e := _entry(bid)
	if e.is_empty():
		return null
	var b: Battle = e["battle"]
	return b.unit(b.uid_for_peer(peer))

# ---------------------------------------------------------------- 組隊 intent

func test_party_intents_through_host() -> void:
	if not game_ok():
		return
	make_char("隊長甲")
	var p2 := add_player("隊員乙")
	assert_eq(view_for(p2).get("room", ""), s().room_id(), "同一個出生房間")
	assert_eq(reason("party_invite", { "target": str(ch().id) }), "bad_target")
	clear_events()
	ok("party_invite", { "target": _cid(p2) })
	ws.advance(0.3)   # 對方的 sheet 由下一個 tick 送出（0.25 秒節流）
	assert_eq(lastp("party_invite_sent").get("name", ""), "隊員乙")
	var inv: Array = evs_for(p2, "party_invited")
	assert_eq(inv.size(), 1)
	assert_eq(inv[0].p.from_char, str(ch().id))
	assert_eq(int(inv[0].p.ttl), 60)
	assert_eq(sheet_for(p2).get("pending", {}).get("party_invite", {}).get("from_char", ""), str(ch().id),
		"sheet.pending 重建邀請提示")
	assert_eq(reason_as(p2, "party_reply", { "from": "ch_nobody", "accept": true }), "no_invite")
	assert_true(send_as(p2, "party_reply", { "from": str(ch().id), "accept": true }).get("ok", false))
	ws.advance(0.3)
	var pt: Dictionary = sheet().get("party", {})
	assert_eq(pt.get("leader", ""), str(ch().id))
	assert_eq((pt.get("members", []) as Array).size(), 2)
	assert_eq(sheet_for(p2).get("party", {}).get("id", ""), pt.get("id", "x"))
	assert_eq(lastp("party_joined").get("peer", 0), p2, "領隊看到 other 變體")
	assert_eq(evs_for(p2, "party_joined")[0].p.leader_name, "隊長甲")
	host().flush_session(s(), true)
	ws.flush()
	var tagged := false
	for pl in view().get("players", []):
		if int(pl.get("peer", 0)) == p2:
			tagged = str(pl.get("party_id", "")) == str(pt.get("id", ""))
	assert_true(tagged, "view.players[].party_id")
	# 領隊離開 → 剩 1 人 → 解散
	clear_events_for(p2)
	ok("party_leave")
	assert_eq(evs_for(p2, "party_disbanded").size(), 1)
	assert_eq(sheet().get("party", {}), {})
	assert_eq(reason("party_leave"), "not_in_party")

func test_offline_leaves_party() -> void:
	if not game_ok():
		return
	make_char("隊長甲")
	var p2 := add_player("隊員乙")
	var p3 := add_player("隊員丙")
	_form_party([p2, p3])
	assert_eq(host().party.sheet_for(s()).members.size(), 3)
	drop_player(p2)
	assert_eq(host().party.sheet_for(s()).members.size(), 2, "離線即離隊")
	assert_eq(lastp("party_left").get("name", ""), "隊員乙")

# ---------------------------------------------------------------- 開戰拉入

func test_encounter_pulls_idle_teammates_in_same_room() -> void:
	if not game_ok():
		return
	make_char("隊長甲")
	var p2 := add_player("隊員乙")
	var p3 := add_player("隊員丙")
	var p4 := add_player("隊員丁")
	var p5 := add_player("路人戊")
	_form_party([p2, p3, p4])
	goto_as(p3, "xw_hill")
	var busy_bid: int = host().battles.start(session_of(p3), ["m_wolf"], "ENCOUNTER")   # 丙已經在打（獨自）
	ws.flush()
	assert_eq(host().battles.humans(busy_bid), 1)
	goto("xw_hill")
	for p in [p2, p5]:
		goto_as(p, "xw_hill")
	goto_as(p4, "xw_grass")
	assert_true(busy_bid > 0)
	var bid := start_battle(["m_wolf"])
	assert_true(bid > 0 and bid != busy_bid)
	assert_eq(session_of(p2).battle_id, bid, "同房閒置隊友被拉入")
	assert_eq(battle_open_for(p2).get("bid", 0), bid, "隊友收到 s2c_battle_open")
	assert_eq(battle_open_for(p2).get("my_side", -1), 0)
	assert_eq(battle_open_for(p2).get("kind", ""), "ENCOUNTER")
	assert_true(int(battle_open_for(p2).get("my_uid", 0)) > 0)
	assert_eq(session_of(p3).battle_id, busy_bid, "戰鬥中的不拉")
	assert_eq(session_of(p4).battle_id, 0, "不同房的不拉")
	assert_eq(session_of(p5).battle_id, 0, "不是隊友的不拉")
	assert_eq(host().battles.humans(bid), 2)
	assert_eq(cs.battle_state.get("kind", ""), "ENCOUNTER")
	assert_eq(cs.battle_state.get("my_side", -1), 0)
	# room_battles：路人看得到兩場，都不能加入
	var rb: Array = host().battles.room_battles("xw_hill", session_of(p5))
	assert_eq(rb.size(), 2)
	var mine: Dictionary = rb[0] if int(rb[0].bid) == bid else rb[1]
	assert_eq(mine.kind, "ENCOUNTER")
	assert_true((mine.names[0] as Array).has("隊長甲") and (mine.names[0] as Array).has("隊員乙"))
	assert_eq((mine.names[1] as Array).size(), 1)
	assert_false(mine.joinable, "不是隊友不能加入")
	ws.advance(0.3)
	assert_true(sheet_for(p2).get("in_battle", false), "隊友的 sheet 標示戰鬥中")

func test_battle_max_humans_caps_pull() -> void:
	if not game_ok():
		return
	make_char("隊長甲")
	var p2 := add_player("隊員乙")
	var p3 := add_player("隊員丙")
	_form_party([p2, p3])
	ws.options["battle_max_humans"] = 2
	var bid := start_battle(["m_wolf"])
	assert_eq(host().battles.humans(bid), 2, "總玩家數不超過 battle_max_humans")
	assert_eq(session_of(p2).battle_id, bid, "依加入順序拉入")
	assert_eq(session_of(p3).battle_id, 0)
	ws.options["battle_max_humans"] = 8

## M2 審查：守衛戰不自動拉入同房隊友（他們可以用 battle_join 自願加入）
func test_guard_battle_does_not_pull_teammates() -> void:
	if not game_ok():
		return
	make_char("隊長甲")
	var p2 := add_player("隊員乙")
	_form_party([p2])
	var bid := start_battle(["m_city_guard"], "GUARD")
	assert_true(bid > 0)
	assert_eq(host().battles.humans(bid), 1, "guard battle is the wanted player's alone")
	assert_eq(session_of(p2).battle_id, 0, "innocent teammate not pulled")
	var rb: Array = host().battles.room_battles(s().room_id(), session_of(p2))
	assert_eq(rb.size(), 1)
	assert_true(bool(rb[0].joinable), "teammate may still join voluntarily")

# ---------------------------------------------------------------- battle_join

func test_battle_join_reason_order_and_events() -> void:
	if not game_ok():
		return
	make_char("隊長甲")
	var p2 := add_player("隊員乙")
	var p3 := add_player("隊員丙")
	var p6 := add_player("路人己")
	_form_party([p2, p3])
	goto_as(p3, "xw_hill")
	var other: int = host().battles.start(session_of(p3), ["m_wolf"], "ENCOUNTER")   # 丙另外在打（獨自）
	assert_eq(host().battles.humans(other), 1)
	goto("xw_hill")
	goto_as(p2, "xw_grass")
	goto_as(p6, "xw_hill")
	var bid := start_battle(["m_wolf"])
	assert_eq(host().battles.humans(bid), 1, "乙不在同房、丙在打 → 都沒被拉")
	assert_eq(reason_as(p2, "battle_join", { "battle_id": 999999 }), "battle_not_found", "不存在")
	assert_eq(reason_as(p2, "battle_join", { "battle_id": bid }), "battle_not_found", "不在同房")
	goto_as(p2, "xw_hill")
	assert_eq(reason_as(p6, "battle_join", { "battle_id": bid }), "join_not_allowed", "沒有隊友在裡面")
	var b: Battle = _entry(bid)["battle"]
	var st := b.state
	b.state = Battle.State.ENDED
	assert_eq(reason_as(p2, "battle_join", { "battle_id": bid }), "battle_over")
	b.state = st
	ws.options["battle_max_humans"] = 1
	assert_eq(reason_as(p2, "battle_join", { "battle_id": bid }), "battle_full")
	ws.options["battle_max_humans"] = 8
	assert_eq(reason_as(p3, "battle_join", { "battle_id": bid }), "in_battle", "C+I：自己在戰鬥中")
	var rb: Array = host().battles.room_battles("xw_hill", session_of(p2))
	var joinable := false
	for x in rb:
		if int(x.bid) == bid:
			joinable = bool(x.joinable)
	assert_true(joinable, "隊友看到 joinable")
	host().flush_session(session_of(p2), true)
	ws.flush()
	var vb: Array = view_for(p2).get("battles", [])
	assert_true(vb.any(func(x): return int(x.get("bid", 0)) == bid and bool(x.get("joinable", false))),
		"view.battles 帶 joinable（RegionSystem 合併）")
	clear_events()
	clear_events_for(p2)
	var r := send_as(p2, "battle_join", { "battle_id": bid })
	assert_true(r.get("ok", false), "battle_join: %s" % str(r))
	assert_eq(session_of(p2).battle_id, bid)
	var bo := battle_open_for(p2)
	assert_eq(bo.get("bid", 0), bid, "新加入者收 s2c_battle_open")
	assert_eq(bo.get("my_side", -1), 0)
	var u = _unit_of(bid, p2)
	assert_true(u != null and u.pos.x == 0, "從邊緣 x=0 出場")
	assert_eq(host().battles.humans(bid), 2)
	assert_eq(evs_for(p2, "battle_join").size(), 1, "新加入者 self")
	assert_eq(evs_for(p2, "battle_join")[0].p.peer, p2)
	assert_eq(evs("battle_join").size(), 1, "全場（隊長）other")
	assert_eq(evs("battle_unit_join").size(), 1)
	assert_eq(evs("battle_unit_join")[0].get("ui", false), true)
	assert_eq(evs("battle_unit_join")[0].p.unit.side, 0)
	assert_eq(reason_as(p2, "battle_join", { "battle_id": bid }), "in_battle", "已在戰鬥中")
	# 加入後 6 號路人仍不能加入
	assert_eq(reason_as(p6, "battle_join", { "battle_id": bid }), "join_not_allowed")

# ---------------------------------------------------------------- 獎勵分享

func test_victory_shares_rewards_including_mid_joiner() -> void:
	if not game_ok():
		return
	make_char("隊長甲")
	make_strong()
	var p2 := add_player("隊員乙")
	var p3 := add_player("隊員丙")
	_form_party([p2, p3])
	goto("xw_hill")
	goto_as(p2, "xw_hill")
	goto_as(p3, "xw_grass")
	for p in [p2, p3]:
		_strengthen(session_of(p).character)
	var xp0 := { 1: int(ch().combat_xp), p2: int(session_of(p2).character.combat_xp),
		p3: int(session_of(p3).character.combat_xp) }
	var bid := start_battle(["m_wolf"])
	assert_eq(host().battles.humans(bid), 2)
	goto_as(p3, "xw_hill")
	assert_true(send_as(p3, "battle_join", { "battle_id": bid }).get("ok", false), "丙中途加入")
	var res := drive_battle("fight")
	assert_eq(res.get("result", ""), "VICTORY")
	var row: Dictionary = tables()["monsters"]["m_wolf"]
	var share := 1.0 / sqrt(3.0)
	for p in [1, p2, p3]:
		var o: Session = s() if p == 1 else session_of(p)
		var expect := BattleRewards.xp_for(row, int(xp0[p]), share)
		assert_eq(int(o.character.combat_xp) - int(xp0[p]), expect, "peer %d 實戰 = 單人 × 1/√3" % p)
	var solo := BattleRewards.xp_for(row, 0, 1.0)
	assert_true(BattleRewards.xp_for(row, 0, share) < solo, "分享後比單打少")
	for p in [p2, p3]:
		var bc: Dictionary = remote[p]["battle_close"]
		assert_eq(bc.get("result", ""), "VICTORY", "peer %d 結果" % p)
		assert_eq(bc.get("kind", ""), "ENCOUNTER")
		assert_eq(int(bc.get("rewards", {}).get("combat_xp", -1)), BattleRewards.xp_for(row, 0, share))
		assert_eq(session_of(p).battle_id, 0)
	assert_eq(cs.last_battle_result.get("kind", ""), "ENCOUNTER")

# ---------------------------------------------------------------- 斷線重連接回

func test_reconnect_reattaches_same_battle() -> void:
	if not game_ok():
		return
	make_char("隊長甲")
	var p2 := add_player("隊員乙")
	_form_party([p2])
	goto("xw_hill")
	goto_as(p2, "xw_hill")
	var cid2 := _cid(p2)
	var ident := identity_of(p2)
	make_strong()
	_strengthen(session_of(p2).character)
	var bid := start_battle(["m_rabbit"])   # 野兔幾乎打不痛人、沒人打牠也不會逃：戰鬥會一直進行
	assert_eq(session_of(p2).battle_id, bid)
	var ch_in_battle = _entry(bid)["chars"][p2]
	drop_player(p2)
	assert_true(host().battles.active.has(bid), "隊長還在：戰鬥照常進行")
	assert_eq(host().battles.battle_of_char(cid2), bid, "斷線者仍算在戰鬥裡")
	var u = _unit_of(bid, p2)
	assert_true(u != null and u.detached and u.afk, "斷線者的單位改為自動防")
	ws.advance(1.0)
	var np := connect_player("隊員乙", ident)
	assert_true(np != p2)
	var r := send_as(np, "char_select", { "char_id": cid2 })
	assert_true(r.get("ok", false), "char_select: %s" % str(r))
	var o := session_of(np)
	assert_eq(o.battle_id, bid, "接回同一場")
	assert_true(o.character == ch_in_battle, "沿用戰鬥中的同一個 Character 物件")
	assert_eq(battle_open_for(np).get("bid", 0), bid, "重送 s2c_battle_open")
	assert_eq(battle_open_for(np).get("my_side", -1), 0)
	var nu = _unit_of(bid, np)
	assert_true(nu != null, "單位換成新 peer")
	assert_false(nu.detached)
	assert_false(nu.afk)
	assert_eq(int(battle_open_for(np).get("my_uid", 0)), int(nu.uid))
	# 接回後還能下令：等到輪到他
	var t := 0.0
	var acted := false
	while t < 120.0 and o.battle_id == bid and not acted:
		var b: Battle = _entry(bid).get("battle") if not _entry(bid).is_empty() else null
		if b != null and b.waiting_humans().has(nu):
			var rr := send_as(np, "battle_cmd", { "battle_id": bid, "cmd": "DEFEND" })
			assert_true(rr.get("ok", false), "重連後 battle_cmd: %s" % str(rr))
			acted = true
		else:
			# 隊長自動防守，讓戰鬥走下去
			if b != null and b.waiting_humans().any(func(x): return x.peer == 1):
				send("battle_cmd", { "battle_id": bid, "cmd": "DEFEND" })
			ws.advance(0.1)
			t += 0.1
	assert_true(acted, "重連的玩家輪得到")
	host().battles.abort_all()

func test_char_select_without_battle_loads_normally() -> void:
	if not game_ok():
		return
	make_char("隊長甲")
	var p2 := add_player("隊員乙")
	var cid2 := _cid(p2)
	var ident := identity_of(p2)
	drop_player(p2)
	assert_eq(host().battles.battle_of_char(cid2), 0)
	var np := connect_player("隊員乙", ident)
	assert_true(send_as(np, "char_select", { "char_id": cid2 }).get("ok", false))
	assert_eq(session_of(np).battle_id, 0)
	assert_false(host().battles.reattach(session_of(np), cid2), "沒有戰鬥時 reattach 回 false")

# ---------------------------------------------------------------- PvP 核心

func test_start_pvp_open_settle_and_summary() -> void:
	if not game_ok():
		return
	make_char("狂徒甲")
	make_strong()
	var p2 := add_player("路人乙")
	var p3 := add_player("隊員丙")
	_form_party([p3])
	goto("xw_road")
	goto_as(p2, "xw_road")
	goto_as(p3, "xw_road")
	var real_pk = host().pk
	var fake := FakePk.new()
	host().pk = fake
	clear_events()
	var bid: int = host().battles.start_pvp(s(), session_of(p2), "FORCED")
	ws.flush()
	assert_true(bid > 0)
	assert_eq(host().battles.humans(bid), 2, "只有兩人，不拉隊友")
	assert_eq(session_of(p3).battle_id, 0)
	assert_eq(cs.battle_state.get("kind", ""), "FORCED")
	assert_eq(cs.battle_state.get("my_side", -1), 0)
	var bo := battle_open_for(p2)
	assert_eq(bo.get("my_side", -1), 1, "被攻擊者在 side 1")
	assert_eq(bo.get("kind", ""), "FORCED")
	for u in bo.get("units", []):
		if int(u.get("peer", 0)) == 1:
			assert_false(u.has("arts"), "對方玩家只帶最少欄位")
			assert_true(u.has("look"))
		elif int(u.get("peer", 0)) == p2:
			assert_true(u.has("arts"), "自己完整")
	assert_eq(reason_as(p3, "battle_join", { "battle_id": bid }), "join_not_allowed", "PvP 不能中途加入")
	assert_eq(host().battles.start_pvp(s(), session_of(p3), "FORCED"), 0, "已在戰鬥中不能再開")
	var res := drive_battle("fight")
	assert_eq(res.get("result", ""), "VICTORY", "結果相對於本人那一方")
	assert_eq(res.get("kind", ""), "FORCED")
	assert_eq(int(res.get("rewards", {}).get("combat_xp", -1)), 0, "PvP 沒有實戰")
	assert_eq(int(res.get("rewards", {}).get("learn_points", -1)), 0)
	assert_eq(evs("battle_reward").size(), 0, "PvP 不送獲得 0 點的訊息")
	var bc: Dictionary = remote[p2]["battle_close"]
	assert_eq(bc.get("result", ""), "DEFEAT")
	assert_true(bool(bc.get("you_died", false)))
	assert_false((bc.get("death", {}) as Dictionary).is_empty(), "PvP 死亡照 handle_death")
	assert_eq(fake.summaries.size(), 1, "on_pvp_end 呼叫一次")
	var sm: Dictionary = fake.summaries[0]
	assert_eq(sm.bid, bid)
	assert_eq(sm.kind, "FORCED")
	assert_eq(sm.room, "xw_road")
	assert_eq(sm.units.size(), 2)
	var by := {}
	for x in sm.units:
		by[x.char_id] = x
	var me: Dictionary = by[str(ch().id)]
	var vic: Dictionary = by[_cid(p2)]
	assert_eq(me.side, 0)
	assert_false(me.died)
	assert_eq(me.peer, 1)
	assert_eq(me.killed_by_char, "")
	assert_eq(vic.side, 1)
	assert_true(vic.died)
	assert_eq(vic.peer, p2)
	assert_eq(vic.name, "路人乙")
	assert_eq(vic.killed_by_char, str(ch().id), "擊殺者 char_id")
	assert_false(vic.fled)
	assert_eq(host().battles.battle_of_char(_cid(p2)), 0)
	host().pk = real_pk

func test_start_pvp_rejects_bad_kind_and_self() -> void:
	if not game_ok():
		return
	make_char("狂徒甲")
	var p2 := add_player("路人乙")
	assert_eq(host().battles.start_pvp(s(), s(), "FORCED"), 0, "不能打自己")
	assert_eq(host().battles.start_pvp(s(), session_of(p2), "ENCOUNTER"), 0, "kind 不對")
	assert_eq(s().battle_id, 0)
	assert_eq(session_of(p2).battle_id, 0)

## M2 審查：斷線後角色還在隊友的戰鬥裡（自動防）時，不能刪除、不能用護照還原；
## 否則戰鬥結束時 _settle_player 會把角色檔寫回來、名字又能被別人取走
func test_delete_and_restore_refused_while_char_still_in_battle() -> void:
	if not game_ok():
		return
	make_char("隊長甲")
	var p2 := add_player("隊員乙")
	_form_party([p2])
	goto("xw_hill")
	goto_as(p2, "xw_hill")
	var cid2 := _cid(p2)
	var ident := identity_of(p2)
	make_strong()
	_strengthen(session_of(p2).character)
	var bid := start_battle(["m_rabbit"])
	var ch_in_battle = _entry(bid)["chars"][p2]
	var passport_json := JSON.stringify(host().make_passport(ch_in_battle))
	drop_player(p2)
	assert_eq(host().battles.battle_of_char(cid2), bid, "still in the battle after the drop")
	var np := connect_player("隊員乙", ident)
	var r := send_as(np, "char_delete", { "char_id": cid2, "confirm_name": "隊員乙" })
	assert_eq(str(r.get("reason", "")), "char_active", "delete refused during the detached battle: %s" % str(r))
	assert_true(host().char_store.has_char(ident, cid2), "file kept")
	assert_true(host().char_store.name_taken("隊員乙"), "name still taken")
	var pp: Variant = JSON.parse_string(passport_json)
	var r2 := send_as(np, "passport_restore", { "passport": pp })
	assert_eq(str(r2.get("reason", "")), "char_active", "passport restore refused during the battle: %s" % str(r2))
	# 戰鬥結束後就可以刪了，刪了也不會被寫回來
	host().battles.abort_all()
	assert_eq(host().battles.battle_of_char(cid2), 0)
	var r3 := send_as(np, "char_delete", { "char_id": cid2, "confirm_name": "隊員乙" })
	assert_true(r3.get("ok", false), "delete after the battle: %s" % str(r3))
	assert_false(host().char_store.has_char(ident, cid2), "deleted for good")
	assert_false(host().char_store.name_taken("隊員乙"), "name freed")
