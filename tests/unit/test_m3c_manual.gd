extends "res://tests/unit/test_world_fixture.gd"
## M3C_PLAN §6.4（WP-LOOT）：秘笈 manual_read 的全部原因碼、上限 = min(秘笈 cap, 讀書識字, 一般上限)、不消耗、扣精神。
## 【設計提案・非原作】秘笈系統（2002-08-21）依擁有者要求提前；classic_strict 關閉（規則 manuals）。

const BOOK := "bk_huqingniu"   # 胡青牛醫書：basic_medic，cap 60，讀書識字 20

func _ready_char() -> void:
	make_char()
	ch().combat_xp = 200000   # 一般上限（實戰）夠高，只看秘笈與讀書識字
	ch().vitals["jing"] = 100000
	ch().vitals["shen"] = 100000
	ch().learn_points = 100000   # M3c 審查：研讀也扣學點

func _read(uid: String, times := 1) -> Dictionary:
	return send("manual_read", { "item_uid": uid, "times": times })

func test_reason_codes_in_order() -> void:
	if not game_ok():
		return
	_ready_char()
	assert_true(host().get("loot") != null, "LootSystem 已載入（M3C_SYSTEMS）")
	assert_true(ws.has_intent_handler("manual_read"), "intents_loot 已註冊")
	var uid := give(BOOK)
	assert_eq(str(_read("it_nothing").get("reason", "")), "no_such_item")
	assert_eq(str(_read(first_uid("w_mudao")).get("reason", "")), "not_manual")
	assert_eq(str(_read(uid).get("reason", "")), "manual_illiterate", "讀書識字 0 < 20")
	ch().skills.set_level("basic_literacy", 25, tables())
	ch().skills.set_level("basic_medic", 25, tables())
	assert_eq(str(_read(uid).get("reason", "")), "manual_cap", "上限 = min(60, 讀書識字 25, 一般上限) = 25")
	ch().skills.set_level("basic_literacy", 30, tables())
	ch().vitals["jing"] = 5
	assert_eq(str(_read(uid).get("reason", "")), "not_enough_jing")
	ch().vitals["jing"] = 1000
	ch().vitals["shen"] = 5
	assert_eq(str(_read(uid).get("reason", "")), "not_enough_shen")
	# 金蛇密笈：manual.requires 悟性 25
	var js := give("bk_jinshe")
	ch().skills.set_level("basic_literacy", 50, tables())
	ch().attrs["wit"] = 10
	ch().vitals["shen"] = 1000
	assert_eq(str(_read(js).get("reason", "")), "req_attr_min", "資質不佳者無以習得")
	# 規則 manuals 關 → 第一個就擋
	use_preset("classic_strict")
	assert_eq(str(_read(uid).get("reason", "")), "manuals_off")

func test_read_gains_prof_costs_and_is_not_consumed() -> void:
	if not game_ok():
		return
	_ready_char()
	var uid := give(BOOK)
	ch().skills.set_level("basic_literacy", 30, tables())
	var j0 := int(ch().vitals["jing"])
	var s0 := int(ch().vitals["shen"])
	clear_events()
	var r := _read(uid, 5)
	assert_true(r.get("ok", false), str(r))
	assert_eq(int(r.get("times_done", 0)), 5)
	# M3c 第二輪審查：每次熟練 +10、精 10、神 10（原 +6／15／15 比自修慢 0.4 倍）
	assert_eq(ch().skills.prof("basic_medic"), 50, "每讀一次熟練 +10")
	assert_eq(int(ch().vitals["jing"]), j0 - 50, "每次精 10")
	assert_eq(int(ch().vitals["shen"]), s0 - 50, "每次神 10")
	assert_eq(item_count(BOOK), 1, "秘笈不消耗")
	var p := lastp("lt_manual_read")
	assert_eq(int(p.get("times", 0)), 5)
	assert_eq(int(p.get("cap", 0)), 30, "cap_eff = min(60, 30, 一般上限)")
	assert_eq(str(p.get("skill_name", "")), str(tables()["basic_skills"]["basic_medic"]["name"]))
	assert_eq(str(p.get("item_name", "")), "胡青牛醫書")

func test_cap_is_min_of_book_literacy_and_general() -> void:
	if not game_ok():
		return
	_ready_char()
	var row: Dictionary = tables()["items"][BOOK]
	var c = ch()
	c.skills.set_level("basic_literacy", 40, tables())
	assert_eq(Learning.manual_cap(c, row, 250), 40, "讀書識字 40 < 秘笈 60")
	c.skills.set_level("basic_literacy", 90, tables())
	assert_eq(Learning.manual_cap(c, row, 250), 60, "秘笈上限 60")
	assert_eq(Learning.manual_cap(c, row, 12), 12, "一般上限（實戰）12")
	assert_eq(Learning.manual_cap(c, row, host().skill_cap(c, "basic_medic")), mini(60, host().skill_cap(c, "basic_medic")))
	# 讀到上限就停：從 24 級讀到 25 級後回報 stopped_reason manual_cap
	c.skills.set_level("basic_literacy", 25, tables())
	c.skills.set_level("basic_medic", 24, tables())
	var res := {}
	for k in 400:
		res = Learning.read_manual(c, row, 10, tables(), 250)
		if str(res.get("stopped_reason", res.get("reason", ""))) == "manual_cap":
			break
	assert_eq(c.skills.level("basic_medic"), 25, "停在讀書識字 25 級")
	assert_eq(str(Learning.read_manual(c, row, 1, tables(), 250).get("reason", "")), "manual_cap")

## M3c 審查：研讀每次扣學點（LP_PER_TIME，與自修同價）；學點不夠 → not_enough_lp（精、神之後）
func test_read_costs_learn_points() -> void:
	if not game_ok():
		return
	_ready_char()
	var uid := give(BOOK)
	ch().skills.set_level("basic_literacy", 30, tables())
	ch().learn_points = 3
	var r := _read(uid, 5)
	assert_true(r.get("ok", false), str(r))
	assert_eq(int(r.get("times_done", 0)), 3, "only as many reads as learn points")
	assert_eq(int(ch().learn_points), 0, "3 learn points spent")
	assert_eq(str(r.get("stopped_reason", "")), "not_enough_lp")
	assert_eq(str(_read(uid).get("reason", "")), "not_enough_lp")
	assert_eq(ch().skills.prof("basic_medic"), 30, "3 reads x 10")
