extends "res://tests/unit/test_battle_helpers.gd"
## M3A_PLAN 5.1–5.4、10.1：毒、醫、暗、陣（另見 test_battle_formation）、內、穴、用藥的驗證原因碼、成功路徑、消耗。

func _cmd_arts(over: Dictionary) -> Dictionary:
	var d := { "POISON": [], "MEDIC": [], "HIDDEN": [], "FORMATION": [], "INNER": [], "ACUPOINT": [] }
	d.merge(over, true)
	return d

## 玩家（uid 1，(1,3)）對木人（uid 2）；木人放到 (x, y)
func _b(pover: Dictionary, mx := 2, my := 3, opts := {}) -> Battle:
	var b := make_battle([player_spec(pover), monster("m_dummy")], 4242, opts)
	place(b, 1, 1, 3)
	place(b, 2, mx, my)
	return b

func _poisoner(over: Dictionary = {}) -> Dictionary:
	var p := { "neili": 50, "neili_max": 50, "sect": "xingxiu",
		"skills": { "t_poison": 30, "basic_poison": 20 }, "cmd_arts": _cmd_arts({ "POISON": ["t_poison"] }) }
	p.merge(over, true)
	return p

func test_cmds_constant_matches_plan() -> void:
	assert_eq(BattleRules.CMDS, ["MOVE", "ATTACK", "ART", "DEFEND", "REST", "EQUIP", "FLEE",
		"POISON", "MEDIC", "HIDDEN", "FORMATION", "INNER", "ACUPOINT", "ITEM",
		"DODGE", "QING"])   # M3d（M3D_PLAN §3.1、§3.2）
	var n := BattleRules.normalize_cmd({ "cmd": "INNER", "mode": "HEAL" })
	assert_eq(n.mode, "HEAL")

## ---------------------------------------------------------------- 毒

func test_poison_reasons() -> void:
	var b := _b({ "neili": 50, "neili_max": 50 })
	assert_eq(do_cmd(b, 1, { "cmd": "POISON", "art": "t_poison", "target": [2, 3] }).err, "cmd_disabled", "沒有毒術")
	b = _b(_poisoner({ "skills": { "t_poison": 0 } }))
	assert_eq(do_cmd(b, 1, { "cmd": "POISON", "art": "t_poison", "target": [2, 3] }).err, "no_poison_art", "等級 0")
	b = _b(_poisoner())
	assert_eq(do_cmd(b, 1, { "cmd": "POISON", "art": "sl_changquan", "target": [2, 3] }).err, "no_poison_art")
	assert_eq(do_cmd(b, 1, { "cmd": "POISON", "art": "t_poison", "target": [5, 5] }).err, "no_target")
	assert_eq(do_cmd(b, 1, { "cmd": "POISON", "art": "t_poison", "target": [1, 3] }).err, "no_target", "自己")
	place(b, 2, 4, 3)
	assert_eq(do_cmd(b, 1, { "cmd": "POISON", "art": "t_poison", "target": [4, 3] }).err, "out_of_range", "射程 2")
	place(b, 2, 3, 3)
	b.unit(1).neili = 4
	assert_eq(do_cmd(b, 1, { "cmd": "POISON", "art": "t_poison", "target": [3, 3] }).err, "not_enough_neili")
	b.unit(1).neili = 5
	assert_eq(do_cmd(b, 1, { "cmd": "POISON", "art": "t_poison", "target": [3, 3] }).err, "")
	assert_eq(b.unit(1).neili, 0, "扣 moves[0].cost_inner")

