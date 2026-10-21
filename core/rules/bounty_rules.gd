class_name BountyRules
extends RefCounted
## 懸賞與律法的純規則（M3D_PLAN §2.1；WP-LAW）。純靜態、只吃參數（balance_sim 與單元測試直接用）。
## 研究（verified_research「M3d 研究」懸賞）：佈告欄「觀看懸賞名單」、兩位官爺（一位耳聾）發賞金獵人執照、
## 執照限 PK值 0、持照擊殺名單上的人不算惡意 PK、死於守衛或特定 NPC PK值 −1、天師 100 兩消 10 殺氣【已證實】。
## 上名單的門檻、金額、誰出錢、執照費用、半仙價錢、NPC 獵人強度【設計提案】（R1–R7）。

const LIST_PK_MIN := 4                 # PK值 ≥ 4（＝ 守城官兵追殺的門檻 > 3）
const LIST_EVIL_PK_MIN := 1            # 或 PK值 ≥ 1 且善惡 ≤ LIST_EVIL_MORALITY
const LIST_EVIL_MORALITY := -101
const FINE_PER_PK := 1000
const FINE_EVIL_BONUS := 500
const FINE_CAP := 20000
const POOL_ADD_MIN := 100
const POOL_CAP := 100000               # 每個目標的加碼上限
const LICENSE_FEE := 100
const LAWFUL_KILLING_INTENT := 20
const TIANSHI_PRICE_PER_10 := 100      # 【已證實 7-11 news_2-5、news_3-2】
const TIANSHI_PER_TIME := 10           # 每次消 10 點殺氣【已證實】
const TIANSHI_MAX_TIMES := 100
const BANXIAN_PRICE_PER_PK := 10000
const BANXIAN_PER_DAY := 1
const HUNTER_CHANCE_PCT := 8           # 名單上的人每進一間野外房間的機率
const HUNTER_COOLDOWN_SHICHEN := 1     # 遇過一次（不論逃掉或開打）之後的冷卻
const HUNTER_TIER_XP := [20000, 100000]  # < 2 萬 → 1；< 10 萬 → 2；其他 → 3
const HUNTER_MONSTERS := ["m_law_hunter_1", "m_law_hunter_2", "m_law_hunter_3"]

## 上名單（R1）：新手（實戰 < protect_xp）不上；PK值 ≥ 4，或 PK值 ≥ 1 且善惡 ≤ −101
static func listed(pk: int, morality: int, combat_xp: int, protect_xp: int) -> bool:
	if combat_xp < protect_xp:
		return false
	if pk >= LIST_PK_MIN:
		return true
	return pk >= LIST_EVIL_PK_MIN and morality <= LIST_EVIL_MORALITY

## 罰金（R2）：min(FINE_CAP, 1000 × PK值 ＋ 惡人 500)；PK值 0 → 0
static func fine(pk: int, morality: int) -> int:
	if pk <= 0:
		return 0
	var f := FINE_PER_PK * pk + (FINE_EVIL_BONUS if morality <= LIST_EVIL_MORALITY else 0)
	return mini(FINE_CAP, f)

## 從被懸賞者自己的錢扣：先身上、再錢莊，扣不到的就沒有（系統不出錢）。回 { from_money, from_bank, total }
static func collect(fine_amount: int, money: int, bank: int) -> Dictionary:
	var need := maxi(0, fine_amount)
	var a := mini(need, maxi(0, money))
	var b := mini(need - a, maxi(0, bank))
	return { "from_money": a, "from_bank": b, "total": a + b }

## 領執照的原因碼（""＝可以領）：PK值 > 0 → license_pk；在名單上 → license_listed；錢不夠 → not_enough_money
static func license_reason(pk: int, is_listed: bool, money: int) -> String:
	if pk > 0:
		return "license_pk"
	if is_listed:
		return "license_listed"
	if money < LICENSE_FEE:
		return "not_enough_money"
	return ""

## 合法緝拿：有執照、獵人 PK值 0、目標在名單上
static func lawful(has_license: bool, hunter_pk: int, target_listed: bool) -> bool:
	return has_license and hunter_pk <= 0 and target_listed

