class_name Inventory
extends RefCounted
## 背包與裝備（M1_PLAN 3.2.3）。
## 堆疊：同一種物品一律疊在一起直到 stack 上限；每疊用 lots 記每一批的取得時間（世界秒），
## 會腐壞的物品只壞過期的那幾批，任何扣除（使用、賣、交任務、死亡掉落…）都從最舊的那批扣。

const MAX_PIECES := 300
## M3C_PLAN §6.3：1 武器＋7 防具（ARMOR＝衣服）。值與 Protocol.SLOTS 相同（core 不依賴 Protocol 的載入順序，照抄字面值）
const SLOTS := ["WEAPON", "ARMOR", "HEAD", "NECK", "WRIST", "CLOAK", "RING", "BOOTS"]
## 舊版（M3c 以前）的兩格；to_dict(legacy) 與護照舊簽章只輸出這兩格
const LEGACY_SLOTS := ["WEAPON", "ARMOR"]

## [{ "uid": "it_..", "id": "c_jingyao", "n": 5, "born_s": float, "lots": [{ "born_s": float, "n": int }] }]
## born_s ＝ 最舊一批的時間（給舊程式與屍體／護照讀）；lots 由舊到新，總數＝n。
var items: Array = []
var equipped: Dictionary = empty_equipped()

## 8 個裝備欄全空
static func empty_equipped() -> Dictionary:
	var d := {}
	for slot in SLOTS:
		d[slot] = ""
	return d

## 舊存檔沒有 lots：整疊當成一批（born_s）。被舊版拆開的同物品堆疊在 consolidate(tables) 合併（要物品表）。
static func from_dict(d: Dictionary) -> Inventory:
	var inv := Inventory.new()
	for it in d.get("items", []):
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var n := CharData.to_int(it.get("n", 1), 1)
		if n <= 0 or String(it.get("uid", "")) == "" or String(it.get("id", "")) == "":
			continue
		var e := {
			"uid": String(it["uid"]), "id": String(it["id"]), "n": n,
			"born_s": CharData.to_float(it.get("born_s", 0.0)),
		}
		if it.get("lots") is Array:
			e["lots"] = it["lots"]
		_sync(e)
		inv.items.append(e)
	var eq: Variant = d.get("equipped", {})
	if typeof(eq) == TYPE_DICTIONARY:
		for slot in SLOTS:
			var uid := String(eq.get(slot, ""))
			inv.equipped[slot] = uid if (uid != "" and not inv.find(uid).is_empty()) else ""
	return inv

## legacy = true：舊版格式（沒有 lots、只有 WEAPON／ARMOR 兩格），只給護照驗證舊簽章用（輸出與 M3c 以前逐位元組相同）
## legacy = false：8 個裝備欄（M3C_PLAN §6.3）
func to_dict(legacy := false) -> Dictionary:
	var arr: Array = []
	for it in items:
		var e := { "uid": it["uid"], "id": it["id"], "n": int(it["n"]), "born_s": float(it["born_s"]) }
		if not legacy:
			var lots: Array = []
			for lot in _sync(it):
				lots.append({ "born_s": float(lot["born_s"]), "n": int(lot["n"]) })
			e["lots"] = lots
			e["born_s"] = float(it["born_s"])
		arr.append(e)
	if legacy:
		return { "items": arr, "equipped": { "WEAPON": equipped.get("WEAPON", ""), "ARMOR": equipped.get("ARMOR", "") } }
	var eq := {}
	for slot in SLOTS:
		eq[slot] = String(equipped.get(slot, ""))
	return { "items": arr, "equipped": eq }

func pieces() -> int:
	var total := 0
	for it in items:
		total += int(it["n"])
	return total

func weight(tables: Dictionary) -> int:
	var total := 0
	for it in items:
		total += int(it["n"]) * CharData.to_int(CharData.row(tables, "items", it["id"]).get("weight", 0))
	return total

func count(item_id: String) -> int:
	var total := 0
	for it in items:
		if it["id"] == item_id:
			total += int(it["n"])
	return total

func find(uid: String) -> Dictionary:
	if uid == "":
		return {}
	for it in items:
		if it["uid"] == uid:
			return it
	return {}

