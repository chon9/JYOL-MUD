class_name EconUi
extends RefCounted
## M3b 錢莊、鏢局、製作窗的純函式（M3B_PLAN §5.2、§7.1–7.3）：讀角色表、ui 事件與本地資料表，
## 算出要顯示的清單、灰掉的原因、即時運費。只是提示——判定一律在主機。

# ================================================================ 共用

## 身上物品（sheet.inventory）的件數合計（堆疊算 n 件）
static func pieces(rows: Array) -> int:
	var n := 0
	for r in rows:
		if r is Dictionary:
			n += maxi(1, UiBuild.num(r.get("n", 1)))
	return n

## 物品的單件重量：先看列上的 weight，沒有就查本地 items 表
static func unit_weight(row: Dictionary) -> int:
	if row.has("weight"):
		return UiBuild.num(row.get("weight", 0))
	var id := str(row.get("item_id", row.get("id", "")))
	return UiBuild.num(UiClient.row("items", id).get("weight", 0))

static func item_id_of(row: Dictionary) -> String:
	return str(row.get("item_id", row.get("id", "")))

## 物品不能存錢莊／托鏢的原因碼（"" = 可以；§4.6、§5.2.1）：裝備中 → equipped_item；任務物品或 bankable: false → not_bankable
static func not_storable_reason(row: Dictionary) -> String:
	if str(row.get("equipped_slot", "")) != "" or bool(row.get("equipped", false)):
		return "equipped_item"
	var it := UiClient.row("items", item_id_of(row))
	if bool(row.get("quest_item", it.get("quest_item", false))):
		return "not_bankable"
	if row.get("bankable", it.get("bankable", true)) == false:
		return "not_bankable"
	return ""

## 原因碼的短句（本機灰掉用；主機回的原因照模板）
const STORE_BLOCK_TEXT := { "equipped_item": "裝備中，先卸下", "not_bankable": "任務物品或不能寄存的東西" }

static func store_block_text(reason: String) -> String:
	return str(STORE_BLOCK_TEXT.get(reason, UiClient.reason_inline(reason)))

## 一列物品的顯示：「鐵礦石 ×3　重 6」
static func item_line(row: Dictionary) -> String:
	var n := maxi(1, UiBuild.num(row.get("n", 1)))
	var nm := str(row.get("name", UiClient.name_of("items", item_id_of(row))))
	var w := unit_weight(row) * n
	return "%s ×%d　重 %d" % [nm, n, w]

## 數量輸入：夾在 1..max
static func clamp_n(n: int, max_n: int) -> int:
	return clampi(n, 1, maxi(1, max_n))

# ================================================================ 錢莊（§5.2.1）

## bank_view payload → { money, items, used, capacity, money_cap }（缺的欄位補預設）
static func bank_view(p: Dictionary) -> Dictionary:
	var items: Array = p.get("items", []) if p.get("items", []) is Array else []
	var used := UiBuild.num(p.get("used", EconUi.pieces(items)))
	return {
		"money": UiBuild.num(p.get("money", 0)),
		"items": items,
		"used": used,
		"capacity": UiBuild.num(p.get("capacity", UiKeys.BANK_CAPACITY_DEFAULT)),
		"money_cap": UiBuild.num(p.get("money_cap", UiKeys.BANK_MONEY_CAP_DEFAULT)),
	}

## 底部「已用 n／1000 件」
static func bank_used_text(v: Dictionary) -> String:
	return "已用 %d／%d 件" % [UiBuild.num(v.get("used", 0)), UiBuild.num(v.get("capacity", UiKeys.BANK_CAPACITY_DEFAULT))]

## 存錢／領錢在本機就知道不行的原因碼（"" = 送出交給主機）。amount > 0 存、< 0 領
static func money_block(amount: int, carried: int, v: Dictionary) -> String:
	if amount == 0:
		return "bad_amount"
	if amount > 0:
		if amount > carried:
			return "not_enough_money"
		if UiBuild.num(v.get("money", 0)) + amount > UiBuild.num(v.get("money_cap", UiKeys.BANK_MONEY_CAP_DEFAULT)):
			return "bank_money_cap"
	else:
		if -amount > UiBuild.num(v.get("money", 0)):
			return "not_enough_bank_money"
		if carried - amount > UiKeys.CARRY_MONEY_MAX:
			return "money_cap"
	return ""

