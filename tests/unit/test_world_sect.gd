extends "res://tests/unit/test_world_sect_fixture.gd"
## 門派流程（M3A_PLAN §6、3.2）：8 派的拜師條件（以 3.2 表的條件裝成測試門派）、不合格的原因碼、內室 any_of 鎖、
## 敵對入山（含選項關閉）、引路、試煉、斷惡取得、每日衰減、進古墓違規（ENTER_REGION）、npc_menu 新欄位。

func before_each() -> void:
	world_name = "w_sect"
	super.before_each()

## 3.2 表：[sect_id, 性別, join_requires, 合格角色的設定 {morality, pk, gender, flag}, 不合格的設定與原因碼]
const JOIN_CASES := [
	["wudang", ["M"], [ { "type": "morality_min", "value": 50 }, { "type": "no_sect" }, { "type": "not_enemy_of", "sect": "wudang" },
		{ "type": "quest_flag", "flag": "wd_recommended" } ], { "morality": 100, "flag": "wd_recommended" },
		[ [ { "morality": 100 }, "req_quest_flag" ], [ { "morality": 0, "flag": "wd_recommended" }, "req_morality_min" ],
		[ { "morality": 100, "flag": "wd_recommended", "gender": "F" }, "req_gender" ],
		[ { "morality": 100, "flag": "wd_recommended", "enemy": true }, "req_not_enemy_of" ] ] ],
	["emei", ["F"], [ { "type": "morality_min", "value": -299 }, { "type": "no_sect" }, { "type": "not_enemy_of", "sect": "emei" } ],
		{ "morality": 0, "gender": "F" }, [ [ { "morality": -300, "gender": "F" }, "req_morality_min" ], [ { "gender": "M" }, "req_gender" ] ] ],
	["hengshan", ["F"], [ { "type": "morality_min", "value": 0 }, { "type": "pk_max", "value": 0 }, { "type": "no_sect" },
		{ "type": "not_enemy_of", "sect": "hengshan" } ], { "morality": 0, "gender": "F" },
		[ [ { "morality": 0, "gender": "F", "pk": 1 }, "req_pk_max" ], [ { "morality": -1, "gender": "F" }, "req_morality_min" ] ] ],
	["quanzhen", ["M"], [ { "type": "morality_min", "value": 0 }, { "type": "no_sect" }, { "type": "not_enemy_of", "sect": "quanzhen" },
		{ "type": "not_enemy_of", "sect": "gumu" } ], { "morality": 0 }, [ [ { "morality": -1 }, "req_morality_min" ] ] ],
	["gumu", ["F"], [ { "type": "morality_min", "value": -299 }, { "type": "morality_max", "value": 299 }, { "type": "no_sect" },
		{ "type": "not_enemy_of", "sect": "gumu" } ], { "morality": 0, "gender": "F" },
		[ [ { "morality": 300, "gender": "F" }, "req_morality_max" ], [ { "morality": 0 }, "req_gender" ] ] ],
	["lingjiu", ["F"], [ { "type": "morality_min", "value": -299 }, { "type": "morality_max", "value": 299 }, { "type": "pk_max", "value": 3 },
		{ "type": "no_sect" }, { "type": "not_enemy_of", "sect": "lingjiu" } ], { "morality": 0, "gender": "F" },
		[ [ { "morality": 0, "gender": "F", "pk": 4 }, "req_pk_max" ] ] ],
	["xingxiu", ["M", "F"], [ { "type": "morality_max", "value": -100 }, { "type": "no_sect" }, { "type": "not_enemy_of", "sect": "xingxiu" } ],
		{ "morality": -200 }, [ [ { "morality": -99 }, "req_morality_max" ] ] ],
	["xuedao", ["M"], [ { "type": "morality_max", "value": -100 }, { "type": "no_sect" }, { "type": "not_enemy_of", "sect": "xuedao" } ],
		{ "morality": -200 }, [ [ { "morality": -200, "gender": "F" }, "req_gender" ] ] ],
]

## 同一個角色反覆重設（每個身分最多 3 個角色）
func _fresh(cfg: Dictionary):
	var c = ch()
	if c == null:
		c = make_char("門人", "xixia", { "wit": 5 }, "M")
	c.gender = str(cfg.get("gender", "M"))
	c.sect = ""
	c.sect_master = ""
	c.sect_enemies = []
	c.sect_record = Character.default_sect_record()
	c.flags = {}
	c.morality = int(cfg.get("morality", 0))
	c.pk = int(cfg.get("pk", 0))
	c.pk_stamp_s = c.online_s
	if cfg.has("flag"):
		c.flags[str(cfg["flag"])] = true
	if bool(cfg.get("enemy", false)):
		c.sect_enemies = [SID]
	return c

