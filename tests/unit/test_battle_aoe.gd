extends "res://tests/unit/test_battle_helpers.gd"
## M3A_PLAN 5.3、10.1：六種形狀的格子集合（含邊界與鏡像）、多目標各自結算、不反擊、bad_direction、no_target。

func _cells(cells: Array) -> Array:
	var out: Array = []
	for p in cells:
		out.append([p.x, p.y])
	out.sort()
	return out

func _v(list: Array) -> Array:
	var out: Array = list.duplicate(true)
	out.sort()
	return out

func test_single_cross_cross_l() -> void:
	var o := Vector2i(1, 3)
	assert_eq(_cells(BattleAoe.cells("SINGLE", o, Vector2i(2, 3), 1)), [[2, 3]])
	assert_eq(_cells(BattleAoe.cells("CROSS", o, Vector2i(5, 4), 3)), _v([[5, 4], [6, 4], [4, 4], [5, 5], [5, 3]]))
	var big := BattleAoe.cells("CROSS_L", o, Vector2i(5, 4), 3)
	assert_eq(big.size(), 13, "大十字 13 格")
	assert_true(big.has(Vector2i(8, 4)) and big.has(Vector2i(2, 4)) and big.has(Vector2i(5, 7)) and big.has(Vector2i(5, 1)))
	# 邊界：中心在角落，場外格去掉
	assert_eq(_cells(BattleAoe.cells("CROSS", Vector2i(5, 5), Vector2i(0, 0), 9)), _v([[0, 0], [1, 0], [0, 1]]))
	assert_eq(BattleAoe.cells("CROSS_L", Vector2i(5, 5), Vector2i(11, 7), 9).size(), 7)
	# 施招者自己不算在格子裡
	assert_false(BattleAoe.cells("CROSS", Vector2i(2, 3), Vector2i(1, 3), 1).has(Vector2i(2, 3)))

func test_line_fan_around_and_mirror() -> void:
	var o := Vector2i(5, 4)
	assert_eq(_cells(BattleAoe.cells("LINE", o, Vector2i(6, 4), 3)), _v([[6, 4], [7, 4], [8, 4]]))
	assert_eq(_cells(BattleAoe.cells("LINE", o, Vector2i(4, 4), 3)), _v([[4, 4], [3, 4], [2, 4]]), "鏡像（往左）")
	assert_eq(_cells(BattleAoe.cells("LINE", o, Vector2i(7, 6), 2)), _v([[6, 5], [7, 6]]), "斜線")
	assert_eq(BattleAoe.direction(o, Vector2i(7, 5)), Vector2i.ZERO, "不在 8 方向上")
	assert_eq(_cells(BattleAoe.cells("LINE", Vector2i(10, 4), Vector2i(11, 4), 3)), [[11, 4]], "邊界截斷")
	var fan := BattleAoe.cells("FAN", o, Vector2i(6, 4), 2)
	assert_eq(_cells(fan), _v([[6, 4], [7, 4], [6, 3], [7, 2], [6, 5], [7, 6]]), "往右的半米字")
	var fan_l := BattleAoe.cells("FAN", o, Vector2i(4, 4), 2)
	assert_eq(_cells(fan_l), _v([[4, 4], [3, 4], [4, 3], [3, 2], [4, 5], [3, 6]]), "往左（右側單位）鏡像")
	var fan_d := BattleAoe.cells("FAN", o, Vector2i(6, 5), 1)
	assert_eq(_cells(fan_d), _v([[6, 5], [6, 4], [5, 5]]), "斜方向：相鄰兩條是直線")
	var around := BattleAoe.cells("AROUND", o, o, 1)
	assert_eq(around.size(), 8)
	assert_eq(BattleAoe.cells("AROUND", Vector2i(0, 0), Vector2i(0, 0), 1).size(), 3, "角落")

func _aoe_battle(move_level := 10) -> Battle:
	var p := player_spec({ "weapon": bare(), "neili": 50, "neili_max": 50, "skills": { "t_cross": move_level }, "arts": ["t_cross"] })
	var b := make_battle([p, monster("m_dummy"), monster("m_dummy"), monster("m_dummy")], 5)
	place(b, 1, 1, 3)
	place(b, 2, 3, 3)
	place(b, 3, 3, 4)
	place(b, 4, 9, 7)
	return b

