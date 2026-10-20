extends "res://tests/unit/test_sect_m3b_fixture.gd"
## M3B_PLAN §5.1.5、§11.1：捉拿公敵（1.0B）。全部原因碼；SEIZE 戰鬥抓的人無 PK 懲罰；目標死亡 → 關押；目標逃跑不關。

func before_each() -> void:
	world_name = "w_seize"
	super.before_each()

func _strong(c) -> void:
	for a in ["str", "agi", "con", "guts", "cal"]:
		c.attrs[a] = 150
	for sk in ["basic_fist", "basic_blade", "basic_dodge", "basic_parry"]:
		c.skills.set_level(sk, 80, tables())
	c.combat_xp = maxi(int(c.combat_xp), 5000)
	c.clamp_vitals(tables(), ws.options)
	Survival.rest_full(c, tables(), ws.options)

## A：測派弟子（抓人的）；B：叛出測派的公敵（實戰 1000）
func _pair() -> Array:
	install_sect()
	ws.options["jail_location"] = "AUTO"
	install_capital_jail()
	var a := add_player("捕快甲")
	var b := add_player("公敵乙")
	var ca = session_of(a).character
	var cb = session_of(b).character
	ca.sect = SID
	cb.sect = SID
	cb.combat_xp = 1000
	cb.betray_penalty(tables(), host().rules, "BETRAY")
	assert_true(cb.sect_enemies.has(SID))
	goto_as(a, HALL)
	goto_as(b, HALL)
	# 敵對入山可能已經開打：結束它
	for p in [a, b]:
		var o := session_of(p)
		if o.battle_id != 0:
			host().battles.active[o.battle_id]["battle"].abort()
			ws.advance(0.2)
	return [a, b]

func _unit_of(bt, peer: int):
	for u in bt.units:
		if int(u.peer) == peer:
			return u
	return null

func _drive(bid: int, policies: Dictionary, max_s := 900.0) -> void:
	var tt := 0.0
	while host().battles.active.has(bid) and tt < max_s:
		var bt = host().battles.active[bid]["battle"]
		for peer in policies:
			var u = _unit_of(bt, int(peer))
			if u == null or str(u.state) != "READY" or bt.is_over():
				continue
			var cmd := { "cmd": "DEFEND" }
			if str(policies[peer]) == "flee":
				cmd = { "cmd": "FLEE" } if bt.grid.is_escape(u.pos) else cmd
				if cmd["cmd"] == "DEFEND":
					for p in bt.grid.reachable(u.pos, BattleFormulas.move_range(u)):
						if bt.grid.is_escape(p):
							cmd = { "cmd": "MOVE", "target": [p.x, p.y] }
							break
			elif str(policies[peer]) == "fight":
				for e in bt.units:
					if int(e.side) != int(u.side) and e.is_active():
						if _dist(u.pos, e.pos) == 1:
							cmd = { "cmd": "ATTACK", "target": [e.pos.x, e.pos.y] }
						else:
							var best: Vector2i = u.pos
							var bd := _dist(u.pos, e.pos)
							for p in bt.grid.reachable(u.pos, BattleFormulas.move_range(u)):
								if _dist(p, e.pos) < bd:
									bd = _dist(p, e.pos)
									best = p
							if best != u.pos:
								cmd = { "cmd": "MOVE", "target": [best.x, best.y] }
						break
			cmd["battle_id"] = bid
			var r := send_as(int(peer), "battle_cmd", cmd)
			if not r.get("ok", false):
				send_as(int(peer), "battle_cmd", { "battle_id": bid, "cmd": "DEFEND" })
		ws.advance(0.1)
		tt += 0.1

