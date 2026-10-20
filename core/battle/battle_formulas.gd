class_name BattleFormulas
extends RefCounted
## 戰鬥公式（M1_PLAN 4.6、4.7）。機率類函式一律回傳 0.0–1.0 的機率（文件寫成 %）。

const GAUGE_FULL := 100.0
const WEAPON_BASIC := {
	"FIST": "basic_fist", "BLADE": "basic_blade", "SWORD": "basic_sword",
	"STAFF": "basic_staff", "WHIP": "basic_whip", "SPEAR": "basic_spear",
	"STAB": "basic_stab",
}
## M3A_PLAN 3.4／3.11：STAB（筆、刺類）加入可出招的類別
const BATTLE_CATEGORIES := ["FIST", "BLADE", "SWORD", "STAFF", "WHIP", "SPEAR", "STAB"]
const MASTERY_LEVEL := 120              # 對應基本武學 ≥ 120 → 出力固定 1.05
const DEF_MULT_DAMAGE := 0.6            # 傷害 = (攻 − 防×0.6) …

## ---- ATB 與移動（4.6） ----

static func atb_gain(u: BattleUnit, tables: Dictionary) -> float:
	var g := 4.0 + u.attr("agi") * 0.15 + u.skill("basic_body") * 0.03 + u.lightness() * 0.02
	if u.carry_ratio() > 0.8:
		g *= 0.7
	if not u.statuses.is_empty():
		g *= BattleStatus.gauge_mult(u, tables)   # 封穴等狀態讓時間棒變慢（M3A_PLAN 5.7）
	return g

static func move_range(u: BattleUnit) -> int:
	return 2 + floori(u.lightness() / 25.0)

## ---- 攻防（4.7） ----

## 出力係數：tenths ≤ 0 代表普通攻擊（固定 1.0）
static func power_factor(tenths: int, base_skill_level: int) -> float:
	if tenths <= 0:
		return 1.0
	if base_skill_level >= MASTERY_LEVEL:
		return 1.05
	return 0.55 + 0.05 * clampi(tenths, 1, 10)

static func inner_cost(move_row: Dictionary, tenths: int) -> int:
	return ceili(float(move_row.get("cost_inner", 0)) * clampi(tenths, 1, 10) / 5.0)

## 攻方兵器類別修正
static func weapon_mod(category: String) -> float:
	match category:
		"BLADE": return 0.10
		"FIST": return -0.10
	return 0.0

## 守方拆招卸力項的修正（依攻方類別）
static func parry_mod(attacker_category: String) -> float:
	match attacker_category:
		"BLADE": return -0.10
		"FIST": return 0.10
	return 0.0

static func basic_for_category(category: String) -> String:
	return WEAPON_BASIC.get(category, "basic_fist")

## 對應基本武學等級；怪物沒列出時以招式（武功）等級代替（5.3 註）
static func base_level(u: BattleUnit, base_skill: String, art_id: String, tables: Dictionary) -> int:
	var lv := u.skill(base_skill)
	if lv > 0 or u.is_player():
		return lv
	if art_id != "":
		return u.skill(art_id)
	# 普通攻擊：取第一個同基本武學的武功等級
	var arts_t: Dictionary = tables.get("martial_arts", {})
	for a in u.arts():
		var row: Dictionary = arts_t.get(str(a), {})
		if str(row.get("base_skill", "")) == base_skill:
			return u.skill(str(a))
	return 0

## 攻擊的類別：ART 用武功類別，普通攻擊用手上兵器類別
static func attack_category(u: BattleUnit, art_row: Dictionary) -> String:
	if not art_row.is_empty():
		return str(art_row.get("category", "FIST"))
	return u.weapon_type()

## 攻擊力。art_row／move_row 為空 = 普通攻擊（招式威力 0、武功等級 = 對應基本武學、出力 1.0）
static func attack_power(u: BattleUnit, art_row: Dictionary, move_row: Dictionary, tenths: int, tables: Dictionary) -> float:
	var category := attack_category(u, art_row)
	var art_id := str(art_row.get("id", ""))
	var base_skill := str(art_row.get("base_skill", "")) if not art_row.is_empty() else basic_for_category(category)
	if base_skill == "":
		base_skill = basic_for_category(category)
	var base_lv := base_level(u, base_skill, art_id, tables)
	var weapon_power := 0.0
	if category != "FIST" and category == u.weapon_type():
		weapon_power = float(u.weapon.get("atk", 0))
	var move_power := float(move_row.get("power", 0))
	var art_level := u.skill(art_id) if art_id != "" else base_lv
	var a := weapon_power + u.attr("str") * 1.5 + move_power * (1.0 + art_level / 60.0) + base_lv / 4.0
	var factor := power_factor(tenths if not art_row.is_empty() else 0, base_lv)
	a *= factor * (1.0 + weapon_mod(category)) * (1.0 + u.killing_intent() / 10000.0)
	return a

static func defense_power(u: BattleUnit, attacker_category: String, _tables: Dictionary) -> float:
	var d := u.armor_power() + u.attr("con") * 1.2 + u.skill("basic_parry") / 3.0 * (1.0 + parry_mod(attacker_category))
	d *= (1.0 - u.attr("guts") * 0.004) * (1.0 - u.killing_intent() / 20000.0)
	if u.defending:
		d *= 1.5 + u.effective_inner() / 400.0
	return d

static func hit_chance(att: BattleUnit, def: BattleUnit, art_level: int) -> float:
	var pct := 80.0 + (art_level - def.skill("basic_dodge")) * 0.3 + (att.attr("agi") - def.attr("agi")) * 0.8
	return clampf(pct, 10.0, 95.0) / 100.0

static func crit_chance(u: BattleUnit) -> float:
	return (2.0 + u.attr("guts") * 0.3) / 100.0

static func crit_mult(u: BattleUnit) -> float:
	return 1.5 + u.attr("con") * 0.01

static func float_range(u: BattleUnit) -> Vector2:
	var lo := 1.0 - (0.3 - u.attr("cal") * 0.006)
	return Vector2(minf(lo, 1.0), 1.1)

static func inner_bonus_max(u: BattleUnit) -> float:
	return u.effective_inner() / 10.0

## 傷害（不含爆擊）：max(1, round((攻 − 防×0.6) × 浮動 + 內功加成))
static func base_damage(atk_power: float, def_power: float, float_mult: float, inner_bonus: float) -> int:
	return maxi(1, roundi((atk_power - def_power * DEF_MULT_DAMAGE) * float_mult + inner_bonus))

static func apply_crit(dmg: int, mult: float) -> int:
	return maxi(1, roundi(dmg * mult))

## 門派技能觸發率（level ≥ 1）
static func proc_chance(level: int) -> float:
	if level < 1:
		return 0.0
	return minf(0.25, 0.05 + level * 0.002)

static func defense_proc_mult(level: int) -> float:
	return 0.7 - level * 0.002

static func recover_pct(level: int) -> float:
	return 0.03 + level * 0.0005

static func counter_chance(u: BattleUnit) -> float:
	var cal := u.attr("cal")
	if cal < 25:
		return 0.0
	return cal * 0.004

const COUNTER_MULT := 0.6
