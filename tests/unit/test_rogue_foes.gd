extends "res://tests/test_case.gd"
## ROGUE_PLAN §3.7、§9.1（WP-RUN）：目標戰力、人數、縮放到目標、首領回合、決定性。

var tables: Dictionary = {}
var r: Dictionary = {}

func before_each() -> void:
	if tables.is_empty():
		var loader := DataLoader.new()
		loader.load_all("res://data")
		tables = loader.activate(["1.0A", "1.0B", "rogue"])
	r = RogueRules.rules(tables)

func _run(seed: int, round: int) -> RogueRun:
	var run := RogueRun.new()
	run.seed = seed
	run.round = round
	return run

func test_target_curve() -> void:
	var p0 := float(r.p0)
	var t1 := RogueFoes.target(_run(1, 1), p0, r)
	var bl := float(r.blend)
	var want := float(r.diff_start) * ((1.0 - bl) * p0 * float(r.p0_mult) + bl * p0)
	assert_true(absf(t1 - want) < 0.001, "第 1 回合 = diff_start × ((1−blend)·p0_mult·P0 + blend·我方)")
	var t3 := RogueFoes.target(_run(1, 3), p0, r)
	var want3 := minf(float(r.diff_max), float(r.diff_start) + 2 * float(r.diff_step)) * ((1.0 - bl) * p0 * float(r.p0_mult) * pow(float(r.growth), 2) + bl * p0)
	assert_true(absf(t3 - want3) < 0.001, "第 3 回合：growth²、diff +2 步")
	var t4 := RogueFoes.target(_run(1, 4), p0, r)
	var t6 := RogueFoes.target(_run(1, 6), p0, r)
	assert_true(t4 > t1 and t6 > t4, "回合越後越強")
	var t5 := RogueFoes.target(_run(1, 5), p0, r)
	var nb := r.duplicate(true)
	nb["boss_every"] = 1000   # 同一回合、不是首領回合
	assert_true(absf(t5 - RogueFoes.target(_run(1, 5), p0, nb) * float(r.boss_mult)) < 0.001, "首領回合 × boss_mult")
	assert_true(t5 > t4, "首領回合比前一回合強")
	assert_true(RogueFoes.target(_run(1, 3), p0 * 4.0, r) > RogueFoes.target(_run(1, 3), p0, r), "我方越強對手越強")

func test_counts_by_round() -> void:
	for s in range(1, 25):
		var run := _run(s, 1 + s % 2)
		var g := RogueFoes.generate(run, RogueFoes.target(run, float(r.p0), r), tables, run.rng_for("foes"))
		assert_eq((g.specs as Array).size(), 1, "回合 1–2 一名")
	for s in range(1, 25):
		var run2 := _run(s, 3)
		var g2 := RogueFoes.generate(run2, RogueFoes.target(run2, 20.0, r), tables, run2.rng_for("foes"))
		var n := (g2.specs as Array).size()
		assert_true(n >= 1 and n <= 2, "回合 3–4 一到二名：%d" % n)
	for s in range(1, 25):
		var run3 := _run(s, 7)
		var g3 := RogueFoes.generate(run3, RogueFoes.target(run3, 40.0, r), tables, run3.rng_for("foes"))
		var n3 := (g3.specs as Array).size()
		assert_true(n3 >= 1 and n3 <= 3, "回合 5+ 一到三名：%d" % n3)

func test_power_within_10pct() -> void:
	var ok := 0
	var total := 0
	for s in range(1, 41):
		var rnd := 1 + s % 14
		var my := float(r.p0) * (1.0 + 0.25 * rnd)
		var run := _run(s, rnd)
		var tgt := RogueFoes.target(run, my, r)
		var g := RogueFoes.generate(run, tgt, tables, run.rng_for("foes"))
		total += 1
		if absf(float(g.power) - tgt) <= tgt * 0.10:
			ok += 1
		for sp in g.specs:
			assert_eq(int(sp.side), 1)
			assert_true(float(sp.get("rg_scale", 1.0)) >= 0.5 and float(sp.get("rg_scale", 1.0)) <= 2.5, "縮放係數在 [0.5, 2.5]")
	assert_true(ok >= int(total * 0.9), "總戰力在目標 ±10%%：%d／%d" % [ok, total])

func test_boss_round_unique_and_min_round() -> void:
	var run := _run(99, 5)
	var seen := {}
	for i in 7:
		var g := RogueFoes.generate(run, RogueFoes.target(run, 30.0, r), tables, run.rng_for("foes"))
		var bid := str(g.boss_id)
		assert_true(bid != "", "首領回合有首領")
		assert_true(bool(tables.rogue_foes[bid].boss))
		assert_true(int(tables.rogue_foes[bid].min_round) <= 5, "min_round 遵守")
		assert_false(seen.has(bid), "同一局不重複：%s" % bid)
		seen[bid] = true
		run.bosses_seen.append(bid)
		assert_true(str(g.boss_name) != "")
		assert_true((g.specs as Array).size() <= 3)
		run.wins += 1   # 換一個亂數流
	for s in range(1, 30):
		var run2 := _run(s, 3)
		var g2 := RogueFoes.generate(run2, 20.0, tables, run2.rng_for("foes"))
		assert_eq(str(g2.boss_id), "", "非首領回合沒有首領")
		for fid in g2.foes:
			assert_true(int(tables.rogue_foes[fid].min_round) <= 3, "min_round：%s" % fid)
			assert_false(bool(tables.rogue_foes[fid].boss))

func test_determinism() -> void:
	var a := RogueFoes.generate(_run(1234, 7), 50.0, tables, _run(1234, 7).rng_for("foes"))
	var b := RogueFoes.generate(_run(1234, 7), 50.0, tables, _run(1234, 7).rng_for("foes"))
	assert_eq(a.foes, b.foes)
	assert_eq(float(a.power), float(b.power))

func test_npc_naming_and_dup_suffix() -> void:
	var sp := RogueFoes.foe_spec(tables.rogue_foes["rg_f_zhouzhiruo"], tables)
	assert_eq(str(sp.ref), "n_em_zhouzhiruo", "立繪用 NPC")
	assert_eq(str(sp.name), "周芷若")
	assert_eq(str(sp.monster_row), "m_rg_zhouzhiruo", "試煉自己的周芷若列（MUD 的 m_em_zhouzhiruo 不變）")
	assert_true(int(sp.qi_max) < 1200, "override 換成試煉級距")
	assert_eq(str((sp.arts as Array)[0]), "mon_baigu", "周芷若用九陰白骨爪（審查）")
	var run := _run(5, 2)
	run.debug_foes = ["rg_f_wolf", "rg_f_wolf"]
	var g := RogueFoes.generate(run, 10.0, tables, run.rng_for("foes"))
	assert_eq((g.specs as Array).size(), 2)
	assert_eq(str(g.specs[0].name), "野狼甲")
	assert_eq(str(g.specs[1].name), "野狼乙")
	assert_true(run.debug_foes.is_empty(), "只用一次")
	assert_false(g.specs[0].has("rg_scale"), "debug 對手不縮放")
