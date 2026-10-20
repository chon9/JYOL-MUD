extends "res://tests/unit/test_battle_helpers.gd"
## M3a 第三輪審查修正（戰鬥部分）的回歸測試：
## - A1：玩家武功「特」附帶中毒只在 later_battle_cmds 開時生效（news 316）；怪物專用武功不受影響；
## - B2：「醫」依 status_effects.cure_by 治狀態（流血止血；中毒限後期版）；
## - B3：指令武功用已解鎖的最高招；暗器武功扣招式內力、附帶招式狀態；醫術武功扣招式內力；
## - B5：氣全滿時不接受運功療傷（full_qi）與醫（nothing_to_heal）。

func _cmd_arts(over: Dictionary) -> Dictionary:
	var d := { "POISON": [], "MEDIC": [], "HIDDEN": [], "FORMATION": [], "INNER": [], "ACUPOINT": [] }
	d.merge(over, true)
	return d

## 深拷貝的表，套上 patch（status_effects／martial_arts 的列）
func _tables_with(arts: Dictionary = {}, statuses: Dictionary = {}) -> Dictionary:
	var t: Dictionary = tables().duplicate(true)
	for k in arts:
		t["martial_arts"][k] = arts[k]
	for k in statuses:
		var row: Dictionary = (t["status_effects"][k] as Dictionary).duplicate(true)
		row.merge(statuses[k], true)
		t["status_effects"][k] = row
	return t

func _move(id: String, unlock: int, power: int, rng: int, cost: int, status := "", chance := 0.0) -> Dictionary:
	return { "id": id, "name": id, "unlock_level": unlock, "power": power, "range": rng, "aoe": "SINGLE",
		"cost_inner": cost, "cost_jing": 0, "status": status, "status_chance": chance, "flavor": "move_fist_basic" }

func _make(specs: Array, t: Dictionary, seed_v: int, opts: Dictionary = {}) -> Battle:
	var b := Battle.new(7, seed_v, default_opts(opts))
	for s in specs:
		b.add_unit(s)
	b.start(t)
	return b

# ---------------------------------------------------------------- A1

func _venom_art(monster_only: bool) -> Dictionary:
	return { "id": "t_venom", "name": "測試毒掌", "sect_id": "", "category": "FIST", "base_skill": "basic_fist",
		"difficulty": 1.0, "monster_only": monster_only, "moves": [_move("t_venom_1", 1, 20, 1, 0, "poison", 1.0)] }

## 用毒掌打到命中為止，回傳目標身上有沒有中毒
func _venom_hit(later: bool, monster_only: bool) -> Variant:
	var t := _tables_with({ "t_venom": _venom_art(monster_only) })
	for sd in range(1, 60):
		var b := _make([player_spec({ "skills": { "t_venom": 10, "basic_fist": 10 }, "arts": ["t_venom"],
			"weapon": bare(), "weapon_options": [] }), monster("m_dummy")], t, sd, { "later_battle_cmds": later })
		place(b, 2, 2, 3)
		var r := do_cmd(b, 1, { "cmd": "ART", "art": "t_venom", "move": "t_venom_1", "power_tenths": 10, "target": [2, 3] }, t)
		assert_eq(r.err, "")
		if find(r.events, "move_fist_basic").is_empty() or not b.unit(2).is_active():
			continue
		return b.unit(2).statuses.has("poison")
	fail("59 個種子都沒命中")
	return null

func test_special_strike_poison_only_with_later_rules() -> void:
	assert_eq(_venom_hit(false, false), false, "2001（news 316）：用「特」只造成兵器傷害，不會中毒")
	assert_eq(_venom_hit(true, false), true, "後期版：招式附帶中毒")
	assert_eq(_venom_hit(false, true), true, "怪物專用武功（毒蛇等）不受影響")

func test_move_status_ok_helper() -> void:
	var b := make_battle([player_spec(), monster("m_dummy")], 1, { "later_battle_cmds": false })
	assert_false(BattleCmds.move_status_ok(b, {}, ""))
	assert_false(BattleCmds.move_status_ok(b, { "monster_only": false }, "poison"))
	assert_true(BattleCmds.move_status_ok(b, { "monster_only": true }, "poison"))
	assert_true(BattleCmds.move_status_ok(b, {}, "inner_wound"), "其他狀態由 status_effects.since 控制")
	# 流血：玩家武功招式附帶流血是自創觸發 → 2001 規則不施加（M3a 審查 #4）；後期規則照常；怪物專用不受影響
	assert_false(BattleCmds.move_status_ok(b, { "monster_only": false }, "bleed"), "classic_strict：血刀刀法第 3 招不附帶流血")
	assert_true(BattleCmds.move_status_ok(b, { "monster_only": true }, "bleed"))
	var later := make_battle([player_spec(), monster("m_dummy")], 1, { "later_battle_cmds": true })
	assert_true(BattleCmds.move_status_ok(later, { "monster_only": false }, "bleed"))

# ---------------------------------------------------------------- B3：招式選擇

