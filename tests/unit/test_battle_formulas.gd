extends "res://tests/unit/test_battle_helpers.gd"
## M1_PLAN 4.6–4.7 每條公式的數值例。

func _u(spec: Dictionary) -> BattleUnit:
	return BattleUnit.new(1, spec)

func _row(art_id: String) -> Dictionary:
	var r: Dictionary = tables().martial_arts[art_id].duplicate()
	r["id"] = art_id
	return r

func _move(art_id: String, idx: int) -> Dictionary:
	return tables().martial_arts[art_id].moves[idx]

func test_atb_gain() -> void:
	var t := tables()
	assert_true(approx(BattleFormulas.atb_gain(_u(player_spec()), t), 7.0), "4 + 20×0.15")
	var u := _u(player_spec({ "skills": { "basic_body": 10 }, "lightness": 20 }))
	assert_true(approx(BattleFormulas.atb_gain(u, t), 7.7), "+ 身法×0.03 + 輕功×0.02")
	var heavy := _u(player_spec({ "carry_ratio": 0.81 }))
	assert_true(approx(BattleFormulas.atb_gain(heavy, t), 4.9), "負重 > 0.8 → ×0.7")
	var edge := _u(player_spec({ "carry_ratio": 0.8 }))
	assert_true(approx(BattleFormulas.atb_gain(edge, t), 7.0), "負重 = 0.8 不減速")

func test_move_range() -> void:
	assert_eq(BattleFormulas.move_range(_u(player_spec())), 2)
	assert_eq(BattleFormulas.move_range(_u(player_spec({ "lightness": 24 }))), 2)
	assert_eq(BattleFormulas.move_range(_u(player_spec({ "lightness": 25 }))), 3)
	assert_eq(BattleFormulas.move_range(_u(player_spec({ "lightness": 50 }))), 4)

func test_power_factor_and_mastery() -> void:
	assert_true(approx(BattleFormulas.power_factor(10, 0), 1.05))
	assert_true(approx(BattleFormulas.power_factor(1, 0), 0.60))
	assert_true(approx(BattleFormulas.power_factor(5, 119), 0.80))
	assert_true(approx(BattleFormulas.power_factor(1, 120), 1.05), "對應基本武學 ≥ 120 → 固定 1.05")
	assert_true(approx(BattleFormulas.power_factor(0, 200), 1.0), "ATTACK 固定 1.0")

func test_inner_cost() -> void:
	assert_eq(BattleFormulas.inner_cost({ "cost_inner": 5 }, 10), 10)
	assert_eq(BattleFormulas.inner_cost({ "cost_inner": 5 }, 5), 5)
	assert_eq(BattleFormulas.inner_cost({ "cost_inner": 5 }, 1), 1)
	assert_eq(BattleFormulas.inner_cost({ "cost_inner": 7 }, 3), 5, "ceil(4.2)")
	assert_eq(BattleFormulas.inner_cost({ "cost_inner": 0 }, 10), 0)

func test_attack_power_plain_attack_weapon_mods() -> void:
	var t := tables()
	# 木刀 BLADE：4 + 20×1.5 = 34；×1.0 ×(1+10%) = 37.4
	var blade := _u(player_spec())
	assert_true(approx(BattleFormulas.attack_power(blade, {}, {}, 0, t), 37.4), "刀 +10%")
	# 空手：30 × (1 − 10%) = 27
	var fist := _u(player_spec({ "weapon": bare() }))
	assert_true(approx(BattleFormulas.attack_power(fist, {}, {}, 0, t), 27.0), "拳 −10%")
	# 木劍 SWORD：34 × 1.0 = 34；基本劍法 20 → +5
	var sword := _u(player_spec({ "weapon": weapon("it_0002", "w_mujian", "SWORD", 4, "木劍"), "skills": { "basic_sword": 20 } }))
	assert_true(approx(BattleFormulas.attack_power(sword, {}, {}, 0, t), 39.0), "劍 0%、+基本/4")
	# 殺氣 1000 → ×1.1
	var ki := _u(player_spec({ "killing_intent": 1000 }))
	assert_true(approx(BattleFormulas.attack_power(ki, {}, {}, 0, t), 37.4 * 1.1))

func test_attack_power_art() -> void:
	var t := tables()
	var u := _u(player_spec({ "weapon": bare(), "skills": { "sl_changquan": 10, "basic_fist": 10 }, "arts": ["sl_changquan"] }))
	# FIST 招式兵器強度 0；30 + 20×(1+10/60) + 10/4 = 55.8333…；×1.05（10 成）×0.9（拳）
	var base := 30.0 + 20.0 * (1.0 + 10.0 / 60.0) + 2.5
	assert_true(approx(BattleFormulas.attack_power(u, _row("sl_changquan"), _move("sl_changquan", 0), 10, t), base * 1.05 * 0.9))
	assert_true(approx(BattleFormulas.attack_power(u, _row("sl_changquan"), _move("sl_changquan", 0), 5, t), base * 0.80 * 0.9))
	# 精熟：搏擊格鬥 120 → 1 成也是 1.05
	var m := _u(player_spec({ "weapon": bare(), "skills": { "sl_changquan": 10, "basic_fist": 120 } }))
	var base2 := 30.0 + 20.0 * (1.0 + 10.0 / 60.0) + 30.0
	assert_true(approx(BattleFormulas.attack_power(m, _row("sl_changquan"), _move("sl_changquan", 0), 1, t), base2 * 1.05 * 0.9))
	# 兵器類武功：手上是同類兵器才算兵器強度
	var sw := _u(player_spec({ "weapon": weapon("it_0002", "w_mujian", "SWORD", 4, "木劍"), "skills": { "hs_jianfa": 6 } }))
	var b3 := 4.0 + 30.0 + 24.0 * (1.0 + 6.0 / 60.0)
	assert_true(approx(BattleFormulas.attack_power(sw, _row("hs_jianfa"), _move("hs_jianfa", 0), 10, t), b3 * 1.05))
	var mismatch := _u(player_spec({ "skills": { "hs_jianfa": 6 } }))   # 拿木刀
	assert_true(approx(BattleFormulas.attack_power(mismatch, _row("hs_jianfa"), _move("hs_jianfa", 0), 10, t), (b3 - 4.0) * 1.05))

