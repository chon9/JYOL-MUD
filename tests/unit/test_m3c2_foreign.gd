extends "res://tests/unit/test_world_fixture.gd"
## M3C2_PLAN §5.3–§5.6（WP-CARRY）：外來角色匯入 passport_import —— 所有原因碼、截斷每一類、未知物品／技能清單、
## 神兵登記空／被佔、重複匯入舊／新、取代保持本地 id、同世界拒絕、單機允許、開房依選項。

const OTHER_WORLD := "w_friend_world"
const OTHER_SECRET := "friend_world_secret"
const FOREIGN_IDENT := "local_abababababababababababababababab"
const DIVINE := "w_sb_yitian"
const IntentsHostRef := preload("res://server/intents/intents_host.gd")

var _old_mode := 0

func before_each() -> void:
	world_name = "w_m3c2_foreign"
	super.before_each()
	_old_mode = NetworkManager.mode
	NetworkManager.mode = NetworkManager.Mode.OFFLINE

func after_each() -> void:
	NetworkManager.mode = _old_mode
	super.after_each()

## 以目前選著的角色為底，做一份「別的世界」的護照（id、身分、名字換掉）
func _foreign_dict(char_name: String, src_id := "ch_fx000001") -> Dictionary:
	var d: Dictionary = ch().to_dict()
	d["id"] = src_id
	d["identity"] = FOREIGN_IDENT
	d["name"] = char_name
	return d

func _pp(d: Dictionary, saved_s := 1000.0, world := OTHER_WORLD) -> Dictionary:
	var pp := Passport.make(OTHER_SECRET, world, d, saved_s)
	pp["world_name"] = "朋友的江湖"
	return _json(pp)

func _json(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))

func _quest_item() -> String:
	for iid in tables()["items"]:
		if bool(tables()["items"][iid].get("quest_item", false)):
			return str(iid)
	return ""

func _char_by_name(n: String):
	var ref: Dictionary = host().char_ref_by_name(n)
	if ref.is_empty():
		return null
	return host().char_store.load_char(str(ref["identity"]), str(ref["char_id"]))

func _has_line(arr: Array, needle: String) -> bool:
	for x in arr:
		if str(x).contains(needle):
			return true
	return false

# ---------------------------------------------------------------- 截斷（純邏輯）

func test_sanitize_clamps_every_category() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("客俠一")
	d["attrs"]["str"] = 99
	d["attrs"]["agi"] = 2
	d["combat_xp"] = 99999999
	d["learn_points"] = 9999999
	d["money"] = 99999999
	d["morality"] = 5000
	d["killing_intent"] = -5
	d["pk"] = 99999999
	d["fame"] = 99999999
	d["lilian"] = -3
	d["skills"]["sk_does_not_exist"] = { "level": 5, "prof": 10 }
	d["skills"]["basic_fist"] = { "level": 999, "prof": 999999999 }
	d["inventory"]["items"].append({ "uid": "it_zz000001", "id": "x_abc", "n": 2, "born_s": 0.0 })
	var qi := _quest_item()
	d["inventory"]["items"].append({ "uid": "it_zz000002", "id": qi, "n": 1, "born_s": 0.0 })
	d["inventory"]["items"].append({ "uid": "it_zz000003", "id": DIVINE, "n": 1, "born_s": 0.0 })
	d["bank"] = { "money": 5000, "items": [{ "uid": "it_bk000001", "id": "c_jingyao", "n": 3, "born_s": 0.0 }] }
	d["guild"] = "g_abc"
	d["quests"] = { "active": { "q_bandit": { "v": 2, "stage": "s1", "objs": {} } }, "done": { "q_xx": { "n": 1 } },
		"cd": { "q_bandit": 999999.0 } }
	d["jail"] = { "sect": "shaolin", "room": "sl_jail", "until_online_s": 9999.0, "reason": "BREACH" }
	d["location"] = { "region": "nowhere", "room": "nowhere_room" }
	d["counters"]["life_cd_until_s"] = 999999.0
	d["ext"] = { "loot": { "lock": 1 }, "ambient": { "once": {} } }
	var pp := _pp(d)
	var r := ForeignImport.sanitize(pp, tables(), GameData.rules, ws.options)
	assert_true(r["ok"], "sanitize ok")
	var c: Dictionary = r["char"]
	var dropped: Array = r["dropped"]
	# 屬性
	assert_eq(int(c["attrs"]["str"]), 30, "attr max 30")
	assert_eq(int(c["attrs"]["agi"]), 13, "attr min 13")
	var tot := 0
	for a in Character.ATTR_IDS:
		tot += int(c["attrs"][a])
	assert_true(tot <= ForeignImport.ATTR_TOTAL_MAX, "attr total %d" % tot)
	assert_true(_has_line(dropped, "屬性"), "attr note")
	# 數值
	assert_eq(int(c["combat_xp"]), 10000000, "combat_xp cap")
	var xcap := int(GameData.rules.get("xuedian_cap", 0))
	if xcap > 0:
		assert_eq(int(c["learn_points"]), xcap, "xuedian cap")
	# M3c2 第二輪審查：銀兩＋物品收購總值一起算上限
	var capv := mini(int(ws.options.get("bank_money_cap", 6000000)), ForeignImport.FOREIGN_MONEY_CAP)
	var invc := Inventory.from_dict(c["inventory"])
	assert_eq(int(c["money"]) + ForeignImport.items_value(invc, tables()), capv, "money + item value cap")
	assert_true(_has_line(dropped, "銀兩超過外來角色上限"), "money cap listed")
	assert_eq(int(c["morality"]), 1000)
	assert_eq(int(c["killing_intent"]), 0)
	assert_eq(int(c["pk"]), ForeignImport.GENERIC_MAX)
	assert_eq(int(c["lilian"]), 0)
	# 技能
	assert_false(c["skills"].has("sk_does_not_exist"), "unknown skill dropped")
	assert_true(_has_line(dropped, "未知技能 sk_does_not_exist"), "unknown skill listed")
	assert_true(int(c["skills"]["basic_fist"]["level"]) <= SkillBook.max_level_of("basic_fist", tables()), "skill max")
	# 物品
	var ids: Array = []
	for it in c["inventory"]["items"]:
		ids.append(str(it["id"]))
	assert_not_has(ids, "x_abc", "unknown item")
	assert_not_has(ids, qi, "quest item")
	assert_has(ids, DIVINE, "divine kept for host to decide")
	assert_true(_has_line(dropped, "未知物品 x_abc ×2"), "unknown item listed: %s" % str(dropped))
	assert_true(_has_line(dropped, "任務物品"), "quest item listed")
	assert_eq(r["summary"]["divine"], [DIVINE])
	# 世界綁定
	assert_eq(int(c["bank"]["money"]), 0)
	assert_eq((c["bank"]["items"] as Array).size(), 0)
	assert_true(_has_line(dropped, "錢莊存款"), "bank listed")
	assert_eq(str(c["guild"]), "")
	assert_true(_has_line(dropped, "組織"), "guild listed")
	assert_eq((c["quests"]["active"] as Dictionary).size(), 0)
	assert_eq((c["quests"]["cd"] as Dictionary).size(), 0)
	assert_true(c["quests"]["done"].has("q_xx"), "done quests kept")
	assert_true(_has_line(dropped, "進行中的任務 1 件"), "active quest listed")
	assert_eq(c["jail"], {})
	assert_false(c["counters"].has("life_cd_until_s"), "cooldowns reset")
	assert_false(c["ext"].has("loot"), "world-bound ext dropped")
	assert_true(c["ext"].has("ambient"), "ambient kept")
	assert_eq(str(c["location"]["room"]), str(tables()["regions"][str(c["birth_city"])]["birth_room"]), "to birth room")
	assert_eq(c["respawn"], { "region": "", "room": "" })
	# 外來標記
	assert_eq(str(c["origin_world"]), OTHER_WORLD)
	assert_eq(str(c["ext"]["foreign"]["world_name"]), "朋友的江湖")
	assert_eq(str(c["ext"]["foreign"]["char_id"]), "ch_fx000001")
	# 摘要
	var sm: Dictionary = r["summary"]
	assert_eq(str(sm["name"]), "客俠一")
	assert_eq(int(sm["combat_xp"]), 10000000)
	assert_true((sm["top_skills"] as Array).size() > 0, "top skills")

