extends "res://tests/unit/test_battle_helpers.gd"
## M2_PLAN 4.6.3、6.1：Battle.join_unit（中途加入）、humans、winner_side、PvP 兩個玩家單位、
## BattleRewards 對沒有怪物的戰鬥、BattleSystem.relative_result（相對於本人那一方的結果）。

func _two_player_pvp(over0: Dictionary = {}, over1: Dictionary = {}, seed_v := 99, kind := "FORCED") -> Battle:
	var o0 := { "peer": 1, "ref": "ch_a", "name": "甲" }
	o0.merge(over0, true)
	var o1 := { "peer": 2, "ref": "ch_b", "name": "乙", "side": 1 }
	o1.merge(over1, true)
	var a := player_spec(o0)
	var d := player_spec(o1)
	var b := Battle.new(5, seed_v, default_opts({ "kind": kind }))
	b.add_unit(a)
	b.add_unit(d)
	b.start(tables())
	return b

func test_join_in_running_places_outer_column() -> void:
	var b := make_battle([player_spec(), monster("m_rabbit")])
	assert_eq(b.state, Battle.State.RUNNING)
	assert_eq(b.humans(), 1)
	var uid := b.join_unit(player_spec({ "peer": 2, "ref": "ch_join", "name": "援手" }), tables())
	assert_eq(uid, 3, "新單位 uid 接在後面")
	var u := b.unit(uid)
	assert_eq(u.side, 0)
	assert_eq(u.pos.x, 0, "side 0 從最外側欄 x=0 出場")
	assert_true(BattleGrid.Y_ORDER.has(u.pos.y))
	assert_false(b.grid.is_escape(u.pos), "不放在逃跑格上")
	assert_eq(u.state, BattleUnit.CHARGING)
	assert_eq(u.gauge, 0.0)
	assert_true(u.rate > 0.0, "時間棒速度已算好")
	assert_eq(b.humans(), 2)
	assert_eq(b.uid_for_peer(2), uid)
	var ev := b.drain_events()
	assert_eq(keys_of(ev), ["battle_join", "battle_unit_join", "battle_gauges"])
	assert_eq(ev[0].ch, "BATTLE")
	assert_false(ev[0].get("ui", false), "battle_join 走模板")
	assert_eq(ev[0].p.uid, uid)
	assert_eq(ev[0].p.name, "援手")
	assert_eq(ev[0].p.peer, 2)
	assert_eq(ev[1].get("ui", false), true, "battle_unit_join 是 UI 事件")
	var snap: Dictionary = ev[1].p.unit
	assert_eq(snap.pos, [u.pos.x, u.pos.y])
	assert_eq(snap.side, 0)
	assert_eq(snap.kind, "PLAYER")
	assert_has(snap, "arts")
	assert_eq(ev[2].p.units.size(), 3, "時間棒清單含新單位")
	assert_eq(b.drain_events(), [], "取走後清空")

func test_join_events_come_out_of_next_step_when_not_drained() -> void:
	var b := make_battle([player_spec(), monster("m_rabbit")])
	b.join_unit(player_spec({ "peer": 2 }), tables())
	var ev := b.step(Battle.TICK, tables())
	assert_true(keys_of(ev).has("battle_join"), "下一次 step 帶出")
	assert_true(keys_of(ev).has("battle_unit_join"))

func test_join_during_await_and_new_unit_acts() -> void:
	var b := make_battle([player_spec(), monster("m_wolf", { "qi": 2000, "qi_max": 2000 })])
	run_until_ready(b, 1)
	assert_eq(b.state, Battle.State.AWAIT_COMMAND, "等待玩家 1 下令")
	var uid := b.join_unit(player_spec({ "peer": 2, "ref": "ch_join" }), tables())
	assert_true(uid > 0, "AWAIT_COMMAND 中也能加入")
	assert_eq(b.state, Battle.State.AWAIT_COMMAND, "加入不打斷等待")
	assert_false(b.pending_uids().has(uid), "新單位從 0 開始蓄力，不在等待清單")
	assert_eq(b.submit(1, { "cmd": "DEFEND" }, tables()), "")
	# 新加入者之後也會輪到並進入等待
	run_until_ready(b, 2)
	assert_eq(b.unit(uid).state, BattleUnit.READY, "新加入者輪到行動")
	assert_true(b.waiting_humans().map(func(x): return x.uid).has(uid))
	assert_eq(b.submit(2, { "cmd": "DEFEND" }, tables()), "")

