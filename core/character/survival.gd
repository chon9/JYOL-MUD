class_name Survival
extends RefCounted
## 飽食飲水、自然回復、打坐、運功、休息、用藥、生日（M1_PLAN 3.2.7、4.10、4.11）。

const HUNGER_INTERVAL_S := 300.0
const LOW_THRESHOLD := 20
const REGEN_INTERVAL_S := 10.0
const REGEN_PCT := 0.02
const REGEN_NEILI_PCT := 0.01
const STARVING_REGEN_MULT := 0.25
const MEDITATE_COOLDOWN_S := 10.0
const MEDITATE_JING := 2
const CULTIVATE_QI := 8
const CULTIVATE_PER_INNER := 5
const EXERT_NEILI := 20
const EXERT_PCT := 0.15
const OVERDOSE_WINDOW_S := 60.0
const OVERDOSE_USES := 5
const EXERT_STATS := ["jing", "qi", "shen"]
const MED_STATS := ["jing", "qi", "shen", "neili"]

## 回傳通知 key 陣列（"hungry" "thirsty" "starving" "parched"，只在跨越門檻時）
static func tick(ch: Character, dt_s: float, in_battle: bool, tables: Dictionary, options: Dictionary) -> Array:
	var notes: Array = []
	if dt_s <= 0.0:
		return notes
	_drain(ch, "food", "food_acc_s", dt_s, "hungry", "starving", notes)
	_drain(ch, "water", "water_acc_s", dt_s, "thirsty", "parched", notes)
	if in_battle:
		return notes
	var acc := float(ch.counters.get("regen_acc_s", 0.0)) + dt_s
	if acc >= REGEN_INTERVAL_S:
		var d := ch.derived(tables, options)
		while acc >= REGEN_INTERVAL_S:
			acc -= REGEN_INTERVAL_S
			var mult := STARVING_REGEN_MULT if int(ch.vitals["food"]) <= 0 else 1.0
			for k in ["jing", "qi", "shen"]:
				var mx := int(d[k + "_max"])
				ch.vitals[k] = mini(mx, int(ch.vitals[k]) + int(ceil(mx * REGEN_PCT * mult - 1e-9)))
			var nmax := int(d["neili_max"])
			ch.vitals["neili"] = mini(nmax, int(ch.vitals["neili"]) + int(ceil(nmax * REGEN_NEILI_PCT * mult - 1e-9)))
	ch.counters["regen_acc_s"] = acc
	return notes

static func _drain(ch: Character, stat: String, acc_key: String, dt_s: float, low_key: String,
		zero_key: String, notes: Array) -> void:
	var acc := float(ch.counters.get(acc_key, 0.0)) + dt_s
	var before := int(ch.vitals[stat])
	var v := before
	while acc >= HUNGER_INTERVAL_S:
		acc -= HUNGER_INTERVAL_S
		v = maxi(0, v - 1)
	ch.counters[acc_key] = acc
	ch.vitals[stat] = v
	if before > LOW_THRESHOLD and v <= LOW_THRESHOLD:
		notes.append(low_key)
	if before > 0 and v <= 0:
		notes.append(zero_key)

static func meditate(ch: Character, tables: Dictionary, options: Dictionary, now_s: float) -> Dictionary:
	var out := { "ok": false, "reason": "", "kind": "", "gain": 0, "neili": int(ch.vitals["neili"]), "qi_gain": 0, "count": ch.cultivations }
	var inner := ch.skills.level("basic_inner")
	if inner < 1:
		out["reason"] = "no_inner"
		return out
	var last := float(ch.counters.get("last_meditate_s", -1.0))
	if last >= 0.0 and now_s - last < MEDITATE_COOLDOWN_S:
		out["reason"] = "busy"
		return out
	var d := ch.derived(tables, options)
	var nmax := int(d["neili_max"])
	var cur := int(ch.vitals["neili"])
	var mode := ""
	if cur < nmax:
		mode = "neili"
	elif ch.cultivations < inner * CULTIVATE_PER_INNER:
		mode = "cultivate"
	else:
		out["reason"] = "nothing_to_do"
		return out
	if int(ch.vitals["jing"]) < MEDITATE_JING:
		out["reason"] = "not_enough_jing"
		return out
	ch.vitals["jing"] = int(ch.vitals["jing"]) - MEDITATE_JING
	ch.counters["last_meditate_s"] = now_s
	if mode == "neili":
		var want: int = maxi(1, inner + floori(nmax * 0.2))
		var after := mini(nmax, cur + want)
		ch.vitals["neili"] = after
		out["gain"] = after - cur
	else:
		ch.vitals["neili"] = 0
		ch.qi_bonus += CULTIVATE_QI
		ch.cultivations += 1
		out["qi_gain"] = CULTIVATE_QI
	out["ok"] = true
	out["kind"] = mode
	out["neili"] = int(ch.vitals["neili"])
	out["count"] = ch.cultivations
	return out

