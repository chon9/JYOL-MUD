extends "res://tests/test_case.gd"
## WP-CHAR：4.10 飽食飲水與回復、4.11 打坐／運功／休息／藥物、生日。

const F := preload("res://tests/unit/test_character_fixtures.gd")

var t: Dictionary
var o: Dictionary

func before_each() -> void:
	t = F.tables()
	o = F.options()

func test_food_water_drain_and_notices() -> void:
	var c := F.new_char()
	assert_eq(Survival.tick(c, 299.0, false, t, o), [])
	assert_eq(c.vitals["food"], 100)
	assert_eq(Survival.tick(c, 1.0, false, t, o), [])
	assert_eq(c.vitals["food"], 99, "−1 per 300 s")
	assert_eq(c.vitals["water"], 99)
	var notes := Survival.tick(c, 300.0 * 79, false, t, o)
	assert_eq(c.vitals["food"], 20)
	assert_eq(notes, ["hungry", "thirsty"])
	assert_eq(Survival.tick(c, 300.0, false, t, o), [], "notice only on crossing")
	notes = Survival.tick(c, 300.0 * 30, true, t, o)
	assert_eq(c.vitals["food"], 0, "drops in battle too, floors at 0")
	assert_eq(notes, ["starving", "parched"])
	assert_eq(Survival.tick(c, 3000.0, false, t, o), [])

func test_drain_remainder_is_kept() -> void:
	var c := F.new_char()
	for i in 30:
		Survival.tick(c, 10.0, false, t, o)
	assert_eq(c.vitals["food"], 99, "30 × 10 s = 300 s")
	var c2 := Character.from_dict(c.to_dict())
	Survival.tick(c2, 150.0, false, t, o)
	Survival.tick(c2, 150.0, false, t, o)
	assert_eq(c2.vitals["food"], 98, "remainder survives save")

func test_natural_regen() -> void:
	var c := F.new_char()
	c.skills.set_level("basic_inner", 10, t)   # 內力上限 50
	c.vitals["qi"] = 100
	c.vitals["jing"] = 10
	c.vitals["neili"] = 0
	Survival.tick(c, 9.0, false, t, o)
	assert_eq(c.vitals["qi"], 100)
	Survival.tick(c, 1.0, false, t, o)
	assert_eq(c.vitals["qi"], 104, "+ceil(180×2%)")
	assert_eq(c.vitals["jing"], 10 + 2, "+ceil(100×2%)：精上限 50+42+8 = 100")
	assert_eq(c.vitals["neili"], 1, "+ceil(50×1%)")
	Survival.tick(c, 10.0, true, t, o)
	assert_eq(c.vitals["qi"], 104, "no regen in battle")

func test_regen_starving_quarter() -> void:
	var c := F.new_char()
	c.vitals["qi"] = 100
	c.vitals["food"] = 0
	Survival.tick(c, 10.0, false, t, o)
	assert_eq(c.vitals["qi"], 101, "ceil(180×2%×0.25) = 1")
	c.vitals["qi"] = 100
	c.qi_bonus = 220     # 氣上限 400 → 8 → ×0.25 = 2
	Survival.tick(c, 10.0, false, t, o)
	assert_eq(c.vitals["qi"], 102)

func test_regen_caps_at_max() -> void:
	var c := F.new_char()
	c.vitals["qi"] = 179
	Survival.tick(c, 10.0, false, t, o)
	assert_eq(c.vitals["qi"], 180)

