extends "res://tests/unit/test_world_fixture.gd"

const DataLint := preload("res://tools/data_lint.gd")
## 移動、no_exit、room_locked、驛站旅行扣錢、夜間打烊、REACH 任務、房間視圖（M1_PLAN 6.1 test_world_move）

func before_each() -> void:
	world_name = "w_move"
	super.before_each()

func test_walk_between_rooms() -> void:
	if not game_ok():
		return
	make_char()
	ok("move", { "dir": "E" })
	assert_eq(str(ch().location["room"]), "xx_gate_e")
	assert_eq(str(ch().location["region"]), "xixia")
	assert_eq(view()["room"], "xx_gate_e")
	assert_eq(sheet()["location"]["room"], "xx_gate_e")
	ok("move", { "dir": "W" })
	assert_eq(str(ch().location["room"]), "xx_square")
	assert_eq(reason("move", { "dir": "U" }), "no_exit")
	assert_eq(reason("move", { "dir": "north" }), "bad_value:dir")

func test_view_contents() -> void:
	if not game_ok():
		return
	make_char()
	ok("look")
	var v := view()
	assert_eq(v["region"], "xixia")
	assert_eq(v["room_name"], host().room_name("xx_square"))
	assert_true(str(v["desc"]) != "")
	assert_true(str(v["clock"]).ends_with("刻"))
	var dirs := []
	for ex in v["exits"]:
		dirs.append(ex["dir"])
		assert_true(ex.has("label") and ex.has("to") and ex.has("to_name") and ex.has("locked"))
	for d in ["E", "N", "S", "W"]:
		assert_has(dirs, d)
	var npc_ids := []
	for n in v["npcs"]:
		npc_ids.append(n["id"])
	assert_has(npc_ids, "n_wujieshan")
	assert_eq(v["safe"], true)
	assert_eq(v["danger"], false)
	goto("xw_grass")
	assert_eq(view()["danger"], true)
	assert_eq(view()["region"], "xixia_wild")

## 回歸：查看要在訊息欄印出房間描述、出口與人物，不能只重送畫面（擁有者回報「按了都沒回應」）
func test_look_prints_room_to_log() -> void:
	if not game_ok():
		return
	make_char()
	clear_events()
	ok("look")
	var p := lastp(Protocol.E_LOOK)
	assert_eq(p.get("room_name", ""), host().room_name("xx_square"))
	assert_true(str(p.get("desc", "")) != "", "有房間描述")
	assert_true(str(p.get("exits", "")).contains("東："), "列出出口：%s" % p.get("exits", ""))
	assert_true(str(p.get("who", "")).contains("武介山"), "列出 NPC：%s" % p.get("who", ""))

## 回歸：關閉世界後 GameHost 與子系統要能被回收（原本互相引用，關遊戲時出現「9 resources still in use」）
func test_stop_releases_game_host() -> void:
	if not game_ok():
		return
	make_char()
	var host_ref: WeakRef = weakref(host())
	var regions_ref: WeakRef = weakref(host().regions)
	var battles_ref: WeakRef = weakref(host().battles)
	ws.stop()
	assert_eq(host_ref.get_ref(), null, "GameHost 已回收")
	assert_eq(regions_ref.get_ref(), null, "RegionSystem 已回收")
	assert_eq(battles_ref.get_ref(), null, "BattleSystem 已回收")
	assert_eq(ws.start(world_name), OK, "同一次執行可以再開世界")

func test_room_locked_for_non_huashan() -> void:
	if not game_ok():
		return
	make_char()
	goto("hs_square")
	var locked := false
	for ex in view()["exits"]:
		if ex["to"] == "hs_hall":
			locked = ex["locked"]
	assert_true(locked, "view shows the hall as locked")
	assert_eq(reason("move", { "dir": "N" }), "room_locked")
	assert_eq(str(ch().location["room"]), "hs_square")
	ch().sect = "huashan"
	ok("move", { "dir": "N" })
	assert_eq(str(ch().location["room"]), "hs_hall")

func test_overweight_blocks_move() -> void:
	if not game_ok():
		return
	make_char()
	var cap := int(ch().derived(tables(), ws.options)["carry_max"])
	# 直接塞進背包（繞過 add 的重量檢查）
	ch().inventory.items.append({ "uid": "it_heavy001", "id": "r_wood", "n": cap, "born_s": 0.0 })
	assert_eq(reason("move", { "dir": "E" }), "overweight")

