extends "res://tests/unit/test_battle_helpers.gd"
## 狀態機、等待模式（TECH_ARCH 10.7）、非等待模式、同 tick 排序、勝負判定、MAX_TICKS。

func test_start_layout_and_escape_tiles() -> void:
	var b := Battle.new(3, 555, default_opts())
	assert_eq(b.add_unit(player_spec()), 1)
	assert_eq(b.add_unit(monster("m_rabbit")), 2)
	assert_eq(b.add_unit(monster("m_rabbit")), 3)
	assert_eq(b.state, Battle.State.SETUP)
	var ev := b.start(tables())
	assert_eq(b.state, Battle.State.RUNNING)
	assert_eq(keys_of(ev), ["battle_gauges"])
	assert_eq(ev[0].get("ui", false), true)
	assert_eq(ev[0].ch, "BATTLE")
	assert_eq(ev[0].bid, 3)
	assert_eq(ev[0].p.units.size(), 3)
	assert_eq(b.unit(1).pos, Vector2i(1, 3))
	assert_eq(b.unit(2).pos, Vector2i(10, 3))
	assert_eq(b.unit(3).pos, Vector2i(10, 4))
	assert_eq(b.grid.escape.size(), 2)
	for e in b.grid.escape:
		assert_true(BattleGrid.manhattan(e, Vector2i(1, 3)) >= 3, "逃跑格離玩家起始格 ≥ 3")
		assert_true(b.unit_at(e) == null, "逃跑格是空格")
	assert_eq(b.add_unit(player_spec()), 0, "開戰後不能加入")
	# 同種子 → 同逃跑格
	var b2 := Battle.new(3, 555, default_opts())
	b2.add_unit(player_spec())
	b2.add_unit(monster("m_rabbit"))
	b2.add_unit(monster("m_rabbit"))
	b2.start(tables())
	assert_eq(b2.grid.escape, b.grid.escape)

func test_placement_order() -> void:
	var specs := [player_spec(), player_spec({ "peer": 2 }), player_spec({ "peer": 3 })]
	for i in 6:
		specs.append(monster("m_rabbit"))
	var b := make_battle(specs)
	assert_eq(b.unit(1).pos, Vector2i(1, 3))
	assert_eq(b.unit(2).pos, Vector2i(1, 4))
	assert_eq(b.unit(3).pos, Vector2i(1, 2))
	var ys := []
	for uid in range(4, 10):
		ys.append(b.unit(uid).pos.y)
		assert_eq(b.unit(uid).pos.x, 10)
	assert_eq(ys, [3, 4, 2, 5, 1, 6])

func test_snapshot_shape() -> void:
	var b := make_battle([player_spec({ "weapon": bare(), "skills": { "sl_changquan": 10 }, "arts": ["sl_changquan"] }),
		monster("m_rabbit")])
	var s := b.snapshot(tables())
	for k in ["bid", "w", "h", "tick", "wait_mode", "escape", "units"]:
		assert_has(s, k)
	assert_eq(s.w, 12)
	assert_eq(s.h, 8)
	assert_eq(s.escape.size(), 2)
	var me: Dictionary = s.units[0]
	for k in ["uid", "name", "side", "kind", "peer", "pos", "qi", "qi_max", "neili", "neili_max", "jing", "jing_max",
			"gauge", "rate", "state", "move_range", "weapon", "weapon_options", "arts"]:
		assert_has(me, k, "player")
	assert_eq(me.arts[0].id, "sl_changquan")
	assert_eq(me.arts[0].moves.size(), 3)
	assert_eq(me.arts[0].moves[0].usable, true)
	assert_eq(me.arts[0].moves[1].usable, false, "30 級才解鎖")
	var foe: Dictionary = s.units[1]
	for k in ["uid", "name", "side", "kind", "peer", "pos", "qi", "qi_max", "gauge", "rate", "state"]:
		assert_has(foe, k, "enemy")
	assert_not_has(foe, "arts")

