extends "res://tests/test_case.gd"
## WP-CHAR：擲骰、分配驗證、名稱驗證、初始角色。

const F := preload("res://tests/unit/test_character_fixtures.gd")

func test_roll_range_1000_times() -> void:
	var rng := F.rng(777)
	var seen_min := 99
	var seen_max := 0
	for i in 1000:
		var r := CharacterFactory.roll(rng)
		assert_eq(r.size(), 7)
		for a in Character.ATTR_IDS:
			var v: int = r[a]
			if v < 13 or v > 25:
				fail("roll out of range %s=%d" % [a, v])
				return
			seen_min = min(seen_min, v)
			seen_max = max(seen_max, v)
	assert_eq(seen_min, 13, "13 reachable")
	assert_eq(seen_max, 25, "25 reachable")

func test_roll_deterministic_by_seed() -> void:
	assert_eq(CharacterFactory.roll(F.rng(5)), CharacterFactory.roll(F.rng(5)))

func test_validate_alloc() -> void:
	assert_eq(CharacterFactory.validate_alloc({ "wit": 5 }), "")
	assert_eq(CharacterFactory.validate_alloc({ "wit": 2, "str": 3 }), "")
	assert_eq(CharacterFactory.validate_alloc({ "wit": 2.0, "str": 3.0 }), "", "integral floats accepted")
	assert_eq(CharacterFactory.validate_alloc({ "wit": 4 }), "bad_alloc", "sum 4")
	assert_eq(CharacterFactory.validate_alloc({ "wit": 6 }), "bad_alloc", "sum 6")
	assert_eq(CharacterFactory.validate_alloc({ "wit": 6, "str": -1 }), "bad_alloc", "negative")
	assert_eq(CharacterFactory.validate_alloc({ "foo": 5 }), "bad_alloc", "unknown key")
	assert_eq(CharacterFactory.validate_alloc({ "wit": 2.5, "str": 2.5 }), "bad_alloc", "fractional")
	assert_eq(CharacterFactory.validate_alloc({ "wit": "5" }), "bad_alloc", "string value")
	assert_eq(CharacterFactory.validate_alloc({}), "bad_alloc", "empty")

func test_validate_name() -> void:
	assert_eq(CharacterFactory.validate_name("測試俠客"), "")
	assert_eq(CharacterFactory.validate_name("一二三四五六七八"), "", "8 chars ok")
	assert_eq(CharacterFactory.validate_name("一二三四五六七八九"), "bad_name", "9 chars")
	assert_eq(CharacterFactory.validate_name(""), "bad_name")
	assert_eq(CharacterFactory.validate_name("阿 朱"), "bad_name", "space")
	assert_eq(CharacterFactory.validate_name("阿　朱"), "bad_name", "fullwidth space")
	assert_eq(CharacterFactory.validate_name("[b]朱"), "bad_name")
	assert_eq(CharacterFactory.validate_name("{x}"), "bad_name")
	assert_eq(CharacterFactory.validate_name("<朱>"), "bad_name")
	assert_eq(CharacterFactory.validate_name("朱\u0007"), "bad_name", "control char")
	assert_eq(CharacterFactory.validate_name("阿" + String.chr(0x200B) + "朱"), "bad_name", "zero-width space")
	assert_eq(CharacterFactory.validate_name(String.chr(0x200E) + "阿朱"), "bad_name", "LRM")
	assert_eq(CharacterFactory.validate_name("阿朱" + String.chr(0xFEFF)), "bad_name", "BOM")
	assert_eq(CharacterFactory.validate_name(String.chr(0x2060)), "bad_name", "word joiner only")
	assert_eq(CharacterFactory.validate_name("阿朱"), "")

func test_create_initial_character() -> void:
	var t := F.tables()
	var roll := { "str": 20, "guts": 19, "wit": 21, "luck": 19, "cal": 19, "agi": 20, "con": 20 }
	var p := { "id": "ch_0a0b0c0d", "identity": "local_x", "name": "阿朱", "gender": "F", "birth_month": 7,
		"birth_city": "dali", "alloc": { "wit": 5 } }
	var c := CharacterFactory.create(p, roll, t, F.options(), F.rng(1), 3.0)
	assert_eq(c.id, "ch_0a0b0c0d")
	assert_eq(c.identity, "local_x")
	assert_eq(c.gender, "F")
	assert_eq(c.birth_month, 7)
	assert_eq(c.attrs["wit"], 26, "alloc may exceed 25")
	assert_eq(c.attrs["str"], 20)
	assert_eq(c.learn_points, 100)
	assert_eq(c.money, 100)
	assert_eq(c.location, { "region": "dali", "room": "dl_square" })
	assert_eq(c.respawn, { "region": "", "room": "" })
	assert_eq(c.created_s, 3.0)
	assert_eq(c.inventory.count("c_jingyao"), 5)
	var w: Dictionary = c.inventory.find(c.inventory.equipped["WEAPON"])
	var a: Dictionary = c.inventory.find(c.inventory.equipped["ARMOR"])
	assert_eq(w.get("id"), "w_mudao", "木刀 equipped")
	assert_eq(a.get("id"), "a_bupao", "布衣 equipped")
	var d := c.derived(t, F.options())
	assert_eq(c.vitals["jing"], d["jing_max"])
	assert_eq(c.vitals["qi"], d["qi_max"])
	assert_eq(c.vitals["shen"], d["shen_max"])
	assert_eq(c.vitals["neili"], 0)
	assert_eq(c.vitals["food"], 100)
	assert_eq(c.vitals["water"], 100)
	assert_eq(c.morality, 0)
	for it in c.inventory.items:
		assert_true(String(it["uid"]).begins_with("it_") and String(it["uid"]).length() == 11, "uid format " + it["uid"])
