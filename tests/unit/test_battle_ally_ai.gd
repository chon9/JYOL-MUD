extends "res://tests/unit/test_battle_helpers.gd"
## ROGUE WP-ALLY（ROGUE_PLAN §4.3、§9.1）：AI 隊友（ai: ally）只打 side 1、用全部武功、不逃、目標排序、護著玩家移動；
## 沒有 ai: ally 的單位行為不變（金檔另由 test_battle_replay 驗證）。

## 隊友：拳腳兩套（arts[0] 是較弱的少林長拳；arts[1] 劈石破玉拳 威力 40、要 15 內力）
static func rg_ally_spec(over: Dictionary = {}) -> Dictionary:
	var s := monster("m_wolf", { "kind": "ALLY", "ai": "ally", "side": 0, "peer": 0, "ref": "n_t_hero", "name": "測試隊友",
		"rg_ally": "1", "arts": ["sl_changquan", "hs_pishiquan"], "skills": { "sl_changquan": 30, "hs_pishiquan": 30 },
		"neili": 100, "neili_max": 100, "qi": 400, "qi_max": 400 })
	for k in over:
		s[k] = over[k]
	return s

func _battle(specs: Array, seed_v := 11, opts := {}) -> Battle:
	var b := Battle.new(7, seed_v, default_opts(opts))
	for s in specs:
		b.add_unit(s)
	b.start(tables())
	return b

func test_ally_usable_moves_use_all_arts() -> void:
	var u := BattleUnit.new(1, rg_ally_spec())
	var arts := BattleAI.usable_moves(u, tables()).map(func(m): return m.art)
	assert_has(arts, "hs_pishiquan", "隊友用全部武功")
	assert_has(arts, "sl_changquan")
	assert_eq(arts[0], "hs_pishiquan", "威力高的在前")
	var mon := BattleUnit.new(1, rg_ally_spec({ "kind": "MONSTER", "ai": "melee_basic" }))
	var marts := BattleAI.usable_moves(mon, tables()).map(func(m): return m.art)
	assert_true(marts.all(func(a): return a == "sl_changquan"), "一般怪物照舊只用 arts[0]")

func test_ally_picks_strongest_move_on_enemy() -> void:
	var b := _battle([player_spec(), rg_ally_spec(), monster("m_wolf")])
	place(b, 1, 0, 0)
	place(b, 2, 5, 3)
	place(b, 3, 6, 3)
	var c := BattleAI.choose(b, b.unit(2), tables(), RandomNumberGenerator.new())
	assert_eq(c.cmd, "ART")
	assert_eq(c.art, "hs_pishiquan", "arts[1] 的強招")
	assert_eq(c.target, [6, 3])

func test_ally_never_targets_own_side() -> void:
	var b := _battle([player_spec(), rg_ally_spec(), monster("m_wolf")])
	# 玩家緊貼隊友、敵人遠在右邊：隊友不會打玩家，只會往敵人移動
	place(b, 1, 4, 3)
	place(b, 2, 5, 3)
	place(b, 3, 11, 0)
	var c := BattleAI.choose(b, b.unit(2), tables(), RandomNumberGenerator.new())
	assert_eq(c.cmd, "MOVE", "身邊只有玩家 → 移動，不攻擊")

func test_ally_target_order_qi_then_near_player() -> void:
	var b := _battle([player_spec(), rg_ally_spec(), monster("m_wolf"), monster("m_wolf")])
	place(b, 1, 3, 6)   # 玩家在下方
	place(b, 2, 5, 3)
	place(b, 3, 5, 2)   # 上方的狼（離玩家遠）
	place(b, 4, 5, 4)   # 下方的狼（離玩家近）
	var c := BattleAI.choose(b, b.unit(2), tables(), RandomNumberGenerator.new())
	assert_eq(c.target, [5, 4], "同氣：離我方玩家近的先打")
	b.unit(3).qi = 10
	var c2 := BattleAI.choose(b, b.unit(2), tables(), RandomNumberGenerator.new())
	assert_eq(c2.target, [5, 2], "氣最少的優先")

