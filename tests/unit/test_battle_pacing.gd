extends "res://tests/unit/test_battle_helpers.gd"
## M2_PLAN 4.6.3、6.1：8 個玩家單位（其中 2 個一直不下令）在等待模式下打到結束，
## 量「每輪等待秒數」：每輪 ≤ wait_mode_round_budget_s + wait_mode_timeout_min_s（預設 45 + 8 = 53 秒）、發呆者被標 afk。

const IDLE_PEERS := [7, 8]

func _eight_vs_wolves(seed_v: int) -> Battle:
	var specs: Array = []
	for peer in range(1, 9):
		specs.append(player_spec({ "peer": peer, "ref": "ch_p%d" % peer, "name": "俠客%d" % peer,
			"attrs": { "str": 40, "con": 40 }, "qi": 400, "qi_max": 400 }))
	for i in 3:
		specs.append(monster("m_wolf", { "qi": 900, "qi_max": 900 }))
	return make_battle(specs, seed_v)

## 回傳 { worst_s, avg_s, rounds, afk: { peer: bool }, over }
func _run(b: Battle, active_peers: Array, max_ticks := Battle.MAX_TICKS) -> Dictionary:
	var worst := 0.0
	var prev := 0.0
	var rounds := 0
	var round_total := 0.0
	var afk := {}
	var await_ticks := 0
	for i in max_ticks:
		if b.is_over():
			break
		for peer in active_peers:
			var uid := b.uid_for_peer(peer)
			var u := b.unit(uid)
			if u != null and u.state == BattleUnit.READY and b.pending_uids().has(uid) and u.queued_cmd.is_empty():
				if b.submit(peer, auto_cmd(b, peer), tables()) != "":
					b.submit(peer, { "cmd": "DEFEND" }, tables())
		if b.state == Battle.State.AWAIT_COMMAND:
			await_ticks += 1
		b.step(Battle.TICK, tables())
		var w := b.round_wait_s()
		worst = maxf(worst, w)
		if w < prev - 0.0001:
			rounds += 1
			round_total += prev
		prev = w
		for peer in IDLE_PEERS:
			var iu := b.unit(b.uid_for_peer(peer))
			if iu != null and iu.afk:
				afk[peer] = true
	return { "worst_s": worst, "avg_s": round_total / maxf(1.0, float(rounds)), "rounds": rounds, "afk": afk,
		"over": b.is_over(), "await_s": await_ticks * Battle.TICK }

func test_eight_players_two_idle_round_budget() -> void:
	var limit := float(default_opts().wait_mode_round_budget_s) + float(default_opts().wait_mode_timeout_min_s)
	assert_eq(limit, 53.0)
	var worst_all := 0.0
	for seed_v in [101, 202, 303]:
		var b := _eight_vs_wolves(seed_v)
		assert_eq(b.humans(), 8)
		var r := _run(b, [1, 2, 3, 4, 5, 6])
		print("      [pacing] seed=%d rounds=%d worst_round_wait=%.1fs avg_round_wait=%.1fs total_await=%.1fs result=%s ticks=%d" % [
			seed_v, r.rounds, r.worst_s, r.avg_s, r.await_s, b.result_name(), b.tick_no])
		assert_true(r.over, "seed %d：打到結束" % seed_v)
		assert_ne_aborted(b, seed_v)
		assert_true(r.worst_s <= limit + 0.0001, "seed %d：每輪等待 %.1f ≤ %.1f 秒" % [seed_v, r.worst_s, limit])
		assert_true(r.afk.get(7, false) and r.afk.get(8, false), "seed %d：一直不下令的兩人被標 afk" % seed_v)
		assert_true(r.rounds >= 2, "至少跑了兩輪")
		worst_all = maxf(worst_all, r.worst_s)
	print("      [pacing] worst round over all seeds: %.1fs (budget %.0fs)" % [worst_all, limit])

func test_mid_join_follows_same_timeouts() -> void:
	# 7 人開打，第 8 人中途加入且從不下令：同樣逾時、被標 afk，每輪仍在預算內
	var specs: Array = []
	for peer in range(1, 8):
		specs.append(player_spec({ "peer": peer, "ref": "ch_p%d" % peer, "attrs": { "str": 40, "con": 40 },
			"qi": 400, "qi_max": 400 }))
	for i in 3:
		specs.append(monster("m_wolf", { "qi": 900, "qi_max": 900 }))
	var b := make_battle(specs, 404)
	for i in 30:
		b.step(Battle.TICK, tables())
		for peer in range(1, 8):
			var uid := b.uid_for_peer(peer)
			if b.pending_uids().has(uid) and b.unit(uid).queued_cmd.is_empty():
				b.submit(peer, { "cmd": "DEFEND" }, tables())
	var uid8 := b.join_unit(player_spec({ "peer": 8, "ref": "ch_p8", "qi": 400, "qi_max": 400 }), tables())
	assert_true(uid8 > 0)
	assert_eq(b.humans(), 8)
	var r := _run(b, [1, 2, 3, 4, 5, 6])
	print("      [pacing] mid-join: rounds=%d worst=%.1fs avg=%.1fs result=%s" % [r.rounds, r.worst_s, r.avg_s, b.result_name()])
	assert_true(r.over)
	assert_true(r.worst_s <= 53.0001, "每輪等待 %.1f ≤ 53" % r.worst_s)
	assert_true(r.afk.get(8, false), "中途加入的發呆者也被標 afk")

func assert_ne_aborted(b: Battle, seed_v: int) -> void:
	assert_true(b.result != Battle.Result.ABORTED, "seed %d：不應該跑到 MAX_TICKS" % seed_v)