func test_poison_success_and_fail_paths() -> void:
	var oks := 0
	var fails := 0
	for sd in range(1, 60):
		var b := make_battle([player_spec(_poisoner()), monster("m_dummy")], sd)
		place(b, 2, 2, 3)
		var r := do_cmd(b, 1, { "cmd": "POISON", "art": "t_poison", "target": [2, 3] })
		assert_eq(r.err, "")
		var ok := find(r.events, "battle_poison_ok")
		var fl := find(r.events, "battle_poison_fail")
		assert_eq(ok.size() + fl.size(), 1, "成功或失敗擇一")
		if ok.size() == 1:
			oks += 1
			# dmg = round(20 × 0.5 × (1 + 30/60)) = 15；L = clamp(1 + floor((20 + 30)/25), 1, 10) = 3
			assert_eq(ok[0].p.dmg, 15)
			assert_eq(ok[0].p.level, 3)
			assert_eq(b.unit(2).qi, 100000 - 15)
			assert_eq(b.unit(2).status_level("poison"), 3)
			assert_eq(int(b.unit(2).statuses.poison), 6, "定力 1：不縮短")
			assert_eq(find(r.events, "battle_status_on")[0].p.level, 3)
		else:
			fails += 1
			assert_false(b.unit(2).statuses.has("poison"))
		assert_eq(b.unit(1).neili, 45)
	assert_true(oks > 0 and fails > 0, "p = 0.40 + (50 − 2) × 0.005 = 0.64：兩種都會出現 (%d/%d)" % [oks, fails])

func test_poison_non_sect_halved() -> void:
	var member := 0
	var outsider := 0
	for sd in range(1, 301):
		for who in ["xingxiu", "huashan"]:
			var b := make_battle([player_spec(_poisoner({ "sect": who, "skills": { "t_poison": 30, "basic_poison": 300 } })),
				monster("m_dummy")], sd)
			place(b, 2, 2, 3)
			var r := do_cmd(b, 1, { "cmd": "POISON", "art": "t_poison", "target": [2, 3] })
			if not find(r.events, "battle_poison_ok").is_empty():
				if who == "xingxiu":
					member += 1
				else:
					outsider += 1
	# 本派 0.90、非本派 0.45
	assert_true(member > 240, "本派成功 %d/300" % member)
	assert_true(outsider < 180 and outsider > 90, "非本派成功 %d/300" % outsider)

func test_poison_tick_each_action() -> void:
	var b := _b({})
	BattleStatus.apply(b, b.unit(2), "poison", tables(), 5)
	var u := b.unit(2)
	var qi0 := u.qi
	var r := do_cmd(b, 2, { "cmd": "DEFEND" })
	var t := find(r.events, "battle_poison_tick")
	assert_eq(t.size(), 1)
	# 2% + 0.4% × 5 = 4% × 100000 = 4000
	assert_eq(t[0].p.dmg, 4000)
	assert_eq(u.qi, qi0 - 4000)
	assert_eq(int(u.statuses.poison), 5)

## ---------------------------------------------------------------- 醫

func test_medic_reasons_and_heal() -> void:
	var b := _b({ "qi": 50 })
	assert_eq(do_cmd(b, 1, { "cmd": "MEDIC", "target": [1, 3] }).err, "no_medic")
	b = _b({ "qi": 50, "skills": { "basic_medic": 10 } })
	assert_eq(do_cmd(b, 1, { "cmd": "MEDIC", "target": [2, 3] }).err, "not_ally", "敵人")
	assert_eq(do_cmd(b, 1, { "cmd": "MEDIC", "target": [6, 6] }).err, "not_ally", "空格")
	assert_eq(do_cmd(b, 1, { "cmd": "MEDIC", "art": "t_medic", "target": [1, 3] }).err, "no_medic", "不會這套醫術")
	b.unit(1).jing = 9
	assert_eq(do_cmd(b, 1, { "cmd": "MEDIC", "target": [1, 3] }).err, "not_enough_jing")
	b.unit(1).jing = 92
	b.unit(1).shen = 4
	assert_eq(do_cmd(b, 1, { "cmd": "MEDIC", "target": [1, 3] }).err, "not_enough_shen")
	b.unit(1).shen = 88
	var r := do_cmd(b, 1, { "cmd": "MEDIC", "target": [1, 3] })
	assert_eq(r.err, "")
	var m := find(r.events, "battle_medic")
	assert_eq(m.size(), 1)
	assert_eq(m[0].p.heal, 40, "20 + 2 × 10")
	assert_eq(b.unit(1).qi, 90)
	assert_eq(b.unit(1).jing, 82, "精 −10")
	assert_eq(b.unit(1).shen, 83, "神 −5")

