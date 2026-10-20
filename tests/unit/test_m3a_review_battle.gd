extends "res://tests/unit/test_battle_helpers.gd"
## M3a 審查修正（戰鬥部分）的回歸測試：
## - 2002-01-25 才有的機制（門派技能觸發、痲痺／混亂／封穴／內傷／分心）在 later_battle_cmds 關時不發生；
## - 2001 官方狀態 氣血失調／昏迷（吃藥過量）；
## - 流血＝氣上限一直往下掉。

## 夾具表 + 正式 status_effects（11 列）
func _real_tables() -> Dictionary:
	var t := tables().duplicate(true)
	var f := FileAccess.open("res://data/status_effects.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	for r in d.rows:
		t["status_effects"][str(r.id)] = r
	return t

func _b(later: bool, pover: Dictionary = {}, seed_v := 5) -> Battle:
	var b := make_battle([player_spec(pover), monster("m_dummy")], seed_v, { "later_battle_cmds": later })
	place(b, 1, 1, 3)
	place(b, 2, 2, 3)
	return b

func test_2002_statuses_not_applied_when_later_cmds_off() -> void:
	var t := _real_tables()
	for later in [false, true]:
		var b := _b(later)
		var u := b.unit(1)
		for sid in ["paralysis", "confusion", "acupoint", "inner_wound", "distract"]:
			var ev := BattleStatus.apply(b, u, sid, t)
			assert_eq(u.statuses.has(sid), later, "%s later=%s" % [sid, later])
			assert_eq(ev.is_empty(), not later, "%s 事件 later=%s" % [sid, later])
		# 2001 就有的狀態照常
		for sid in ["poison", "bleed", "qixue"]:
			BattleStatus.apply(b, u, sid, t)
			assert_true(u.statuses.has(sid), "%s later=%s" % [sid, later])

func test_sect_procs_off_when_later_cmds_off() -> void:
	# 古墓 清心（PARALYZE）滿級：規則關時一次都不觸發；開時會觸發
	var t := _real_tables()
	for later in [false, true]:
		var procs := 0
		for sd in range(1, 80):
			var b := _b(later, { "jing": 90, "shen": 90, "sect": "gumu",
				"sect_skill": { "id": "qingxin", "effect": "PARALYZE", "level": 100 } }, sd)
			if BattleStatus.try_proc(b, b.unit(1), "PARALYZE", t):
				procs += 1
		if later:
			assert_true(procs > 0, "規則開：會觸發")
		else:
			assert_eq(procs, 0, "規則關（classic_strict 2001）：門派技能不觸發")

func test_defense_proc_off_when_later_cmds_off() -> void:
	# 少林 佛法（DEFENSE）也是 2002-01-25 才開的觸發
	for later in [false, true]:
		var n := 0
		for sd in range(1, 60):
			var b := make_battle([player_spec(), monster("m_dummy", { "sect_skill": { "id": "foxa", "effect": "DEFENSE", "level": 100 } })],
				sd, { "later_battle_cmds": later })
			place(b, 1, 1, 3)
			place(b, 2, 2, 3)
			var r := do_cmd(b, 1, { "cmd": "ATTACK", "target": [2, 3] })
			n += find(r.events, "battle_proc_DEFENSE").size()
		if later:
			assert_true(n > 0, "規則開：佛法會觸發")
		else:
			assert_eq(n, 0, "規則關：佛法不觸發")

func test_paralysis_blocks_move_not_action() -> void:
	var t := _real_tables()
	var b := _b(true)
	BattleStatus.apply(b, b.unit(1), "paralysis", t)
	assert_eq(do_cmd(b, 1, { "cmd": "MOVE", "target": [1, 4] }, t).err, "status_blocked", "痲痺不能移動")
	var r := do_cmd(b, 1, { "cmd": "ATTACK", "target": [2, 3] }, t)
	assert_eq(r.err, "")
	assert_eq(find(r.events, "battle_status_skip").size(), 0, "痲痺不是暈眩：照樣出手")
	assert_true(BattleStatus.gauge_mult(b.unit(1), t) < 1.0, "時間棒變慢")

func test_medicine_overuse_qixue_then_coma() -> void:
	var t := _real_tables()
	var items := [ { "uid": "it_q1", "item_id": "c_jinchuang", "name": "金創藥", "n": 9,
		"effects": [ { "type": "restore", "stat": "qi", "value": 10 } ] } ]
	var b := make_battle([player_spec({ "qi": 50, "battle_items": items }), monster("m_dummy")], 3)
	place(b, 1, 1, 3)
	place(b, 2, 6, 3)
	for i in 2:
		var r := do_cmd(b, 1, { "cmd": "ITEM", "item_uid": "it_q1", "target": [1, 3] }, t)
		assert_eq(r.err, "")
		assert_false(b.unit(1).statuses.has("qixue"), "第 %d 次還沒事" % (i + 1))
	do_cmd(b, 1, { "cmd": "ITEM", "item_uid": "it_q1", "target": [1, 3] }, t)
	assert_true(b.unit(1).statuses.has("qixue"), "第 3 次氣血失調")
	var r2 := do_cmd(b, 1, { "cmd": "ITEM", "item_uid": "it_q1", "target": [1, 3] }, t)
	assert_true(b.unit(1).statuses.has("coma"), "失調中再吃藥昏迷")
	assert_eq(find(r2.events, "battle_status_on").back().p.status_name, "昏迷")
	var r3 := do_cmd(b, 1, { "cmd": "DEFEND" }, t)
	assert_eq(find(r3.events, "battle_status_skip").size(), 1, "昏迷跳過一次行動")

func test_bleed_lowers_qi_max() -> void:
	var t := _real_tables()
	var b := _b(true, { "qi": 180, "qi_max": 180 })
	BattleStatus.apply(b, b.unit(1), "bleed", t)
	var r := do_cmd(b, 1, { "cmd": "DEFEND" }, t)
	var bt := find(r.events, "battle_bleed_tick")
	assert_eq(bt.size(), 1, "每次行動都流血（不用移動）")
	assert_eq(int(bt[0].p.dmg), 5, "180 × 3% = 5.4 → 5")
	assert_eq(b.unit(1).qi_max(), 175, "氣上限往下掉")
	assert_eq(b.unit(1).qi, 175)
	r = do_cmd(b, 1, { "cmd": "MOVE", "target": [1, 4] }, t)
	assert_eq(r.err, "")
	assert_eq(b.unit(1).qi_max(), 170, "移動不另外扣")
