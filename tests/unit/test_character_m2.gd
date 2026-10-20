extends "res://tests/test_case.gd"
## WP-PK：Character 的 M2 新欄位（M2_PLAN 4.6.5、4.8、6.1）。

const F := preload("res://tests/unit/test_character_fixtures.gd")

func test_new_fields_roundtrip() -> void:
	var c := F.new_char()
	c.pk = 2
	c.pk_stamp_s = 1234.5
	c.prefs = { "accept_challenge": false, "accept_party": true }
	c.origin_world = "w_other"
	var d := c.to_dict()
	for k in ["pk", "pk_stamp_s", "prefs", "origin_world"]:
		assert_has(d, k, "to_dict key")
	var c2 := Character.from_dict(d)
	assert_eq(c2.to_dict(), d, "roundtrip")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	var c3 := Character.from_dict(parsed)
	assert_eq(c3.to_dict(), d, "json roundtrip")
	assert_type(c3.pk, TYPE_INT)
	assert_type(c3.pk_stamp_s, TYPE_FLOAT)
	assert_type(c3.prefs["accept_challenge"], TYPE_BOOL)

func test_old_save_fills_defaults() -> void:
	var c := Character.from_dict({ "id": "ch_old", "name": "舊角", "pk": 1 })
	assert_eq(c.pk, 1)
	assert_eq(c.pk_stamp_s, 0.0)
	assert_eq(c.prefs, { "accept_challenge": true, "accept_party": true })
	assert_eq(c.origin_world, "")
	var bad := Character.from_dict({ "prefs": { "accept_party": false, "junk": 5 } })
	assert_eq(bad.prefs, { "accept_challenge": true, "accept_party": false }, "unknown pref keys dropped")
	var weird := Character.from_dict({ "prefs": "x" })
	assert_eq(weird.prefs, Character.default_prefs())

func test_pk_value_decays_with_online_time() -> void:
	var c := F.new_char()
	c.pk = 3
	c.pk_stamp_s = 100.0
	c.online_s = 100.0
	assert_eq(c.pk_value(), 3)
	c.online_s = 1899.0
	assert_eq(c.pk_value(), 3)
	c.online_s = 1900.0
	assert_eq(c.pk_value(), 2)
	c.online_s = 3700.0
	assert_eq(c.pk_value(), 1)

func test_add_pk_normalizes_first() -> void:
	var c := F.new_char()
	c.pk = 3
	c.pk_stamp_s = 0.0
	c.online_s = 3700.0          # 目前值 = 1
	assert_eq(c.add_pk(1), 2, "1 + 1")
	assert_eq(c.pk, 2, "base normalized")
	assert_eq(c.pk_stamp_s, 3700.0, "stamp = online_s")
	c.online_s = 3700.0 + 1799.0
	assert_eq(c.pk_value(), 2, "fresh 30-min window after add")
	c.online_s = 3700.0 + 1800.0
	assert_eq(c.pk_value(), 1)
	assert_eq(c.add_pk(-5), 0, "never negative")

func test_morality_and_killing_intent() -> void:
	var c := F.new_char()
	c.morality = 990
	assert_eq(c.add_morality(50), 10, "clamped at +1000")
	assert_eq(c.morality, 1000)
	c.morality = -980
	assert_eq(c.add_morality(-50), -20)
	assert_eq(c.morality, -1000)
	c.morality = 0
	assert_eq(c.align(), "NEUTRAL")
	c.morality = 101
	assert_eq(c.align(), "GOOD")
	c.morality = -101
	assert_eq(c.align(), "EVIL")
	c.killing_intent = 5
	assert_eq(c.add_killing_intent(100), 100)
	assert_eq(c.killing_intent, 105)
	assert_eq(c.add_killing_intent(-500), -105)
	assert_eq(c.killing_intent, 0)

func test_sheet_has_pk_align_prefs() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.pk = 2
	c.pk_stamp_s = 0.0
	c.online_s = 1800.0
	c.morality = -200
	c.prefs["accept_challenge"] = false
	var sh := c.to_sheet(t, {}, {})
	assert_eq(sh["pk"], 1, "sheet pk is current value")
	assert_eq(sh["align"], "EVIL")
	assert_eq(sh["prefs"], { "accept_challenge": false, "accept_party": true })

func test_req_pk_max_uses_current_value() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.pk = 2
	c.pk_stamp_s = 0.0
	c.online_s = 0.0
	var req := [ { "type": "pk_max", "value": 1 } ]
	assert_true(Requirements.check(req, c, t, {}, {}) != "", "pk 2 > 1 blocked")
	c.online_s = 1800.0           # 目前值 1
	assert_eq(Requirements.check(req, c, t, {}, {}), "", "decayed pk passes")