func test_wait_mode_pauses_and_timeout_defends() -> void:
	var b := make_battle([player_spec({ "attrs": { "agi": 30 } }), monster("m_dummy")])
	var ev := run_until_ready(b, 1)
	assert_eq(b.state, Battle.State.AWAIT_COMMAND)
	var aw := find(ev, "battle_await")
	assert_eq(aw.size(), 1)
	assert_eq(aw[0].get("ui", false), true)
	assert_eq(aw[0].p.units, [1])
	var t0 := b.tick_no
	assert_eq(aw[0].p.deadline_tick, t0 + 200, "1 人 → 20 秒")
	var g := b.unit(2).gauge
	for i in 199:
		var e := b.step(Battle.TICK, tables())
		assert_eq(find(e, "battle_timeout").size(), 0)
	assert_eq(b.unit(2).gauge, g, "等待中時間棒全部暫停")
	assert_eq(b.state, Battle.State.AWAIT_COMMAND)
	ev = b.step(Battle.TICK, tables())
	assert_eq(b.tick_no, t0 + 200)
	assert_eq(find(ev, "battle_timeout").size(), 1)
	assert_eq(find(ev, "battle_defend").size(), 1, "逾時自動防")
	assert_true(b.unit(1).defending)
	assert_eq(b.unit(1).timeouts, 1)
	assert_false(b.unit(1).afk)
	assert_eq(b.state, Battle.State.RUNNING)
	assert_true(find(ev, "battle_gauges").size() == 1, "結算後送新錨點")

func test_afk_after_two_timeouts_and_reset_on_command() -> void:
	var b := make_battle([player_spec({ "attrs": { "agi": 30 } }), monster("m_dummy")])
	for n in 2:
		run_until_ready(b, 1)
		for i in 200:
			b.step(Battle.TICK, tables())
	assert_eq(b.unit(1).timeouts, 2)
	assert_true(b.unit(1).afk, "連續兩次逾時 → afk")
	var ev := run_until_ready(b, 1)
	assert_eq(find(ev, "battle_await")[0].p.deadline_tick, b.tick_no + 30, "afk 逾時 3 秒")
	assert_eq(b.submit(1, { "cmd": "DEFEND" }, tables()), "")
	assert_false(b.unit(1).afk, "自己下指令解除 afk")
	assert_eq(b.unit(1).timeouts, 0)

func test_timeout_shrinks_with_humans_and_round_budget() -> void:
	var opts := default_opts()
	var specs := []
	for p in range(1, 5):
		specs.append(player_spec({ "peer": p }))
	specs.append(monster("m_dummy"))
	var b := make_battle(specs)
	assert_true(approx(BattleRules.normal_timeout(b, opts), 14.0), "4 人 → 14 秒")
	var specs7 := []
	for p in range(1, 9):
		specs7.append(player_spec({ "peer": p }))
	specs7.append(monster("m_dummy"))
	var b7 := make_battle(specs7)
	assert_true(approx(BattleRules.normal_timeout(b7, opts), 8.0), "8 人 → 下限 8 秒")
	var b1 := make_battle([player_spec(), monster("m_dummy")])
	assert_true(approx(BattleRules.normal_timeout(b1, opts), 20.0))
	b1._round_wait_ticks = 450
	assert_true(approx(BattleRules.normal_timeout(b1, opts), 8.0), "本輪累計等待 ≥ 45 秒 → 最小值")
	var u := b1.unit(1)
	u.afk = true
	assert_true(approx(BattleRules.unit_timeout(b1, u, opts), 3.0))
	assert_true(approx(BattleRules.await_timeout(b1, [u], opts), 3.0))

func test_round_budget_resets_after_everyone_acted() -> void:
	var b := make_battle([player_spec({ "attrs": { "agi": 30 } }), monster("m_dummy")])
	run_until_ready(b, 1)
	for i in 50:
		b.step(Battle.TICK, tables())
	assert_eq(b._round_wait_ticks, 50)
	b.submit(1, { "cmd": "DEFEND" }, tables())
	b.step(Battle.TICK, tables())
	assert_eq(b._round_wait_ticks, 0, "唯一的真人行動過 → 新的一輪")

