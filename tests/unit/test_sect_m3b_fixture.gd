extends "res://tests/unit/test_world_sect_fixture.gd"
## WP-SECT 的 M3b 整合測試共用基底（本檔沒有 test_ 方法）。
## 丐幫、京城監獄的正式內容由內容 WP 的碎片經 WP-MERGE 合併後才進 data/；這裡在記憶體裡裝一個假的「測丐幫」
## （位階、乞討、小黃）與一間假的京城監獄，只測 WP-SECT 的程式（M3B_PLAN §9.3「先寫純邏輯與不依賴新常數的測試」）。
## GameData.tables 在 after_each 的 _restore_rules（GameData.activate）時整個重建，所以這裡直接改它。

const GB := "tgb"
const GB_REGION := "tgb_r"
const GB_GATE := "tgb_gate"
const GB_HALL := "tgb_hall"
const CHEN := "n_tgb_chen"
const GB_SKILL := "tgb_qitao"
const GB_ADV := "tgb_adv"
const DOG := "m_tgb_dog"
const Q_DAI1 := "q_tgb_dai1"
const CAP_REGION := "tcap_r"
const CAP_YAMEN := "tcap_yamen"
const CAP_GATE := "tcap_gate"
const CAP_JAIL := "tcap_jail"
const CAP_JAILER := "n_tcap_jailer"
const STREET := "xx_square"          # 西夏廣場：街道類房間（沒有 INN／BANK／SHOP 的 NPC）
const BEGGEE := "n_xx_caishang"      # 西夏廣場的菜商（kind STORY）
const SHOPKEEPER := "n_xx_smith"     # 西夏兵器鋪（SHOP）

## M3b 整合：合併後 data/ 有真的京城監獄（jc_jail，1.0B）。AUTO 會選到它而不是假的 tcap_jail，
## 所以每個測試先把真的 CAPITAL 牢房降成一般房間（只改記憶體裡的 GameData.tables；after_each 重建）。
func before_each() -> void:
	super.before_each()
	hide_real_capital_jails()

func hide_real_capital_jails() -> void:
	var tb := t()
	var changed := false
	for rid in tb.get("maps", {}).keys():
		var m: Dictionary = tb["maps"][rid]
		for room in m.get("rooms", []):
			if str(room.get("jail_scope", "")) == "CAPITAL" and str(room.get("id", "")) != CAP_JAIL:
				room["jail_scope"] = "SECT"
				room["jail"] = false
				changed = true
	if changed and host() != null:
		host().index.build(tb)

func _row_base() -> Dictionary:
	return { "era": "1.0A", "src": "proposal" }

