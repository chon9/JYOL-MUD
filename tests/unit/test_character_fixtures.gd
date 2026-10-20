extends "res://tests/test_case.gd"
## WP-CHAR 測試共用的資料表 fixture（G10：只用測試內自建字典，不讀 res://data）。
## 本檔沒有 test_ 方法；run_tests 載入後不會執行任何測試。

static func _index(rows: Array) -> Dictionary:
	var out := {}
	for r in rows:
		out[r["id"]] = r
	return out

static func tables() -> Dictionary:
	var t := {}
	t["eras"] = _index([{ "id": "1.0A", "name": "1.0-A" }])
	t["attributes"] = _index([
		{ "id": "str", "name": "臂力" }, { "id": "guts", "name": "膽識" }, { "id": "wit", "name": "悟性" },
		{ "id": "luck", "name": "福緣" }, { "id": "cal", "name": "定力" }, { "id": "agi", "name": "機敏" },
		{ "id": "con", "name": "根骨" },
	])
	t["basic_skills"] = _index([
		{ "id": "basic_fist", "name": "搏擊格鬥", "curve": "CUBIC", "difficulty": 0.9, "max_level": 250, "attr_bonus_per10": { "str": 1 }, "attr_bonus_cap": { "str": 15 } },
		{ "id": "basic_blade", "name": "基本刀法", "curve": "CUBIC", "difficulty": 0.9, "max_level": 250, "attr_bonus_per10": {} },
		{ "id": "basic_sword", "name": "基本劍法", "curve": "CUBIC", "difficulty": 0.9, "max_level": 250, "attr_bonus_per10": {} },
		{ "id": "basic_inner", "name": "基本內功", "curve": "QUARTIC", "difficulty": 0.8, "max_level": 250, "attr_bonus_per10": { "con": 1 } },
		{ "id": "basic_dodge", "name": "閃躲縱躍", "curve": "CUBIC", "difficulty": 0.9, "max_level": 250, "attr_bonus_per10": { "agi": 1 } },
		{ "id": "basic_parry", "name": "拆招卸力", "curve": "CUBIC", "difficulty": 0.9, "max_level": 250, "attr_bonus_per10": {} },
		{ "id": "basic_literacy", "name": "讀書識字", "curve": "LITERACY", "difficulty": 1.0, "max_level": 250, "attr_bonus_per10": {} },
	])
	t["martial_arts"] = _index([
		{ "id": "sl_changquan", "name": "少林長拳", "sect_id": "shaolin", "category": "FIST", "base_skill": "basic_fist",
		  "difficulty": 0.9, "self_study_until": 0, "self_study_cap": 0, "monster_only": false,
		  "requires": [ { "type": "sect", "sect": "shaolin" } ],
		  "moves": [ { "id": "sl_cq_1", "name": "黑虎掏心", "unlock_level": 1, "power": 20, "range": 1, "aoe": "SINGLE", "cost_inner": 0, "cost_jing": 0 } ] },
		{ "id": "sl_luohanquan", "name": "羅漢拳", "sect_id": "shaolin", "category": "FIST", "base_skill": "basic_fist",
		  "difficulty": 0.9, "self_study_until": 0, "requires": [ { "type": "sect", "sect": "shaolin" } ], "moves": [] },
		{ "id": "sl_xinfa", "name": "少林心法", "sect_id": "shaolin", "category": "INNER", "base_skill": "basic_inner",
		  "difficulty": 0.9, "self_study_until": 0, "requires": [], "moves": [] },
		{ "id": "sl_shenfa", "name": "少林身法", "sect_id": "shaolin", "category": "LIGHTNESS", "base_skill": "basic_body",
		  "difficulty": 0.9, "self_study_until": 0, "requires": [], "moves": [] },
		{ "id": "hs_jianfa", "name": "華山劍法", "sect_id": "huashan", "category": "SWORD", "base_skill": "basic_sword",
		  "difficulty": 0.8, "self_study_until": 0, "requires": [ { "type": "sect", "sect": "huashan" } ], "moves": [] },
		{ "id": "x_selfart", "name": "自修拳", "sect_id": "", "category": "FIST", "base_skill": "basic_fist",
		  "difficulty": 0.9, "self_study_until": 3, "self_study_cap": 20, "requires": [], "moves": [] },
		{ "id": "mon_bite", "name": "撕咬", "sect_id": "", "category": "FIST", "base_skill": "basic_fist",
		  "difficulty": 0.9, "monster_only": true, "requires": [], "moves": [] },
	])
	t["sects"] = _index([
		{ "id": "shaolin", "name": "少林", "gender": ["M"], "join_requires": [ { "type": "no_sect" } ],
		  "sect_skill": "foxa", "sect_skill_name": "佛法", "sect_skill_effect": { "effect": "DEFENSE" },
		  "sect_skill_cost": ["jing", "neili"], "sect_skill_cap": 100,
		  "sect_skill_limits_arts": true, "sect_art_cap_bonus": 10, "forbid_meat": true },
		{ "id": "huashan", "name": "華山", "gender": ["M", "F"], "join_requires": [],
		  "sect_skill": "rufeng", "sect_skill_name": "儒風", "sect_skill_effect": { "effect": "RECOVER" },
		  "sect_skill_cost": ["jing", "shen"], "sect_skill_cap": 100 },
	])
	t["life_skills"] = _index([
		{ "id": "life_farming", "name": "種田", "feature": "FIELD", "tool": "t_chutou", "cap": 100 },
		{ "id": "life_fishing", "name": "釣魚", "feature": "WATER", "tool": "t_yugan", "cap": 100 },
	])
	t["masters"] = _index([
		{ "id": "ms_zhike_foxa", "npc_id": "n_zhike", "skill_id": "foxa", "cap": 50, "price": 0, "tool": "",
		  "requires": [ { "type": "sect", "sect": "shaolin" } ] },
		{ "id": "ms_huizhen_cq", "npc_id": "n_huizhen", "skill_id": "sl_changquan", "cap": 100, "price": 0, "tool": "",
		  "requires": [ { "type": "sect", "sect": "shaolin" }, { "type": "skill_min", "skill": "foxa", "value": 10 } ] },
		{ "id": "ms_huizhen_lhq", "npc_id": "n_huizhen", "skill_id": "sl_luohanquan", "cap": 100, "price": 0, "tool": "", "requires": [] },
		{ "id": "ms_huizhen_inner", "npc_id": "n_huizhen", "skill_id": "basic_inner", "cap": 140, "price": 0, "tool": "", "requires": [] },
		{ "id": "ms_wushi_fist", "npc_id": "n_wushi", "skill_id": "basic_fist", "cap": 30, "price": 5, "tool": "", "requires": [] },
		{ "id": "ms_wushi_lit", "npc_id": "n_wushi", "skill_id": "basic_literacy", "cap": 30, "price": 5, "tool": "", "requires": [] },
		{ "id": "ms_yue_rufeng", "npc_id": "n_yue", "skill_id": "rufeng", "cap": 50, "price": 0, "tool": "", "requires": [] },
		{ "id": "ms_self", "npc_id": "n_selfm", "skill_id": "x_selfart", "cap": 40, "price": 0, "tool": "", "requires": [] },
		{ "id": "ms_taoyun_farm", "npc_id": "n_taoyun", "skill_id": "life_farming", "cap": 100, "price": 50, "tool": "t_chutou", "requires": [] },
	])
	t["items"] = _index([
		{ "id": "w_mudao", "name": "木刀", "tab": "WEAPON", "slot": "WEAPON", "weapon_type": "BLADE", "atk": 4, "def": 4, "weight": 2, "price": 20, "stack": 1, "spoil_days": 0, "effects": [] },
		{ "id": "w_mujian", "name": "木劍", "tab": "WEAPON", "slot": "WEAPON", "weapon_type": "SWORD", "atk": 4, "def": 4, "weight": 2, "price": 20, "stack": 1, "spoil_days": 0, "effects": [] },
		{ "id": "a_bupao", "name": "布衣", "tab": "ARMOR", "slot": "ARMOR", "atk": 0, "def": 2, "weight": 2, "price": 10, "stack": 1, "spoil_days": 0, "effects": [] },
		{ "id": "a_cubudaopao", "name": "粗布道袍", "tab": "ARMOR", "slot": "ARMOR", "atk": 0, "def": 4, "weight": 3, "price": 120, "stack": 1, "spoil_days": 0,
		  "effects": [ { "type": "attr", "stat": "wit", "value": 2 } ] },
		{ "id": "c_jingyao", "name": "精藥水", "tab": "OTHER", "slot": "", "weight": 1, "price": 30, "stack": 99, "spoil_days": 0, "usable": true,
		  "effects": [ { "type": "restore", "stat": "jing", "value": 50 } ] },
		{ "id": "c_qiyao", "name": "金創藥", "tab": "OTHER", "slot": "", "weight": 1, "price": 50, "stack": 99, "spoil_days": 0, "usable": true,
		  "effects": [ { "type": "restore", "stat": "qi", "value": 100 } ] },
		{ "id": "c_mantou", "name": "饅頭", "tab": "OTHER", "slot": "", "weight": 1, "price": 5, "stack": 20, "spoil_days": 3, "usable": true,
		  "effects": [ { "type": "restore", "stat": "food", "value": 20 } ] },
		{ "id": "c_smoke", "name": "守護者之煙", "tab": "OTHER", "slot": "", "weight": 1, "price": 5000, "stack": 10, "spoil_days": 0, "usable": true,
		  "effects": [ { "type": "smoke", "value": 300 } ] },
		{ "id": "r_bigrabbitskin", "name": "大兔皮", "tab": "MATERIAL", "slot": "", "weight": 1, "price": 30, "stack": 50, "spoil_days": 30, "effects": [], "no_sell": true },
		{ "id": "r_stone", "name": "石塊", "tab": "MATERIAL", "slot": "", "weight": 50, "price": 1, "stack": 99, "spoil_days": 0, "effects": [] },
		{ "id": "t_chutou", "name": "鋤頭", "tab": "OTHER", "slot": "", "weight": 3, "price": 40, "stack": 1, "spoil_days": 0, "effects": [] },
	])
	t["regions"] = _index([
		{ "id": "xixia", "name": "西夏", "type": "CITY", "birth_allowed": true, "birth_room": "xx_square" },
		{ "id": "dali", "name": "大理", "type": "CITY", "birth_allowed": true, "birth_room": "dl_square" },
	])
	t["maps"] = {
		"xixia": { "region_id": "xixia", "rooms": [
			{ "id": "xx_square", "name": "西夏廣場", "exits": [] },
			{ "id": "xx_gate_e", "name": "西夏東門", "exits": [] },
		] },
		"dali": { "region_id": "dali", "rooms": [ { "id": "dl_square", "name": "五華樓前", "exits": [] } ] },
	}
	t["npcs"] = _index([ { "id": "n_wujieshan", "name": "武介山" }, { "id": "n_zhike", "name": "知客僧" } ])
	t["quests"] = _index([
		{ "id": "q_rabbit", "name": "狩獵事件：大兔皮", "giver": "n_wujieshan",
		  "text": "出西夏東門到郊外的荒草坡打大野兔，把大兔皮帶回來。",
		  "steps": [ { "type": "DELIVER", "target": "n_wujieshan", "item": "r_bigrabbitskin", "count": 1, "text": "交給武介山 1 張大兔皮" } ] },
		{ "id": "q_bandit", "name": "剿滅山賊", "giver": "n_wujieshan",
		  "steps": [ { "type": "KILL", "target": "m_bandit", "count": 3, "text": "擊敗山賊 3 名" },
					 { "type": "TALK", "target": "n_wujieshan", "count": 1, "text": "回報" } ] },
	])
	return t

