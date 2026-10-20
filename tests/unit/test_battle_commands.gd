extends "res://tests/unit/test_battle_helpers.gd"
## M1_PLAN 3.4.3：每個指令的合法情形與每個原因碼。

## 玩家（機敏 30，先滿條）對木人；回傳已在等待指令的戰鬥
func _ready_battle(pover: Dictionary = {}, monster_id := "m_dummy", opts := {}) -> Battle:
	var spec := player_spec({ "attrs": { "agi": 30 } })
	for k in pover:
		spec[k] = pover[k]
	var b := make_battle([spec, monster(monster_id)], 99, opts)
	run_until_ready(b, 1)
	return b

func test_not_ready_and_bad_cmd() -> void:
	var b := make_battle([player_spec(), monster("m_dummy")])
	assert_eq(b.submit(1, { "cmd": "DEFEND" }, tables()), "not_ready", "還沒滿條")
	run_until_ready(b, 1)
	assert_eq(b.state, Battle.State.AWAIT_COMMAND)
	assert_eq(b.submit(42, { "cmd": "DEFEND" }, tables()), "not_ready", "不是參戰 peer")
	assert_eq(b.submit(1, { "cmd": "JUMP" }, tables()), "bad_cmd")
	assert_eq(b.submit(1, {}, tables()), "bad_cmd")
	assert_eq(b.submit(1, { "cmd": "MOVE" }, tables()), "bad_cmd", "缺 target")
	assert_eq(b.submit(1, { "cmd": "MOVE", "target": [1] }, tables()), "bad_cmd", "target 形狀")
	assert_eq(b.submit(1, { "cmd": "ATTACK" }, tables()), "bad_cmd")
	assert_eq(b.submit(1, { "cmd": "EQUIP" }, tables()), "bad_cmd", "缺 item_uid")
	assert_eq(b.submit(1, { "cmd": "DEFEND" }, tables()), "")

func test_move() -> void:
	var b := _ready_battle()
	var me := b.unit(1)
	assert_eq(me.pos, Vector2i(1, 3))
	assert_eq(b.submit(1, { "cmd": "MOVE", "target": [4, 3] }, tables()), "out_of_range", "超過 2 格")
	assert_eq(b.submit(1, { "cmd": "MOVE", "target": [-1, 3] }, tables()), "out_of_range", "出界")
	assert_eq(b.submit(1, { "cmd": "MOVE", "target": [1, 3] }, tables()), "occupied", "原地（自己占著）")
	place(b, 2, 2, 3)
	assert_eq(b.submit(1, { "cmd": "MOVE", "target": [2, 3] }, tables()), "occupied")
	assert_eq(b.submit(1, { "cmd": "MOVE", "target": [3, 3] }, tables()), "out_of_range", "不能穿越單位")
	assert_eq(b.submit(1, { "cmd": "MOVE", "target": [1, 5] }, tables()), "")
	var ev := b.step(Battle.TICK, tables())
	var mv := find(ev, "battle_move")
	assert_eq(mv.size(), 1)
	assert_eq(mv[0].p.from, [1, 3])
	assert_eq(mv[0].p.to, [1, 5])
	assert_eq(mv[0].p.peer, 1)
	assert_eq(me.pos, Vector2i(1, 5))
	assert_true(approx(me.gauge, 50.0), "MOVE 後時間棒 50")
	assert_eq(me.state, BattleUnit.CHARGING)

func test_attack() -> void:
	var b := _ready_battle()
	assert_eq(b.submit(1, { "cmd": "ATTACK", "target": [5, 5] }, tables()), "no_target", "空格")
	assert_eq(b.submit(1, { "cmd": "ATTACK", "target": [1, 3] }, tables()), "no_target", "自己")
	assert_eq(b.submit(1, { "cmd": "ATTACK", "target": [10, 3] }, tables()), "out_of_range")
	place(b, 2, 2, 3)
	assert_eq(b.submit(1, { "cmd": "ATTACK", "target": [2, 3] }, tables()), "")
	var ev := b.step(Battle.TICK, tables())
	var hits := find(ev, "atk_blade")
	var misses := find(ev, "battle_miss")
	assert_eq(hits.size() + misses.size(), 1, "一次普通攻擊")
	if hits.size() == 1:
		var p: Dictionary = hits[0].p
		assert_eq(p.weapon, "木刀")
		for k in ["bid", "atk_uid", "def_uid", "atk", "def", "atk_peer", "def_peer", "dmg", "part", "crit", "def_qi"]:
			assert_has(p, k)
		assert_eq(p.def_qi, b.unit(2).qi)
		assert_true(BattleRules.PARTS.has(p.part))