func test_sanitize_skill_capped_by_combat_xp_and_bad_data() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("客俠二")
	d["combat_xp"] = 0
	d["skills"]["basic_fist"] = { "level": 60, "prof": 1 }
	var r := ForeignImport.sanitize(_pp(d), tables(), GameData.rules, ws.options)
	assert_true(r["ok"])
	assert_eq(int(r["char"]["skills"]["basic_fist"]["level"]), DerivedStats.art_level_cap(0), "xp cap")
	assert_true(_has_line(r["dropped"], "技能等級截到上限"), "capped listed")
	# 格式不對
	var bad := _pp(d)
	bad.erase("sig")
	assert_eq(str(ForeignImport.sanitize(bad, tables(), GameData.rules, ws.options)["reason"]), "foreign_bad_data")
	var bad2 := _pp(d)
	bad2["char"]["gender"] = "X"
	assert_eq(str(ForeignImport.sanitize(bad2, tables(), GameData.rules, ws.options)["reason"]), "foreign_bad_data")

func test_sanitize_unknown_sect_cleared_but_arts_kept() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("客俠三")
	d["sect"] = "no_such_sect"
	d["sect_enemies"] = ["no_such_sect", "shaolin"]
	var r := ForeignImport.sanitize(_pp(d), tables(), GameData.rules, ws.options)
	assert_eq(str(r["char"]["sect"]), "")
	assert_eq(r["char"]["sect_enemies"], ["shaolin"])
	assert_true(_has_line(r["dropped"], "原門派本世界沒有開放"), str(r["dropped"]))

# ---------------------------------------------------------------- 原因碼（主機）

