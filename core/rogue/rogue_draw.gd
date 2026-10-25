class_name RogueDraw
extends RefCounted
## 江湖試煉的抽卡（ROGUE_PLAN §3.4）【設計提案・非原作】。
## 先擲種類（kind_weights）、再擲稀有度（rarity_bands／首領獎勵），再從 data/rogue_cards.json 的候選依 weight 抽；
## 卡面文字（繁中、遊戲內名稱）在這裡組好，介面不自己拼規則文字（§3.4.4）。

const CATEGORY_NAMES := { "FIST": "拳掌", "BLADE": "刀法", "SWORD": "劍法", "STAFF": "杖法", "WHIP": "鞭法",
	"SPEAR": "槍法", "STAB": "筆法", "INNER": "內功", "LIGHTNESS": "輕功" }
const WEAPON_TYPE_NAMES := { "FIST": "拳套", "BLADE": "刀", "SWORD": "劍", "STAFF": "杖", "WHIP": "鞭", "SPEAR": "槍", "STAB": "筆" }
const NEED_TEXT := { "FIST": "不挑兵器", "BLADE": "需持刀", "SWORD": "需持劍", "STAFF": "需持杖", "WHIP": "需持鞭",
	"SPEAR": "需持槍", "STAB": "需持筆" }
const SLOT_NAMES := { "WEAPON": "兵器", "ARMOR": "衣服", "HEAD": "頭部", "NECK": "頸部", "WRIST": "護腕", "CLOAK": "披風",
	"RING": "戒指", "BOOTS": "鞋子" }
## 同 UiKeys.ATTR_NAMES（屬性分配窗、HUD、物品說明都用這套名稱）
const ATTR_NAMES := { "str": "臂力", "guts": "膽識", "wit": "悟性", "luck": "福緣", "cal": "定力", "agi": "機敏", "con": "根骨" }
const KIND_RETRIES := 5
const ART_MATCH_PCT := 0.5
const WEAPON_MATCH_PCT := 0.5
## 已會的武功（精進卡）在候選裡的權重倍數（審查：精進卡出現得太少，換種子就掉到 40% 以下）【設計提案】
const UPGRADE_WEIGHT_MULT := 3
## 卡面「戰力」估算時屬性卡的分法（同 balance_sim 的 smart：平均加到臂力、根骨、機敏）
const POWER_ATTR_SPLIT := ["str", "con", "agi"]

static func draw(run: RogueRun, ch: Character, tables: Dictionary, rng: RandomNumberGenerator, min_rarity := "") -> Array:
	var r := RogueRules.rules(tables)
	var out: Array = []
	var used := {}
	# rogue_debug cards：固定的三張（只用一次）
	if not run.debug_cards.is_empty():
		for cid in run.debug_cards:
			var row: Dictionary = tables.get("rogue_cards", {}).get(str(cid), {})
			if row.is_empty() or used.has(str(cid)) or out.size() >= 3:
				continue
			var snap := snapshot(row, out.size(), run, ch, tables, r)
			if not snap.is_empty():
				out.append(snap)
				used[str(cid)] = true
		run.debug_cards = []
		if not out.is_empty():
			return out
	var kw: Dictionary = r.get("kind_weights", RogueRules.DEFAULTS["kind_weights"])
	var rw: Array = RogueRules.rarity_weights(run.round, r, min_rarity)
	var kinds_drawn: Array = []
	var guard := 0
	while out.size() < 3 and guard < 30:
		guard += 1
		var weights: Array = []
		for k in RogueRules.KINDS:
			weights.append(_kind_weight(k, kw, run, r))
		var ki := RogueRules.pick_weighted(weights, rng)
		if ki < 0:
			break
		# 三張至少兩種不同種類：第三張若與前兩張同種，重擲種類（最多 5 次）
		if out.size() == 2 and kinds_drawn[0] == kinds_drawn[1] and RogueRules.KINDS[ki] == kinds_drawn[0]:
			for t in KIND_RETRIES:
				ki = RogueRules.pick_weighted(weights, rng)
				if RogueRules.KINDS[ki] != kinds_drawn[0]:
					break
		var kind: String = RogueRules.KINDS[ki]
		var ri := RogueRules.pick_weighted(rw, rng)
		if ri < 0:
			ri = 0
		var row := _pick_row(kind, ri, run, ch, tables, rng, used, r, min_rarity)
		if row.is_empty():
			continue
		var snap := snapshot(row, out.size(), run, ch, tables, r)
		if snap.is_empty():
			continue
		used[str(row["id"])] = true
		kinds_drawn.append(kind)
		out.append(snap)
	return out

