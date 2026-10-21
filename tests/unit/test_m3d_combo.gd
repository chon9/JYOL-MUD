extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §3.3、§10.1（WP-COMBAT）：合體技系統（1.0B）——
## 建立默契（請求、同意、拒絕、失效）、取消、培養感情、兩日扣點只在兩人同時在線、玉女素心劍法的修練條件逐條、
## 戰鬥中 3 秒窗內觸發與窗外不觸發、成功率邊界、配合度增加；1.0A-only 世界 era_locked。
## 另含烙跑鞋與夜明珠的資料列、to_combatant 的 flee_anywhere／combo。

const H := preload("res://tests/unit/test_battle_helpers.gd")

# ---------------------------------------------------------------- 戰鬥（純邏輯）

## 測試用的合體武功（拳腳，免兵器）
static func _ctables() -> Dictionary:
	var t: Dictionary = H.tables().duplicate(true)
	t["martial_arts"]["t_combo"] = { "id": "t_combo", "name": "測試合璧", "sect_id": "", "category": "FIST",
		"base_skill": "basic_fist", "difficulty": 1.0, "tier": "QUEST", "monster_only": false, "requires": [],
		"combo": { "group": "tc", "pair": [{ "gender": "M", "art": "t_combo", "min": 1 }, { "gender": "F", "art": "t_combo", "min": 1 }],
			"moqi_min": 20 },
		"moves": [{ "id": "tc_1", "name": "合擊", "unlock_level": 1, "power": 40, "range": 1, "aoe": "SINGLE",
			"cost_inner": 0, "cost_jing": 0, "status": "", "status_chance": 0.0, "flavor": "move_fist_basic" }] }
	return t

## A（uid 1，peer 1，ch_a）、B（uid 2，peer 2，ch_b）、木人（uid 3）；A、B 都在木人旁邊
static func _cb(seed_v: int, moqi := 100, b_partner := "ch_a") -> Battle:
	var common := { "skills": { "t_combo": 50, "basic_fist": 50 }, "arts": ["t_combo"], "attrs": { "agi": 60 },
		"qi": 100000, "qi_max": 100000 }
	var a := H.player_spec(common)
	a["ref"] = "ch_a"
	a["char_id"] = "ch_a"
	a["gender"] = "M"
	a["combo"] = { "partner_char": "ch_b", "moqi": moqi }
	var bb := H.ally_spec(2, common)
	bb["ref"] = "ch_b"
	bb["char_id"] = "ch_b"
	bb["gender"] = "F"
	bb["combo"] = { "partner_char": b_partner, "moqi": moqi }
	var b := Battle.new(7, seed_v, H.default_opts())
	for sp in [a, bb, H.monster("m_dummy")]:
		b.add_unit(sp)
	b.start(_ctables())
	b.unit(1).pos = Vector2i(4, 3)
	b.unit(2).pos = Vector2i(5, 4)
	b.unit(3).pos = Vector2i(5, 3)
	return b

static func _art(b: Battle, uid: int) -> Dictionary:
	return H.do_cmd(b, uid, { "cmd": "ART", "art": "t_combo", "move": "tc_1", "power_tenths": 10, "target": [5, 3] }, _ctables())

## B 先出、A 在 dt 秒後出；回傳 A 那一下的事件
static func _pair_hit(b: Battle, dt: float) -> Array:
	b.tick_no = 100
	_art(b, 2)
	b.tick_no = 100 + roundi(dt / Battle.TICK)
	return _art(b, 1).events

func test_chance_bounds() -> void:
	assert_true(absf(ComboRules.chance(0) - 0.20) < 0.0001)
	assert_true(absf(ComboRules.chance(50) - 0.375) < 0.0001)
	assert_true(absf(ComboRules.chance(100) - 0.55) < 0.0001, "上限 0.55（M3d 審查：默契 100 也要留在 +10–25% 帶）")
	assert_true(absf(ComboRules.chance(200) - 0.55) < 0.0001)
	assert_eq(ComboRules.COMBO_WINDOW_S, 3.0, "3 秒【已證實】")

