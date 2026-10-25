class_name RogueRules
extends RefCounted
## 江湖試煉的規則常數與純函式（ROGUE_PLAN §3.1、§3.8、§3.9.2）【設計提案・非原作】。
## 數字一律來自 data/rogue_rules.json 的唯一列 rg_rules；缺列或缺鍵時用 DEFAULTS（同值）。
## core 不碰 Autoload：tables 由呼叫端（server 或 balance_sim）傳進來。

const RULES_ID := "rg_rules"                       # data/rogue_rules.json 的唯一列
const PHASES := ["ALLOC", "PICK", "READY", "BATTLE", "OVER"]
const KINDS := ["ART", "WEAPON", "ATTR", "ALLY"]
const RARITIES := ["COMMON", "FINE", "RARE", "TREASURE", "DIVINE"]   # 凡 良 稀 珍 神
const RARITY_NAMES := { "COMMON": "凡", "FINE": "良", "RARE": "稀", "TREASURE": "珍", "DIVINE": "神" }
const CAUSES := ["DEATH", "ABANDON", "TIMEOUT", "LEAVE"]

const DEFAULTS := {
	"attr_cap": 45, "art_cap": 150, "weapons_keep": 3, "ally_max": 2, "ally_min_round": 2, "boss_every": 5,
	"kind_weights": { "ART": 35, "WEAPON": 25, "ATTR": 25, "ALLY": 15 },
	"rarity_bands": [{ "from": 1, "w": [60, 30, 10, 0, 0] }, { "from": 4, "w": [40, 35, 20, 5, 0] },
		{ "from": 7, "w": [25, 35, 27, 11, 2] }, { "from": 10, "w": [15, 30, 32, 18, 5] }, { "from": 15, "w": [10, 25, 33, 23, 9] }],
	"boss_reward_w": [0, 0, 60, 30, 10],
	"attr_points": { "COMMON": 3, "FINE": 4, "RARE": 6, "TREASURE": 8, "DIVINE": 10 },
	"art_level": { "COMMON": 25, "FINE": 40, "RARE": 60, "TREASURE": 80, "DIVINE": 100 },
	"upgrade_by": { "COMMON": 15, "FINE": 20, "RARE": 25, "TREASURE": 30, "DIVINE": 35 },
	"ally_share": { "COMMON": 0.35, "FINE": 0.45, "RARE": 0.60, "TREASURE": 0.75, "DIVINE": 0.90 },
	"p0_mult": 0.9, "growth": 1.16, "diff_start": 0.80, "diff_step": 0.04, "diff_max": 1.20, "blend": 0.5, "boss_mult": 1.15,
	"ally_weight": 1.0,   # 隊友計入我方戰力的比重（ROGUE_PLAN 缺漏的補充；資料列的校準值見 data/rogue_rules.json）
	# 0.7.x 試煉審查（【設計提案】；資料列的校準值見 data/rogue_rules.json）：
	"renown_share": 0.0,  # 永久點數有幾成也算進「參考新角色」（江湖名聲：前幾回合不會因為點數多就變成走過場）
	"renown_fade": 10,    # 江湖名聲逐回合淡出：第 1 回合全額、第 1+renown_fade 回合起為 0（點數的好處留到後面的硬仗）
	"restore_pct": 0.35, "restore_neili_pct": 0.5,
	"points_cap": 60, "points_k": 1.5, "points_soft": 20, "points_half": 30,
}

