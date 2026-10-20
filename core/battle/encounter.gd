class_name Encounter
extends RefCounted
## 踩地雷遇敵（M1_PLAN 4.14）與怪物的戰鬥者規格（3.3）。

const MAX_MONSTERS := 4
const ATTR_IDS := ["str", "guts", "wit", "luck", "cal", "agi", "con"]
const DEFAULT_ATTR := 10       # 怪物 stats 缺的屬性（例：悟性、福緣）【設計提案】
const DEFAULT_JING := 100      # 怪物 stats 沒有精時【設計提案】

## 回傳怪物 id 陣列；空 = 沒遇敵。rate_mult：守護者之煙 = 0.1。
static func roll(room: Dictionary, rng: RandomNumberGenerator, rate_mult: float = 1.0) -> Array:
	var enc: Variant = room.get("encounter", null)
	if not (enc is Dictionary) or enc.is_empty():
		return []
	var table: Array = enc.get("table", [])
	var rate := float(enc.get("rate", 0.0)) * rate_mult
	if table.is_empty() or rate <= 0.0:
		return []
	if rng.randf() >= rate:
		return []
	return pick(room, rng)

## 只依遇敵表的權重挑一組怪物（不擲遇敵率）：踩地雷擲中之後、以及「查看偵察」（必定發現）共用。
## 數量規則與 roll 相同（count [lo, hi]，最多 MAX_MONSTERS 隻）；表空或權重全 0 → []。
static func pick(room: Dictionary, rng: RandomNumberGenerator) -> Array:
	var enc: Variant = room.get("encounter", null)
	if not (enc is Dictionary) or enc.is_empty():
		return []
	var table: Array = enc.get("table", [])
	if table.is_empty():
		return []
	var total := 0
	for r in table:
		total += maxi(0, int(r.get("w", 0)))
	if total <= 0:
		return []
	var left := rng.randi_range(1, total)
	var row: Dictionary = table[table.size() - 1]
	for r in table:
		left -= maxi(0, int(r.get("w", 0)))
		if left <= 0:
			row = r
			break
	var cnt: Array = row.get("count", [1, 1])
	var lo := int(cnt[0]) if cnt.size() > 0 else 1
	var hi := int(cnt[1]) if cnt.size() > 1 else lo
	var n := clampi(rng.randi_range(mini(lo, hi), maxi(lo, hi)), 1, MAX_MONSTERS)
	var out: Array = []
	for i in n:
		out.append(str(row.get("monster", "")))
	return out

const DUP_SUFFIXES := ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]

## 一場戰鬥的所有怪物規格；同名怪物不只一隻時，名字加上 甲／乙／丙…（棋子取簡稱最後一字＋序號，例「兔甲」）
static func monster_specs(monster_ids: Array, tables: Dictionary) -> Array:
	var specs: Array = []
	var counts := {}
	for mid in monster_ids:
		var spec := monster_spec(str(mid), tables)
		if spec.is_empty():
			continue
		specs.append(spec)
		counts[spec["name"]] = int(counts.get(spec["name"], 0)) + 1
	var seen := {}
	for spec in specs:
		var nm: String = spec["name"]
		if int(counts[nm]) <= 1:
			continue
		var i := int(seen.get(nm, 0))
		seen[nm] = i + 1
		var suffix: String = DUP_SUFFIXES[i] if i < DUP_SUFFIXES.size() else str(i + 1)
		var short: String = spec.get("short", "")
		if short == "":
			short = nm
		spec["name"] = nm + suffix
		spec["short"] = short.right(1) + suffix
	return specs

## 怪物的戰鬥者規格（3.3）。找不到怪物回 {}。
static func monster_spec(monster_id: String, tables: Dictionary) -> Dictionary:
	var row: Dictionary = tables.get("monsters", {}).get(monster_id, {})
	if row.is_empty():
		return {}
	var stats: Dictionary = row.get("stats", {})
	var attrs := {}
	for a in ATTR_IDS:
		attrs[a] = int(stats.get(a, DEFAULT_ATTR))
	var skills := {}
	for k in row.get("skills", {}):
		var lv := int(row.skills[k])
		if lv >= 1:
			skills[str(k)] = lv
	var arts: Array = []
	var arts_t: Dictionary = tables.get("martial_arts", {})
	var best_inner := 0
	var best_light := 0
	# M3A_PLAN 5.5：怪物也有 cmd_arts（從 arts 依類別分類；INNER 依等級高到低；ACUPOINT = acupoint:true）
	var cmd_arts := { "POISON": [], "MEDIC": [], "HIDDEN": [], "FORMATION": [], "INNER": [], "ACUPOINT": [] }
	var inner_lv := {}
	for a in row.get("arts", []):
		var aid := str(a.get("art", "")) if a is Dictionary else str(a)
		var lv := int(a.get("level", 1)) if a is Dictionary else 1
		if aid == "" or lv < 1:
			continue
		skills[aid] = maxi(lv, int(skills.get(aid, 0)))
		var cat := str(arts_t.get(aid, {}).get("category", ""))
		if cmd_arts.has(cat) and not (cmd_arts[cat] as Array).has(aid):
			(cmd_arts[cat] as Array).append(aid)
			if cat == "INNER":
				inner_lv[aid] = lv
		if bool(arts_t.get(aid, {}).get("acupoint", false)) and not (cmd_arts.ACUPOINT as Array).has(aid):
			(cmd_arts.ACUPOINT as Array).append(aid)
		if BattleFormulas.BATTLE_CATEGORIES.has(cat):
			arts.append(aid)
		elif cat == "INNER":
			best_inner = maxi(best_inner, lv)
		elif cat == "LIGHTNESS":
			best_light = maxi(best_light, lv)
	(cmd_arts.INNER as Array).sort_custom(func(x, y): return int(inner_lv[x]) > int(inner_lv[y]))
	var qi := maxi(1, int(stats.get("qi", 1)))
	var neili := int(stats.get("neili", 0))
	var jing := int(stats.get("jing", DEFAULT_JING))
	var shen := int(stats.get("shen", jing))
	var wtype := str(row.get("weapon_type", "FIST"))
	if wtype == "":
		wtype = "FIST"
	var weapon := { "uid": "", "item_id": "", "weapon_type": wtype, "atk": int(row.get("weapon_power", 0)), "name": "" }
	return {
		"kind": "MONSTER",
		"ref": monster_id,
		"name": str(row.get("name", monster_id)),
		"short": str(row.get("short", "")),
		"side": 1,
		"peer": 0,
		"ai": str(row.get("ai", "melee_basic")) if str(row.get("ai", "")) != "" else "melee_basic",
		"attrs": attrs,
		"qi": qi, "qi_max": qi, "neili": neili, "neili_max": neili,
		"jing": jing, "jing_max": jing, "shen": shen, "shen_max": shen,
		"skills": skills,
		"arts": arts,
		"weapon": weapon,
		"weapon_options": [],
		"armor_power": int(row.get("armor_power", 0)),
		"effective_inner": int(skills.get("basic_inner", 0)) + floori(best_inner / 2.0),
		"lightness": best_light,
		"sect_skill": {},
		"killing_intent": 0,
		"carry_ratio": 0.0,
		"monster_row": monster_id,
		# M3A_PLAN 5.5
		"cmd_arts": cmd_arts,
		"hidden_items": [],
		"battle_items": [],
		"statuses": {},
		"gender": "",
		"sect": str(row.get("sect", "")),
		"party_id": "",
	}
