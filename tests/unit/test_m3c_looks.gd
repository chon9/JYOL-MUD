extends "res://tests/unit/test_world_fixture.gd"
## M3c WP-LOOKS（M3C_PLAN §3）：Looks 純函式、Character.battle_look 三狀態、存讀、創角帶 look、set_look 原因碼。

const F := preload("res://tests/unit/test_character_fixtures.gd")

func before_each() -> void:
	world_name = "w_m3c_looks"
	super.before_each()

# ---------------------------------------------------------------- Looks（純函式）

func test_looks_table() -> void:
	assert_eq(Looks.LOOK_MAX, 8)
	assert_eq(Looks.LOOK_MAX, Protocol.LOOK_MAX, "與協定同值")
	assert_eq(Looks.NAMES_M, ["布衣", "書生", "獵戶", "浪子", "少年俠客", "壯漢", "刀客", "富家公子", "西域旅人"])
	assert_eq(Looks.NAMES_F, ["布衣", "俠女", "村姑", "千金小姐", "江湖女子", "少女", "女刀客", "醫女", "苗疆少女"])
	for i in 9:
		assert_true(Looks.valid(i), str(i))
	assert_false(Looks.valid(-1))
	assert_false(Looks.valid(9))

func test_looks_art_ref() -> void:
	assert_eq(Looks.art_ref("M", 0), "player_m")
	assert_eq(Looks.art_ref("F", 0), "player_f")
	assert_eq(Looks.art_ref("M", 1), "look_m01")
	assert_eq(Looks.art_ref("M", 8), "look_m08")
	assert_eq(Looks.art_ref("F", 5), "look_f05")
	assert_eq(Looks.art_ref("F", 9), "player_f", "不合法 → 0 號")
	assert_eq(Looks.art_ref("M", -3), "player_m")
	assert_eq(Looks.art_ref("", 2), "look_m02", "性別不明當男")

func test_looks_battle_look_and_names() -> void:
	assert_eq(Looks.battle_look("", "M", 5), "look_m05")
	assert_eq(Looks.battle_look("shaolin", "M", 5), "shaolin_m", "入派：門派服裝優先")
	assert_eq(Looks.battle_look("emei", "F", 3), "emei_f")
	assert_eq(Looks.battle_look("", "F", 0), "player_f")
	assert_eq(Looks.name_of("M", 5), "壯漢")
	assert_eq(Looks.name_of("F", 7), "醫女")
	assert_eq(Looks.name_of("F", 0), "布衣")
	assert_eq(Looks.name_of("M", 42), "布衣")
	var cat := Looks.catalog("F")
	assert_eq(cat.size(), 9)
	assert_eq(cat[8], { "look": 8, "name": "苗疆少女", "art": "look_f08" })

func test_looks_sanitize() -> void:
	assert_eq(Looks.sanitize(3), 3)
	assert_eq(Looks.sanitize(3.0), 3, "JSON 數字是 float")
	assert_eq(Looks.sanitize(3.5), 0)
	assert_eq(Looks.sanitize(9), 0)
	assert_eq(Looks.sanitize(-1), 0)
	assert_eq(Looks.sanitize("4"), 0)
	assert_eq(Looks.sanitize(null), 0)

func test_every_look_resolves_to_its_own_idle_art() -> void:
	for g in ["M", "F"]:
		for i in range(1, 9):
			var ref := Looks.art_ref(g, i)
			var tex := ArtRegistry.unit_texture(ref, "PLAYER", "idle")
			assert_true(tex != null, ref + " idle")
			if tex != null:
				assert_true(tex.resource_path.ends_with("unit_%s_idle.png" % ref), "%s → %s" % [ref, tex.resource_path])

# ---------------------------------------------------------------- Character

func test_character_battle_look_three_states() -> void:
	var c := Character.new()
	c.gender = "M"
	c.appearance = 5
	assert_eq(c.battle_look(), "look_m05", "未入派：造型")
	c.sect = "shaolin"
	assert_eq(c.battle_look(), "shaolin_m", "入派：門派服裝")
	assert_eq(c.appearance, 5, "造型保留")
	c.sect = ""
	assert_eq(c.battle_look(), "look_m05", "離派：回到造型")
	c.appearance = 0
	assert_eq(c.battle_look(), "player_m", "0 號＝布衣（舊行為）")
	c.gender = "F"
	assert_eq(c.battle_look(), "player_f")