const MONEY_BLOCK_TEXT := {
	"bad_amount": "請輸入銀兩數目",
	"not_enough_money": "身上的銀兩不夠",
	"bank_money_cap": "錢莊存款已到上限",
	"not_enough_bank_money": "存款不夠",
	"money_cap": "身上最多帶六百萬兩",
}

static func money_block_text(reason: String) -> String:
	return str(MONEY_BLOCK_TEXT.get(reason, UiClient.reason_inline(reason)))

## 存入一件物品在本機就知道不行的原因碼
static func put_block(row: Dictionary, n: int, v: Dictionary) -> String:
	var why := EconUi.not_storable_reason(row)
	if why != "":
		return why
	if UiBuild.num(v.get("used", 0)) + n > UiBuild.num(v.get("capacity", UiKeys.BANK_CAPACITY_DEFAULT)):
		return "bank_full"
	return ""

## 取出在本機就知道不行的原因碼（件數上限 300、負重）
static func take_block(row: Dictionary, n: int, sheet: Dictionary) -> String:
	var inv: Array = sheet.get("inventory", []) if sheet.get("inventory", []) is Array else []
	if EconUi.pieces(inv) + n > UiKeys.CARRY_PIECES_MAX:
		return "too_many"
	var cmax := UiBuild.num(sheet.get("carry_max", 0))
	if cmax > 0 and UiBuild.num(sheet.get("carry", 0)) + EconUi.unit_weight(row) * n > cmax:
		return "too_heavy"
	return ""

const ITEM_BLOCK_TEXT := { "bank_full": "錢莊已經放滿了", "too_many": "身上的東西太多了", "too_heavy": "背不動了" }

static func item_block_text(reason: String) -> String:
	if ITEM_BLOCK_TEXT.has(reason):
		return str(ITEM_BLOCK_TEXT[reason])
	return EconUi.store_block_text(reason)

# ================================================================ 鏢局（§5.2.2）

## npc_menu.escort：{ city, city_name, ready, routes: [ { city, city_name, delay_text } ], fee_base?, fee_per_weight? }
static func escort_menu(menu: Dictionary) -> Dictionary:
	var e: Variant = menu.get("escort", null)
	return e if e is Dictionary else {}

static func routes(menu: Dictionary) -> Array:
	var r: Variant = EconUi.escort_menu(menu).get("routes", [])
	return (r as Array).filter(func(x): return x is Dictionary) if r is Array else []

## 目的城下拉選單的一項：「大理（約 4 時辰）」
static func route_label(r: Dictionary) -> String:
	var nm := str(r.get("city_name", UiClient.name_of("regions", str(r.get("city", "")))))
	var d := str(r.get("delay_text", ""))
	return "%s（%s）" % [nm, d] if d != "" else nm

## 運費參數：npc_menu.escort 或 world_info 有給就用主機的，否則 §4.11 預設
## # M3B_PLAN 缺漏：§6 的 world_info／npc_menu 新欄位沒有列出運費參數；這裡依序找 escort.fee_base、world_info.consign_fee_base，都沒有用預設 20／2
static func fee_params(menu: Dictionary) -> Vector2i:
	var e := EconUi.escort_menu(menu)
	var wi := UiClient.world_info()
	var base := UiBuild.num(e.get("fee_base", wi.get("consign_fee_base", UiKeys.CONSIGN_FEE_BASE_DEFAULT)))
	var per := UiBuild.num(e.get("fee_per_weight", wi.get("consign_fee_per_weight", UiKeys.CONSIGN_FEE_PER_WEIGHT_DEFAULT)))
	return Vector2i(base, per)

## 選好的物品 { uid: n } 的總重（身上物品的單件重 × 數量）
static func picked_weight(sheet: Dictionary, picks: Dictionary) -> int:
	var w := 0
	for it in sheet.get("inventory", []):
		if it is Dictionary and picks.has(str(it.get("uid", ""))):
			w += EconUi.unit_weight(it) * UiBuild.num(picks[str(it.get("uid", ""))])
	return w

## 運費 = 基本 + 每重 × 總重（§5.2.2）
static func consign_fee(total_weight: int, base: int, per_weight: int) -> int:
	return base + per_weight * maxi(0, total_weight)