static func _kind_weight(kind: String, kw: Dictionary, run: RogueRun, r: Dictionary) -> int:
	if kind == "ALLY" and (run.round < int(r.get("ally_min_round", 2)) or run.alive_allies().size() >= int(r.get("ally_max", 2))):
		return 0
	return maxi(0, int(kw.get(kind, 0)))

## 該種類、該稀有度的候選；沒有 → 往下一階找、再往上一階找（不低於 min_rarity）
static func _pick_row(kind: String, ri: int, run: RogueRun, ch: Character, tables: Dictionary, rng: RandomNumberGenerator,
		used: Dictionary, r: Dictionary, min_rarity: String) -> Dictionary:
	var floor_i := RogueRules.rarity_index(min_rarity) if min_rarity != "" else 0
	var order: Array = []
	for i in range(ri, floor_i - 1, -1):
		order.append(i)
	for i in range(ri + 1, RogueRules.RARITIES.size()):
		order.append(i)
	# 搭配偏好（§3.4.3）：ART 50% 只抽與目前兵器相合的；WEAPON 50% 只抽與已會最高武功同類別的兵器
	var prefer := ""
	if kind == "ART" and rng.randf() < ART_MATCH_PCT:
		prefer = str(ch.inventory.equipped_row("WEAPON", tables).get("weapon_type", "FIST")) if ch != null else "FIST"
		if prefer == "":
			prefer = "FIST"
	elif kind == "WEAPON" and rng.randf() < WEAPON_MATCH_PCT:
		prefer = _best_art_category(ch, tables)
	for i in order:
		var rarity: String = RogueRules.RARITIES[i]
		var cands := candidates(kind, rarity, run, ch, tables, used, r)
		if prefer != "":
			var narrowed: Array = cands.filter(func(c): return _matches(kind, c, prefer, tables))
			if not narrowed.is_empty():
				cands = narrowed
		if cands.is_empty():
			continue
		var weights: Array = []
		for c in cands:
			var w := maxi(0, int(c.get("weight", 1)))
			if kind == "ART" and ch != null and _is_upgrade(c, ch, tables):
				w *= UPGRADE_WEIGHT_MULT
			weights.append(w)
		var pi := RogueRules.pick_weighted(weights, rng)
		if pi >= 0:
			return cands[pi]
	return {}

## 這張武功卡對角色是精進（已會、不是基本武學）
static func _is_upgrade(c: Dictionary, ch: Character, tables: Dictionary) -> bool:
	var art := str(c.get("art", ""))
	return not tables.get("basic_skills", {}).has(art) and ch.skills.level(art) > 0

## 某種類、某稀有度、這一回合可以出的卡列（依 id 排序，決定性）
static func candidates(kind: String, rarity: String, run: RogueRun, ch: Character, tables: Dictionary, used: Dictionary,
		r: Dictionary) -> Array:
	var out: Array = []
	var cards: Dictionary = tables.get("rogue_cards", {})
	var ids: Array = cards.keys()
	ids.sort()
	var ally_ids := run.ally_card_ids()
	for id in ids:
		var c: Dictionary = cards[id]
		if str(c.get("kind", "")) != kind or str(c.get("rarity", "")) != rarity or used.has(str(id)):
			continue
		if int(c.get("min_round", 1)) > run.round or int(c.get("weight", 1)) <= 0:
			continue
		if not eligible(c, run, ch, tables, r, ally_ids):
			continue
		out.append(c)
	return out

