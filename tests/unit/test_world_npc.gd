extends "res://tests/unit/test_world_fixture.gd"
## NPC 服務：對話選單、商店買賣（收購 30%）、教學（含佛法 10 門檻）、拜入（性別、華山考驗）、客棧、記錄點、齋食時辰
## （M1_PLAN 6.1 test_world_npc）

func before_each() -> void:
	world_name = "w_npc"
	super.before_each()

func test_talk_sends_line_and_menu() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])   # M3B_PLAN §2：1.0A-only 世界的驛站只有一條路線（1.0B 多京城）
	make_char()
	assert_eq(reason("talk", { "npc": "n_xx_cha" }), "not_here")
	assert_eq(reason("talk", { "npc": "n_nobody" }), "not_here")
	ok("talk", { "npc": "n_wujieshan" })
	var line := last("talk_n_wujieshan")
	assert_false(line.is_empty(), "talk template event")
	assert_eq(line.get("ch", ""), "SCENE")
	var menu := last("npc_menu")
	assert_eq(menu.get("ui", false), true, "npc_menu is UI-only")
	var p: Dictionary = menu.get("p", {})
	assert_eq(p.get("npc", ""), "n_wujieshan")
	assert_has(p.get("services", []), "QUEST")
	var q: Array = p.get("quests", [])
	# M3b：武介山另有 q_sm_shepi（WP-C-story_missing 的 npc_links）→ 2 條
	assert_eq(q.size(), 2)
	var rabbit := {}
	for row in q:
		if str(row.get("id", "")) == "q_rabbit":
			rabbit = row
	assert_eq(rabbit.get("id", ""), "q_rabbit")
	assert_eq(rabbit.get("state", ""), "AVAILABLE")
	goto("xx_station")
	ok("talk", { "npc": "n_xx_station" })
	assert_eq(lastp("npc_menu").get("routes", ["x"]), [], "stagecoach off by default (WORLD_2001 D5)")
	host().options["stagecoach_enabled"] = true
	ok("talk", { "npc": "n_xx_station" })
	var routes: Array = lastp("npc_menu").get("routes", [])
	assert_eq(routes.size(), 1)
	if routes.size() == 1:
		assert_eq([routes[0]["to_room"], routes[0]["price"]], ["dl_station", 150])

func test_shop_buy_and_sell() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_smithy")
	assert_eq(reason("buy", { "npc": "n_xx_innkeeper", "item": "w_dandao" }), "not_here")
	assert_eq(reason("learn_list", { "npc": "n_xx_smith" }), "no_service")
	ok("shop_list", { "npc": "n_xx_smith" })
	var sl := last("shop_list")
	assert_eq(sl.get("ui", false), true)
	var ids := []
	for it in sl["p"]["items"]:
		ids.append(it["id"])
	assert_has(ids, "w_dandao")
	ch().money = 1000
	assert_eq(reason("buy", { "npc": "n_xx_smith", "item": "c_jingyao" }), "no_item", "not sold here")
	ok("buy", { "npc": "n_xx_smith", "item": "w_dandao" })
	assert_eq(int(ch().money), 850)
	assert_eq(item_count("w_dandao"), 1)
	assert_eq(int(lastp("buy").get("cost", 0)), 150)
	ok("buy", { "npc": "n_xx_smith", "item": "w_mujian", "n": 2 })
	assert_eq(item_count("w_mujian"), 2, "non-stackable bought one by one")
	assert_eq(int(ch().money), 810)
	ch().money = 10
	assert_eq(reason("buy", { "npc": "n_xx_smith", "item": "w_gangdao" }), "not_enough_money")
	# 收購價 = ⌊價格 × 0.3⌋
	var uid := first_uid("w_dandao")
	ok("sell", { "npc": "n_xx_smith", "item_uid": uid })
	assert_eq(int(ch().money), 10 + 45)
	assert_eq(item_count("w_dandao"), 0)
	assert_eq(reason("sell", { "npc": "n_xx_smith", "item_uid": uid }), "no_item")
	# 已裝備的武器可以賣（先卸下）
	var weapon_uid := str(ch().inventory.equipped.get("WEAPON", ""))
	ok("sell", { "npc": "n_xx_smith", "item_uid": weapon_uid })
	assert_eq(str(ch().inventory.equipped.get("WEAPON", "")), "")
	# 任務物品不能賣
	var letter := give("i_letter")
	assert_eq(reason("sell", { "npc": "n_xx_smith", "item_uid": letter }), "not_sellable")
	var skin := give("r_bigrabbitskin")
	assert_eq(reason("sell", { "npc": "n_xx_smith", "item_uid": skin }), "not_sellable")
	var pots := give("c_qiyao", 3)
	assert_eq(reason("sell", { "npc": "n_xx_smith", "item_uid": pots, "n": 4 }), "no_item")
	ok("sell", { "npc": "n_xx_smith", "item_uid": pots, "n": 2 })
	assert_eq(item_count("c_qiyao"), 1)