func test_join_side1_uses_x11() -> void:
	var b := make_battle([player_spec(), player_spec({ "peer": 2, "side": 1, "ref": "ch_b" })])
	var uid := b.join_unit(player_spec({ "peer": 3, "side": 1, "ref": "ch_c" }), tables())
	assert_true(uid > 0)
	assert_eq(b.unit(uid).pos.x, 11, "side 1 從 x=11 出場")
	assert_eq(b.unit(uid).side, 1)

func test_join_fills_outer_column_then_moves_inward_then_zero() -> void:
	var b := make_battle([player_spec(), monster("m_rabbit")])
	var last_x := -1
	var placed := 0
	var first_inner := -1
	for i in 60:
		var uid := b.join_unit(player_spec({ "peer": 10 + i }), tables())
		if uid == 0:
			break
		placed += 1
		var p := b.unit(uid).pos
		assert_true(p.x >= last_x, "由外往內：x 不減（%d 之後 %d）" % [last_x, p.x])
		assert_true(p.x <= 5, "只用己方半場")
		if p.x > 0 and first_inner < 0:
			first_inner = placed
		last_x = p.x
	assert_true(placed > 8, "外側欄滿了會往內")
	assert_true(first_inner > 1, "先填滿外側欄")
	assert_true(placed < 60, "半場滿了回 0")
	assert_eq(b.join_unit(player_spec({ "peer": 99 }), tables()), 0, "沒有空格回 0")
	assert_eq(b.join_cell(0), Vector2i(-1, -1))

func test_join_rejected_in_setup_and_after_end() -> void:
	var b := Battle.new(1, 1, default_opts())
	b.add_unit(player_spec())
	b.add_unit(monster("m_rabbit"))
	assert_eq(b.join_unit(player_spec({ "peer": 2 }), tables()), 0, "SETUP 不能 join（用 add_unit）")
	b.start(tables())
	b.abort()
	assert_eq(b.join_unit(player_spec({ "peer": 2 }), tables()), 0, "ENDED 不能 join")

func test_joined_player_shares_rewards() -> void:
	var b := make_battle([player_spec({ "attrs": { "str": 60 } }), monster("m_rabbit", { "ai": "melee_basic" })], 77)
	var uid := b.join_unit(player_spec({ "peer": 2, "ref": "ch_join", "attrs": { "str": 60 } }), tables())
	play(b, [1, 2])
	assert_eq(b.result, Battle.Result.VICTORY)
	var r := BattleRewards.compute(b, tables(), RandomNumberGenerator.new())
	assert_has(r, uid, "中途加入者也分獎勵")
	assert_has(r, 1)
	assert_eq(int(r[uid].combat_xp), int(r[1].combat_xp), "同實戰的兩人分得一樣多")

func test_snapshot_kind_and_outcome_winner_side() -> void:
	var b := make_battle([player_spec({ "attrs": { "str": 60 } }), monster("m_rabbit", { "ai": "melee_basic" })], 3,
		{ "kind": "ENCOUNTER" })
	assert_eq(b.snapshot(tables()).kind, "ENCOUNTER")
	assert_eq(b.winner_side(), -1, "未分勝負")
	play(b, [1])
	assert_eq(b.result, Battle.Result.VICTORY)
	assert_eq(b.winner_side(), 0)
	assert_eq(b.outcome().winner_side, 0)