func test_medic_ally_range_hengshan_and_cure() -> void:
	var med := { "sect": "hengshan", "skills": { "basic_medic": 20, "t_medic": 10 },
		"cmd_arts": _cmd_arts({ "MEDIC": ["t_medic"] }) }
	var b := make_battle([player_spec(med), ally_spec(2, { "qi": 10 }), monster("m_dummy")], 7)
	place(b, 1, 1, 3)
	place(b, 2, 1, 6)
	assert_eq(do_cmd(b, 1, { "cmd": "MEDIC", "target": [1, 6] }).err, "out_of_range", "沒指定醫術：射程 1")
	assert_eq(do_cmd(b, 1, { "cmd": "MEDIC", "art": "t_medic", "target": [1, 6] }).err, "out_of_range", "醫術射程 2")
	place(b, 2, 1, 5)
	BattleStatus.apply(b, b.unit(2), "poison", tables(), 5)
	var r := do_cmd(b, 1, { "cmd": "MEDIC", "art": "t_medic", "target": [1, 5] })
	assert_eq(r.err, "")
	var m: Dictionary = find(r.events, "battle_medic")[0]
	# (20 + 40 + 30) × 1.3 = 117
	assert_eq(m.p.heal, 117)
	assert_eq(m.p.cured, false, "20 + 10 < 10 × 5")
	BattleStatus.apply(b, b.unit(2), "poison", tables(), 3)   # LEVEL_MAX：仍是 5
	assert_eq(b.unit(2).status_level("poison"), 5)
	b.unit(2).status_levels["poison"] = 3
	r = do_cmd(b, 1, { "cmd": "MEDIC", "art": "t_medic", "target": [1, 5] })
	assert_eq(find(r.events, "battle_medic")[0].p.cured, true, "30 ≥ 10 × 3")
	assert_false(b.unit(2).statuses.has("poison"))
	# later_battle_cmds 關：醫不解毒
	b.opts["later_battle_cmds"] = false
	BattleStatus.apply(b, b.unit(2), "poison", tables(), 1)
	# 氣全滿、身上只有醫不好的毒 → 主機不接受（M3a 審查 B5）
	assert_eq(b.unit(2).qi, b.unit(2).qi_max())
	assert_eq(do_cmd(b, 1, { "cmd": "MEDIC", "art": "t_medic", "target": [1, 5] }).err, "nothing_to_heal")
	b.unit(2).qi = 10
	r = do_cmd(b, 1, { "cmd": "MEDIC", "art": "t_medic", "target": [1, 5] })
	assert_eq(find(r.events, "battle_medic")[0].p.cured, false)
	assert_true(b.unit(2).statuses.has("poison"))

## ---------------------------------------------------------------- 暗

func _thrower(over: Dictionary = {}) -> Dictionary:
	var p := { "skills": { "basic_hidden": 40 },
		"hidden_items": [ { "uid": "it_h1", "item_id": "h_jinqianbiao", "name": "金錢鏢", "n": 2, "dmg": 8 } ] }
	p.merge(over, true)
	return p