func test_window_inside_triggers_and_outside_never() -> void:
	var inside := 0
	var outside := 0
	for sd in range(1, 301):
		var b := _cb(sd, 100)
		if not H.find(_pair_hit(b, 2.0), "battle_combo").is_empty():
			inside += 1
		var b2 := _cb(sd, 100)
		outside += H.find(_pair_hit(b2, 3.1), "battle_combo").size()
	assert_eq(outside, 0, "3.1 秒：窗外不觸發")
	var rate := inside / 300.0
	assert_true(rate >= 0.45 and rate <= 0.65, "默契 100 → 約 55%%（%.2f）" % rate)

func test_rate_at_zero_moqi() -> void:
	var n := 0
	for sd in range(1, 601):
		if not H.find(_pair_hit(_cb(sd, 0), 1.0), "battle_combo").is_empty():
			n += 1
	var rate := n / 600.0
	assert_true(rate >= 0.15 and rate <= 0.25, "默契 0 → 約 20%%（%.3f）" % rate)

func test_success_damage_and_bookkeeping() -> void:
	for sd in range(1, 200):
		var b := _cb(sd, 100)
		b.tick_no = 100
		var e1: Array = _art(b, 2).events
		var mark_b: Dictionary = b.unit(2).combo_mark.duplicate()
		var dealt_b := int(mark_b.get("dmg", 0))
		b.tick_no = 110
		var dealt_a0 := b.unit(1).dmg_dealt
		var ev: Array = _art(b, 1).events
		var cb := H.find(ev, "battle_combo")
		if cb.is_empty():
			continue
		var dealt_a := b.unit(1).dmg_dealt - dealt_a0 - int(cb[0].p.dmg)
		assert_eq(int(cb[0].p.dmg), maxi(1, roundi((dealt_a + dealt_b) * ComboRules.COMBO_BONUS)), "兩招傷害和 × 0.5")
		assert_eq(str(cb[0].p.art_name), "測試合璧")
		assert_eq(int(cb[0].p.def_uid), 3)
		assert_eq(int(cb[0].p.def_qi), b.unit(3).qi, "目標的氣")
		assert_true(b.unit(1).combo_mark.is_empty() and b.unit(2).combo_mark.is_empty(), "成功後兩人的記號都清掉")
		assert_eq([b.unit(1).combo_hits, b.unit(2).combo_hits], [1, 1])
		assert_eq(b.unit(1).combo_with, ["ch_b"])
		assert_eq(b.unit(2).combo_with, ["ch_a"])
		var oc: Dictionary = b.outcome().units[1]
		assert_eq(int(oc.combo_hits), 1, "outcome 帶 combo_hits")
		assert_true(int(oc.dmg_dealt) > 0 and int(oc.hits_landed) >= 1, "outcome 帶 dmg_dealt、hits_landed")
		assert_eq(e1.size() > 0, true)
		return
	fail("199 個種子都沒有成功的合體一擊")

func test_failure_clears_only_partner_mark() -> void:
	for sd in range(1, 200):
		var b := _cb(sd, 0)
		var ev := _pair_hit(b, 1.0)
		if not H.find(ev, "battle_combo").is_empty():
			continue
		assert_true(b.unit(2).combo_mark.is_empty(), "失敗：夥伴的記號清掉")
		assert_false(b.unit(1).combo_mark.is_empty(), "自己的記號保留（給夥伴下一招機會）")
		return
	fail("找不到失敗的種子")

func test_needs_matching_partner() -> void:
	var hits := 0
	for sd in range(1, 101):
		var b := _cb(sd, 100)
		b.unit(1).spec["combo"] = { "partner_char": "ch_x", "moqi": 100 }
		hits += H.find(_pair_hit(b, 1.0), "battle_combo").size()
	assert_eq(hits, 0, "夥伴不是同一場的那個人 → 不觸發")
	# 敵方同名單位不算
	var b2 := _cb(3, 100)
	b2.unit(2).side = 1
	assert_eq(ComboRules.partner_unit(b2, b2.unit(1)), null, "不同邊")

