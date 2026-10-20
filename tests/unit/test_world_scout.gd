extends "res://tests/unit/test_world_fixture.gd"
## 查看偵察（docs/GDD.md §5.10【設計提案・非原作】；ScoutSystem）：
## 野外按查看（look { scout: true }）→ 主機擲遇敵表、必定發現 → scout_offer（ui）；迎戰 = 與踩地雷相同的開戰（拉同房隊友）；
## 離開、過期、換房、進戰鬥、離線、選項關閉都讓提示失效；冷卻（cooldowns.scout）只在能偵察的房間；
## 安全的房間查看照舊（沒有冷卻、沒有提示）；scout_enabled = false 時與以前完全一樣。

const WILD := "dlw_road"        # 只有野兔（count [1, 1]）
const WILD2 := "dlw_lake"
const SAFE := "xx_square"

func before_each() -> void:
	world_name = "w_scout"
	super.before_each()

func after_each() -> void:
	ws.set_time_scale(1.0)
	super.after_each()

func _offer() -> Dictionary:
	return s().scout_offer

func _cd() -> float:
	return float(sheet().get("cooldowns", {}).get("scout", -1.0))

func _scout() -> Dictionary:
	clear_events()
	return ok("look", { "scout": true })

func _cid(peer: int) -> String:
	var o := session_of(peer)
	return str(o.character.id) if o != null and o.character != null else ""

# ---------------------------------------------------------------- 協定

func test_protocol_shapes() -> void:
	assert_eq(Protocol.validate_args("look", {}), "")
	assert_eq(Protocol.validate_args("look", { "scout": true }), "")
	assert_eq(Protocol.validate_args("look", { "scout": 1 }), "bad_type:scout")
	assert_eq(Protocol.validate_args("scout_accept", { "offer_id": "sc_1" }), "")
	assert_eq(Protocol.validate_args("scout_accept", {}), "missing_arg:offer_id")
	assert_eq(Protocol.validate_args("scout_accept", { "offer_id": "sc_1", "monsters": ["m_tiger"] }), "unexpected_arg",
		"客戶端不能指定怪物")
	assert_eq(Protocol.validate_args("scout_decline", { "offer_id": "sc_1" }), "")
	assert_true(Protocol.VERSION >= 4, "偵察本身不升版；M3a（K1）升到 4，故事包升到 5")
	assert_has(UiKeys.UI_ONLY_KEYS, UiKeys.E_SCOUT_OFFER)
	assert_has(UiKeys.UI_ONLY_KEYS, UiKeys.E_SCOUT_CLOSED)
	assert_eq(UiKeys.I_SCOUT_ACCEPT, Protocol.I_SCOUT_ACCEPT)
	assert_eq(UiKeys.I_SCOUT_DECLINE, Protocol.I_SCOUT_DECLINE)

func test_encounter_pick_ignores_rate() -> void:
	var room := { "encounter": { "rate": 0.0001, "table": [ { "monster": "m_rabbit", "w": 1, "count": [2, 2] } ] } }
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 20:
		assert_eq(Encounter.pick(room, rng), ["m_rabbit", "m_rabbit"], "必定挑到、數量規則同踩地雷")
	assert_eq(Encounter.pick({ "encounter": { "rate": 1.0, "table": [] } }, rng), [])
	assert_eq(Encounter.pick({}, rng), [])
	var big := { "encounter": { "rate": 1.0, "table": [ { "monster": "m_rabbit", "w": 1, "count": [9, 9] } ] } }
	assert_eq(Encounter.pick(big, rng).size(), Encounter.MAX_MONSTERS)

# ---------------------------------------------------------------- 偵察與提示

func test_look_in_wild_makes_offer() -> void:
	if not game_ok():
		return
	make_char()
	goto(WILD)
	assert_true(ws.world_info().get("scout_enabled", false), "world_info 帶選項")
	_scout()
	assert_eq(lastp(Protocol.E_LOOK).get("room_name", ""), host().room_name(WILD), "照樣印房間描述")
	var o := _offer()
	assert_false(o.is_empty(), "主機存了提示")
	assert_eq(o.get("monsters", []), ["m_rabbit"])
	assert_eq(str(o.get("room", "")), WILD)
	assert_true(str(o.get("id", "")).begins_with("sc_"))
	var e := last(Protocol.E_SCOUT_OFFER)
	assert_true(bool(e.get("ui", false)), "offer 是 ui 事件")
	var p: Dictionary = e.get("p", {})
	assert_eq(str(p.get("offer_id", "")), str(o["id"]))
	assert_eq(str(p.get("text", "")), "你發現附近有：野兔 ×1")
	assert_eq(p.get("monsters", []), [ { "id": "m_rabbit", "name": "野兔", "n": 1 } ])
	assert_eq(float(p.get("ttl_s", 0)), ScoutSystem.OFFER_TTL_REAL_S)
	assert_eq(str(lastp(Protocol.E_SCOUT_FOUND).get("monsters", "")), "野兔 ×1")
	assert_eq(s().battle_id, 0, "還沒開戰")

