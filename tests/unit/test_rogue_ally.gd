extends "res://tests/unit/test_battle_helpers.gd"
## ROGUE WP-ALLY（ROGUE_PLAN §4.1、§4.2、§4.5、§9.1）：RogueAlly.spec_for 的規格形狀、份額縮放、qi_pct；apply_outcome；
## BattleSystem._rogue_ally_units 放進戰場；battle_summary 的 killed_by.kind。
## 只依賴 tests/fixtures/battle_tables.json ＋本地假 NPC 列（不需要 WP-RUN 的資料）。

const NPC_ID := "n_t_hero"

static func ally_tables() -> Dictionary:
	var t: Dictionary = tables().duplicate()
	t["npcs"] = { NPC_ID: { "id": NPC_ID, "name": "測試大俠客", "short": "大俠" } }
	return t

static func ally(over: Dictionary = {}) -> Dictionary:
	var a := { "slot": 1, "card_id": "rg_c_ally_test", "monster": "m_wolf", "npc": NPC_ID, "name": "",
		"share": 0.6, "qi_pct": 1.0, "alive": true }
	a.merge(over, true)
	return a

func test_rogue_ally_spec_shape() -> void:
	var s := RogueAlly.spec_for(ally(), 0.0, ally_tables())
	assert_eq(s.kind, "ALLY")
	assert_eq(s.kind, RogueAlly.KIND)
	assert_eq(s.ai, "ally")
	assert_eq(s.side, 0)
	assert_eq(s.peer, 0)
	assert_eq(s.rg_ally, "1", "rg_ally = slot（字串）")
	assert_eq(s.ref, NPC_ID, "ref＝NPC id（立繪）")
	assert_eq(s.npc, NPC_ID)
	assert_eq(s.name, "測試大俠客")
	assert_eq(s.short, "大俠")
	assert_eq(s.monster_row, "m_wolf", "數值仍是怪物列")
	assert_eq(int(s.qi), int(s.qi_max), "qi_pct 1 → 滿氣")
	assert_eq(int(s.qi_max), 250, "沒有戰力（0）→ 不縮放")
	assert_eq(int(s.neili), int(s.neili_max), "內力全滿")
	var u := BattleUnit.new(1, s)
	assert_eq(u.kind(), "ALLY")
	assert_false(u.is_player(), "隊友不是玩家單位")
	assert_true(u.is_ai())
	assert_eq(u.ai_kind(), "ally")

func test_rogue_ally_name_override_and_fallbacks() -> void:
	var s := RogueAlly.spec_for(ally({ "name": "小黃" }), 0.0, ally_tables())
	assert_eq(s.name, "小黃", "卡上的名字優先")
	var s2 := RogueAlly.spec_for(ally({ "npc": "" }), 0.0, ally_tables())
	assert_eq(s2.ref, "m_wolf", "沒有 NPC → 怪物立繪")
	assert_eq(s2.name, str(tables().monsters.m_wolf.name))
	var s3 := RogueAlly.spec_for(ally({ "npc": "n_missing" }), 0.0, ally_tables())
	assert_eq(s3.ref, "m_wolf", "NPC 列不存在 → 照怪物")
	assert_eq(RogueAlly.spec_for(ally({ "monster": "m_nope" }), 100.0, ally_tables()), {}, "資料缺 → {}")
	assert_eq(RogueAlly.spec_for(ally({ "monster": "" }), 100.0, ally_tables()), {})

func test_rogue_ally_qi_pct_carries_over() -> void:
	var s := RogueAlly.spec_for(ally({ "qi_pct": 0.4 }), 0.0, ally_tables())
	assert_eq(int(s.qi), 100, "250 × 0.4")
	var s0 := RogueAlly.spec_for(ally({ "qi_pct": 0.0 }), 0.0, ally_tables())
	assert_eq(int(s0.qi), 1, "至少 1")