func is_equipped(uid: String) -> bool:
	return slot_of(uid) != ""

func slot_of(uid: String) -> String:
	for slot in SLOTS:
		if uid != "" and equipped.get(slot, "") == uid:
			return slot
	return ""

## carry_max < 0 表示不檢查負重。
func add(item_id: String, n: int, tables: Dictionary, now_s: float, carry_max: int, make_uid: Callable) -> Dictionary:
	return add_lots(item_id, [{ "born_s": now_s, "n": n }], tables, carry_max, make_uid)

## 放進一批或多批（lots = [{ born_s, n }]，例如屍體上撿回來的整疊）。
## 同一種物品一律併進現有的堆疊（未裝備、未滿）直到上限，滿了才開新格；每疊用 lots 記住每一批的取得時間，
## 腐壞時只壞過期的那幾批（2026-10 修正：舊版只在 60 秒內取得的才合併，每場戰鬥的兔皮各佔一格）。
func add_lots(item_id: String, lots: Array, tables: Dictionary, carry_max: int, make_uid: Callable) -> Dictionary:
	var r := CharData.row(tables, "items", item_id)
	var incoming := _clean_lots(lots, 0.0)
	var n := _lots_sum(incoming)
	if r.is_empty() or n <= 0:
		return { "ok": false, "reason": "no_item", "uid": "" }
	if pieces() + n > MAX_PIECES:
		return { "ok": false, "reason": "inventory_full", "uid": "" }
	var w := CharData.to_int(r.get("weight", 0))
	if carry_max >= 0 and weight(tables) + w * n > carry_max:
		return { "ok": false, "reason": "overweight", "uid": "" }
	var stack: int = max(1, CharData.to_int(r.get("stack", 1), 1))
	var perishable := CharData.to_int(r.get("spoil_days", 0)) > 0
	var last_uid := ""
	var touched: Array = []
	for lot in incoming:
		var left := int(lot["n"])
		var born := float(lot["born_s"])
		if stack > 1:
			for it in items:
				if left <= 0:
					break
				if it["id"] != item_id or is_equipped(it["uid"]) or int(it["n"]) >= stack:
					continue
				var put: int = min(left, stack - int(it["n"]))
				var ls := _sync(it)
				ls.append({ "born_s": born, "n": put })
				it["n"] = int(it["n"]) + put
				left -= put
				last_uid = it["uid"]
				if not touched.has(it):
					touched.append(it)
		while left > 0:
			var put: int = min(left, stack)
			var uid := String(make_uid.call())
			var nit := { "uid": uid, "id": item_id, "n": put, "born_s": born, "lots": [{ "born_s": born, "n": put }] }
			items.append(nit)
			touched.append(nit)
			left -= put
			last_uid = uid
	for it in touched:
		_sync(it)
		if not perishable:
			_collapse(it)
	return { "ok": true, "reason": "", "uid": last_uid }

## 從一疊拿走 n 件：先拿最舊的那批。
func remove(uid: String, n: int) -> Dictionary:
	var it := find(uid)
	if it.is_empty() or n <= 0 or n > int(it["n"]):
		return { "ok": false, "reason": "no_item", "removed": 0 }
	var slot := slot_of(uid)
	if slot != "":
		equipped[slot] = ""
	_take(it, n)
	if int(it["n"]) <= 0:
		items.erase(it)
	return { "ok": true, "reason": "", "removed": n }

## 依取得時間由舊到新扣（跨堆疊，以「批」為單位）；未裝備的優先。
func remove_item_id(item_id: String, n: int) -> Dictionary:
	if n <= 0 or count(item_id) < n:
		return { "ok": false, "reason": "no_item", "removed": 0 }
	var left := n
	while left > 0:
		var best: Dictionary = {}
		var best_eq := 0
		var best_born := 0.0
		for it in items:
			if it["id"] != item_id or int(it["n"]) <= 0:
				continue
			var ls := _sync(it)
			var eq := 1 if is_equipped(it["uid"]) else 0
			var born := float(ls[0]["born_s"]) if not ls.is_empty() else 0.0
			if best.is_empty() or eq < best_eq or (eq == best_eq and born < best_born):
				best = it
				best_eq = eq
				best_born = born
		if best.is_empty():
			break
		var oldest: Array = best["lots"]
		var take: int = min(left, int(oldest[0]["n"]) if not oldest.is_empty() else int(best["n"]))
		remove(best["uid"], take)
		left -= take
	return { "ok": true, "reason": "", "removed": n }