func test_reason_codes_in_order() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var good := _pp(_foreign_dict("客俠四"))
	# foreign_bad_data（格式）
	var f1 := good.duplicate(true)
	f1.erase("char")
	assert_eq(reason("passport_import", { "passport": f1 }), "foreign_bad_data")
	# foreign_same_world
	var same := _pp(_foreign_dict("客俠四"), 1000.0, str(ws.world.get("world_id", "")))
	assert_eq(reason("passport_import", { "passport": same }), "foreign_same_world")
	# 開房、選項關 → foreign_disabled；選項開 → 可以
	NetworkManager.mode = NetworkManager.Mode.ENET_HOST
	ws.options["allow_foreign_characters"] = false
	assert_false(host().foreign_allowed())
	assert_eq(reason("passport_import", { "passport": good }), "foreign_disabled")
	assert_false(bool(ws.world_info()["foreign_allowed"]), "world_info says no")
	ws.options["allow_foreign_characters"] = true
	assert_true(host().foreign_allowed())
	assert_true(bool(ws.world_info()["foreign_allowed"]), "world_info says yes")
	NetworkManager.mode = NetworkManager.Mode.OFFLINE
	ws.options["allow_foreign_characters"] = false
	assert_true(host().foreign_allowed(), "offline always allowed")
	# 成功
	clear_events()
	var r := ok("passport_import", { "passport": good })
	var new_id := str(r.get("char_id", ""))
	assert_true(new_id != "" and new_id != "ch_fx000001", "new local id")
	var e := lastp("foreign_imported")
	assert_eq(str(e.get("name", "")), "客俠四")
	assert_eq(bool(e.get("replaced", true)), false)
	assert_true(last("foreign_imported").get("ui", false), "ui event")
	var imp = host().char_store.load_char(s().identity, new_id)
	assert_true(imp != null, "file written")
	assert_eq(str(imp.identity), s().identity)
	assert_eq(str(imp.origin_world), OTHER_WORLD)
	var reg: Dictionary = ws.world["foreign_imports"]
	assert_true(reg.has(OTHER_WORLD + "/ch_fx000001"), "registered")
	assert_eq(str(reg[OTHER_WORLD + "/ch_fx000001"]["char_id"]), new_id)
	# 角色清單：外來標記
	var found := false
	for row in cs.char_list:
		if str(row.get("char_id", "")) == new_id:
			found = true
			assert_true(bool(row.get("foreign", false)), "summary foreign")
			assert_eq(str(row.get("origin_world_name", "")), "朋友的江湖")
	assert_true(found, "in char list")
	# 再匯入同一份 → foreign_not_newer
	assert_eq(reason("passport_import", { "passport": good }), "foreign_not_newer")

func test_name_taken_then_new_name_and_too_many_chars() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var pp := _pp(_foreign_dict("本地俠", "ch_fx000009"))
	assert_eq(reason("passport_import", { "passport": pp }), "passport_name_taken")
	assert_eq(reason("passport_import", { "passport": pp, "new_name": "壞 名" }), "bad_value:new_name")
	var r := ok("passport_import", { "passport": pp, "new_name": "改名俠" })
	var imp = host().char_store.load_char(s().identity, str(r["char_id"]))
	assert_eq(str(imp.name), "改名俠")
	assert_eq(host().char_ref_by_name("改名俠").get("char_id", ""), str(r["char_id"]), "name registered")
	# 第三個角色 → 滿了
	make_char("第三人")
	var pp2 := _pp(_foreign_dict("客俠五", "ch_fx000010"))
	assert_eq(reason("passport_import", { "passport": pp2 }), "too_many_chars")

func test_replace_newer_keeps_local_id_and_char_active() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("客俠六", "ch_fx000020")
	d["money"] = 100
	var r := ok("passport_import", { "passport": _pp(d, 1000.0) })
	var local_id := str(r["char_id"])
	var n_before: int = host().char_store.count(s().identity)
	# 舊的 → not newer
	assert_eq(reason("passport_import", { "passport": _pp(d, 900.0) }), "foreign_not_newer")
	# 選著那個本地角色 → char_active
	ok("char_select", { "char_id": local_id })
	d["money"] = 555
	assert_eq(reason("passport_import", { "passport": _pp(d, 2000.0) }), "char_active")
	ok("char_select", { "char_id": str(host().char_ref_by_name("本地俠")["char_id"]) })
	# 新的 → 取代：本地 id 不變、角色數不變
	clear_events()
	var r2 := ok("passport_import", { "passport": _pp(d, 2000.0) })
	assert_eq(str(r2["char_id"]), local_id, "same local id")
	assert_eq(host().char_store.count(s().identity), n_before, "count unchanged")
	assert_true(bool(lastp("foreign_imported").get("replaced", false)), "replaced flag")
	var imp = host().char_store.load_char(s().identity, local_id)
	assert_eq(int(imp.money), 100, "M3c2 第三輪審查：取代時銀兩沿用本地角色的（不是檔案的 555）")
	assert_eq(float(ws.world["foreign_imports"][OTHER_WORLD + "/ch_fx000020"]["saved_s"]), 2000.0)

func test_foreign_owned_by_other_identity() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("客俠七", "ch_fx000030")
	var peer := connect_player("朋友")
	var pp := _pp(d, 1000.0)
	assert_true(send_as(peer, "passport_import", { "passport": pp }).get("ok", false), "friend imports first")
	assert_eq(reason("passport_import", { "passport": _pp(d, 5000.0) }), "foreign_owned")