func test_join_requirements_for_eight_sects() -> void:
	if not game_ok():
		return
	for case in JOIN_CASES:
		var sid := str(case[0])
		install_sect({ "gender": case[1], "join_requires": _swap(case[2], sid) })
		# 合格
		var c = _fresh(case[3])
		goto(HALL)
		var r := send("join_sect", { "npc": HEAD })
		assert_true(r.get("ok", false), "%s 合格角色拜師：%s" % [sid, str(r)])
		assert_eq(str(c.sect), SID, sid)
		assert_eq((c.sect_record.get("history", []) as Array).back().get("what", ""), "JOIN")
		# 不合格
		for bad in case[4]:
			var cfg: Dictionary = bad[0]
			_fresh(cfg)
			goto(HALL)
			if s().battle_id != 0:
				host().battles.abort_all()
				s().battle_id = 0
			assert_eq(reason("join_sect", { "npc": HEAD }), str(bad[1]), "%s %s" % [sid, str(cfg)])

## 把條件裡的門派 id 換成測試門派（not_enemy_of 自己）
func _swap(conds: Array, sid: String) -> Array:
	var out: Array = []
	for c in conds:
		var d: Dictionary = (c as Dictionary).duplicate(true)
		if str(d.get("sect", "")) == sid:
			d["sect"] = SID
		out.append(d)
	return out

func test_inner_room_any_of_lock() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("訪客俠")
	goto(HALL)
	assert_eq(reason("move", { "dir": "N" }), "room_locked", "非本派、沒有令牌")
	var ex: Dictionary = {}
	for e in host().regions.view(s())["exits"]:
		if str(e["to"]) == INNER:
			ex = e
	assert_eq(str(ex.get("lock_reason", "")), "req_any_of")
	give(TOKEN)
	ok("move", { "dir": "N" })
	assert_eq(s().room_id(), INNER, "有令牌、無門派可進")
	c.inventory.remove_item_id(TOKEN, 1)
	goto(HALL)
	c.sect = SID
	ok("move", { "dir": "N" })

func test_hostile_entry_and_option() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("敵人俠")
	c.sect_enemies = [SID]
	ws.options["sect_hostile_entry"] = false
	goto(GATE)
	assert_eq(s().battle_id, 0, "選項關閉不開戰")
	goto(HALL)
	assert_eq(s().battle_id, 0)
	ws.options["sect_hostile_entry"] = true
	clear_events()
	ok("move", { "dir": "S" })
	assert_true(s().battle_id != 0, "公敵入山開戰")
	assert_eq(evs(Protocol.E_SECT_HOSTILE).size(), 1)
	var entry: Dictionary = host().battles.active.get(s().battle_id, {})
	assert_eq(str(entry.get("kind", "")), "SECT_GUARD")
	host().battles.abort_all()
	s().battle_id = 0
	# 30 秒內不再觸發
	goto(HALL)
	assert_eq(s().battle_id, 0, "冷卻中")
	c.online_s += 31.0
	goto(GATE)
	assert_true(s().battle_id != 0, "冷卻過後再觸發")
	host().battles.abort_all()
	s().battle_id = 0
	# 本派弟子不觸發（INNER 規則：善惡 ≤ −101）
	install_sect({ "hostile_entry": [ { "if": [ { "type": "morality_max", "value": -101 } ], "rooms": "INNER", "monster": GUARD,
		"count": [2, 2], "chance": 1.0, "no_flee": false, "capture": false } ] })
	c.sect_enemies = []
	c.morality = -500
	c.online_s += 31.0
	goto(GATE)
	assert_eq(s().battle_id, 0, "GATE 不是 INNER")
	c.online_s += 31.0
	goto(HALL)
	assert_true(s().battle_id != 0, "惡人進 INNER 開戰")
	var b = host().battles.active[s().battle_id]["battle"]
	var guards := 0
	for u in b.units:
		if int(u.side) == 1:
			guards += 1
	assert_eq(guards, 2, "count [2, 2]")
	host().battles.abort_all()
	s().battle_id = 0
	c.sect = SID
	c.online_s += 31.0
	goto(GATE)
	goto(HALL)
	assert_eq(s().battle_id, 0, "本派弟子不觸發")