static func options() -> Dictionary:
	return { "attr_from_basic_skills": false, "enabled_eras": ["1.0A"], "sects_enabled": [] }

static func rules(preset: String = "classic_standard") -> Dictionary:
	match preset:
		"classic_strict":
			return { "death_rule": "STRICT_2001", "corpse_window": "CLASSIC_30", "xuedian_cap": 0, "self_study_cap": "NONE" }
		"later_official":
			return { "death_rule": "STANDARD", "corpse_window": "LATER_10", "xuedian_cap": 65200, "self_study_cap": "NONE" }
		"friends_casual":
			return { "death_rule": "CASUAL", "corpse_window": "CLASSIC_30", "xuedian_cap": 0, "self_study_cap": "NONE" }
	return { "death_rule": "STANDARD", "corpse_window": "CLASSIC_30", "xuedian_cap": 65200, "self_study_cap": "NONE" }

static func rng(seed_v: int = 12345) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r

## 固定屬性的新角色（P0：臂 20、膽 19、悟 21、福 19、定 19、機 20、根 20）
static func new_char(seed_v: int = 1) -> Character:
	var roll := { "str": 20, "guts": 19, "wit": 21, "luck": 19, "cal": 19, "agi": 20, "con": 20 }
	var p := { "id": "ch_00000001", "identity": "local_test", "name": "測試俠客", "gender": "M",
		"birth_month": 3, "birth_city": "xixia", "alloc": {} }
	return CharacterFactory.create(p, roll, tables(), options(), rng(seed_v), 12.5)

static func uid_maker(prefix: String = "it_t") -> Callable:
	var counter := [0]
	return func() -> String:
		counter[0] += 1
		return "%s%06d" % [prefix, counter[0]]