func test_shared_wait_for_simultaneous_humans() -> void:
	var b := make_battle([player_spec(), player_spec({ "peer": 2, "name": "乙" }), monster("m_dummy")])
	var ev := run_until_ready(b, 1)
	var aw := find(ev, "battle_await")
	assert_eq(aw.size(), 1)
	assert_eq(aw[0].p.units, [1, 2], "同 tick 滿條一起等")
	assert_eq(aw[0].p.deadline_tick, b.tick_no + 180, "2 人 → 18 秒")
	assert_eq(b.submit(1, { "cmd": "DEFEND" }, tables()), "")
	ev = b.step(Battle.TICK, tables())
	assert_eq(b.state, Battle.State.AWAIT_COMMAND, "還在等乙")
	assert_eq(find(ev, "battle_defend").size(), 0)
	assert_eq(b.submit(2, { "cmd": "DEFEND" }, tables()), "")
	ev = b.step(Battle.TICK, tables())
	assert_eq(find(ev, "battle_defend").size(), 2, "全部下令就立刻結算")
	assert_eq(b.state, Battle.State.RUNNING)

func test_non_wait_mode() -> void:
	var b := make_battle([player_spec({ "attrs": { "agi": 30 } }), monster("m_dummy")], 1234, { "wait_mode": false })
	run_until_ready(b, 1)
	assert_eq(b.state, Battle.State.RUNNING)
	assert_eq(b.unit(1).state, BattleUnit.READY)
	var g := b.unit(2).gauge
	var ev: Array = []
	for i in 5:
		ev.append_array(b.step(Battle.TICK, tables()))
	assert_eq(find(ev, "battle_await").size(), 0)
	assert_true(b.unit(2).gauge > g or b.unit(2).actions > 0, "其他單位照常累積")
	assert_eq(b.unit(1).state, BattleUnit.READY, "玩家停在滿條")
	assert_true(approx(b.unit(1).gauge, 100.0))
	assert_eq(b.submit(1, { "cmd": "DEFEND" }, tables()), "")
	ev = b.step(Battle.TICK, tables())
	assert_eq(find(ev, "battle_defend").size(), 1, "下一個 step 結算")

func test_same_tick_order_overflow_agi_uid() -> void:
	var b := make_battle([player_spec(), monster("m_dummy", { "attrs": { "agi": 0 } }),
		monster("m_dummy", { "attrs": { "agi": 20 } }), monster("m_dummy", { "attrs": { "agi": 20 } })])
	# 速度：玩家 7、2 號 4、3 號 7、4 號 7 → 溢出量 4、2、2、2
	b.unit(1).gauge = 97.0
	b.unit(2).gauge = 98.0
	b.unit(3).gauge = 95.0
	b.unit(4).gauge = 95.0
	b.step(Battle.TICK, tables())
	assert_eq(b.state, Battle.State.AWAIT_COMMAND)
	assert_eq(b.pending_uids(), [1, 3, 4, 2], "溢出量 → 機敏 → uid")

func test_ai_acts_immediately_without_humans_waiting() -> void:
	var b := make_battle([player_spec({ "attrs": { "agi": 1 } }), monster("m_rabbit", { "attrs": { "agi": 30 } })])
	var ev: Array = []
	for i in 15:
		ev.append_array(b.step(Battle.TICK, tables()))
	assert_eq(find(ev, "battle_move").size(), 1, "兔子先滿條、立刻移動")
	assert_eq(find(ev, "battle_await").size(), 0)

func test_victory_outcome_and_kills() -> void:
	var b := make_battle([player_spec({ "attrs": { "agi": 40 } }), monster("m_glass")], 77)
	var r := play(b, [1])
	assert_true(b.is_over())
	assert_eq(b.result_name(), "VICTORY")
	var ev: Array = r.events
	assert_eq(find(ev, "battle_kill").size(), 1)
	var k: Dictionary = find(ev, "battle_kill")[0].p
	assert_eq(k.peer, 0)
	assert_eq(k.by, "測試俠客")
	assert_eq(keys_of(ev).back(), "battle_end")
	assert_eq(ev.back().p.result, "VICTORY")
	var o := b.outcome()
	assert_eq(o.result, "VICTORY")
	assert_eq(o.bid, 7)
	assert_eq(o.ticks, b.tick_no)
	var me: Dictionary = o.units[1]
	for key in ["uid", "kind", "ref", "side", "peer", "alive", "died", "fled", "qi", "neili", "jing", "shen", "weapon_uid", "kills"]:
		assert_has(me, key)
	assert_eq(me.kills, ["m_glass"])
	assert_eq(me.weapon_uid, "it_0001")
	assert_eq(me.alive, true)
	var foe: Dictionary = o.units[2]
	assert_eq(foe.died, true)
	assert_eq(foe.alive, false)
	assert_eq(foe.qi, 1, "氣降到 1 即死亡")
	assert_eq(foe.killed_by, 1)
	assert_eq(foe.ref, "m_glass")