## M3d 審查：合體武功兩人同使——夥伴不在陣上（或倒下）不能出招，AI 也不選
func test_combo_art_needs_partner_on_field() -> void:
	var b := _cb(5, 100)
	b.unit(1).spec["combo"] = { "partner_char": "ch_x", "moqi": 100 }
	var r := H.do_cmd(b, 1, { "cmd": "ART", "art": "t_combo", "move": "tc_1", "power_tenths": 10, "target": [5, 3] }, _ctables())
	assert_eq(str(r.err), "combo_partner_absent", "沒有夥伴同場")
	for m in BattleAI.usable_moves(b.unit(1), _ctables(), b):
		assert_true(str(m.art) != "t_combo", "AI 不選合體武功")
	var b3 := _cb(6, 100)
	var r3 := H.do_cmd(b3, 1, { "cmd": "ART", "art": "t_combo", "move": "tc_1", "power_tenths": 10, "target": [5, 3] }, _ctables())
	assert_eq(str(r3.err), "", "夥伴同場 → 可以出")
	b3.unit(2).state = BattleUnit.DEAD
	var r4 := H.do_cmd(b3, 1, { "cmd": "ART", "art": "t_combo", "move": "tc_1", "power_tenths": 10, "target": [5, 3] }, _ctables())
	assert_eq(str(r4.err), "combo_partner_absent", "夥伴倒下")

# ---------------------------------------------------------------- 修練條件（純邏輯）

func test_ready_reason_order() -> void:
	var row: Dictionary = tables()["martial_arts"]["gm_suxin"]
	var me := { "gender": "M", "skills": { "qz_jianfa": 60 }, "sect_skill": 30 }
	var cc := { "partner": "x", "partner_here": true, "same_party": true, "partner_gender": "F",
		"partner_skills": { "gm_yunu_jian": 60 }, "partner_sect_skill": 30, "moqi": 20 }
	assert_eq(ComboRules.ready_reason(row, me, cc), "", "全部符合")
	assert_eq(ComboRules.ready_reason(row, me, {}), "combo_need_partner")
	assert_eq(ComboRules.ready_reason(row, me, { "partner": "" }), "combo_need_partner")
	var c2 := cc.duplicate()
	c2["partner_here"] = false
	assert_eq(ComboRules.ready_reason(row, me, c2), "combo_need_party", "不在同房")
	c2 = cc.duplicate()
	c2["same_party"] = false
	assert_eq(ComboRules.ready_reason(row, me, c2), "combo_need_party", "沒組隊")
	c2 = cc.duplicate()
	c2["partner_gender"] = "M"
	assert_eq(ComboRules.ready_reason(row, me, c2), "combo_pair_mismatch", "同性")
	c2 = cc.duplicate()
	c2["partner_skills"] = { "gm_yunu_jian": 59 }
	assert_eq(ComboRules.ready_reason(row, me, c2), "combo_pair_mismatch", "玉女劍法不到 60")
	var me2 := me.duplicate()
	me2["sect_skill"] = 29
	assert_eq(ComboRules.ready_reason(row, me2, cc), "combo_pair_mismatch", "門技（心性）不到 30")
	c2 = cc.duplicate()
	c2["moqi"] = 9
	assert_eq(ComboRules.ready_reason(row, me, c2), "combo_moqi_low", "M3d 審查（第 3 輪）：官方要默契「達到一定程度」→ 默契 10")
	c2["moqi"] = 10
	assert_eq(ComboRules.ready_reason(row, me, c2), "", "默契 10 → 可以")
	# moqi_min 的檢查（測試列 moqi_min 20）
	var trow := row.duplicate(true)
	trow["combo"]["moqi_min"] = 20
	c2["moqi"] = 19
	assert_eq(ComboRules.ready_reason(trow, me, c2), "combo_moqi_low")
	# 女方學也可以（兩邊對調）
	var her := { "gender": "F", "skills": { "gm_yunu_jian": 60 }, "sect_skill": 30 }
	var hc := cc.duplicate()
	hc["partner_gender"] = "M"
	hc["partner_skills"] = { "qz_jianfa": 60 }
	assert_eq(ComboRules.ready_reason(row, her, hc), "")

# ---------------------------------------------------------------- 資料列