func test_character_save_roundtrip_and_old_saves() -> void:
	var c := Character.new()
	c.id = "ch_looks01"
	c.gender = "F"
	c.appearance = 7
	var d := c.to_dict()
	assert_eq(d["appearance"], 7)
	var c2 := Character.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(c2.appearance, 7, "JSON 往返（float → int）")
	assert_type(c2.appearance, TYPE_INT)
	assert_eq(c2.battle_look(), "look_f07")
	d.erase("appearance")
	assert_eq(Character.from_dict(d).appearance, 0, "舊存檔沒有 appearance → 0")
	d["appearance"] = 99
	assert_eq(Character.from_dict(d).appearance, 0, "不合法 → 0")
	d["appearance"] = "3"
	assert_eq(Character.from_dict(d).appearance, 0, "型別錯 → 0")

func test_character_sheet_and_summary_keys() -> void:
	var t := F.tables()
	var p := { "id": "ch_looks02", "identity": "local_x", "name": "阿朱", "gender": "F", "birth_month": 7,
		"birth_city": "dali", "alloc": { "wit": 5 }, "look": 3 }
	var roll := { "str": 20, "guts": 19, "wit": 21, "luck": 19, "cal": 19, "agi": 20, "con": 20 }
	var c := CharacterFactory.create(p, roll, t, F.options(), F.rng(1), 3.0)
	assert_eq(c.appearance, 3, "CharacterFactory 讀 look")
	var sh := c.to_sheet(t, F.options(), {})
	assert_eq(sh["look"], "look_f03")
	assert_eq(sh["appearance"], 3)
	assert_eq(c.to_summary(t)["look"], "look_f03")
	assert_eq(c.to_combatant(t, F.options(), 0, 1)["look"], "look_f03", "戰鬥快照跟著造型")
	p["look"] = 12
	assert_eq(CharacterFactory.create(p, roll, t, F.options(), F.rng(1), 3.0).appearance, 0, "不合法 → 0")
	p.erase("look")
	assert_eq(CharacterFactory.create(p, roll, t, F.options(), F.rng(1), 3.0).appearance, 0, "沒帶 → 0")

# ---------------------------------------------------------------- 主機（真的 intent 路徑）

func _create(char_name: String, gender: String, look: Variant) -> Dictionary:
	ok("char_roll")
	var a := { "name": char_name, "gender": gender, "birth_month": 3, "birth_city": "xixia", "alloc": { "wit": 5 } }
	if look != null:
		a["look"] = look
	return send("char_create", a)

func test_char_create_with_look() -> void:
	if not game_ok():
		return
	var r := _create("造型甲", "M", 5)
	assert_true(r.get("ok", false), str(r))
	assert_eq(ch().appearance, 5)
	assert_eq(sheet().get("look"), "look_m05")
	assert_eq(sheet().get("appearance"), 5)
	var summary: Array = cs.char_list
	var mine := summary.filter(func(x): return str(x.get("char_id", "")) == str(ch().id))
	assert_eq(mine.size(), 1)
	if mine.size() == 1:
		assert_eq(mine[0].get("look"), "look_m05", "summary.look（選角畫面）")
	# 存檔 → 重新載入
	var cid := str(ch().id)
	var loaded = host().char_store.load_char(s().identity, cid)
	assert_eq(loaded.appearance, 5, "存檔落地")

func test_char_create_look_validation() -> void:
	if not game_ok():
		return
	assert_eq(str(_create("造型乙", "M", 9).get("reason", "")), "bad_value:look", "協定範圍")
	assert_eq(str(_create("造型乙", "M", -1).get("reason", "")), "bad_value:look")
	assert_eq(str(_create("造型乙", "M", "3").get("reason", "")), "bad_type:look")
	var r := _create("造型乙", "F", null)
	assert_true(r.get("ok", false), "不帶 look（舊客戶端）→ 0 號：%s" % str(r))
	assert_eq(ch().appearance, 0)
	assert_eq(sheet().get("look"), "player_f")
	# 第二道（處理器）：繞過協定直接呼叫
	assert_eq(IntentsChar.look_arg({ "look": 9 }), -1)
	assert_eq(IntentsChar.look_arg({ "look": 2.0 }), 2)
	assert_eq(IntentsChar.look_arg({}), 0)