static func eligible(c: Dictionary, run: RogueRun, ch: Character, tables: Dictionary, r: Dictionary, ally_ids: Array = []) -> bool:
	match str(c.get("kind", "")):
		"ART":
			var art := str(c.get("art", ""))
			var is_basic: bool = tables.get("basic_skills", {}).has(art)
			if not is_basic and not tables.get("martial_arts", {}).has(art):
				return false
			if ch == null:
				return true
			var cur := ch.skills.level(art)
			if cur <= 0:
				return true
			if is_basic:
				return cur < card_level(c, r)
			# 已會的武功（還沒到上限）→ 精進卡（目前等級 + upgrade_by）。每門武功只有一張卡，
			# 舊規則「等級 < 卡的等級才出」讓精進永遠不出現（審查）
			return cur < int(r.get("art_cap", 150))
		"WEAPON":
			var item_id := str(c.get("item", ""))
			var row: Dictionary = tables.get("items", {}).get(item_id, {})
			if row.is_empty() or not Inventory.SLOTS.has(str(row.get("slot", ""))):
				return false
			if ch == null:
				return true
			if ch.inventory.count(item_id) > 0:
				return false
			return Inventory.requirement_reason(row, ch, tables) == ""
		"ATTR":
			return true
		"ALLY":
			if not tables.get("monsters", {}).has(str(c.get("monster", ""))):
				return false
			if ally_ids.has(str(c.get("id", ""))):
				return false
			# 同一局見過（打過或正在打）的首領不會變成隊友（審查：同一人同時出現在敵我兩邊）
			return not RogueFoes.same_person_seen(str(c.get("npc", "")), str(c.get("monster", "")), run.bosses_seen, tables)
	return false

static func card_level(c: Dictionary, r: Dictionary) -> int:
	if c.has("level") and int(c["level"]) > 0:
		return int(c["level"])
	var t: Dictionary = r.get("art_level", RogueRules.DEFAULTS["art_level"])
	return int(t.get(str(c.get("rarity", "COMMON")), 25))

static func card_points(c: Dictionary, r: Dictionary) -> int:
	if c.has("points") and int(c["points"]) > 0:
		return int(c["points"])
	var t: Dictionary = r.get("attr_points", RogueRules.DEFAULTS["attr_points"])
	return int(t.get(str(c.get("rarity", "COMMON")), 3))

## 已會（≥ 1 級）的最高戰鬥武功的類別；沒有回 ""
static func _best_art_category(ch: Character, tables: Dictionary) -> String:
	if ch == null:
		return ""
	var best := ""
	var best_lv := 0
	for k in ch.skills.special_arts(tables):
		var cat := SkillBook.category_of(k, tables)
		if BattleFormulas.BATTLE_CATEGORIES.has(cat) and ch.skills.level(k) > best_lv:
			best_lv = ch.skills.level(k)
			best = cat
	return best

static func _matches(kind: String, c: Dictionary, prefer: String, tables: Dictionary) -> bool:
	if kind == "ART":
		var art := str(c.get("art", ""))
		if tables.get("basic_skills", {}).has(art):
			return true
		var cat := str(tables.get("martial_arts", {}).get(art, {}).get("category", ""))
		return cat == prefer or cat == "FIST" or cat == "INNER" or cat == "LIGHTNESS"
	if kind == "WEAPON":
		var row: Dictionary = tables.get("items", {}).get(str(c.get("item", "")), {})
		return str(row.get("slot", "")) == "WEAPON" and str(row.get("weapon_type", "FIST")) == prefer
	return true