func test_data_rows() -> void:
	var t := tables()
	var row: Dictionary = t["martial_arts"]["gm_suxin"]
	assert_eq(str(row.get("sect_id", "x")), "", "兩派都能學")
	assert_eq(str(row.get("era", "")), "1.0B")
	assert_eq((row.get("requires", []) as Array).size(), 0, "旗標 gm_suxin_unlocked 拿掉")
	var cb: Dictionary = row["combo"]
	assert_eq(str(cb.group), "suxin")
	assert_eq(int(cb.moqi_min), 10, "M3d 審查（第 3 輪）：修練要默契（官方原文）")
	assert_true(str(cb.get("src_note", "")).contains("設計提案・非原作"), "一起打贏加配合度標成非原作")
	assert_eq(str(cb.pair[0].art), "qz_jianfa")
	assert_eq(str(cb.pair[1].art), "gm_yunu_jian")
	var ms: Dictionary = t["masters"]["ms_gm_xiaolongnu_suxin"]
	assert_eq(ms.requires, [{ "type": "combo_ready", "art": "gm_suxin" }])
	assert_eq(int(ms.cap), 100)
	var shoes: Dictionary = t["items"]["i_cb_laopaoxie"]
	assert_eq([str(shoes.slot), int(shoes.def), int(shoes.weight), int(shoes.price)], ["BOOTS", 5, 1, 50000])
	assert_eq(str(shoes.effects[0].type), "FLEE_ANYWHERE")
	var pearl: Dictionary = t["items"]["i_cb_yemingzhu"]
	assert_eq([str(pearl.slot), str(pearl.tab), int(pearl.weight), int(pearl.price)], ["", "OTHER", 0, 20000])
	assert_eq(str(pearl.effects[0].type), "LIGHT")
	assert_false(bool(pearl.usable))
	var npc: Dictionary = t["npcs"]["n_cb_jc_huolang"]
	assert_eq(str(npc.room), "jc_square")
	assert_eq(npc.shop.items, ["i_cb_laopaoxie", "i_cb_yemingzhu"])

func test_1_0a_world_locked() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])
	make_char("單一時代", "xixia")
	assert_false(tables()["martial_arts"].has("gm_suxin"), "1.0A 視圖看不到素心劍")
	assert_false(tables()["items"].has("i_cb_laopaoxie"))
	assert_eq(reason("combo_bond", { "target_char": "ch_nobody" }), "era_locked")
	assert_eq(reason("combo_cancel"), "era_locked")
	assert_eq(reason("combo_nurture"), "era_locked")

# ---------------------------------------------------------------- 主機：默契

var _her := 0

## 本機男角（peer 1）＋遠端女角（_her）同在西夏廣場
func _two() -> bool:
	if not game_ok():
		return false
	if make_char("全真少俠", "xixia") == null:
		return false
	_her = connect_player("古墓少女")
	var r1 := send_as(_her, "char_roll")
	var r2 := send_as(_her, "char_create", { "name": "古墓少女", "gender": "F", "birth_month": 3, "birth_city": "xixia",
		"alloc": { "wit": 5 } })
	assert_true(r1.get("ok", false) and r2.get("ok", false), "建女角")
	host().regions.teleport(session_of(_her), s().room_id())
	ws.flush()
	return host().combo != null

func _her_ch():
	return session_of(_her).character

func _bond() -> void:
	ok("combo_bond", { "target_char": str(_her_ch().id) })
	assert_eq(str(send_as(_her, "combo_reply", { "from_char": str(ch().id), "accept": true }).get("reason", "x")), "")

func test_bond_accept_cancel() -> void:
	if not _two():
		return
	assert_eq(reason("combo_bond", { "target_char": str(ch().id) }), "not_here", "不是自己")
	ok("combo_bond", { "target_char": str(_her_ch().id) })
	var req := evs_for(_her, "cb_bond_request")
	assert_eq(req.size(), 1, "對方收到 cb_bond_request")
	# M3d 審查：請求還沒過期 → 不能再送（不再跳視窗）
	assert_eq(reason("combo_bond", { "target_char": str(_her_ch().id) }), "combo_request_pending", "防洗版")
	assert_eq(evs_for(_her, "cb_bond_request").size(), 1, "只跳一次")
	assert_eq(str(req[0].p.from_name), "全真少俠")
	assert_true(bool(req[0].get("ui", false)), "ui 事件")
	assert_eq(str(send_as(_her, "combo_reply", { "from_char": str(ch().id), "accept": true }).get("reason", "x")), "")
	var p: Dictionary = host().combo.pair_of(str(ch().id))
	assert_false(p.is_empty(), "world.combo_pairs 有這一對")
	assert_eq(str(host().ws.world["combo_pairs"].keys()[0]), ComboSystem.pair_key(str(ch().id), str(_her_ch().id)))
	assert_eq([int(p.moqi), int(p.peihe)], [0, 0])
	assert_eq(str(ch().ext.combo.partner), str(_her_ch().id))
	assert_eq(str(_her_ch().ext.combo.partner), str(ch().id))
	host().flush_session(s(), true)
	ws.flush()
	assert_eq(str(sheet().get("combo", {}).get("partner_name", "")), "古墓少女", "角色表 combo")
	assert_false(evs("cb_bond_changed").is_empty(), "cb_bond_changed（ui）")
	# 已有夥伴
	assert_eq(reason("combo_bond", { "target_char": str(_her_ch().id) }), "combo_has_partner")
	# 取消（任一方）
	assert_eq(str(send_as(_her, "combo_cancel").get("reason", "x")), "")
	assert_true(host().combo.pair_of(str(ch().id)).is_empty())
	assert_false(ch().ext.has("combo"), "兩邊的 ext.combo 都清掉")
	assert_false(_her_ch().ext.has("combo"))
	assert_eq(reason("combo_cancel"), "combo_need_partner")

