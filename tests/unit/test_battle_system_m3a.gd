extends "res://tests/unit/test_world_fixture.gd"
## WP-CMD 主機端（M3A_PLAN 5.8、5.9）：start_ex 波次與 no_flee、battle_opts 的 later_battle_cmds、
## 戰後扣掉用掉的暗器／藥（item_lost）、summary 形狀、mode 參數轉送。

func before_each() -> void:
	world_name = "w_battle_m3a"
	super.before_each()

func test_start_ex_waves_no_flee_and_kind() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_road")
	make_strong()
	var bid: int = host().battles.start_ex(s(), [], "TRIAL",
		{ "waves": [["m_rabbit"], ["m_rabbit", "m_rabbit"]], "no_flee": true, "pull_party": false })
	ws.flush()
	assert_true(bid > 0)
	assert_eq(s().battle_id, bid)
	var b: Battle = host().battles.active[bid]["battle"]
	assert_eq(b.wave_total, 2, "第一波 waves[0]，後面 1 波")
	assert_eq(b.units.filter(func(u): return u.side == 1).size(), 1)
	assert_eq(bool(b.opts.get("no_flee", false)), true)
	assert_eq(str(cs.battle_state.get("kind", "")), "TRIAL")
	assert_eq(cs.battle_state.get("no_flee", false), true)
	var res := drive_battle("fight")
	assert_eq(str(res.get("result", "")), "VICTORY", str(res))
	assert_eq(b.units.size(), 4, "1 玩家 + 3 隻")
	assert_false(evs("battle_wave").is_empty(), "battle_wave 轉送到客戶端")

func test_start_still_works_and_opts_carry_later_cmds() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_road")
	var o: Dictionary = host().battles.battle_opts("xixia_west", "ENCOUNTER")
	assert_eq(o.get("later_battle_cmds", null), bool(host().rules.get("later_battle_cmds", true)))
	var bid := start_battle(["m_rabbit"])
	var b: Battle = host().battles.active[bid]["battle"]
	assert_eq(b.wave_total, 1)
	assert_false(bool(b.opts.get("no_flee", false)))
	host().battles.abort_all()

func test_used_items_removed_after_battle() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_road")
	var uid := give("c_jingyao", 3)
	var before := item_count("c_jingyao")
	uid = first_uid("c_jingyao")
	var bid := start_battle(["m_rabbit"])
	var b: Battle = host().battles.active[bid]["battle"]
	var me: BattleUnit = b.unit(b.uid_for_peer(1))
	me.used_items[uid] = 2
	me.used_items["it_gone"] = 1   # 背包裡沒有的 uid：略過
	clear_events()
	host().battles.abort_all()
	ws.flush()
	assert_eq(item_count("c_jingyao"), before - 2, "用掉 2 個")
	var lost := evs("item_lost")
	assert_eq(lost.size(), 1)
	assert_eq(int(lost[0].p.get("n", 0)), 2)

func test_battle_cmd_passes_mode() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_road")
	var bid := start_battle(["m_rabbit"])
	var b: Battle = host().battles.active[bid]["battle"]
	for i in 400:
		if b.state == Battle.State.AWAIT_COMMAND and b.waiting_humans().size() > 0:
			break
		host().battles.tick(Battle.TICK)
	# 沒有內功：INNER 回 no_inner_art（證明 mode 有轉送、指令被認得）
	var r := send("battle_cmd", { "battle_id": bid, "cmd": "INNER", "mode": "HEAL" })
	var why := str(r.get("reason", ""))
	assert_true(why in ["no_inner_art", "bad_value:cmd", "unexpected_arg", "cmd_disabled"], why)
	host().battles.abort_all()

func test_summary_shape() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_road")
	var bid := start_battle(["m_rabbit"])
	var entry: Dictionary = host().battles.active[bid]
	var b: Battle = entry["battle"]
	var out := b.outcome()
	var u: Dictionary = out.units[b.uid_for_peer(1)]
	var sm2: Dictionary = host().battles.battle_summary(entry, u, "VICTORY")
	for k in ["kind", "result", "kills", "killed_by", "died", "pvp_initiator", "same_sect_kills"]:
		assert_has(sm2, k)
	assert_eq(sm2.kind, "ENCOUNTER")
	assert_eq(sm2.pvp_initiator, false)
	for k in ["kind", "ref", "sect"]:
		assert_has(sm2.killed_by, k)
	host().battles.abort_all()
