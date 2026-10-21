extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §5.3.3–5.3.4、§10.1（WP-EVENTS）：DUEL（切磋模式）。沒有死亡懲罰、戰後補滿、門技不觸發、召喚道具拿掉、
## 限時判定三層（總傷害 → 命中 → 氣比例 → 先報名者）、逃走與斷線＝棄權、旁觀者收到每一擊的文字、比武不交給 PkSystem。

var foe := 0

func before_each() -> void:
	world_name = "w_m3d_duel"
	super.before_each()

func _setup() -> bool:
	if not game_ok():
		return false
	ws.options["wait_mode"] = false   # 遠端對手不下令：停在滿條，本機一方照常行動
	if make_char("比武甲") == null:
		return false
	make_strong()
	goto(TourneyRules.ARENA_ROOM)
	foe = add_player("比武乙")
	goto_as(foe, TourneyRules.ARENA_ROOM)
	return true

func _duel(limit := 600.0, order := {}) -> Dictionary:
	clear_events()
	var bid: int = host().battles.start_pvp(s(), session_of(foe), "DUEL", { "duel_limit_s": limit, "order": order })
	ws.flush()
	assert_true(bid != 0, "DUEL 開打")
	return host().battles.active.get(bid, {})

func _units(b) -> Array:
	var a = null
	var c = null
	for u in b.units:
		if u.is_player() and u.side == 0:
			a = u
		elif u.is_player() and u.side == 1:
			c = u
	return [a, c]

func test_no_death_penalty_and_refill() -> void:
	if not _setup():
		return
	var c = ch()
	c.pk = 0
	var ki0 := int(c.killing_intent)
	var dead0 := int(c.dead_count)
	var skills0: Dictionary = {}
	for k in c.skills.entries:
		skills0[k] = int(c.skills.level(str(k)))
	var items0: int = c.inventory.items.size()
	var foe_ch = session_of(foe).character
	var entry := _duel()
	var b = entry["battle"]
	var us := _units(b)
	assert_eq(str(entry.get("kind", "")), "DUEL")
	assert_true(BattleSystem.is_pvp_kind("DUEL") and BattleSystem.is_pvp_kind("ROB"), "PVP_KINDS 有 ROB、DUEL")
	var st: Dictionary = host().battles._state_for(entry, 1)
	assert_true(absf(float(st.get("duel_left_s", -1.0)) - 600.0) < 0.5, "開場快照帶比武倒數")
	# 本機一方被打倒（qi 1）→ 對手勝；沒有死亡懲罰
	c.vitals["qi"] = 10
	BattleRules.kill(b, us[0], us[1])
	b._check_end(tables())   # 真的戰鬥裡打倒發生在行動結算中，_resolve_pending 會呼叫；測試直接補這一步
	ws.advance(0.2)
	assert_eq(s().battle_id, 0, "打倒 → 結束")
	assert_eq(s().room_id(), TourneyRules.ARENA_ROOM, "不送回記錄點")
	assert_eq(int(c.dead_count), dead0, "不算死亡")
	assert_eq(c.inventory.items.size(), items0, "不掉物品")
	for k in skills0:
		assert_eq(int(c.skills.level(str(k))), int(skills0[k]), "不扣技能 %s" % str(k))
	var d: Dictionary = c.derived(tables(), ws.options)
	assert_eq(int(c.vitals["qi"]), int(d["qi_max"]), "戰後氣補滿")
	assert_eq(int(c.vitals["neili"]), int(d["neili_max"]), "內力補滿")
	assert_eq(int(c.pk_value()), 0, "比武不加 PK值")
	assert_eq(int(c.killing_intent), ki0, "比武不加殺氣")
	assert_eq(int(foe_ch.pk_value()), 0, "打倒對手也不加 PK值")
	assert_true(bool(cs.last_battle_result.get("duel", false)), "結果框標 duel")
	assert_false(bool(cs.last_battle_result.get("you_died", true)), "you_died false")
	assert_eq(str(cs.last_battle_result.get("result", "")), "DEFEAT")
	assert_true(evs("pk_kill").is_empty(), "不廣播 pk_kill")

func test_duel_spec_strips_sect_skill_and_summons() -> void:
	if not _setup():
		return
	var spec := { "ref": "x", "sect_skill": { "id": "sl_fofa", "level": 50 },
		"battle_items": [{ "uid": "a", "effects": [{ "type": "SUMMON" }] }, { "uid": "b", "effects": [{ "type": "restore", "stat": "qi" }] }] }
	host().battles._m3d_duel_spec({ "opts": { "order": { "x": 3 } } }, spec)
	assert_eq(spec["sect_skill"], {}, "門技清空")
	assert_eq((spec["battle_items"] as Array).size(), 1, "召喚類道具拿掉")
	assert_eq(str(spec["battle_items"][0]["uid"]), "b")
	assert_eq(int(spec["duel_order"]), 3, "先報名順位")
	# 真的開打：門派弟子的規格沒有門技
	ch().sect = "shaolin"
	var entry := _duel()
	for u in entry["battle"].units:
		if u.is_player():
			assert_eq(u.spec.get("sect_skill", {}), {}, "DUEL 單位沒有門技")