func test_offer_text_groups_counts() -> void:
	if not game_ok():
		return
	make_char()
	var sc: ScoutSystem = host().scout
	assert_eq(sc.monsters_text(["m_rabbit", "m_rabbit", "m_wolf"]), "野兔 ×2、%s ×1" % host().monster_name("m_wolf"))
	assert_eq(sc.groups(["m_rabbit", "m_rabbit"]), [ { "id": "m_rabbit", "name": "野兔", "n": 2 } ])

func test_safe_room_look_has_no_offer_no_cooldown() -> void:
	if not game_ok():
		return
	make_char()
	goto(SAFE)
	for i in 3:
		_scout()
		assert_eq(evs(Protocol.E_LOOK).size(), 1, "印房間描述")
		assert_eq(evs(Protocol.E_SCOUT_OFFER).size(), 0, "安全的房間沒有提示")
		assert_eq(evs(Protocol.E_SCOUT_BUSY).size(), 0, "沒有冷卻")
		assert_eq(_cd(), 0.0)
	assert_true(_offer().is_empty())

func test_plain_look_in_wild_does_not_scout() -> void:
	if not game_ok():
		return
	make_char()
	goto(WILD)
	clear_events()
	ok("look")   # 客戶端自動補畫面的 look：不帶 scout
	assert_eq(evs(Protocol.E_SCOUT_OFFER).size(), 0)
	assert_true(_offer().is_empty())
	assert_eq(_cd(), 0.0)

# ---------------------------------------------------------------- 冷卻

func test_cooldown_in_wild_only_and_scaled() -> void:
	if not game_ok():
		return
	make_char()
	goto(WILD)
	_scout()
	assert_true(absf(_cd() - ScoutSystem.COOLDOWN_S) < 0.01, "cooldowns.scout 立刻開始：%f" % _cd())
	ws.advance(2.0)
	var first_id := str(_offer().get("id", ""))
	_scout()
	assert_eq(evs(Protocol.E_LOOK).size(), 1, "冷卻中照樣印房間描述")
	assert_eq(int(lastp(Protocol.E_SCOUT_BUSY).get("n", 0)), 4, "還要 4 秒")
	assert_eq(evs(Protocol.E_SCOUT_OFFER).size(), 0, "冷卻中不偵察")
	assert_eq(str(_offer().get("id", "")), first_id, "原本的提示還在")
	# 安全的房間：冷卻顯示為 0；回到野外：剩下的還在
	goto(SAFE)
	assert_eq(_cd(), 0.0, "安全的房間查看沒有冷卻")
	goto(WILD2)
	assert_true(absf(_cd() - 4.0) < 0.01, "回到野外繼續倒數：%f" % _cd())
	ws.advance(4.1)
	_scout()
	assert_eq(evs(Protocol.E_SCOUT_OFFER).size(), 1, "冷卻結束可以再偵察")
	# time_scale：剩餘秒數換成真實秒數
	ws.set_time_scale(2.0)
	ws.advance(ScoutSystem.COOLDOWN_S + 0.1)
	_scout()
	assert_true(absf(_cd() - ScoutSystem.COOLDOWN_S / 2.0) < 0.01, "×2 時真實 3 秒：%f" % _cd())

func test_new_scout_replaces_old_offer() -> void:
	if not game_ok():
		return
	make_char()
	goto(WILD)
	_scout()
	var old_id := str(_offer()["id"])
	ws.advance(ScoutSystem.COOLDOWN_S + 0.1)
	_scout()
	var new_id := str(_offer()["id"])
	assert_true(new_id != old_id, "新的提示")
	assert_eq(str(lastp(Protocol.E_SCOUT_CLOSED).get("offer_id", "")), old_id, "舊視窗收到 scout_closed")
	assert_eq(str(lastp(Protocol.E_SCOUT_CLOSED).get("why", "")), ScoutSystem.WHY_REPLACED)
	assert_eq(reason("scout_accept", { "offer_id": old_id }), "scout_gone")

# ---------------------------------------------------------------- 迎戰／離開