func test_divine_registry_free_and_taken() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	ws.options["allow_foreign_divine"] = true   # M3c2 第二輪審查：R10 的登記規則只在主機打開外來神兵時用
	# 登記空 → 帶入並登記給匯入的角色
	var d := _foreign_dict("持劍客", "ch_fx000040")
	d["inventory"]["items"].append({ "uid": "it_dv000001", "id": DIVINE, "n": 1, "born_s": 0.0 })
	d["inventory"]["items"].append({ "uid": "it_dv000002", "id": DIVINE, "n": 1, "born_s": 0.0 })
	var r := ok("passport_import", { "passport": _pp(d) })
	var cid := str(r["char_id"])
	assert_eq(host().loot.holder_of(DIVINE), cid, "registered to importer")
	var imp = host().char_store.load_char(s().identity, cid)
	assert_eq(int(imp.inventory.count(DIVINE)), 1, "only one copy kept")
	# 另一個世界帶來同一把：已有人持有 → 拿掉並列在清單
	var d2 := _foreign_dict("另一客", "ch_fx000041")
	d2["inventory"]["items"].append({ "uid": "it_dv000003", "id": DIVINE, "n": 1, "born_s": 0.0 })
	clear_events()
	var r2 := ok("passport_import", { "passport": _pp(d2, 1000.0, "w_third_world") })
	var imp2 = host().char_store.load_char(s().identity, str(r2["char_id"]))
	assert_eq(int(imp2.inventory.count(DIVINE)), 0, "taken divine removed")
	assert_true(_has_line(lastp("foreign_imported").get("dropped", []), "本世界已有人持有"), "listed")
	assert_eq(host().loot.holder_of(DIVINE), cid, "registry unchanged")

func test_server_option_toggle_via_panel_intent() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	ok("server_opts_set", { "key": "allow_foreign_characters", "value": "true" })
	assert_eq(ws.options["allow_foreign_characters"], true)
	assert_eq(sm.load_options(ws.world_id).get("allow_foreign_characters"), true, "saved to options.json")
	assert_eq(reason("server_opts_set", { "key": "allow_foreign_characters", "value": "maybe" }), "bad_value:value")
	ok("server_opts_set", { "key": "allow_foreign_characters", "value": "false" })
	assert_eq(ws.options["allow_foreign_characters"], false)

# ---------------------------------------------------------------- M3c2 審查（重複匯入、回流、取代、型別、編號）

func _treasure_item() -> String:
	for iid in tables()["items"]:
		var r: Dictionary = tables()["items"][iid]
		if str(r.get("rarity", "")) == "TREASURE" and not bool(r.get("divine", false)) and int(r.get("stack", 1)) <= 1:
			return str(iid)
	return ""

## 審查 #1：刪掉匯入的角色後，同一份檔案不能再匯一次（登記留著）
func test_review_delete_then_reimport_same_file_refused() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("客俠刪", "ch_fx000050")
	var pp := _pp(d, 1000.0)
	var r := ok("passport_import", { "passport": pp })
	var cid := str(r["char_id"])
	ok("char_delete", { "char_id": cid, "confirm_name": "客俠刪" })
	assert_false(host().char_store.has_char(s().identity, cid), "deleted")
	assert_eq(reason("passport_import", { "passport": pp }), "foreign_not_newer", "same file after delete")
	assert_eq(reason("passport_import", { "passport": _pp(d, 900.0) }), "foreign_not_newer", "older file after delete")
	# 原世界玩過、較新的檔案 → 可以（匯入本來就是複製，R9；同一個來源角色仍只對應一個本地角色）
	var r2 := ok("passport_import", { "passport": _pp(d, 2000.0) })
	assert_true(str(r2["char_id"]) != "", "newer file after delete imports")

## 審查 #1：被較新的匯入取代後，舊的本地角色護照（本世界簽的）不能再還原成第二份
func test_review_restore_superseded_foreign_refused() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("客俠還", "ch_fx000051")
	var r := ok("passport_import", { "passport": _pp(d, 1000.0) })
	var l1 := str(r["char_id"])
	var c1 = host().char_store.load_char(s().identity, l1)
	var wid := str(ws.world.get("world_id", ws.world_id))
	var own_pp := _json(Passport.make(str(ws.world.get("world_secret", "")), wid, c1.to_dict(), 5000.0))
	ok("char_delete", { "char_id": l1, "confirm_name": "客俠還" })
	var r2 := ok("passport_import", { "passport": _pp(d, 2000.0) })
	assert_true(str(r2["char_id"]) != l1, "new local char")
	assert_eq(reason("passport_restore", { "passport": own_pp }), "foreign_superseded")

## 審查 #2：A → B → A 回流、改過 world_id 的本世界護照、本世界角色 id → foreign_same_world
func test_review_bounce_back_and_tampered_world_id_refused() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var wid := str(ws.world.get("world_id", ws.world_id))
	# 角色的 origin_world 是本世界（從本世界匯出到 B，再從 B 匯出回來）
	var d := _foreign_dict("回流客", "ch_fx000060")
	d["origin_world"] = wid
	assert_eq(reason("passport_import", { "passport": _pp(d) }), "foreign_same_world", "origin_world")
	# 來源鏈：A → B → C → A
	var d2 := _foreign_dict("回流客二", "ch_fx000061")
	d2["origin_world"] = "w_b"
	d2["ext"] = { "foreign": { "world_id": "w_b", "via": [wid, "w_c"] } }
	assert_eq(reason("passport_import", { "passport": _pp(d2) }), "foreign_same_world", "via chain")
	# 本世界的護照、只把 world_id 改掉
	var mine: Dictionary = ch().to_dict()
	var pp := _json(Passport.make(str(ws.world.get("world_secret", "")), wid, mine, 9000.0))
	pp["world_id"] = OTHER_WORLD
	assert_eq(reason("passport_import", { "passport": pp }), "foreign_same_world", "tampered world_id")
	# 簽章也改壞，但角色 id 還是本世界的
	pp["sig"] = "0".repeat(64)
	assert_eq(reason("passport_import", { "passport": pp }), "foreign_same_world", "local char id")
	# 匯入後的角色帶著來源鏈
	var d3 := _foreign_dict("鏈客", "ch_fx000062")
	d3["origin_world"] = "w_zero"
	var r := ok("passport_import", { "passport": _pp(d3) })
	var imp = host().char_store.load_char(s().identity, str(r["char_id"]))
	assert_has(imp.ext["foreign"]["via"], "w_zero", "chain kept")

