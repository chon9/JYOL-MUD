extends "res://tests/test_case.gd"
## WP-CHAR：3.11.1 每個條件 type 的通過與失敗、判定順序、describe。

const F := preload("res://tests/unit/test_character_fixtures.gd")

var t: Dictionary
var o: Dictionary
var r: Dictionary

func before_each() -> void:
	t = F.tables()
	o = F.options()
	r = F.rules()

func _chk(cond: Dictionary, c: Character, opts: Dictionary = {}, rules: Dictionary = {}) -> String:
	return Requirements.check([cond], c, t, o if opts.is_empty() else opts, r if rules.is_empty() else rules)

func _pair(cond: Dictionary, pass_c: Character, fail_c: Character) -> void:
	var typ: String = cond["type"]
	assert_eq(_chk(cond, pass_c), "", typ + " pass")
	assert_eq(_chk(cond, fail_c), "req_" + typ, typ + " fail")

func test_morality() -> void:
	var good := F.new_char()
	good.morality = 100
	var bad := F.new_char()
	bad.morality = -100
	_pair({ "type": "morality_min", "value": -99 }, good, bad)
	_pair({ "type": "morality_max", "value": 0 }, bad, good)

func test_sect_no_sect_enemy() -> void:
	var sl := F.new_char()
	sl.sect = "shaolin"
	var none := F.new_char()
	_pair({ "type": "sect", "sect": "shaolin" }, sl, none)
	_pair({ "type": "no_sect" }, none, sl)
	var enemy := F.new_char()
	enemy.sect_enemies = ["shaolin"]
	_pair({ "type": "not_enemy_of", "sect": "shaolin" }, none, enemy)

func test_gender() -> void:
	var m := F.new_char()
	var f := F.new_char()
	f.gender = "F"
	_pair({ "type": "gender", "value": "M" }, m, f)

func test_attr_min_uses_effective() -> void:
	var c := F.new_char()   # 悟性 21
	var low := F.new_char()
	low.attrs["wit"] = 15
	_pair({ "type": "attr_min", "attr": "wit", "value": 21 }, c, low)
	var res := c.inventory.add("a_cubudaopao", 1, t, 0.0, -1, F.uid_maker())
	c.inventory.equip(res["uid"], t)
	assert_eq(_chk({ "type": "attr_min", "attr": "wit", "value": 23 }, c), "", "equipment counts")

func test_skill_min() -> void:
	var c := F.new_char()
	c.skills.set_level("foxa", 10, t)
	_pair({ "type": "skill_min", "skill": "foxa", "value": 10 }, c, F.new_char())

func test_combat_xp_pk_killing() -> void:
	var vet := F.new_char()
	vet.combat_xp = 600
	vet.pk = 3
	vet.killing_intent = 50
	var newb := F.new_char()
	_pair({ "type": "combat_xp_min", "value": 500 }, vet, newb)
	_pair({ "type": "pk_max", "value": 0 }, newb, vet)
	_pair({ "type": "killing_intent_max", "value": 10 }, newb, vet)

func test_quest_flag_and_done() -> void:
	var c := F.new_char()
	c.flags["hs_trial_passed"] = true
	c.quests["done"]["q_rabbit"] = 1
	var n := F.new_char()
	n.quests["done"]["q_rabbit"] = 0
	_pair({ "type": "quest_flag", "flag": "hs_trial_passed" }, c, n)
	_pair({ "type": "quest_done", "quest": "q_rabbit" }, c, n)

func test_era_enabled() -> void:
	var c := F.new_char()
	assert_eq(_chk({ "type": "era_enabled", "era": "1.0A" }, c), "")
	assert_eq(_chk({ "type": "era_enabled", "era": "gmdk" }, c), "req_era_enabled")
	assert_eq(Requirements.check([{ "type": "era_enabled", "era": "1.0A" }], c, t, {}, r), "", "fallback to tables.eras")

func test_sect_enabled() -> void:
	var c := F.new_char()
	assert_eq(_chk({ "type": "sect_enabled", "sect": "wudang" }, c), "", "empty list = all enabled")
	var opts := { "sects_enabled": ["shaolin"] }
	assert_eq(_chk({ "type": "sect_enabled", "sect": "shaolin" }, c, opts), "")
	assert_eq(_chk({ "type": "sect_enabled", "sect": "wudang" }, c, opts), "req_sect_enabled")

func test_rule() -> void:
	var c := F.new_char()
	assert_eq(_chk({ "type": "rule", "key": "death_rule", "value": "STANDARD" }, c), "")
	assert_eq(_chk({ "type": "rule", "key": "death_rule", "value": "CASUAL" }, c), "req_rule")
	assert_eq(_chk({ "type": "rule", "key": "xuedian_cap", "value": 65200.0 }, c), "", "int/float compare")
	assert_eq(_chk({ "type": "rule", "key": "nope", "value": 1 }, c), "req_rule")

func test_unmarried_and_unknown() -> void:
	var c := F.new_char()
	assert_eq(_chk({ "type": "unmarried" }, c), "")
	assert_eq(_chk({ "type": "mystery" }, c), "req_mystery")

func test_order_first_failure_wins() -> void:
	var c := F.new_char()
	c.gender = "F"
	var conds := [{ "type": "no_sect" }, { "type": "gender", "value": "M" }, { "type": "sect", "sect": "shaolin" }]
	assert_eq(Requirements.check(conds, c, t, o, r), "req_gender")
	assert_eq(Requirements.check([], c, t, o, r), "")

func test_describe() -> void:
	assert_eq(Requirements.describe({ "type": "skill_min", "skill": "foxa", "value": 10 }, t), "佛法 10 級以上")
	assert_eq(Requirements.describe({ "type": "sect", "sect": "shaolin" }, t), "少林弟子")
	assert_eq(Requirements.describe({ "type": "attr_min", "attr": "wit", "value": 25 }, t), "悟性 25 以上")
	assert_eq(Requirements.describe({ "type": "gender", "value": "M" }, t), "限男性")
	assert_eq(Requirements.describe({ "type": "quest_done", "quest": "q_rabbit" }, t), "完成任務「狩獵事件：大兔皮」")
	for typ in ["morality_min", "morality_max", "no_sect", "not_enemy_of", "combat_xp_min", "pk_max", "quest_flag",
			"killing_intent_max", "era_enabled", "sect_enabled", "rule", "unmarried"]:
		assert_true(Requirements.describe({ "type": typ, "value": 1 }, t) != "", typ + " describe")