func test_hidden_reasons_range_and_ammo() -> void:
	var b := _b({ "skills": { "basic_hidden": 40 } })
	assert_eq(do_cmd(b, 1, { "cmd": "HIDDEN", "item_uid": "it_h1", "target": [2, 3] }).err, "no_hidden", "沒有暗器")
	b = _b(_thrower({ "skills": {} }))
	assert_eq(do_cmd(b, 1, { "cmd": "HIDDEN", "item_uid": "it_h1", "target": [2, 3] }).err, "no_hidden", "不會暗器功夫")
	b = _b(_thrower(), 5, 3)
	assert_eq(do_cmd(b, 1, { "cmd": "HIDDEN", "item_uid": "it_x", "target": [5, 3] }).err, "no_ammo")
	assert_eq(do_cmd(b, 1, { "cmd": "HIDDEN", "item_uid": "it_h1", "target": [4, 3] }).err, "no_target")
	assert_eq(BattleCmds.hidden_range(b.unit(1), "", tables()), 4, "3 + 40/40")
	assert_eq(do_cmd(b, 1, { "cmd": "HIDDEN", "item_uid": "it_h1", "target": [5, 3] }).err, "", "距離 4")
	assert_eq(b.unit(1).used_items, { "it_h1": 1 })
	var ev: Array = do_cmd(b, 1, { "cmd": "HIDDEN", "item_uid": "it_h1", "target": [5, 3] }).events
	assert_eq(find(ev, "battle_hidden_hit").size() + find(ev, "battle_hidden_miss").size(), 1)
	var e: Dictionary = (find(ev, "battle_hidden_hit") + find(ev, "battle_hidden_miss"))[0]
	assert_eq(e.p.item_name, "金錢鏢")
	assert_eq(e.p.left, 0, "數量遞減")
	assert_eq(do_cmd(b, 1, { "cmd": "HIDDEN", "item_uid": "it_h1", "target": [5, 3] }).err, "no_ammo", "用完")
	assert_eq(b.outcome().units[1].used_items, { "it_h1": 2 }, "戰後扣背包用")
	place(b, 2, 8, 3)
	b.unit(1).used_items = {}
	assert_eq(do_cmd(b, 1, { "cmd": "HIDDEN", "item_uid": "it_h1", "target": [8, 3] }).err, "out_of_range")
	var b2 := _b(_thrower({ "skills": { "basic_hidden": 400, "t_hidden": 5 }, "cmd_arts": _cmd_arts({ "HIDDEN": ["t_hidden"] }) }))
	assert_eq(BattleCmds.hidden_range(b2.unit(1), "t_hidden", tables()), 6, "最多 6")

func test_hidden_damage_formula() -> void:
	for sd in range(1, 40):
		var b := make_battle([player_spec(_thrower()), monster("m_dummy")], sd)
		place(b, 2, 3, 3)
		var ev: Array = do_cmd(b, 1, { "cmd": "HIDDEN", "item_uid": "it_h1", "target": [3, 3] }).events
		var hit := find(ev, "battle_hidden_hit")
		if hit.is_empty():
			continue
		# 8 × (1 + 40/50) = 14.4；木人防禦 = 根骨 1 × 1.2 = 1.2 → −0.36；浮動 0.706–1.1
		var dmg := int(hit[0].p.dmg)
		assert_true(dmg >= 10 and dmg <= 16, "傷害 %d" % dmg)
		assert_true(BattleRules.PARTS.has(hit[0].p.part))
		return
	fail("39 個種子都沒命中")

## ---------------------------------------------------------------- 內

func _inner(over: Dictionary = {}) -> Dictionary:
	var p := { "qi": 100, "neili": 200, "neili_max": 200, "skills": { "t_inner": 50, "basic_inner": 40 },
		"cmd_arts": _cmd_arts({ "INNER": ["t_inner"] }) }
	p.merge(over, true)
	return p

