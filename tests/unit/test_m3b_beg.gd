extends "res://tests/unit/test_sect_m3b_fixture.gd"
## M3B_PLAN §5.1.2、§5.1.3、§11.1：乞討（驗證順序全部原因碼、熟練增加、同 NPC 冷卻、施捨、不受善惡停止傳功影響）
## 與小黃追咬（街道房機率觸發、乞討 30 免、室內不觸發、60 秒節流、打贏 5 學點）。

func _beggar() -> void:
	install_gb()
	make_char("測乞兒")
	join_gb()
	ch().skills.set_level(GB_SKILL, 10, tables())
	Survival.rest_full(ch(), tables(), ws.options)
	ch().skills.set_level(GB_SKILL, 31, tables())   # 先免追咬，乞討測試不被小黃打斷
	ch().skills.set_level(GB_SKILL, 10, tables())

func _quiet_goto(room: String) -> void:
	ch().skills.set_level(GB_SKILL, 30, tables())   # 乞討 ≥ 30 免追咬
	goto(room)
	ch().skills.set_level(GB_SKILL, 10, tables())

func test_reason_order() -> void:
	if not game_ok():
		return
	install_gb()
	make_char("測路人")
	# 本派沒有 practice（沒有門派）
	assert_eq(reason("beg", { "npc": BEGGEE }), "no_practice")
	join_gb()
	_quiet_goto(GB_HALL)
	assert_eq(reason("beg", { "npc": BEGGEE }), "npc_not_here")
	_quiet_goto(STREET)
	assert_eq(reason("beg", { "npc": "n_xx_guard" }), "npc_not_here", "守衛在東門，不在廣場")
	_quiet_goto("xx_inn")
	assert_eq(reason("beg", { "npc": "n_xx_cook" }), "cant_beg", "師父（MASTER）不能乞討")
	_quiet_goto(STREET)
	tables()["npcs"][BEGGEE]["no_beg"] = true
	assert_eq(reason("beg", { "npc": BEGGEE }), "cant_beg", "no_beg")
	tables()["npcs"][BEGGEE].erase("no_beg")
	ch().vitals["jing"] = 5
	assert_eq(reason("beg", { "npc": BEGGEE }), "not_enough_jing")
	Survival.rest_full(ch(), tables(), ws.options)
	ch().vitals["shen"] = 5
	assert_eq(reason("beg", { "npc": BEGGEE }), "not_enough_shen")
	Survival.rest_full(ch(), tables(), ws.options)
	ok("beg", { "npc": BEGGEE })
	var r := send("beg", { "npc": BEGGEE })
	assert_eq(str(r.get("reason", "")), "beg_cooldown", "同一位 NPC 冷卻")
	assert_true(int(r.get("left_s", 0)) >= 1, "冷卻帶剩餘秒數")
	# 戰鬥中、坐牢中由 GameHost 擋
	ch().jail = { "sect": GB, "room": STREET, "until_online_s": ch().online_s + 100.0, "reason": "BREACH", "rule": "",
		"days": 1, "notified": true, "scope": "SECT" }
	assert_eq(reason("beg", { "npc": BEGGEE }), "jailed")
	ch().jail = {}

func test_success_gives_prof_and_costs_vitals() -> void:
	if not game_ok():
		return
	_beggar()
	_quiet_goto(STREET)
	Survival.rest_full(ch(), tables(), ws.options)
	var jing := int(ch().vitals["jing"])
	var shen := int(ch().vitals["shen"])
	var prof := int(ch().skills.prof(GB_SKILL))
	clear_events()
	var r := ok("beg", { "npc": BEGGEE })
	assert_eq(int(ch().vitals["jing"]), jing - 20, "耗精 20")
	assert_eq(int(ch().vitals["shen"]), shen - 20, "耗神 20")
	var gain := int(ch().skills.prof(GB_SKILL)) - prof
	assert_true(gain >= 3 and gain <= 6, "熟練 +3～6（實得 %d）" % gain)
	assert_eq(int(r.get("gain_prof", -1)), gain)
	var p := lastp("beg")
	assert_eq(str(p.get("npc_name", "")), host().npc_name(BEGGEE))
	assert_eq(int(p.get("gain_prof", -1)), gain)
	# 冷卻過了（600 世界秒）可以再乞討
	host().debug_enabled = true
	ws.world["world_time_s"] = ws.world_time() + 601.0
	Survival.rest_full(ch(), tables(), ws.options)
	ok("beg", { "npc": BEGGEE })