func test_rogue_ally_scaled_to_share() -> void:
	var t := ally_tables()
	var base := RogueAlly.spec_for(ally(), 0.0, t)
	if not ResourceLoader.exists(RogueAlly.POWER_PATH):
		# RoguePower（WP-RUN）還沒合併：spec_for 不縮放（容錯，ROGUE_PLAN §0.1 #5）
		var s := RogueAlly.spec_for(ally(), 500.0, t)
		assert_eq(int(s.qi_max), int(base.qi_max), "no RoguePower → unscaled")
		return
	var rp: Script = load(RogueAlly.POWER_PATH)
	var p0 := float(rp.call("unit_power", base, t))
	assert_true(p0 > 0.0, "unit_power > 0")
	for share in [0.35, 0.6, 0.9]:
		var my_power := p0 * 2.0
		var target: float = my_power * share
		var s := RogueAlly.spec_for(ally({ "share": share }), my_power, t)
		var p := float(rp.call("unit_power", s, t))
		assert_true(absf(p - target) <= target * 0.10, "share %.2f: power %.1f ≈ target %.1f" % [share, p, target])
		assert_eq(s.kind, "ALLY", "縮放後形狀不變")
		assert_eq(s.ai, "ally")
		assert_eq(s.side, 0)
		assert_eq(int(s.qi), int(s.qi_max))
	# 數值列遠強於玩家（縮放器夾在 s = 0.5 仍太強）→ 第二段削弱：仍然落在份額附近
	var tiny := p0 * 0.05
	var s_t := RogueAlly.spec_for(ally({ "share": 0.5 }), tiny / 0.5, t)
	var p_t := float(rp.call("unit_power", s_t, t))
	assert_true(p_t <= tiny * 1.10, "weakened: %.2f ≤ %.2f" % [p_t, tiny * 1.1])
	assert_true(s_t.has("rg_weaken"))
	assert_true(int(s_t.qi) >= 1 and int(s_t.qi) == int(s_t.qi_max))
	var w := RogueAlly.weaken(base, 0.5)
	assert_eq(int(w.qi_max), 125)
	assert_true(float(rp.call("unit_power", w, t)) < p0, "削弱單調變弱")
	# 份額越高越強
	var weak := RogueAlly.spec_for(ally({ "share": 0.35 }), p0 * 2.0, t)
	var strong := RogueAlly.spec_for(ally({ "share": 0.9 }), p0 * 2.0, t)
	assert_true(float(rp.call("unit_power", strong, t)) > float(rp.call("unit_power", weak, t)), "神 > 凡")

func test_rogue_ally_apply_outcome() -> void:
	var a := ally({ "qi_pct": 0.9 })
	var dead := RogueAlly.apply_outcome(a, { "died": true, "qi": 1, "qi_max": 250 })
	assert_false(dead.alive)
	assert_eq(float(dead.qi_pct), 0.0)
	assert_true(bool(a.alive), "原字典不變")
	assert_eq(float(a.qi_pct), 0.9)
	var hurt := RogueAlly.apply_outcome(a, { "died": false, "alive": true, "qi": 50, "qi_max": 200 })
	assert_true(hurt.alive)
	assert_true(approx(float(hurt.qi_pct), 0.25))
	var no_max := RogueAlly.apply_outcome(a, { "died": false, "qi": 50 })
	assert_true(approx(float(no_max.qi_pct), 0.9), "沒有 qi_max → qi_pct 不變")
	var dead2 := RogueAlly.apply_outcome(a, { "alive": false, "qi": 1 })
	assert_false(dead2.alive, "alive=false 也算倒下")
	assert_true(RogueAlly.restore(hurt, 0.35, false).qi_pct > 0.59 and RogueAlly.restore(hurt, 0.35, false).qi_pct < 0.61, "+0.35")
	assert_eq(float(RogueAlly.restore(hurt, 0.35, true).qi_pct), 1.0, "首領全滿")
	assert_eq(float(RogueAlly.restore(hurt, 0.9, false).qi_pct), 1.0, "夾上限")
	assert_false(RogueAlly.restore(dead, 0.35, true).alive, "倒下的不回復")