## rogue_rules 列（缺 → DEFAULTS）；另外附上 "p0"＝參考新角色的戰力（RoguePower.reference_power；RogueFoes.target 用）
static func rules(tables: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var row: Variant = tables.get("rogue_rules", {}).get(RULES_ID, {})
	if row is Dictionary:
		for k in row:
			if DEFAULTS.has(k) and typeof(row[k]) == typeof(DEFAULTS[k]):
				out[k] = row[k].duplicate(true) if (row[k] is Dictionary or row[k] is Array) else row[k]
			elif DEFAULTS.has(k) and (typeof(DEFAULTS[k]) == TYPE_FLOAT or typeof(DEFAULTS[k]) == TYPE_INT) \
					and (typeof(row[k]) == TYPE_FLOAT or typeof(row[k]) == TYPE_INT):
				out[k] = float(row[k]) if typeof(DEFAULTS[k]) == TYPE_FLOAT else int(row[k])
	out["p0"] = RoguePower.reference_power(tables)
	return out

static func rarity_index(rarity: String) -> int:
	var i := RARITIES.find(rarity)
	return i if i >= 0 else 0

static func rarity_name(rarity: String) -> String:
	return str(RARITY_NAMES.get(rarity, RARITY_NAMES["COMMON"]))

## §3.9.2：raw = ⌊k·√勝⌋ + 首領 + (新紀錄且 ≥ 3 勝 ? 1 : 0)；累計 ≥ soft 之後遞減 raw·half/(half+total)（至少 1，raw 為 0 時 0）；不超過上限
static func award(wins: int, bosses: int, total: int, new_best: bool, r: Dictionary) -> int:
	var k := float(r.get("points_k", DEFAULTS["points_k"]))
	var soft := int(r.get("points_soft", DEFAULTS["points_soft"]))
	var half := float(r.get("points_half", DEFAULTS["points_half"]))
	var cap := int(r.get("points_cap", DEFAULTS["points_cap"]))
	wins = maxi(0, wins)
	bosses = maxi(0, bosses)
	total = maxi(0, total)
	var raw := int(floor(k * sqrt(float(wins)) + 1e-9)) + bosses + (1 if new_best and wins >= 3 else 0)
	var got := raw
	if total >= soft:
		got = maxi(mini(1, raw), roundi(raw * half / (half + total)))
	return clampi(got, 0, maxi(0, cap - total))

## §3.8、O13：氣、精、神 + 最大值 × restore_pct，內力 + 最大值 × restore_neili_pct（首領回合全滿）；飽食飲水補滿、戰後狀態清掉。
## 回傳實際加了多少 { qi, jing, shen, neili }
static func restore(ch: Character, tables: Dictionary, options: Dictionary, boss: bool, r: Dictionary) -> Dictionary:
	var d: Dictionary = ch.derived(tables, options)
	var pct := float(r.get("restore_pct", DEFAULTS["restore_pct"]))
	var npct := float(r.get("restore_neili_pct", DEFAULTS["restore_neili_pct"]))
	var out := {}
	for k in ["qi", "jing", "shen", "neili"]:
		var mx := int(d[k + "_max"])
		var cur := clampi(int(ch.vitals.get(k, 0)), 0, mx)
		var add := mx - cur
		if not boss:
			add = mini(add, int(floor(mx * (npct if k == "neili" else pct))))
		ch.vitals[k] = cur + add
		out[k] = add
	ch.vitals["food"] = Character.FOOD_MAX
	ch.vitals["water"] = Character.WATER_MAX
	ch.conditions = {}
	return out

static func is_boss_round(round: int, r: Dictionary) -> bool:
	var every := maxi(1, int(r.get("boss_every", DEFAULTS["boss_every"])))
	return round > 0 and round % every == 0

## 回合的稀有度權重（rarity_bands 中 from ≤ round 的最後一列）；min_rarity 非空時用 boss_reward_w，再把低於它的歸 0
static func rarity_weights(round: int, r: Dictionary, min_rarity: String = "") -> Array:
	var w: Array = [60, 30, 10, 0, 0]
	if min_rarity != "":
		w = (r.get("boss_reward_w", DEFAULTS["boss_reward_w"]) as Array).duplicate()
	else:
		var best_from := -1
		for band in r.get("rarity_bands", DEFAULTS["rarity_bands"]):
			if band is Dictionary and int(band.get("from", 1)) <= round and int(band.get("from", 1)) > best_from:
				best_from = int(band["from"])
				w = (band.get("w", w) as Array).duplicate()
	while w.size() < RARITIES.size():
		w.append(0)
	if min_rarity != "":
		for i in rarity_index(min_rarity):
			w[i] = 0
	for i in w.size():
		w[i] = maxi(0, int(w[i]))
	return w

## 權重陣列擲一個索引；全 0 → -1
static func pick_weighted(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0
	for x in weights:
		total += maxi(0, int(x))
	if total <= 0:
		return -1
	var left := rng.randi_range(1, total)
	for i in weights.size():
		left -= maxi(0, int(weights[i]))
		if left <= 0:
			return i
	return weights.size() - 1

## 中文數字（1–999；卡面「四十級」）
const CN_DIGITS := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
static func cn_number(n: int) -> String:
	if n <= 0:
		return CN_DIGITS[0]
	if n >= 1000:
		return str(n)
	var out := ""
	var h := n / 100
	var t := (n / 10) % 10
	var o := n % 10
	if h > 0:
		out += CN_DIGITS[h] + "百"
		if t == 0 and o > 0:
			out += "零"
	if t > 0:
		if not (t == 1 and h == 0):
			out += CN_DIGITS[t]
		out += "十"
	if o > 0:
		out += CN_DIGITS[o]
	return out