func test_accept_starts_encounter_battle() -> void:
	if not game_ok():
		return
	make_char()
	make_strong()
	goto(WILD)
	_scout()
	var id := str(_offer()["id"])
	clear_events()
	ok("scout_accept", { "offer_id": id })
	assert_true(s().battle_id != 0, "開戰")
	assert_true(_offer().is_empty(), "提示用掉了")
	assert_eq(cs.battle_state.get("kind", ""), "ENCOUNTER", "與踩地雷相同的戰鬥種類（同樣的獎勵）")
	var foes := 0
	for u in cs.battle_state.get("units", []):
		if int(u.get("side", 0)) == 1:
			foes += 1
			assert_eq(str(u.get("ref", "")), "m_rabbit", "怪物是主機擲的那一組")
	assert_eq(foes, 1)
	assert_eq(str(lastp(Protocol.E_SCOUT_ENGAGE).get("monsters", "")), "野兔")
	assert_eq(reason("scout_accept", { "offer_id": id }), "in_battle", "戰鬥中不能再迎戰")
	var res := drive_battle("fight")
	assert_false(res.is_empty(), "收到戰鬥結果")
	assert_eq(s().battle_id, 0, "打完")
	assert_true(evs(Protocol.E_BATTLE_REWARD).size() >= 1 or evs(Protocol.E_BATTLE_VICTORY).size() >= 1,
		"勝利有獎勵（同踩地雷）")

func test_accept_validation() -> void:
	if not game_ok():
		return
	make_char()
	goto(WILD)
	assert_eq(reason("scout_accept", { "offer_id": "sc_nothing" }), "scout_gone", "沒有提示")
	_scout()
	var id := str(_offer()["id"])
	assert_eq(reason("scout_accept", { "offer_id": "sc_forged" }), "scout_gone", "id 對不上")
	assert_false(_offer().is_empty(), "錯的 id 不影響原本的提示")
	ch().vitals["qi"] = 0
	assert_eq(reason("scout_accept", { "offer_id": id }), "scout_dead", "倒下的人不能迎戰")
	assert_eq(s().battle_id, 0)
	assert_eq(UiClient.reason_inline("scout_dead"), "你已經沒有力氣再打了。")
	assert_eq(UiClient.reason_inline("scout_gone"), "牠們已經不在附近了。")

func test_decline_clears_offer() -> void:
	if not game_ok():
		return
	make_char()
	goto(WILD)
	_scout()
	var id := str(_offer()["id"])
	clear_events()
	ok("scout_decline", { "offer_id": id })
	assert_true(_offer().is_empty())
	assert_eq(evs(Protocol.E_SCOUT_DECLINED).size(), 1)
	assert_eq(s().battle_id, 0)
	assert_eq(reason("scout_accept", { "offer_id": id }), "scout_gone")
	clear_events()
	ok("scout_decline", { "offer_id": id })   # 已經失效也回成功（視窗本來就要關）
	assert_eq(evs(Protocol.E_SCOUT_DECLINED).size(), 0, "對不上就不印")

func test_offer_expires() -> void:
	if not game_ok():
		return
	make_char()
	goto(WILD)
	_scout()
	var id := str(_offer()["id"])
	clear_events()
	ws.advance(ScoutSystem.OFFER_TTL_REAL_S - 1.0)
	assert_false(_offer().is_empty(), "還沒過期")
	ws.advance(1.5)
	assert_true(_offer().is_empty(), "tick 收回過期的提示")
	assert_eq(evs(Protocol.E_SCOUT_EXPIRED).size(), 1)
	assert_eq(str(lastp(Protocol.E_SCOUT_CLOSED).get("why", "")), ScoutSystem.WHY_EXPIRED)
	assert_eq(reason("scout_accept", { "offer_id": id }), "scout_gone")

func test_expiry_checked_on_accept_and_time_scale() -> void:
	if not game_ok():
		return
	make_char()
	goto(WILD)
	ws.set_time_scale(2.0)
	_scout()
	var o := _offer()
	assert_true(absf(float(o["expires_s"]) - host().now_s() - ScoutSystem.OFFER_TTL_REAL_S * 2.0) < 0.01,
		"有效時間是真實秒數（world_span）")
	# 不跑 tick，直接把世界時間撥過到期：迎戰時也要擋
	ws.world["world_time_s"] = float(o["expires_s"]) + 0.5
	assert_eq(reason("scout_accept", { "offer_id": str(o["id"]) }), "scout_expired")
	assert_true(_offer().is_empty())

