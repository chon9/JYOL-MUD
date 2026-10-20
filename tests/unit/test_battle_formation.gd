extends "res://tests/unit/test_battle_helpers.gd"
## M3A_PLAN 5.4（陣）、10.1：3 人陣成功、站位不足、性別限制、一人倒下破陣、移動破陣、加成數值。

func _member(peer: int, over: Dictionary = {}) -> Dictionary:
	var p := { "neili": 50, "neili_max": 50, "party_id": "pt1", "gender": "M",
		"skills": { "t_formation": 20, "basic_formation": 10 },
		"cmd_arts": { "FORMATION": ["t_formation"] } }
	p.merge(over, true)
	return ally_spec(peer, p) if peer != 1 else player_spec(p)

## 隊長 (2,3)、兩位隊員在 (1,4)、(3,4)（side 0：站位 [-1,1]、[1,1]）
func _b(o1 := {}, o2 := {}, o3 := {}) -> Battle:
	var b := make_battle([_member(1, o1), _member(2, o2), _member(3, o3), monster("m_dummy")], 11)
	place(b, 1, 2, 3)
	place(b, 2, 1, 4)
	place(b, 3, 3, 4)
	place(b, 4, 9, 3)
	return b

func _form(b: Battle, art := "t_formation") -> Dictionary:
	return do_cmd(b, 1, { "cmd": "FORMATION", "art": art })

func test_three_person_formation_success_and_bonus() -> void:
	var b := _b()
	var r := _form(b)
	assert_eq(r.err, "")
	var on := find(r.events, "battle_formation_on")
	assert_eq(on.size(), 1)
	assert_eq(on[0].p.art_name, "測試三才陣")
	assert_eq(on[0].p.members.size(), 3)
	# 平均陣法等級 = (20 + 10) / 2 = 15 → 攻 × 1.13、防 × 1.23
	for uid in [1, 2, 3]:
		var u := b.unit(uid)
		assert_true(u.statuses.has("formation"), "成員 %d 有陣法加持" % uid)
		assert_true(approx(BattleStatus.atk_mult(u, tables()), 1.13), "攻")
		assert_true(approx(BattleStatus.def_mult(u, tables()), 1.23), "防")
	assert_eq(b.unit(1).neili, 40, "施陣者扣 cost_inner")
	assert_eq(b.unit(2).neili, 50, "其他人下次行動才扣")
	do_cmd(b, 2, { "cmd": "DEFEND" })
	assert_eq(b.unit(2).neili, 40)
	do_cmd(b, 2, { "cmd": "DEFEND" })
	assert_eq(b.unit(2).neili, 40, "只扣一次")
	# 陣法加持讓攻擊力變高
	var plain := BattleFormulas.attack_power(b.unit(3), {}, {}, 0, tables())
	assert_true(plain * BattleStatus.atk_mult(b.unit(3), tables()) > plain)

func test_party_size_gender_and_party_id() -> void:
	var b := _b({}, {}, { "party_id": "other" })
	assert_eq(_form(b).err, "formation_party", "不同隊伍")
	b = _b({}, {}, { "skills": { "basic_formation": 10 } })
	assert_eq(_form(b).err, "formation_party", "不會此陣")
	b = _b({ "cmd_arts": {} })
	assert_eq(_form(b).err, "no_formation_art")
	assert_eq(do_cmd(b, 2, { "cmd": "FORMATION", "art": "sl_changquan" }).err, "no_formation_art")
	# 女子陣（2 人，限女）：男性 → formation_party
	var fo := { "skills": { "t_formation_f": 5 }, "cmd_arts": { "FORMATION": ["t_formation_f"] } }
	b = _b(fo, fo, fo)
	assert_eq(_form(b, "t_formation_f").err, "formation_party", "性別不符")
	var ff := fo.duplicate(true)
	ff["gender"] = "F"
	b = _b(ff, ff, fo)
	place(b, 2, 2, 4)   # 站位 [0,1]
	assert_eq(_form(b, "t_formation_f").err, "")

func test_stations_and_neili() -> void:
	var b := _b()
	place(b, 3, 4, 4)
	assert_eq(_form(b).err, "formation_stations", "站位格上沒有隊友")
	place(b, 3, 3, 4)
	b.unit(1).neili = 9
	assert_eq(_form(b).err, "not_enough_neili")

func test_right_side_mirror() -> void:
	# 在右側（side 1）時左右鏡像：[-1,1] → x+1
	var b := _b()
	var u := b.unit(1)
	u.side = 1
	assert_eq(BattleCmds.station_cell(u, [-1, 1]), Vector2i(3, 4))
	u.side = 0
	assert_eq(BattleCmds.station_cell(u, [-1, 1]), Vector2i(1, 4))

func test_member_death_breaks_formation() -> void:
	var b := _b()
	_form(b)
	var ev := BattleRules.kill(b, b.unit(3), b.unit(4))
	assert_eq(find(ev, "battle_formation_off").size(), 1)
	assert_eq(find(ev, "battle_formation_off")[0].p.art_name, "測試三才陣")
	for uid in [1, 2, 3]:
		assert_false(b.unit(uid).statuses.has("formation"))
		assert_true(b.unit(uid).formation.is_empty())

func test_move_breaks_formation() -> void:
	var b := _b()
	_form(b)
	var r := do_cmd(b, 2, { "cmd": "MOVE", "target": [0, 4] })
	assert_eq(r.err, "")
	assert_eq(find(r.events, "battle_formation_off").size(), 1)
	for uid in [1, 2, 3]:
		assert_false(b.unit(uid).statuses.has("formation"))

func test_upkeep_failure_breaks_formation() -> void:
	var b := _b({}, { "neili": 5 })
	_form(b)
	var r := do_cmd(b, 2, { "cmd": "DEFEND" })
	assert_eq(find(r.events, "battle_formation_off").size(), 1, "內力不夠退出陣法 → 破陣")
	assert_false(b.unit(1).statuses.has("formation"))

func test_snapshot_formation_field() -> void:
	var b := _b()
	var d := b.unit_snapshot(b.unit(1), tables())
	assert_eq(d.cmd_avail.FORMATION, true)
	assert_eq(d.formation.art, "t_formation")
	assert_eq(d.formation.stations, [[0, 0], [-1, 1], [1, 1]])
	assert_eq(d.formation.party_size, 3)
