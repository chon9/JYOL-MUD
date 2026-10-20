extends "res://tests/test_case.gd"
## WP-UI：BattleViewModel（M1_PLAN 3.12）：以 3.9.3 快照初始化、套用 3.8.4 事件、時間棒外插、輪到我判定

static func state(wait_mode := true) -> Dictionary:
	return {
		"bid": 3, "w": 12, "h": 8, "tick": 0, "wait_mode": wait_mode, "my_uid": 1,
		"escape": [[0, 6], [5, 0]],
		"units": [
			{ "uid": 1, "name": "測試俠客", "side": 0, "kind": "PLAYER", "peer": 1, "pos": [1, 3],
			  "qi": 180, "qi_max": 180, "neili": 20, "neili_max": 50, "jing": 92, "jing_max": 92,
			  "gauge": 0.0, "rate": 7.0, "state": "CHARGING", "move_range": 2,
			  "weapon": { "uid": "it_0001", "name": "木刀", "weapon_type": "BLADE" },
			  "weapon_options": [ { "uid": "it_0001", "name": "木刀", "weapon_type": "BLADE" } ],
			  "arts": [ { "id": "sl_changquan", "name": "少林長拳", "category": "FIST", "level": 10,
				"moves": [
					{ "id": "sl_cq_1", "name": "黑虎掏心", "unlock_level": 1, "range": 1, "cost_inner": 0, "cost_jing": 0, "usable": true },
					{ "id": "sl_cq_2", "name": "雙龍搶珠", "unlock_level": 30, "range": 1, "cost_inner": 5, "cost_jing": 0, "usable": false } ] } ] },
			{ "uid": 2, "name": "野兔", "side": 1, "kind": "MONSTER", "peer": 0, "pos": [10, 3],
			  "qi": 60, "qi_max": 60, "gauge": 0.0, "rate": 6.25, "state": "CHARGING" },
		],
	}

func ev(key: String, p: Dictionary, ui := false) -> Dictionary:
	var e := { "seq": 1, "t": 0.0, "ch": "BATTLE", "key": key, "p": p, "bid": 3 }
	if ui:
		e["ui"] = true
	return e

func test_init_from_state() -> void:
	var vm := BattleViewModel.from_state(state())
	assert_eq(vm.bid, 3)
	assert_eq(vm.my_uid, 1)
	assert_eq(vm.units.size(), 2)
	assert_eq(vm.unit(1)["pos"], Vector2i(1, 3))
	assert_true(vm.is_escape(Vector2i(0, 6)))
	assert_false(vm.is_escape(Vector2i(1, 3)))
	assert_eq(vm.unit_at(Vector2i(10, 3)), 2)
	assert_true(vm.is_enemy(2))
	assert_false(vm.is_enemy(1))

func test_gauge_extrapolation_and_cap() -> void:
	var vm := BattleViewModel.from_state(state())
	assert_eq(vm.gauge_at(1, 10.0), 70.0)
	assert_eq(vm.gauge_at(1, 100.0), 100.0, "capped")
	vm.apply_event(ev("battle_gauges", { "tick": 20, "units": [[1, 40.0, 7.0, true], [2, 50.0, 6.25, false]] }, true))
	assert_eq(vm.anchor_tick, 20.0)
	assert_eq(vm.gauge_at(1, 30.0), 100.0, "40 + 70 capped")
	assert_eq(vm.gauge_at(1, 25.0), 75.0)
	assert_eq(vm.gauge_at(2, 99.0), 50.0, "not charging stays")
	assert_eq(vm.gauge_at(1, 10.0), 40.0, "before anchor clamps to anchor")

func test_wait_mode_turn_and_submit() -> void:
	var vm := BattleViewModel.from_state(state(true))
	assert_false(vm.is_my_turn(1000.0), "wait mode needs battle_await")
	vm.apply_event(ev("battle_await", { "units": [1], "deadline_tick": 300 }, true))
	vm.apply_event(ev("battle_gauges", { "tick": 100, "units": [[1, 100.0, 7.0, false], [2, 30.0, 6.25, false]] }, true))
	assert_true(vm.is_my_turn(100.0))
	assert_eq(vm.seconds_left(100.0), 20.0)
	vm.mark_submitted()
	assert_false(vm.is_my_turn(100.0))
	# 結算後時間棒重新流動 → 清掉等待
	vm.apply_event(ev("battle_gauges", { "tick": 101, "units": [[1, 0.0, 7.0, true], [2, 30.0, 6.25, true]] }, true))
	assert_eq(vm.await_units, [])
	assert_false(vm.is_my_turn(101.0))

func test_non_wait_mode_turn_by_gauge() -> void:
	var vm := BattleViewModel.from_state(state(false))
	assert_false(vm.is_my_turn(5.0))
	assert_true(vm.is_my_turn(15.0), "7/tick × 15 ≥ 100")
	vm.mark_submitted()
	assert_false(vm.is_my_turn(15.0))

func test_timeout_and_afk() -> void:
	var vm := BattleViewModel.from_state(state())
	vm.apply_event(ev("battle_await", { "units": [1], "deadline_tick": 200 }, true))
	vm.apply_event(ev("battle_timeout", { "uid": 1, "name": "測試俠客", "peer": 1 }))
	assert_false(vm.await_units.has(1))
	assert_false(vm.afk.has(1))
	vm.apply_event(ev("battle_timeout", { "uid": 1, "name": "測試俠客", "peer": 1 }))
	assert_true(vm.afk.has(1), "two timeouts → afk")
	vm.apply_event(ev("battle_move", { "uid": 1, "name": "測試俠客", "peer": 1, "from": [1, 3], "to": [2, 3] }))
	assert_false(vm.afk.has(1), "acting clears afk")
	assert_eq(vm.unit(1)["pos"], Vector2i(2, 3))