func test_money_cap_on_sell() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_smithy")
	ch().money = Character.MONEY_CAP
	var pots := give("c_qiyao", 1)
	assert_eq(reason("sell", { "npc": "n_xx_smith", "item_uid": pots }), "money_cap")
	assert_eq(item_count("c_qiyao"), 1, "item kept")

func test_teach_list_and_learn_basic() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_wuguan")
	ok("learn_list", { "npc": "n_xx_wushi" })
	var tl := last("teach_list")
	assert_eq(tl.get("ui", false), true)
	assert_true((tl["p"]["entries"] as Array).size() >= 8)
	var lp := int(ch().learn_points)
	var money := int(ch().money)
	ok("learn", { "npc": "n_xx_wushi", "skill": "basic_fist", "times": 3 })
	var p := lastp("learn")
	assert_eq(int(p.get("times", 0)), 3)
	assert_eq(int(p.get("lp", 0)), 3)
	assert_eq(int(ch().learn_points), lp - 3)
	assert_eq(int(ch().money), money - 15, "武館 5 兩／次")
	assert_true(int(ch().skills.prof("basic_fist")) > 0)
	assert_true(int(p.get("prof", 0)) > 0)
	assert_eq(reason("learn", { "npc": "n_xx_wushi", "skill": "sl_changquan" }), "not_taught")

func test_shaolin_join_and_foxa_gate() -> void:
	if not game_ok():
		return
	make_char()
	goto("sl_gate")
	ok("join_sect", { "npc": "n_sl_zhike" })
	assert_eq(str(ch().sect), "shaolin")
	assert_eq(sheet()["sect"], "shaolin")
	assert_eq(lastp("sect_join").get("sect_name", ""), str(tables()["sects"]["shaolin"]["name"]))
	assert_eq(reason("join_sect", { "npc": "n_sl_zhike" }), "already_in_sect")
	goto("sl_wuchang")
	assert_eq(reason("learn", { "npc": "n_sl_huizhen", "skill": "sl_changquan" }), "req_skill_min", "佛法未達 10")
	ch().skills.set_level("foxa", 10, tables())
	ch().combat_xp = 500
	ok("learn", { "npc": "n_sl_huizhen", "skill": "sl_changquan", "times": 10 })
	assert_true(int(ch().skills.prof("sl_changquan")) > 0)

func test_female_cannot_join_shaolin() -> void:
	if not game_ok():
		return
	make_char("女俠", "xixia", { "wit": 5 }, "F")
	goto("sl_gate")
	assert_eq(reason("join_sect", { "npc": "n_sl_zhike" }), "req_gender")
	assert_eq(str(ch().sect), "")

func test_huashan_needs_trial() -> void:
	if not game_ok():
		return
	make_char()
	goto("hs_square")
	assert_true(reason("join_sect", { "npc": "n_yuebuqun" }).begins_with("req_"))
	ch().skills.set_level("basic_inner", 5, tables())
	ch().skills.set_level("basic_literacy", 5, tables())
	assert_eq(reason("join_sect", { "npc": "n_yuebuqun" }), "req_quest_flag")
	ch().flags["hs_trial_passed"] = true
	ok("join_sect", { "npc": "n_yuebuqun" })
	assert_eq(str(ch().sect), "huashan")