## 裝一個測丐幫。over 覆寫 sects 列欄位
func install_gb(over: Dictionary = {}) -> void:
	var tb := t()
	var sect := {
		"id": GB, "name": "測丐幫", "home_city": "xixia", "gate_region": GB_REGION, "prefix": "tg",
		"gate_room": GB_GATE, "head_npc": CHEN, "gender": ["M", "F"],
		"join_requires": [ { "type": "no_sect" }, { "type": "morality_min", "value": 0 }, { "type": "not_enemy_of", "sect": GB } ],
		"teach_requires": [ { "type": "morality_min", "value": 0 } ],
		"sect_skill": GB_SKILL, "sect_skill_name": "測乞討", "sect_skill_effect": { "effect": "POISON_FANG" },
		"sect_skill_cost": ["jing", "shen"], "sect_skill_cap": 100, "sect_skill_limits_arts": false, "sect_art_cap_bonus": 0,
		"sect_skill_gain": [], "sect_skill_penalties": [], "personal_master": false,
		"enforcer": false, "enforcers": [], "jail_room": "", "hostile_entry": [], "visitors": "OPEN", "meal_npc": "",
		"ranks": GB, "no_escort": true, "respawn_at_gate": false,
		"practice": { "verb": "乞討", "target": "NPC", "cost": { "jing": 20, "shen": 20 }, "prof": [3, 6], "per_npc_cd_s": 600,
			"alms": [ { "money": [1, 8], "chance": 0.35 }, { "item": "c_mantou", "n": 1, "chance": 0.10 } ],
			"npc_kinds": ["SHOP", "FUNC", "QUEST", "STORY"] },
		"harass": [ { "regions": { "xixia": 1.0 }, "monster": DOG, "count": [1, 1],
			"unless": [ { "type": "skill_min", "skill": GB_SKILL, "value": 30 } ] } ],
		"era": "1.0A", "src": "proposal",
	}
	sect.merge(over, true)
	tb["sects"][GB] = sect
	if not tb.has("sect_ranks") or not (tb["sect_ranks"] is Dictionary):
		tb["sect_ranks"] = {}
	var rk := [
		{ "id": "tgb_dai0", "sect": GB, "rank": 0, "name": "無袋弟子", "requires": [], "promote": "JOIN", "cost": {} },
		{ "id": "tgb_dai1", "sect": GB, "rank": 1, "name": "一袋弟子",
			"requires": [ { "type": "fame_min", "value": 250 }, { "type": "lilian_min", "value": 250 } ],
			"promote": "QUEST", "quest": Q_DAI1, "assembly": true, "cost": {} },
		{ "id": "tgb_dai2", "sect": GB, "rank": 2, "name": "二袋弟子",
			"requires": [ { "type": "fame_min", "value": 500 }, { "type": "lilian_min", "value": 500 },
				{ "type": "sect_rank_min", "sect": GB, "value": 1 } ],
			"promote": "QUEST", "quest": Q_DAI1, "assembly": true, "cost": { "fame": 250, "lilian": 250 } },
		{ "id": "tgb_dai3", "sect": GB, "rank": 3, "name": "三袋弟子",
			"requires": [ { "type": "fame_min", "value": 1200 }, { "type": "sect_rank_min", "sect": GB, "value": 2 } ],
			"promote": "AUTO", "cost": {} },
	]
	for r in rk:
		r.merge(_row_base(), true)
		tb["sect_ranks"][str(r["id"])] = r
	tb["regions"][GB_REGION] = { "id": GB_REGION, "name": "測丐幫總舵", "type": "SECT", "city": "xixia", "map": "",
		"world_pos": [0, 0], "suggested_xp": [0, 0], "pk_allowed": false, "birth_allowed": false, "birth_room": "",
		"night_closed": [], "era": "1.0A", "src": "proposal" }
	tb["maps"][GB_REGION] = { "region_id": GB_REGION, "era": "1.0A", "src": "proposal", "desc": "", "escape_tiles_hint": 2,
		"rooms": [
			{ "id": GB_GATE, "name": "測破廟門口", "desc": "", "exits": [ { "dir": "N", "to": GB_HALL } ], "npcs": [],
				"features": [], "requires": [] },
			{ "id": GB_HALL, "name": "測破廟正殿", "desc": "", "exits": [ { "dir": "S", "to": GB_GATE } ], "npcs": [CHEN],
				"features": [], "requires": [] },
		] }
	tb["npcs"][CHEN] = { "id": CHEN, "name": "測陳長老", "kind": "MASTER", "region": GB_REGION, "room": GB_HALL,
		"alignment": "GOOD", "night_closed": false, "services": ["JOIN", "BETRAY", "RANK", "TEACH"], "join_sect": GB,
		"era": "1.0A", "src": "proposal" }
	tb["masters"]["ms_tgb_skill"] = { "id": "ms_tgb_skill", "npc_id": CHEN, "skill_id": GB_SKILL, "cap": 10, "price": 0,
		"requires": [ { "type": "sect", "sect": GB } ], "era": "1.0A", "src": "proposal" }
	tb["masters"]["ms_tgb_adv"] = { "id": "ms_tgb_adv", "npc_id": CHEN, "skill_id": GB_ADV, "cap": 60, "price": 0,
		"requires": [ { "type": "sect", "sect": GB } ], "era": "1.0A", "src": "proposal" }
	var adv: Dictionary = tb["martial_arts"].get(ART, {}).duplicate(true) if tb["martial_arts"].has(ART) else {}
	if adv.is_empty():
		install_sect()   # 借用 M3a 測派的武功列形狀
		adv = tb["martial_arts"][ART].duplicate(true)
	adv["id"] = GB_ADV
	adv["name"] = "測瘋魔杖法"
	adv["sect_id"] = GB
	adv["tier"] = "ADVANCED"
	adv["requires"] = [ { "type": "sect", "sect": GB }, { "type": "sect_rank_min", "sect": GB, "value": 2 } ]
	tb["martial_arts"][GB_ADV] = adv
	var dog: Dictionary = tb["monsters"]["m_rabbit"].duplicate(true)
	dog["id"] = DOG
	dog["name"] = "測小黃"
	dog["learn_points"] = 5
	dog["drops"] = []
	dog["ai"] = "melee_basic"   # 小黃會撲上來咬（野兔是 coward，會逃）
	tb["monsters"][DOG] = dog
	host().index.build(tb)

## 一間假的京城監獄（jail_scope CAPITAL、出獄送到衙門、只許坐牢的人進）＋看守人
func install_capital_jail() -> void:
	var tb := t()
	tb["regions"][CAP_REGION] = { "id": CAP_REGION, "name": "測京城", "type": "CITY", "city": CAP_REGION, "map": "",
		"world_pos": [0, 0], "suggested_xp": [0, 0], "pk_allowed": false, "birth_allowed": false, "birth_room": "",
		"night_closed": [], "era": "1.0A", "src": "proposal" }
	tb["maps"][CAP_REGION] = { "region_id": CAP_REGION, "era": "1.0A", "src": "proposal", "desc": "", "escape_tiles_hint": 2,
		"rooms": [
			{ "id": CAP_YAMEN, "name": "測京城衙門", "desc": "", "exits": [ { "dir": "N", "to": CAP_GATE } ], "npcs": [],
				"features": [], "requires": [] },
			{ "id": CAP_GATE, "name": "測監獄門口", "desc": "", "exits": [ { "dir": "S", "to": CAP_YAMEN }, { "dir": "N", "to": CAP_JAIL } ],
				"npcs": [CAP_JAILER], "features": [], "requires": [] },
			{ "id": CAP_JAIL, "name": "測京城監獄", "desc": "", "jail": true, "jail_scope": "CAPITAL", "jail_release_to": CAP_YAMEN,
				"safe": true, "exits": [ { "dir": "S", "to": CAP_GATE } ], "npcs": [], "features": [], "requires": [] },
		] }
	tb["npcs"][CAP_JAILER] = { "id": CAP_JAILER, "name": "測看守人", "kind": "FUNC", "region": CAP_REGION, "room": CAP_GATE,
		"alignment": "GOOD", "night_closed": false, "services": ["JAIL"], "era": "1.0A", "src": "proposal" }
	host().index.build(tb)

## 直接寫角色進測丐幫（不走 join_sect）
func join_gb(c = null) -> void:
	if c == null:
		c = ch()
	c.sect = GB
	c.sect_rank = 0
	c.sect_rank_pending = {}
	c.sect_record["joined_online_s"] = c.online_s

## 世界時間撥到下一個辰時起點之後 1 秒（跑 GameHost.tick 的時辰與分鐘工作）
func to_next_chen() -> void:
	set_shichen(5)   # 先離開辰時（新世界從辰時開始），再到下一個辰時
	set_shichen(4)
	host().check_clock()
	host()._minute_jobs()
	ws.flush()