static func exert(ch: Character, stat: String, tables: Dictionary, options: Dictionary) -> Dictionary:
	if not EXERT_STATS.has(stat):
		return { "ok": false, "reason": "bad_value:stat", "stat": stat, "gain": 0 }
	if int(ch.vitals["neili"]) < EXERT_NEILI:
		return { "ok": false, "reason": "not_enough_neili", "stat": stat, "gain": 0 }
	var d := ch.derived(tables, options)
	var mx := int(d[stat + "_max"])
	ch.vitals["neili"] = int(ch.vitals["neili"]) - EXERT_NEILI
	var cur := int(ch.vitals[stat])
	var after := mini(mx, cur + floori(mx * EXERT_PCT))
	ch.vitals[stat] = maxi(cur, after)
	return { "ok": true, "reason": "", "stat": stat, "gain": int(ch.vitals[stat]) - cur }

static func rest_full(ch: Character, tables: Dictionary, options: Dictionary) -> void:
	var d := ch.derived(tables, options)
	for k in ["jing", "qi", "shen", "neili"]:
		ch.vitals[k] = int(d[k + "_max"])

static func use_item(ch: Character, uid: String, tables: Dictionary, options: Dictionary, now_s: float) -> Dictionary:
	var out := { "ok": false, "reason": "", "item_id": "", "item_name": "", "effects_applied": [], "overdose": false }
	var it := ch.inventory.find(uid)
	if it.is_empty():
		out["reason"] = "no_item"
		return out
	var r := CharData.row(tables, "items", it["id"])
	out["item_id"] = it["id"]
	out["item_name"] = String(r.get("name", it["id"]))
	var effects: Variant = r.get("effects", [])
	if not bool(r.get("usable", false)) or typeof(effects) != TYPE_ARRAY or effects.is_empty():
		out["reason"] = "not_usable"
		return out
	var is_med := false
	for e in effects:
		if typeof(e) == TYPE_DICTIONARY and e.get("type", "") == "restore" and MED_STATS.has(e.get("stat", "")):
			is_med = true
	var overdose := false
	if is_med:
		var uses: Array = []
		for t in ch.counters.get("med_uses", []):
			if now_s - float(t) < OVERDOSE_WINDOW_S:
				uses.append(float(t))
		overdose = uses.size() >= OVERDOSE_USES
		uses.append(now_s)
		ch.counters["med_uses"] = uses
	var d := ch.derived(tables, options)
	var applied: Array = []
	for e in effects:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var stat := String(e.get("stat", ""))
		var val := CharData.to_int(e.get("value", 0))
		match String(e.get("type", "")):
			"restore":
				if not ch.vitals.has(stat):
					continue
				var mx: int = Character.FOOD_MAX if stat == "food" else (Character.WATER_MAX if stat == "water" else int(d[stat + "_max"]))
				var cur := int(ch.vitals[stat])
				ch.vitals[stat] = maxi(cur, mini(mx, cur + val))
				applied.append({ "stat": stat, "gain": int(ch.vitals[stat]) - cur })
			"smoke":
				ch.buffs["smoke_until_s"] = now_s + float(val)
				applied.append({ "stat": "smoke", "gain": val })
			"cure":
				# M3A_PLAN 3.9、6.10：戰鬥外解除戰後持續狀態（等級 ≤ max_level 才解得掉）；gain = 解掉的等級（0 = 沒解）
				var sid := String(e.get("status", ""))
				var lv := ch.condition_level(sid)
				var cured := 0
				if lv > 0 and lv <= CharData.to_int(e.get("max_level", 0)):
					ch.clear_condition(sid)
					cured = lv
				applied.append({ "stat": "cure", "status": sid, "gain": cured })
	# M3b 審查 3：keep_on_use 的物品（絕情丹「一人一顆」）用了不消失——原作一人只給一顆，用掉就再也拿不到會變成陷阱
	if not bool(r.get("keep_on_use", false)):
		ch.inventory.remove(uid, 1)
	out["kept"] = bool(r.get("keep_on_use", false))
	if overdose:
		for k in ["jing", "qi", "shen"]:
			ch.vitals[k] = 1
	out["ok"] = true
	out["effects_applied"] = applied
	out["overdose"] = overdose
	out["sect_skill_loss"] = _meat_penalty(ch, r, tables)
	if (out["sect_skill_loss"] as Dictionary).is_empty():
		out["sect_skill_loss"] = _wine_penalty(ch, r, tables)
	return out