func test_bond_refuse_and_stale() -> void:
	if not _two():
		return
	assert_eq(str(send_as(_her, "combo_reply", { "from_char": str(ch().id), "accept": true }).get("reason", "")), "combo_no_request",
		"沒有邀請")
	ok("combo_bond", { "target_char": str(_her_ch().id) })
	clear_events()
	assert_eq(str(send_as(_her, "combo_reply", { "from_char": str(ch().id), "accept": false }).get("reason", "x")), "")
	assert_true(host().combo.pair_of(str(ch().id)).is_empty(), "拒絕 → 沒有關係")
	assert_eq(evs("cb_bond_refused").size(), 1)
	# 過期
	ok("combo_bond", { "target_char": str(_her_ch().id) })
	ws.world["world_time_s"] = ws.world_time() + host().world_span(ComboSystem.REQ_TTL_REAL_S) + 1.0
	assert_eq(str(send_as(_her, "combo_reply", { "from_char": str(ch().id), "accept": true }).get("reason", "")), "combo_no_request",
		"邀請 60 秒後失效")
	# 不同房
	goto("xx_inn")
	assert_eq(reason("combo_bond", { "target_char": str(_her_ch().id) }), "not_here")

func test_nurture() -> void:
	if not _two():
		return
	_bond()
	assert_eq(reason("combo_nurture"), "combo_peihe_low")
	var p: Dictionary = host().combo.pair_of(str(ch().id))
	p["peihe"] = 100
	ok("combo_nurture")
	assert_eq([int(p.moqi), int(p.peihe)], [5, 0], "默契 +5、配合度歸 0")
	assert_eq(int(ch().ext.combo.moqi), 5, "ext 鏡像")
	p["moqi"] = 98
	p["peihe"] = 100
	ok("combo_nurture")
	assert_eq(int(p.moqi), 100, "上限 100")
	assert_eq(evs("cb_nurtured").size(), 2)

func test_drain_only_when_both_online() -> void:
	if not _two():
		return
	_bond()
	var p: Dictionary = host().combo.pair_of(str(ch().id))
	var d: int = host().combo.today()
	p["peihe"] = 50
	p["drain_day"] = d - 1
	assert_eq(host().combo.drain_all(d), 0, "還不到 2 遊戲日")
	p["drain_day"] = d - 2
	assert_eq(host().combo.drain_all(d), 1)
	assert_eq(int(p.peihe), 30, "配合度 −20")
	assert_eq(int(p.drain_day), d)
	p["peihe"] = 10
	p["moqi"] = 12
	p["drain_day"] = d - 3
	host().combo.drain_all(d)
	assert_eq([int(p.peihe), int(p.moqi)], [0, 7], "不夠扣 → 配合度 0、默契 −5")
	p["moqi"] = 3
	p["drain_day"] = d - 2
	host().combo.drain_all(d)
	assert_eq(int(p.moqi), 0, "最低 0")
	# 一方離線 → 不扣
	p["peihe"] = 80
	p["drain_day"] = d - 5
	ws.on_peer_disconnected(_her)
	ws.flush()
	assert_eq(host().combo.drain_all(d), 0, "夥伴不在線")
	assert_eq(int(p.peihe), 80)