## 審查 #3：取代時本世界綁定的狀態沿用本地角色（錢莊、組織、坐牢、禁學、計數、冷卻、ext）
func test_review_replace_keeps_local_world_bound_state() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("客俠存", "ch_fx000070")
	var r := ok("passport_import", { "passport": _pp(d, 1000.0) })
	var cid := str(r["char_id"])
	var loc = host().char_store.load_char(s().identity, cid)
	loc.bank["money"] = 777
	loc.guild = "g_test_keep"
	loc.jail = { "sect": "shaolin", "room": "sl_siguo", "until_online_s": 99999.0, "reason": "BREACH", "rule": "", "days": 1, "notified": true, "scope": "SECT" }
	loc.sect_record["lockout"] = "shaolin"
	loc.counters["chore_day"] = { "day": 3, "n": { "q_ch_sl_saodi": 2 } }
	loc.quests["cd"] = { "q_bandit": 12345.0 }
	loc.ext["loot"] = { "lock": 7 }
	host().save_char(loc)
	var r2 := ok("passport_import", { "passport": _pp(d, 2000.0) })
	assert_eq(str(r2["char_id"]), cid)
	var imp = host().char_store.load_char(s().identity, cid)
	assert_eq(int(imp.bank["money"]), 777, "bank kept")
	assert_eq(str(imp.guild), "g_test_keep", "guild kept")
	assert_eq(str(imp.jail.get("sect", "")), "shaolin", "jail kept")
	assert_eq(str(imp.sect_record.get("lockout", "")), "shaolin", "lockout kept")
	assert_eq(int(imp.counters["chore_day"]["n"]["q_ch_sl_saodi"]), 2, "daily counters kept")
	assert_true(imp.quests["cd"].has("q_bandit"), "quest cooldowns kept")
	assert_eq(int(imp.ext["loot"]["lock"]), 7, "world-bound ext kept")
	assert_true(imp.ext.get("foreign") is Dictionary, "foreign tag")

## 審查 #5、#6：奇怪的型別不讓引擎報錯；重複的物品編號只留一件、匯入後全部換成主機的新編號
func test_review_odd_types_and_duplicate_uids() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("怪檔客", "ch_fx000080")
	d["sect_enemies"] = [{ "x": 1 }, 5, "shaolin"]
	d["sect_traitor"] = [[1], "wudang"]
	d["origin_world"] = 12
	d["inventory"]["items"].append({ "uid": 77, "id": "c_jingyao", "n": 1, "born_s": 0.0 })
	d["inventory"]["items"].append({ "uid": "u_dup", "id": "c_jingyao", "n": 1, "born_s": 0.0 })
	d["inventory"]["items"].append({ "uid": "u_dup", "id": "c_jingyao", "n": 2, "born_s": 0.0 })
	var san := ForeignImport.sanitize(_pp(d), tables(), GameData.rules, ws.options)
	assert_true(san["ok"], "sanitize survives odd types")
	assert_eq(san["char"]["sect_enemies"], ["shaolin"])
	assert_eq(san["char"]["sect_traitor"], ["wudang"])
	var dups := 0
	for it in san["char"]["inventory"]["items"]:
		if str(it["uid"]) == "u_dup":
			dups += 1
	assert_eq(dups, 1, "duplicate uid dropped")
	assert_true(_has_line(san["dropped"], "重複編號"), "dup listed")
	var r := ok("passport_import", { "passport": _pp(d) })
	var imp = host().char_store.load_char(s().identity, str(r["char_id"]))
	var seen := {}
	for it in imp.inventory.items:
		assert_false(seen.has(str(it["uid"])), "unique uid")
		seen[str(it["uid"])] = true
		assert_true(str(it["uid"]).begins_with("it_"), "host uid")
	var wuid := str(imp.inventory.equipped.get("WEAPON", ""))
	if wuid != "":
		assert_false(imp.inventory.find(wuid).is_empty(), "equipped remapped")