func _judge_case(a_dmg: int, b_dmg: int, a_hits: int, b_hits: int, a_qi: int, b_qi: int) -> String:
	var entry := _duel(5.0, { str(ch().id): 1, str(session_of(foe).character.id): 2 })
	var b = entry["battle"]
	var us := _units(b)
	us[0].dmg_dealt = a_dmg
	us[1].dmg_dealt = b_dmg
	us[0].hits_landed = a_hits
	us[1].hits_landed = b_hits
	us[0].qi = a_qi
	us[1].qi = b_qi
	b.tick_no = 60   # 戰鬥時間 6 秒 > 限時 5 秒
	ws.advance(0.1)
	assert_eq(s().battle_id, 0, "限時到 → 判定結束")
	assert_eq(str(b.opts.get("ev_end", {}).get("how", "")), "JUDGE", "how JUDGE")
	return str(cs.last_battle_result.get("result", ""))

func test_time_limit_judge_three_tiers() -> void:
	if not _setup():
		return
	var foe_ch = session_of(foe).character
	var qa := int(ch().derived(tables(), ws.options)["qi_max"])
	var qb := int(foe_ch.derived(tables(), ws.options)["qi_max"])
	assert_eq(_judge_case(100, 50, 1, 9, 10, qb), "VICTORY", "總傷害多者勝")
	assert_eq(_judge_case(50, 50, 2, 3, qa, 10), "DEFEAT", "傷害同 → 命中多者勝")
	# 氣比例：本機 50%、對手 ~100%
	assert_eq(_judge_case(50, 50, 3, 3, qa / 2, qb), "DEFEAT", "命中也同 → 氣比例高者勝")
	assert_eq(_judge_case(50, 50, 3, 3, qa, qb), "VICTORY", "全都一樣 → 先報名者（order 1）勝")

func test_forfeit_by_flee_and_disconnect() -> void:
	if not _setup():
		return
	# 逃走＝棄權：Battle 判 ALL_FLED，BattleSystem 改成另一方勝
	var out := { "result": "ALL_FLED", "winner_side": -1, "units": {
		1: { "side": 0, "fled": true, "died": false }, 2: { "side": 1, "fled": false, "died": false } } }
	host().battles._m3d_duel_outcome(out)
	assert_eq(str(out["result"]), "DEFEAT")
	assert_eq(int(out["winner_side"]), 1)
	assert_eq(str(out["duel_how"]), "FORFEIT")
	# 斷線＝棄權
	var entry := _duel()
	var b = entry["battle"]
	drop_player(foe)
	ws.advance(0.2)
	assert_eq(s().battle_id, 0, "對手斷線 → 結束")
	assert_eq(str(b.opts.get("ev_end", {}).get("how", "")), "FORFEIT")
	assert_eq(str(cs.last_battle_result.get("result", "")), "VICTORY", "留在場上的一方勝")

func test_spectators_get_lines() -> void:
	if not _setup():
		return
	var watcher := add_player("看熱鬧丁")
	goto_as(watcher, TourneyRules.REST_ROOM)
	var outsider := add_player("路人戊")
	goto_as(outsider, "xx_square")
	_duel()
	for i in 600:
		if s().battle_id == 0:
			break
		var entry: Dictionary = host().battles.active.get(s().battle_id, {})
		if entry.is_empty():
			break
		var b = entry["battle"]
		var me = _my_unit(b)
		if me != null and str(me.state) == "READY":
			var cmd := _choose(b, "fight")
			cmd["battle_id"] = b.id
			send("battle_cmd", cmd)
		ws.advance(0.1)
		if not evs_for(watcher, "ev_duel_line").is_empty() or not evs_for(watcher, "ev_duel_line_miss").is_empty():
			break
	var lines := evs_for(watcher, "ev_duel_line").size() + evs_for(watcher, "ev_duel_line_miss").size()
	assert_true(lines > 0, "休息區的人收到擂臺上的每一擊")
	assert_eq(evs_for(outsider, "ev_duel_line").size() + evs_for(outsider, "ev_duel_line_miss").size(), 0, "外頭的人收不到")
	assert_true(evs_for(foe, "ev_duel_line").is_empty(), "選手自己看戰鬥畫面，不收房間文字")