## ch 有給時檢查物品的 requires（M3C_PLAN §6.3：條件不合回 req_<type>，例 req_gender）
func equip(uid: String, tables: Dictionary, ch = null, options: Dictionary = {}, rules: Dictionary = {}) -> Dictionary:
	var it := find(uid)
	if it.is_empty():
		return { "ok": false, "reason": "no_item", "slot": "", "prev_uid": "" }
	var row := CharData.row(tables, "items", it["id"])
	var slot := String(row.get("slot", ""))
	if not SLOTS.has(slot):
		return { "ok": false, "reason": "not_equippable", "slot": "", "prev_uid": "" }
	if ch != null:
		var req := requirement_reason(row, ch, tables, options, rules)
		if req != "":
			return { "ok": false, "reason": req, "slot": "", "prev_uid": "" }
	var prev := String(equipped.get(slot, ""))
	equipped[slot] = uid
	return { "ok": true, "reason": "", "slot": slot, "prev_uid": prev }

## 物品的裝備條件（items.requires）：回 "" 或 req_<type>
static func requirement_reason(row: Dictionary, ch, tables: Dictionary, options: Dictionary = {}, rules: Dictionary = {}) -> String:
	var req: Variant = row.get("requires", [])
	if typeof(req) != TYPE_ARRAY or (req as Array).is_empty() or ch == null:
		return ""
	return Requirements.check(req, ch, tables, options, rules)

## 已裝備的物品放錯欄（舊存檔：帽子以前放在 ARMOR；物品表改了 slot）→ 搬到正確的欄。
## 目的欄已有東西 → 卸下這件（留在背包）；物品已不能裝備 → 卸下。回傳是否有變動（M3C_PLAN §6.3）
func fix_slots(tables: Dictionary) -> bool:
	var changed := false
	for slot in SLOTS:
		var uid := String(equipped.get(slot, ""))
		if uid == "":
			continue
		var it := find(uid)
		if it.is_empty():
			equipped[slot] = ""
			changed = true
			continue
		var want := String(CharData.row(tables, "items", String(it["id"])).get("slot", ""))
		if want == slot:
			continue
		equipped[slot] = ""
		changed = true
		if SLOTS.has(want) and String(equipped.get(want, "")) == "":
			equipped[want] = uid
	return changed

func unequip(slot: String) -> Dictionary:
	if not SLOTS.has(slot) or String(equipped.get(slot, "")) == "":
		return { "ok": false, "reason": "no_item", "uid": "" }
	var uid := String(equipped[slot])
	equipped[slot] = ""
	return { "ok": true, "reason": "", "uid": uid }

func equipped_row(slot: String, tables: Dictionary) -> Dictionary:
	var it := find(String(equipped.get(slot, "")))
	if it.is_empty():
		return {}
	return CharData.row(tables, "items", it["id"])

func weapon_options(tables: Dictionary) -> Array:
	var out: Array = []
	for it in items:
		var r := CharData.row(tables, "items", it["id"])
		if r.get("slot", "") != "WEAPON":
			continue
		out.append({
			"uid": it["uid"], "item_id": it["id"],
			"weapon_type": String(r.get("weapon_type", "FIST")),
			"atk": CharData.to_int(r.get("atk", 0)),
			"name": String(r.get("name", it["id"])),
		})
	return out