## 審查 #7（第一份）：珍品件數與銀兩上限；開房沒開放時外來角色不能進入
func test_review_treasure_cap_and_hosted_block() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var tid := _treasure_item()
	var d := _foreign_dict("珍客", "ch_fx000090")
	d["money"] = 5000000
	if tid != "":
		for i in 4:
			d["inventory"]["items"].append({ "uid": "it_tr%06d" % i, "id": tid, "n": 1, "born_s": 0.0 })
	var san := ForeignImport.sanitize(_pp(d), tables(), GameData.rules, ws.options)
	assert_eq(int(san["char"]["money"]) + ForeignImport.items_value(Inventory.from_dict(san["char"]["inventory"]), tables()),
		ForeignImport.FOREIGN_MONEY_CAP, "money + item value cap")
	if tid != "":
		var n := 0
		for it in san["char"]["inventory"]["items"]:
			if str(it["id"]) == tid:
				n += int(it["n"])
		assert_eq(n, ForeignImport.FOREIGN_TREASURE_MAX, "treasure cap")
		assert_true(_has_line(san["dropped"], "珍品"), "treasure listed")
	var r := ok("passport_import", { "passport": _pp(d) })
	var cid := str(r["char_id"])
	NetworkManager.mode = NetworkManager.Mode.ENET_HOST
	ws.options["allow_foreign_characters"] = false
	assert_eq(reason("char_select", { "char_id": cid }), "foreign_char_blocked", "hosted, option off")
	assert_true(s().character != null and str(s().character.name) == "本地俠", "still on local char")
	ws.options["allow_foreign_characters"] = true
	ok("char_select", { "char_id": cid })
	NetworkManager.mode = NetworkManager.Mode.OFFLINE
	ws.options["allow_foreign_characters"] = false

# ---------------------------------------------------------------- M3c2 第二輪審查

## #1（節奏與經濟）：高價輕巧的消耗品不能繞過 10 萬兩上限：銀兩＋物品收購總值 ≤ 上限
func test_review2_item_sell_value_capped_with_money() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var smoke := "c_smoke"
	if not tables()["items"].has(smoke):
		return
	var d := _foreign_dict("煙客", "ch_fx000080")
	d["money"] = 9999999
	d["combat_xp"] = 10000000
	for k in Character.ATTR_IDS:
		d["attrs"][k] = 30
	var stack := maxi(1, int(tables()["items"][smoke].get("stack", 1)))
	for i in ceili(300.0 / stack):
		d["inventory"]["items"].append({ "uid": "it_sm%06d" % i, "id": smoke, "n": stack, "born_s": 0.0 })
	var r := ForeignImport.sanitize(_pp(d), tables(), GameData.rules, ws.options)
	assert_true(r["ok"])
	var c: Dictionary = r["char"]
	var inv := Inventory.from_dict(c["inventory"])
	var total := int(c["money"]) + ForeignImport.items_value(inv, tables())
	assert_true(total <= ForeignImport.FOREIGN_MONEY_CAP, "total %d" % total)
	assert_true(inv.count(smoke) < 300, "smoke trimmed")
	assert_true(_has_line(r["dropped"], "物品收購總值超過外來角色上限"), str(r["dropped"]))
	# 物品本身就超過上限 → 銀兩 0
	assert_true(int(c["money"]) < EconCalc.sell_price(tables()["items"][smoke]), "money only fills the remainder: %d" % int(c["money"]))
	# 只有一點點東西 → 銀兩照帶（上限內）
	var d2 := _foreign_dict("小客", "ch_fx000081")
	d2["money"] = 500
	var r2 := ForeignImport.sanitize(_pp(d2), tables(), GameData.rules, ws.options)
	assert_eq(int(r2["char"]["money"]), 500)

## #2（帶走角色）：修練次數 ≤ 基本內功 × 5、氣上限加成 ≤ 修練次數 × 8
func test_review2_cultivation_and_qi_bonus_clamped() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("氣客", "ch_fx000082")
	d["qi_bonus"] = 1000000
	d["cultivations"] = 999999
	d["skills"]["basic_inner"] = { "level": 10, "prof": SkillBook.prof_for_level("basic_inner", 10, tables()) }
	var r := ForeignImport.sanitize(_pp(d), tables(), GameData.rules, ws.options)
	var c: Dictionary = r["char"]
	var lv := int(c["skills"]["basic_inner"]["level"])
	assert_eq(int(c["cultivations"]), lv * Survival.CULTIVATE_PER_INNER)
	assert_eq(int(c["qi_bonus"]), lv * Survival.CULTIVATE_PER_INNER * Survival.CULTIVATE_QI)
	assert_true(_has_line(r["dropped"], "修練次數"), str(r["dropped"]))
	# 沒有基本內功 → 0
	var d2 := _foreign_dict("氣客二", "ch_fx000083")
	d2["skills"].erase("basic_inner")
	d2["qi_bonus"] = 40
	d2["cultivations"] = 5
	var c2: Dictionary = ForeignImport.sanitize(_pp(d2), tables(), GameData.rules, ws.options)["char"]
	assert_eq(int(c2["qi_bonus"]), 0)
	assert_eq(int(c2["cultivations"]), 0)

## #3／#4：新手期學點的一輩子上限（counters.novice_lp）跟著角色走；取代時取兩邊較大的
func test_review2_novice_lp_carried() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("學客", "ch_fx000084")
	d["counters"][Learning.NOVICE_LP_KEY] = 4000
	var r := ok("passport_import", { "passport": _pp(d, 1000.0) })
	var cid := str(r["char_id"])
	var imp = host().char_store.load_char(s().identity, cid)
	assert_eq(int(imp.counters.get(Learning.NOVICE_LP_KEY, 0)), 4000, "fresh import keeps lifetime novice LP")
	assert_eq(Learning.novice_lp_left(imp, GameData.rules), 0, "no more novice LP")
	# 取代：本地 3000、檔案 1000 → 3000
	imp.counters[Learning.NOVICE_LP_KEY] = 3000
	host().save_char(imp)
	d["counters"][Learning.NOVICE_LP_KEY] = 1000
	ok("passport_import", { "passport": _pp(d, 2000.0) })
	var imp2 = host().char_store.load_char(s().identity, cid)
	assert_eq(int(imp2.counters.get(Learning.NOVICE_LP_KEY, 0)), 3000, "replace keeps the larger")

