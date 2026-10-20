extends "res://tests/unit/test_battle_helpers.gd"
## M3A_PLAN 5.7、10.1：每個狀態的效果、定力縮短、LEVEL_MAX 疊加、RESIST 抵抗、開戰帶入狀態、快照 statuses。

func _b(pover: Dictionary = {}, mover: Dictionary = {}, seed_v := 77) -> Battle:
	var b := make_battle([player_spec(pover), monster("m_dummy", mover)], seed_v)
	place(b, 1, 1, 3)
	place(b, 2, 2, 3)
	return b

func test_status_table_rows_loaded() -> void:
	for id in ["inner_wound", "poison", "acupoint", "paralysis", "confusion", "distract", "bleed", "formation"]:
		assert_false(BattleStatus.row(id, tables()).is_empty(), id)
	# 正式資料表（WP-CMD 擁有）：8 列 + 2001 官方狀態 氣血失調／昏迷／走火入魔（news 316；M3a 審查修正）＝ 11 列；M3b 加情花毒 ＝ 12 列、欄位齊全
	var f := FileAccess.open("res://data/status_effects.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	assert_eq(int(d.version), 2)
	assert_eq(d.rows.size(), 12)
	var by := {}
	for r in d.rows:
		by[str(r.id)] = r
		for k in ["id", "name", "kind", "glyph", "color", "duration_actions", "stack", "blocks", "skip_actions",
				"random_action", "atk_mult", "def_mult", "gauge_mult", "qi_pct_per_action", "qi_pct_per_level",
				"qi_pct_per_move", "resist_by", "cure_by", "persists", "persist_tick_real_s", "persist_ticks_per_level",
				"persist_qi_pct", "since", "desc", "era", "src"]:
			assert_has(r, k, str(r.id))
	# news 316（2001-08-09）官方顏色：中毒 綠、氣血失調 藍、昏迷 灰、走火入魔 紫、流血 紅；別的狀態不能撞色
	var official := { "poison": "#3c9a3c", "qixue": "#3a5fc8", "coma": "#7a7a7a", "zouhuo": "#8a4b9c", "bleed": "#c03030" }
	for id in official:
		assert_eq(str(by[id].color), official[id], id)
	for id in by:
		if not official.has(id):
			assert_false(str(by[id].color) in official.values(), "%s 撞到官方狀態色 %s" % [id, by[id].color])
	# 2002-01-25（決戰光明頂）才有的狀態：since gmdk（規則 later_battle_cmds 關時不施加）
	for id in ["inner_wound", "acupoint", "paralysis", "confusion", "distract"]:
		assert_eq(str(by[id].since), "gmdk", id)
		assert_true(str(by[id].src) != "verified", "%s 不能標已證實 1.0A" % id)
	for id in ["poison", "bleed", "qixue", "coma", "zouhuo"]:
		assert_eq(str(by[id].since), "", id)
	# 痲痺：不能移動、時間棒變慢（研究 gaoshou/28），不是跳過行動
	assert_eq(bool(by.paralysis.skip_actions), false)
	assert_true("MOVE" in by.paralysis.blocks)
	assert_true(float(by.paralysis.gauge_mult) < 1.0)
	# 流血：氣上限一直往下掉、敷藥止血；不是每走一步扣氣，數值是設計提案
	assert_eq(float(by.bleed.qi_pct_per_move), 0.0)
	assert_true(float(by.bleed.get("qi_max_pct_per_action", 0.0)) > 0.0)
	assert_eq(str(by.bleed.src), "proposal")
	assert_eq(str(by.formation.era), "1.0B", "陣法 2001-10-05 隨神鵰大俠開放")

func test_inner_wound_tick_and_rest_block() -> void:
	var b := _b({ "qi": 180 })
	BattleStatus.apply(b, b.unit(1), "inner_wound", tables())
	assert_eq(do_cmd(b, 1, { "cmd": "REST" }).err, "status_blocked")
	var r := do_cmd(b, 1, { "cmd": "DEFEND" })
	var t := find(r.events, "battle_wound_tick")
	assert_eq(t.size(), 1)
	assert_eq(t[0].p.dmg, 4, "180 × 2% = 3.6 → 4")
	assert_eq(b.unit(1).qi, 176)

func test_paralysis_skips_action() -> void:
	var b := _b()
	BattleStatus.apply(b, b.unit(1), "paralysis", tables())
	assert_eq(int(b.unit(1).statuses.paralysis), 1)
	var r := do_cmd(b, 1, { "cmd": "ATTACK", "target": [2, 3] })
	assert_eq(r.err, "")
	assert_eq(find(r.events, "battle_status_skip").size(), 1)
	assert_eq(find(r.events, "battle_status_skip")[0].p.status_name, "痲痺")
	assert_eq(find(r.events, "atk_blade").size() + find(r.events, "battle_miss").size(), 0, "跳過，不攻擊")
	assert_false(b.unit(1).statuses.has("paralysis"), "消耗一次")
	assert_eq(b.unit(1).state, BattleUnit.CHARGING)
	assert_true(approx(b.unit(1).gauge, 0.0))

func test_confusion_random_attack() -> void:
	# 混亂的玩家旁邊有隊友與敵人：亂打其中一個（不分敵我）
	var hit_ally := 0
	var hit_enemy := 0
	for sd in range(1, 40):
		var b := make_battle([player_spec(), ally_spec(2), monster("m_dummy")], sd)
		place(b, 1, 1, 3)
		place(b, 2, 1, 4)
		place(b, 3, 2, 3)
		BattleStatus.apply(b, b.unit(1), "confusion", tables())
		var r := do_cmd(b, 1, { "cmd": "DEFEND" })
		assert_eq(find(r.events, "battle_confused").size(), 1)
		assert_eq(find(r.events, "battle_defend").size(), 0, "改成亂打")
		for e in r.events:
			if int(e.p.get("atk_uid", 0)) == 1 and not e.p.get("counter", false):
				if int(e.p.def_uid) == 2:
					hit_ally += 1
				elif int(e.p.def_uid) == 3:
					hit_enemy += 1
	assert_true(hit_ally > 0 and hit_enemy > 0, "敵我都可能被打 %d/%d" % [hit_ally, hit_enemy])
	# 旁邊沒人：防
	var b2 := _b()
	place(b2, 2, 6, 6)
	BattleStatus.apply(b2, b2.unit(1), "confusion", tables())
	var r2 := do_cmd(b2, 1, { "cmd": "ATTACK", "target": [6, 6] })
	assert_eq(r2.err, "out_of_range")
	r2 = do_cmd(b2, 1, { "cmd": "DEFEND" })
	assert_eq(find(r2.events, "battle_confused").size(), 1)
	assert_eq(find(r2.events, "battle_defend").size(), 1)
	assert_true(b2.unit(1).defending)

func test_distract_atk_mult() -> void:
	var b := _b()
	var u := b.unit(1)
	var base := BattleStatus.atk_mult(u, tables())
	BattleStatus.apply(b, u, "distract", tables())
	assert_true(approx(BattleStatus.atk_mult(u, tables()), base * 0.8))
	assert_true(approx(BattleStatus.def_mult(u, tables()), 1.0))

func test_bleed_move_costs_qi() -> void:
	var b := _b({ "qi": 100 })
	BattleStatus.apply(b, b.unit(1), "bleed", tables())
	var r := do_cmd(b, 1, { "cmd": "MOVE", "target": [1, 5] })
	assert_eq(r.err, "")
	var t := find(r.events, "battle_bleed_tick")
	assert_eq(t.size(), 1)
	assert_eq(t[0].p.dmg, 5, "180 × 3% = 5.4 → 5")
	assert_eq(b.unit(1).qi, 95)
	r = do_cmd(b, 1, { "cmd": "DEFEND" })
	assert_eq(find(r.events, "battle_bleed_tick").size(), 0, "不移動不扣")

func test_dingli_shortens_duration() -> void:
	var b := _b({ "attrs": { "cal": 45 } })
	BattleStatus.apply(b, b.unit(1), "poison", tables())
	assert_eq(int(b.unit(1).statuses.poison), 4, "6 − floor((45 − 20) / 10) = 4")
	BattleStatus.apply(b, b.unit(1), "paralysis", tables())
	assert_eq(int(b.unit(1).statuses.paralysis), 1, "最少 1 次")
	assert_eq(BattleStatus.duration_for(b.unit(2), BattleStatus.row("poison", tables())), 6, "定力 1 不縮短")

func test_level_max_stacking_and_refresh() -> void:
	var b := _b()
	var u := b.unit(2)
	BattleStatus.apply(b, u, "poison", tables(), 4)
	u.statuses["poison"] = 2
	var ev := BattleStatus.apply(b, u, "poison", tables(), 2)
	assert_eq(u.status_level("poison"), 4, "取較高等級")
	assert_eq(int(u.statuses.poison), 6, "重設次數")
	assert_eq(ev[0].p.level, 4)
	BattleStatus.apply(b, u, "poison", tables(), 7)
	assert_eq(u.status_level("poison"), 7)
	# REFRESH：沒有等級欄位
	ev = BattleStatus.apply(b, u, "inner_wound", tables())
	assert_false(ev[0].p.has("level"))

func test_resist_blocks_resistable_status() -> void:
	var t := tables().duplicate(true)
	var resisted := 0
	for sd in range(1, 120):
		var b := make_battle([player_spec({ "jing": 90, "neili": 90, "neili_max": 90, "sect": "wudang",
			"sect_skill": { "id": "xiayi", "effect": "RESIST", "level": 100 } }), monster("m_dummy")], sd)
		var u := b.unit(1)
		var ev := BattleStatus.apply(b, u, "poison", t, 2)
		if not find(ev, "battle_proc_RESIST").is_empty():
			resisted += 1
			assert_false(u.statuses.has("poison"))
			assert_eq(u.jing, 87, "精 −3")
			assert_eq(u.neili, 87, "內力 −3")
			assert_eq(find(ev, "battle_proc_RESIST")[0].p.skill_name, "xiayi名")
		else:
			assert_true(u.statuses.has("poison"))
			assert_eq(u.jing, 90)
		# 內傷不在 resist_by：不擲抵抗
		var ev2 := BattleStatus.apply(b, u, "inner_wound", t)
		assert_true(find(ev2, "battle_proc_RESIST").is_empty())
	assert_true(resisted > 10 and resisted < 50, "25%%：%d/119" % resisted)

func test_statuses_from_spec_and_snapshot() -> void:
	var b := _b({ "statuses": { "poison": { "n": 4, "level": 3 } } })
	var u := b.unit(1)
	assert_eq(int(u.statuses.poison), 4)
	assert_eq(u.status_level("poison"), 3)
	var snap := b.snapshot(tables())
	var me: Dictionary = snap.units[0]
	assert_eq(me.statuses.size(), 1)
	var s: Dictionary = me.statuses[0]
	assert_eq(s.id, "poison")
	assert_eq(s.name, "中毒")
	assert_eq(s.glyph, "毒")
	assert_eq(s.color, "#3c9a3c")
	assert_eq(s.n, 4)
	assert_eq(s.level, 3)
	assert_eq(snap.units[1].statuses, [], "敵方也有 statuses 欄位")
	var out := b.outcome()
	assert_eq(out.units[1].statuses, { "poison": 3 })
	assert_eq(out.units[1].start_statuses, { "poison": 3 })

func test_status_off_after_count() -> void:
	var b := _b()
	BattleStatus.apply(b, b.unit(1), "distract", tables())
	for i in 2:
		do_cmd(b, 1, { "cmd": "DEFEND" })
	var r := do_cmd(b, 1, { "cmd": "DEFEND" })
	assert_eq(find(r.events, "battle_status_off").size(), 1)
	assert_false(b.unit(1).statuses.has("distract"))
	assert_false(b.unit(1).status_levels.has("distract"))
