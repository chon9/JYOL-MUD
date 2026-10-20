extends "res://tests/unit/test_world_fixture.gd"
## WP-RULES 的 M3a 整合測試共用基底（本檔沒有 test_ 方法）。
## 門派內容由 WP-SECT 碎片經 WP-MERGE 合併後才進 data/；這裡在記憶體裡裝一個假的門派（地區、房間、NPC、師父、武功、
## 門規、怪物、物品），只測 WP-RULES 的程式（M3A_PLAN 8.3「先寫純邏輯與不依賴新常數的測試」）。
## GameData.tables 在 after_each 的 _restore_rules（GameData.activate）時整個重建，所以這裡直接改它。

const SID := "tsect"
const REGION := "tsect_r"
const GATE := "ts_gate"
const HALL := "ts_hall"
const INNER := "ts_inner"
const JAIL := "ts_jail"
const HEAD := "n_ts_head"
const JAILER := "n_ts_jailer"
const GUIDE := "n_ts_guide"
const TRIAL := "n_ts_trial"
const SKILL := "ts_skill"
const ART := "ts_art"
const OTHER_ART := "ts_other_art"
const GUARD := "m_ts_guard"
const TOKEN := "i_ts_token"
const ANTIDOTE := "c_ts_antidote"

func t() -> Dictionary:
	return GameData.tables