func test_art_reasons() -> void:
	var b := _ready_battle({ "weapon": bare(), "neili": 10, "neili_max": 50,
		"skills": { "sl_changquan": 10, "hs_jianfa": 5, "test_aoe": 1, "hs_pishiquan": 1, "sl_xinfa": 5 },
		"arts": ["sl_changquan", "hs_jianfa", "test_aoe", "hs_pishiquan", "sl_xinfa"] })
	place(b, 2, 2, 3)
	var t := tables()
	var art := func(a: String, m: String, tgt: Array, tenths := 10) -> String:
		return b.submit(1, { "cmd": "ART", "art": a, "move": m, "power_tenths": tenths, "target": tgt }, t)
	assert_eq(art.call("mon_bite", "mon_bite_1", [2, 3]), "art_unknown", "不在 arts")
	assert_eq(art.call("sl_xinfa", "x", [2, 3]), "art_unknown", "內功不能出招")
	assert_eq(art.call("sl_changquan", "sl_cq_2", [2, 3]), "move_locked", "30 級才解鎖")
	assert_eq(art.call("sl_changquan", "nope", [2, 3]), "move_locked", "不屬於此武功")
	assert_eq(art.call("hs_jianfa", "hs_jf_1", [2, 3]), "need_weapon", "空手用劍法")
	# M3a：範圍招式可用；直線（LINE）的中心格不在 8 方向上 → bad_direction（M3A_PLAN 5.2）
	assert_eq(art.call("test_aoe", "t_aoe_1", [3, 4]), "bad_direction")
	assert_eq(art.call("sl_changquan", "sl_cq_1", [5, 5]), "no_target")
	assert_eq(art.call("sl_changquan", "sl_cq_1", [1, 3]), "no_target", "自己")
	place(b, 2, 3, 3)
	assert_eq(art.call("sl_changquan", "sl_cq_1", [3, 3]), "out_of_range", "射程 1")
	place(b, 2, 2, 3)
	assert_eq(art.call("hs_pishiquan", "hs_pishi_1", [2, 3]), "not_enough_neili", "15×10/5 = 30 > 10")
	assert_eq(art.call("test_aoe", "t_jing_1", [2, 3]), "not_enough_jing")
	assert_eq(art.call("sl_changquan", "sl_cq_1", [2, 3], 11), "bad_cmd", "成數 1–10")
	assert_eq(art.call("sl_changquan", "sl_cq_1", [2, 3], 0), "bad_cmd")
	assert_eq(art.call("hs_pishiquan", "hs_pishi_1", [2, 3], 3), "", "15×3/5 = 9 ≤ 10")
	var ev := b.step(Battle.TICK, t)
	assert_eq(b.unit(1).neili, 1, "扣內力 9")
	var hit := find(ev, "move_fist_basic")
	var miss := find(ev, "battle_miss")
	assert_eq(hit.size() + miss.size(), 1)
	if hit.size() == 1:
		assert_eq(hit[0].p.art, "劈石破玉拳")
		assert_eq(hit[0].p.move, "劈石破玉")
		assert_eq(hit[0].p.tenths, 3)
		assert_eq(hit[0].p.atk_neili, 1)
		assert_eq(find(ev, "battle_status_on").size(), 1, "status_chance 1.0 → 內傷")
		assert_true(b.unit(2).statuses.has("inner_wound"))
	else:
		assert_eq(miss[0].p.move, "劈石破玉")

func test_art_with_matching_weapon() -> void:
	var b := _ready_battle({ "weapon": weapon("it_0002", "w_mujian", "SWORD", 4, "木劍"),
		"skills": { "hs_jianfa": 5 }, "arts": ["hs_jianfa"] })
	place(b, 2, 2, 3)
	assert_eq(b.submit(1, { "cmd": "ART", "art": "hs_jianfa", "move": "hs_jf_1", "power_tenths": 10, "target": [2, 3] }, tables()), "")