## 卡片快照（§3.4.4）
static func snapshot(c: Dictionary, idx: int, run: RogueRun, ch: Character, tables: Dictionary, r: Dictionary) -> Dictionary:
	var kind := str(c.get("kind", ""))
	var rarity := str(c.get("rarity", "COMMON"))
	var snap := { "idx": idx, "id": str(c.get("id", "")), "kind": kind, "rarity": rarity, "title": "", "sub": "", "lines": [],
		"upgrade": false }
	match kind:
		"ART":
			_art_snapshot(snap, c, ch, tables, r)
		"WEAPON":
			_weapon_snapshot(snap, c, ch, tables, int(r.get("weapons_keep", 3)))
		"ATTR":
			var pts := card_points(c, r)
			snap["title"] = "屬性 +%d" % pts
			snap["sub"] = "自由分配"
			snap["lines"] = ["選定後把 %d 點分到七項屬性。" % pts, "單項屬性最多 %d。" % int(r.get("attr_cap", 45))]
			snap["points"] = pts
		"ALLY":
			_ally_snapshot(snap, c, tables, r)
		_:
			return {}
	if str(snap["title"]) == "":
		return {}
	return snap

static func _art_snapshot(snap: Dictionary, c: Dictionary, ch: Character, tables: Dictionary, r: Dictionary) -> void:
	var art := str(c.get("art", ""))
	var is_basic: bool = tables.get("basic_skills", {}).has(art)
	var row: Dictionary = tables.get("martial_arts", {}).get(art, {}) if not is_basic else tables["basic_skills"][art]
	var nm := str(row.get("name", art))
	var cat := "BASIC" if is_basic else str(row.get("category", ""))
	var lv := card_level(c, r)
	var cur := ch.skills.level(art) if ch != null else 0
	var upgrade := cur > 0 and not is_basic
	if upgrade:
		var up: Dictionary = r.get("upgrade_by", RogueRules.DEFAULTS["upgrade_by"])
		lv = mini(int(r.get("art_cap", 150)), cur + int(up.get(str(c.get("rarity", "COMMON")), 15)))
	snap["upgrade"] = upgrade
	snap["title"] = "%s %d 級" % [nm, lv]   # 阿拉伯數字（審查：卡身與 HUD 都寫「45 級」）
	var lines: Array = []
	if is_basic:
		snap["sub"] = "基本武學"
		lines.append("%s提升到 %d 級。" % [nm, lv])
		lines.append_array(basic_effect_lines(art, lv))
	else:
		var cname := str(CATEGORY_NAMES.get(cat, cat))
		if BattleFormulas.BATTLE_CATEGORIES.has(cat):
			snap["sub"] = "%s・%s" % [cname, str(NEED_TEXT.get(cat, ""))]
		else:
			snap["sub"] = cname
		if upgrade:
			lines.append("精進：目前 %d 級，提升到 %d 級。" % [cur, lv])
		var moves: Array = []
		for m in row.get("moves", []):
			if m is Dictionary and int(m.get("unlock_level", 1)) <= lv:
				moves.append(m)
		moves.sort_custom(func(a, b): return int(a.get("power", 0)) > int(b.get("power", 0)))
		for m in moves.slice(0, 1 if upgrade else 2):
			lines.append("招式：%s（威力 %d）" % [str(m.get("name", m.get("id", ""))), int(m.get("power", 0))])
		# 同步提升的基本武學（與 RogueRun._apply_art 同一套：base_skill／兵器類別的基本功；內功＋基本內功；輕功＋閃躲縱躍）
		var raised: Array = []
		for b in raised_basics(art, tables):
			raised.append(SkillBook.skill_name(b, tables))
		if not raised.is_empty():
			var extra := ""
			if BattleFormulas.BATTLE_CATEGORIES.has(cat):
				extra = "，攻擊 +%d" % (lv / 4)
			elif cat == "INNER":
				extra = "，內力上限 %d" % (lv * DerivedStats.NEILI_PER_INNER)
			lines.append("%s同步提升到 %d 級%s。" % ["、".join(raised), lv, extra])
		if BattleFormulas.BATTLE_CATEGORIES.has(cat) and ch != null:
			var wt := str(ch.inventory.equipped_row("WEAPON", tables).get("weapon_type", "FIST"))
			if wt == "":
				wt = "FIST"
			if cat == "FIST":
				lines.append("拿什麼兵器都能出招。")
			elif cat == wt:
				lines.append("與目前兵器相合。")
			else:
				lines.append("目前兵器用不上，要換%s。" % str(WEAPON_TYPE_NAMES.get(cat, cat)))
	snap["lines"] = lines.slice(0, 4)
	snap["art"] = { "id": art, "level": lv, "category": cat }

