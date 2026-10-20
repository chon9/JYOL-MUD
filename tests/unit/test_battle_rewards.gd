extends "res://tests/unit/test_battle_helpers.gd"
## M1_PLAN 4.8：實戰／學點公式、分享係數、掉落歸屬、逃走怪物不給、DEFEAT 空結果。

func _row(id: String) -> Dictionary:
	return tables().monsters[id]

func test_formula_ratio_and_clamps() -> void:
	var rabbit := _row("m_rabbit")
	assert_eq(BattleRewards.xp_for(rabbit, 0, 1.0), 5, "5 × 1050/1000")
	assert_eq(BattleRewards.lp_for(rabbit, 0, 1.0), 2, "2 × 1.05 = 2.1")
	assert_eq(BattleRewards.xp_for(rabbit, 10000, 1.0), 1, "比例夾在 0.1 → 0.5 → 至少 1")
	assert_eq(BattleRewards.lp_for(rabbit, 10000, 1.0), 1, "比例夾在 0.2 → 0.4 → 至少 1")
	var bandit := _row("m_bandit")
	assert_eq(BattleRewards.xp_for(bandit, 0, 1.0), 80, "比例 4 → 夾在 2.0")
	assert_eq(BattleRewards.lp_for(bandit, 0, 1.0), 45, "比例 4 → 夾在 3.0")
	assert_eq(BattleRewards.xp_for(bandit, 0, 1.0 / sqrt(2.0)), 57, "分享係數 1/√2")
	assert_eq(BattleRewards.xp_for(bandit, 3000, 1.0), 40, "比例 1")
	assert_eq(BattleRewards.xp_for(_row("m_dummy"), 0, 1.0), 0, "combat_xp 0 → 0")
	assert_eq(BattleRewards.lp_for(_row("m_dummy"), 0, 1.0), 0, "learn_points 0 → 0")

func _victory_setup() -> Battle:
	# 玩家 1、2 存活，3 死亡，4 逃走；怪物 5 由 2 擊殺，6 由已死的 3 擊殺，7 逃走，8 是 no_rewards
	var b := make_battle([player_spec(), player_spec({ "peer": 2, "ref": "ch_b" }), player_spec({ "peer": 3, "ref": "ch_c" }),
		player_spec({ "peer": 4, "ref": "ch_d" }),
		monster("m_glass"), monster("m_glass"), monster("m_glass"), monster("m_trainee")])
	b.unit(3).state = BattleUnit.DEAD
	b.unit(4).state = BattleUnit.FLED
	b.unit(5).state = BattleUnit.DEAD
	b.unit(5).killed_by = 2
	b.unit(2).kills = ["m_glass"]
	b.unit(6).state = BattleUnit.DEAD
	b.unit(6).killed_by = 3
	b.unit(3).kills = ["m_glass"]
	b.unit(7).state = BattleUnit.FLED
	b.unit(8).state = BattleUnit.DEAD
	b.unit(8).killed_by = 1
	b.unit(1).kills = ["m_trainee"]
	assert_true(b._check_end())
	assert_eq(b.result_name(), "VICTORY")
	return b

func test_compute_distribution() -> void:
	var b := _victory_setup()
	var r := BattleRewards.compute(b, tables(), RandomNumberGenerator.new())
	assert_eq(r.keys(), [1, 2], "只有存活且未逃走的玩家")
	# 每隻紙老虎：實戰 10 × 1 × (1/√2) = 7.07 → 7；學點 4 × 0.707 = 2.83 → 3；兩隻死亡（逃走、no_rewards 不算）
	for uid in [1, 2]:
		assert_eq(r[uid].combat_xp, 14)
		assert_eq(r[uid].learn_points, 6)
	# 5 號由 2 擊殺 → 掉落、銀兩、善惡、殺氣給 2
	assert_eq(r[2].items, [{ "id": "r_rabbitskin", "n": 2, "rarity": "COMMON" }])
	assert_eq(r[2].money, 7)
	assert_eq(r[2].morality, -5)
	assert_eq(r[2].killing_intent, 2)
	# 6 號的擊殺者已死 → 掉落與銀兩改給 uid 最小的存活玩家；善惡、殺氣不轉給別人
	assert_eq(r[1].items, [{ "id": "r_rabbitskin", "n": 2, "rarity": "COMMON" }])
	assert_eq(r[1].money, 7)
	assert_eq(r[1].morality, 0)
	assert_eq(r[1].killing_intent, 0)
	assert_eq(r[1].kills, ["m_trainee"], "kills 仍列出（任務計數用）")
	assert_eq(r[2].kills, ["m_glass"])

func test_single_player_no_share_and_merge_items() -> void:
	var b := make_battle([player_spec({ "combat_xp": 0 }), monster("m_glass"), monster("m_glass")])
	for uid in [2, 3]:
		b.unit(uid).state = BattleUnit.DEAD
		b.unit(uid).killed_by = 1
	b._check_end()
	var r := BattleRewards.compute(b, tables(), RandomNumberGenerator.new())
	assert_eq(r[1].combat_xp, 20)
	assert_eq(r[1].learn_points, 8)
	assert_eq(r[1].items, [{ "id": "r_rabbitskin", "n": 4, "rarity": "COMMON" }], "同 id 合併")
	assert_eq(r[1].money, 14)
	assert_eq(r[1].morality, -10)

func test_player_xp_lowers_rewards() -> void:
	var b := make_battle([player_spec({ "combat_xp": 9000 }), monster("m_bandit")])
	b.unit(2).state = BattleUnit.DEAD
	b.unit(2).killed_by = 1
	b._check_end()
	var r := BattleRewards.compute(b, tables(), RandomNumberGenerator.new())
	# 比例 4000/10000 = 0.4 → 實戰 16、學點 6
	assert_eq(r[1].combat_xp, 16)
	assert_eq(r[1].learn_points, 6)
	assert_eq(r[1].morality, 3)
	assert_eq(r[1].killing_intent, 5)
	assert_true(r[1].money >= 20 and r[1].money <= 60)

func test_non_victory_is_empty() -> void:
	var b := make_battle([player_spec(), monster("m_glass")])
	b.unit(1).state = BattleUnit.DEAD
	b._check_end()
	assert_eq(b.result_name(), "DEFEAT")
	assert_eq(BattleRewards.compute(b, tables(), RandomNumberGenerator.new()), {})
	var c := make_battle([player_spec(), monster("m_glass")])
	c.unit(1).state = BattleUnit.FLED
	c._check_end()
	assert_eq(c.result_name(), "ALL_FLED")
	assert_eq(BattleRewards.compute(c, tables(), RandomNumberGenerator.new()), {})
	var d := make_battle([player_spec(), monster("m_glass")])
	d.abort()
	assert_eq(BattleRewards.compute(d, tables(), RandomNumberGenerator.new()), {})

func test_rewards_deterministic_drops() -> void:
	var r1 := []
	var r2 := []
	for out in [r1, r2]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		for i in 20:
			var b := make_battle([player_spec(), monster("m_rabbit")])
			b.unit(2).state = BattleUnit.DEAD
			b.unit(2).killed_by = 1
			b._check_end()
			out.append(BattleRewards.compute(b, tables(), rng))
	assert_eq(JSON.stringify(r1), JSON.stringify(r2))
	var got_skin := r1.any(func(r): return not r[1].items.is_empty())
	var no_skin := r1.any(func(r): return r[1].items.is_empty())
	assert_true(got_skin and no_skin, "chance 0.5 有掉有不掉")
