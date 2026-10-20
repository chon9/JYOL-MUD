extends "res://tests/unit/test_battle_helpers.gd"
## M1_PLAN 4.14：固定種子重現；權重；煙 ×0.1；數量上限 4；monster_spec 形狀（3.3）。

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

const ROOM := { "id": "xw_grass", "encounter": { "rate": 0.25, "table": [
	{ "monster": "m_rabbit", "w": 70, "count": [1, 2] },
	{ "monster": "m_bigrabbit", "w": 25, "count": [1, 1] },
	{ "monster": "m_wolf", "w": 5, "count": [1, 1] } ] } }

func test_no_encounter() -> void:
	assert_eq(Encounter.roll({ "id": "x" }, _rng(1)), [])
	assert_eq(Encounter.roll({ "encounter": {} }, _rng(1)), [])
	assert_eq(Encounter.roll({ "encounter": { "rate": 0.0, "table": [{ "monster": "m_rabbit", "w": 1 }] } }, _rng(1)), [])
	assert_eq(Encounter.roll({ "encounter": { "rate": 1.0, "table": [] } }, _rng(1)), [])

func test_fixed_seed_reproducible() -> void:
	var a := _rng(2024)
	var b := _rng(2024)
	var sa := []
	var sb := []
	for i in 200:
		sa.append(Encounter.roll(ROOM, a))
		sb.append(Encounter.roll(ROOM, b))
	assert_eq(sa, sb)
	assert_true(sa.any(func(x): return not x.is_empty()))

func test_rate_and_weights() -> void:
	var r := _rng(7)
	var n := 20000
	var hits := 0
	var counts := { "m_rabbit": 0, "m_bigrabbit": 0, "m_wolf": 0 }
	for i in n:
		var m := Encounter.roll(ROOM, r)
		if m.is_empty():
			continue
		hits += 1
		counts[m[0]] += 1
		for x in m:
			assert_eq(x, m[0], "一次遇敵只有一種怪")
	assert_true(absf(hits / float(n) - 0.25) < 0.02, "遇敵率 0.25（實際 %f）" % (hits / float(n)))
	assert_true(absf(counts.m_rabbit / float(hits) - 0.70) < 0.03, "權重 70")
	assert_true(absf(counts.m_bigrabbit / float(hits) - 0.25) < 0.03, "權重 25")
	assert_true(absf(counts.m_wolf / float(hits) - 0.05) < 0.02, "權重 5")

func test_smoke_multiplier() -> void:
	var room := { "encounter": { "rate": 0.5, "table": [{ "monster": "m_rabbit", "w": 1, "count": [1, 1] }] } }
	var r := _rng(9)
	var hits := 0
	var n := 20000
	for i in n:
		if not Encounter.roll(room, r, 0.1).is_empty():
			hits += 1
	assert_true(absf(hits / float(n) - 0.05) < 0.01, "0.5 × 0.1（實際 %f）" % (hits / float(n)))

func test_count_range_and_cap() -> void:
	var room := { "encounter": { "rate": 1.0, "table": [{ "monster": "m_wolf", "w": 1, "count": [3, 9] }] } }
	var r := _rng(11)
	var seen := {}
	for i in 500:
		var m := Encounter.roll(room, r)
		assert_true(m.size() >= 3 and m.size() <= 4, "數量夾在 4 以內")
		seen[m.size()] = true
	assert_eq(seen.size(), 2)
	var room2 := { "encounter": { "rate": 1.0, "table": [{ "monster": "m_wolf", "w": 1, "count": [1, 2] }] } }
	var seen2 := {}
	for i in 200:
		seen2[Encounter.roll(room2, r).size()] = true
	assert_true(seen2.has(1) and seen2.has(2), "randi_range(count[0], count[1])")

func test_monster_spec_shape() -> void:
	var s := Encounter.monster_spec("m_rabbit", tables())
	for k in ["kind", "ref", "name", "side", "peer", "ai", "attrs", "qi", "qi_max", "neili", "neili_max", "jing", "jing_max",
			"shen", "shen_max", "skills", "arts", "weapon", "weapon_options", "armor_power", "effective_inner", "lightness",
			"sect_skill", "killing_intent", "carry_ratio", "monster_row"]:
		assert_has(s, k)
	assert_eq(s.kind, "MONSTER")
	assert_eq(s.ref, "m_rabbit")
	assert_eq(s.name, "野兔")
	assert_eq(s.side, 1)
	assert_eq(s.peer, 0)
	assert_eq(s.ai, "coward")
	assert_eq(s.qi, 60)
	assert_eq(s.qi_max, 60)
	assert_eq(s.attrs.agi, 15)
	assert_eq(s.attrs.size(), 7)
	assert_eq(s.arts, ["mon_bite"])
	assert_eq(s.skills.mon_bite, 1)
	assert_eq(s.skills.basic_dodge, 5)
	assert_not_has(s.skills, "basic_parry", "只列 ≥1 的")
	assert_eq(s.weapon, { "uid": "", "item_id": "", "weapon_type": "FIST", "atk": 0, "name": "" })
	assert_eq(s.armor_power, 31)
	assert_eq(s.sect_skill, {})
	assert_eq(s.monster_row, "m_rabbit")
	var bandit := Encounter.monster_spec("m_bandit", tables())
	assert_eq(bandit.weapon.weapon_type, "BLADE")
	assert_eq(bandit.weapon.atk, 10)
	assert_eq(bandit.effective_inner, 10)
	var gw := Encounter.monster_spec("m_guiwang", tables())
	assert_eq(gw.arts, ["mon_guiwang"], "內功不放進可出招的 arts")
	assert_eq(gw.effective_inner, 50 + 15, "基本內功 + 最高內功/2")
	assert_eq(Encounter.monster_spec("m_nope", tables()), {})

func test_monster_specs_number_duplicates() -> void:
	var specs := Encounter.monster_specs(["m_rabbit", "m_wolf", "m_rabbit"], tables())
	assert_eq(specs.size(), 3)
	assert_eq(specs[0].name, "野兔甲")
	assert_eq(specs[1].name, "野狼", "單隻不加序號")
	assert_eq(specs[2].name, "野兔乙")
	assert_eq(specs[0].short, "兔甲")
	assert_eq(specs[2].short, "兔乙")
	assert_eq(Encounter.monster_specs(["m_rabbit"], tables())[0].name, "野兔")

func test_monster_spec_usable_in_battle() -> void:
	var b := make_battle([player_spec(), monster("m_guiwang")])
	assert_eq(b.unit(2).ai_kind(), "melee_basic")
	assert_true(b.unit(2).is_ai())
	assert_false(b.unit(1).is_ai())
