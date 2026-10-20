extends "res://tests/unit/test_world_fixture.gd"
## M3C2_PLAN §2.3.3、§10.1（WP-PACE）：切磋獎勵——打贏給實戰與學點、spar_daily_cap、規則 spar_rewards 關、
## 輸了不給、過了新手期只給實戰；SectSystem.spar_given 的反推與 BattleRewards 一致。

const A := preload("res://tests/unit/test_m3c_npc_attack.gd")

func _join(sect := "wudang") -> bool:
	if not game_ok():
		return false
	if make_char("切磋弟子", "dali") == null:
		return false
	ws.options["sect_hostile_entry"] = false
	ch().sect = sect
	ch().morality = 100
	host().sects.on_join(s(), sect, str(tables()["sects"][sect].get("head_npc", "")))
	make_strong()
	clear_events()
	return true

## 打一場切磋（win：打贏）；回傳 { xp, lp } 的變化
func _spar(win := true, npc := "n_wd_spar", room := "wd_square") -> Dictionary:
	goto(room)
	Survival.rest_full(ch(), tables(), ws.options)
	var xp0: int = ch().combat_xp
	var lp0: int = ch().learn_points
	ok("fight", { "npc": npc })
	A.finish(self, 1, win)
	return { "xp": int(ch().combat_xp) - xp0, "lp": int(ch().learn_points) - lp0 }

func _spar_n() -> int:
	var sd: Variant = ch().counters.get("spar_day", {})
	return int((sd as Dictionary).get("n", 0)) if sd is Dictionary else 0

func test_data_rows() -> void:
	var mons: Dictionary = tables()["monsters"]
	for mid in ["m_hs_trainee", "m_sl_dizi", "m_wd_dizi", "m_em_dizi", "m_gm_dizi", "m_hg_dizi", "m_lj_dizi", "m_qz_dizi", "m_xh_dizi", "m_xd_dizi", "m_gb_dizi"]:
		assert_false(bool(mons[mid].get("no_rewards", true)), "%s no_rewards false" % mid)
		assert_true(int(mons[mid]["combat_xp"]) >= 20 and int(mons[mid]["combat_xp"]) <= 300, "%s combat_xp" % mid)
		assert_true(int(mons[mid]["learn_points"]) >= 2 and int(mons[mid]["learn_points"]) <= 30, "%s learn_points" % mid)
		assert_true(SectSystem.is_spar_monster(mid))
	assert_false(SectSystem.is_spar_monster("m_npc_gm_dizi"), "滅派專用列不是切磋")
	assert_eq(int(GameData.default_server_options().get("spar_daily_cap", 0)), 30)

func test_win_gives_xp_and_lp() -> void:
	if not _join():
		return
	var d := _spar(true)
	var row: Dictionary = tables()["monsters"]["m_wd_dizi"]
	assert_eq(int(d["xp"]), BattleRewards.xp_for(row, int(ch().combat_xp) - int(d["xp"]), 1.0), "實戰 = BattleRewards")
	assert_true(int(d["xp"]) > 0 and int(d["lp"]) > 0, "打贏給實戰與學點 %s" % str(d))
	assert_eq(_spar_n(), 1, "counters.spar_day.n")

func test_loss_gives_nothing() -> void:
	if not _join():
		return
	var d := _spar(false)
	assert_eq(int(d["xp"]), 0)
	assert_eq(int(d["lp"]), 0)
	assert_eq(_spar_n(), 0, "輸了不算一場")

func test_daily_cap() -> void:
	if not _join():
		return
	ws.options["spar_daily_cap"] = 2
	assert_true(int(_spar(true)["xp"]) > 0)
	assert_true(int(_spar(true)["xp"]) > 0)
	clear_events()
	var d := _spar(true)
	assert_eq(int(d["xp"]), 0, "第 3 場超過上限：不給實戰")
	assert_eq(int(d["lp"]), 0, "也不給學點")
	assert_false(evs(Protocol.E_CH_SPAR_CAPPED).is_empty(), "ch_spar_capped")
	assert_eq(_spar_n(), 2)
	# 換日重設
	var day: float = host().day_s()
	ws.world["world_time_s"] = (floorf(ws.world_time() / day) + 1.0) * day + 1.0
	ws.advance(0.1)
	assert_true(int(_spar(true)["xp"]) > 0, "換日後又有獎勵")
	assert_eq(_spar_n(), 1)

func test_cap_zero() -> void:
	if not _join():
		return
	ws.options["spar_daily_cap"] = 0
	var d := _spar(true)
	assert_eq(int(d["xp"]) + int(d["lp"]), 0)

func test_rule_off_classic_strict() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	if not _join():
		return
	assert_false(host().rules.get("spar_rewards", true))
	var d := _spar(true)
	assert_eq(int(d["xp"]), 0, "strict：切磋不計實戰")
	assert_eq(int(d["lp"]), 0, "strict：不計學點")
	assert_false(evs("ch_spar_rule").is_empty())

func test_novice_over_xp_only() -> void:
	if not _join():
		return
	ch().skills.set_level("wd_changquan", 45, tables())
	var d := _spar(true)
	assert_true(int(d["xp"]) > 0, "實戰照給")
	assert_eq(int(d["lp"]), 0, "最高本派武功 ≥ 40：學點 0")
	assert_eq(str(lastp(Protocol.E_CH_NO_LP).get("why", "")), "novice")

func test_huashan_trainee_counts() -> void:
	if not _join("huashan"):
		return
	var d := _spar(true, "n_ludayou", "hs_square")
	assert_true(int(d["xp"]) > 0 and int(d["lp"]) > 0, "華山陸大有（m_hs_trainee）也是切磋 %s" % str(d))

func test_spar_given_inverts() -> void:
	var row: Dictionary = tables()["monsters"]["m_wd_dizi"]
	for x0 in [0, 37, 999, 4500, 8800, 20000]:
		for n in [1, 2, 3]:
			var share := 1.0 / sqrt(float(n))
			var g := BattleRewards.xp_for(row, x0, share)
			var r := SectSystem.spar_given([row], x0 + g, n)
			assert_true(bool(r["ok"]), "x0 %d n %d" % [x0, n])
			assert_eq(int(r["xp"]), g, "x0 %d n %d xp" % [x0, n])