func test_inner_reasons() -> void:
	var b := _b({ "neili": 100 })
	assert_eq(do_cmd(b, 1, { "cmd": "INNER", "mode": "HEAL" }).err, "no_inner_art")
	b = _b(_inner(), 2, 3, { "later_battle_cmds": false })
	assert_eq(do_cmd(b, 1, { "cmd": "INNER", "mode": "HEAL" }).err, "cmd_disabled", "classic_strict")
	b = _b(_inner())
	assert_eq(do_cmd(b, 1, { "cmd": "INNER", "mode": "FLY" }).err, "bad_cmd")
	assert_eq(do_cmd(b, 1, { "cmd": "INNER" }).err, "bad_cmd", "缺 mode")
	assert_eq(do_cmd(b, 1, { "cmd": "INNER", "mode": "EXPEL" }).err, "nothing_to_expel")
	assert_eq(do_cmd(b, 1, { "cmd": "INNER", "mode": "UNSEAL" }).err, "not_sealed")
	assert_eq(do_cmd(b, 1, { "cmd": "INNER", "mode": "TRANSFER", "target": [1, 3] }).err, "not_ally", "自己")
	assert_eq(do_cmd(b, 1, { "cmd": "INNER", "mode": "TRANSFER", "target": [2, 3] }).err, "not_ally", "敵人")
	b.unit(1).neili = 19
	assert_eq(do_cmd(b, 1, { "cmd": "INNER", "mode": "HEAL" }).err, "not_enough_neili", "10% × 200 = 20")

func test_inner_heal_expel_unseal_transfer() -> void:
	var b := make_battle([player_spec(_inner({ "sect": "quanzhen" })), ally_spec(2, { "neili": 10, "neili_max": 100 }),
		monster("m_dummy")], 99)
	place(b, 1, 1, 3)
	place(b, 2, 1, 4)
	var r := do_cmd(b, 1, { "cmd": "INNER", "mode": "HEAL" })
	var h: Dictionary = find(r.events, "battle_inner_heal")[0]
	# n = 20；I = 50 + 40/2 = 70；20 × 1.7 × 1.3 = 44.2 → 44
	assert_eq(h.p.heal, 44)
	assert_eq(h.p.neili, 180)
	assert_eq(b.unit(1).qi, 144)
	# 逼毒：−(1 + floor(70/25)) = −3
	BattleStatus.apply(b, b.unit(1), "poison", tables(), 5)
	r = do_cmd(b, 1, { "cmd": "INNER", "mode": "EXPEL" })
	assert_eq(find(r.events, "battle_inner_expel")[0].p.level_left, 2)
	assert_eq(b.unit(1).status_level("poison"), 2)
	assert_eq(b.unit(1).neili, 160)
	r = do_cmd(b, 1, { "cmd": "INNER", "mode": "EXPEL" })
	assert_eq(find(r.events, "battle_inner_expel")[0].p.level_left, 0)
	assert_false(b.unit(1).statuses.has("poison"), "到 0 解除")
	assert_eq(find(r.events, "battle_status_off").size(), 1)
	# 衝穴
	var oks := 0
	for i in 20:
		BattleStatus.apply(b, b.unit(1), "acupoint", tables())
		b.unit(1).neili = 100
		r = do_cmd(b, 1, { "cmd": "INNER", "mode": "UNSEAL" })
		assert_eq(b.unit(1).neili, 85, "扣 15")
		if not find(r.events, "battle_inner_unseal_ok").is_empty():
			oks += 1
			assert_false(b.unit(1).statuses.has("acupoint"))
		else:
			assert_eq(find(r.events, "battle_inner_unseal_fail").size(), 1)
	assert_true(oks >= 8, "0.30 + 0.35 − 0.01 ≈ 0.64：%d/20" % oks)
	# 傳力：min(100 × 0.5, 90) = 50
	b.unit(1).neili = 100
	r = do_cmd(b, 1, { "cmd": "INNER", "mode": "TRANSFER", "target": [1, 4] })
	assert_eq(find(r.events, "battle_inner_transfer")[0].p.n, 50)
	assert_eq(b.unit(2).neili, 60)
	assert_eq(b.unit(1).neili, 50)
	place(b, 2, 1, 6)
	assert_eq(do_cmd(b, 1, { "cmd": "INNER", "mode": "TRANSFER", "target": [1, 6] }).err, "out_of_range")