func test_defeat_player_qi_is_one() -> void:
	var b := make_battle([player_spec({ "qi": 2, "attrs": { "agi": 1 } }), monster("m_wolf")], 5)
	var r := play(b, [1])
	assert_eq(b.result_name(), "DEFEAT")
	assert_eq(find(r.events, "battle_death").size(), 1)
	var me: Dictionary = b.outcome().units[1]
	assert_eq(me.died, true)
	assert_eq(me.qi, 1)

func test_partial_flee_with_death_is_defeat() -> void:
	var b := make_battle([player_spec(), player_spec({ "peer": 2 }), monster("m_dummy")])
	b.unit(1).state = BattleUnit.FLED
	b.unit(2).qi = 2
	b.unit(2).statuses["inner_wound"] = 5
	b.unit(2).state = BattleUnit.READY
	var ev := BattleRules.execute(b, b.unit(2), { "cmd": "DEFEND" }, tables(), b.rng)
	assert_eq(keys_of(ev), ["battle_wound_tick", "battle_death"], "內傷發作可致死，行動取消")
	assert_true(b._check_end())
	assert_eq(b.result_name(), "DEFEAT")

func test_all_fled_and_monster_flee() -> void:
	var b := make_battle([player_spec(), player_spec({ "peer": 2 }), monster("m_dummy")])
	b.unit(1).state = BattleUnit.FLED
	b.unit(2).state = BattleUnit.FLED
	assert_true(b._check_end())
	assert_eq(b.result_name(), "ALL_FLED")
	# 怪物全部逃走也是勝利
	var c := make_battle([player_spec(), monster("m_rabbit")])
	c.unit(2).state = BattleUnit.FLED
	assert_true(c._check_end())
	assert_eq(c.result_name(), "VICTORY")

func test_status_wears_off() -> void:
	var b := make_battle([player_spec(), monster("m_dummy")])
	var u := b.unit(1)
	BattleRules.apply_status(b, u, "inner_wound", tables())
	assert_eq(u.statuses.inner_wound, 5)
	var offs := 0
	var ticks := 0
	for i in 5:
		u.state = BattleUnit.READY
		var ev := BattleRules.execute(b, u, { "cmd": "DEFEND" }, tables(), b.rng)
		ticks += find(ev, "battle_wound_tick").size()
		offs += find(ev, "battle_status_off").size()
		if i == 0:
			assert_eq(find(ev, "battle_wound_tick")[0].p.dmg, 4, "180×2% → 4")
	assert_eq(ticks, 5)
	assert_eq(offs, 1)
	assert_true(u.statuses.is_empty())
	assert_eq(u.qi, 160)

func test_max_ticks_aborts() -> void:
	var b := make_battle([player_spec({ "qi": 1000000, "qi_max": 1000000 }), monster("m_dummy")], 1, { "wait_mode": false })
	var ev := run_until_over(b)
	assert_true(b.is_over())
	assert_eq(b.result_name(), "ABORTED")
	assert_eq(b.tick_no, Battle.MAX_TICKS)
	assert_eq(ev.back().key, "battle_end")