func test_move_invalidates_offer() -> void:
	if not game_ok():
		return
	make_char()
	goto(WILD)
	_scout()
	var id := str(_offer()["id"])
	clear_events()
	ws.options["encounters_enabled"] = false   # 走路不踩地雷
	ok("move", { "dir": "W" })
	assert_eq(ch().location["room"], WILD2)
	assert_true(_offer().is_empty(), "換房即失效")
	assert_eq(str(lastp(Protocol.E_SCOUT_CLOSED).get("why", "")), ScoutSystem.WHY_MOVED)
	ok("move", { "dir": "E" })
	assert_eq(reason("scout_accept", { "offer_id": id }), "scout_gone", "走回原房也不能用舊提示")
	ws.options["encounters_enabled"] = true

func test_battle_and_logout_invalidate_offer() -> void:
	if not game_ok():
		return
	make_char()
	goto(WILD)
	_scout()
	start_battle(["m_rabbit"])   # 例如被別的事情拖進戰鬥
	assert_true(_offer().is_empty(), "進戰鬥即失效")
	assert_eq(str(lastp(Protocol.E_SCOUT_CLOSED).get("why", "")), ScoutSystem.WHY_BATTLE)
	# 離線：另一位玩家
	var p2 := add_player("偵察乙")
	goto_as(p2, WILD)
	var r := send_as(p2, "look", { "scout": true })
	assert_true(r.get("ok", false))
	var o2 := session_of(p2)
	assert_false(o2.scout_offer.is_empty())
	host().switch_out(o2)
	assert_true(o2.scout_offer.is_empty(), "換角／離線即失效")

func test_option_off_behaves_like_before() -> void:
	if not game_ok():
		return
	make_char()
	goto(WILD)
	ws.options["scout_enabled"] = false
	assert_false(ws.world_info()["scout_enabled"])
	for i in 2:
		_scout()
		assert_eq(evs(Protocol.E_LOOK).size(), 1, "照樣印房間描述")
		assert_eq(evs(Protocol.E_SCOUT_OFFER).size(), 0)
		assert_eq(evs(Protocol.E_SCOUT_BUSY).size(), 0)
		assert_eq(_cd(), 0.0, "沒有冷卻")
	# 有提示時關掉選項：收回
	ws.options["scout_enabled"] = true
	_scout()
	var id := str(_offer()["id"])
	ws.options["scout_enabled"] = false
	ws.advance(0.2)
	assert_true(_offer().is_empty())
	assert_eq(str(lastp(Protocol.E_SCOUT_CLOSED).get("why", "")), ScoutSystem.WHY_DISABLED)
	assert_eq(reason("scout_accept", { "offer_id": id }), "scout_gone")
	ws.options["scout_enabled"] = true

func test_admin_toggle() -> void:
	if not game_ok():
		return
	make_char()
	assert_has(AdminSystem.EDITABLE_KEYS, "scout_enabled")
	ok("server_opts_get")
	var found := false
	for row in lastp(Protocol.E_SERVER_OPTIONS).get("editable", []):
		if str(row.get("key", "")) == "scout_enabled":
			found = true
			assert_eq(str(row.get("value", "")), "true", "預設開")
	assert_true(found, "伺服器設定面板有這一列")
	ok("server_opts_set", { "key": "scout_enabled", "value": "false" })
	assert_eq(ws.options["scout_enabled"], false)
	assert_false(cs.world_info.get("scout_enabled", true), "world_info_changed 送到客戶端")
	assert_false(UiClient.scout_enabled())
	ok("server_opts_set", { "key": "scout_enabled", "value": "true" })
	assert_true(UiClient.scout_enabled())

# ---------------------------------------------------------------- 組隊

func test_accept_pulls_idle_teammates_like_encounter() -> void:
	if not game_ok():
		return
	make_char("偵察隊長")
	var p2 := add_player("偵察隊員")
	var p3 := add_player("隔壁隊員")
	for p in [p2, p3]:
		ok("party_invite", { "target": _cid(p) })
		assert_true(send_as(p, "party_reply", { "from": str(ch().id), "accept": true }).get("ok", false))
	goto(WILD)
	goto_as(p2, WILD)
	goto_as(p3, WILD2)
	_scout()
	ok("scout_accept", { "offer_id": str(_offer()["id"]) })
	var bid := s().battle_id
	assert_true(bid != 0)
	assert_eq(session_of(p2).battle_id, bid, "同房閒置隊友一起入場")
	assert_eq(battle_open_for(p2).get("kind", ""), "ENCOUNTER")
	assert_eq(session_of(p3).battle_id, 0, "不同房的不拉")
	assert_eq(evs_for(p2, Protocol.E_SCOUT_OFFER).size(), 0, "提示只給按查看的人")