func test_reason_codes() -> void:
	if not game_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	# era_locked：1.0A 世界
	GameData.enabled_eras = ["1.0A"]
	assert_eq(reason_as(a, "seize_enemy", { "name": "公敵乙" }), "era_locked")
	GameData.enabled_eras = ["1.0A", "1.0B"]
	ws.options["seize_enabled"] = false
	assert_eq(reason_as(a, "seize_enemy", { "name": "公敵乙" }), "seize_disabled")
	ws.options["seize_enabled"] = true
	var c := add_player("路人丙")
	goto_as(c, HALL)
	if session_of(c).battle_id != 0:
		host().battles.active[session_of(c).battle_id]["battle"].abort()
		ws.advance(0.2)
	assert_eq(reason_as(c, "seize_enemy", { "name": "公敵乙" }), "no_sect")
	assert_eq(reason_as(a, "seize_enemy", { "name": "不存在的人" }), "not_here")
	goto_as(b, GATE)
	assert_eq(reason_as(a, "seize_enemy", { "name": "公敵乙" }), "not_here", "不在同一間房")
	goto_as(b, HALL)
	if session_of(b).battle_id != 0:
		host().battles.active[session_of(b).battle_id]["battle"].abort()
		ws.advance(0.2)
	session_of(c).character.combat_xp = 1000
	assert_eq(reason_as(a, "seize_enemy", { "name": "路人丙" }), "not_enemy")
	session_of(b).character.combat_xp = 100
	assert_eq(reason_as(a, "seize_enemy", { "name": "公敵乙" }), "target_newbie_protected")
	session_of(b).character.combat_xp = 1000
	# 不能 PK 又不是本派地區（西夏城）
	goto_as(a, STREET)
	goto_as(b, STREET)
	assert_eq(reason_as(a, "seize_enemy", { "name": "公敵乙" }), "no_pk_here")
	goto_as(a, HALL)
	goto_as(b, HALL)
	for pp in [a, b]:
		if session_of(pp).battle_id != 0:
			host().battles.active[session_of(pp).battle_id]["battle"].abort()
			ws.advance(0.2)
	session_of(b).character.jail = { "sect": SID, "room": JAIL, "until_online_s": 1e9, "reason": "ENEMY", "rule": "",
		"days": 3, "notified": true, "scope": "SECT" }
	assert_eq(reason_as(a, "seize_enemy", { "name": "公敵乙" }), "target_busy", "坐牢中的人")
	session_of(b).character.jail = {}
	# seizable 標記：A 看 B 是可捉拿，C 看 B 不是
	session_of(a).view_dirty = true
	host().flush_session(session_of(a), true)
	ws.flush()
	var seen := false
	for e in view_for(a).get("players", []):
		if str(e.get("name", "")) == "公敵乙":
			seen = bool(e.get("seizable", false))
	assert_true(seen, "player_tags.seizable")

func test_seize_kill_jails_without_penalty() -> void:
	if not game_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	var ca = session_of(a).character
	var cb = session_of(b).character
	_strong(ca)
	cb.vitals["qi"] = 1
	var pk0: int = ca.pk_value()
	var mo0: int = ca.morality
	var ki0: int = ca.killing_intent
	var r := send_as(a, "seize_enemy", { "name": "公敵乙" })
	assert_true(r.get("ok", false), "seize：%s" % str(r))
	var bid := session_of(a).battle_id
	assert_eq(str(host().battles.active[bid]["kind"]), "SEIZE")
	assert_false(evs_for(b, "seize_start").is_empty(), "seize_start")
	_drive(bid, { a: "fight", b: "defend" })
	assert_true(int(cb.dead_count) >= 1, "目標死亡")
	assert_true(cb.is_jailed(), "被抓的公敵關押")
	assert_eq(str(cb.jail.get("reason", "")), "ENEMY")
	assert_eq(str(cb.jail.get("room", "")), CAP_JAIL, "京城監獄")
	ws.advance(1.5)   # ConditionSystem 每秒把坐牢中的人送進牢房（enforce_jail）
	assert_eq(session_of(b).room_id(), CAP_JAIL)
	assert_eq(ca.pk_value(), pk0, "抓的人不加 PK 值")
	assert_eq(int(ca.morality), mo0, "不改善惡")
	assert_eq(int(ca.killing_intent), ki0, "不加殺氣")
	assert_true(evs_for(a, "pk_kill").is_empty(), "不廣播 pk_kill")
	var done := evs_for(a, "seize_done")
	assert_false(done.is_empty(), "全服 seize_done")
	assert_eq(str(done[0].get("p", {}).get("name", "")), "公敵乙")

func test_target_flee_not_jailed() -> void:
	if not game_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	var cb = session_of(b).character
	_strong(cb)
	cb.attrs["agi"] = 200
	var r := send_as(a, "seize_enemy", { "name": "公敵乙" })
	assert_true(r.get("ok", false))
	var bid := session_of(a).battle_id
	_drive(bid, { a: "defend", b: "flee" })
	assert_false(cb.is_jailed(), "目標逃跑：不關")
	assert_eq(int(cb.dead_count), 0)

func test_seize_pulls_attacker_party_only() -> void:
	if not game_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	if host().get("party") == null:
		return
	var m := add_player("捕快丁")
	goto_as(m, HALL)
	if session_of(m).battle_id != 0:
		host().battles.active[session_of(m).battle_id]["battle"].abort()
		ws.advance(0.2)
	session_of(m).character.sect = SID
	assert_true(send_as(a, "party_invite", { "target": str(session_of(m).character.id) }).get("ok", false))
	var inv := evs_for(m, "party_invited")
	if inv.is_empty():
		return
	send_as(m, "party_reply", { "from": str(session_of(a).character.id), "accept": true })
	var r := send_as(a, "seize_enemy", { "name": "公敵乙" })
	assert_true(r.get("ok", false))
	assert_eq(session_of(m).battle_id, session_of(a).battle_id, "同房閒置隊友一起入場")
	assert_eq(session_of(b).battle_id, session_of(a).battle_id)