func test_travel_by_station() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])   # M3B_PLAN §2：這條測 1.0A-only 世界（京城不存在）
	make_char()
	host().options["stagecoach_enabled"] = true   # 馬車是伺服器選項【設計提案・非原作】
	goto("xx_station")
	var before := int(ch().money)
	assert_eq(reason("travel", { "npc": "n_xx_station", "dest": "sl_gate" }), "no_route")
	assert_eq(reason("travel", { "npc": "n_xx_station", "dest": "jc_station" }), "no_route", "京城 is 1.0B")
	assert_eq(reason("travel", { "npc": "n_dl_station", "dest": "xx_station" }), "not_here")
	ch().money = 100
	assert_eq(reason("travel", { "npc": "n_xx_station", "dest": "dl_station" }), "not_enough_money")
	ch().money = before + 150
	ok("travel", { "npc": "n_xx_station", "dest": "dl_station" })
	assert_eq(str(ch().location["room"]), "dl_station")
	assert_eq(str(ch().location["region"]), "dali")
	assert_eq(int(ch().money), before)
	assert_eq(int(sheet()["money"]), before)
	assert_eq(int(lastp("travel").get("cost", 0)), 150)
	assert_eq(view()["room"], "dl_station")
	ok("talk", { "npc": "n_dl_station" })
	var m := lastp("npc_menu")
	assert_has(m.get("services", []), "TRAVEL", "menu shows 驛站 when enabled:")
	assert_eq(m.get("routes", []).size(), 1, "one route back to 西夏")

func test_travel_disabled_by_default() -> void:
	if not game_ok():
		return
	make_char()
	assert_eq(host().options.get("stagecoach_enabled", false), false, "default world has no stagecoach")
	assert_eq(ws.world_info().get("stagecoach_enabled", true), false, "world_info carries the option")
	goto("xx_station")
	var before := int(ch().money)
	assert_eq(reason("travel", { "npc": "n_xx_station", "dest": "dl_station" }), "stagecoach_disabled")
	assert_eq(str(ch().location["room"]), "xx_station")
	assert_eq(int(ch().money), before)
	ok("talk", { "npc": "n_xx_station" })
	var m := lastp("npc_menu")
	assert_not_has(m.get("services", []), "TRAVEL", "menu hides 驛站:")
	assert_has(m.get("services", []), "QUEST", "letter quests still offered:")
	assert_eq(m.get("routes", ["x"]), [], "no routes")
	for n in view()["npcs"]:
		if n["id"] == "n_xx_station":
			assert_not_has(n["services"], "TRAVEL", "room view hides 驛站:")
	assert_true(str(tables()["text_templates"]["err_stagecoach_disabled"]["self"]) != "", "error template")

## 西夏 → 大理全程走路（關掉遇敵）：WORLD_2001 §1.3 西路
func test_walk_xixia_to_dali() -> void:
	if not game_ok():
		return
	make_char()
	for rid in host().index.rooms:
		host().index.rooms[rid].erase("encounter")
	var path: Array = DataLint.find_path(tables(), "xx_square", "dl_gate_n")
	assert_true(path.size() > 2, "path: %s" % str(path))
	for i in range(1, path.size()):
		var dir := ""
		for ex in host().index.room(str(path[i - 1])).get("exits", []):
			if str(ex["to"]) == str(path[i]):
				dir = str(ex["dir"])
		ok("move", { "dir": dir })
	assert_eq(str(ch().location["room"]), "dl_gate_n")
	assert_eq(str(ch().location["region"]), "dali")
	assert_true("de_oasis" in path, "via the oasis")

## WORLD_2001 §8：舊存檔的位置／記錄點已不在生效的房間裡
func _reenter(room: String, respawn_room := "") -> void:
	var c = ch()
	host().leave_character(s(), false)
	c.location = { "region": "x", "room": room }
	if respawn_room != "":
		c.respawn = { "region": "x", "room": respawn_room }
	clear_events()
	host().enter_character(s(), c)
	host().flush_session(s(), true)
	ws.flush()

func test_relocate_removed_cave_to_forest() -> void:
	if not game_ok():
		return
	make_char()
	_reenter("dlw_cave")
	assert_eq(str(ch().location["room"]), "dlw_forest")
	assert_eq(str(ch().location["region"]), "dali_wild")
	assert_eq(lastp("relocated").get("room_name", ""), host().room_name("dlw_forest"))
	assert_true(evs("respawn_reset").is_empty(), "respawn untouched")

func test_relocate_era_gated_room_to_respawn() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])   # M3B_PLAN §2：這條測 1.0A-only 世界（京城不存在）
	make_char()
	_reenter("jc_street", "hs_gate")
	assert_eq(str(ch().location["room"]), "hs_gate", "moved to the record point")
	assert_eq(str(ch().location["region"]), "huashan")
	assert_eq(lastp("relocated").get("room_name", ""), host().room_name("hs_gate"))
	_reenter("jcw_crossroad")
	# 記錄點仍是華山山門
	assert_eq(str(ch().location["room"]), "hs_gate")