func test_counter_attack_and_defense_proc() -> void:
	# 定力高 → 反擊；佛法 → DEFENSE 觸發（兩者都靠 rng，找一個會發生的種子）
	var found_counter := false
	var found_proc := false
	for s in range(1, 200):
		var b := make_battle([player_spec({ "attrs": { "cal": 80, "agi": 1 }, "qi": 100000, "qi_max": 100000,
			"sect_skill": { "id": "foxa", "effect": "DEFENSE", "level": 100 } }), monster("m_wolf")], s)
		place(b, 2, 2, 3)
		var wolf := b.unit(2)
		wolf.state = BattleUnit.READY
		var ev := BattleRules.execute(b, wolf, { "cmd": "ART", "art": "mon_claw", "move": "mon_claw_1", "power_tenths": 10,
			"target": [1, 3] }, tables(), b.rng)
		var ks := keys_of(ev)
		if ks.has("battle_counter"):
			found_counter = true
			var i := ks.find("battle_counter")
			assert_eq(ev[i].p.atk_uid, 1, "反擊者是玩家")
			assert_true(ks.slice(i + 1).has("atk_blade") or ks.slice(i + 1).has("battle_miss"), "反擊 = 一次 ATTACK")
			assert_eq(ks.count("battle_counter"), 1, "反擊不會再引發反擊")
			var follow: Array = ev.slice(i + 1).filter(func(e): return e.key == "atk_blade")
			if not follow.is_empty():
				assert_eq(follow[0].p.counter, true)
		if ks.has("battle_proc_DEFENSE"):
			found_proc = true
			assert_eq(ev[ks.find("battle_proc_DEFENSE")].p.skill_name, "佛法")
			assert_true(ks.find("battle_proc_DEFENSE") < ks.find("move_claw"), "觸發在命中事件之前")
		if found_counter and found_proc:
			break
	assert_true(found_counter, "反擊")
	assert_true(found_proc, "佛法觸發")

func test_recover_proc() -> void:
	var found := false
	for s in range(1, 200):
		var b := make_battle([player_spec({ "qi": 100, "shen": 10, "attrs": { "agi": 200 },
			"sect_skill": { "id": "rufeng", "effect": "RECOVER", "level": 100 } }), monster("m_dummy")], s)
		place(b, 2, 2, 3)
		var me := b.unit(1)
		me.state = BattleUnit.READY
		var ev := BattleRules.execute(b, me, { "cmd": "ATTACK", "target": [2, 3] }, tables(), b.rng)
		var r := find(ev, "battle_proc_RECOVER")
		if not r.is_empty():
			found = true
			# 上限 × (3% + 100×0.05%) = 8%
			assert_eq(r[0].p.qi_gain, 14, "180×8%")
			assert_eq(r[0].p.shen_gain, 7, "88×8%")
			assert_eq(r[0].p.skill_name, "儒風")
			assert_eq(ev.back().key, "battle_proc_RECOVER", "行動結束時")
			break
	assert_true(found)

## 回歸：實際戰鬥事件餵給客戶端 BattleViewModel 後，輪到我時指令列必須可按。
## 曾經 battle_await 後同 tick 的 battle_gauges 仍標示怪物 charging，客戶端因此清掉等待清單，畫面卡在「蓄勢中」。
func test_view_model_sees_my_turn_through_real_events() -> void:
	for seed_v in [1, 2, 3, 4, 5]:
		var b := Battle.new(9, seed_v, default_opts())
		b.add_unit(player_spec())
		b.add_unit(monster("m_wolf"))
		var start_ev := b.start(tables())
		var snap := b.snapshot(tables())
		snap["my_uid"] = b.uid_for_peer(1)
		var vm := BattleViewModel.from_state(snap)
		for e in start_ev:
			vm.apply_event(e)
		var turns := 0
		for i in 3000:
			if b.is_over() or turns >= 3:
				break
			var ev := b.step(Battle.TICK, tables())
			for e in ev:
				vm.apply_event(e)
			if b.state == Battle.State.AWAIT_COMMAND and b.waiting_humans().any(func(u): return u.peer == 1):
				assert_true(vm.is_my_turn(float(b.tick_no)), "seed %d：主機在等我下令，客戶端卻不是我的回合" % seed_v)
				assert_eq(b.submit(1, { "cmd": "DEFEND" }, tables()), "")
				vm.mark_submitted()
				turns += 1
		assert_true(turns >= 1, "seed %d：至少輪到我一次" % seed_v)
