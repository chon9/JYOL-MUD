extends "res://tests/unit/test_world_fixture.gd"
## 角色：擲骰→創角→自動選角；名稱重複；第 4 個角色；刪除；stop()→start() 後角色完整；welcome.your_characters
## （M1_PLAN 3.6 char_*、6.1 test_world_chars）

func before_each() -> void:
	world_name = "w_chars"
	super.before_each()

func test_game_host_is_running() -> void:
	if not game_ok():
		return
	for kind in Protocol.INTENT_SCHEMA:
		if kind == Protocol.I_DEBUG_SET or kind == Protocol.I_ROGUE_DEBUG:   # ROGUE_PLAN §3.11：rogue_debug 同 debug_set
			# M3A_PLAN 6.11：只在 --debug-intents 時註冊
			assert_false(ws.has_intent_handler(kind), "debug_set 預設不註冊")
			continue
		# STORY_PLAN §8.1：villain_reply、rumor_list 由 WP-AMBIENT 的 intents_ambient.gd 註冊（S2 容錯：檔案還沒有時不註冊）
		if kind in [Protocol.I_VILLAIN_REPLY, Protocol.I_RUMOR_LIST] 				and not ResourceLoader.exists("res://server/intents/intents_ambient.gd"):
			continue
		# M3B_PLAN L3：錢莊／鏢局（intents_econ.gd）、組織（intents_org.gd）由 WP-ECON／WP-ORG 的檔案註冊；檔案還沒有時不註冊
		if kind.begins_with("bank_") or kind.begins_with("consign_"):
			if not ResourceLoader.exists("res://server/intents/intents_econ.gd"):
				continue
		if kind.begins_with("org_") and not ResourceLoader.exists("res://server/intents/intents_org.gd"):
			continue
		assert_true(ws.has_intent_handler(kind), "handler for " + kind)

func test_roll_then_create_enters_world() -> void:
	if not game_ok():
		return
	assert_eq(reason("look"), "no_character")
	ok("char_roll")
	var rolled := lastp("char_rolled")
	var total := 0
	for a in Character.ATTR_IDS:
		assert_true(int(rolled.get(a, 0)) >= 13 and int(rolled.get(a, 0)) <= 25, "%s=%s" % [a, str(rolled.get(a))])
		total += int(rolled.get(a, 0))
	assert_eq(int(rolled.get("total", -1)), total)
	assert_eq(int(rolled.get("peer", 0)), 1)
	var r := ok("char_create", { "name": "測試俠客", "gender": "M", "birth_month": 3, "birth_city": "xixia",
		"alloc": { "wit": 5 } })
	assert_true(ch() != null, "auto-selected")
	assert_eq(lastp("char_created").get("name", ""), "測試俠客")
	assert_eq(str(lastp("char_entered").get("room_name", "")), host().room_name("xx_square"))
	# 角色表（3.9.1）
	assert_eq(sheet().get("char_id", ""), str(r.get("char_id", "?")))
	assert_eq(sheet()["location"]["room"], "xx_square")
	assert_eq(int(sheet()["learn_points"]), 100)
	assert_eq(int(sheet()["money"]), 100)
	assert_eq(sheet()["in_battle"], false)
	assert_true(sheet().has("clock"))
	assert_eq(int(sheet()["attrs_base"]["wit"]), int(rolled["wit"]) + 5, "alloc applied")
	var equipped: Dictionary = sheet()["equipped"]
	assert_true(str(equipped.get("WEAPON", "")) != "" and str(equipped.get("ARMOR", "")) != "", "equipped")
	assert_eq(item_count("c_jingyao"), 5)
	# 房間視圖與角色清單
	assert_eq(view().get("room", ""), "xx_square")
	assert_eq(view()["players"].size(), 1)
	assert_eq(cs.char_list.size(), 1)
	assert_eq(cs.char_list[0]["name"], "測試俠客")
	assert_true(s().pending_roll.is_empty(), "roll consumed")
	assert_eq(reason("char_create", { "name": "第二人", "gender": "F", "birth_month": 1, "birth_city": "dali",
		"alloc": { "str": 5 } }), "no_roll")

func test_create_validation_order() -> void:
	if not game_ok():
		return
	# M3b O3：京城 1.0B 可出生 → 用不可出生的少林
	var base := { "name": "甲", "gender": "M", "birth_month": 3, "birth_city": "shaolin", "alloc": { "wit": 5 } }
	assert_eq(reason("char_create", base), "bad_value:birth_city", "birth city checked first, even without roll")
	base["birth_city"] = "xixia"
	assert_eq(reason("char_create", base), "no_roll")
	ok("char_roll")
	var a := base.duplicate()
	a["name"] = "名 字"
	assert_eq(reason("char_create", a), "bad_name")
	a = base.duplicate()
	a["alloc"] = { "wit": 4 }
	assert_eq(reason("char_create", a), "bad_alloc")
	a["alloc"] = { "wit": 6 }
	assert_eq(reason("char_create", a), "bad_alloc")
	a["alloc"] = { "luck": 2, "evil": 3 }
	assert_eq(reason("char_create", a), "bad_alloc")
	assert_true(not s().pending_roll.is_empty(), "failed create keeps the roll")
	ok("char_create", base)
	ok("char_roll")
	var dup := base.duplicate()
	dup["birth_city"] = "dali"
	assert_eq(reason("char_create", dup), "name_taken")