func test_winner_side_table() -> void:
	var b := _two_player_pvp()
	b.result = Battle.Result.DEFEAT
	assert_eq(b.winner_side(), 1, "side 0 全倒、side 1 還站著")
	b.unit(2).state = BattleUnit.FLED
	assert_eq(b.winner_side(), -1, "side 1 也不在場：無勝方")
	b.result = Battle.Result.ALL_FLED
	assert_eq(b.winner_side(), -1)
	b.result = Battle.Result.ABORTED
	assert_eq(b.winner_side(), -1)
	b.result = Battle.Result.VICTORY
	assert_eq(b.winner_side(), 0)

func test_pvp_two_players_to_the_end() -> void:
	# 乙（side 1）明顯較強：應該是 side 1 勝
	var b := _two_player_pvp({}, { "attrs": { "str": 80, "con": 60 }, "qi": 600, "qi_max": 600 }, 11)
	assert_eq(b.humans(), 2)
	assert_eq(b.snapshot(tables()).kind, "FORCED")
	play(b, [1, 2])
	assert_true(b.is_over())
	assert_eq(b.result, Battle.Result.DEFEAT, "以 side 0 為準是 DEFEAT")
	assert_eq(b.winner_side(), 1)
	var out := b.outcome()
	assert_eq(out.winner_side, 1)
	assert_true(out.units[1].died, "甲倒下")
	assert_eq(out.units[1].killed_by, 2, "擊殺者記錄照常")
	assert_false(out.units[2].died)
	assert_eq(BattleSystem.relative_result(out, 0), "DEFEAT")
	assert_eq(BattleSystem.relative_result(out, 1), "VICTORY", "結果相對於本人那一方")
	assert_eq(BattleRewards.compute(b, tables(), RandomNumberGenerator.new()), {}, "PvP 沒有獎勵")

func test_pvp_side0_wins() -> void:
	var b := _two_player_pvp({ "attrs": { "str": 80, "con": 60 }, "qi": 600, "qi_max": 600 }, {}, 12, "CHALLENGE")
	play(b, [1, 2])
	assert_eq(b.result, Battle.Result.VICTORY)
	var out := b.outcome()
	assert_eq(BattleSystem.relative_result(out, 0), "VICTORY")
	assert_eq(BattleSystem.relative_result(out, 1), "DEFEAT")
	assert_eq(BattleRewards.compute(b, tables(), RandomNumberGenerator.new()), {}, "PvP 勝利也沒有獎勵")

func test_relative_result_edges() -> void:
	assert_eq(BattleSystem.relative_result({ "result": "ABORTED", "winner_side": -1 }, 0), "ABORTED")
	assert_eq(BattleSystem.relative_result({ "result": "ALL_FLED", "winner_side": -1 }, 1), "ALL_FLED")
	assert_eq(BattleSystem.relative_result({ "result": "DEFEAT", "winner_side": -1 }, 0), "ALL_FLED", "沒有勝方")
	assert_eq(BattleSystem.relative_result({ "result": "VICTORY" }, 0), "VICTORY", "舊形狀（沒有 winner_side）")
	assert_eq(BattleSystem.relative_result({ "result": "DEFEAT" }, 0), "DEFEAT")

func test_redact_enemy_player_unit() -> void:
	var b := _two_player_pvp()
	var snap := b.snapshot(tables())
	var mine: Dictionary = BattleSystem.redact_unit(snap.units[0], 0)
	var theirs: Dictionary = BattleSystem.redact_unit(snap.units[1], 0)
	assert_has(mine, "arts", "自己那方完整")
	assert_has(mine, "weapon_options")
	assert_not_has(theirs, "arts", "對方玩家只帶最少欄位")
	assert_not_has(theirs, "neili")
	assert_not_has(theirs, "weapon_options")
	assert_has(theirs, "look")
	assert_has(theirs, "qi")
	assert_has(theirs, "pos")
