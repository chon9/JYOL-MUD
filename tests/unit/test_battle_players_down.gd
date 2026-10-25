extends "res://tests/unit/test_battle_helpers.gd"
## ROGUE WP-ALLY（ROGUE_PLAN §4.4、O6）：opts.end_on_players_down —— 我方玩家全倒就判負（隊友還活著也一樣）；
## 沒有這個選項的戰鬥照舊（我方有任何活人就繼續）。

static func rg_ally_spec() -> Dictionary:
	return monster("m_guiwang", { "kind": "ALLY", "ai": "ally", "side": 0, "peer": 0, "rg_ally": "1", "name": "測試隊友" })

func _battle(opts: Dictionary, seed_v := 21) -> Battle:
	var b := Battle.new(7, seed_v, default_opts(opts))
	b.add_unit(player_spec())
	b.add_unit(rg_ally_spec())
	b.add_unit(monster("m_wolf"))
	b.start(tables())
	return b

func test_players_down_defeat_even_if_ally_alive() -> void:
	var b := _battle({ "end_on_players_down": true })
	BattleRules.kill(b, b.unit(1), b.unit(3))
	assert_true(b._check_end(tables()), "玩家倒下 → 結束")
	assert_eq(b.result_name(), "DEFEAT")
	assert_true(b.unit(2).is_active(), "隊友還活著")
	assert_eq(b.winner_side(), 1, "side 1 還有人 → 敵方勝")
	assert_eq(BattleSystem.relative_result(b.outcome(), 0), "DEFEAT")
	var ev := b.drain_events()
	assert_true(find(ev, "battle_end").size() == 1, "battle_end 事件")

func test_without_option_battle_goes_on() -> void:
	var b := _battle({})
	BattleRules.kill(b, b.unit(1), b.unit(3))
	assert_false(b._check_end(tables()), "沒有 end_on_players_down：隊友還在就繼續")
	assert_false(b.is_over())
	var b2 := _battle({ "end_on_players_down": false })
	BattleRules.kill(b2, b2.unit(1), b2.unit(3))
	assert_false(b2._check_end(tables()))

func test_option_without_player_units_is_ignored() -> void:
	var b := Battle.new(7, 3, default_opts({ "end_on_players_down": true }))
	b.add_unit(rg_ally_spec())
	b.add_unit(monster("m_wolf"))
	b.start(tables())
	assert_false(b._check_end(tables()), "side 0 沒有玩家單位 → 不套用")

func test_players_alive_keeps_going_and_victory_still_works() -> void:
	var b := _battle({ "end_on_players_down": true })
	assert_false(b._check_end(tables()))
	BattleRules.kill(b, b.unit(2), b.unit(3))
	assert_false(b._check_end(tables()), "只有隊友倒下：繼續")
	BattleRules.kill(b, b.unit(3), b.unit(1))
	assert_true(b._check_end(tables()))
	assert_eq(b.result_name(), "VICTORY")

func test_full_battle_ends_when_player_falls() -> void:
	# 玩家很弱、隊友（鬼王級）很強、對手山賊：沒有選項時常常隊友把山賊打死（VICTORY）；有選項時玩家一倒就 DEFEAT
	var defeats_with := 0
	var player_dead_wins_without := 0
	for sd in [1, 2, 3, 4, 5, 6]:
		for with_opt in [true, false]:
			var b := Battle.new(7, sd, default_opts({ "wait_mode": false, "end_on_players_down": with_opt }))
			b.add_unit(player_spec({ "qi": 5, "qi_max": 180, "ai": "melee_basic" }))
			b.add_unit(rg_ally_spec())
			b.add_unit(monster("m_bandit"))
			b.start(tables())
			place(b, 1, 5, 3)   # 玩家貼著山賊；隊友在遠處
			place(b, 3, 6, 3)
			place(b, 2, 0, 0)
			run_until_over(b, 20000)
			var pdead := b.unit(1).is_dead()
			if with_opt:
				if pdead:
					assert_eq(b.result_name(), "DEFEAT", "seed %d：玩家倒下 → 判負" % sd)
					defeats_with += 1
			elif pdead and b.result_name() == "VICTORY":
				player_dead_wins_without += 1
	assert_true(defeats_with > 0, "有選項時至少一場玩家倒下判負")
	assert_true(player_dead_wins_without > 0, "沒有選項時隊友可以代打到勝利（舊規則不變）")