func test_three_characters_max() -> void:
	if not game_ok():
		return
	make_char("一號")
	make_char("二號", "dali")
	make_char("三號")
	assert_eq(cs.char_list.size(), 3)
	ok("char_roll")
	assert_eq(reason("char_create", { "name": "四號", "gender": "M", "birth_month": 3, "birth_city": "xixia",
		"alloc": { "wit": 5 } }), "too_many_chars")

func test_select_and_delete() -> void:
	if not game_ok():
		return
	var a = make_char("甲角")
	var a_id := str(a.id)
	var b = make_char("乙角", "dali")
	var b_id := str(b.id)
	assert_eq(str(ch().id), b_id, "newest is active")
	assert_eq(sheet()["location"]["room"], "dl_square")
	assert_eq(reason("char_select", { "char_id": "ch_nope" }), "no_such_char")
	ok("char_select", { "char_id": a_id })
	assert_eq(str(ch().id), a_id)
	assert_eq(sheet()["char_id"], a_id)
	assert_eq(view()["room"], "xx_square")
	assert_eq(reason("char_delete", { "char_id": b_id, "confirm_name": "錯的" }), "confirm_mismatch")
	assert_eq(reason("char_delete", { "char_id": a_id, "confirm_name": "甲角" }), "char_active")
	assert_eq(reason("char_delete", { "char_id": "ch_zz", "confirm_name": "x" }), "no_such_char")
	ok("char_delete", { "char_id": b_id, "confirm_name": "乙角" })
	assert_eq(lastp("char_deleted").get("name", ""), "乙角")
	assert_eq(cs.char_list.size(), 1)
	assert_false(host().char_store.name_taken("乙角"), "name freed")
	make_char("乙角", "dali")   # 名稱可以再用

func test_characters_survive_restart() -> void:
	if not game_ok():
		return
	var c = make_char("存檔俠")
	var cid := str(c.id)
	goto("xx_street")
	c.money = 4321
	var uid := give("c_qiyao", 3)
	ws.stop()
	assert_eq(ws.start(world_name), OK)
	cs.begin_local_session()
	ws.flush()
	if not game_ok():
		return
	var list: Array = cs.char_list
	assert_eq(list.size(), 1, "welcome.your_characters")
	assert_eq(str(list[0]["char_id"]), cid)
	assert_eq(str(list[0]["room_name"]), host().room_name("xx_street"))
	ws.sessions[1].rate_limiter = TokenBucket.new(1000000.0, 1000000.0)
	ok("char_select", { "char_id": cid })
	assert_eq(int(ch().money), 4321)
	assert_eq(str(ch().location["room"]), "xx_street")
	assert_eq(item_count("c_qiyao"), 3)
	assert_true(not ch().inventory.find(uid).is_empty(), "item uid kept")
	assert_true(host().char_store.name_taken("存檔俠"), "name index persisted")

func test_character_file_format() -> void:
	if not game_ok():
		return
	var c = make_char("檔案俠")
	ws.save_now()
	var r: Dictionary = sm.load_character(world_name, s().identity, str(c.id))
	assert_true(r["ok"])
	assert_eq(int(r["data"]["schema_version"]), 1)
	assert_eq(r["data"]["name"], "檔案俠")
	assert_eq(sm.list_character_ids(world_name, s().identity), [str(c.id)])

func test_ids_are_unique_and_well_formed() -> void:
	if not game_ok():
		return
	var seen := {}
	var re := RegEx.create_from_string("^it_[0-9a-f]{8}$")
	for i in 500:
		var id: String = host().new_id("it_")
		assert_true(re.search(id) != null, id)
		assert_false(seen.has(id), "dup " + id)
		seen[id] = true

func test_no_character_guards() -> void:
	if not game_ok():
		return
	for kind_args in [["look", {}], ["move", { "dir": "N" }], ["talk", { "npc": "n_wujieshan" }], ["meditate", {}],
			["battle_cmd", { "battle_id": 1, "cmd": "DEFEND" }], ["quest_abandon", { "quest": "q_rabbit" }]]:
		assert_eq(reason(kind_args[0], kind_args[1]), "no_character", kind_args[0])
	ok("char_list")
	assert_eq(cs.char_list, [])

func test_disconnect_saves_character() -> void:
	if not game_ok():
		return
	var c = make_char("斷線俠")
	c.money = 777
	var ident: String = s().identity
	ws.on_peer_disconnected(1)
	assert_false(ws.sessions.has(1))
	var r: Dictionary = sm.load_character(world_name, ident, str(c.id))
	assert_eq(int(r["data"]["money"]), 777)