## ---------------------------------------------------------------- 穴

func test_acupoint_reasons_and_paths() -> void:
	var b := _b({ "neili": 50 })
	assert_eq(do_cmd(b, 1, { "cmd": "ACUPOINT", "target": [2, 3] }).err, "no_acupoint")
	b = _b({ "neili": 50, "skills": { "basic_stab": 10 } }, 2, 3, { "later_battle_cmds": false })
	assert_eq(do_cmd(b, 1, { "cmd": "ACUPOINT", "target": [2, 3] }).err, "cmd_disabled")
	b = _b({ "neili": 50, "skills": { "basic_stab": 10 } }, 3, 3)
	assert_eq(do_cmd(b, 1, { "cmd": "ACUPOINT", "target": [4, 4] }).err, "no_target")
	assert_eq(do_cmd(b, 1, { "cmd": "ACUPOINT", "target": [3, 3] }).err, "out_of_range")
	assert_eq(do_cmd(b, 1, { "cmd": "ACUPOINT", "art": "t_stab", "target": [3, 3] }).err, "no_acupoint", "不會此武功")
	place(b, 2, 2, 3)
	b.unit(1).neili = 14
	assert_eq(do_cmd(b, 1, { "cmd": "ACUPOINT", "target": [2, 3] }).err, "not_enough_neili")
	var oks := 0
	for i in 30:
		b.unit(1).neili = 15
		b.unit(2).statuses.erase("acupoint")
		var r := do_cmd(b, 1, { "cmd": "ACUPOINT", "target": [2, 3] })
		assert_eq(b.unit(1).neili, 0)
		if not find(r.events, "battle_acupoint_ok").is_empty():
			oks += 1
			assert_true(b.unit(2).statuses.has("acupoint"))
		else:
			assert_eq(find(r.events, "battle_acupoint_fail").size(), 1)
	assert_true(oks > 3 and oks < 25, "0.30 + 10 × 0.004 = 0.34：%d/30" % oks)
	# 封穴：不能移動、不能逃；時間棒 × 0.6
	b.unit(2).statuses["acupoint"] = 3
	var u2 := b.unit(2)
	assert_eq(do_cmd(b, 2, { "cmd": "MOVE", "target": [3, 3] }).err, "status_blocked")
	assert_eq(do_cmd(b, 2, { "cmd": "FLEE" }).err, "status_blocked")
	var g_sealed := BattleFormulas.atb_gain(u2, tables())
	u2.statuses.erase("acupoint")
	assert_true(approx(g_sealed, BattleFormulas.atb_gain(u2, tables()) * 0.6))

## ---------------------------------------------------------------- 用藥

