extends "res://tests/unit/test_battle_helpers.gd"
## M3D_PLAN §3.1、§10.1（WP-COMBAT）：戰鬥指令「閃」（DODGE，2001；規則 dodge_cmd）——
## 命中率下降量、閃的人不反擊、到下次行動清除、規則關閉、事件與快照。

## 玩家（uid 1）在 (1,3)，野狼（uid 2）在 (2,3)
func _b(pover: Dictionary = {}, opts := {}) -> Battle:
	var p := { "qi": 100000, "qi_max": 100000 }
	p.merge(pover, true)
	var b := make_battle([player_spec(p), monster("m_wolf", { "qi": 100000, "qi_max": 100000 })], 4242, opts)
	place(b, 1, 1, 3)
	place(b, 2, 2, 3)
	return b

func test_cmds_include_dodge_and_qing() -> void:
	assert_has(BattleRules.CMDS, "DODGE")
	assert_has(BattleRules.CMDS, "QING")
	assert_eq(BattleRules.normalize_cmd({ "cmd": "DODGE" }).cmd, "DODGE")

func test_drop_formula() -> void:
	var b := _b()
	var u := b.unit(1)
	assert_true(approx(BattleRules.dodge_hit_drop(u), 0.15), "基本閃躲 0 → 0.15")
	u.spec["skills"] = { "basic_dodge": 100 }
	assert_true(approx(BattleRules.dodge_hit_drop(u), 0.25), "基本閃躲 100 → 0.25")
	u.spec["skills"] = { "basic_dodge": 400 }
	assert_true(approx(BattleRules.dodge_hit_drop(u), 0.30), "上限 0.30")

## 野狼打玩家 4000 下：閃的時候命中率少 dodge_hit_drop（±0.03）
func test_hit_rate_drops() -> void:
	var rates := []
	for dodging in [false, true]:
		var b := _b()
		var wolf := b.unit(2)
		var me := b.unit(1)
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var hits := 0
		var n := 4000
		for i in n:
			me.dodging = dodging
			me.qi = me.qi_max()
			var ev := BattleRules.resolve_strike(b, wolf, me, {}, {}, 0, tables(), rng, false, true)
			if find(ev, "battle_miss").is_empty():
				hits += 1
			elif dodging:
				assert_true(bool(find(ev, "battle_miss")[0].p.get("dodged", false)), "閃掉的 battle_miss 帶 dodged")
		rates.append(float(hits) / n)
	var drop: float = rates[0] - rates[1]
	var art_level := BattleFormulas.base_level(_b().unit(2), "basic_fist", "", tables())
	var base := BattleFormulas.hit_chance(_b().unit(2), _b().unit(1), art_level)
	var want := minf(base, BattleRules.dodge_hit_drop(_b().unit(1)))
	assert_true(absf(drop - want) <= 0.03, "命中率 %.3f → %.3f（下降 %.3f，應 %.3f）" % [rates[0], rates[1], drop, want])
	assert_true(drop >= 0.12 and drop <= 0.33, "15–30 個百分點的帶（含抽樣誤差）")

## 定力 60 的玩家正常會反擊；閃的時候一次都不反擊
func test_dodging_never_counters() -> void:
	for dodging in [false, true]:
		var b := _b({ "attrs": { "cal": 60 } })
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var counters := 0
		for i in 600:
			b.unit(1).dodging = dodging
			b.unit(1).qi = 100000
			b.unit(2).qi = 100000
			var ev := BattleRules.resolve_strike(b, b.unit(2), b.unit(1), {}, {}, 0, tables(), rng, false)
			counters += find(ev, "battle_counter").size()
		if dodging:
			assert_eq(counters, 0, "閃的人不反擊")
		else:
			assert_true(counters > 0, "沒閃時會反擊（%d）" % counters)

func test_execute_and_clear_on_next_action() -> void:
	var b := _b()
	var r := do_cmd(b, 1, { "cmd": "DODGE" })
	assert_eq(r.err, "")
	assert_eq(find(r.events, "battle_dodge").size(), 1, "battle_dodge")
	assert_true(b.unit(1).dodging, "閃中")
	assert_eq(b.unit(1).gauge, 0.0, "只花一回合：時間棒歸 0")
	assert_true(bool(b.unit_snapshot(b.unit(1), tables()).dodging), "快照 dodging")
	r = do_cmd(b, 1, { "cmd": "DEFEND" })
	assert_eq(r.err, "")
	assert_false(b.unit(1).dodging, "下次行動開頭清掉")

func test_rule_off() -> void:
	var b := _b({}, { "dodge_cmd": false })
	assert_eq(do_cmd(b, 1, { "cmd": "DODGE" }).err, "dodge_off", "規則 dodge_cmd 關")
	assert_eq(b.unit_snapshot(b.unit(1), tables()).cmd_avail.DODGE, false)
	assert_eq(b.snapshot(tables()).dodge_cmd, false)
	b = _b()
	assert_eq(b.unit_snapshot(b.unit(1), tables()).cmd_avail.DODGE, true, "缺省開")

func test_submit_path() -> void:
	var b := make_battle([player_spec({ "qi": 100000, "qi_max": 100000 }), monster("m_dummy")], 11)
	run_until_ready(b, 1)
	assert_eq(b.submit(1, { "cmd": "DODGE" }, tables()), "")
	var ev := b.step(Battle.TICK, tables())
	assert_eq(find(ev, "battle_dodge").size(), 1)