## #1（帶走角色）：取代後，取代前存下的本世界護照（online_s 較大）不能還原
func test_review2_replace_then_old_passport_restore_refused() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("回溯客", "ch_fx000085")
	d["online_s"] = 36000.0
	var r := ok("passport_import", { "passport": _pp(d, 1000.0) })
	var cid := str(r["char_id"])
	# 在本世界玩了 5 小時：本地 online_s 54000，客戶端存著那時的護照
	var loc = host().char_store.load_char(s().identity, cid)
	loc.online_s = 54000.0
	loc.money = 5000
	host().save_char(loc)
	var wid := str(ws.world.get("world_id", ws.world_id))
	var p1 := _json(Passport.make(str(ws.world.get("world_secret", "")), wid, loc.to_dict(), 54000.0))
	# 原世界再玩 1 小時（11 小時）→ 取代
	d["online_s"] = 39600.0
	ok("passport_import", { "passport": _pp(d, 2000.0) })
	var rep = host().char_store.load_char(s().identity, cid)
	assert_true(float(rep.online_s) > 54000.0, "online_s never goes back: %s" % str(rep.online_s))
	assert_eq(reason("passport_restore", { "passport": p1 }), "passport_not_needed")

## #4（帶走角色）：外來神兵預設一律拿掉（沒人持有也一樣），主機打開 allow_foreign_divine 才照登記
func test_review2_divine_stripped_by_default() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	assert_false(ws.options.get("allow_foreign_divine", false) == true, "default off")
	var d := _foreign_dict("偽劍客", "ch_fx000086")
	d["inventory"]["items"].append({ "uid": "it_dv000009", "id": DIVINE, "n": 1, "born_s": 0.0 })
	clear_events()
	var r := ok("passport_import", { "passport": _pp(d) })
	var imp = host().char_store.load_char(s().identity, str(r["char_id"]))
	assert_eq(int(imp.inventory.count(DIVINE)), 0, "stripped")
	assert_eq(str(host().loot.holder_of(DIVINE)), "", "not registered")
	assert_true(_has_line(lastp("foreign_imported").get("dropped", []), "不接受外來神兵"), "listed")

## #4（帶走角色）：每個身分最多帶進 3 個不同的來源角色（刪了也算；同一個來源的更新不算）
func test_review2_foreign_source_quota() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var ids: Array = []
	for i in 3:
		var d := _foreign_dict("額客%d" % i, "ch_fxq0000%d" % i)
		var r := ok("passport_import", { "passport": _pp(d, 1000.0) })
		ids.append(str(r["char_id"]))
		if i < 2:
			ok("char_delete", { "char_id": str(r["char_id"]), "confirm_name": "額客%d" % i })
	var d4 := _foreign_dict("額客9", "ch_fxq00009")
	assert_eq(reason("passport_import", { "passport": _pp(d4, 1000.0) }), "foreign_quota", "4th source refused")
	# 已登記的來源：較新的檔案仍可更新
	var d3 := _foreign_dict("額客2", "ch_fxq00002")
	var r3 := ok("passport_import", { "passport": _pp(d3, 2000.0) })
	assert_eq(str(r3["char_id"]), str(ids[2]), "update of a registered source still works")
	assert_true(UiClient.reason_inline("foreign_quota").contains("3 個"), UiClient.reason_inline("foreign_quota"))

# ---------------------------------------------------------------- M3c2 第三輪審查（重複匯入複製、NaN、學點上限、身分接手）

## #1：取代只帶進成長；銀兩與身上物品沿用本地角色的（改大 saved_s 重匯不會再拿一次錢）
func test_review3_replace_keeps_local_money_and_items() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("複製客", "ch_fx000300")
	d["money"] = 90000
	d["combat_xp"] = 1000
	var r := ok("passport_import", { "passport": _pp(d, 1000.0) })
	var cid := str(r["char_id"])
	# 錢存進錢莊、身上清空（存錢莊／給別人）
	var loc = host().char_store.load_char(s().identity, cid)
	loc.bank["money"] = int(loc.money)
	loc.money = 0
	loc.inventory = Inventory.new()
	host().save_char(loc)
	# 改大 saved_s 再匯（實戰也變多：成長要帶進來）
	d["combat_xp"] = 5000
	clear_events()
	ok("passport_import", { "passport": _pp(d, 99999999.0) })
	var imp = host().char_store.load_char(s().identity, cid)
	assert_eq(int(imp.money), 0, "money not refilled")
	assert_eq(int(imp.inventory.items.size()), 0, "items not refilled")
	assert_eq(int(imp.bank["money"]), 90000, "bank kept")
	assert_eq(int(imp.combat_xp), 5000, "progression updated")
	assert_true(_has_line(lastp("foreign_imported").get("dropped", []), "沿用本世界"), "listed")

