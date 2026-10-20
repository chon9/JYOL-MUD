extends "res://tests/unit/test_battle_helpers.gd"
## M3A_PLAN 5.6、10.1：8 種門派觸發（固定亂數種子）與消耗、消耗不夠不觸發；DEFENSE／RECOVER 不變（金檔照舊）。

const LV := 100   # 觸發率 25%

func _ss(sect: String, skill: String, effect: String) -> Dictionary:
	return { "sect": sect, "sect_skill": { "id": skill, "effect": effect, "level": LV },
		"jing": 92, "shen": 88, "neili": 90, "neili_max": 90 }

## 跑 n 個種子，回傳 { hits, battles: [Battle 有觸發的第一場] }
func _trials(pover: Dictionary, mover: Dictionary, cmd_uid: int, cmd: Dictionary, key: String, n := 80) -> Dictionary:
	var hits := 0
	var first: Battle = null
	var first_ev: Array = []
	for sd in range(1, n + 1):
		var b := make_battle([player_spec(pover), monster("m_dummy", mover)], sd)
		place(b, 1, 1, 3)
		place(b, 2, 2, 3)
		var r := do_cmd(b, cmd_uid, cmd)
		if not find(r.events, key).is_empty():
			hits += 1
			if first == null:
				first = b
				first_ev = r.events
	return { "hits": hits, "battle": first, "events": first_ev }

func test_evade_proc() -> void:
	var r := _trials({ "weapon": bare() }, { "sect_skill": { "id": "duane", "effect": "EVADE", "level": LV }, "sect": "emei",
		"jing": 90, "shen": 90 }, 1, { "cmd": "ATTACK", "target": [2, 3] }, "battle_proc_EVADE")
	assert_true(r.hits > 5 and r.hits < 40, "EVADE %d/80" % r.hits)
	var b: Battle = r.battle
	assert_eq(b.unit(2).jing, 87, "精 −3")
	assert_eq(b.unit(2).shen, 87, "神 −3")
	var e: Dictionary = find(r.events, "battle_proc_EVADE")[0]
	assert_eq(e.p.uid, 2)
	assert_eq(e.p.skill_name, "duane名")

func test_heavy_proc_damage() -> void:
	var r := _trials(_ss("xuedao", "weihe", "HEAVY"), {}, 1, { "cmd": "ATTACK", "target": [2, 3] }, "battle_proc_HEAVY")
	assert_true(r.hits > 5, "HEAVY %d/80" % r.hits)
	var e: Dictionary = find(r.events, "battle_proc_HEAVY")[0]
	assert_eq(e.p.def_uid, 2)
	assert_eq(r.battle.unit(1).jing, 89)
	assert_eq(r.battle.unit(1).neili, 87)

func test_paralyze_confuse_distract_on_hit() -> void:
	for row in [["gumu", "qingxin", "PARALYZE", "paralysis"], ["lingjiu", "dingxing", "CONFUSE", "confusion"],
			["xingxiu", "chanmei", "DISTRACT", "distract"]]:
		var r := _trials(_ss(row[0], row[1], row[2]), {}, 1, { "cmd": "ATTACK", "target": [2, 3] }, "battle_proc_" + row[2])
		assert_true(r.hits > 3, "%s %d/80" % [row[2], r.hits])
		if r.battle != null:
			assert_true(r.battle.unit(2).statuses.has(row[3]), row[3])
			assert_eq(r.battle.unit(1).shen, 85, "精＋神 各 −3")

func test_counter_proc() -> void:
	var mover := { "sect_skill": { "id": "cibei", "effect": "COUNTER", "level": LV }, "sect": "hengshan",
		"jing": 90, "neili": 90, "attrs": { "cal": 1 } }
	var r := _trials({ "weapon": bare() }, mover, 1, { "cmd": "ATTACK", "target": [2, 3] }, "battle_proc_COUNTER")
	assert_true(r.hits > 3, "COUNTER %d/80" % r.hits)
	var ev: Array = r.events
	var c := find(ev, "battle_counter")
	assert_eq(c.size(), 1, "反擊一次")
	assert_eq(c[0].p.atk_uid, 2)
	assert_eq(find(ev, "battle_proc_COUNTER")[0].p.def_uid, 1)

func test_rest_proc() -> void:
	var r := _trials(_ss("quanzhen", "yangsheng", "REST").merged({ "qi": 100, "neili": 10 }, true), {}, 1,
		{ "cmd": "REST" }, "battle_proc_REST")
	assert_true(r.hits > 5, "REST %d/80" % r.hits)
	var e: Dictionary = find(r.events, "battle_proc_REST")[0]
	assert_eq(e.p.qi_gain, 18, "180 × 10%")
	assert_eq(e.p.neili_gain, 9)
	# 一般休息 9 + 觸發 18
	assert_eq(r.battle.unit(1).qi, 127)

func test_resist_proc_cost() -> void:
	var b := make_battle([player_spec(_ss("wudang", "xiayi", "RESIST")), monster("m_dummy")], 1)
	var hit := false
	for i in 40:
		var ev := BattleStatus.apply(b, b.unit(1), "confusion", tables())
		if not find(ev, "battle_proc_RESIST").is_empty():
			hit = true
			break
		b.unit(1).statuses.erase("confusion")
	assert_true(hit)
	assert_eq(b.unit(1).jing + b.unit(1).neili, 92 + 90 - 6)

func test_no_proc_without_cost() -> void:
	var r := _trials(_ss("xuedao", "weihe", "HEAVY").merged({ "jing": 2 }, true), {}, 1,
		{ "cmd": "ATTACK", "target": [2, 3] }, "battle_proc_HEAVY")
	assert_eq(r.hits, 0, "精不夠 3：不觸發")
	var r2 := _trials(_ss("quanzhen", "yangsheng", "REST").merged({ "shen": 0 }, true), {}, 1,
		{ "cmd": "REST" }, "battle_proc_REST")
	assert_eq(r2.hits, 0, "神不夠")

func test_cost_from_spec_override() -> void:
	var p := _ss("", "x", "HEAVY")
	p.sect_skill["cost"] = ["neili"]
	var b := make_battle([player_spec(p), monster("m_dummy")], 1)
	assert_eq(BattleStatus.proc_cost(b.unit(1), tables()), ["neili"])
	var p2 := _ss("xuedao", "weihe", "HEAVY")
	var b2 := make_battle([player_spec(p2), monster("m_dummy")], 1)
	assert_eq(BattleStatus.proc_cost(b2.unit(1), tables()), ["jing", "neili"])

func test_defense_and_recover_unchanged() -> void:
	# DEFENSE、RECOVER 照 M1：不扣消耗（D12）
	var r := _trials({ "weapon": bare() }, { "sect_skill": { "id": "foxa", "effect": "DEFENSE", "level": LV }, "jing": 90, "neili": 90 },
		1, { "cmd": "ATTACK", "target": [2, 3] }, "battle_proc_DEFENSE")
	assert_true(r.hits > 3)
	assert_eq(r.battle.unit(2).jing, 90)
	assert_eq(r.battle.unit(2).neili, 90)
