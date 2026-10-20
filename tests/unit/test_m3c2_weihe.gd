extends "res://tests/unit/test_battle_helpers.gd"
## M3C2_PLAN §3、§10.1（WP-PACE）：血刀威嚇（HEAVY）小幅削弱。
## 常數 1.5 → 1.4、觸發機率 × 0.9；一樣只擲一次亂數（其他效果的亂數序列不變）；期望增傷（解析）新／舊 ≈ 0.72；
## 固定種子下觸發次數比 ≈ 0.9；觸發時傷害 × 1.4。

func _xd(lv: int) -> Dictionary:
	return { "sect": "xuedao", "sect_skill": { "id": "weihe", "effect": "HEAVY", "level": lv },
		"jing": 9000, "jing_max": 9000, "shen": 88, "neili": 9000, "neili_max": 9000 }

func test_constants() -> void:
	assert_eq(BattleStatus.HEAVY_MULT, 1.4)
	assert_eq(BattleStatus.HEAVY_CHANCE_MULT, 0.9)

func test_expected_uplift_ratio_analytic() -> void:
	for lv in [10, 50, 100]:
		var p := BattleFormulas.proc_chance(lv)
		var old_up := p * 0.5
		var new_up := p * BattleStatus.HEAVY_CHANCE_MULT * (BattleStatus.HEAVY_MULT - 1.0)
		var ratio := new_up / old_up
		assert_true(ratio >= 0.70 and ratio <= 0.80, "lv %d ratio %.3f" % [lv, ratio])
	assert_eq(snappedf(BattleFormulas.proc_chance(100) * 0.9, 0.0001), 0.225)

## 一樣只擲一次亂數：HEAVY 與 EVADE 各呼叫一次 try_proc 後亂數狀態相同
func test_single_rng_draw() -> void:
	var b1 := make_battle([player_spec(_xd(100)), monster("m_dummy")], 77)
	var b2 := make_battle([player_spec({ "sect": "emei", "sect_skill": { "id": "duane", "effect": "EVADE", "level": 100 },
		"jing": 9000, "shen": 9000 }), monster("m_dummy")], 77)
	assert_eq(b1.rng.state, b2.rng.state, "同種子")
	BattleStatus.try_proc(b1, b1.unit(1), "HEAVY", tables())
	BattleStatus.try_proc(b2, b2.unit(1), "EVADE", tables())
	assert_eq(b1.rng.state, b2.rng.state, "各擲一次")

## 固定種子：觸發率 ≈ 0.225（lv 100），與「不乘 0.9」的同一串亂數比 ≈ 0.9
func test_trigger_ratio_fixed_seed() -> void:
	var b := make_battle([player_spec(_xd(100)), monster("m_dummy")], 4242)
	var u := b.unit(1)
	var rng := RandomNumberGenerator.new()
	var hits := 0
	var old_hits := 0
	var n := 4000
	for i in n:
		rng.state = b.rng.state
		var x := rng.randf()
		if x < BattleFormulas.proc_chance(100):
			old_hits += 1
		u.jing = 9000
		u.neili = 9000
		if BattleStatus.try_proc(b, u, "HEAVY", tables()):
			hits += 1
	var rate := hits / float(n)
	assert_true(rate >= 0.20 and rate <= 0.25, "觸發率 %.3f" % rate)
	var r := hits / float(maxi(1, old_hits))
	assert_true(r >= 0.87 and r <= 0.93, "觸發次數比 %.3f" % r)

## 觸發時的傷害 × 1.4：同一個種子、同一下攻擊。精不夠付觸發消耗時 try_proc 不擲亂數（M3B D12），
## 所以「付不起」的那場傷害就是威嚇之前的基礎傷害；有觸發的那場 = max(1, round(基礎 × 1.4))
func _hit_dmg(over: Dictionary, sd: int) -> Dictionary:
	var b := make_battle([player_spec(over), monster("m_dummy", { "qi": 99999, "qi_max": 99999 })], sd)
	place(b, 1, 1, 3)
	place(b, 2, 2, 3)
	var r := do_cmd(b, 1, { "cmd": "ATTACK", "target": [2, 3] })
	var dmg := 0
	for e in r.events:
		if int(e.p.get("atk_uid", 0)) == 1 and e.p.has("dmg") and not e.p.get("counter", false):
			dmg = int(e.p.dmg)
	return { "dmg": dmg, "proc": not find(r.events, "battle_proc_HEAVY").is_empty() }

func test_proc_damage_mult() -> void:
	var checked := 0
	for sd in range(1, 400):
		var a := _hit_dmg(_xd(100), sd)
		if not bool(a["proc"]) or int(a["dmg"]) <= 0:
			continue
		var base := _hit_dmg(_xd(100).merged({ "jing": 2 }, true), sd)
		assert_false(bool(base["proc"]))
		assert_eq(int(a["dmg"]), maxi(1, roundi(int(base["dmg"]) * 1.4)), "seed %d：%d vs 基礎 %d" % [sd, int(a["dmg"]), int(base["dmg"])])
		checked += 1
		if checked >= 6:
			break
	assert_true(checked >= 3, "找到觸發的出手 %d" % checked)