func _art(b: Battle, move: String, tgt: Array) -> Dictionary:
	return do_cmd(b, 1, { "cmd": "ART", "art": "t_cross", "move": move, "power_tenths": 10, "target": tgt })

func test_aoe_validation() -> void:
	var b := _aoe_battle()
	assert_eq(_art(b, "t_cross_1", [1, 5]).err, "no_target", "範圍內沒有敵人")
	assert_eq(_art(b, "t_cross_1", [5, 4]).err, "out_of_range", "中心格距離 5 > 3")
	assert_eq(_art(b, "t_line_1", [3, 4]).err, "bad_direction", "(2,1) 不在 8 方向上")
	assert_eq(_art(b, "t_line_1", [1, 3]).err, "bad_direction", "中心格是自己")
	assert_eq(_art(b, "t_line_1", [5, 3]).err, "out_of_range", "直線長度 3、中心 4 格外")
	assert_eq(_art(b, "t_fan_1", [1, 5]).err, "no_target", "往下的半米字打不到")
	assert_eq(_art(b, "t_around_1", [1, 3]).err, "no_target", "周身沒有敵人")

func test_aoe_hits_each_target_without_counter() -> void:
	var b := _aoe_battle()
	# 小十字中心 (3,3)：打到 (3,3) 與 (3,4) 兩隻
	var r := _art(b, "t_cross_1", [3, 3])
	assert_eq(r.err, "")
	var a := find(r.events, "battle_aoe")
	assert_eq(a.size(), 1)
	assert_eq(a[0].get("ui", false), true)
	assert_eq(a[0].p.targets, [2, 3])
	assert_eq(_v(a[0].p.cells), _v([[3, 3], [4, 3], [2, 3], [3, 4], [3, 2]]))
	var strikes := 0
	for e in r.events:
		if int(e.p.get("atk_uid", 0)) == 1 and (str(e.key).begins_with("move_") or e.key == "battle_miss"):
			strikes += 1
	assert_eq(strikes, 2, "每個目標各自結算")
	assert_eq(find(r.events, "battle_counter").size(), 0, "範圍招式不引發反擊")
	assert_eq(a[0].p.move, "小十字")

func test_aoe_inner_cost_once_and_ai_uses_aoe() -> void:
	var t := tables().duplicate(true)
	t.martial_arts.t_cross.moves[0]["cost_inner"] = 5   # 10 成 → 10
	var p := player_spec({ "weapon": bare(), "neili": 50, "neili_max": 50, "skills": { "t_cross": 10 }, "arts": ["t_cross"] })
	var b := make_battle([p, monster("m_dummy"), monster("m_dummy")], 5)
	place(b, 1, 1, 3)
	place(b, 2, 3, 3)
	place(b, 3, 3, 4)
	var r := do_cmd(b, 1, { "cmd": "ART", "art": "t_cross", "move": "t_cross_1", "power_tenths": 10, "target": [3, 3] }, t)
	assert_eq(r.err, "")
	assert_eq(b.unit(1).neili, 40, "兩個目標，內力只扣一次")
	# 快照：範圍招式標示 aoe、可用
	var d := b.unit_snapshot(b.unit(1), t)
	var mv: Dictionary = d.arts[0].moves[0]
	assert_eq(mv.aoe, "CROSS")
	assert_eq(mv.usable, true)

func test_monster_side_line_mirrored() -> void:
	# 右側（side 1）的單位往左打直線
	var b := make_battle([player_spec(), monster("m_dummy")], 9)
	place(b, 1, 6, 3)
	place(b, 2, 8, 3)
	var u := b.unit(2)
	var area := BattleAoe.cells("LINE", u.pos, Vector2i(7, 3), 3)
	assert_eq(_cells(area), _v([[7, 3], [6, 3], [5, 3]]))
	assert_eq(BattleAoe.enemies_in(b, u, area).map(func(x): return x.uid), [1])
