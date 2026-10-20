class_name SkillBook
extends RefCounted
## 角色的技能簿（M1_PLAN 3.2.2）。prof 為累計熟練度（D5）。

const KIND_BASIC := "BASIC"
const KIND_ART := "ART"
const KIND_SECT := "SECT"
const KIND_LIFE := "LIFE"
const DEFAULT_MAX_LEVEL := 250
const DEFAULT_SECT_CAP := 100
const DEFAULT_LIFE_CAP := 100
const EPS := 1e-9

var entries: Dictionary = {}   # skill_id -> { "level": int, "prof": int }

static func from_dict(d: Dictionary) -> SkillBook:
	var b := SkillBook.new()
	for k in d:
		var e: Variant = d[k]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		b.entries[String(k)] = {
			"level": CharData.to_int(e.get("level", 0)),
			"prof": CharData.to_int(e.get("prof", 0)),
		}
	return b

func to_dict() -> Dictionary:
	var out := {}
	var keys := entries.keys()
	keys.sort()
	for k in keys:
		out[k] = { "level": int(entries[k]["level"]), "prof": int(entries[k]["prof"]) }
	return out

static func kind_of(skill_id: String, tables: Dictionary) -> String:
	if skill_id == "":
		return ""
	if not CharData.row(tables, "basic_skills", skill_id).is_empty():
		return KIND_BASIC
	if not CharData.row(tables, "martial_arts", skill_id).is_empty():
		return KIND_ART
	if not CharData.sect_of_skill(tables, skill_id).is_empty():
		return KIND_SECT
	if not CharData.row(tables, "life_skills", skill_id).is_empty():
		return KIND_LIFE
	return ""

static func skill_name(skill_id: String, tables: Dictionary) -> String:
	match kind_of(skill_id, tables):
		KIND_BASIC:
			return String(CharData.row(tables, "basic_skills", skill_id).get("name", skill_id))
		KIND_ART:
			return String(CharData.row(tables, "martial_arts", skill_id).get("name", skill_id))
		KIND_SECT:
			return String(CharData.sect_of_skill(tables, skill_id).get("sect_skill_name", skill_id))
		KIND_LIFE:
			return String(CharData.row(tables, "life_skills", skill_id).get("name", skill_id))
	return skill_id

## 技能類別（ART 的 category；其他回 ""）
static func category_of(skill_id: String, tables: Dictionary) -> String:
	return String(CharData.row(tables, "martial_arts", skill_id).get("category", ""))

## 技能本身的等級上限（資料上限，不含實戰／師父上限）
static func max_level_of(skill_id: String, tables: Dictionary) -> int:
	match kind_of(skill_id, tables):
		KIND_BASIC:
			return CharData.to_int(CharData.row(tables, "basic_skills", skill_id).get("max_level", DEFAULT_MAX_LEVEL), DEFAULT_MAX_LEVEL)
		KIND_ART:
			return CharData.to_int(CharData.row(tables, "martial_arts", skill_id).get("max_level", DEFAULT_MAX_LEVEL), DEFAULT_MAX_LEVEL)
		KIND_SECT:
			return CharData.to_int(CharData.sect_of_skill(tables, skill_id).get("sect_skill_cap", DEFAULT_SECT_CAP), DEFAULT_SECT_CAP)
		KIND_LIFE:
			return CharData.to_int(CharData.row(tables, "life_skills", skill_id).get("cap", DEFAULT_LIFE_CAP), DEFAULT_LIFE_CAP)
	return DEFAULT_MAX_LEVEL

func level(skill_id: String) -> int:
	return int(entries.get(skill_id, {}).get("level", 0))

func prof(skill_id: String) -> int:
	return int(entries.get(skill_id, {}).get("prof", 0))

func has(skill_id: String) -> bool:
	return level(skill_id) >= 1

func add_prof(skill_id: String, amount: int, tables: Dictionary, cap_level: int) -> Dictionary:
	var before := level(skill_id)
	var p: int = max(0, prof(skill_id) + amount)
	var lv := level_for_prof(skill_id, p, tables)
	var after: int = max(before, min(lv, cap_level))
	entries[skill_id] = { "level": after, "prof": p }
	return { "before": before, "after": after, "prof": p }

func set_level(skill_id: String, lv: int, tables: Dictionary) -> void:
	if lv <= 0:
		entries.erase(skill_id)
		return
	entries[skill_id] = { "level": lv, "prof": prof_for_level(skill_id, lv, tables) }

func special_arts(tables: Dictionary) -> Array:
	var out: Array = []
	for k in entries:
		if int(entries[k]["level"]) < 1:
			continue
		var r := CharData.row(tables, "martial_arts", k)
		if r.is_empty() or bool(r.get("monster_only", false)):
			continue
		out.append(k)
	out.sort()
	return out

func highest_special_art(tables: Dictionary) -> String:
	var best := ""
	for k in special_arts(tables):
		if best == "":
			best = k
			continue
		var lk := level(k)
		var lb := level(best)
		if lk > lb or (lk == lb and prof(k) > prof(best)) or (lk == lb and prof(k) == prof(best) and k < best):
			best = k
	return best

func best_level_in_category(category: String, tables: Dictionary) -> int:
	var best := 0
	for k in entries:
		var r := CharData.row(tables, "martial_arts", k)
		if r.is_empty() or r.get("category", "") != category:
			continue
		best = max(best, int(entries[k]["level"]))
	return best

## 4.3：到達等級 lv 所需的累計熟練度
static func prof_for_level(skill_id: String, lv: int, tables: Dictionary) -> int:
	if lv <= 0:
		return 0
	var L := float(lv)
	match kind_of(skill_id, tables):
		KIND_BASIC:
			var r := CharData.row(tables, "basic_skills", skill_id)
			var curve := String(r.get("curve", "CUBIC"))
			match curve:
				"QUARTIC":
					return _ceil(L * L * L * L * CharData.to_float(r.get("difficulty", 0.8), 0.8))
				"LITERACY":
					var total := 0
					for n in lv:
						total += (n + 3) * (n + 3) * 10
					return total
				_:
					return _ceil(L * L * L * CharData.to_float(r.get("difficulty", 0.9), 0.9))
		KIND_ART:
			var a := CharData.row(tables, "martial_arts", skill_id)
			return _ceil(L * L * L * CharData.to_float(a.get("difficulty", 0.9), 0.9))
		KIND_SECT:
			return _ceil(L * L * L * 1.0)
		KIND_LIFE:
			return lv * lv * 2
	return _ceil(L * L * L)

static func level_for_prof(skill_id: String, p: int, tables: Dictionary) -> int:
	var max_lv := max_level_of(skill_id, tables)
	var lv := 0
	while lv < max_lv and prof_for_level(skill_id, lv + 1, tables) <= p:
		lv += 1
	return lv

static func _ceil(x: float) -> int:
	return int(ceil(x - EPS))