func test_guide() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("男訪客")
	goto(GATE)
	assert_eq(reason("npc_guide", { "npc": GUIDE }), "req_any_of", "男性非弟子不帶")
	c.gender = "F"
	clear_events()
	ok("npc_guide", { "npc": GUIDE })
	assert_eq(s().room_id(), INNER)
	assert_eq(str(lastp(Protocol.E_NPC_GUIDE).get("room_name", "")), "測派內室")
	assert_eq(reason("npc_guide", { "npc": GUIDE }), "not_here")

func test_trial_flag_on_victory() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("試煉俠")
	goto(HALL)
	assert_eq(reason("sect_trial", { "npc": TRIAL }), "req_sect")
	c.sect = SID
	clear_events()
	ok("talk", { "npc": TRIAL })
	var tm: Variant = lastp(Protocol.E_NPC_MENU).get("trial")
	assert_true(tm is Dictionary and bool(tm.get("ok", false)), str(tm))
	assert_eq(int(tm.get("party_min", 0)), 1)
	install_sect()   # party_min 4：人數不足
	host().npc_row(TRIAL)["trial"]["party_min"] = 4
	assert_eq(reason("sect_trial", { "npc": TRIAL }), "trial_party")
	host().npc_row(TRIAL)["trial"]["party_min"] = 1
	var r := ok("sect_trial", { "npc": TRIAL })
	assert_true(s().battle_id != 0, "開戰")
	assert_eq(str(host().battles.active[s().battle_id]["kind"]), "TRIAL")
	sects().on_battle_settled(s(), c, { "kind": "TRIAL", "result": "VICTORY", "kills": [], "died": false })
	ws.flush()
	assert_true(bool(c.flags.get("ts_trial_passed", false)), "通過旗標")
	assert_eq(evs(Protocol.E_TRIAL_PASSED).size(), 1)

func test_kill_alignment_gain() -> void:
	if not game_ok():
		return
	install_sect({ "sect_skill_gain": [ { "on": "KILL_ALIGNMENT", "alignment": "EVIL", "prof": 10 } ] })
	var c = member("斷惡俠")
	c.sect = SID
	c.combat_xp = 100000
	var p0: int = c.skills.prof(SKILL)
	sects().on_battle_settled(s(), c, { "kind": "ENCOUNTER", "result": "VICTORY", "kills": ["m_bandit", "m_bandit", "m_rabbit"] })
	assert_eq(int(c.skills.prof(SKILL)) - p0, 20, "兩隻邪惡怪 × 10")
	sects().on_battle_settled(s(), c, { "kind": "ENCOUNTER", "result": "DEFEAT", "kills": ["m_bandit"] })
	assert_eq(int(c.skills.prof(SKILL)) - p0, 20, "敗戰不算")

func test_daily_decay() -> void:
	if not game_ok():
		return
	install_sect({ "sect_skill_penalties": [ { "trigger": "DAILY_IF", "if": [ { "type": "killing_intent_min", "value": 2001 } ], "levels": 1 } ] },
		[])
	var c = member("定性俠")
	join_via_npc()
	c.skills.set_level(SKILL, 10, tables())
	clear_events()
	fast_forward(7300.0)
	assert_eq(c.skills.level(SKILL), 10, "殺氣不高不衰減")
	c.killing_intent = 2500
	fast_forward(7300.0)
	assert_eq(c.skills.level(SKILL), 9, "每遊戲日 −1")
	assert_eq(int(lastp(Protocol.E_SECT_SKILL_DECAY).get("level", -1)), 9)

func test_enter_region_breach_and_penalty() -> void:
	if not game_ok():
		return
	install_sect({ "sect_skill_penalties": [ { "trigger": "ENTER_REGION", "region": "huashan", "levels": 1 } ] })
	var c = member("全真俠")
	join_via_npc()
	c.skills.set_level(SKILL, 5, tables())
	clear_events()
	goto("hs_gate")
	assert_eq(evs(Protocol.E_SECT_BREACH).size(), 1, "走進禁地 → 違反門規")
	assert_true(c.is_jailed(), "預設 JAIL")
	assert_eq(c.skills.level(SKILL), 4, "門派技能 −1")
	assert_eq(s().room_id(), JAIL)

