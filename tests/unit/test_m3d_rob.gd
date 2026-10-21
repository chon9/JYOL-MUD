extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §5.2.2–5.2.4、§10.1（WP-EVENTS）：劫鏢。條件、開戰即給劫鏢標記、劫鏢方不能逃、鏢單位倒下＝劫鏢成功、
## 存活者平分 80%、押鏢失敗、劫鏢算強制 PK（PK值 +1）、守城官兵（WP-LAW 讀 rob_marked）、朋友互劫合計只減不增。

const Q := "q_ev_jb_xx_dl_huo"
const VALUE := 3200
const WILD := "xw_grass"

var robber := 0

func before_each() -> void:
	world_name = "w_m3d_rob"
	super.before_each()

## 本機玩家押鏢（在野外房間），遠端玩家 robber 實戰 10 萬
func _setup(robber_xp := 100000) -> bool:
	if not game_ok() or host().get("jiebiao") == null or GameData.tables.get("quests", {}).get(Q, {}).is_empty():
		fail("劫鏢系統或資料不在")
		return false
	if make_char("押鏢甲") == null:
		return false
	make_strong()
	var c = ch()
	c.combat_xp = 100000
	c.fame = 100
	c.lilian = 100
	c.money = 20000
	goto("xx_biaoju")
	if not assert_true(send("quest_accept", { "npc": "n_ev_jb_xx", "quest": Q }).get("ok", false), "接鏢"):
		return false
	JiebiaoSystem.active_of(ch())["rooms_since"] = -100   # 測試：這一段不要遇上特殊地雷
	goto(WILD)
	robber = add_player("劫鏢乙")
	var rs := session_of(robber)
	rs.character.combat_xp = robber_xp
	rs.character.money = 0
	goto_as(robber, WILD)
	return true

func _rob() -> Dictionary:
	return send_as(robber, "rob_escort", { "target_char": str(ch().id) })

func _rob_entry() -> Dictionary:
	var bid := s().battle_id
	return host().battles.active.get(bid, {})

func test_rob_conditions() -> void:
	if not _setup(99999):
		return
	assert_eq(reason_as(robber, "rob_escort", { "target_char": str(ch().id) }), "rob_xp", "實戰不到 10 萬不能劫鏢")
	session_of(robber).character.combat_xp = 100000
	assert_eq(reason_as(robber, "rob_escort", { "target_char": str(session_of(robber).character.id) }), "bad_target", "不能劫自己")
	assert_eq(reason_as(robber, "rob_escort", { "target_char": "c_nobody" }), "target_not_here")
	# 城裡不能動手
	goto("xx_square")
	goto_as(robber, "xx_square")
	assert_eq(reason_as(robber, "rob_escort", { "target_char": str(ch().id) }), "pk_not_allowed_here", "城裡不能劫")
	goto(WILD)
	goto_as(robber, WILD)
	# 同隊不能劫
	var pr = host().get("party")
	if pr != null:
		var inv: Dictionary = pr.invite(session_of(robber), str(ch().id))
		if inv.get("ok", false):
			var rep: Dictionary = pr.reply(s(), str(session_of(robber).character.id), true)
			if rep.get("ok", false):
				assert_eq(reason_as(robber, "rob_escort", { "target_char": str(ch().id) }), "rob_same_party", "同隊不能劫")
				pr.leave(s())
	# 主機關掉 PK
	ws.options["pk_mode"] = "OFF"
	assert_eq(reason_as(robber, "rob_escort", { "target_char": str(ch().id) }), "pk_disabled")
	ws.options["pk_mode"] = "CLASSIC"
	# 沒押鏢的人不能劫
	var other := add_player("路人丙")
	goto_as(other, WILD)
	assert_eq(reason_as(robber, "rob_escort", { "target_char": str(session_of(other).character.id) }), "rob_no_escort")