func test_item_reasons_restore_and_cure() -> void:
	var items := [ { "uid": "it_c1", "item_id": "c_jieduyao", "name": "解毒藥", "n": 1,
			"effects": [ { "type": "cure", "status": "poison", "max_level": 5 } ] },
		{ "uid": "it_q1", "item_id": "c_jinchuang", "name": "金創藥", "n": 3,
			"effects": [ { "type": "restore", "stat": "qi", "value": 100 }, { "type": "restore", "stat": "food", "value": 9 } ] } ]
	var b := make_battle([player_spec({ "qi": 50, "battle_items": items }), ally_spec(2, { "qi": 20 }), monster("m_dummy")], 3)
	place(b, 1, 1, 3)
	place(b, 2, 1, 5)
	place(b, 3, 2, 3)
	assert_eq(do_cmd(b, 1, { "cmd": "ITEM", "item_uid": "it_zz", "target": [1, 3] }).err, "no_item")
	assert_eq(do_cmd(b, 1, { "cmd": "ITEM", "item_uid": "it_q1", "target": [2, 3] }).err, "not_ally")
	assert_eq(do_cmd(b, 1, { "cmd": "ITEM", "item_uid": "it_q1", "target": [1, 5] }).err, "out_of_range")
	var r := do_cmd(b, 1, { "cmd": "ITEM", "item_uid": "it_q1", "target": [1, 3] })
	assert_eq(r.err, "")
	assert_eq(find(r.events, "battle_item_use")[0].p.item_name, "金創藥")
	assert_eq(b.unit(1).qi, 150, "回氣；food 忽略")
	BattleStatus.apply(b, b.unit(1), "poison", tables(), 6)
	r = do_cmd(b, 1, { "cmd": "ITEM", "item_uid": "it_c1", "target": [1, 3] })
	assert_true(b.unit(1).statuses.has("poison"), "等級 6 > 5 解不了")
	assert_eq(do_cmd(b, 1, { "cmd": "ITEM", "item_uid": "it_c1", "target": [1, 3] }).err, "no_item", "用完")
	b.unit(1).used_items.erase("it_c1")
	b.unit(1).status_levels["poison"] = 4
	r = do_cmd(b, 1, { "cmd": "ITEM", "item_uid": "it_c1", "target": [1, 3] })
	assert_false(b.unit(1).statuses.has("poison"), "ITEM 解毒")
	assert_eq(find(r.events, "battle_status_off").size(), 1)
	assert_eq(b.outcome().units[1].used_items, { "it_q1": 1, "it_c1": 1 })

## ---------------------------------------------------------------- 開放條件快照、怪物用毒、no_flee

func test_snapshot_cmd_avail() -> void:
	var b := _b(_inner({ "skills": { "t_inner": 50, "basic_inner": 40, "basic_medic": 1, "basic_hidden": 1 },
		"hidden_items": [ { "uid": "it_h1", "item_id": "h_dangong", "name": "彈弓", "n": 3, "dmg": 2 } ] }))
	var d := b.unit_snapshot(b.unit(1), tables())
	assert_eq(d.cmd_avail.MEDIC, true)
	assert_eq(d.cmd_avail.HIDDEN, true)
	assert_eq(d.cmd_avail.POISON, false)
	assert_eq(d.cmd_avail.INNER, ["HEAL", "EXPEL", "UNSEAL", "TRANSFER"])
	assert_eq(d.cmd_avail.ACUPOINT, false)
	assert_eq(d.cmd_arts.INNER[0].id, "t_inner")
	assert_eq(d.hidden_items[0].n, 3)
	assert_eq(d.formation, null)
	assert_has(d, "statuses")
	b.opts["later_battle_cmds"] = false
	assert_eq(b.unit_snapshot(b.unit(1), tables()).cmd_avail.INNER, [])
	var mon := b.unit_snapshot(b.unit(2), tables())
	assert_has(mon, "statuses")
	assert_false(mon.has("cmd_avail"), "敵方不帶指令欄位")

func test_monster_spec_cmd_arts_and_ai_poison() -> void:
	var spec := monster("m_poisoner")
	assert_eq(spec.cmd_arts.POISON, ["t_poison"])
	assert_eq(spec.cmd_arts.INNER, ["t_inner"])
	assert_eq(spec.sect, "xingxiu")
	assert_eq(spec.hidden_items, [])
	assert_eq(spec.statuses, {})
	var used := 0
	for sd in range(1, 60):
		var b := make_battle([player_spec(), monster("m_poisoner")], sd)
		place(b, 2, 3, 3)
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		var c := BattleAI.choose(b, b.unit(2), tables(), rng)
		if c.cmd == "POISON":
			used += 1
			assert_eq(c.art, "t_poison")
			assert_eq(c.target, [1, 3])
	assert_true(used > 5 and used < 35, "30%%：%d/59" % used)

func test_no_flee_option() -> void:
	var b := _b({}, 2, 3, { "no_flee": true })
	b.unit(1).pos = b.grid.escape[0]
	assert_eq(do_cmd(b, 1, { "cmd": "FLEE" }).err, "no_flee")