func test_meditate() -> void:
	var c := F.new_char()
	assert_eq(Survival.meditate(c, t, o, 100.0)["reason"], "no_inner")
	c.skills.set_level("basic_inner", 2, t)   # 內力上限 10
	var r := Survival.meditate(c, t, o, 100.0)
	assert_eq(r["ok"], true)
	assert_eq(r["kind"], "neili")
	assert_eq(r["gain"], 4, "max(1, 2 + ⌊10×0.2⌋)")
	assert_eq(r["neili"], 4)
	assert_eq(c.vitals["jing"], 92 - 2)
	assert_eq(Survival.meditate(c, t, o, 105.0)["reason"], "busy")
	r = Survival.meditate(c, t, o, 110.0)
	assert_eq(r["neili"], 8)
	r = Survival.meditate(c, t, o, 120.0)
	assert_eq(r["gain"], 2, "capped at max")
	assert_eq(c.vitals["neili"], 10)
	r = Survival.meditate(c, t, o, 130.0)
	assert_eq(r["kind"], "cultivate")
	assert_eq(r["qi_gain"], 8)
	assert_eq(r["count"], 1)
	assert_eq(c.vitals["neili"], 0)
	assert_eq(c.qi_bonus, 8)
	assert_eq(c.derived(t, o)["qi_max"], 188)
	c.vitals["neili"] = 10
	c.cultivations = 10
	assert_eq(Survival.meditate(c, t, o, 200.0)["reason"], "nothing_to_do", "cultivations < inner×5")
	c.vitals["neili"] = 0
	c.vitals["jing"] = 1
	assert_eq(Survival.meditate(c, t, o, 300.0)["reason"], "not_enough_jing")

func test_exert() -> void:
	var c := F.new_char()
	c.skills.set_level("basic_inner", 10, t)
	c.vitals["neili"] = 19
	assert_eq(Survival.exert(c, "qi", t, o)["reason"], "not_enough_neili")
	assert_eq(Survival.exert(c, "neili", t, o)["reason"], "bad_value:stat")
	c.vitals["neili"] = 50
	c.vitals["qi"] = 100
	var r := Survival.exert(c, "qi", t, o)
	assert_eq(r, { "ok": true, "reason": "", "stat": "qi", "gain": 27 })
	assert_eq(c.vitals["neili"], 30)
	c.vitals["qi"] = 175
	assert_eq(Survival.exert(c, "qi", t, o)["gain"], 5, "capped at max")

func test_rest_full() -> void:
	var c := F.new_char()
	c.skills.set_level("basic_inner", 4, t)
	c.vitals = { "jing": 1, "qi": 1, "shen": 1, "neili": 0, "food": 50, "water": 50 }
	Survival.rest_full(c, t, o)
	assert_eq(c.vitals, { "jing": 92, "qi": 180, "shen": 88, "neili": 20, "food": 50, "water": 50 })

func test_use_item_restore() -> void:
	var c := F.new_char()
	c.vitals["jing"] = 10
	var uid: String = ""
	for it in c.inventory.items:
		if it["id"] == "c_jingyao":
			uid = it["uid"]
	var r := Survival.use_item(c, uid, t, o, 0.0)
	assert_eq(r["ok"], true)
	assert_eq(r["item_id"], "c_jingyao")
	assert_eq(r["effects_applied"], [{ "stat": "jing", "gain": 50 }])
	assert_eq(r["overdose"], false)
	assert_eq(c.vitals["jing"], 60)
	assert_eq(c.inventory.count("c_jingyao"), 4)
	assert_eq(Survival.use_item(c, "it_nope", t, o, 0.0)["reason"], "no_item")
	assert_eq(Survival.use_item(c, c.inventory.equipped["WEAPON"], t, o, 0.0)["reason"], "not_usable")