func test_battle_settle_adds_peihe_once() -> void:
	if not _two():
		return
	_bond()
	var p: Dictionary = host().combo.pair_of(str(ch().id))
	var a_id := str(p.a)
	var a_ch = ch() if str(ch().id) == a_id else _her_ch()
	var b_ch = _her_ch() if a_ch == ch() else ch()
	host().combo.on_battle_settled(null, b_ch, { "bid": 0, "combo_hits": 2 })
	assert_eq(int(p.peihe), 0, "角色 id 較大的一方不計（避免兩人各算一次）")
	host().combo.on_battle_settled(null, a_ch, { "bid": 0, "combo_hits": 2 })
	assert_eq(int(p.peihe), 20, "兩次合體一擊 → +20")
	p["peihe"] = 95
	host().combo.on_battle_settled(null, a_ch, { "bid": 0, "combo_hits": 1 })
	assert_eq(int(p.peihe), 100, "上限 100")

func test_to_combatant_fields() -> void:
	if not _two():
		return
	_bond()
	var sp: Dictionary = ch().to_combatant(tables(), ws.options, 0, 1)
	assert_eq(str(sp.combo.partner_char), str(_her_ch().id))
	assert_eq(int(sp.combo.moqi), 0)
	assert_eq(str(sp.char_id), str(ch().id))
	assert_false(bool(sp.flee_anywhere))
	var uid := give("i_cb_laopaoxie")
	s().last_equip_ms = -100000
	ok("equip", { "item_uid": uid })
	assert_true(bool(ch().to_combatant(tables(), ws.options, 0, 1).flee_anywhere), "穿上烙跑鞋")

## 玉女素心劍法：男全真（全真劍法 60、養生 30）＋女古墓（玉女劍法 60、清心 30）、組隊、同房、默契 20 → 小龍女教得到
func test_learn_suxin_conditions() -> void:
	if not _two():
		return
	var me = ch()
	var her = _her_ch()
	ws.options["sect_hostile_entry"] = false
	host().sects.on_join(s(), "quanzhen", str(tables()["sects"]["quanzhen"].get("head_npc", "")))
	host().sects.on_join(session_of(_her), "gumu", str(tables()["sects"]["gumu"].get("head_npc", "")))
	me.sect = "quanzhen"
	her.sect = "gumu"
	me.morality = 100
	her.morality = 100
	for c in [me, her]:
		c.combat_xp = 200000
	me.skills.set_level("qz_jianfa", 60, tables())
	me.skills.set_level("yangsheng", 30, tables())
	her.skills.set_level("gm_yunu_jian", 60, tables())
	her.skills.set_level("qingxin", 30, tables())
	for c in [me, her]:
		c.combat_xp = 200000
		c.learn_points = 5000
		for a in ["wit", "con"]:
			c.attrs[a] = 60
		Survival.rest_full(c, tables(), ws.options)
	goto("gm_xiaolongnu")
	host().regions.teleport(session_of(_her), "gm_xiaolongnu")
	ws.flush()
	# 換地區時門派技能會衰減（M3a）：到了再設一次
	me.skills.set_level("yangsheng", 30, tables())
	her.skills.set_level("qingxin", 30, tables())
	var args := { "npc": "n_gm_xiaolongnu", "skill": "gm_suxin", "times": 1 }
	# 1. 沒有夥伴
	host().combo.refresh_live_ctx()
	assert_eq(reason("learn", args), "req_combo_ready", "沒有夥伴")
	assert_eq(Requirements.combo_ready_reason({ "art": "gm_suxin" }, me, tables(), host().sects.req_ctx(s())), "combo_need_partner")
	# 2. 有夥伴、沒組隊
	_bond()
	host().combo.refresh_live_ctx()
	assert_eq(Requirements.combo_ready_reason({ "art": "gm_suxin" }, me, tables(), host().sects.req_ctx(s())), "combo_need_party")
	assert_eq(reason("learn", args), "req_combo_ready")
	# 3. 組隊、默契 0 → 默契不夠；培養到 10 → 學得到（ctx 經 ComboRules.live_ctx）
	assert_eq(str(host().party.invite(s(), str(her.id)).get("reason", "x")), "")
	assert_eq(str(host().party.reply(session_of(_her), str(me.id), true).get("reason", "x")), "")
	host().combo.refresh_live_ctx()
	assert_eq(int(host().combo.pair_of(str(me.id)).get("moqi", -1)), 0, "默契 0")
	assert_eq(Requirements.combo_ready_reason({ "art": "gm_suxin" }, me, tables(), {}), "combo_moqi_low", "默契 0 → 不夠")
	host().combo.pair_of(str(me.id))["moqi"] = 10
	host().combo.refresh_live_ctx()
	assert_eq(Requirements.combo_ready_reason({ "art": "gm_suxin" }, me, tables(), {}), "", "live_ctx")
	ok("learn", args)
	assert_true(me.skills.level("gm_suxin") >= 1, "男全真學到素心劍")
	# 女方也學得到（兩邊對調）
	assert_eq(str(send_as(_her, "learn", args).get("reason", "x")), "")
	assert_true(her.skills.level("gm_suxin") >= 1, "女古墓學到素心劍")
	# 5. 夥伴的玉女劍法不夠 → 配不上
	her.skills.set_level("gm_yunu_jian", 59, tables())
	host().combo.refresh_live_ctx()
	assert_eq(Requirements.combo_ready_reason({ "art": "gm_suxin" }, me, tables(), host().sects.req_ctx(s())), "combo_pair_mismatch")
	# 6. 夥伴走開
	her.skills.set_level("gm_yunu_jian", 60, tables())
	host().regions.teleport(session_of(_her), "xx_square")
	host().combo.refresh_live_ctx()
	assert_eq(Requirements.combo_ready_reason({ "art": "gm_suxin" }, me, tables(), host().sects.req_ctx(s())), "combo_need_party")

