extends "res://tests/unit/test_battle_helpers.gd"
## M3D_PLAN §3.4、§10.1（WP-COMBAT）：無敵烙跑鞋（FLEE_ANYWHERE）——任何格子都能逃、追擊戰與 PK 也可以；
## 任務戰（QUEST）、試煉（TRIAL）、劫鏢方（ROB 的 side 0）不行。資料列與 to_combatant 見 test_m3d_combo（主機端）。

func _b(shoes: bool, opts := {}) -> Battle:
	var b := make_battle([player_spec({ "flee_anywhere": shoes }), monster("m_dummy")], 4242, opts)
	place(b, 1, 1, 3)
	place(b, 2, 2, 3)
	return b

func test_any_cell() -> void:
	var b := _b(false)
	assert_false(b.grid.is_escape(b.unit(1).pos))
	assert_eq(do_cmd(b, 1, { "cmd": "FLEE" }).err, "not_on_escape", "沒穿鞋要站逃跑格")
	b = _b(true)
	var r := do_cmd(b, 1, { "cmd": "FLEE" })
	assert_eq(r.err, "", "穿鞋任何格子都能逃")
	assert_eq(b.unit(1).state, BattleUnit.FLED, "100% 成功")
	assert_eq(find(r.events, "battle_flee").size(), 1)

func test_chase_and_pvp_ok() -> void:
	for kind in ["CHASE", "ENCOUNTER", "SECT_GUARD"]:
		var b := _b(true, { "kind": kind, "no_flee": true })
		assert_eq(do_cmd(b, 1, { "cmd": "FLEE" }).err, "", "%s（no_flee）穿鞋可以逃" % kind)
	for kind in ["FORCED", "CHALLENGE", "SEIZE", "DUEL"]:
		var b := _b(true, { "kind": kind })
		assert_eq(do_cmd(b, 1, { "cmd": "FLEE" }).err, "", kind)
	var b2 := _b(false, { "kind": "CHASE", "no_flee": true })
	assert_eq(do_cmd(b2, 1, { "cmd": "FLEE" }).err, "no_flee", "沒穿鞋照舊不能逃追擊戰")

func test_blocked_kinds() -> void:
	for kind in ["QUEST", "TRIAL"]:
		var b := _b(true, { "kind": kind, "no_flee": true })
		assert_eq(do_cmd(b, 1, { "cmd": "FLEE" }).err, "no_flee", kind)
		var b2 := _b(true, { "kind": kind })
		assert_eq(do_cmd(b2, 1, { "cmd": "FLEE" }).err, "not_on_escape", kind + "（沒有 no_flee 也只照一般規則）")
	var rob := _b(true, { "kind": "ROB", "no_flee": true })
	assert_eq(do_cmd(rob, 1, { "cmd": "FLEE" }).err, "no_flee", "劫鏢方（side 0）不行")
	var rob1 := _b(true, { "kind": "ROB" })
	rob1.unit(1).side = 1
	assert_eq(do_cmd(rob1, 1, { "cmd": "FLEE" }).err, "", "押鏢方（side 1）可以")

func test_snapshot_flag() -> void:
	var b := _b(true)
	assert_true(bool(b.unit_snapshot(b.unit(1), tables()).flee_anywhere))
	b = _b(true, { "kind": "QUEST" })
	assert_false(bool(b.unit_snapshot(b.unit(1), tables()).flee_anywhere), "任務戰不顯示")
	b = _b(false)
	assert_false(bool(b.unit_snapshot(b.unit(1), tables()).flee_anywhere))