## 全真飲酒：sects.sect_skill_penalties 的 DRINK 列 → 門派技能（養生）降 levels 級【已證實：飲酒減低養生；級數設計提案】；
## 哪些物品算酒（items.alcohol）【設計提案】。回傳 {} 或 { skill, name, from, to, kind: "WINE" }（M3a 審查 A4）
static func _wine_penalty(ch: Character, item_row: Dictionary, tables: Dictionary) -> Dictionary:
	if not bool(item_row.get("alcohol", false)) or ch.sect == "":
		return {}
	var srow := CharData.row(tables, "sects", ch.sect)
	var levels := 0
	for p in srow.get("sect_skill_penalties", []):
		if p is Dictionary and String(p.get("trigger", "")) == "DRINK":
			levels += maxi(1, CharData.to_int(p.get("levels", 1)))
	var sk := String(srow.get("sect_skill", ""))
	var lv := ch.skills.level(sk)
	if levels <= 0 or sk == "" or lv <= 0:
		return {}
	var after := maxi(0, lv - levels)
	ch.skills.set_level(sk, after, tables)
	return { "skill": sk, "name": SkillBook.skill_name(sk, tables), "from": lv, "to": after, "kind": "WINE" }

## 少林吃葷：門派技能（佛法）降一級【已證實】；哪些物品算葷（items.meat）【設計提案】。
## 回傳 {} 或 { skill, name, from, to }
static func _meat_penalty(ch: Character, item_row: Dictionary, tables: Dictionary) -> Dictionary:
	if not bool(item_row.get("meat", false)) or ch.sect == "":
		return {}
	var srow := CharData.row(tables, "sects", ch.sect)
	if not bool(srow.get("forbid_meat", false)):
		return {}
	var sk := String(srow.get("sect_skill", ""))
	var lv := ch.skills.level(sk)
	if sk == "" or lv <= 0:
		return {}
	ch.skills.set_level(sk, lv - 1, tables)   # 熟練度設為新等級的門檻（同 DeathPenalty._lose）
	return { "skill": sk, "name": SkillBook.skill_name(sk, tables), "from": lv, "to": lv - 1 }

static func eat_meal(ch: Character, food: int, water: int) -> void:
	ch.vitals["food"] = clampi(int(ch.vitals["food"]) + food, 0, Character.FOOD_MAX)
	ch.vitals["water"] = clampi(int(ch.vitals["water"]) + water, 0, Character.WATER_MAX)

static func birthday_check(ch: Character, game_year: int, game_month: int, rng: RandomNumberGenerator) -> String:
	if game_month != ch.birth_month:
		return ""
	if int(ch.counters.get("last_birthday_year", 0)) >= game_year:
		return ""
	ch.counters["last_birthday_year"] = game_year
	var attr: String = Character.ATTR_IDS[rng.randi_range(0, Character.ATTR_IDS.size() - 1)]
	ch.attrs[attr] = int(ch.attrs[attr]) + 1
	return attr