func test_rogue_ally_apply_battle() -> void:
	var t := ally_tables()
	var a1 := ally({ "slot": 1 })
	var a2 := ally({ "slot": 2, "npc": "", "monster": "m_bandit" })
	var b := Battle.new(3, 5, default_opts({ "wait_mode": false }))
	b.add_unit(player_spec())
	var u1 := b.add_unit(RogueAlly.spec_for(a1, 0.0, t))
	var u2 := b.add_unit(RogueAlly.spec_for(a2, 0.0, t))
	b.add_unit(monster("m_wolf"))
	b.start(tables())
	b.unit(u1).qi = 125
	BattleRules.kill(b, b.unit(u2), b.unit(4))
	assert_eq(RogueAlly.ally_units(b).size(), 2)
	var out := RogueAlly.unit_out(b.unit(u1))
	assert_eq(out.rg_ally, "1")
	assert_eq(int(out.qi_max), 250)
	var res := RogueAlly.apply_battle([a1, a2], b)
	assert_eq(res.allies.size(), 2)
	assert_true(res.allies[0].alive)
	assert_true(approx(float(res.allies[0].qi_pct), 0.5))
	assert_false(res.allies[1].alive)
	assert_eq(res.fallen, [str(tables().monsters.m_bandit.name)])

func test_rogue_ally_units_enter_battle() -> void:
	var bs := BattleSystem.new(null)
	var b := Battle.new(9, 1, default_opts())
	b.add_unit(player_spec())
	var t := ally_tables()
	var raw := RogueAlly.spec_for(ally(), 0.0, t)
	raw["side"] = 1   # 就算給錯邊也放在玩家這邊
	raw["peer"] = 7
	var entry := { "battle": b }
	bs._rogue_ally_units(entry, b, { "ally_specs": [raw, RogueAlly.spec_for(ally({ "slot": 2 }), 0.0, t),
		RogueAlly.spec_for(ally({ "slot": 3 }), 0.0, t), {}] })
	assert_eq(b.units.size(), 3, "玩家＋最多 2 位隊友")
	for u in b.units.slice(1):
		assert_eq(u.side, 0)
		assert_eq(u.peer, 0)
		assert_eq(u.kind(), "ALLY")
		assert_eq(u.ai_kind(), "ally")
	assert_eq(int(entry.get("rogue_allies", 0)), 2)
	bs._rogue_ally_units(entry, b, {})
	assert_eq(b.units.size(), 3, "沒有 ally_specs → 不動")
	b.add_unit(monster("m_wolf"))
	b.start(tables())
	for u in b.units:
		if u.side == 0:
			assert_true(u.pos.x < Battle.W / 2, "隊友站左側（BattleGrid.place_units）")

func test_rogue_ally_killed_by_kind_in_summary() -> void:
	var bs := BattleSystem.new(null)
	var b := Battle.new(9, 1, default_opts())
	var p := b.add_unit(player_spec())
	var a := b.add_unit(RogueAlly.spec_for(ally(), 0.0, ally_tables()))
	var m := b.add_unit(monster("m_wolf"))
	b.start(tables())
	var entry := { "battle": b, "kind": "ROGUE", "opts": {} }
	var s1 := bs.battle_summary(entry, { "uid": p, "killed_by": a }, "DEFEAT")
	assert_eq(s1.killed_by.kind, "ALLY", "k.kind() 取代 PLAYER／MONSTER 二分")
	var s2 := bs.battle_summary(entry, { "uid": p, "killed_by": m }, "DEFEAT")
	assert_eq(s2.killed_by.kind, "MONSTER", "怪物照舊")
	var s3 := bs.battle_summary(entry, { "uid": m, "killed_by": p }, "VICTORY")
	assert_eq(s3.killed_by.kind, "PLAYER", "玩家照舊")
	assert_eq(s1.allies, [], "summary.allies 只列玩家（隊友不是合體夥伴）")