## 腐壞：每疊只移除過期的那幾批（最舊的先壞）；回傳 [{ id, n }]（每疊一筆）
func spoil(now_s: float, day_s: float, tables: Dictionary) -> Array:
	var gone: Array = []
	var keep: Array = []
	for it in items:
		var days := CharData.to_int(CharData.row(tables, "items", it["id"]).get("spoil_days", 0))
		if days <= 0 or is_equipped(it["uid"]):
			keep.append(it)
			continue
		var ls := _sync(it)
		var fresh: Array = []
		var lost := 0
		for lot in ls:
			if now_s - float(lot["born_s"]) >= days * day_s:
				lost += int(lot["n"])
			else:
				fresh.append(lot)
		if lost > 0:
			gone.append({ "id": it["id"], "n": lost })
			it["lots"] = fresh
			it["n"] = int(it["n"]) - lost
			_sync(it)
		if int(it["n"]) > 0:
			keep.append(it)
	items = keep
	return gone

## 這一疊最早一批還剩幾秒會壞；不會腐壞的回傳 -1
func spoil_left_s(it: Dictionary, now_s: float, day_s: float, tables: Dictionary) -> float:
	if it.is_empty():
		return -1.0
	var days := CharData.to_int(CharData.row(tables, "items", String(it.get("id", ""))).get("spoil_days", 0))
	if days <= 0:
		return -1.0
	var ls := _sync(it)
	var born := float(ls[0]["born_s"]) if not ls.is_empty() else float(it.get("born_s", 0.0))
	return maxf(0.0, born + days * day_s - now_s)

## 舊存檔：同一種物品被拆成好幾格（舊版 60 秒合併窗）→ 併成最少格數（最舊的批放前面那格）。
## 不會腐壞的物品每疊只留一批。已裝備的不動。回傳是否有變動。（需要物品表，所以在角色進入世界時呼叫）
func consolidate(tables: Dictionary) -> bool:
	# M3C_PLAN §6.3：fix_slots 與 consolidate 在同一處呼叫（角色進入世界）→ 由這裡一併處理
	var changed := fix_slots(tables)
	var seen := {}
	for it in items.duplicate():
		var iid: String = it["id"]
		if seen.has(iid):
			continue
		seen[iid] = true
		var r := CharData.row(tables, "items", iid)
		if r.is_empty():
			continue
		var stack: int = max(1, CharData.to_int(r.get("stack", 1), 1))
		var perishable := CharData.to_int(r.get("spoil_days", 0)) > 0
		var group: Array = []
		for g in items:
			if g["id"] == iid and not is_equipped(g["uid"]):
				group.append(g)
		if stack <= 1 or group.is_empty():
			continue
		var all_lots: Array = []
		var before: Array = []
		for g in group:
			before.append([int(g["n"]), _sync(g).duplicate(true)])
			all_lots.append_array(g["lots"])
		all_lots = _clean_lots(all_lots, 0.0)
		var total := _lots_sum(all_lots)
		var need := ceili(total / float(stack))
		var li := 0
		var carry: Dictionary = {}   # 被切開的那一批剩下的部分
		for gi in group.size():
			var g: Dictionary = group[gi]
			if gi >= need:
				items.erase(g)
				changed = true
				continue
			var room := stack
			var mine: Array = []
			while room > 0 and (not carry.is_empty() or li < all_lots.size()):
				var lot: Dictionary = carry
				if lot.is_empty():
					lot = all_lots[li]
					li += 1
				carry = {}
				var put: int = min(room, int(lot["n"]))
				mine.append({ "born_s": float(lot["born_s"]), "n": put })
				room -= put
				if put < int(lot["n"]):
					carry = { "born_s": float(lot["born_s"]), "n": int(lot["n"]) - put }
			g["lots"] = mine
			g["n"] = _lots_sum(mine)
			_sync(g)
			if not perishable:
				_collapse(g)
			if before[gi][0] != int(g["n"]) or before[gi][1] != g["lots"]:
				changed = true
	return changed

## tables 有給時：keep_on_death 的物品（神兵，M3C_PLAN §6.3）留在身上（已裝備的照舊裝著）
func take_all(tables: Dictionary = {}) -> Array:
	var out: Array = []
	var keep: Array = []
	for it in items:
		if _keeps(it, tables):
			keep.append(it)
		else:
			out.append(it)
	items = keep
	for slot in SLOTS:
		var uid := String(equipped.get(slot, ""))
		if uid == "" or find(uid).is_empty():
			equipped[slot] = ""
	return out

