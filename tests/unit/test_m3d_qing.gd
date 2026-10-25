extends "res://tests/unit/test_battle_helpers.gd"
## M3D_PLAN §3.2、§10.1（WP-COMBAT）：戰鬥指令「輕」（QING，2002，跟著 later_battle_cmds）——
## JUMP 越過敵人、範圍 +1、內力；ESCAPE 機率邊界、不能脫身的戰鬥（任務戰、試煉、劫鏢方）、追擊戰可以、規則關。

## 玩家（uid 1）在 (1,3)，野狼（uid 2）在 (2,3)，木人（uid 3）在 (2,2)、(2,4) 擋路
func _b(pover: Dictionary = {}, opts := {}) -> Battle:
	var p := { "qi": 100000, "qi_max": 100000, "neili": 100, "neili_max": 100 }
	p.merge(pover, true)
	var b := make_battle([player_spec(p), monster("m_wolf"), monster("m_dummy"), monster("m_dummy")], 4242, opts)
	place(b, 1, 1, 3)
	place(b, 2, 2, 3)
	place(b, 3, 2, 2)
	place(b, 4, 2, 4)
	return b

func test_jump_over_enemy() -> void:
	var b := _b()
	var u := b.unit(1)
	assert_eq(BattleFormulas.move_range(u), 2)
	assert_eq(do_cmd(b, 1, { "cmd": "MOVE", "target": [4, 3] }).err, "out_of_range", "一般移動被擋住、也不夠遠")
	assert_true(b.grid.jump_targets(u).has(Vector2i(4, 3)), "jump_targets(u)：移動範圍 + 1")
	assert_false(b.grid.jump_targets(u).has(Vector2i(5, 3)), "距離 4 不行")
	var r := do_cmd(b, 1, { "cmd": "QING", "mode": "JUMP", "target": [4, 3] })
	assert_eq(r.err, "")
	assert_eq(u.pos, Vector2i(4, 3), "越過野狼")
	assert_eq(u.neili, 100 - (10 + 2 * 2), "內力 10 + 2 × 移動範圍")
	assert_eq(u.gauge, Battle.MOVE_GAUGE, "時間棒照移動")
	var j := find(r.events, "battle_qing_jump")
	assert_eq(j.size(), 1)
	assert_eq(j[0].p.from, [1, 3])
	assert_eq(j[0].p.to, [4, 3])

func test_jump_reasons() -> void:
	var b := _b()
	assert_eq(do_cmd(b, 1, { "cmd": "QING", "mode": "JUMP", "target": [5, 3] }).err, "out_of_range")
	assert_eq(do_cmd(b, 1, { "cmd": "QING", "mode": "JUMP", "target": [2, 3] }).err, "occupied")
	assert_eq(do_cmd(b, 1, { "cmd": "QING", "mode": "JUMP" }).err, "bad_cmd", "沒有目標格")
	assert_eq(do_cmd(b, 1, { "cmd": "QING", "mode": "FLY", "target": [4, 3] }).err, "bad_cmd", "不認得的 mode")
	b.unit(1).neili = 13
	assert_eq(do_cmd(b, 1, { "cmd": "QING", "mode": "JUMP", "target": [4, 3] }).err, "not_enough_neili")
	b.unit(1).neili = 14
	assert_eq(do_cmd(b, 1, { "cmd": "QING", "mode": "JUMP", "target": [4, 3] }).err, "")
	# 輕功 25 → 移動範圍 3、跳 4 格、內力 16
	b = _b({ "lightness": 25 })
	assert_true(b.grid.jump_targets(b.unit(1)).has(Vector2i(5, 3)))
	assert_eq(BattleRules.qing_jump_cost(b.unit(1)), 16)
	# 封穴：不能移動 → 也不能飛身
	b = _b()
	b.unit(1).statuses["acupoint"] = 3
	assert_eq(do_cmd(b, 1, { "cmd": "QING", "mode": "JUMP", "target": [4, 3] }, _t()).err, "status_blocked")
	assert_eq(do_cmd(b, 1, { "cmd": "QING", "mode": "ESCAPE" }, _t()).err, "status_blocked")

func test_rule_off() -> void:
	var b := _b({}, { "later_battle_cmds": false })
	assert_eq(do_cmd(b, 1, { "cmd": "QING", "mode": "ESCAPE" }).err, "qing_off")
	assert_eq(do_cmd(b, 1, { "cmd": "QING", "mode": "JUMP", "target": [4, 3] }).err, "qing_off")
	assert_eq(b.unit_snapshot(b.unit(1), tables()).cmd_avail.QING, [])
	b = _b()
	assert_eq(b.unit_snapshot(b.unit(1), tables()).cmd_avail.QING, ["JUMP", "ESCAPE"])
	b.unit(1).neili = 20
	assert_eq(b.unit_snapshot(b.unit(1), tables()).cmd_avail.QING, ["JUMP"], "內力不到 30 不能脫身")