## consign_send 的 items 參數：[{uid, n}]（照身上物品的順序，n ≥ 1）
static func picks_to_items(sheet: Dictionary, picks: Dictionary) -> Array:
	var out: Array = []
	for it in sheet.get("inventory", []):
		if not (it is Dictionary):
			continue
		var uid := str(it.get("uid", ""))
		if picks.has(uid) and UiBuild.num(picks[uid]) > 0:
			out.append({ "uid": uid, "n": UiBuild.num(picks[uid]) })
	return out

## 托鏢送出前本機就知道不行的原因碼
static func send_block(to_name: String, city: String, items: Array, money: int, fee: int, sheet: Dictionary) -> String:
	if to_name.strip_edges() == "":
		return "need_target"
	if to_name.strip_edges() == str(sheet.get("name", "")) and str(sheet.get("name", "")) != "":
		return "self_target"
	if city == "":
		return "no_route"
	if items.is_empty() and money <= 0:
		return "nothing_to_send"
	if items.size() > UiKeys.CONSIGN_ITEMS_MAX:
		return "too_many"
	if money + fee > UiBuild.num(sheet.get("money", 0)):
		return "not_enough_money"
	return ""

const SEND_BLOCK_TEXT := {
	"need_target": "請填收件人的名字",
	"self_target": "不能寄給自己",
	"no_route": "請選目的城",
	"nothing_to_send": "請選要寄的物品或銀兩",
	"too_many": "一次最多寄 10 樣東西",
	"not_enough_money": "身上的銀兩不夠付運費",
}

static func send_block_text(reason: String) -> String:
	return str(SEND_BLOCK_TEXT.get(reason, UiClient.reason_inline(reason)))

## consign_list payload 的列（容錯：rows／items／consignments，或 ready＋sent 兩段）
## # M3B_PLAN 缺漏：§6 只寫 consign_list(ui)，沒寫 payload 形狀；這裡照 world.consignments 的列（§4.13）讀，
## 另接受主機加的 can_take、left_s、city_name 欄位
static func consign_rows(p: Dictionary) -> Array:
	var out: Array = []
	for k in ["rows", "items", "consignments", "ready", "sent", "transit"]:
		var v: Variant = p.get(k, null)
		if v is Array:
			for r in v:
				if r is Dictionary and not out.any(func(x): return str(x.get("id", "")) == str(r.get("id", "")) and str(r.get("id", "")) != ""):
					out.append(r)
	return out

## 這一筆我能不能在這裡領（主機有給 can_take 就照主機）
static func can_take(row: Dictionary, my_char: String) -> bool:
	if row.has("can_take"):
		return bool(row["can_take"])
	var st := str(row.get("status", ""))
	if st == "READY":
		return my_char == "" or str(row.get("to_char", my_char)) == my_char
	if st == "RETURNED":
		return my_char == "" or str(row.get("from_char", my_char)) == my_char
	return false

## 取貨清單的一行：「天天寄來：鐵劍 ×1、200 兩（已到站）」
static func consign_line(row: Dictionary, my_char: String) -> String:
	var parts: PackedStringArray = []
	for it in row.get("items", []):
		if it is Dictionary:
			parts.append("%s ×%d" % [str(it.get("name", UiClient.name_of("items", EconUi.item_id_of(it)))), maxi(1, UiBuild.num(it.get("n", 1)))])
	if UiBuild.num(row.get("money", 0)) > 0:
		parts.append("%d 兩" % UiBuild.num(row.get("money", 0)))
	var st := str(row.get("status", ""))
	var mine_sent := my_char != "" and str(row.get("from_char", "")) == my_char
	var head := ""
	if mine_sent:
		head = "寄給%s（往%s）" % [str(row.get("to_name", "?")), str(row.get("to_city_name", UiClient.name_of("regions", str(row.get("to_city", "")))))]
	else:
		head = "%s寄來" % str(row.get("from_name", "?"))
	var tail := str(UiKeys.CONSIGN_STATUS_LABELS.get(st, st))
	if st == "TRANSIT" and UiBuild.num(row.get("left_s", 0)) > 0:
		tail += "，約 %s後到" % SectUi.duration_text(float(row.get("left_s", 0)))
	return "%s：%s（%s）" % [head, "、".join(parts) if not parts.is_empty() else "（空）", tail]

# ================================================================ 製作窗（§4.5、§7.3）

static func inv_counts(sheet: Dictionary) -> Dictionary:
	var out := {}
	for it in sheet.get("inventory", []):
		if it is Dictionary:
			var id := str(it.get("id", ""))
			out[id] = UiBuild.num(out.get(id, 0)) + maxi(1, UiBuild.num(it.get("n", 1)))
	return out

