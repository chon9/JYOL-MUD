extends "res://tests/unit/test_pk_world_base.gd"
## M3D_PLAN §2.5（WP-LAW）：NPC 賞金獵人——只在 WILD、名單上的人、冷卻一個時辰、三階分級、警告倒數內離開＝逃掉、
## 倒數結束開追擊戰（不能逃）、死了 PK值 −1、打贏沒有獎勵（no_rewards）、選項關、新手不追。

func before_each() -> void:
	world_name = "w_m3d_hunters"
	super.before_each()

func law():
	return host().get("law")

func _deps() -> bool:
	if not deps_ok():
		return false
	if law() == null:
		fail("LawSystem 沒有載入")
		return false
	return true

func _listed(peer: int, pk := 5, xp := 5000) -> void:
	var c = chr(peer)
	c.combat_xp = xp
	c.pk = pk
	c.pk_stamp_s = c.online_s
	law().refresh_board()

## 直接觸發（不經走路）：在 room 呼叫 on_enter_room
func _enter(peer: int, room: String) -> void:
	goto_p(peer, room)
	law().on_enter_room(sess(peer), "", room)

func test_tiers_pure() -> void:
	assert_eq(BountyRules.hunter_tier(500), 1)
	assert_eq(BountyRules.hunter_tier(19999), 1)
	assert_eq(BountyRules.hunter_tier(20000), 2)
	assert_eq(BountyRules.hunter_tier(99999), 2)
	assert_eq(BountyRules.hunter_tier(100000), 3)
	assert_eq(BountyRules.hunter_monster(1), "m_law_hunter_1")
	assert_eq(BountyRules.hunter_monster(3), "m_law_hunter_3")
	for mid in BountyRules.HUNTER_MONSTERS:
		assert_true(tables().get("monsters", {}).has(mid), mid)
		assert_true(bool(tables()["monsters"].get(mid, {}).get("no_rewards", false)), mid + " no_rewards")

func test_only_wild_listed_and_cooldown() -> void:
	if not _deps():
		return
	law().hunter_chance_pct = 100
	var a := add("惡甲")
	_listed(a)
	_enter(a, "xx_square")
	assert_true(evs_p(a, "law_hunter_warn").is_empty(), "city: no hunter")
	_enter(a, "xw_road")
	var w := lastp_p(a, "law_hunter_warn")
	assert_eq(str(w.get("wid", "")), "law_hunter", "warned in the wild")
	assert_eq(int(w.get("warn_s", -1)), int(ws.options.get("villain_warn_s", 3)))
	assert_false(lastp_p(a, "law_hunter_coming").is_empty(), "text warning too")
	# 倒數內離開 → 逃掉
	goto_p(a, "xw_grass")
	ws.advance(0.2)
	assert_false(lastp_p(a, "law_hunter_escaped").is_empty(), "escaped by leaving")
	assert_eq(sess(a).battle_id, 0)
	# 冷卻中：再進野外不會再觸發
	clear_events_for(a)
	_enter(a, "xw_road")
	assert_true(evs_p(a, "law_hunter_warn").is_empty(), "cooldown (one shichen)")
	# 冷卻過了 → 再觸發
	LawSystem.law_ext(chr(a))["hunt_cd_s"] = 0.0
	_enter(a, "xw_road")
	assert_false(evs_p(a, "law_hunter_warn").is_empty(), "after cooldown")

func test_not_listed_or_newbie_or_off() -> void:
	if not _deps():
		return
	law().hunter_chance_pct = 100
	var a := add("良民甲")
	_enter(a, "xw_road")
	assert_true(evs_p(a, "law_hunter_warn").is_empty(), "not listed")
	var n := add("新手乙")
	_listed(n, 9, 100)
	assert_false(law().is_listed(cid(n)), "newbie never listed")
	_enter(n, "xw_road")
	assert_true(evs_p(n, "law_hunter_warn").is_empty(), "newbie never hunted")
	var b := add("惡丙")
	_listed(b)
	ws.options["bounty_hunters"] = false
	_enter(b, "xw_road")
	assert_true(evs_p(b, "law_hunter_warn").is_empty(), "option off")
	ws.options["bounty_hunters"] = true

func test_countdown_starts_chase_by_tier_and_death_lowers_pk() -> void:
	if not _deps():
		return
	law().hunter_chance_pct = 100
	var a := add("惡甲")
	_listed(a, 5, 30000)
	_enter(a, "xw_road")
	var warn_s := float(ws.options.get("villain_warn_s", 3))
	ws.advance(warn_s * float(ws.time_scale) + 0.5)
	var bid := sess(a).battle_id
	assert_true(bid != 0, "chase started after the countdown")
	assert_eq(active_kind(a), "CHASE")
	assert_true(law().is_hunter_bid(bid))
	var b = host().battles.active[bid]["battle"]
	var refs: Array = []
	for u in b.units:
		if int(u.side) == 1:
			refs.append(str(u.spec.get("ref", "")))
	assert_eq(refs, ["m_law_hunter_2"], "tier 2 for 30k combat xp")
	assert_true(bool(b.opts.get("no_flee", false)), "chase: no flee")
	make_weak_p(a)
	var settled := FileAccess.get_file_as_string("res://server/battle_system.gd").contains("m3d_battle_settled")
	drive_bid(bid, { a: "defend" })
	if not settled:
		# WP-EVENTS 的結算鉤子還沒合併：照鉤子的參數自己呼叫一次（本地假）
		law().on_battle_settled(sess(a), chr(a), { "kind": "CHASE", "bid": bid, "died": true, "room": "xw_road" })
	assert_eq(int(chr(a).pk_value()), 4, "killed by a bounty hunter: PK −1")