func test_escape_chance_bounds() -> void:
	var b := _b()
	assert_true(approx(BattleRules.qing_escape_chance(b.unit(1)), 0.20), "輕功 0、基本輕功 0 → 20%")
	b.unit(1).spec["lightness"] = 50
	b.unit(1).spec["skills"] = { "basic_body": 50 }
	assert_true(approx(BattleRules.qing_escape_chance(b.unit(1)), 0.50), "20 + 50×0.4 + 50×0.2 = 50%")
	b.unit(1).spec["lightness"] = 300
	assert_true(approx(BattleRules.qing_escape_chance(b.unit(1)), 0.80), "上限 80%")

## 輕功 50、基本輕功 50 → 50%：600 次的成功率 ∈ [0.44, 0.56]；成功＝離場、失敗＝時間棒歸 0
func test_escape_rate_and_events() -> void:
	var ok := 0
	var n := 600
	for sd in range(1, n + 1):
		var b := make_battle([player_spec({ "neili": 100, "neili_max": 100, "lightness": 50, "skills": { "basic_body": 50 } }),
			monster("m_dummy")], sd)
		var r := do_cmd(b, 1, { "cmd": "QING", "mode": "ESCAPE" })
		assert_eq(r.err, "")
		assert_eq(b.unit(1).neili, 70, "內力 30")
		if not find(r.events, "battle_qing_escape").is_empty():
			ok += 1
			assert_eq(b.unit(1).state, BattleUnit.FLED)
		else:
			assert_eq(find(r.events, "battle_qing_fail").size(), 1)
			assert_eq(b.unit(1).state, BattleUnit.CHARGING)
			assert_eq(b.unit(1).gauge, 0.0)
	var rate := float(ok) / n
	assert_true(rate >= 0.44 and rate <= 0.56, "脫身率 %.3f" % rate)

func test_escape_blocked_kinds() -> void:
	for kind in ["QUEST", "TRIAL", "ROGUE"]:
		var b := _b({}, { "kind": kind, "no_flee": true })
		assert_eq(do_cmd(b, 1, { "cmd": "QING", "mode": "ESCAPE" }).err, "no_flee", kind)
		assert_false(b.unit_snapshot(b.unit(1), tables()).cmd_avail.QING.has("ESCAPE"), kind + " 快照")
		# 烙跑鞋（flee_anywhere）也不行（ROGUE 審查：脫身會被當成倒下、結束這一局）
		var shoe := _b({ "flee_anywhere": true }, { "kind": kind, "no_flee": true })
		assert_eq(do_cmd(shoe, 1, { "cmd": "FLEE" }).err, "no_flee", kind + " 烙跑鞋")
		assert_false(bool(shoe.unit_snapshot(shoe.unit(1), tables()).get("flee_anywhere", false)), kind + " 快照 flee_anywhere")
	var c := _b({}, { "kind": "CHASE", "no_flee": true })
	assert_eq(do_cmd(c, 1, { "cmd": "QING", "mode": "ESCAPE" }).err, "", "追擊戰可以（功能和烙跑鞋一樣）")
	var rob := _b({}, { "kind": "ROB" })
	assert_eq(do_cmd(rob, 1, { "cmd": "QING", "mode": "ESCAPE" }).err, "no_flee", "劫鏢方（ROB side 0）不行")
	rob.unit(1).side = 1
	assert_eq(BattleRules.special_flee_blocked(rob, rob.unit(1)), false, "ROB side 1（押鏢方）可以")
	var duel := _b({}, { "kind": "DUEL" })
	assert_eq(do_cmd(duel, 1, { "cmd": "QING", "mode": "ESCAPE" }).err, "", "DUEL 逃＝棄權（WP-EVENTS 判定）")
	var low := _b({ "neili": 29 })
	assert_eq(do_cmd(low, 1, { "cmd": "QING", "mode": "ESCAPE" }).err, "not_enough_neili")

## status_effects 的 blocks 要用真的表（acupoint blocks MOVE、FLEE）
func _t() -> Dictionary:
	var t := tables().duplicate(true)
	if not (t.get("status_effects", {}) as Dictionary).has("acupoint"):
		t["status_effects"]["acupoint"] = { "id": "acupoint", "name": "封穴", "blocks": ["MOVE", "FLEE"], "duration_actions": 3 }
	return t
