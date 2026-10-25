class_name RogueRun
extends RefCounted
## 江湖試煉的一局（ROGUE_PLAN §3.1、§3.2、§3.5、§3.9.1）【設計提案・非原作】。
## 純資料＋純邏輯：狀態機的轉移由 RogueSystem（主機）與 balance_sim 共用這裡的方法；亂數一律走 rng_for(stream)（U11）。

var run_id := ""
var seed := 0
var phase := "ALLOC"
var round := 1
var wins := 0
var foes_beaten := 0
var bosses_beaten := 0
var members: Array = []          # 角色 id（v1 只有一位；§2.5）
var cards: Array = []            # 目前可選的 3 張（快照 §3.4.4）
var extra_picks := 0             # 首領獎勵還剩幾次 PICK（§3.8）
var allies: Array = []           # [{ slot, card_id, monster, npc, name, ref, rarity, share, qi_pct, alive }]
var taken: Array = []            # 拿過的卡 [{ id, kind, rarity, title, round }]
var best_card: Dictionary = {}
var roll: Dictionary = {}        # 擲出的七項屬性
var cause := ""
# ---- 內部欄位（ROGUE_PLAN §0.1 #2：各 WP 自行決定） ----
var alloc_points := 0            # 開局可分配點數（FREE_POINTS + 永久點數）
var min_rarity := ""             # 目前這次 PICK 的最低稀有度（首領獎勵 = RARE）
var bosses_seen: Array = []      # 這局出現過的首領（rogue_foes 列 id；同局不重複 §3.7.2）
var famous_beaten: Array = []    # 打倒的首領列 id（寫進名人錄）
var debug_cards: Array = []      # rogue_debug cards：下一次抽卡固定的卡列 id
var debug_foes: Array = []       # rogue_debug foes：下一場固定的對手列 id
var fight: Dictionary = {}       # 正在打的這一場：{ boss, boss_id, boss_name, foes: [rg_f id], power, target }
var last_result: Dictionary = {} # 上一場的結果（close.rogue §6.4）：{ round, won, boss, allies_fallen, over }
var draws := 0                   # 抽過幾次卡（同一回合抽兩次時亂數不同）

const SNAPSHOT_KEYS := ["run_id", "seed", "phase", "round", "wins", "foes_beaten", "bosses_beaten", "members", "cards",
	"extra_picks", "allies", "taken", "best_card", "roll", "cause", "alloc_points", "min_rarity", "bosses_seen",
	"famous_beaten", "debug_cards", "debug_foes", "fight", "last_result", "draws"]

func to_dict() -> Dictionary:
	var out := {}
	for k in SNAPSHOT_KEYS:
		var v: Variant = get(k)
		out[k] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return out

static func from_dict(d: Dictionary) -> RogueRun:
	var r := RogueRun.new()
	for k in SNAPSHOT_KEYS:
		if not d.has(k):
			continue
		var cur: Variant = r.get(k)
		var v: Variant = d[k]
		if typeof(cur) == TYPE_INT and (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT):
			r.set(k, int(v))
		elif typeof(cur) == typeof(v):
			r.set(k, v.duplicate(true) if (v is Dictionary or v is Array) else v)
	return r

## 決定性亂數（U11）：種子 = hash([seed, stream, round, wins, taken.size()])；同一回合的第二次抽卡另帶 draws
func rng_for(stream: String) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	var key: Array = [seed, stream, round, wins, taken.size()]
	if stream == "draw":
		key.append(draws)
	g.seed = key.hash()
	return g

## §3.7.5：戰鬥種子 = hash([run.seed, "battle", round])（BattleSystem 用 opts.seed 取代 host.rng.randi()）
func battle_seed() -> int:
	return [seed, "battle", round].hash() & 0x7FFFFFFF

func alive_allies() -> Array:
	return allies.filter(func(a): return bool(a.get("alive", false)))

## 這局招募過（不論生死）的隊友卡 id
func ally_card_ids() -> Array:
	var out: Array = []
	for a in allies:
		out.append(str(a.get("card_id", "")))
	return out

