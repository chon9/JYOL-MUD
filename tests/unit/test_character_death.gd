extends "res://tests/test_case.gd"
## WP-CHAR：6.2 死亡規則矩陣（CHAR 部分）與 respawn_vitals。

const F := preload("res://tests/unit/test_character_fixtures.gd")

var t: Dictionary

func before_each() -> void:
	t = F.tables()

## 6.2 的固定角色
func _make(xp: int) -> Character:
	var c := F.new_char()
	c.sect = "shaolin"
	c.combat_xp = xp
	c.skills.set_level("sl_changquan", 20, t)
	c.skills.set_level("sl_luohanquan", 15, t)
	c.skills.set_level("basic_inner", 10, t)
	c.skills.set_level("foxa", 12, t)
	c.skills.set_level("life_farming", 5, t)
	c.inventory.remove_item_id("c_jingyao", 2)    # 精藥水 ×3
	c.inventory.add("r_bigrabbitskin", 1, t, 0.0, -1, F.uid_maker())
	c.money = 1000
	return c

func _levels(c: Character) -> Array:
	return [c.skills.level("sl_changquan"), c.skills.level("sl_luohanquan"), c.skills.level("basic_inner"),
		c.skills.level("foxa"), c.skills.level("life_farming")]

func _ids(arr: Array) -> Array:
	var out: Array = []
	for it in arr:
		out.append(it["id"])
	out.sort()
	return out

func _check_strict(xp: int) -> void:
	var c := _make(xp)
	var r := DeathPenalty.apply(c, F.rules("classic_strict"), t)
	assert_eq(r["rule"], "STRICT_2001")
	assert_eq(r["safe_newbie"], false)
	assert_eq(_levels(c), [19, 14, 9, 11, 5])
	assert_eq(c.skills.prof("sl_changquan"), SkillBook.prof_for_level("sl_changquan", 19, t), "prof = threshold")
	assert_eq(r["skill_losses"].size(), 4)
	assert_eq(_ids(r["dropped"]), ["a_bupao", "c_jingyao", "r_bigrabbitskin", "w_mudao"])
	assert_eq(c.inventory.items, [])
	assert_eq(c.inventory.equipped, Inventory.empty_equipped())   # M3c：8 個裝備欄
	assert_eq(c.money, 1000)
	assert_eq(r["money_lost"], 0)
	assert_eq(c.dead_count, 1)

func test_strict_veteran() -> void:
	_check_strict(2000)

func test_strict_newbie_no_protection() -> void:
	_check_strict(300)

func test_strict_level_one_skill_drops_to_zero() -> void:
	var c := F.new_char()
	c.skills.set_level("basic_fist", 1, t)
	var r := DeathPenalty.apply(c, F.rules("classic_strict"), t)
	assert_eq(c.skills.level("basic_fist"), 0)
	assert_eq(r["skill_losses"], [{ "skill": "basic_fist", "name": "搏擊格鬥", "from": 1, "to": 0 }])

func _check_standard_veteran(preset: String) -> void:
	var c := _make(2000)
	var r := DeathPenalty.apply(c, F.rules(preset), t)
	assert_eq(r["rule"], "STANDARD")
	assert_eq(r["safe_newbie"], false)
	assert_eq(_levels(c), [19, 15, 10, 12, 5], "only highest special art")
	assert_eq(r["skill_losses"], [{ "skill": "sl_changquan", "name": "少林長拳", "from": 20, "to": 19 }])
	assert_eq(_ids(r["dropped"]), ["a_bupao", "w_mudao"])
	assert_eq(c.inventory.count("c_jingyao"), 3, "bag stays")
	assert_eq(c.inventory.count("r_bigrabbitskin"), 1)
	assert_eq(c.money, 1000)

func test_standard_veteran() -> void:
	_check_standard_veteran("classic_standard")

func test_later_official_veteran() -> void:
	_check_standard_veteran("later_official")

func test_standard_newbie_safe() -> void:
	var c := _make(300)
	var before := c.to_dict()
	var r := DeathPenalty.apply(c, F.rules("classic_standard"), t)
	assert_eq(r["safe_newbie"], true)
	assert_eq(r["skill_losses"], [])
	assert_eq(r["dropped"], [])
	before["dead_count"] = 1
	assert_eq(c.to_dict(), before, "nothing changes except dead_count")

func test_standard_boundary_500_is_safe() -> void:
	var c := _make(DeathPenalty.NEWBIE_XP)
	assert_eq(DeathPenalty.apply(c, F.rules(), t)["safe_newbie"], true)
	var c2 := _make(DeathPenalty.NEWBIE_XP + 1)
	assert_eq(DeathPenalty.apply(c2, F.rules(), t)["safe_newbie"], false)

func test_standard_no_special_art() -> void:
	var c := F.new_char()
	c.combat_xp = 2000
	c.skills.set_level("basic_fist", 10, t)
	var r := DeathPenalty.apply(c, F.rules(), t)
	assert_eq(r["skill_losses"], [])
	assert_eq(c.skills.level("basic_fist"), 10)
	assert_eq(r["dropped"].size(), 2, "equipment still dropped")

func test_casual() -> void:
	var c := _make(2000)
	var r := DeathPenalty.apply(c, F.rules("friends_casual"), t)
	assert_eq(r["rule"], "CASUAL")
	assert_eq(_levels(c), [20, 15, 10, 12, 5])
	assert_eq(r["dropped"], [])
	assert_eq(r["money_lost"], 100)
	assert_eq(c.money, 900)
	assert_eq(c.inventory.count("c_jingyao"), 3)
	assert_true(c.inventory.equipped["WEAPON"] != "")

func test_respawn_vitals() -> void:
	var c := _make(2000)
	c.vitals = { "jing": 1, "qi": 1, "shen": 1, "neili": 40, "food": 30, "water": 30 }
	DeathPenalty.respawn_vitals(c, t, F.options())
	var d := c.derived(t, F.options())
	assert_eq(c.vitals["jing"], floori(d["jing_max"] * 0.5))
	assert_eq(c.vitals["qi"], 90)
	assert_eq(c.vitals["shen"], 44)
	assert_eq(c.vitals["neili"], 0)
	assert_eq(c.vitals["food"], 30)
