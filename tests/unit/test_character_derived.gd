extends "res://tests/test_case.gd"
## WP-CHAR：4.2 衍生數值、4.4 實戰上限、有效屬性。

const F := preload("res://tests/unit/test_character_fixtures.gd")

func test_base_formulas() -> void:
	var t := F.tables()
	var c := F.new_char()   # 臂 20 膽 19 悟 21 福 19 定 19 機 20 根 20
	var d := c.derived(t, F.options())
	assert_eq(d["carry_max"], 20 * 3 + 20 * 5, "負重上限 = 根骨×3 + 臂力×5")
	assert_eq(d["qi_max"], 60 + 20 * 6, "氣上限")
	assert_eq(d["qi_max"], 180, "P0 氣上限 180")
	assert_eq(d["jing_max"], 50 + 21 * 2, "精上限")
	assert_eq(d["shen_max"], 50 + 19 * 2, "神上限")
	assert_eq(d["neili_max"], 0)
	assert_eq(d["carry"], 5 + 2 + 2, "精藥水 5 + 木刀 2 + 布衣 2")
	assert_eq(d["weapon_power"], 4)
	assert_eq(d["weapon_type"], "BLADE")
	assert_eq(d["armor_power"], 2)
	assert_eq(d["effective_inner"], 0)
	assert_eq(d["art_level_cap"], 5)
	for k in ["jing_max", "qi_max", "shen_max", "neili_max", "carry_max", "carry", "weapon_power", "weapon_type",
			"armor_power", "effective_inner", "art_level_cap", "attrs"]:
		assert_has(d, k)

func test_inner_and_literacy_bonuses() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.skills.set_level("basic_inner", 25, t)
	c.skills.set_level("basic_literacy", 20, t)
	c.qi_bonus = 16
	var d := c.derived(t, F.options())
	assert_eq(d["neili_max"], 125, "內力上限 = 基本內功×5")
	assert_eq(d["jing_max"], 50 + (21 + 2) * 2 + 2 * 8, "精上限：悟性含讀書 +2、內功 ⌊25/10⌋×8")
	assert_eq(d["shen_max"], 50 + 19 * 2 + 2 * 8, "神上限：讀書 ⌊20/10⌋×8")
	assert_eq(d["qi_max"], 180 + 16, "修煉加成")
	assert_eq(d["attrs"]["wit"], 23, "讀書 20 級悟性 +2")

func test_literacy_10_gives_wit_plus_1() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.skills.set_level("basic_literacy", 9, t)
	assert_eq(c.effective_attrs(t, F.options())["wit"], 21)
	c.skills.set_level("basic_literacy", 10, t)
	assert_eq(c.effective_attrs(t, F.options())["wit"], 22)
	assert_eq(c.attrs["wit"], 21, "base untouched")

func test_basic_skill_attr_bonus_caps() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.skills.set_level("basic_literacy", 250, t)
	assert_eq(c.effective_attrs(t, F.options())["wit"], 21 + 10, "讀書給悟性最多 +10")
	c.skills.set_level("basic_fist", 250, t)
	assert_eq(c.effective_attrs(t, { "attr_from_basic_skills": true })["str"], 20 + 15, "搏擊給臂力最多 +15")

func test_equipment_attr_bonus() -> void:
	var t := F.tables()
	var c := F.new_char()
	var res := c.inventory.add("a_cubudaopao", 1, t, 0.0, -1, F.uid_maker())
	c.inventory.equip(res["uid"], t)
	var d := c.derived(t, F.options())
	assert_eq(d["attrs"]["wit"], 23, "粗布道袍 悟性 +2")
	assert_eq(d["armor_power"], 4)
	assert_eq(d["jing_max"], 50 + 23 * 2, "精上限用有效悟性")

func test_attr_from_basic_skills_switch() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.skills.set_level("basic_fist", 25, t)
	c.skills.set_level("basic_inner", 10, t)
	var off := c.effective_attrs(t, { "attr_from_basic_skills": false })
	assert_eq(off["str"], 20)
	assert_eq(off["con"], 20)
	var on := c.effective_attrs(t, { "attr_from_basic_skills": true })
	assert_eq(on["str"], 22, "搏擊 25 → 臂力 +2")
	assert_eq(on["con"], 21, "內功 10 → 根骨 +1")
	assert_eq(c.derived(t, { "attr_from_basic_skills": true })["qi_max"], 60 + 21 * 6)

func test_effective_inner_and_lightness() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.skills.set_level("basic_inner", 10, t)
	c.skills.set_level("sl_xinfa", 7, t)
	c.skills.set_level("sl_shenfa", 12, t)
	var d := c.derived(t, F.options())
	assert_eq(d["effective_inner"], 13, "10 + ⌊7/2⌋")
	assert_eq(DerivedStats.effective_inner(c.skills, t), 13)
	assert_eq(d["lightness"], 12)

func test_art_level_cap() -> void:
	assert_eq(DerivedStats.art_level_cap(0), 5, "沒有實戰最多 5 級")
	assert_eq(DerivedStats.art_level_cap(9), 5)
	assert_eq(DerivedStats.art_level_cap(10), 6)
	assert_eq(DerivedStats.art_level_cap(250), 10)
	assert_eq(DerivedStats.art_level_cap(1000), 15)
	assert_eq(DerivedStats.art_level_cap(10000), 36)

func test_clamp_vitals() -> void:
	var t := F.tables()
	var c := F.new_char()
	c.vitals = { "jing": 9999, "qi": -5, "shen": 10, "neili": 50, "food": 150, "water": -3 }
	c.clamp_vitals(t, F.options())
	assert_eq(c.vitals, { "jing": 92, "qi": 0, "shen": 10, "neili": 0, "food": 100, "water": 0 })