func test_betray_flow() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("叛徒俠")
	join_via_npc()
	c.skills.set_level(SKILL, 20, tables())
	c.skills.set_level(ART, 21, tables())
	c.skills.set_level(OTHER_ART, 30, tables())
	c.skills.set_level("basic_fist", 40, tables())
	give(TOKEN, 2)
	clear_events()
	ok("talk", { "npc": HEAD })
	assert_true(bool(lastp(Protocol.E_NPC_MENU).get("betray", false)), "menu.betray")
	assert_eq(reason("sect_betray", { "npc": HEAD }), "need_confirm")
	assert_eq(reason("sect_betray", { "npc": HEAD, "confirm": false }), "need_confirm")
	assert_eq(reason("sect_betray", { "npc": GUIDE, "confirm": true }), "not_here")
	ok("sect_betray", { "npc": HEAD, "confirm": true })
	assert_eq(str(c.sect), "")
	assert_eq(c.skills.level(ART), 10, "本門武功減半")
	assert_eq(c.skills.level(OTHER_ART), 30, "別派武功不變")
	assert_eq(c.skills.level("basic_fist"), 40, "基本武學不變（預設）")
	assert_eq(c.skills.level(SKILL), 20, "門派技能不動（2001：只減半本門武功；歸零屬後期官方規則 betrayal_halves_basics）")
	assert_true(c.sect_traitor.has(SID), "叛徒記號")
	assert_eq(item_count(TOKEN), 0, "門派物品沒收")
	assert_true(c.sect_enemies.has(SID), "公敵")
	assert_eq(evs(Protocol.E_SECT_BETRAY).size(), 1)
	assert_eq(reason("join_sect", { "npc": HEAD }), "req_not_enemy_of", "永遠不能再拜")
	refresh_sheet()
	assert_has(sheet().get("enemy_of", []), "測派")
	assert_eq(reason("sect_betray", { "npc": HEAD, "confirm": true }), "no_service", "已經不是本派")

func test_menu_and_teach_block() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("傳功俠")
	join_via_npc()
	clear_events()
	ok("talk", { "npc": HEAD })
	var m := lastp(Protocol.E_NPC_MENU)
	for k in ["betray", "jail", "trial", "guide", "teach_blocked"]:
		assert_true(m.has(k), "menu has " + k)
	assert_eq(str(m.get("teach_blocked", "x")), "")
	c.morality = -10   # teach_requires morality_min 0
	clear_events()
	ok("talk", { "npc": HEAD })
	assert_eq(str(lastp(Protocol.E_NPC_MENU).get("teach_blocked", "")), "sect_stop_teach")
	ok("learn_list", { "npc": HEAD })
	var tl := lastp(Protocol.E_TEACH_LIST)
	assert_eq(str(tl.get("blocked", "")), "sect_stop_teach")
	for e in tl.get("entries", []):
		assert_false(bool(e.get("ok", true)), "全部灰掉")
	assert_eq(reason("learn", { "npc": HEAD, "skill": SKILL }), "sect_stop_teach")
	refresh_sheet()
	assert_eq(str(sheet().get("sect_info", {}).get("stop_teach", "")), "sect_stop_teach")
	c.morality = 0
	ok("learn", { "npc": HEAD, "skill": ART })

func test_sheet_sect_info_warnings() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("燈籠俠")
	join_via_npc()
	refresh_sheet()
	var si: Dictionary = sheet().get("sect_info", {})
	assert_eq(str(si.get("id", "")), SID)
	assert_eq(str(si.get("name", "")), "測派")
	assert_eq(str(si.get("skill_id", "")), SKILL)
	assert_eq(si.get("warnings", []), [])
	c.morality = -85
	c.killing_intent = 1900
	refresh_sheet()
	var w: Array = sheet()["sect_info"]["warnings"]
	assert_has(w, "morality")
	assert_has(w, "killing_intent")
	assert_eq(sheet().get("jail"), null)

func test_hour_in_and_party_ctx() -> void:
	if not game_ok():
		return
	install_sect()
	member("時辰俠")
	var ctx: Dictionary = sects().req_ctx(s())
	assert_eq(int(ctx.get("party_size", 0)), 1, "只有自己")
	assert_true(str(ctx.get("shichen", "")) in WorldClock.SHICHEN)
	set_shichen(3)
	assert_eq(sects().check_reqs([ { "type": "hour_in", "hours": ["卯"] } ], s()), "")
	assert_eq(sects().check_reqs([ { "type": "hour_in", "hours": ["午"] } ], s()), "req_hour_in")
	assert_eq(sects().check_reqs([ { "type": "party_size_min", "value": 2 } ], s()), "req_party_size_min")