func test_monster_base_skill_fallback() -> void:
	# 怪物沒列出對應基本武學 → 以武功等級代替（5.3 註）
	var wolf := _u(monster("m_wolf"))
	assert_eq(BattleFormulas.base_level(wolf, "basic_fist", "mon_claw", tables()), 10)
	assert_eq(BattleFormulas.base_level(wolf, "basic_fist", "", tables()), 10, "普通攻擊取同基本武學的武功")
	var p := _u(player_spec({ "skills": { "sl_changquan": 10 } }))
	assert_eq(BattleFormulas.base_level(p, "basic_fist", "sl_changquan", tables()), 0, "玩家不代替")

func test_defense_power() -> void:
	var t := tables()
	var rabbit := _u(monster("m_rabbit"))
	# 31 + 10×1.2 + 0 = 43；×(1 − 5×0.004)
	assert_true(approx(BattleFormulas.defense_power(rabbit, "BLADE", t), 43.0 * 0.98))
	var p := _u(player_spec({ "skills": { "basic_parry": 30 } }))
	var g := 1.0 - 19 * 0.004
	assert_true(approx(BattleFormulas.defense_power(p, "FIST", t), (2.0 + 24.0 + 10.0 * 1.1) * g), "對拳掌 +10%")
	assert_true(approx(BattleFormulas.defense_power(p, "BLADE", t), (2.0 + 24.0 + 10.0 * 0.9) * g), "對刀 −10%")
	assert_true(approx(BattleFormulas.defense_power(p, "SWORD", t), (2.0 + 24.0 + 10.0) * g))
	var d := _u(player_spec({ "skills": { "basic_parry": 30 }, "effective_inner": 40 }))
	d.defending = true
	assert_true(approx(BattleFormulas.defense_power(d, "SWORD", t), 36.0 * g * 1.6), "防禦姿態 ×(1.5 + 內功/400)")
	var ki := _u(player_spec({ "killing_intent": 2000 }))
	assert_true(approx(BattleFormulas.defense_power(ki, "SWORD", t), 26.0 * g * 0.9), "殺氣 ×(1 − 殺氣/20000)")

func test_hit_crit_float_counter_proc() -> void:
	var p := _u(player_spec())
	var rabbit := _u(monster("m_rabbit"))
	assert_true(approx(BattleFormulas.hit_chance(p, rabbit, 0), 0.825), "80 − 5×0.3 + 5×0.8")
	var fast := _u(player_spec({ "attrs": { "agi": 200 } }))
	assert_true(approx(BattleFormulas.hit_chance(fast, rabbit, 0), 0.95), "上限 95%")
	assert_true(approx(BattleFormulas.hit_chance(rabbit, fast, 0), 0.10), "下限 10%")
	assert_true(approx(BattleFormulas.crit_chance(p), 0.077), "2 + 19×0.3 %")
	assert_true(approx(BattleFormulas.crit_mult(p), 1.7))
	var fr := BattleFormulas.float_range(p)
	assert_true(approx(fr.x, 0.814) and approx(fr.y, 1.1))
	var calm := _u(player_spec({ "attrs": { "cal": 60 } }))
	assert_true(approx(BattleFormulas.float_range(calm).x, 1.0), "下界夾在 ≤ 1.0")
	assert_true(approx(BattleFormulas.counter_chance(_u(player_spec({ "attrs": { "cal": 24 } }))), 0.0))
	assert_true(approx(BattleFormulas.counter_chance(_u(player_spec({ "attrs": { "cal": 25 } }))), 0.10))
	assert_true(approx(BattleFormulas.proc_chance(0), 0.0))
	assert_true(approx(BattleFormulas.proc_chance(10), 0.07))
	assert_true(approx(BattleFormulas.proc_chance(100), 0.25), "上限 25%")
	assert_true(approx(BattleFormulas.defense_proc_mult(10), 0.68))
	assert_true(approx(BattleFormulas.recover_pct(20), 0.04))

func test_damage_calibration_newbie_vs_rabbit() -> void:
	# GDD 5.6 校準：新手拿木刀打野兔 8–15 點
	var t := tables()
	var p := _u(player_spec())
	var rabbit := _u(monster("m_rabbit"))
	var ap := BattleFormulas.attack_power(p, {}, {}, 0, t)
	var dp := BattleFormulas.defense_power(rabbit, "BLADE", t)
	assert_eq(BattleFormulas.base_damage(ap, dp, 1.0, 0.0), 12)
	var fr := BattleFormulas.float_range(p)
	assert_true(BattleFormulas.base_damage(ap, dp, fr.x, 0.0) >= 8, "浮動下界 ≥ 8")
	assert_true(BattleFormulas.base_damage(ap, dp, fr.y, 0.0) <= 15, "浮動上界 ≤ 15")
	assert_eq(BattleFormulas.base_damage(1.0, 100.0, 1.0, 0.0), 1, "至少 1")
	assert_eq(BattleFormulas.apply_crit(12, 1.7), 20)