## 沒有 summary.combo_hits 時：tick 記下有合體夥伴參戰的 Battle，結算時讀單位的 combo_with（BattleSystem 不必改）
func test_battle_settle_reads_tracked_battle() -> void:
	if not _two():
		return
	_bond()
	var p: Dictionary = host().combo.pair_of(str(ch().id))
	var a_id := str(p.a)
	var b_id := str(p.b)
	var a_ch = ch() if str(ch().id) == a_id else _her_ch()
	var sa := H.player_spec({ "ref": a_id, "char_id": a_id, "combo": { "partner_char": b_id, "moqi": 0 } })
	var sb := H.ally_spec(2, { "ref": b_id, "char_id": b_id, "combo": { "partner_char": a_id, "moqi": 0 } })
	var bt := H.make_battle([sa, sb, H.monster("m_dummy")], 3)
	bt.unit(1).combo_with = [b_id, b_id, b_id]
	host().battles.active[987] = { "battle": bt }
	host().combo.tick(1.5)
	host().battles.active.erase(987)
	host().combo.on_battle_settled(null, a_ch, { "bid": 987 })
	assert_eq(int(p.peihe), 30, "三次合體一擊 → +30（讀 Battle 單位的 combo_with）")

## M3d 審查（第 3 輪）：合體武功要夥伴「也會這門武功」、兩人配得上 pair 的性別——只有夥伴站在場上不夠
func test_combo_art_needs_partner_who_knows_it_and_fits() -> void:
	var b := _cb(11, 100)
	b.unit(2).spec["skills"] = { "basic_fist": 50 }   # 夥伴不會 t_combo
	var r := H.do_cmd(b, 1, { "cmd": "ART", "art": "t_combo", "move": "tc_1", "power_tenths": 10, "target": [5, 3] }, _ctables())
	assert_eq(str(r.err), "combo_partner_absent", "夥伴不會這門合體武功 → 不能出")
	for m in BattleAI.usable_moves(b.unit(1), _ctables(), b):
		assert_true(str(m.art) != "t_combo", "AI 也不選")
	var b2 := _cb(12, 100)
	b2.unit(2).spec["gender"] = "M"
	var r2 := H.do_cmd(b2, 1, { "cmd": "ART", "art": "t_combo", "move": "tc_1", "power_tenths": 10, "target": [5, 3] }, _ctables())
	assert_eq(str(r2.err), "combo_partner_absent", "兩個男的配不上一男一女的 pair")
	var b3 := _cb(13, 100)
	assert_true(ComboRules.partner_for_art(b3, b3.unit(1), _ctables()["martial_arts"]["t_combo"]) != null, "一男一女、都會 → 可以")
	# 合體一擊也照同樣的條件（夥伴不會 → 不觸發）
	var hits := 0
	for sd in range(1, 80):
		var bx := _cb(sd, 100)
		bx.tick_no = 100
		_art(bx, 2)
		bx.unit(2).spec["skills"] = { "basic_fist": 50 }
		bx.tick_no = 110
		hits += H.find(_art(bx, 1).events, "battle_combo").size()
	assert_eq(hits, 0, "夥伴不會 → 沒有合體一擊")