static func skill_levels(sheet: Dictionary) -> Dictionary:
	var out := {}
	for s in sheet.get("skills", []):
		if s is Dictionary:
			out[str(s.get("id", ""))] = UiBuild.num(s.get("level", 0))
	return out

## 這項技能／配方要帶的工具 id（tool、tools、配方 tools；去重、去空）
static func tools_needed(skill: Dictionary, recipe: Dictionary = {}) -> Array:
	var out: Array = []
	var all: Array = [skill.get("tool", "")]
	for k in [skill.get("tools", []), recipe.get("tools", [])]:
		if k is Array:
			all.append_array(k)
	for t in all:
		var s := str(t)
		if s != "" and not out.has(s):
			out.append(s)
	return out

static func _missing_tools(tools: Array, counts: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for t in tools:
		if UiBuild.num(counts.get(str(t), 0)) <= 0:
			out.append(UiClient.name_of("items", str(t)))
	return out

## 配方的材料文字：「鐵礦石×3、木炭×1」
static func inputs_text(recipe: Dictionary) -> String:
	var parts: PackedStringArray = []
	for i in recipe.get("inputs", []):
		if i is Dictionary:
			parts.append("%s×%d" % [UiClient.name_of("items", str(i.get("item", ""))), maxi(1, UiBuild.num(i.get("n", 1)))])
	return "、".join(parts)

## 成品文字：「鐵劍」「木炭×2」
static func output_text(recipe: Dictionary) -> String:
	var o: Variant = recipe.get("output", {})
	if not (o is Dictionary) or str((o as Dictionary).get("item", "")) == "":
		return str(recipe.get("name", recipe.get("id", "")))
	var n := maxi(1, UiBuild.num((o as Dictionary).get("n", 1)))
	var nm := UiClient.name_of("items", str(o["item"]))
	return nm if n == 1 else "%s×%d" % [nm, n]

## 一個配方能不能做與原因（第一個不成立的；照主機驗證順序：等級 → 工具 → 精 → 材料）
static func recipe_state(skill: Dictionary, recipe: Dictionary, sheet: Dictionary) -> Dictionary:
	var counts := EconUi.inv_counts(sheet)
	var lv := UiBuild.num(EconUi.skill_levels(sheet).get(str(skill.get("id", "")), 0))
	var min_lv := maxi(1, UiBuild.num(recipe.get("min_level", 1)))
	var why := ""
	if lv <= 0:
		why = "還沒學會%s" % str(skill.get("name", skill.get("id", "")))
	elif lv < min_lv:
		why = "需 %d 級" % min_lv
	if why == "":
		var miss := EconUi._missing_tools(EconUi.tools_needed(skill, recipe), counts)
		if not miss.is_empty():
			why = "缺工具：%s" % "、".join(miss)
	if why == "":
		var jc := UiBuild.num(recipe.get("jing_cost", skill.get("jing_cost", 0)))
		var vit: Variant = sheet.get("vitals", {})
		if jc > 0 and vit is Dictionary and (vit as Dictionary).has("jing") and UiBuild.num(vit["jing"]) < jc:
			why = "精不足（要 %d）" % jc
	if why == "":
		var lack: PackedStringArray = []
		for i in recipe.get("inputs", []):
			if not (i is Dictionary):
				continue
			var need := maxi(1, UiBuild.num(i.get("n", 1)))
			var have := UiBuild.num(counts.get(str(i.get("item", "")), 0))
			if have < need:
				lack.append("%s×%d" % [UiClient.name_of("items", str(i.get("item", ""))), need - have])
		if not lack.is_empty():
			why = "缺：%s" % "、".join(lack)
	return { "ok": why == "", "why": why, "level": min_lv }

## 採集／打獵能不能做（等級 → 工具 → 精）
static func gather_state(skill: Dictionary, sheet: Dictionary) -> Dictionary:
	var lv := UiBuild.num(EconUi.skill_levels(sheet).get(str(skill.get("id", "")), 0))
	var why := ""
	if lv <= 0:
		why = "還沒學會%s" % str(skill.get("name", skill.get("id", "")))
	if why == "":
		var miss := EconUi._missing_tools(EconUi.tools_needed(skill), EconUi.inv_counts(sheet))
		if not miss.is_empty():
			why = "缺工具：%s" % "、".join(miss)
	if why == "":
		var jc := UiBuild.num(skill.get("jing_cost", 0))
		var vit: Variant = sheet.get("vitals", {})
		if jc > 0 and vit is Dictionary and (vit as Dictionary).has("jing") and UiBuild.num(vit["jing"]) < jc:
			why = "精不足（要 %d）" % jc
	return { "ok": why == "", "why": why }

static func skill_mode(skill: Dictionary) -> String:
	var m := str(skill.get("mode", "GATHER"))
	return m if m in ["GATHER", "CRAFT", "HUNT"] else "GATHER"

## 採集鈕的字：skill.verb，打獵「打獵」
static func gather_verb(skill: Dictionary) -> String:
	var v := str(skill.get("verb", ""))
	if v != "":
		return v
	return str(UiKeys.LIFE_VERBS.get(str(skill.get("id", "")), "採集" if EconUi.skill_mode(skill) != "HUNT" else "打獵"))

## 依房間設施列出製作窗的內容：[{ id, name, level, gather: {verb, ok, why}|null, recipes: [{ id, name, inputs, output, level, ok, why }] }]
## - 採集／打獵：技能的 feature 在這個房間；
## - 配方：配方的 feature（沒寫就用技能的）在這個房間，或 ""（隨地，例如裁縫、工匠）——隨地的只列已學會的技能；
## - 沒學會但這裡就有設施的技能照樣列出（灰掉，寫明要先學）。
static func craft_entries(view: Dictionary, sheet: Dictionary, skills: Dictionary = {}) -> Array:
	if skills.is_empty():
		skills = UiClient.table("life_skills")
	var feats := {}
	for f in view.get("features", []):
		feats[str(f)] = true
	var levels := EconUi.skill_levels(sheet)
	var ids: Array = skills.keys()
	ids.sort()
	var out: Array = []
	for sid in ids:
		var sk: Variant = skills[sid]
		if not (sk is Dictionary):
			continue
		var skill: Dictionary = sk
		if not skill.has("id"):
			skill = skill.duplicate()
			skill["id"] = str(sid)
		var known := UiBuild.num(levels.get(str(sid), 0)) > 0
		var sfeat := str(skill.get("feature", ""))
		var mode := EconUi.skill_mode(skill)
		var entry := { "id": str(sid), "name": str(skill.get("name", sid)), "level": UiBuild.num(levels.get(str(sid), 0)),
			"known": known, "gather": null, "recipes": [] }
		var has_gather := (mode == "HUNT") or (mode == "GATHER" and skill.get("yield", []) is Array and not (skill.get("yield", []) as Array).is_empty())
		if has_gather and sfeat != "" and feats.has(sfeat):
			var gs := EconUi.gather_state(skill, sheet)
			entry["gather"] = { "verb": EconUi.gather_verb(skill), "ok": gs["ok"], "why": gs["why"], "hunt": mode == "HUNT" }
		for r in skill.get("recipes", []):
			if not (r is Dictionary):
				continue
			var rf := str(r.get("feature", sfeat))
			if rf == "" and not known:
				continue
			if rf != "" and not feats.has(rf):
				continue
			var st := EconUi.recipe_state(skill, r, sheet)
			(entry["recipes"] as Array).append({ "id": str(r.get("id", "")), "name": str(r.get("name", r.get("id", ""))),
				"inputs": EconUi.inputs_text(r), "output": EconUi.output_text(r), "level": st["level"], "ok": st["ok"], "why": st["why"],
				"feature": rf })
		if entry["gather"] != null or not (entry["recipes"] as Array).is_empty():
			out.append(entry)
	return out

## 這個房間的「製作」鈕要不要出現：有製作型設施，或有已學會的隨地配方
static func craft_available(view: Dictionary, sheet: Dictionary) -> bool:
	for f in view.get("features", []):
		if str(f) in UiKeys.CRAFT_FEATURES:
			return true
	for e in EconUi.craft_entries(view, sheet):
		for r in e["recipes"]:
			if str(r.get("feature", "x")) == "":
				return true
	return false

## work 的參數：採集／打獵不帶 recipe（與場景卷軸既有的砍柴等按鈕相同）
static func work_args(skill: String, recipe: String) -> Dictionary:
	var a := { "skill": skill }
	if recipe != "":
		a["recipe"] = recipe
	return a