## §3.5：套用一張卡（快照）。回 "" 或原因碼（rogue_bad_card／rogue_bad_alloc／rogue_attr_cap／rogue_ally_full）
func apply_card(ch: Character, card: Dictionary, alloc: Dictionary, tables: Dictionary, options: Dictionary, r: Dictionary) -> String:
	if ch == null or card.is_empty():
		return "rogue_bad_card"
	var kind := str(card.get("kind", ""))
	var rarity := str(card.get("rarity", "COMMON"))
	match kind:
		"ART":
			var why := _apply_art(ch, card, tables, r)
			if why != "":
				return why
		"WEAPON":
			var why2 := _apply_weapon(ch, card, tables, options, r)
			if why2 != "":
				return why2
		"ATTR":
			var why3 := check_alloc(ch.attrs, alloc, int(card.get("points", 0)), int(r.get("attr_cap", 45)))
			if why3 != "":
				return why3
			for a in alloc:
				ch.attrs[a] = int(ch.attrs.get(a, 0)) + int(alloc[a])
			ch.clamp_vitals(tables, options)
		"ALLY":
			if alive_allies().size() >= int(r.get("ally_max", 2)):
				return "rogue_ally_full"
			var crow: Dictionary = tables.get("rogue_cards", {}).get(str(card.get("id", "")), {})
			var ally_d: Dictionary = card.get("ally", {}) if card.get("ally") is Dictionary else {}
			var mon := str(crow.get("monster", ally_d.get("monster", "")))
			if mon == "" or not tables.get("monsters", {}).has(mon):
				return "rogue_bad_card"
			var share_t: Dictionary = r.get("ally_share", RogueRules.DEFAULTS["ally_share"])
			allies.append({
				"slot": "rg_ally_%d" % allies.size(), "card_id": str(card.get("id", "")), "monster": mon,
				"npc": str(crow.get("npc", "")), "name": str(ally_d.get("name", card.get("title", ""))),
				"ref": str(ally_d.get("ref", mon)), "rarity": rarity,
				"share": float(share_t.get(rarity, 0.35)), "qi_pct": 1.0, "alive": true,
			})
			if crow.get("override") is Dictionary and not (crow["override"] as Dictionary).is_empty():
				allies[allies.size() - 1]["override"] = (crow["override"] as Dictionary).duplicate(true)
		_:
			return "rogue_bad_card"
	var t := { "id": str(card.get("id", "")), "kind": kind, "rarity": rarity, "title": str(card.get("title", "")), "round": round }
	taken.append(t)
	if best_card.is_empty() or RogueRules.rarity_index(rarity) >= RogueRules.rarity_index(str(best_card.get("rarity", "COMMON"))):
		best_card = { "id": t.id, "title": t.title, "rarity": rarity }
	return ""

## ATTR 與開局分配的檢查：鍵是七項屬性、值是非負整數、總和 = points、每項 ≤ cap
static func check_alloc(base: Dictionary, alloc: Dictionary, points: int, cap: int) -> String:
	var total := 0
	for k in alloc:
		if typeof(k) != TYPE_STRING or not Character.ATTR_IDS.has(k):
			return "rogue_bad_alloc"
		var v: Variant = alloc[k]
		if typeof(v) == TYPE_FLOAT and float(v) == floor(float(v)):
			v = int(v)
		if typeof(v) != TYPE_INT or int(v) < 0:
			return "rogue_bad_alloc"
		alloc[k] = int(v)
		total += int(v)
	if total != points:
		return "rogue_bad_alloc"
	for k in alloc:
		if int(base.get(k, 0)) + int(alloc[k]) > cap:
			return "rogue_attr_cap"
	return ""

func _apply_art(ch: Character, card: Dictionary, tables: Dictionary, r: Dictionary) -> String:
	var a: Dictionary = card.get("art", {}) if card.get("art") is Dictionary else {}
	var art := str(a.get("id", ""))
	var is_basic: bool = tables.get("basic_skills", {}).has(art)
	var row: Dictionary = tables.get("martial_arts", {}).get(art, {})
	if art == "" or (row.is_empty() and not is_basic):
		return "rogue_bad_card"
	var cap := int(r.get("art_cap", 150))
	var cur := ch.skills.level(art)
	var lv := int(a.get("level", 0))
	if bool(card.get("upgrade", false)):
		var up: Dictionary = r.get("upgrade_by", RogueRules.DEFAULTS["upgrade_by"])
		lv = cur + int(up.get(str(card.get("rarity", "COMMON")), 15))
	lv = mini(lv, cap)
	if lv <= 0:
		return "rogue_bad_card"
	ch.skills.set_level(art, maxi(cur, lv), tables)
	if is_basic:
		return ""
	var nlv := ch.skills.level(art)
	for b in RogueDraw.raised_basics(art, tables):
		if ch.skills.level(b) < nlv:
			ch.skills.set_level(b, nlv, tables)
	return ""

func _apply_weapon(ch: Character, card: Dictionary, tables: Dictionary, options: Dictionary, r: Dictionary) -> String:
	var it: Dictionary = card.get("item", {}) if card.get("item") is Dictionary else {}
	var item_id := str(it.get("id", ""))
	var row: Dictionary = tables.get("items", {}).get(item_id, {})
	if row.is_empty() or not Inventory.SLOTS.has(str(row.get("slot", ""))):
		return "rogue_bad_card"
	var slot0 := str(row.get("slot", ""))
	# 兵器：與目前相合的兵器不會被自動換掉（審查：兵器卡換上後把相合的武功關掉＝陷阱）；護具一律換上
	var wear := slot0 != "WEAPON" or weapon_auto_equip(ch, row, tables)
	var g := rng_for("uid")
	var add := ch.inventory.add(item_id, 1, tables, 0.0, -1, func() -> String: return CharacterFactory.new_item_uid(ch.inventory, g))
	if not bool(add.get("ok", false)):
		return "rogue_bad_card"
	var uid := str(add.get("uid", ""))
	if wear:
		var eq := ch.inventory.equip(uid, tables, ch, options)
		if not bool(eq.get("ok", false)):
			ch.inventory.remove(uid, 1)
			return "rogue_bad_card"
		var slot := str(eq.get("slot", ""))
		var prev := str(eq.get("prev_uid", ""))
		if slot != "WEAPON" and prev != "" and prev != uid:
			var pit := ch.inventory.find(prev)
			if not pit.is_empty():
				ch.inventory.remove(prev, int(pit.get("n", 1)))   # 換下的護具丟掉
	trim_weapons(ch, tables, int(r.get("weapons_keep", 3)), uid)
	ch.clamp_vitals(tables, options)
	return ""