func test_settle_rules_direct() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	var c = chr(a)
	c.pk = 3
	c.pk_stamp_s = c.online_s
	# 守城官兵殺死 → −1
	law().on_battle_settled(sess(a), c, { "kind": "GUARD", "bid": 999, "died": true })
	assert_eq(int(c.pk_value()), 2, "guard kill: PK −1")
	# 一般追擊戰（不是獵人）→ 不變
	law().on_battle_settled(sess(a), c, { "kind": "CHASE", "bid": 998, "died": true })
	assert_eq(int(c.pk_value()), 2, "other chase: unchanged")
	# 沒死 → 不變
	law().on_battle_settled(sess(a), c, { "kind": "GUARD", "bid": 997, "died": false })
	assert_eq(int(c.pk_value()), 2)
	# 最低 0
	c.pk = 0
	law().on_battle_settled(sess(a), c, { "kind": "GUARD", "bid": 996, "died": true })
	assert_eq(int(c.pk_value()), 0, "floor 0")

func test_chance_roll_respected() -> void:
	if not _deps():
		return
	law().hunter_chance_pct = 0
	var a := add("惡甲")
	_listed(a)
	for i in 20:
		_enter(a, "xw_road")
	assert_true(evs_p(a, "law_hunter_warn").is_empty(), "0% never triggers")

## M3d 審查：獵人追擊戰被拉進來的隊友死了不減 PK值（只有被追的目標 −1）
func test_pulled_teammate_no_pk_drop() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	var c := add("同伴丙")
	chr(c).pk = 2
	chr(c).pk_stamp_s = chr(c).online_s
	chr(a).pk = 5
	chr(a).pk_stamp_s = chr(a).online_s
	law()._hunter_bids[4242] = { "since_s": 0.0, "target": cid(a) }
	law().on_battle_settled(sess(c), chr(c), { "kind": "CHASE", "bid": 4242, "died": true })
	assert_eq(int(chr(c).pk_value()), 2, "teammate: unchanged")
	law().on_battle_settled(sess(a), chr(a), { "kind": "CHASE", "bid": 4242, "died": true })
	assert_eq(int(chr(a).pk_value()), 4, "target: −1")

## M3d 審查（第 3 輪）：獵人依目標實戰決定數值——校準點（各列 combat_xp_ref）照資料列、兩點之間單調內插、
## 低於 2 萬往下縮、高於 20 萬往上長；主機的追擊戰真的帶上縮放後的數值
func test_hunter_scales_with_target_xp() -> void:
	var t: Dictionary = host().tables if host() != null else {}
	if not t.get("monsters", {}).has("m_law_hunter_3"):
		return
	var qi_at := func(xp: int) -> int:
		var sp := Encounter.monster_spec(BountyRules.hunter_monster(BountyRules.hunter_tier(xp)), t)
		BountyRules.apply_hunter_xp(sp, xp, t)
		return int(sp.qi_max)
	var lv_at := func(xp: int) -> int:
		var sp := Encounter.monster_spec(BountyRules.hunter_monster(BountyRules.hunter_tier(xp)), t)
		BountyRules.apply_hunter_xp(sp, xp, t)
		return int(sp.skills.get("basic_dodge", 0))
	for mid in BountyRules.HUNTER_MONSTERS:
		var ref := int(t.monsters[mid].combat_xp_ref)
		var raw := Encounter.monster_spec(mid, t)
		var sp := Encounter.monster_spec(mid, t)
		BountyRules.apply_hunter_xp(sp, ref, t)
		assert_eq(int(sp.qi_max), int(raw.qi_max), "%s：在自己的校準點不變" % mid)
		assert_eq(int(sp.skills.basic_dodge), int(raw.skills.basic_dodge), "%s：武學不變" % mid)
	var prev := 0
	for xp in [500, 5000, 19999, 20001, 50000, 99999, 100001, 200000, 500000, 1000000]:
		var q: int = qi_at.call(xp)
		assert_true(q >= prev, "氣隨目標實戰單調不減（%d：%d ≥ %d）" % [xp, q, prev])
		prev = q
	assert_true(int(lv_at.call(500)) < int(lv_at.call(19999)), "1 階底端比頂端弱")
	assert_true(int(lv_at.call(1000000)) > int(lv_at.call(200000)), "20 萬以上繼續長")

func test_chase_uses_scaled_hunter() -> void:
	if not _deps():
		return
	law().hunter_chance_pct = 100
	var a := add("惡乙")
	_listed(a, 5, 600)
	var bid := int(law().start_hunt(sess(a), BountyRules.hunter_tier(600)))
	assert_true(bid != 0)
	var b = host().battles.active[bid]["battle"]
	var raw := Encounter.monster_spec("m_law_hunter_1", host().tables)
	for u in b.units:
		if int(u.side) == 1:
			assert_true(int(u.qi_max()) < int(raw.qi_max), "實戰 600 的目標：獵人的氣低於 1 階校準值（%d < %d）" % [u.qi_max(), raw.qi_max])