func test_rob_success_share_and_penalties() -> void:
	if not _setup():
		return
	var rch = session_of(robber).character
	var pk0 := int(rch.pk_value())
	var r := _rob()
	assert_true(r.get("ok", false), "劫鏢開戰：%s" % str(r))
	# 開戰當下就有劫鏢標記（世界秒 1 小時）
	assert_true(JiebiaoRules.rob_marked(rch.ext, host().now_s()), "標記立即存在")
	var until := float(rch.ext["jiebiao"]["rob_until_s"])
	assert_true(absf(until - host().now_s() - 3600.0) < 1.0, "標記 1 小時")
	var tags: Dictionary = host().jiebiao.player_tags(s(), session_of(robber))
	assert_has(tags.get("tags", []), "劫鏢", "頭上標「劫鏢」")
	if host().pk != null and host().pk.has_method("_law_guard_count"):
		assert_eq(int(host().pk._law_guard_count(rch, 0)), MoralityPk.GUARDS_PK, "守城官兵照 PK > 3 的人數（2 名）")
	var entry := _rob_entry()
	assert_eq(str(entry.get("kind", "")), "ROB")
	var b = entry["battle"]
	var cart = b.unit(int(entry.get("rob_uid", 0)))
	assert_true(cart != null, "side 1 有鏢單位")
	if cart == null:
		return
	assert_eq(cart.side, 1)
	assert_eq(str(cart.spec.get("ref", "")), "m_ev_jb_cart", "送貨鏢 → 鏢車")
	# 劫鏢方不能逃（烙跑鞋也不行：在 BattleSystem.submit 就擋）
	assert_eq(reason_as(robber, "battle_cmd", { "battle_id": b.id, "cmd": "FLEE" }), "no_flee", "劫鏢方 FLEE → no_flee")
	assert_eq(reason_as(robber, "battle_cmd", { "battle_id": b.id, "cmd": "QING", "mode": "ESCAPE" }), "no_flee", "QING ESCAPE → no_flee")
	var st: Dictionary = host().battles._state_for(entry, robber)
	assert_true(bool(st.get("no_flee", false)), "劫鏢方的開場快照 no_flee")
	var st2: Dictionary = host().battles._state_for(entry, 1)
	assert_false(bool(st2.get("no_flee", false)), "押鏢方可以逃（逃了就失敗）")
	# 打掉鏢車 → 劫鏢成功，戰鬥當場結束
	var me = null
	for u in b.units:
		if u.is_player() and u.side == 0:
			me = u
	BattleRules.kill(b, cart, me)
	ws.advance(0.2)
	assert_eq(s().battle_id, 0, "鏢車倒下 → 戰鬥結束")
	assert_eq(int(rch.money), int(floor(VALUE * 0.8)), "存活劫鏢者分 80%（2560）")
	assert_true(JiebiaoSystem.active_of(ch()).is_empty(), "押鏢方失敗")
	assert_false(QuestState.is_active(ch().quests, Q))
	assert_eq(int(ch().money), 20000 - VALUE, "押金沒收")
	assert_eq(str(lastp("ev_jb_failed").get("why", "")), "robbed")
	assert_eq(int(rch.pk_value()), pk0 + 1, "劫鏢算強制 PK：PK值 +1")
	assert_false(evs_for(robber, "ev_jb_robbed").is_empty(), "劫鏢者收到 ev_jb_robbed")
	assert_false(evs("ev_jb_robbed").is_empty(), "押鏢者收到 ev_jb_robbed")
	assert_eq(int(evs_for(robber, "ev_jb_robbed")[0]["p"]["share"]), 2560)
	# 朋友互劫：A 付押金 V、B 拿 0.8V → 合計 −0.2V
	var total := int(ch().money) + int(rch.money)
	assert_eq(total, 20000 - VALUE + 2560, "兩人合計少了 0.2 × 鏢價（不生錢）")
	assert_true(JiebiaoRules.friends_net(VALUE, 1) < 0)
	assert_true(JiebiaoRules.friends_net(8000, 3) < 0)
	# 標記到期
	assert_false(JiebiaoRules.rob_marked(rch.ext, host().now_s() + 3601.0), "1 小時後標記消失")

func test_rob_fails_when_robbers_all_down() -> void:
	if not _setup():
		return
	var rch = session_of(robber).character
	assert_true(_rob().get("ok", false))
	var entry := _rob_entry()
	var b = entry["battle"]
	var robber_unit = null
	var me = null
	for u in b.units:
		if u.is_player() and u.side == 0:
			robber_unit = u
		elif u.is_player() and u.side == 1:
			me = u
	BattleRules.kill(b, robber_unit, me)
	ws.advance(0.3)
	for i in 50:
		if s().battle_id == 0:
			break
		ws.advance(0.5)
	assert_eq(s().battle_id, 0, "劫鏢方全倒 → 結束")
	assert_false(JiebiaoSystem.active_of(ch()).is_empty(), "鏢保住了，繼續走")
	assert_true(QuestState.is_active(ch().quests, Q))
	assert_eq(int(rch.money), 0, "沒分到錢")
	assert_true(JiebiaoRules.rob_marked(rch.ext, host().now_s()), "失敗也有標記（開戰當下給）")
	assert_false(evs("ev_jb_rob_repelled").is_empty(), "ev_jb_rob_repelled")

func test_rob_share_math() -> void:
	assert_eq(JiebiaoRules.rob_share(3200, 1), 2560)
	assert_eq(JiebiaoRules.rob_share(3200, 2), 1280)
	assert_eq(JiebiaoRules.rob_share(8000, 3), 2133)
	assert_eq(JiebiaoRules.rob_share(8000, 0), 0, "沒人活著 → 0")
	assert_false(JiebiaoRules.rob_marked({}, 0.0))
	assert_true(JiebiaoRules.rob_marked({ "jiebiao": { "rob_until_s": 100.0 } }, 50.0))
	assert_false(JiebiaoRules.rob_marked({ "jiebiao": { "rob_until_s": 100.0 } }, 100.0))

