class_name DeathPenalty
extends RefCounted
## 死亡懲罰（M1_PLAN 3.2.9、4.13）。不處理重生位置與屍體物件（WORLD 負責）。

const NEWBIE_XP := 500
const CASUAL_MONEY_PCT := 0.10
const RESPAWN_PCT := 0.5

static func apply(ch: Character, rules: Dictionary, tables: Dictionary) -> Dictionary:
	var rule := String(rules.get("death_rule", "STANDARD"))
	var out := { "rule": rule, "safe_newbie": false, "skill_losses": [], "dropped": [], "money_lost": 0 }
	ch.dead_count += 1
	match rule:
		"STRICT_2001":
			var ids := ch.skills.entries.keys()
			ids.sort()
			for sid in ids:
				var kind := SkillBook.kind_of(sid, tables)
				if kind == SkillBook.KIND_LIFE or kind == "":
					continue
				var lv := ch.skills.level(sid)
				if lv < 1:
					continue
				_lose(ch, sid, lv, tables, out)
			out["dropped"] = ch.inventory.take_all(tables)   # M3c：keep_on_death（神兵）不掉
		"CASUAL":
			var lost := floori(ch.money * CASUAL_MONEY_PCT)
			ch.money -= lost
			out["money_lost"] = lost
		_:  # STANDARD（未知值也以 STANDARD 處理）
			out["rule"] = "STANDARD"
			if ch.combat_xp <= NEWBIE_XP:
				out["safe_newbie"] = true
			else:
				var art := ch.skills.highest_special_art(tables)
				if art != "":
					_lose(ch, art, ch.skills.level(art), tables, out)
				out["dropped"] = ch.inventory.take_equipped(tables)   # M3c：keep_on_death（神兵）不掉
	return out

static func _lose(ch: Character, sid: String, lv: int, tables: Dictionary, out: Dictionary) -> void:
	ch.skills.set_level(sid, lv - 1, tables)
	out["skill_losses"].append({ "skill": sid, "name": SkillBook.skill_name(sid, tables), "from": lv, "to": lv - 1 })

## 精、氣、神 = 上限的 50%（無條件捨去，至少 1）；內力 = 0
static func respawn_vitals(ch: Character, tables: Dictionary, options: Dictionary) -> void:
	var d := ch.derived(tables, options)
	for k in ["jing", "qi", "shen"]:
		ch.vitals[k] = maxi(1, floori(int(d[k + "_max"]) * RESPAWN_PCT))
	ch.vitals["neili"] = 0
