class_name DerivedStats
extends RefCounted
## 衍生數值（M1_PLAN 4.2、4.4）。

const QI_BASE := 60
const QI_PER_CON := 6
const JING_BASE := 50
const JING_PER_WIT := 2
const SHEN_BASE := 50
const SHEN_PER_CAL := 2
const PER10_BONUS := 8
const NEILI_PER_INNER := 5
const CARRY_PER_CON := 3
const CARRY_PER_STR := 5

static func compute(ch: Character, tables: Dictionary, options: Dictionary) -> Dictionary:
	var a := ch.effective_attrs(tables, options)
	var inner := ch.skills.level("basic_inner")
	var literacy := ch.skills.level("basic_literacy")
	var weapon_row := ch.inventory.equipped_row("WEAPON", tables)
	return {
		"jing_max": JING_BASE + int(a["wit"]) * JING_PER_WIT + floori(inner / 10.0) * PER10_BONUS,
		"qi_max": QI_BASE + int(a["con"]) * QI_PER_CON + ch.qi_bonus,
		"shen_max": SHEN_BASE + int(a["cal"]) * SHEN_PER_CAL + floori(literacy / 10.0) * PER10_BONUS,
		"neili_max": inner * NEILI_PER_INNER,
		"carry_max": int(a["con"]) * CARRY_PER_CON + int(a["str"]) * CARRY_PER_STR,
		"carry": ch.inventory.weight(tables),
		"weapon_power": CharData.to_int(weapon_row.get("atk", 0)),
		"weapon_type": String(weapon_row.get("weapon_type", "FIST")) if not weapon_row.is_empty() else "FIST",
		"armor_power": armor_power(ch.inventory, tables),
		"effective_inner": effective_inner(ch.skills, tables),
		"lightness": ch.skills.best_level_in_category("LIGHTNESS", tables),
		"art_level_cap": art_level_cap(ch.combat_xp),
		"attrs": a,
	}

## M3C_PLAN §6.3：armor_power = 7 個防具欄（WEAPON 以外）的 def 加總
static func armor_power(inv: Inventory, tables: Dictionary) -> int:
	var total := 0
	for slot in Inventory.SLOTS:
		if slot == "WEAPON":
			continue
		total += CharData.to_int(inv.equipped_row(slot, tables).get("def", 0))
	return total

## 4.4：5 + ⌊√(實戰/10)⌋
static func art_level_cap(combat_xp: int) -> int:
	return 5 + int(floor(sqrt(maxi(0, combat_xp) / 10.0) + 1e-9))

## 4.2：基本內功 + ⌊最高 INNER 武功等級 / 2⌋
static func effective_inner(book: SkillBook, tables: Dictionary) -> int:
	return book.level("basic_inner") + floori(book.best_level_in_category("INNER", tables) / 2.0)