## M3d 審查：劫鏢只拉「自己也能劫鏢」的隊友——新手、實戰不到 10 萬、持照者都不拉，也不會被扣標記與 PK值
func test_rob_pulls_only_qualified_teammates() -> void:
	if not _setup():
		return
	var pr = host().get("party")
	if pr == null:
		return
	var newbie := add_player("新手丁")
	var mid := add_player("中手戊")
	var lic := add_player("持照己")
	var vet := add_player("老手庚")
	session_of(newbie).character.combat_xp = 10
	session_of(mid).character.combat_xp = 50000
	session_of(lic).character.combat_xp = 200000
	LawSystem.law_ext(session_of(lic).character)["license"] = true
	session_of(vet).character.combat_xp = 200000
	for p in [newbie, mid, lic, vet]:
		goto_as(p, WILD)
		var inv: Dictionary = pr.invite(session_of(robber), str(session_of(p).character.id))
		assert_true(inv.get("ok", false), "invite %s" % str(inv))
		assert_true(pr.reply(session_of(p), str(session_of(robber).character.id), true).get("ok", false))
	var r := _rob()
	assert_true(r.get("ok", false), "劫鏢開戰：%s" % str(r))
	assert_eq(session_of(newbie).battle_id, 0, "新手不拉")
	assert_eq(session_of(mid).battle_id, 0, "實戰不到 10 萬不拉")
	assert_eq(session_of(lic).battle_id, 0, "持照者不拉")
	assert_true(session_of(vet).battle_id != 0, "夠格的老手照拉")
	for p in [newbie, mid, lic]:
		assert_false(JiebiaoRules.rob_marked(session_of(p).character.ext, host().now_s()), "沒被拉的人沒有劫鏢標記")
	assert_true(JiebiaoRules.rob_marked(session_of(vet).character.ext, host().now_s()))

## M3d 審查（第 3 輪）：押著危險鏢的人不能去劫別人的鏢；劫鏢戰裡死掉（或逃走）的其他玩家，自己身上的危險鏢一樣失敗
func test_rob_escort_carrier_cannot_rob() -> void:
	if not _setup():
		return
	var rch = session_of(robber).character
	JiebiaoSystem.data_of(rch)["active"] = { "quest": "q_ev_jb_dl_xx_huo", "value": 3200, "kind": "huo", "from": "dl", "to": "xx", "since_s": 0.0 }
	assert_eq(reason_as(robber, "rob_escort", { "target_char": str(ch().id) }), "jb_active", "自己押鏢中不能劫鏢")

func test_rob_dead_robber_loses_own_escort() -> void:
	if not _setup():
		return
	var rch = session_of(robber).character
	assert_true(_rob().get("ok", false))
	# 開戰之後才有鏢（舊存檔、中途加入的保險）：死在劫鏢戰 → 自己的鏢失敗
	JiebiaoSystem.data_of(rch)["active"] = { "quest": "q_ev_jb_dl_xx_huo", "value": 3200, "kind": "huo", "from": "dl", "to": "xx", "since_s": 0.0 }
	var entry := _rob_entry()
	var b = entry["battle"]
	var robber_unit = null
	var me = null
	for u in b.units:
		if u.is_player() and u.side == 0:
			robber_unit = u
		elif u.is_player() and u.side == 1:
			me = u
	BattleRules.kill(b, robber_unit, me)
	for i in 50:
		if s().battle_id == 0:
			break
		ws.advance(0.5)
	assert_eq(s().battle_id, 0, "結束")
	assert_true(JiebiaoSystem.active_of(rch).is_empty(), "劫鏢者死了 → 他自己的危險鏢失敗（不能再送達拿兩倍）")
	assert_false(JiebiaoSystem.active_of(ch()).is_empty(), "押鏢方的鏢照走")

## M3d 審查第三輪：同房隊友自己押著危險鏢 → 不拉進劫鏢戰（不會被扣劫鏢標記、PK值，也不會一邊押鏢一邊分贓）
func test_rob_skips_teammate_carrying_escort() -> void:
	if not _setup():
		return
	var pr = host().get("party")
	if pr == null:
		return
	var carrier := add_player("押鏢隊友辛")
	var vet := add_player("老手壬")
	for p in [carrier, vet]:
		session_of(p).character.combat_xp = 200000
		goto_as(p, WILD)
		assert_true(pr.invite(session_of(robber), str(session_of(p).character.id)).get("ok", false))
		assert_true(pr.reply(session_of(p), str(session_of(robber).character.id), true).get("ok", false))
	var cch = session_of(carrier).character
	JiebiaoSystem.data_of(cch)["active"] = { "quest": "q_ev_jb_dl_xx_huo", "value": 3200, "kind": "huo", "from": "dl", "to": "xx", "since_s": 0.0 }
	var pk0 := int(cch.pk_value())
	var r := _rob()
	assert_true(r.get("ok", false), "劫鏢開戰：%s" % str(r))
	assert_eq(session_of(carrier).battle_id, 0, "押著鏢的隊友不拉")
	assert_false(JiebiaoRules.rob_marked(cch.ext, host().now_s()), "沒有劫鏢標記")
	assert_eq(int(cch.pk_value()), pk0, "PK值 不變")
	assert_true(session_of(vet).battle_id != 0, "其他夠格的隊友照拉")