func test_ally_moves_toward_enemy_nearest_player() -> void:
	var b := _battle([player_spec(), rg_ally_spec(), monster("m_wolf"), monster("m_wolf")])
	place(b, 1, 6, 7)    # 玩家在右下
	place(b, 2, 2, 0)    # 隊友在左上
	place(b, 3, 3, 0)    # 狼甲：貼著隊友 → 直接打（基準）
	place(b, 4, 7, 7)    # 狼乙：貼著玩家
	var c := BattleAI.choose(b, b.unit(2), tables(), RandomNumberGenerator.new())
	assert_eq(c.cmd, "ART", "打得到就打")
	place(b, 3, 11, 0)   # 狼甲退到遠處
	var c2 := BattleAI.choose(b, b.unit(2), tables(), RandomNumberGenerator.new())
	assert_eq(c2.cmd, "MOVE")
	var dest := Vector2i(int(c2.target[0]), int(c2.target[1]))
	assert_true(BattleGrid.manhattan(dest, Vector2i(7, 7)) < BattleGrid.manhattan(Vector2i(2, 0), Vector2i(7, 7)),
		"往貼著玩家的狼乙靠近")

func test_ally_never_flees_and_hits_only_side1() -> void:
	var acts := 0
	for sd in [3, 17, 29, 101]:
		var qi := 3 if sd > 20 else 400   # 後兩場：隊友只剩 3 點氣（一般 coward 會想逃的狀況）
		var b := _battle([player_spec(), rg_ally_spec({ "qi": qi }), monster("m_wolf"), monster("m_bandit")], sd, { "wait_mode": false })
		b.unit(1).spec["ai"] = "melee_basic"   # 玩家也交給 AI（非等待模式），兩方打到結束
		var ev := run_until_over(b, 20000)
		for e in ev:
			var p: Dictionary = e.get("p", {})
			if e.key == "battle_flee" and int(p.get("uid", 0)) == 2:
				fail("隊友不該逃（seed %d）" % sd)
			if int(p.get("atk_uid", 0)) == 2 and not bool(p.get("counter", false)):
				acts += 1
				assert_eq(b.unit(int(p.def_uid)).side, 1, "隊友只打 side 1（seed %d）" % sd)
		assert_true(b.is_over(), "seed %d ends" % sd)
	assert_true(acts > 0, "隊友有出手")

func test_ally_acts_automatically_in_wait_mode() -> void:
	var b := _battle([player_spec(), rg_ally_spec(), monster("m_dummy")], 5)
	place(b, 2, 5, 3)
	place(b, 3, 6, 3)
	var hits := 0
	for i in 4000:
		for e in b.step(Battle.TICK, tables()):
			if int(e.get("p", {}).get("atk_uid", 0)) == 2:
				hits += 1
		if b.state == Battle.State.AWAIT_COMMAND:
			assert_false(b.waiting_humans().any(func(u): return u.uid == 2), "不等隊友下令")
			b.submit(1, { "cmd": "DEFEND" }, tables())
		if hits >= 3:
			break
	assert_true(hits >= 3, "隊友自己出手（%d）" % hits)

func test_non_ally_monster_path_unchanged() -> void:
	# 同一場面：一般怪物（melee_basic）的選擇與以前一樣（只用 arts[0]，打最少氣的、不看玩家位置）
	var b := _battle([player_spec(), monster("m_guiwang", { "side": 1 }), monster("m_wolf", { "side": 0, "peer": 0 })])
	place(b, 1, 4, 3)
	place(b, 2, 5, 3)
	place(b, 3, 5, 4)
	b.unit(1).qi = 500
	var c := BattleAI.choose(b, b.unit(2), tables(), RandomNumberGenerator.new())
	assert_eq(c.cmd, "ART")
	assert_eq(c.art, "mon_guiwang", "怪物只用 arts[0]")
	assert_eq(c.target, [5, 4], "氣最少（野狼）")