func test_respawn_in_removed_room_is_reset() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])   # M3B_PLAN §2：這條測 1.0A-only 世界（京城不存在）
	make_char()
	_reenter("jc_street", "jc_gate_s")
	assert_eq(str(ch().respawn.get("room", "")), "", "record point cleared")
	assert_eq(lastp("respawn_reset").get("room_name", ""), host().room_name("xx_square"))
	assert_eq(str(ch().location["room"]), "xx_square", "no record point -> birth city")
	assert_eq(lastp("relocated").get("room_name", ""), host().room_name("xx_square"))
	# 位置合法時不送任何搬家事件
	_reenter("xw_grass")
	assert_true(evs("relocated").is_empty() and evs("respawn_reset").is_empty(), "nothing to fix")

func test_night_closes_shops() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_pharmacy")
	ch().money = 1000
	ok("buy", { "npc": "n_xx_pharmacist", "item": "c_jingyao" })
	clear_events()
	set_shichen(10)   # 戌時
	assert_eq(host().clock()["shichen_name"], "戌")
	assert_true(not evs("night_falls").is_empty(), "night_falls broadcast")
	assert_eq(reason("buy", { "npc": "n_xx_pharmacist", "item": "c_jingyao" }), "closed_night")
	assert_eq(reason("shop_list", { "npc": "n_xx_pharmacist" }), "closed_night")
	var closed := false
	for n in view()["npcs"]:
		if n["id"] == "n_xx_pharmacist":
			closed = n["closed"]
	assert_true(closed, "view marks pharmacist closed")
	# 驛站與客棧夜間照常營業
	goto("xx_inn")
	ok("inn_rest", { "npc": "n_xx_innkeeper" })
	goto("xx_station")
	host().options["stagecoach_enabled"] = true
	ok("travel", { "npc": "n_xx_station", "dest": "dl_station" })
	clear_events()
	set_shichen(3)    # 卯時
	assert_true(not evs("day_breaks").is_empty(), "day_breaks broadcast")
	goto("xx_pharmacy")
	ok("buy", { "npc": "n_xx_pharmacist", "item": "c_jingyao" })

func test_reach_quest_progress() -> void:
	if not game_ok():
		return
	make_char()
	# 測試專用任務（M1 資料沒有 REACH 任務）：直接放進生效視圖
	GameData.tables["quests"]["q_test_reach"] = { "id": "q_test_reach", "name": "到東門看看", "giver": "n_wujieshan",
		"repeatable": false, "requires": [], "give_items": [],
		"steps": [ { "type": "REACH", "target": "xx_gate_e", "item": "", "count": 1, "text": "到東門" } ],
		"rewards": { "money": 7 }, "era": "1.0A", "src": "proposal" }
	ch().quests["active"]["q_test_reach"] = { "step": 0, "counts": {} }
	var money := int(ch().money)
	ok("move", { "dir": "E" })
	assert_false(ch().quests["active"].has("q_test_reach"))
	assert_eq(QuestState.done_count(ch().quests, "q_test_reach"), 1)   # done 列是 { n, outcome, world_s, failed }（§4.7）
	assert_eq(int(ch().money), money + 7)
	assert_eq(lastp("quest_complete").get("quest_name", ""), "到東門看看")

func test_other_players_see_walk_events() -> void:
	if not game_ok():
		return
	make_char()
	# 第二位玩家（peer 2）直接建 session 放進同房間；不 flush（離線 peer 沒有 peer 2 可送 RPC）
	var s2 := Session.new(2, "local_0123456789abcdef0123456789abcdef", "客人")
	ws.sessions[2] = s2
	var c2 = CharacterFactory.create({ "id": "ch_guest001", "identity": s2.identity, "name": "客人甲", "gender": "F",
		"birth_month": 1, "birth_city": "xixia", "alloc": { "str": 5 } }, CharacterFactory.roll(ws.rng),
		tables(), ws.options, ws.rng, 0.0)
	s2.character = c2
	host().regions.enter_world(s2)
	seq += 1
	var r: Dictionary = ws.handle_intent(1, seq, "move", { "dir": "E" })
	assert_true(r.get("ok", false), str(r))
	var keys := []
	for e in ws.pending_events(2):
		keys.append(e["key"])
	assert_has(keys, "room_leave", "guest saw me leave")
	var mine := []
	for e in ws.pending_events(1):
		mine.append(e["key"])
	assert_not_has(mine, "room_leave", "walker does not get own room_leave")
	assert_true(s2.view_dirty, "guest view refreshed")
	ws.sessions.erase(2)
	ws.flush()
