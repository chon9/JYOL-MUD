extends "res://tests/test_case.gd"
## M3B_PLAN §5.1.7、O20（D12）、§11.1：毒牙（POISON_FANG）觸發與消耗；DEFENSE／RECOVER 觸發也扣 sect_skill_cost。

func _tables() -> Dictionary:
	var tb: Dictionary = GameData.tables.duplicate()
	var sects: Dictionary = (tb.get("sects", {}) as Dictionary).duplicate()
	sects["tgb"] = { "id": "tgb", "name": "測丐幫", "sect_skill": "tgb_qitao", "sect_skill_name": "測乞討",
		"sect_skill_effect": { "effect": "POISON_FANG" }, "sect_skill_cost": ["jing", "shen"] }
	sects["tdf"] = { "id": "tdf", "name": "測守派", "sect_skill": "tdf_skill", "sect_skill_name": "測守",
		"sect_skill_effect": { "effect": "DEFENSE" }, "sect_skill_cost": ["jing", "neili"] }
	sects["trc"] = { "id": "trc", "name": "測回派", "sect_skill": "trc_skill", "sect_skill_name": "測回",
		"sect_skill_effect": { "effect": "RECOVER" }, "sect_skill_cost": ["jing", "neili"] }
	tb["sects"] = sects
	return tb

func _unit(effect: String, level: int, sect: String) -> BattleUnit:
	var spec := { "kind": "PLAYER", "name": "測", "side": 0, "peer": 1, "sect": sect,
		"attrs": { "str": 20, "guts": 20, "wit": 20, "luck": 20, "cal": 20, "agi": 20, "con": 20 },
		"qi": 500, "qi_max": 500, "neili": 200, "neili_max": 200, "jing": 200, "jing_max": 200, "shen": 200, "shen_max": 200,
		"skills": {}, "arts": [], "weapon": {}, "armor_power": 0, "effective_inner": 0, "lightness": 0,
		"sect_skill": { "id": sect + "_skill", "effect": effect, "level": level } }
	var u := BattleUnit.new(0, spec)
	return u

func _battle(later := true) -> Battle:
	return Battle.new(1, 12345, { "later_battle_cmds": later, "wait_mode": false })

func test_fang_level_formula() -> void:
	assert_eq(BattleStatus.fang_level(0), 1)
	assert_eq(BattleStatus.fang_level(24), 1)
	assert_eq(BattleStatus.fang_level(25), 2)
	assert_eq(BattleStatus.fang_level(100), 5, "1 + floor(乞討 / 25)")

func test_fang_poisons_and_costs() -> void:
	var tb := _tables()
	var b := _battle()
	var att := _unit("POISON_FANG", 100, "tgb")
	att.spec["sect_skill"]["id"] = "tgb_qitao"
	var def := _unit("", 0, "")
	b.units.append(att)
	b.units.append(def)
	att.uid = 1
	def.uid = 2
	def.side = 1
	var procs := 0
	for i in 200:
		var jing0 := att.jing
		var shen0 := att.shen
		var ev := BattleStatus.on_hit_procs(b, att, def, tb)
		if not ev.is_empty():
			procs += 1
			assert_eq(str(ev[0].get("key", "")), "battle_proc_POISON_FANG")
			assert_eq(att.jing, jing0 - BattleStatus.PROC_COST, "耗精")
			assert_eq(att.shen, shen0 - BattleStatus.PROC_COST, "耗神")
			assert_true(def.statuses.has("poison") or str(ev[ev.size() - 1].get("key", "")) == "battle_proc_RESIST", "目標中毒")
			if def.statuses.has("poison"):
				assert_eq(def.status_level("poison"), 5, "毒牙等級 1 + 100/25")
			att.jing = 200
			att.shen = 200
	assert_true(procs > 0, "200 次命中至少觸發一次（機率照 M3A §5.6）")

func test_fang_needs_later_cmds_and_payable_cost() -> void:
	var tb := _tables()
	var b := _battle(false)
	var att := _unit("POISON_FANG", 100, "tgb")
	att.spec["sect_skill"]["id"] = "tgb_qitao"
	var def := _unit("", 0, "")
	def.side = 1
	for i in 100:
		assert_true(BattleStatus.on_hit_procs(b, att, def, tb).is_empty(), "later_battle_cmds 關：不觸發")
	var b2 := _battle(true)
	att.jing = 2
	for i in 100:
		assert_true(BattleStatus.on_hit_procs(b2, att, def, tb).is_empty(), "精不夠付：不觸發")

func test_defense_and_recover_now_cost() -> void:
	var tb := _tables()
	var b := _battle()
	var u := _unit("DEFENSE", 100, "tdf")
	u.spec["sect_skill"]["id"] = "tdf_skill"
	var fired := 0
	for i in 200:
		var j0 := u.jing
		var n0 := u.neili
		if BattleStatus.try_proc(b, u, "DEFENSE", tb):
			fired += 1
			assert_eq(u.jing, j0 - BattleStatus.PROC_COST, "DEFENSE 觸發扣精（D12）")
			assert_eq(u.neili, n0 - BattleStatus.PROC_COST, "扣內力")
			u.jing = 200
			u.neili = 200
	assert_true(fired > 0)
	var r := _unit("RECOVER", 100, "trc")
	r.spec["sect_skill"]["id"] = "trc_skill"
	r.qi = 100
	r.jing = 2   # 付不起
	for i in 100:
		assert_true(BattleRules._recover_proc(b, r, tb, b.rng).is_empty(), "RECOVER 付不起消耗：不觸發")
	r.jing = 200
	var got := false
	for i in 200:
		var ev := BattleRules._recover_proc(b, r, tb, b.rng)
		if not ev.is_empty():
			got = true
			assert_eq(str(ev[0].get("key", "")), "battle_proc_RECOVER")
			break
	assert_true(got)
	assert_true(r.jing < 200, "RECOVER 觸發扣精（D12）")
