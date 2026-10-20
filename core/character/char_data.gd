class_name CharData
extends RefCounted
## WP-CHAR 內部共用的資料表查詢工具（純邏輯，不引用 Autoload）。
## tables 的形狀 = GameData.tables：table_name -> { id -> row }，另含 "maps": { region_id -> map }。

const ATTR_NAMES := {
	"str": "臂力", "guts": "膽識", "wit": "悟性", "luck": "福緣", "cal": "定力", "agi": "機敏", "con": "根骨",
}
const VITAL_NAMES := {
	"jing": "精", "qi": "氣", "shen": "神", "neili": "內力", "food": "飽食", "water": "飲水",
}
## 可出招的武功類別（M3A_PLAN 3.11：加 STAB；POISON／MEDIC／HIDDEN／FORMATION／INNER 走專用指令，不在這裡）
const BATTLE_CATEGORIES := ["FIST", "BLADE", "SWORD", "STAFF", "WHIP", "SPEAR", "STAB"]

static func row(tables: Dictionary, table: String, id: String) -> Dictionary:
	if id == "":
		return {}
	var t: Variant = tables.get(table, {})
	if typeof(t) != TYPE_DICTIONARY:
		return {}
	var r: Variant = t.get(id, {})
	return r if typeof(r) == TYPE_DICTIONARY else {}

static func rows(tables: Dictionary, table: String) -> Array:
	var t: Variant = tables.get(table, {})
	if typeof(t) != TYPE_DICTIONARY:
		return []
	return t.values()

static func to_int(v: Variant, def: int = 0) -> int:
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			return int(round(v))
		TYPE_BOOL:
			return 1 if v else 0
		TYPE_STRING:
			return int(v) if String(v).is_valid_int() else def
	return def

## 不可信資料（護照、匯入檔）裡的字串欄位：只接受 String／StringName，其他型別回 def（M3c2 審查：String(int) 會讓引擎報錯）
static func to_str(v: Variant, def: String = "") -> String:
	match typeof(v):
		TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return String(v)
	return def

static func to_float(v: Variant, def: float = 0.0) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return float(v)
		TYPE_STRING:
			return float(v) if String(v).is_valid_float() else def
	return def

## 在所有 maps 裡找房間；找不到回 {}
static func room(tables: Dictionary, room_id: String) -> Dictionary:
	if room_id == "":
		return {}
	var maps: Variant = tables.get("maps", {})
	if typeof(maps) != TYPE_DICTIONARY:
		return {}
	for region_id in maps:
		var m: Variant = maps[region_id]
		if typeof(m) != TYPE_DICTIONARY:
			continue
		for r in m.get("rooms", []):
			if typeof(r) == TYPE_DICTIONARY and r.get("id", "") == room_id:
				return r
	return {}

static func room_name(tables: Dictionary, room_id: String) -> String:
	return String(room(tables, room_id).get("name", room_id))

static func region_name(tables: Dictionary, region_id: String) -> String:
	return String(row(tables, "regions", region_id).get("name", region_id))

static func item_name(tables: Dictionary, item_id: String) -> String:
	return String(row(tables, "items", item_id).get("name", item_id))

static func npc_name(tables: Dictionary, npc_id: String) -> String:
	return String(row(tables, "npcs", npc_id).get("name", npc_id))

static func sect_name(tables: Dictionary, sect_id: String) -> String:
	if sect_id == "":
		return ""
	return String(row(tables, "sects", sect_id).get("name", sect_id))

static func attr_name(tables: Dictionary, attr: String) -> String:
	var r := row(tables, "attributes", attr)
	if r.has("name"):
		return String(r["name"])
	return String(ATTR_NAMES.get(attr, attr))

## 找出把 skill_id 當作門派技能的門派列；沒有回 {}
static func sect_of_skill(tables: Dictionary, skill_id: String) -> Dictionary:
	for r in rows(tables, "sects"):
		if typeof(r) == TYPE_DICTIONARY and r.get("sect_skill", "") == skill_id and skill_id != "":
			return r
	return {}

## masters 表中所有 skill_id == skill 的列
static func masters_for_skill(tables: Dictionary, skill_id: String) -> Array:
	var out: Array = []
	for r in rows(tables, "masters"):
		if typeof(r) == TYPE_DICTIONARY and r.get("skill_id", "") == skill_id:
			out.append(r)
	return out

## masters 表中 npc_id + skill_id 的第一列；沒有回 {}
static func master_row(tables: Dictionary, npc_id: String, skill_id: String) -> Dictionary:
	for r in rows(tables, "masters"):
		if typeof(r) == TYPE_DICTIONARY and r.get("npc_id", "") == npc_id and r.get("skill_id", "") == skill_id:
			return r
	return {}

static func masters_of_npc(tables: Dictionary, npc_id: String) -> Array:
	var out: Array = []
	for r in rows(tables, "masters"):
		if typeof(r) == TYPE_DICTIONARY and r.get("npc_id", "") == npc_id:
			out.append(r)
	return out

## 招式列（在 martial_arts 的 moves 內）
static func move_row(art_row: Dictionary, move_id: String) -> Dictionary:
	for m in art_row.get("moves", []):
		if typeof(m) == TYPE_DICTIONARY and m.get("id", "") == move_id:
			return m
	return {}