func test_cmd_move_highest_unlocked() -> void:
	var arow := { "id": "t_x", "moves": [_move("m1", 1, 20, 1, 4), _move("m2", 60, 32, 2, 10)] }
	var u := BattleUnit.new(1, player_spec({ "skills": { "t_x": 59 } }))
	assert_eq(str(BattleCmds.cmd_move(u, arow).id), "m1", "59 級：第二招還沒解鎖")
	u = BattleUnit.new(1, player_spec({ "skills": { "t_x": 60 } }))
	assert_eq(str(BattleCmds.cmd_move(u, arow).id), "m2", "60 級：用第二招")
	assert_eq(BattleCmds.cmd_move(u, {}), {})

func test_poison_second_move_range() -> void:
	var t := _tables_with({ "t_poison": { "id": "t_poison", "name": "測試放毒法", "sect_id": "xingxiu", "category": "POISON",
		"base_skill": "basic_poison", "difficulty": 1.0, "poison": { "status": "poison", "level_bonus": 0 },
		"moves": [_move("p1", 1, 20, 1, 4), _move("p2", 60, 32, 2, 10)] } })
	var spec := player_spec({ "neili": 50, "neili_max": 50, "skills": { "t_poison": 30, "basic_poison": 20 },
		"cmd_arts": _cmd_arts({ "POISON": ["t_poison"] }) })
	var b := _make([spec, monster("m_dummy")], t, 3)
	place(b, 1, 1, 3)
	place(b, 2, 3, 3)
	assert_eq(do_cmd(b, 1, { "cmd": "POISON", "art": "t_poison", "target": [3, 3] }, t).err, "out_of_range", "30 級：射程 1")
	spec["skills"]["t_poison"] = 60
	b = _make([spec, monster("m_dummy")], t, 3)
	place(b, 1, 1, 3)
	place(b, 2, 3, 3)
	var r := do_cmd(b, 1, { "cmd": "POISON", "art": "t_poison", "target": [3, 3] }, t)
	assert_eq(r.err, "", "60 級：第二招射程 2")
	assert_eq(b.unit(1).neili, 40, "扣第二招的內力 10")

# ---------------------------------------------------------------- B3：暗器武功

func _thrower_t(status_chance: float) -> Dictionary:
	return _tables_with({ "t_hidden": { "id": "t_hidden", "name": "測試暗器", "sect_id": "", "category": "HIDDEN",
		"base_skill": "basic_hidden", "difficulty": 1.0, "hidden": { "range_bonus": 0 },
		"moves": [_move("h1", 1, 10, 3, 4, "poison", status_chance)] } })

func _thrower_spec(neili: int) -> Dictionary:
	return player_spec({ "neili": neili, "neili_max": 50, "skills": { "basic_hidden": 40, "t_hidden": 10 },
		"cmd_arts": _cmd_arts({ "HIDDEN": ["t_hidden"] }),
		"hidden_items": [ { "uid": "it_h1", "item_id": "h_jinqianbiao", "name": "金錢鏢", "n": 5, "dmg": 8 } ] })

func test_hidden_art_costs_inner() -> void:
	var t := _thrower_t(0.0)
	var b := _make([_thrower_spec(3), monster("m_dummy")], t, 5)
	place(b, 2, 3, 3)
	assert_eq(do_cmd(b, 1, { "cmd": "HIDDEN", "art": "t_hidden", "item_uid": "it_h1", "target": [3, 3] }, t).err,
		"not_enough_neili", "飛星術招式要 4 內力")
	assert_eq(do_cmd(b, 1, { "cmd": "HIDDEN", "item_uid": "it_h1", "target": [3, 3] }, t).err, "", "不用暗器武功就不扣內力")
	assert_eq(b.unit(1).neili, 3)
	b.unit(1).neili = 10
	assert_eq(do_cmd(b, 1, { "cmd": "HIDDEN", "art": "t_hidden", "item_uid": "it_h1", "target": [3, 3] }, t).err, "")
	assert_eq(b.unit(1).neili, 6, "命中與否都扣招式內力 4")

func _hidden_poisons(later: bool) -> Variant:
	var t := _thrower_t(1.0)
	for sd in range(1, 60):
		var b := _make([_thrower_spec(50), monster("m_dummy")], t, sd, { "later_battle_cmds": later })
		place(b, 2, 3, 3)
		var r := do_cmd(b, 1, { "cmd": "HIDDEN", "art": "t_hidden", "item_uid": "it_h1", "target": [3, 3] }, t)
		assert_eq(r.err, "")
		if find(r.events, "battle_hidden_hit").is_empty() or not b.unit(2).is_active():
			continue
		return b.unit(2).statuses.has("poison")
	fail("59 個種子都沒命中")
	return null

func test_hidden_art_move_status() -> void:
	assert_eq(_hidden_poisons(true), true, "後期版：飛星術命中附帶中毒")
	assert_eq(_hidden_poisons(false), false, "2001：暗器武功的中毒也照 news 316 不施加")

# ---------------------------------------------------------------- B2、B5：醫