## NPC 賞金獵人的強度（1..3），依目標實戰
static func hunter_tier(combat_xp: int) -> int:
	if combat_xp < int(HUNTER_TIER_XP[0]):
		return 1
	if combat_xp < int(HUNTER_TIER_XP[1]):
		return 2
	return 3

static func hunter_monster(tier: int) -> String:
	return str(HUNTER_MONSTERS[clampi(tier, 1, 3) - 1])

## M3d 審查（第 3 輪）：獵人只在各階頂端校準過（2 萬／10 萬／20 萬，三列的 combat_xp_ref）→ 同一階的底端（剛過新手保護、
## 2 萬出頭、10 萬出頭）幾乎必死（不能逃、勝率 0%），20 萬以上又打不動目標（50 萬勝率 100%；研究：獵人「遙不可及」）。
## 改成依目標實戰決定獵人的數值（名字、招式、兵器種類仍照 hunter_tier 那一階）：
## - 兩個校準點之間：數值（屬性、氣、內力、精、武學等級、兵器、護甲）照 √實戰 在兩列之間線性內插；
## - 低於 2 萬、高於 20 萬：從最近的校準列外推——武學、兵器、護甲 × r，屬性的「超過 20 的部分」× r，
##   氣、內力、精照參考角色的氣（180 + 上限 × 20）的比例；r ＝ 武學上限(目標) ÷ 武學上限(ref)（本作上限 5+⌊√(實戰/10)⌋）。
## 數字全部【設計提案】；balance_sim law_hunter_tiers 量各階底端、中段、頂端與 50 萬、100 萬。
const HUNTER_ATTR_BASE := 20
const HUNTER_DOWN_EXP := 1.15
const HUNTER_NUM_KEYS := ["qi", "qi_max", "neili", "neili_max", "jing", "jing_max", "shen", "shen_max", "armor_power",
	"effective_inner", "lightness"]

## 獵人規格的數值部分改成「目標實戰 target_xp」的版本（就地修改 spec；tables 要有三列獵人，缺列就不動）
static func apply_hunter_xp(spec: Dictionary, target_xp: int, tables: Dictionary) -> void:
	if spec.is_empty():
		return
	var anchors: Array = []   # [{ ref, spec }]，ref 遞增
	for mid in HUNTER_MONSTERS:
		var row: Dictionary = tables.get("monsters", {}).get(mid, {})
		var sp := Encounter.monster_spec(mid, tables)
		if row.is_empty() or sp.is_empty() or int(row.get("combat_xp_ref", 0)) <= 0:
			return
		anchors.append({ "ref": int(row["combat_xp_ref"]), "spec": sp })
	anchors.sort_custom(func(a, b): return int(a.ref) < int(b.ref))
	var x := maxi(0, target_xp)
	var num := {}
	if x <= int(anchors[0].ref):
		num = _hunter_extrapolate(anchors[0].spec, x, int(anchors[0].ref))
	elif x >= int(anchors[-1].ref):
		num = _hunter_extrapolate(anchors[-1].spec, x, int(anchors[-1].ref))
	else:
		for k in anchors.size() - 1:
			var a0: int = anchors[k].ref
			var a1: int = anchors[k + 1].ref
			if x >= a0 and x <= a1:
				var t := (sqrt(float(x)) - sqrt(float(a0))) / maxf(0.0001, sqrt(float(a1)) - sqrt(float(a0)))
				num = _hunter_lerp(_hunter_numbers(anchors[k].spec), _hunter_numbers(anchors[k + 1].spec), t)
				break
	if num.is_empty():
		return
	for k in HUNTER_NUM_KEYS:
		if spec.has(k) and num.has(k):
			spec[k] = maxi(0 if k in ["armor_power", "effective_inner", "lightness"] else 1, roundi(float(num[k])))
	if spec.get("attrs") is Dictionary and num.get("attrs") is Dictionary:
		for a in (spec["attrs"] as Dictionary).keys():
			if (num["attrs"] as Dictionary).has(a):
				spec["attrs"][a] = maxi(1, roundi(float(num["attrs"][a])))
	if spec.get("skills") is Dictionary:
		for k in (spec["skills"] as Dictionary).keys():
			spec["skills"][k] = maxi(1, roundi(float(num.get("skill", spec["skills"][k]))))
	if spec.get("weapon") is Dictionary:
		spec["weapon"]["atk"] = maxi(0, roundi(float(num.get("atk", 0))))