## 選這門武功時跟著提升的基本武學（RogueRun._apply_art 也用這個）
static func raised_basics(art: String, tables: Dictionary) -> Array:
	var row: Dictionary = tables.get("martial_arts", {}).get(art, {})
	if row.is_empty():
		return []
	var cat := str(row.get("category", ""))
	var base := str(row.get("base_skill", ""))
	if base == "" and BattleFormulas.BATTLE_CATEGORIES.has(cat):
		base = BattleFormulas.basic_for_category(cat)
	var out: Array = []
	if base != "":
		out.append(base)
	if cat == "INNER" and not out.has("basic_inner"):
		out.append("basic_inner")
	elif cat == "LIGHTNESS" and not out.has("basic_dodge"):
		out.append("basic_dodge")
	return out.filter(func(b): return tables.get("basic_skills", {}).has(b))

## 基本武學卡的效果（數字同 BattleFormulas／DerivedStats；與 SkillEffects 的說明一致）
static func basic_effect_lines(art: String, lv: int) -> Array:
	match art:
		"basic_inner":
			return ["內力上限 %d；按「防」時防禦更高，打中時另加內力傷害。" % (lv * DerivedStats.NEILI_PER_INNER)]
		"basic_dodge":
			return ["對方打你的命中率每級 −0.3%%（共 −%s%%）。" % _fmt1(lv * 0.3)]
		"basic_parry":
			return ["防禦力 +%d（每 3 級 +1）。" % (lv / 3)]
		"basic_body":
			return ["時間棒每級 +0.03（共 +%s），出手更快。" % _fmt1(lv * 0.03)]
	if BattleFormulas.WEAPON_BASIC.values().has(art):
		return ["攻擊力每 4 級 +1（共 +%d）。" % (lv / 4)]
	return []

static func _fmt1(x: float) -> String:
	var t := "%.1f" % x
	return t.trim_suffix(".0")

static func _weapon_snapshot(snap: Dictionary, c: Dictionary, ch: Character, tables: Dictionary, keep: int = 3) -> void:
	var item_id := str(c.get("item", ""))
	var row: Dictionary = tables.get("items", {}).get(item_id, {})
	var slot := str(row.get("slot", ""))
	var atk := int(row.get("atk", 0))
	var def := int(row.get("def", 0))
	var wt := str(row.get("weapon_type", "FIST")) if slot == "WEAPON" else ""
	snap["title"] = str(row.get("name", item_id))
	var lines: Array = []
	if slot == "WEAPON":
		snap["sub"] = "兵器・%s・攻擊 %d" % [str(WEAPON_TYPE_NAMES.get(wt, wt)), atk]
		var match_arts: Array = []
		if ch != null:
			for k in ch.skills.special_arts(tables):
				if SkillBook.category_of(k, tables) == wt:   # 拳套也與拳掌武功相合（審查）
					match_arts.append(SkillBook.skill_name(k, tables))
		if not match_arts.is_empty():
			lines.append("與你的%s相合。" % "、".join(match_arts.slice(0, 2)))
		elif wt != "FIST":
			lines.append("你還沒有%s的武功，只能普通攻擊。" % str(CATEGORY_NAMES.get(wt, wt)))
		if RogueRun.weapon_auto_equip(ch, row, tables):
			lines.append("選定後立刻換上。")
		else:
			var cur := ch.inventory.equipped_row("WEAPON", tables) if ch != null else {}
			if RogueRun.known_weapon_arts(ch, tables).has(str(cur.get("weapon_type", ""))):
				lines.append("放進行囊，不換下相合的%s（可在左邊改用）。" % str(cur.get("name", "兵器")))
			else:
				lines.append("放進行囊：攻擊不比手上的%s高（可在左邊改用）。" % str(cur.get("name", "兵器")))
		var drop := _weapon_drop_name(ch, tables, keep, RogueRun.weapon_auto_equip(ch, row, tables))
		if drop != "":
			lines.append("兵器最多留 %d 把：丟掉%s。" % [keep, drop])
	else:
		snap["sub"] = "護具・%s・防禦 %d" % [str(SLOT_NAMES.get(slot, slot)), def]
		if ch != null:
			var old := ch.inventory.equipped_row(slot, tables)
			if not old.is_empty():
				lines.append("換下並丟掉%s（防禦 %d）。" % [str(old.get("name", "")), int(old.get("def", 0))])
		lines.append("選定後立刻穿上。")
	var bonus: Variant = row.get("bonus", {})
	if bonus is Dictionary and not (bonus as Dictionary).is_empty():
		var parts: Array = []
		for a in bonus:
			parts.append("%s +%d" % [str(ATTR_NAMES.get(str(a), str(a))), int(bonus[a])])
		lines.push_front("屬性加成：" + "、".join(parts))
	snap["lines"] = lines.slice(0, 4)
	snap["item"] = { "id": item_id, "slot": slot, "weapon_type": wt, "atk": atk, "def": def }

