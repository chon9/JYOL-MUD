extends "res://tests/test_case.gd"
## ROGUE_PLAN §3.6、§3.7.3、§9.1（WP-RUN）：戰力分數的單調性、縮放與二分搜尋。

var tables: Dictionary = {}

func before_each() -> void:
	if tables.is_empty():
		var loader := DataLoader.new()
		loader.load_all("res://data")
		tables = loader.activate(["1.0A", "1.0B", "rogue"])

func _base() -> Dictionary:
	return RoguePower.reference_spec(tables)

func test_monotonic_attrs_level_weapon() -> void:
	var p0 := RoguePower.unit_power(_base(), tables)
	assert_true(p0 > 0.0, "參考新角色 > 0")
	var s1 := _base()
	s1.attrs.str = 30
	assert_true(RoguePower.unit_power(s1, tables) > p0, "膂力高 → P 大")
	var s2 := _base()
	s2.attrs.con = 30
	s2.qi_max = DerivedStats.QI_BASE + 30 * DerivedStats.QI_PER_CON
	s2.qi = s2.qi_max
	assert_true(RoguePower.unit_power(s2, tables) > p0, "根骨高 → P 大")
	var s3 := _base()
	s3.weapon.atk = 30
	assert_true(RoguePower.unit_power(s3, tables) > p0, "兵器攻擊高 → P 大")
	var s4 := _base()
	s4.weapon = { "uid": "x", "item_id": "w_qingfeng", "weapon_type": "SWORD", "atk": 15, "name": "" }
	s4.skills = { "hs_jianfa": 20, "basic_sword": 20 }
	s4.arts = ["hs_jianfa"]
	var p4 := RoguePower.unit_power(s4, tables)
	var s5 := s4.duplicate(true)
	s5.skills = { "hs_jianfa": 60, "basic_sword": 60 }
	assert_true(RoguePower.unit_power(s5, tables) > p4, "武功等級高 → P 大")
	assert_true(p4 > p0, "有武功 → P 大")

func test_side_power_sum() -> void:
	var a := _base()
	var b := Encounter.monster_spec("m_wolf", tables)
	var sum := RoguePower.unit_power(a, tables) + RoguePower.unit_power(b, tables)
	assert_true(absf(RoguePower.side_power([a, b], tables) - sum) < 0.001)
	assert_eq(RoguePower.side_power([], tables), 0.0)

func test_scale_spec_shape() -> void:
	var w := Encounter.monster_spec("m_bandit", tables)
	var up := RoguePower.scale_spec(w, 2.0)
	assert_eq(int(up.qi_max), int(w.qi_max) * 2, "氣 × s")
	assert_eq(int(up.attrs.str), clampi(int(w.attrs.str) + 6, 5, 60), "膂力 + 6(s−1)")
	assert_eq(int(up.attrs.wit), int(w.attrs.wit), "悟性不變")
	assert_eq(float(up.rg_scale), 2.0)
	var down := RoguePower.scale_spec(w, 0.5)
	for k in down.skills:
		assert_true(int(down.skills[k]) >= 1, "技能至少 1")
	assert_eq(int(down.attrs.str), clampi(int(w.attrs.str) - 3, 5, 60))
	assert_true(RoguePower.unit_power(up, tables) > RoguePower.unit_power(w, tables), "放大 → P 大")
	assert_true(RoguePower.unit_power(down, tables) < RoguePower.unit_power(w, tables), "縮小 → P 小")
	assert_eq(int(w.qi_max), int(Encounter.monster_spec("m_bandit", tables).qi_max), "不改原字典")

func test_scale_to_converges() -> void:
	for mid in ["m_bandit", "m_npc_wushi", "m_em_zhouzhiruo", "m_rg_linghuchong"]:
		var sp := Encounter.monster_spec(mid, tables)
		if not assert_false(sp.is_empty(), "%s 存在" % mid):
			continue
		var raw := RoguePower.unit_power(sp, tables)
		for f in [0.8, 1.3]:
			var res := RoguePower.scale_to(sp, raw * f, tables)
			assert_true(bool(res.ok), "%s ×%.1f 收斂（得 %.1f／目標 %.1f）" % [mid, f, float(res.power), raw * f])
			assert_true(absf(float(res.power) - raw * f) <= raw * f * 0.03 + 0.001, "%s ±3%%" % mid)
			assert_true(float(res.s) >= 0.5 and float(res.s) <= 2.5)

func test_scale_to_bounds() -> void:
	var sp := Encounter.monster_spec("m_wolf", tables)
	var raw := RoguePower.unit_power(sp, tables)
	var hi := RoguePower.scale_to(sp, raw * 100.0, tables)
	assert_eq(float(hi.s), 2.5, "到不了 → 夾在上限")
	assert_false(bool(hi.ok))
	var lo := RoguePower.scale_to(sp, raw * 0.01, tables)
	assert_eq(float(lo.s), 0.5, "到不了 → 夾在下限")
	assert_false(bool(lo.ok))

func test_reference_is_duel_balance() -> void:
	var me := _base()
	me.attrs.str = 25
	var p_default := RoguePower.unit_power(me, tables)
	RoguePower.set_reference(me)
	assert_true(RoguePower.has_reference())
	assert_true(absf(RoguePower.unit_power(me, tables) - sqrt(float(me.qi_max))) < 0.01, "以自己為參考：P = √氣上限")
	var wolf := Encounter.monster_spec("m_wolf", tables)
	var pw := RoguePower.unit_power(wolf, tables)
	var res := RoguePower.scale_to(wolf, RoguePower.unit_power(me, tables), tables)
	assert_true(absf(float(res.power) - sqrt(float(me.qi_max))) <= sqrt(float(me.qi_max)) * 0.03 + 0.01 or not bool(res.ok), "縮放到同戰力")
	RoguePower.clear_reference()
	assert_false(RoguePower.has_reference())
	assert_true(absf(RoguePower.unit_power(me, tables) - p_default) < 0.0001, "清掉後回到固定參考")
	assert_true(pw > 0.0)

func test_prepare_fight_clears_reference() -> void:
	var run := RogueRun.new()
	run.seed = 9
	run.round = 3
	var r := RogueRules.rules(tables)
	var prep := RogueFoes.prepare_fight(run, _base(), tables, r)
	assert_false(RoguePower.has_reference(), "用完清掉")
	assert_true(float(prep.my_unit) > 0.0 and float(prep.target) > 0.0)
	assert_false((prep.gen.specs as Array).is_empty(), "有對手")
