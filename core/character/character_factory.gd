class_name CharacterFactory
extends RefCounted
## 創角（M1_PLAN 3.2.4、4.1）。

const ROLL_CAP := 25
const FREE_POINTS := 5
const NAME_MAX := 8
const START_MONEY := 100
const START_LEARN_POINTS := 100
const START_ITEMS := [   # [item_id, n, equip]
	["c_jingyao", 5, false],
	["a_bupao", 1, true],
	["w_mudao", 1, true],
]
const BAD_NAME_CHARS := [" ", "\t", "\n", "\r", "　", " ", "[", "]", "{", "}", "<", ">"]

## 每項 = 9 + 4d4 → [13, 25]
static func roll(rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for a in Character.ATTR_IDS:
		var v := 9
		for i in 4:
			v += rng.randi_range(1, 4)
		out[a] = min(v, ROLL_CAP)
	return out

static func validate_alloc(alloc: Dictionary) -> String:
	var total := 0
	for k in alloc:
		if typeof(k) != TYPE_STRING or not Character.ATTR_IDS.has(k):
			return "bad_alloc"
		var v: Variant = alloc[k]
		if typeof(v) == TYPE_FLOAT and float(v) == floor(v):
			v = int(v)
		if typeof(v) != TYPE_INT or int(v) < 0:
			return "bad_alloc"
		total += int(v)
	return "" if total == FREE_POINTS else "bad_alloc"

static func validate_name(p_name: String) -> String:
	var n := p_name.length()
	if n < 1 or n > NAME_MAX:
		return "bad_name"
	for c in BAD_NAME_CHARS:
		if p_name.contains(c):
			return "bad_name"
	for i in n:
		var code := p_name.unicode_at(i)
		if code < 32 or code == 127 or (code >= 0x80 and code < 0xA0) or _invisible(code):
			return "bad_name"
	return ""

## 看不見的格式字元、各種空白（避免「看起來一樣」的冒名或空白名字）
static func _invisible(code: int) -> bool:
	return code == 0x00A0 or code == 0x00AD or code == 0x034F or code == 0x061C or code == 0x115F \
		or code == 0x1160 or code == 0x1680 or code == 0x180E or (code >= 0x2000 and code <= 0x200F) \
		or (code >= 0x2028 and code <= 0x202F) or (code >= 0x205F and code <= 0x206F) \
		or code == 0x3000 or code == 0x3164 or (code >= 0xFE00 and code <= 0xFE0F) or code == 0xFEFF \
		or code == 0xFFA0 or (code >= 0xFFF0 and code <= 0xFFFF) or (code >= 0xE0000 and code <= 0xE0FFF)

## p = { id, identity, name, gender, birth_month, birth_city, alloc[, look] }（look：M3c 初始造型 0–8，不合法 → 0）
static func create(p: Dictionary, p_roll: Dictionary, tables: Dictionary, options: Dictionary,
		rng: RandomNumberGenerator, now_s: float) -> Character:
	var c := Character.new()
	c.id = String(p.get("id", ""))
	c.identity = String(p.get("identity", ""))
	c.name = String(p.get("name", ""))
	c.gender = String(p.get("gender", "M"))
	c.birth_month = clampi(CharData.to_int(p.get("birth_month", 1), 1), 1, 12)
	c.birth_city = String(p.get("birth_city", ""))
	c.appearance = Looks.sanitize(p.get("look", 0))   # M3C_PLAN §3.3
	c.created_s = now_s
	var alloc: Dictionary = p.get("alloc", {}) if typeof(p.get("alloc", {})) == TYPE_DICTIONARY else {}
	for a in Character.ATTR_IDS:
		c.attrs[a] = CharData.to_int(p_roll.get(a, 0)) + CharData.to_int(alloc.get(a, 0))
	c.money = START_MONEY
	c.learn_points = START_LEARN_POINTS
	var birth_room := String(CharData.row(tables, "regions", c.birth_city).get("birth_room", ""))
	c.location = { "region": c.birth_city, "room": birth_room }
	c.respawn = { "region": "", "room": "" }
	var make_uid := func() -> String: return new_item_uid(c.inventory, rng)
	for spec in START_ITEMS:
		var res := c.inventory.add(spec[0], spec[1], tables, now_s, -1, make_uid)
		if res["ok"] and spec[2]:
			c.inventory.equip(res["uid"], tables)
	var d := c.derived(tables, options)
	c.vitals = {
		"jing": int(d["jing_max"]), "qi": int(d["qi_max"]), "shen": int(d["shen_max"]),
		"neili": 0, "food": Character.FOOD_MAX, "water": Character.WATER_MAX,
	}
	return c

## 產生該背包內唯一的物品實例 id（it_<8 hex>）。
## WORLD 若需要「全世界唯一」，應自己傳入 make_uid（3.1）；這裡只用於初始物品。
static func new_item_uid(inv: Inventory, rng: RandomNumberGenerator) -> String:
	while true:
		var uid := "it_%08x" % (rng.randi() & 0xFFFFFFFF)
		if inv.find(uid).is_empty():
			return uid
	return ""