## 隊友份額的說法（審查：「10 成功力」會被讀成「成功」＋「力」；0.45 不能四捨五入成五成）：
## 1.0 →「功力與你相當」；0.45 →「功力約為你的四成半」；0.7 →「功力約為你的七成」
static func share_text(share: float) -> String:
	var halves := roundi(clampf(share, 0.0, 1.0) * 20.0)
	if halves >= 20:
		return "功力與你相當"
	var whole := halves / 2
	var t := RogueRules.cn_number(whole) + "成" if whole > 0 else ""
	if halves % 2 == 1:
		t += "半" if whole > 0 else "半成"
	return "功力約為你的%s" % t

## 拿了這把兵器之後會被丟掉的那把的名字（"" = 不用丟；同 RogueRun.trim_weapons：攻擊最低、選定後沒裝備、不是剛拿到的）
static func _weapon_drop_name(ch: Character, tables: Dictionary, keep: int, will_equip: bool) -> String:
	if ch == null:
		return ""
	var ws: Array = ch.inventory.weapon_options(tables)
	if ws.size() + 1 <= maxi(1, keep):
		return ""
	var worst: Dictionary = {}
	for w in ws:
		if ch.inventory.is_equipped(str(w.uid)) and not will_equip:
			continue   # 換上新兵器時，原本裝備的那把也可能被丟
		if worst.is_empty() or int(w.atk) < int(worst.atk):
			worst = w
	if worst.is_empty():
		return ""
	return "%s（攻擊 %d）" % [str(worst.name), int(worst.atk)]