func test_inn_rest() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_inn")
	var c = ch()
	c.vitals["jing"] = 1
	c.vitals["qi"] = 1
	c.vitals["shen"] = 1
	var money := int(c.money)
	ok("inn_rest", { "npc": "n_xx_innkeeper" })
	assert_eq(int(c.money), money - 20)
	var v: Dictionary = sheet()["vitals"]
	assert_eq(int(v["jing"]), int(v["jing_max"]))
	assert_eq(int(v["qi"]), int(v["qi_max"]))
	assert_eq(int(v["shen"]), int(v["shen_max"]))
	assert_eq(str(lastp("inn_rest").get("room_name", "")), "西夏客棧")
	c.money = 19
	assert_eq(reason("inn_rest", { "npc": "n_xx_innkeeper" }), "not_enough_money")
	# 審查 round 4：綠洲住宿的訊息不能寫「你在客棧……」
	c.money = 100
	goto("de_oasis")
	ok("inn_rest", { "npc": "n_de_host" })
	assert_eq(str(lastp("inn_rest").get("room_name", "")), "綠洲")
	var tpl: Dictionary = GameData.tables.get("text_templates", {}).get("inn_rest", {})
	assert_true(str(tpl.get("self", "")).contains("{room_name}") and not str(tpl.get("self", "")).contains("客棧"), str(tpl))

func test_set_respawn() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_gate_e")
	ok("talk", { "npc": "n_xx_cha" })
	ok("set_respawn", { "npc": "n_xx_cha" })
	assert_eq(str(ch().respawn["room"]), "xx_gate_e")
	assert_eq(sheet()["respawn"]["room"], "xx_gate_e")
	assert_eq(lastp("respawn_set").get("room_name", ""), host().room_name("xx_gate_e"))
	assert_eq(reason("set_respawn", { "npc": "n_xx_guard" }), "no_service")

func test_meal_hours() -> void:
	if not game_ok():
		return
	make_char()
	goto("sl_zhaitang")
	set_shichen(4)   # 辰時：不是用齋時間
	assert_eq(reason("meal", { "npc": "n_sl_zhaiseng" }), "not_meal_time")
	set_shichen(6)   # 午時
	ch().vitals["food"] = 10
	ch().vitals["water"] = 10
	ok("meal", { "npc": "n_sl_zhaiseng" })
	assert_true(int(ch().vitals["food"]) >= 50, "food +40")
	assert_true(int(ch().vitals["water"]) >= 50, "water +40")
	assert_eq(reason("meal", { "npc": "n_sl_zhaiseng" }), "already_ate")
	set_shichen(9)   # 酉時
	ok("meal", { "npc": "n_sl_zhaiseng" })

func test_fight_npc_starts_battle() -> void:
	if not game_ok():
		return
	make_char()
	goto("hs_square")
	ok("fight", { "npc": "n_ludayou" })
	assert_true(s().battle_id != 0)
	assert_false(cs.battle_state.is_empty(), "s2c_battle_open delivered")
	assert_eq(int(cs.battle_state.get("my_uid", 0)), my_uid)
	assert_true(my_uid > 0)
	assert_false(last("fight_start").is_empty())
	assert_eq(reason("talk", { "npc": "n_ludayou" }), "in_battle")
	assert_eq(reason("move", { "dir": "S" }), "in_battle")
	ok("look")
	assert_eq(sheet()["in_battle"], true)
	assert_eq(int(sheet()["battle_id"]), s().battle_id)

## 回歸：剛入門、內力 0 的弟子，學門派技能的那一行要先標「需要內力」，不能是可按的鈕（擁有者截圖：按了才說內力不夠）
func test_learn_list_flags_sect_skill_needing_neili() -> void:
	if not game_ok():
		return
	make_char()
	goto("sl_gate")
	ok("join_sect", { "npc": "n_sl_zhike" })
	ch().vitals["neili"] = 0
	clear_events()
	ok("learn_list", { "npc": "n_sl_zhike" })
	var foxa := {}
	for e in lastp(Protocol.E_TEACH_LIST).get("entries", []):
		if str(e.get("skill", "")) == "foxa":
			foxa = e
	assert_false(bool(foxa.get("ok", true)), "內力 0 時佛法不能按")
	assert_eq(foxa.get("reason", ""), "learn_need_neili")
	ch().vitals["neili"] = 5
	clear_events()
	ok("learn_list", { "npc": "n_sl_zhike" })
	for e in lastp(Protocol.E_TEACH_LIST).get("entries", []):
		if str(e.get("skill", "")) == "foxa":
			assert_true(bool(e.get("ok", false)), "有內力就能學")