func _medic_t(bleed_cure: Array) -> Dictionary:
	return _tables_with({ "t_medic": { "id": "t_medic", "name": "測試醫術", "sect_id": "hengshan", "category": "MEDIC",
		"base_skill": "basic_medic", "difficulty": 1.0, "medic": { "heal_mult": 1.0 },
		"moves": [_move("md1", 1, 0, 2, 5)] } }, { "bleed": { "cure_by": bleed_cure } })

func test_medic_cures_bleed_by_cure_by() -> void:
	for later in [true, false]:
		var t := _medic_t(["MEDIC", "AUTO"])
		var med := player_spec({ "neili": 20, "neili_max": 20, "skills": { "basic_medic": 20, "t_medic": 10 },
			"cmd_arts": _cmd_arts({ "MEDIC": ["t_medic"] }) })
		var b := _make([med, ally_spec(2), monster("m_dummy")], t, 7, { "later_battle_cmds": later })
		place(b, 1, 1, 3)
		place(b, 2, 1, 4)
		assert_eq(do_cmd(b, 1, { "cmd": "MEDIC", "art": "t_medic", "target": [1, 4] }, t).err, "nothing_to_heal",
			"氣全滿、沒有傷 → 不接受（以前照扣精神）")
		assert_eq([b.unit(1).jing, b.unit(1).shen, b.unit(1).neili], [92, 88, 20], "沒有扣任何東西")
		BattleStatus.apply(b, b.unit(2), "bleed", t)
		assert_true(b.unit(2).statuses.has("bleed"))
		var r := do_cmd(b, 1, { "cmd": "MEDIC", "art": "t_medic", "target": [1, 4] }, t)
		assert_eq(r.err, "", "氣全滿但在流血 → 可以醫")
		assert_eq(find(r.events, "battle_medic")[0].p.cured, true)
		assert_eq(find(r.events, "battle_status_off").size(), 1)
		assert_false(b.unit(2).statuses.has("bleed"), "醫止住流血（cure_by MEDIC；later=%s）" % str(later))
		assert_eq(b.unit(1).neili, 15, "醫術武功的招式內力 5")
	# cure_by 沒有 MEDIC → 醫不了
	var t2 := _medic_t(["AUTO"])
	var b2 := _make([player_spec({ "skills": { "basic_medic": 20 } }), ally_spec(2, { "qi": 50 }), monster("m_dummy")], t2, 7)
	place(b2, 1, 1, 3)
	place(b2, 2, 1, 4)
	BattleStatus.apply(b2, b2.unit(2), "bleed", t2)
	var r2 := do_cmd(b2, 1, { "cmd": "MEDIC", "target": [1, 4] }, t2)
	assert_eq(r2.err, "")
	assert_true(b2.unit(2).statuses.has("bleed"))
	assert_eq(find(r2.events, "battle_medic")[0].p.cured, false)

func test_medic_art_not_enough_neili() -> void:
	var t := _medic_t(["MEDIC", "AUTO"])
	var med := player_spec({ "neili": 4, "neili_max": 20, "skills": { "basic_medic": 20, "t_medic": 10 },
		"cmd_arts": _cmd_arts({ "MEDIC": ["t_medic"] }) })
	var b := _make([med, ally_spec(2, { "qi": 50 }), monster("m_dummy")], t, 7)
	place(b, 1, 1, 3)
	place(b, 2, 1, 4)
	assert_eq(do_cmd(b, 1, { "cmd": "MEDIC", "art": "t_medic", "target": [1, 4] }, t).err, "not_enough_neili")

func test_inner_heal_rejected_at_full_qi() -> void:
	var spec := player_spec({ "neili": 200, "neili_max": 200, "skills": { "t_inner": 50, "basic_inner": 40 },
		"cmd_arts": _cmd_arts({ "INNER": ["t_inner"] }) })
	var b := make_battle([spec, monster("m_dummy")], 3)
	assert_eq(b.unit(1).qi, b.unit(1).qi_max())
	assert_eq(do_cmd(b, 1, { "cmd": "INNER", "mode": "HEAL" }).err, "full_qi", "氣全滿不能運功療傷")
	assert_eq(b.unit(1).neili, 200, "沒有扣內力")
	b.unit(1).qi -= 1
	assert_eq(do_cmd(b, 1, { "cmd": "INNER", "mode": "HEAL" }).err, "")

# ---------------------------------------------------------------- B1：治好的才記下來

func test_cure_marks_cured_statuses_only() -> void:
	var b := make_battle([player_spec({ "statuses": { "poison": { "n": 1, "level": 3 } } }), monster("m_dummy")], 3)
	var u := b.unit(1)
	assert_eq(u.start_statuses, { "poison": 3 })
	# 行動次數用完（_status_tick 移除）不算治好
	u.statuses["poison"] = 1
	BattleRules._status_tick(b, u, tables())
	assert_false(u.statuses.has("poison"))
	assert_eq(u.cured_statuses, {}, "次數用完不是治好")
	assert_false(b.outcome().units[1].cured_statuses.has("poison"))
	# 解藥／醫／逼毒（BattleStatus.remove）才算
	BattleStatus.apply(b, u, "poison", tables(), 2, false)
	BattleStatus.remove(b, u, "poison", tables())
	assert_eq(b.outcome().units[1].cured_statuses, { "poison": true })