## 一列獵人的數值：{ 數值欄位…, attrs: {}, skill: 武學等級（取最高）, atk }
static func _hunter_numbers(sp: Dictionary) -> Dictionary:
	var out := {}
	for k in HUNTER_NUM_KEYS:
		out[k] = float(sp.get(k, 0))
	var at := {}
	for a in (sp.get("attrs", {}) as Dictionary):
		at[a] = float(sp["attrs"][a])
	out["attrs"] = at
	var best := 1
	for k in (sp.get("skills", {}) as Dictionary):
		best = maxi(best, int(sp["skills"][k]))
	out["skill"] = float(best)
	out["atk"] = float((sp.get("weapon", {}) as Dictionary).get("atk", 0))
	return out

static func _hunter_lerp(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		if a[k] is Dictionary:
			var d := {}
			for kk in a[k]:
				d[kk] = lerpf(float(a[k][kk]), float((b.get(k, {}) as Dictionary).get(kk, a[k][kk])), t)
			out[k] = d
		else:
			out[k] = lerpf(float(a[k]), float(b.get(k, a[k])), t)
	return out

static func _hunter_extrapolate(sp: Dictionary, x: int, ref: int) -> Dictionary:
	var n := _hunter_numbers(sp)
	var cap_t := DerivedStats.art_level_cap(x)
	var cap_r := DerivedStats.art_level_cap(ref)
	var r := float(cap_t) / float(cap_r)
	var q := float(180 + cap_t * 20) / float(180 + cap_r * 20)
	if x < ref:   # 往下外推再放一點（參考角色在低實戰時屬性追不上武學比例；balance_sim law_hunter_t1_mid 校準）
		r = pow(r, HUNTER_DOWN_EXP)
		q = pow(q, HUNTER_DOWN_EXP)
	for k in ["qi", "qi_max", "neili", "neili_max", "jing", "jing_max", "shen", "shen_max"]:
		n[k] = float(n[k]) * q
	for k in ["armor_power", "effective_inner", "lightness", "skill", "atk"]:
		n[k] = float(n[k]) * r
	var at: Dictionary = n["attrs"]
	for a in at:
		at[a] = maxf(10.0, HUNTER_ATTR_BASE + (float(at[a]) - HUNTER_ATTR_BASE) * r)
	return n

## 天師：每次 −10 殺氣、−100 兩；times 截到付得起與殺氣夠扣的次數（每次要整整 10 點；不滿 10 的零頭不收、也不消，
## 例：殺氣 95 要消 10 次 → 只消 9 次、900 兩，剩 5）。回 { times, cost, drop }
static func tianshi(killing_intent: int, times: int, money: int) -> Dictionary:
	var want := clampi(times, 0, TIANSHI_MAX_TIMES)
	var by_intent := maxi(0, killing_intent) / TIANSHI_PER_TIME
	var by_money := maxi(0, money) / TIANSHI_PRICE_PER_10
	var n := mini(want, mini(by_intent, by_money))
	var drop := mini(maxi(0, killing_intent), n * TIANSHI_PER_TIME)
	return { "times": n, "cost": n * TIANSHI_PRICE_PER_10, "drop": drop }

## 京城半仙：PK值 0 → cleanse_nothing；今天已用滿 → cleanse_daily；錢不夠 → not_enough_money。回 { ok, reason, cost }
static func banxian(pk: int, money: int, used_today: int) -> Dictionary:
	if pk <= 0:
		return { "ok": false, "reason": "cleanse_nothing", "cost": 0 }
	if used_today >= BANXIAN_PER_DAY:
		return { "ok": false, "reason": "cleanse_daily", "cost": 0 }
	if money < BANXIAN_PRICE_PER_PK:
		return { "ok": false, "reason": "not_enough_money", "cost": BANXIAN_PRICE_PER_PK }
	return { "ok": true, "reason": "", "cost": BANXIAN_PRICE_PER_PK }