func test_hit_rest_equip_death_events() -> void:
	var vm := BattleViewModel.from_state(state())
	vm.apply_event(ev("move_fist_basic", { "atk_uid": 1, "def_uid": 2, "atk": "測試俠客", "def": "野兔", "atk_peer": 1, "def_peer": 0,
		"art": "少林長拳", "move": "黑虎掏心", "tenths": 10, "dmg": 12, "part": "胸口", "crit": false, "def_qi": 48, "atk_neili": 15 }))
	assert_eq(vm.unit(2)["qi"], 48)
	assert_eq(vm.unit(1)["neili"], 15)
	vm.apply_event(ev("atk_blade", { "atk_uid": 2, "def_uid": 1, "atk": "野兔", "def": "測試俠客", "atk_peer": 0, "def_peer": 1,
		"weapon": "拳腳", "dmg": 3, "part": "左腿", "crit": false, "def_qi": 177 }))
	assert_eq(vm.unit(1)["qi"], 177)
	vm.apply_event(ev("battle_rest", { "uid": 1, "name": "測試俠客", "peer": 1, "qi_gain": 3, "neili_gain": 5, "qi": 180, "neili": 20 }))
	assert_eq(vm.unit(1)["qi"], 180)
	assert_eq(vm.unit(1)["neili"], 20)
	vm.apply_event(ev("battle_equip", { "uid": 1, "name": "測試俠客", "peer": 1, "item_name": "" }))
	assert_eq(vm.unit(1)["weapon"]["uid"], "")
	vm.apply_event(ev("battle_equip", { "uid": 1, "name": "測試俠客", "peer": 1, "item_name": "木刀" }))
	assert_eq(vm.unit(1)["weapon"]["uid"], "it_0001")
	vm.apply_event(ev("battle_status_on", { "uid": 1, "name": "測試俠客", "peer": 1, "status": "inner_wound", "status_name": "內傷" }))
	assert_true(vm.unit(1)["statuses"].has("inner_wound"))
	vm.apply_event(ev("battle_status_off", { "uid": 1, "name": "測試俠客", "peer": 1, "status": "inner_wound", "status_name": "內傷" }))
	assert_false(vm.unit(1)["statuses"].has("inner_wound"))
	vm.apply_event(ev("battle_kill", { "uid": 2, "name": "野兔", "peer": 0, "by": 1 }))
	assert_false(vm.is_active(2))
	assert_eq(vm.unit_at(Vector2i(10, 3)), 0, "dead units do not occupy")
	vm.apply_event(ev("battle_end", { "result": "VICTORY" }, true))
	assert_true(vm.ended)
	assert_eq(vm.result, "VICTORY")
	assert_false(vm.is_my_turn(9999.0))

func test_flee_and_other_battle_ignored() -> void:
	var vm := BattleViewModel.from_state(state())
	var other := ev("battle_move", { "uid": 1, "from": [1, 3], "to": [5, 5] })
	other["bid"] = 99
	assert_false(vm.apply_event(other), "other bid ignored")
	assert_eq(vm.unit(1)["pos"], Vector2i(1, 3))
	assert_false(vm.apply_event({ "ch": "SYSTEM", "key": "buy", "p": {} }))
	vm.apply_event(ev("battle_flee", { "uid": 2, "name": "野兔", "peer": 0 }))
	assert_eq(vm.unit(2)["state"], "FLED")
	assert_false(vm.is_active(2))

func test_move_targets_bfs_blocks_units() -> void:
	var vm := BattleViewModel.from_state(state())
	var t := vm.move_targets()
	# 從 (1,3) 走 2 步、4 方向：菱形 12 格，扣掉格子外的 (-1,3) = 11 格
	assert_eq(t.size(), 11)
	assert_false(t.has(Vector2i(-1, 3)), "outside grid")
	assert_true(t.has(Vector2i(3, 3)))
	assert_true(t.has(Vector2i(0, 2)))
	assert_false(t.has(Vector2i(1, 3)), "own cell excluded")
	# 在 (2,3) 放一個敵人 → (2,3)、(3,3) 不可達（不能穿越）
	vm.apply_event(ev("battle_move", { "uid": 2, "from": [10, 3], "to": [2, 3] }))
	t = vm.move_targets()
	assert_false(t.has(Vector2i(2, 3)))
	assert_false(t.has(Vector2i(3, 3)))
	assert_true(t.has(Vector2i(2, 2)))
	assert_eq(vm.enemy_cells_within(1), [Vector2i(2, 3)])

func test_edge_of_grid_and_escape() -> void:
	var s := state()
	s["units"][0]["pos"] = [0, 6]
	var vm := BattleViewModel.from_state(s)
	assert_true(vm.on_escape())
	for c in vm.move_targets():
		assert_true(vm.in_grid(c), "in grid %s" % str(c))

func test_inner_cost_formula() -> void:
	assert_eq(UiKeys.inner_cost(5, 10), 10)
	assert_eq(UiKeys.inner_cost(5, 1), 1)
	assert_eq(UiKeys.inner_cost(6, 3), 4)   # ceil(3.6)
	assert_eq(UiKeys.inner_cost(0, 10), 0)
