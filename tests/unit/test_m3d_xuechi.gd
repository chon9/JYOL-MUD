extends "res://tests/unit/test_m3d_arts_base.gd"
## M3D_PLAN §4.7（C7，WP-ARTS）：血池比武（2003【後期版】）——初／中／高三階（三位 NPC，M3D_PLAN 缺漏：FIGHT 一位 NPC 一種怪），
## 贏了威嚇熟練 +30／+60／+100（算進每日 +200 上限）、每階每遊戲日 3 次有熟練、怪物 no_rewards（不給實戰學點）、輸了沒有熟練。

func _xd(weihe := 80) -> bool:
	if join_char("xuedao") == null:
		return false
	ch().morality = -200
	set_skills({ "weihe": weihe })
	goto("xd_pool")
	return true

func _prof() -> int:
	return int(ch().skills.prof("weihe"))

func _fight(npc: String, win := true) -> Dictionary:
	Survival.rest_full(ch(), tables(), ws.options)
	var p0 := _prof()
	var xp0: int = ch().combat_xp
	ok("fight", { "npc": npc })
	if win:
		win_battle()
	else:
		lose_battle()
	return { "prof": _prof() - p0, "xp": int(ch().combat_xp) - xp0 }

func test_data_rows() -> void:
	if not game_ok():
		return
	for t in ArtsRules.XUECHI:
		var e: Dictionary = ArtsRules.XUECHI[t]
		var n: Dictionary = tables()["npcs"][e["npc"]]
		assert_eq(str(n["room"]), "xd_pool")
		assert_eq(str(n["fight"]["monster"]), str(e["monster"]))
		var m: Dictionary = tables()["monsters"][e["monster"]]
		assert_true(bool(m["no_rewards"]), "%s no_rewards" % e["monster"])
	assert_eq(int(tables()["monsters"]["m_ar_xd_xuechi_1"]["stats"]["qi"]), 800)
	assert_eq(int(tables()["monsters"]["m_ar_xd_xuechi_2"]["stats"]["qi"]), 2000)
	assert_eq(int(tables()["monsters"]["m_ar_xd_xuechi_3"]["stats"]["qi"]), 5000)

func test_three_tiers_gain() -> void:
	if not _xd():
		return
	var d1 := _fight("n_ar_xd_xuechi")
	assert_eq(int(d1["prof"]), 30, "初階 +30")
	assert_eq(int(d1["xp"]), 0, "no_rewards：沒有實戰")
	var d2 := _fight("n_ar_xd_xuechi_2")
	assert_eq(int(d2["prof"]), 60, "中階 +60")
	var d3 := _fight("n_ar_xd_xuechi_3")
	assert_eq(int(d3["prof"]), 100, "高階 +100")
	var d4 := _fight("n_ar_xd_xuechi_3")
	assert_eq(int(d4["prof"]), 10, "每日 200 上限：只剩 10")

func test_tier_requires() -> void:
	if not _xd(30):
		return
	assert_eq(reason("fight", { "npc": "n_ar_xd_xuechi_2" }), "req_skill_min", "中階要威嚇 40")
	assert_eq(reason("fight", { "npc": "n_ar_xd_xuechi_3" }), "req_skill_min", "高階要威嚇 70")
	ch().sect = "xingxiu"
	assert_eq(reason("fight", { "npc": "n_ar_xd_xuechi" }), "req_sect", "只限血刀")

func test_three_per_day() -> void:
	if not _xd():
		return
	for i in 3:
		assert_eq(int(_fight("n_ar_xd_xuechi")["prof"]), 30, "第 %d 場" % (i + 1))
	clear_events()
	assert_eq(int(_fight("n_ar_xd_xuechi")["prof"]), 0, "第 4 場沒有熟練")
	assert_false(evs("ar_xuechi_daily").is_empty(), "ar_xuechi_daily")
	var day: float = host().day_s()
	ws.world["world_time_s"] = (floorf(ws.world_time() / day) + 1.0) * day + 1.0
	ws.advance(0.1)
	assert_eq(int(_fight("n_ar_xd_xuechi")["prof"]), 30, "換日重設")

