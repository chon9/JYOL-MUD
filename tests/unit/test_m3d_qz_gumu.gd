extends "res://tests/unit/test_m3d_arts_base.gd"
## M3D_PLAN §4.9（C9，WP-ARTS）：全真弟子殺古墓弟子——殺氣加倍（1.0A；怪物列殺氣 0 時至少多 5）、
## 計數 counters.qz_gumu_kills（古墓玩家、古墓 NPC、sect: gumu 的怪都算；全真弟子才計；不遞減）、
## 門規 qz_r_kill_gumu（1.0B）：第 11 個觸發（坐牢），坐牢後計數不歸零、再殺一個再觸發。

const RULE := "qz_r_kill_gumu"

func _qz() -> bool:
	if join_char("quanzhen") == null:
		return false
	ch().morality = 500
	ch().killing_intent = 0
	return true

func _kills() -> int:
	return int(ch().counters.get(ArtsRules.COUNTER_QZ_GUMU, 0))

## 打贏一隻古墓弟子（sect: gumu 的怪）
func _kill_monster(mid := "m_gm_dizi") -> void:
	goto("zn_road2")
	host().battles.start(s(), [mid], "ENCOUNTER")
	win_battle()

## 攻擊 NPC 殺死古墓 NPC 弟子（SectSystem.on_npc_killed；NpcAttackSystem 的呼叫點）
func _kill_npc() -> void:
	host().sects.on_npc_killed(s(), ch(), "n_gm_sunpopo", { "sect": "gumu", "monster": "m_npc_gm_dizi" }, "GOOD")
	host().sects.check_state(s(), "BATTLE")

func _pvp_victim(sect_id: String):
	var v := Character.new()
	v.sect = sect_id
	v.name = "古墓少女"
	return v

func test_rule_row() -> void:
	if not game_ok():
		return
	var r: Dictionary = tables()["sect_rules"][RULE]
	assert_eq(str(r["sect"]), "quanzhen")
	assert_eq(str(r["era"]), "1.0B")
	assert_eq(str(r["ok_if"][0]["type"]), "counter_max")
	assert_eq(int(r["ok_if"][0]["value"]), 10)

func test_counter_max_requirement() -> void:
	if not _qz():
		return
	var c := [{ "type": "counter_max", "key": "qz_gumu_kills", "value": 10 }]
	assert_eq(Requirements.check(c, ch(), tables(), ws.options, host().rules), "", "沒有計數 = 0")
	ch().counters["qz_gumu_kills"] = 10
	assert_eq(Requirements.check(c, ch(), tables(), ws.options, host().rules), "")
	ch().counters["qz_gumu_kills"] = 11.0   # 存檔讀回是浮點數
	assert_eq(Requirements.check(c, ch(), tables(), ws.options, host().rules), "req_counter_max")
	assert_true(Requirements.describe(c[0], tables()).contains("10"))

func test_monster_kill_doubles() -> void:
	if not _qz():
		return
	var ki0: int = ch().killing_intent
	_kill_monster()
	assert_eq(_kills(), 1, "計數 +1")
	assert_eq(int(ch().killing_intent) - ki0, ArtsRules.GUMU_EXTRA_MIN, "怪物列殺氣 0 → 多 5")
	assert_false(evs("ar_qz_gumu_kill").is_empty())

func test_npc_kill_doubles() -> void:
	if not _qz():
		return
	var base := int(tables()["monsters"]["m_npc_gm_dizi"]["killing_intent_on_kill"])
	var ki0: int = ch().killing_intent
	_kill_npc()
	assert_eq(_kills(), 1)
	assert_eq(int(ch().killing_intent) - ki0, maxi(base, ArtsRules.GUMU_EXTRA_MIN), "NPC 那份再加一次")

func test_pvp_kill_doubles() -> void:
	if not _qz():
		return
	var ki0: int = ch().killing_intent
	host().sects.on_pvp_kill(s(), _pvp_victim("gumu"), false)
	assert_eq(_kills(), 1, "古墓玩家也算（叫戰、反殺都算：任何 PvP）")
	assert_eq(int(ch().killing_intent) - ki0, MoralityPk.KILL_KILLING_INTENT, "PvP 殺氣 +100 再加一份")
	host().sects.on_pvp_kill(s(), _pvp_victim("huashan"), true)
	assert_eq(_kills(), 1, "別派不算")

func test_other_sect_no_effect() -> void:
	if join_char("huashan") == null:
		return
	ch().killing_intent = 0
	_kill_monster()
	assert_eq(_kills(), 0, "不是全真弟子不計")
	assert_eq(int(ch().killing_intent), 0)

func test_rule_jails_on_11th_and_again() -> void:
	if not _qz():
		return
	ch().counters[ArtsRules.COUNTER_QZ_GUMU] = 10
	host().sects.check_state(s(), "BATTLE")
	assert_false(ch().is_jailed(), "10 個還沒事")
	_kill_npc()
	assert_eq(_kills(), 11)
	assert_true(ch().is_jailed(), "第 11 個：門規觸發（預設 JAIL）")
	assert_eq(str(ch().jail.get("rule", "")), RULE)
	# 出獄：計數不歸零，但不會馬上又被抓
	host().sects.release(s(), "served")
	assert_false(ch().is_jailed())
	host().sects.check_state(s(), "TICK")
	assert_false(ch().is_jailed(), "沒再殺就不再觸發")
	assert_eq(_kills(), 11, "坐牢後計數不歸零")
	_kill_npc()
	assert_true(ch().is_jailed(), "再殺一個再坐牢")

func test_1_0a_no_rule_but_double() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])
	if not _qz():
		return
	assert_false(tables()["sect_rules"].has(RULE), "10 人門規是 1.0B")
	ch().counters[ArtsRules.COUNTER_QZ_GUMU] = 20
	var ki0: int = ch().killing_intent
	_kill_npc()
	assert_false(ch().is_jailed(), "1.0A 沒有這條門規")
	assert_true(int(ch().killing_intent) > ki0, "殺氣加倍是 1.0A 就有")