## 裝一個測試門派。over 覆寫 sects 列的欄位；extra_rules 取代預設門規。
func install_sect(over: Dictionary = {}, rules: Variant = null) -> void:
	var tb := t()
	var sect := {
		"id": SID, "name": "測派", "home_city": "xixia", "gate_region": REGION, "prefix": "ts",
		"gate_room": GATE, "head_npc": HEAD, "gender": ["M", "F"],
		"join_requires": [ { "type": "morality_min", "value": -99 }, { "type": "no_sect" },
			{ "type": "not_enemy_of", "sect": SID } ],
		"teach_requires": [ { "type": "morality_min", "value": 0 } ],
		"sect_skill": SKILL, "sect_skill_name": "測心", "sect_skill_effect": { "effect": "RESIST" },
		"sect_skill_cost": ["jing", "neili"], "sect_skill_cap": 100, "sect_skill_limits_arts": false,
		"sect_art_cap_bonus": 10, "sect_skill_gain": [], "sect_skill_penalties": [], "personal_master": false,
		"enforcer": true, "enforcers": [JAILER], "jail_room": JAIL,
		"hostile_entry": [ { "if": [ { "type": "enemy_of", "sect": SID } ], "rooms": "ALL", "monster": GUARD,
			"count": [1, 1], "chance": 1.0, "no_flee": true, "capture": true } ],
		"visitors": "OPEN", "meal_npc": "", "era": "1.0A", "src": "proposal",
	}
	sect.merge(over, true)
	tb["sects"][SID] = sect
	var rl: Array = rules if rules is Array else [
		{ "id": "ts_r_morality", "sect": SID, "tier": "BREACH", "kind": "STATE",
			"ok_if": [ { "type": "morality_min", "value": -99 } ], "text": "rule_ts_morality", "era": "1.0A", "src": "proposal" },
		{ "id": "ts_r_killing", "sect": SID, "tier": "BREACH", "kind": "STATE",
			"ok_if": [ { "type": "killing_intent_max", "value": 2000 } ], "text": "rule_ts_killing", "era": "1.0A", "src": "proposal" },
		{ "id": "ts_r_kill_same", "sect": SID, "tier": "BREACH", "kind": "EVENT", "event": "KILL_SAME_SECT",
			"text": "rule_ts_kill_same", "era": "1.0A", "src": "proposal" },
		{ "id": "ts_r_region", "sect": SID, "tier": "BREACH", "kind": "EVENT", "event": "ENTER_REGION",
			"event_arg": "huashan", "text": "rule_ts_region", "era": "1.0A", "src": "proposal" },
	]
	for k in tb.get("sect_rules", {}).keys():
		if str(tb["sect_rules"][k].get("sect", "")) == SID:
			tb["sect_rules"].erase(k)
	if not tb.has("sect_rules"):
		tb["sect_rules"] = {}
	for r in rl:
		tb["sect_rules"][str(r["id"])] = r
	tb["text_templates"]["rule_ts_morality"] = { "id": "rule_ts_morality", "self": "善惡不得低於 −99", "era": "1.0A" }
	tb["regions"][REGION] = { "id": REGION, "name": "測派山", "type": "SECT", "city": "xixia", "map": "",
		"world_pos": [0, 0], "suggested_xp": [0, 0], "pk_allowed": false, "birth_allowed": false, "birth_room": "",
		"night_closed": [], "era": "1.0A", "src": "proposal" }
	tb["maps"][REGION] = { "region_id": REGION, "era": "1.0A", "src": "proposal", "desc": "", "escape_tiles_hint": 2,
		"rooms": [
			{ "id": GATE, "name": "測派山門", "desc": "", "exits": [ { "dir": "N", "to": HALL } ],
				"npcs": [GUIDE], "features": [], "requires": [] },
			{ "id": HALL, "name": "測派大殿", "desc": "", "exits": [ { "dir": "S", "to": GATE }, { "dir": "N", "to": INNER },
				{ "dir": "E", "to": JAIL } ], "npcs": [HEAD, TRIAL], "features": [], "requires": [] },
			{ "id": INNER, "name": "測派內室", "desc": "", "exits": [ { "dir": "S", "to": HALL } ], "npcs": [],
				"features": [], "requires": [ { "type": "any_of", "options": [
					[ { "type": "sect", "sect": SID } ],
					[ { "type": "no_sect" }, { "type": "has_item", "item": TOKEN } ] ] } ] },
			{ "id": JAIL, "name": "測派思過處", "desc": "", "jail": true, "exits": [ { "dir": "W", "to": HALL } ],
				"npcs": [JAILER], "features": [], "requires": [ { "type": "sect", "sect": SID } ] },
		] }
	var npc_base := { "kind": "MASTER", "region": REGION, "alignment": "GOOD", "night_closed": false, "era": "1.0A", "src": "proposal" }
	var head := npc_base.duplicate(true)
	head.merge({ "id": HEAD, "name": "測掌門", "room": HALL, "services": ["JOIN", "BETRAY", "TEACH"], "join_sect": SID }, true)
	tb["npcs"][HEAD] = head
	var jl := npc_base.duplicate(true)
	jl.merge({ "id": JAILER, "name": "測看守", "kind": "FUNC", "room": JAIL, "services": ["JAIL"] }, true)
	tb["npcs"][JAILER] = jl
	var gd := npc_base.duplicate(true)
	gd.merge({ "id": GUIDE, "name": "測引路人", "kind": "FUNC", "room": GATE, "services": ["GUIDE"],
		"guide": { "to_room": INNER, "requires": [ { "type": "any_of", "options": [ [ { "type": "sect", "sect": SID } ],
			[ { "type": "no_sect" }, { "type": "gender", "value": "F" } ] ] } ] } }, true)
	tb["npcs"][GUIDE] = gd
	var tr := npc_base.duplicate(true)
	tr.merge({ "id": TRIAL, "name": "測試煉師", "kind": "FUNC", "room": HALL, "services": ["TRIAL"],
		"trial": { "id": "ts_trial", "name": "測派試煉", "waves": [["m_rabbit"], ["m_rabbit", "m_rabbit"]], "party_min": 1, "party_max": 3,
			"requires": [ { "type": "sect", "sect": SID } ], "reward_flag": "ts_trial_passed", "no_flee": true } }, true)
	tb["npcs"][TRIAL] = tr
	tb["masters"]["ms_ts_skill"] = { "id": "ms_ts_skill", "npc_id": HEAD, "skill_id": SKILL, "cap": 50, "price": 0,
		"requires": [ { "type": "sect", "sect": SID } ], "era": "1.0A", "src": "proposal" }
	tb["masters"]["ms_ts_art"] = { "id": "ms_ts_art", "npc_id": HEAD, "skill_id": ART, "cap": 50, "price": 0,
		"requires": [ { "type": "sect", "sect": SID } ], "era": "1.0A", "src": "proposal" }
	var art := { "id": ART, "name": "測拳", "sect_id": SID, "category": "FIST", "base_skill": "basic_fist", "difficulty": 1.0,
		"self_study_until": 0, "self_study_cap": 0, "party_size": 0, "monster_only": false, "requires": [ { "type": "sect", "sect": SID } ],
		"moves": [ { "id": "ts_art_1", "name": "測招", "unlock_level": 1, "power": 20, "range": 1, "aoe": "SINGLE",
			"cost_inner": 0, "cost_jing": 0, "flavor": "", "src": "proposal" } ], "era": "1.0A", "src": "proposal" }
	tb["martial_arts"][ART] = art
	var other := art.duplicate(true)
	other["id"] = OTHER_ART
	other["sect_id"] = "huashan"
	other["requires"] = []
	tb["martial_arts"][OTHER_ART] = other
	var guard: Dictionary = tb["monsters"]["m_rabbit"].duplicate(true)
	guard["id"] = GUARD
	guard["name"] = "測守山弟子"
	guard["sect"] = SID
	tb["monsters"][GUARD] = guard
	tb["items"][TOKEN] = { "id": TOKEN, "name": "測令牌", "tab": "OTHER", "slot": "", "atk": 0, "def": 0, "weight": 1,
		"price": 1, "stack": 99, "spoil_days": 0, "effects": [], "usable": false, "usable_in_battle": false,
		"no_sell": false, "quest_item": false, "sect_only": SID, "era": "1.0A", "src": "proposal" }
	tb["items"][ANTIDOTE] = { "id": ANTIDOTE, "name": "測解毒藥", "tab": "OTHER", "slot": "", "atk": 0, "def": 0, "weight": 1,
		"price": 1, "stack": 99, "spoil_days": 0, "effects": [ { "type": "cure", "status": "poison", "max_level": 5 } ],
		"usable": true, "usable_in_battle": true, "no_sell": false, "quest_item": false, "era": "1.0A", "src": "proposal" }
	if not tb.has("status_effects"):
		tb["status_effects"] = {}
	if not tb["status_effects"].has("poison") or not tb["status_effects"]["poison"].has("persist_qi_pct"):
		tb["status_effects"]["poison"] = { "id": "poison", "name": "中毒", "kind": "DEBUFF", "glyph": "毒", "color": "#3c9a3c",
			"duration_actions": 6, "stack": "LEVEL_MAX", "persists": true, "persist_tick_real_s": 120,
			"persist_ticks_per_level": 2, "persist_qi_pct": 0.03, "era": "1.0A", "src": "proposal" }
	host().index.build(tb)
	# M3B_PLAN §5.1.4：M3a 的思過處測試固定用各派思過處（合併後 1.0B 的京城監獄生效時 AUTO 會改用京城監獄）
	ws.options["jail_location"] = "SECT"

## 建角並加入測試門派（直接寫角色，不走 join_sect）
func member(char_name := "測弟子", gender := "M"):
	var c = make_char(char_name, "xixia", { "wit": 5 }, gender)
	return c

func join_via_npc() -> Dictionary:
	goto(HALL)
	return send("join_sect", { "npc": HEAD })

func sects():
	return host().sects

func refresh_sheet() -> void:
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()

func fast_forward(sec: float) -> void:
	ch().online_s += sec
	host().conditions.check_now(s())
	ws.flush()