func take_equipped(tables: Dictionary = {}) -> Array:
	var out: Array = []
	for slot in SLOTS:
		var uid := String(equipped.get(slot, ""))
		if uid == "":
			continue
		var it := find(uid)
		if not it.is_empty() and _keeps(it, tables):
			continue
		if not it.is_empty():
			items.erase(it)
			out.append(it)
		equipped[slot] = ""
	return out

static func _keeps(it: Dictionary, tables: Dictionary) -> bool:
	return not tables.is_empty() and bool(CharData.row(tables, "items", String(it.get("id", ""))).get("keep_on_death", false))

# ---------- 批（lots）----------

## 正規化一疊的 lots（就地）：補齊、排序、同時間的併成一批、總數對齊 n；born_s 欄位＝最舊一批的時間。
## 外部直接改了 n（測試或舊程式）：少了 → 視為最舊的先用掉；多了 → 補進最新一批。
static func _sync(it: Dictionary) -> Array:
	var n := int(it.get("n", 0))
	var raw: Variant = it.get("lots")
	var ls: Array
	if raw is Array and not (raw as Array).is_empty():
		ls = _clean_lots(raw, float(it.get("born_s", 0.0)))
	else:
		ls = [{ "born_s": float(it.get("born_s", 0.0)), "n": n }] if n > 0 else []
	var total := _lots_sum(ls)
	while total > n and not ls.is_empty():
		var cut: int = min(total - n, int(ls[0]["n"]))
		ls[0]["n"] = int(ls[0]["n"]) - cut
		total -= cut
		if int(ls[0]["n"]) <= 0:
			ls.remove_at(0)
	if total < n:
		if ls.is_empty():
			ls.append({ "born_s": float(it.get("born_s", 0.0)), "n": n - total })
		else:
			ls[ls.size() - 1]["n"] = int(ls[ls.size() - 1]["n"]) + n - total
	it["lots"] = ls
	if not ls.is_empty():
		it["born_s"] = float(ls[0]["born_s"])
	elif not it.has("born_s"):
		it["born_s"] = 0.0
	return ls

## lots 陣列清理：丟掉壞資料與 n <= 0，依 born_s 排序，同一時間的合併成一批
static func _clean_lots(raw: Array, default_born: float) -> Array:
	var out: Array = []
	for lot in raw:
		if typeof(lot) != TYPE_DICTIONARY:
			continue
		var k := CharData.to_int(lot.get("n", 0))
		if k <= 0:
			continue
		out.append({ "born_s": CharData.to_float(lot.get("born_s", default_born)), "n": k })
	out.sort_custom(func(a, b): return float(a["born_s"]) < float(b["born_s"]))
	var merged: Array = []
	for lot in out:
		if not merged.is_empty() and float(merged[merged.size() - 1]["born_s"]) == float(lot["born_s"]):
			merged[merged.size() - 1]["n"] = int(merged[merged.size() - 1]["n"]) + int(lot["n"])
		else:
			merged.append(lot)
	return merged

static func _lots_sum(ls: Array) -> int:
	var t := 0
	for lot in ls:
		t += int(lot["n"])
	return t

## 從一疊拿走 k 件（最舊的批先拿），回傳拿走的批
static func _take(it: Dictionary, k: int) -> Array:
	var ls := _sync(it)
	var out: Array = []
	var left := k
	while left > 0 and not ls.is_empty():
		var cut: int = min(left, int(ls[0]["n"]))
		out.append({ "born_s": float(ls[0]["born_s"]), "n": cut })
		ls[0]["n"] = int(ls[0]["n"]) - cut
		left -= cut
		if int(ls[0]["n"]) <= 0:
			ls.remove_at(0)
	it["n"] = int(it["n"]) - (k - left)
	_sync(it)
	return out

## 不會腐壞的物品：整疊只留一批（取最早的時間），存檔不會越來越長
static func _collapse(it: Dictionary) -> void:
	var ls := _sync(it)
	if ls.size() > 1:
		it["lots"] = [{ "born_s": float(ls[0]["born_s"]), "n": int(it["n"]) }]