## 角色會的戰鬥武功類別（≥ 1 級；拳掌除外：拳掌任何兵器都能出）→ 等級最高的那門
static func known_weapon_arts(ch: Character, tables: Dictionary) -> Dictionary:
	var out := {}
	if ch == null:
		return out
	for k in ch.skills.special_arts(tables):
		var cat := SkillBook.category_of(k, tables)
		if cat == "FIST" or not BattleFormulas.BATTLE_CATEGORIES.has(cat):
			continue
		out[cat] = maxi(int(out.get(cat, 0)), ch.skills.level(k))
	return out

## 兵器卡選定後要不要自動換上：
## 目前的兵器有相合的武功 → 只在同類而且攻擊不低於目前時換；目前的兵器沒有相合的武功 → 新兵器相合就換，都不相合時攻擊較高才換
static func weapon_auto_equip(ch: Character, row: Dictionary, tables: Dictionary) -> bool:
	if ch == null:
		return true
	var cur := ch.inventory.equipped_row("WEAPON", tables)
	if cur.is_empty():
		return true
	var known := known_weapon_arts(ch, tables)
	var cur_t := str(cur.get("weapon_type", "FIST"))
	var new_t := str(row.get("weapon_type", "FIST"))
	var cur_atk := int(cur.get("atk", 0))
	var new_atk := int(row.get("atk", 0))
	if known.has(cur_t):
		return new_t == cur_t and new_atk >= cur_atk
	if known.has(new_t):
		return true
	return new_atk >= cur_atk

## 背包內的兵器超過 keep 把時，丟掉攻擊最低、沒裝備的那把（同攻擊丟較早拿到的；protect＝剛拿到的那把不丟）
static func trim_weapons(ch: Character, tables: Dictionary, keep: int, protect: String = "") -> void:
	while true:
		var worst := trim_victim(ch, tables, keep, protect)
		if worst.is_empty():
			return
		ch.inventory.remove(str(worst.uid), 1)

## 下一把會被丟掉的兵器（{} = 不用丟）
static func trim_victim(ch: Character, tables: Dictionary, keep: int, protect: String = "") -> Dictionary:
	var ws: Array = ch.inventory.weapon_options(tables)
	if ws.size() <= maxi(1, keep):
		return {}
	var worst: Dictionary = {}
	for w in ws:
		if ch.inventory.is_equipped(str(w.uid)) or str(w.uid) == protect:
			continue
		if worst.is_empty() or int(w.atk) < int(worst.atk):
			worst = w
	return worst

## §3.8：打贏一場（killed＝這場打倒的對手數）
func on_won(killed: int, boss: bool, boss_id: String = "") -> void:
	wins += 1
	foes_beaten += maxi(0, killed)
	round += 1
	if boss:
		bosses_beaten += 1
		extra_picks = 1
		if boss_id != "":
			famous_beaten.append(boss_id)

## §3.9.1：結算（points_gained／points_total／new_best 由 RogueProfile.apply_run 填）
func summary() -> Dictionary:
	var recruited := 0
	var allied: Array = []
	for t in taken:
		if str(t.get("kind", "")) == "ALLY":
			recruited += 1
			allied.append(str(t.get("id", "")))
	var bc := { "id": str(best_card.get("id", "")), "title": str(best_card.get("title", "")),
		"rarity": str(best_card.get("rarity", "")) }
	return {
		"run_id": run_id, "seed": seed, "cause": cause if cause != "" else "DEATH", "rounds": round, "wins": wins,
		"foes_beaten": foes_beaten, "bosses_beaten": bosses_beaten, "best_card": bc, "allies_recruited": recruited,
		"points_gained": 0, "points_total": 0, "new_best": false,
		# 最後一場結束時還站著的隊友（玩家倒下、隊友還在 → 結算說明「試煉以你本人為準」）
		"allies_standing": int(last_result.get("allies_standing", 0)) if not bool(last_result.get("won", true)) else 0,
		# 名人錄（RogueProfile.apply_run 用；§3.9.3 famous_beaten／famous_allied）
		"famous_beaten": famous_beaten.duplicate(), "famous_allied": allied,
	}