## #1：刪掉本地角色後再匯較新的檔案：只帶進成長，銀兩與物品不再給
func test_review3_delete_then_newer_reimport_has_no_goods() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("刪匯客", "ch_fx000301")
	d["money"] = 50000
	var r := ok("passport_import", { "passport": _pp(d, 1000.0) })
	var first = host().char_store.load_char(s().identity, str(r["char_id"]))
	assert_eq(int(first.money), 50000, "first import brings money")
	ok("char_delete", { "char_id": str(r["char_id"]), "confirm_name": "刪匯客" })
	clear_events()
	var r2 := ok("passport_import", { "passport": _pp(d, 2000.0) })
	var imp = host().char_store.load_char(s().identity, str(r2["char_id"]))
	assert_eq(int(imp.money), 0, "no money on second import")
	assert_eq(int(imp.inventory.items.size()), 0, "no items on second import")
	assert_true(_has_line(lastp("foreign_imported").get("dropped", []), "第一次匯入時已經帶進過"), "listed")

## 審查二 #3：取代時本地角色在本世界合法拿到的神兵留著（登記不動）
func test_review3_replace_keeps_local_divine() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("神兵客", "ch_fx000302")
	var r := ok("passport_import", { "passport": _pp(d, 1000.0) })
	var cid := str(r["char_id"])
	var loc = host().char_store.load_char(s().identity, cid)
	loc.inventory.items.append({ "uid": "it_dvloc001", "id": DIVINE, "n": 1, "born_s": 0.0 })
	host().save_char(loc)
	host().loot.divine_registry()[DIVINE] = cid
	ok("passport_import", { "passport": _pp(d, 2000.0) })
	var imp = host().char_store.load_char(s().identity, cid)
	assert_eq(int(imp.inventory.count(DIVINE)), 1, "local divine kept")
	assert_eq(str(host().loot.holder_of(DIVINE)), cid, "registry kept")

## 審查二 #4：本地角色刪掉後，別的身分也不能接手那個來源（原身分的名額不會空出來）
func test_review3_other_identity_cannot_take_deleted_source() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("接手客", "ch_fx000303")
	var r := ok("passport_import", { "passport": _pp(d, 1000.0) })
	ok("char_delete", { "char_id": str(r["char_id"]), "confirm_name": "接手客" })
	var n_before := IntentsHostRef.foreign_sources_of(host(), s().identity)
	var peer := connect_player("朋友")
	assert_eq(reason_as(peer, "passport_import", { "passport": _pp(d, 5000.0) }), "foreign_owned")
	assert_eq(IntentsHostRef.foreign_sources_of(host(), s().identity), n_before, "quota unchanged")

## 審查二 #2：NaN 的 saved_s 不收；角色裡的 NaN 換成 0；world.json 的 null 讀得回來
func test_review3_nan_saved_s_and_floats() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("非數客", "ch_fx000304")
	var pp := Passport.make(OTHER_SECRET, OTHER_WORLD, d, 1000.0)
	pp["saved_s"] = NAN
	assert_eq(Passport.check_format(pp), "passport_bad_format", "NaN saved_s")
	pp["saved_s"] = INF
	assert_eq(Passport.check_format(pp), "passport_bad_format", "INF saved_s")
	var pp2 := Passport.make(OTHER_SECRET, OTHER_WORLD, _foreign_dict("非數客", "ch_fx000304"), 1000.0)
	pp2["char"]["online_s"] = NAN
	var san := ForeignImport.sanitize(pp2, tables(), host().rules, ws.options)
	assert_true(bool(san["ok"]))
	assert_true(is_finite(float(san["char"]["online_s"])), "online_s finite")
	assert_eq(ForeignImport.finite_floats({ "a": [1.0, NAN, { "b": -INF }] }), { "a": [1.0, 0.0, { "b": 0.0 }] })
	var w := { "schema_version": 1, "foreign_imports": { "x/y": { "char_id": "c", "identity": "i", "saved_s": null, "imported_s": null } } }
	var cw: Dictionary = sm._coerce_world(w)
	assert_eq(float(cw["foreign_imports"]["x/y"]["saved_s"]), 0.0, "null saved_s → 0")

## 審查一 #2：規則不限學點（xuedian_cap 0）時，匯入仍截到 65200
func test_review3_learn_points_capped_when_rule_unlimited() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("學點客", "ch_fx000305")
	d["learn_points"] = 99999999
	var san := ForeignImport.sanitize(Passport.make(OTHER_SECRET, OTHER_WORLD, d, 1000.0), tables(), { "xuedian_cap": 0 }, ws.options)
	assert_eq(int(san["char"]["learn_points"]), ForeignImport.FOREIGN_LP_CAP_FALLBACK)
	var san2 := ForeignImport.sanitize(Passport.make(OTHER_SECRET, OTHER_WORLD, d, 1000.0), tables(), { "xuedian_cap": 100 }, ws.options)
	assert_eq(int(san2["char"]["learn_points"]), 100, "rule cap still wins when set")

## 介面審查 #2：本世界沒有的門派不顯示內部 id
func test_review3_unknown_sect_line_has_no_id() -> void:
	if not game_ok():
		return
	make_char("本地俠")
	var d := _foreign_dict("外派客", "ch_fx000306")
	d["sect"] = "xiaoyao"
	var san := ForeignImport.sanitize(Passport.make(OTHER_SECRET, OTHER_WORLD, d, 1000.0), tables(), host().rules, ws.options)
	for line in san["dropped"]:
		assert_false(str(line).contains("xiaoyao"), str(line))
	assert_true(_has_line(san["dropped"], "原門派本世界沒有開放"))