## M3d 審查（第 3 輪）：兩人同一邊一起打贏 → 配合度 +10（每對每遊戲日最多 60）；比武、劫鏢、輸了、對手逃光不算【設計提案・非原作】
func test_joint_victory_adds_peihe_with_daily_cap() -> void:
	if not _two():
		return
	_bond()
	var p: Dictionary = host().combo.pair_of(str(ch().id))
	var a_id := str(p.a)
	var b_id := str(p.b)
	var a_ch = ch() if str(ch().id) == a_id else _her_ch()
	var sa := H.player_spec({ "ref": a_id, "char_id": a_id, "combo": { "partner_char": b_id, "moqi": 0 } })
	var sb := H.ally_spec(2, { "ref": b_id, "char_id": b_id, "combo": { "partner_char": a_id, "moqi": 0 } })
	var bt := H.make_battle([sa, sb, H.monster("m_dummy")], 3)
	bt.unit(3).state = BattleUnit.DEAD
	host().battles.active[988] = { "battle": bt }
	host().combo.tick(1.5)
	host().battles.active.erase(988)
	var win := { "bid": 988, "kind": "ENCOUNTER", "per": "VICTORY", "kills": ["m_dummy"] }
	host().combo.on_battle_settled(null, a_ch, win)
	assert_eq(int(p.peihe), ComboSystem.JOINT_PEIHE, "一起打贏 +10")
	for k in ["DUEL", "ROB"]:
		var w2 := win.duplicate()
		w2["kind"] = k
		host().combo.on_battle_settled(null, a_ch, w2)
	var lost := win.duplicate()
	lost["per"] = "DEFEAT"
	host().combo.on_battle_settled(null, a_ch, lost)
	bt.unit(3).state = BattleUnit.FLED
	host().combo.on_battle_settled(null, a_ch, win)
	bt.unit(3).state = BattleUnit.DEAD
	assert_eq(int(p.peihe), ComboSystem.JOINT_PEIHE, "比武、劫鏢、輸了、對手逃光都不算")
	for i in 20:
		host().combo.on_battle_settled(null, a_ch, win)
	assert_eq(int(p.peihe), ComboSystem.JOINT_PEIHE_DAY_CAP, "每遊戲日最多 60")
	p["joint_day"] = int(p.joint_day) - 1
	host().combo.on_battle_settled(null, a_ch, win)
	assert_eq(int(p.peihe), ComboSystem.JOINT_PEIHE_DAY_CAP + ComboSystem.JOINT_PEIHE, "隔天又可以加")

## 結算時戰鬥已從 active 移除、tick 也還沒記到（很短的戰鬥）：改看 battle_summary 帶的 allies／foes_killed
func test_joint_victory_from_summary_allies() -> void:
	if not _two():
		return
	_bond()
	var p: Dictionary = host().combo.pair_of(str(ch().id))
	var a_ch = ch() if str(ch().id) == str(p.a) else _her_ch()
	var win := { "bid": 4321, "kind": "ENCOUNTER", "per": "VICTORY", "allies": [str(p.b)], "foes_killed": true }
	host().combo.on_battle_settled(null, a_ch, win)
	assert_eq(int(p.peihe), ComboSystem.JOINT_PEIHE, "summary 的 allies 有夥伴 → +10")
	var w2 := win.duplicate()
	w2["allies"] = []
	host().combo.on_battle_settled(null, a_ch, w2)
	var w3 := win.duplicate()
	w3["foes_killed"] = false
	host().combo.on_battle_settled(null, a_ch, w3)
	assert_eq(int(p.peihe), ComboSystem.JOINT_PEIHE, "夥伴不在同一邊、沒打倒對手 → 不加")