static func _ally_snapshot(snap: Dictionary, c: Dictionary, tables: Dictionary, r: Dictionary) -> void:
	var mon := str(c.get("monster", ""))
	var mrow: Dictionary = tables.get("monsters", {}).get(mon, {})
	var npc := str(c.get("npc", ""))
	var nrow: Dictionary = tables.get("npcs", {}).get(npc, {}) if npc != "" else {}
	var nm := str(c.get("name", ""))
	if nm == "":
		nm = str(nrow.get("name", mrow.get("name", mon)))
	var ref := npc if not nrow.is_empty() else mon
	snap["title"] = nm
	var sect := str(mrow.get("sect", nrow.get("sect", "")))
	var sect_name := str(tables.get("sects", {}).get(sect, {}).get("name", ""))
	if str(c.get("affil", "")) != "":
		sect_name = str(c["affil"])   # 不屬於任何可加入門派的名人（郭靖：襄陽；張無忌：明教）
	snap["sub"] = "隊友・%s" % (sect_name if sect_name != "" else "江湖")
	var arts: Array = []
	for a in mrow.get("arts", []):
		var aid := str(a.get("art", "")) if a is Dictionary else str(a)
		var arow: Dictionary = tables.get("martial_arts", {}).get(aid, {})
		if not arow.is_empty():
			arts.append(str(arow.get("name", aid)))
	var lines: Array = []
	if not arts.is_empty():
		lines.append("武功：" + "、".join(arts.slice(0, 3)))
	var share := float((r.get("ally_share", RogueRules.DEFAULTS["ally_share"]) as Dictionary).get(str(c.get("rarity", "COMMON")), 0.35))
	lines.append(share_text(share) + "，每場跟著你成長。")
	lines.append("自動出手；倒下就離開這次試煉。")
	snap["lines"] = lines
	snap["ally"] = { "name": nm, "ref": ref, "monster": mon }

# ---------------------------------------------------------------- 卡面的戰力變化（審查：贏的選法在畫面上看不到）

## 每張卡（隊友除外）加上 power_pct：選了之後「以自己為參考」的戰力（RoguePower，同開戰時對手縮放用的那一套）變化幾 %。
## 屬性卡以平均加到臂力、根骨、機敏估算（power_note 說明）；放進行囊不換上的兵器＝0。只讀：角色與這一局都用副本。
static func annotate_power(cards: Array, run: RogueRun, ch: Character, tables: Dictionary, r: Dictionary, options: Dictionary = {}) -> void:
	if ch == null or run == null or cards.is_empty():
		return
	var saved := RoguePower.get_reference()
	var base := self_power(ch, tables, options)
	if base > 0.0:
		for c in cards:
			if not (c is Dictionary) or str(c.get("kind", "")) == "ALLY":
				continue
			var ch2 := Character.from_dict(ch.to_dict())
			var run2 := RogueRun.from_dict(run.to_dict())
			var al := {}
			if str(c.get("kind", "")) == "ATTR":
				al = spread_points(ch2.attrs, int(c.get("points", 0)), POWER_ATTR_SPLIT, int(r.get("attr_cap", 45)))
				c["power_note"] = "（平均加到臂力、根骨、機敏時）"
			if run2.apply_card(ch2, c, al, tables, options, r) != "":
				continue
			c["power_pct"] = roundi((self_power(ch2, tables, options) / base - 1.0) * 100.0)
	RoguePower.set_reference(saved)

## 角色的相對戰力（同 balance_sim 的 smart 選卡）：以自己為參考時，自己的戰力 ÷ 參考新角色（七項 17、木刀）的戰力。
## 自己對自己的 P 只剩 √氣上限，所以要除以「新角色打你」的 P，攻擊、防禦、速度才算得進去；比值才有意義。
static func self_power(ch: Character, tables: Dictionary, options: Dictionary = {}) -> float:
	var sp: Dictionary = ch.to_combatant(tables, options, 0, 0)
	RoguePower.set_reference(sp)
	var p := RoguePower.unit_power(sp, tables)
	var p0 := RoguePower.reference_power(tables)
	RoguePower.clear_reference()
	return p / maxf(0.001, p0)

## n 點一點一點輪流分到 keys（單項不超過 cap；都滿了才給其他屬性）
static func spread_points(base: Dictionary, n: int, keys: Array, cap: int) -> Dictionary:
	var out := {}
	var progress := true
	while n > 0 and progress:
		progress = false
		for k in keys:
			if n > 0 and int(base.get(k, 0)) + int(out.get(k, 0)) + 1 <= cap:
				out[k] = int(out.get(k, 0)) + 1
				n -= 1
				progress = true
	for a in Character.ATTR_IDS:
		while n > 0 and int(base.get(a, 0)) + int(out.get(a, 0)) < cap:
			out[a] = int(out.get(a, 0)) + 1
			n -= 1
	return out