func test_loss_gives_nothing() -> void:
	if not _xd():
		return
	var d := _fight("n_ar_xd_xuechi", false)
	assert_eq(int(d["prof"]), 0, "輸了沒有熟練")
	var n: Variant = ch().counters.get(ArtsRules.COUNTER_XUECHI, {})
	assert_eq(int((n as Dictionary).get("n", {}).get("1", 0)) if n is Dictionary else 0, 0, "輸了不算一場")

func test_sandbag_is_safe() -> void:
	## 陪練出手輕：高階長老打一個剛入門的血刀弟子 30 下，期望總傷害遠低於他的氣（M3D_PLAN 缺漏：FIGHT 沒有不死選項，
	## 靠怪物本身出手輕來確保「掛機」不會被打死；真的被打死照一般死亡懲罰）
	if not _xd(70):
		return
	for a in ["str", "agi", "con", "guts", "cal"]:
		ch().attrs[a] = 20   # 一般資質（join_char 把角色加強過；這裡改回普通人）
	set_skills({ "basic_dodge": 30, "basic_parry": 30, "basic_blade": 30, "basic_fist": 30 })
	ch().clamp_vitals(tables(), ws.options)
	var b := Battle.new(1, 7, { "wait_mode": false, "escape_tiles": 2 })
	var spec := Encounter.monster_spec("m_ar_xd_xuechi_3", tables())
	var me: Dictionary = ch().to_combatant(tables(), ws.options, 0, 1)
	spec["side"] = 1
	spec["peer"] = 0
	b.add_unit(me)
	b.add_unit(spec)
	b.start(tables())
	var foe: BattleUnit = b.units[1]
	var pu: BattleUnit = b.units[0]
	pu.pos = Vector2i(1, 3)
	foe.pos = Vector2i(2, 3)
	var dmg := 0
	for i in 30:
		foe.state = BattleUnit.READY
		pu.qi = pu.qi_max()
		var ev: Array = BattleRules.execute(b, foe, { "cmd": "ATTACK", "target": [1, 3] }, tables(), b.rng)
		for e in ev:
			var p: Dictionary = e.p
			if p.has("dmg") and int(p.get("atk_uid", 0)) == int(foe.uid) and not p.get("counter", false):
				dmg += int(p.dmg)
	assert_true(dmg / 30.0 < pu.qi_max() * 0.1, "平均一下 %.1f < 氣 %d 的 10%%" % [dmg / 30.0, pu.qi_max()])

## M3d 審查第三輪：血池是 2003 的內容——規則 later_events 關（classic_strict）時三位都不陪打，戰後也不給威嚇熟練
func test_strict_rules_no_xuechi() -> void:
	if not _xd():
		return
	GameData.rules["later_events"] = false
	for npc in ["n_ar_xd_xuechi", "n_ar_xd_xuechi_2", "n_ar_xd_xuechi_3"]:
		assert_eq(reason("fight", { "npc": npc }), "req_rule", "%s：later_events 關 → 不陪打" % npc)
	# 規則中途關掉：已經開打的那一場打贏也不給
	GameData.rules["later_events"] = true
	Survival.rest_full(ch(), tables(), ws.options)
	var p0 := _prof()
	ok("fight", { "npc": "n_ar_xd_xuechi" })
	GameData.rules["later_events"] = false
	win_battle()
	assert_eq(_prof() - p0, 0, "later_events 關 → 沒有威嚇熟練")
	GameData.rules["later_events"] = true
	assert_eq(Requirements.describe({ "type": "rule", "key": "later_events", "value": true, "desc": "測試原因" }, tables()), "測試原因",
		"rule 條件可以帶 desc 給介面")