func test_alms_over_many_begs() -> void:
	if not game_ok():
		return
	_beggar()
	_quiet_goto(STREET)
	var money0 := int(ch().money)
	var got_money := 0
	var got_item := 0
	for i in 60:
		Survival.rest_full(ch(), tables(), ws.options)
		ch().counters["beg_cd"] = {}
		var r := ok("beg", { "npc": BEGGEE })
		if int(r.get("money", 0)) > 0:
			got_money += 1
			assert_true(int(r["money"]) >= 1 and int(r["money"]) <= 8, "施捨 1–8 兩")
		if str(r.get("item", "")) == "c_mantou":
			got_item += 1
	assert_true(got_money > 5, "35% 銀兩（60 次中 %d 次）" % got_money)
	assert_true(got_item >= 1, "10% 饅頭（60 次中 %d 次）" % got_item)
	assert_true(int(ch().money) > money0)
	assert_true(item_count("c_mantou") >= got_item)

func test_beg_not_blocked_by_stop_teach() -> void:
	if not game_ok():
		return
	_beggar()
	ch().morality = -500   # 善惡 < 0：停止傳功
	assert_eq(ch().teach_block_reason(tables(), ws.options, host().rules), "sect_stop_teach")
	_quiet_goto(STREET)
	Survival.rest_full(ch(), tables(), ws.options)
	ok("beg", { "npc": BEGGEE })

func test_npc_menu_beg_field() -> void:
	if not game_ok():
		return
	_beggar()
	_quiet_goto(STREET)
	clear_events()
	ok("talk", { "npc": BEGGEE })
	var b: Variant = lastp("npc_menu").get("beg")
	assert_true(b is Dictionary, "本派有 practice：npc_menu.beg")
	assert_true(bool(b.get("ok", false)))
	Survival.rest_full(ch(), tables(), ws.options)
	ok("beg", { "npc": BEGGEE })
	clear_events()
	ok("talk", { "npc": BEGGEE })
	b = lastp("npc_menu").get("beg")
	assert_false(bool(b.get("ok", true)))
	assert_eq(str(b.get("reason", "")), "beg_cooldown")
	assert_true(float(b.get("left_s", 0.0)) > 0.0)
	# 沒有門派的人看不到
	ch().sect = ""
	clear_events()
	ok("talk", { "npc": BEGGEE })
	assert_eq(lastp("npc_menu").get("beg"), null)

# ---------------------------------------------------------------- 小黃追咬

func test_harass_on_street() -> void:
	if not game_ok():
		return
	_beggar()
	ch().skills.set_level(GB_SKILL, 10, tables())
	clear_events()
	goto(STREET)   # 機率 1.0（測試門派），乞討 10 < 30
	assert_true(s().battle_id != 0, "街道房被小黃追咬")
	assert_eq(str(host().battles.active[s().battle_id]["kind"]), "HARASS")
	assert_false(evs("harass").is_empty(), "harass 事件")
	make_strong()
	var res := drive_battle("fight")
	assert_eq(str(res.get("result", "")), "VICTORY")
	assert_eq(int(res.get("rewards", {}).get("learn_points", 0)), 5, "打贏一隻 5 學點【已證實】")

func test_harass_exemptions_and_throttle() -> void:
	if not game_ok():
		return
	_beggar()
	# 乞討 ≥ 30 免
	ch().skills.set_level(GB_SKILL, 30, tables())
	goto(STREET)
	assert_eq(s().battle_id, 0, "乞討 30 免追咬")
	ch().skills.set_level(GB_SKILL, 10, tables())
	# 室內（有 SHOP 的 NPC）不觸發
	goto("xx_smithy")
	assert_eq(s().battle_id, 0, "兵器鋪（SHOP）不追咬")
	goto("xx_inn")
	assert_eq(s().battle_id, 0, "客棧（INN）不追咬")
	# 不是 regions 裡的地區不觸發
	goto(GB_HALL)
	assert_eq(s().battle_id, 0)
	# 觸發一次後 60 秒內不再觸發
	goto(STREET)
	assert_true(s().battle_id != 0)
	make_strong()
	drive_battle("fight")
	goto("xx_street")
	assert_eq(s().battle_id, 0, "60 秒節流")
	ch().online_s += 61.0
	goto(STREET)
	assert_true(s().battle_id != 0, "60 秒後又會追咬")
	drive_battle("fight")
	# 別的門派不會
	ch().sect = SID
	install_sect()
	ch().online_s += 61.0
	goto("xx_street")
	assert_eq(s().battle_id, 0, "其他門派沒有 harass")