func test_set_look_reasons_and_event() -> void:
	if not game_ok():
		return
	assert_eq(reason("set_look", { "look": 1 }), "no_character", "沒有角色")
	assert_true(_create("造型丙", "M", 5).get("ok", false))
	clear_events()
	var r := ok("set_look", { "look": 2 })
	assert_eq(int(r.get("look", -1)), 2)
	assert_eq(ch().appearance, 2)
	assert_eq(sheet().get("look"), "look_m02", "角色表立即更新")
	var e := last("look_changed")
	assert_eq(bool(e.get("ui", false)), true, "ui 事件")
	var p: Dictionary = e.get("p", {})
	assert_eq(int(p.get("look", -1)), 2)
	assert_eq(str(p.get("look_name", "")), "獵戶")
	assert_eq(str(p.get("shown", "")), "look_m02")
	assert_eq(str(p.get("note", "")), "", "未入派沒有附註")
	for i in 9:
		assert_true(send("set_look", { "look": i }).get("ok", false), "look %d" % i)
	assert_eq(reason("set_look", { "look": 9 }), "bad_value:look")
	assert_eq(reason("set_look", { "look": -1 }), "bad_value:look")
	assert_eq(reason("set_look", {}), "missing_arg:look")
	assert_eq(reason("set_look", { "look": "2" }), "bad_type:look")
	assert_eq(ch().appearance, 8, "失敗不改")
	# 存檔
	var loaded = host().char_store.load_char(s().identity, str(ch().id))
	assert_eq(loaded.appearance, 8, "set_look 之後存檔")
	# 處理器第二道
	assert_eq(str(IntentsChar.set_look(host(), s(), { "look": 42 }).get("reason", "")), "bad_look")

func test_set_look_in_sect_keeps_uniform() -> void:
	if not game_ok():
		return
	assert_true(_create("造型丁", "M", 4).get("ok", false))
	ch().sect = "shaolin"
	clear_events()
	ok("set_look", { "look": 6 })
	assert_eq(ch().appearance, 6)
	assert_eq(sheet().get("look"), "shaolin_m", "入派中顯示門派服裝")
	assert_eq(sheet().get("appearance"), 6)
	var p := lastp("look_changed")
	assert_eq(str(p.get("shown", "")), "shaolin_m")
	assert_eq(str(p.get("note", "")), "（拜在門下時仍穿門派服裝）")
	ch().sect = ""
	host().flush_session(s(), true)
	ws.flush()
	assert_eq(ch().battle_look(), "look_m06", "離派回到造型")

func test_set_look_in_battle_is_refused() -> void:
	if not game_ok():
		return
	assert_true(_create("造型戊", "M", 1).get("ok", false))
	make_strong()
	var bid := start_battle(["m_rabbit"])
	assert_true(bid != 0, "battle started")
	var units: Array = cs.battle_state.get("units", [])
	var mine := units.filter(func(u): return int(u.get("uid", -1)) == int(cs.battle_state.get("my_uid", -2)))
	assert_eq(mine.size(), 1, "battle snapshot has my unit")
	if mine.size() == 1:
		assert_eq(str(mine[0].get("look", "")), "look_m01", "戰鬥快照自己的單位用造型")
	assert_eq(reason("set_look", { "look": 3 }), "in_battle", "戰鬥中不能換（IDLE）")
	assert_eq(ch().appearance, 1)

func test_set_look_allowed_in_jail() -> void:
	if not game_ok():
		return
	assert_true(_create("造型己", "F", 1).get("ok", false))
	ch().jail = { "sect": "shaolin", "room": str(ch().location.get("room", "")), "until_online_s": ch().online_s + 99999.0,
		"reason": "BREACH", "rule": "test" }
	assert_eq(reason("move", { "dir": "N" }), "jailed", "坐牢中一般動作被擋（確認確實在牢裡）")
	assert_true(send("set_look", { "look": 4 }).get("ok", false), "坐牢中也可以換")
	assert_eq(ch().appearance, 4)