func test_shaolin_meat_lowers_foxa() -> void:
	t["items"]["c_meat"] = { "id": "c_meat", "name": "烤魚", "tab": "OTHER", "slot": "", "weight": 1, "price": 1,
		"stack": 20, "spoil_days": 0, "usable": true, "meat": true,
		"effects": [ { "type": "restore", "stat": "food", "value": 10 } ] }
	var c := F.new_char()
	c.skills.set_level("foxa", 12, t)
	c.inventory.add("c_meat", 3, t, 0.0, -1, func(): return "it_meat_test")
	var uid: String = c.inventory.items.filter(func(it): return it["id"] == "c_meat")[0]["uid"]
	var r := Survival.use_item(c, uid, t, o, 0.0)
	assert_eq(r["ok"], true)
	assert_eq(r["sect_skill_loss"], {}, "非少林弟子不受葷戒限制")
	assert_eq(c.skills.level("foxa"), 12)
	c.sect = "shaolin"
	r = Survival.use_item(c, uid, t, o, 0.0)
	assert_eq(r["sect_skill_loss"], { "skill": "foxa", "name": SkillBook.skill_name("foxa", t), "from": 12, "to": 11 })
	assert_eq(c.skills.level("foxa"), 11)
	assert_eq(c.skills.prof("foxa"), SkillBook.prof_for_level("foxa", 11, t), "熟練度設為新等級門檻")
	# 素食不受影響
	c.vitals["food"] = 0
	var mt: String = c.inventory.items.filter(func(it): return it["id"] == "c_mantou")[0]["uid"] if c.inventory.count("c_mantou") > 0 else ""
	if mt != "":
		assert_eq(Survival.use_item(c, mt, t, o, 0.0)["sect_skill_loss"], {})
		assert_eq(c.skills.level("foxa"), 11)

func test_overdose() -> void:
	var c := F.new_char()
	var mk := F.uid_maker()
	c.inventory.add("c_qiyao", 10, t, 0.0, -1, mk)
	var uid: String = c.inventory.items[c.inventory.items.size() - 1]["uid"]
	for i in 5:
		var r := Survival.use_item(c, uid, t, o, float(i))
		assert_eq(r["overdose"], false, "use %d" % i)
	var r6 := Survival.use_item(c, uid, t, o, 10.0)
	assert_eq(r6["overdose"], true, "6th within 60 s")
	assert_eq([c.vitals["jing"], c.vitals["qi"], c.vitals["shen"]], [1, 1, 1])
	# 60 秒後的窗口只剩部分紀錄
	var r7 := Survival.use_item(c, uid, t, o, 200.0)
	assert_eq(r7["overdose"], false)

func test_food_does_not_count_as_medicine() -> void:
	var c := F.new_char()
	c.vitals["food"] = 0
	c.inventory.add("c_mantou", 10, t, 0.0, -1, F.uid_maker())
	var uid: String = c.inventory.items[c.inventory.items.size() - 1]["uid"]
	for i in 7:
		assert_eq(Survival.use_item(c, uid, t, o, float(i))["overdose"], false)
	assert_eq(c.vitals["food"], 100)

func test_smoke_buff() -> void:
	var c := F.new_char()
	var res := c.inventory.add("c_smoke", 1, t, 0.0, -1, F.uid_maker())
	var r := Survival.use_item(c, res["uid"], t, o, 50.0)
	assert_eq(r["ok"], true)
	assert_eq(c.buffs["smoke_until_s"], 350.0)

func test_eat_meal() -> void:
	var c := F.new_char()
	c.vitals["food"] = 70
	c.vitals["water"] = 10
	Survival.eat_meal(c, 40, 40)
	assert_eq(c.vitals["food"], 100)
	assert_eq(c.vitals["water"], 50)

func test_birthday() -> void:
	var c := F.new_char()   # birth_month 3
	var rng := F.rng(9)
	var total_before := 0
	for a in Character.ATTR_IDS:
		total_before += c.attrs[a]
	assert_eq(Survival.birthday_check(c, 1, 2, rng), "")
	var attr := Survival.birthday_check(c, 1, 3, rng)
	assert_true(Character.ATTR_IDS.has(attr), "returns attr id")
	var total_after := 0
	for a in Character.ATTR_IDS:
		total_after += c.attrs[a]
	assert_eq(total_after, total_before + 1)
	assert_eq(Survival.birthday_check(c, 1, 3, rng), "", "once per year")
	assert_true(Survival.birthday_check(c, 2, 3, rng) != "", "next year again")