func test_defend_and_rest() -> void:
	var b := _ready_battle({ "qi": 100, "neili": 0, "neili_max": 100 })
	assert_eq(b.submit(1, { "cmd": "DEFEND" }, tables()), "")
	var ev := b.step(Battle.TICK, tables())
	assert_eq(find(ev, "battle_defend").size(), 1)
	assert_true(b.unit(1).defending)
	run_until_ready(b, 1)
	assert_eq(b.submit(1, { "cmd": "REST" }, tables()), "")
	var qi_before := b.unit(1).qi
	var neili_before := b.unit(1).neili
	ev = b.step(Battle.TICK, tables())
	var r := find(ev, "battle_rest")
	assert_eq(r.size(), 1)
	assert_eq(r[0].p.qi_gain, 9, "180×5%")
	assert_eq(r[0].p.neili_gain, 10, "100×10%")
	assert_eq(b.unit(1).qi, qi_before + 9)
	assert_eq(b.unit(1).neili, neili_before + 10)
	assert_false(b.unit(1).defending, "下次行動後解除防禦")
	run_until_ready(b, 1)
	b.unit(1).statuses["inner_wound"] = 3
	assert_eq(b.submit(1, { "cmd": "REST" }, tables()), "status_blocked", "內傷禁止休息")

func test_rest_caps_at_max() -> void:
	var b := _ready_battle({ "qi": 178 })
	b.submit(1, { "cmd": "REST" }, tables())
	var ev := b.step(Battle.TICK, tables())
	assert_eq(find(ev, "battle_rest")[0].p.qi_gain, 2)
	assert_eq(b.unit(1).qi, 180)

func test_equip() -> void:
	var b := _ready_battle()
	assert_eq(b.submit(1, { "cmd": "EQUIP", "item_uid": "it_9999" }, tables()), "no_item")
	assert_eq(b.submit(1, { "cmd": "EQUIP", "item_uid": "it_0002" }, tables()), "")
	var ev := b.step(Battle.TICK, tables())
	assert_eq(find(ev, "battle_equip")[0].p.item_name, "木劍")
	assert_eq(b.unit(1).weapon_type(), "SWORD")
	run_until_ready(b, 1)
	assert_eq(b.submit(1, { "cmd": "EQUIP", "item_uid": "" }, tables()), "", "空手")
	ev = b.step(Battle.TICK, tables())
	assert_eq(find(ev, "battle_equip")[0].p.item_name, "空手")
	assert_eq(b.unit(1).weapon_type(), "FIST")
	assert_eq(b.outcome().units[1].weapon_uid, "")

func test_flee() -> void:
	var b := _ready_battle()
	assert_eq(b.submit(1, { "cmd": "FLEE" }, tables()), "not_on_escape")
	var esc: Vector2i = b.grid.escape[0]
	b.unit(1).pos = esc
	assert_eq(b.submit(1, { "cmd": "FLEE" }, tables()), "")
	var ev := b.step(Battle.TICK, tables())
	assert_eq(find(ev, "battle_flee").size(), 1)
	assert_eq(b.unit(1).state, BattleUnit.FLED)
	assert_true(b.is_over())
	assert_eq(b.result_name(), "ALL_FLED")
	assert_eq(b.submit(1, { "cmd": "DEFEND" }, tables()), "battle_over")

func test_battle_over_after_abort() -> void:
	var b := _ready_battle()
	var ev := b.abort()
	assert_eq(keys_of(ev), ["battle_end"])
	assert_eq(ev[0].p.result, "ABORTED")
	assert_eq(ev[0].get("ui", false), true)
	assert_eq(b.submit(1, { "cmd": "DEFEND" }, tables()), "battle_over")
	assert_eq(b.abort(), [], "第二次 abort 不再產生事件")

func test_invalidated_command_falls_back_to_defend() -> void:
	# 已排入的 ATTACK 在結算前目標消失 → 改為「防」
	var b := _ready_battle()
	place(b, 2, 2, 3)
	assert_eq(b.submit(1, { "cmd": "ATTACK", "target": [2, 3] }, tables()), "")
	place(b, 2, 9, 3)
	var ev := b.step(Battle.TICK, tables())
	assert_eq(find(ev, "battle_defend").size(), 1)
	assert_eq(find(ev, "atk_blade").size() + find(ev, "battle_miss").size(), 0)
