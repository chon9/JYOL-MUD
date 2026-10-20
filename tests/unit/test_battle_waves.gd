extends "res://tests/unit/test_battle_helpers.gd"
## M3A_PLAN 5.9、10.1：3 波接續、battle_wave 事件、最後一波才勝利、no_flee。

func _wave_battle(opts := {}) -> Battle:
	var b := Battle.new(3, 555, default_opts(opts))
	b.add_unit(player_spec({ "attrs": { "agi": 30, "str": 40 } }))
	b.add_unit(monster("m_trainee"))
	b.set_waves([[monster("m_trainee"), monster("m_trainee")], [monster("m_trainee")]])
	b.start(tables())
	return b

func test_three_waves_in_sequence() -> void:
	var b := _wave_battle()
	assert_eq(b.wave_total, 3)
	assert_eq(b.snapshot(tables()).wave, { "n": 1, "total": 3 })
	var r := play(b, [1])
	var ev: Array = r.events
	assert_true(b.is_over())
	assert_eq(b.result_name(), "VICTORY", "最後一波清光才勝利")
	var waves := find(ev, "battle_wave")
	assert_eq(waves.size(), 2)
	assert_eq(waves[0].p, { "n": 2, "total": 3, "bid": 3 })
	assert_eq(waves[1].p.n, 3)
	assert_eq(find(ev, "battle_unit_join").size(), 3, "第二波 2 隻、第三波 1 隻")
	assert_eq(find(ev, "battle_end").size(), 1)
	assert_eq(b.units.size(), 5)
	assert_eq(b.units.filter(func(u): return u.side == 1 and u.is_dead()).size(), 4)
	# battle_end 在最後一個 battle_wave 之後
	var last_wave := -1
	var end_at := -1
	for i in ev.size():
		if ev[i].key == "battle_wave":
			last_wave = i
		if ev[i].key == "battle_end":
			end_at = i
	assert_true(end_at > last_wave)
	assert_eq(b.outcome().wave, { "n": 3, "total": 3 })

func test_wave_spawns_on_right_edge() -> void:
	var b := _wave_battle()
	for i in 4000:
		if b.wave_no >= 2 or b.is_over():
			break
		for peer in [1]:
			var u := b.unit(b.uid_for_peer(peer))
			if u.state == BattleUnit.READY and b.pending_uids().has(u.uid) and u.queued_cmd.is_empty():
				b.submit(peer, auto_cmd(b, peer), tables())
		b.step(Battle.TICK, tables())
	assert_eq(b.wave_no, 2)
	for u in b.units.slice(2):
		assert_eq(u.pos.x, 11, "右側邊緣")
		assert_eq(u.side, 1)
		assert_eq(u.state, BattleUnit.CHARGING)
	assert_false(b.is_over(), "還有敵人")

func test_no_flee_in_wave_battle() -> void:
	var b := _wave_battle({ "no_flee": true })
	run_until_ready(b, 1)
	b.unit(1).pos = b.grid.escape[0]
	assert_eq(b.submit(1, { "cmd": "FLEE" }, tables()), "no_flee")
	assert_eq(b.snapshot(tables()).no_flee, true)

func test_no_waves_is_unchanged() -> void:
	var b := make_battle([player_spec({ "attrs": { "str": 40 } }), monster("m_trainee")], 555)
	assert_eq(b.wave_total, 1)
	play(b, [1])
	assert_eq(b.result_name(), "VICTORY")
