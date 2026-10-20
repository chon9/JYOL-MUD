class_name BankStore
extends RefCounted
## 錢莊的純邏輯（M3B_PLAN §5.2.1、§4.12；WP-ECON）。不碰主機、不送事件；BankSystem 負責驗證 NPC、扣錢、送訊息。
##
## 錢莊帳戶 ch.bank = { "money": int, "items": [ { "uid", "id", "n", "born_s", "lots": [ { "born_s", "n", "stored_s" } ] } ] }
## items 的列形狀與 Inventory.items 相同（uid、id、n、born_s、lots），每一批多記 stored_s（存進錢莊的世界秒）：
## 錢莊裡不腐壞（O15）→ 取出時把該批的 born_s 往後平移「存放的時間」，腐壞時鐘接著存入前的進度走。
## 同一種物品在錢莊裡只佔一列（錢莊不分疊，件數上限看 bank_capacity）。

const DEFAULT_CAPACITY := 1000          # bank_capacity（既有選項，【已證實】1000 件）
const DEFAULT_MONEY_CAP := 6000000      # bank_money_cap（【後期版推得】600 萬）
const CARRY_MONEY_CAP := 6000000        # Character.MONEY_CAP（身上銀兩上限，不變）

# ---------- 帳戶 ----------

## 空帳戶
static func empty() -> Dictionary:
	return { "money": 0, "items": [] }

## 讀角色的錢莊帳戶（就地正規化）。
## ch.bank 是 §4.12 的欄位（WP-SECT Day-0 加進 Character）；還沒有這個欄位的角色類別（Day-0 前、測試替身）
## 改放在 counters["bank"]（counters 會原樣存檔），Day-0 落地後自動改用 ch.bank。
static func bank_of(ch) -> Dictionary:
	if ch == null:
		return empty()
	if "bank" in ch:
		var b: Variant = ch.bank
		if not (b is Dictionary):
			b = empty()
		normalize(b)
		ch.bank = b
		return ch.bank
	var c: Variant = ch.counters if "counters" in ch else null
	if not (c is Dictionary):
		return empty()
	var fb: Variant = (c as Dictionary).get("bank")
	if not (fb is Dictionary):
		fb = empty()
		(c as Dictionary)["bank"] = fb
	normalize(fb)
	return fb

## 補齊欄位、丟掉壞列（就地）；回傳同一個字典
static func normalize(bank: Dictionary) -> Dictionary:
	bank["money"] = maxi(0, CharData.to_int(bank.get("money", 0)))
	var raw: Variant = bank.get("items", [])
	var out: Array = []
	if raw is Array:
		for it in raw:
			if not (it is Dictionary):
				continue
			var id := str(it.get("id", ""))
			var uid := str(it.get("uid", ""))
			if id == "" or uid == "":
				continue
			var lots := _clean_lots(it.get("lots", []), CharData.to_float(it.get("born_s", 0.0)),
				CharData.to_int(it.get("n", 0)))
			var n := _sum(lots)
			if n <= 0:
				continue
			out.append({ "uid": uid, "id": id, "n": n, "born_s": float(lots[0]["born_s"]), "lots": lots })
	bank["items"] = out
	return bank

## 錢莊裡的總件數（容量檢查用）
static func pieces(bank: Dictionary) -> int:
	var t := 0
	for it in bank.get("items", []):
		if it is Dictionary:
			t += int(it.get("n", 0))
	return t

static func find(bank: Dictionary, uid: String) -> Dictionary:
	if uid == "":
		return {}
	for it in bank.get("items", []):
		if it is Dictionary and str(it.get("uid", "")) == uid:
			return it
	return {}

static func find_id(bank: Dictionary, item_id: String) -> Dictionary:
	for it in bank.get("items", []):
		if it is Dictionary and str(it.get("id", "")) == item_id:
			return it
	return {}

static func count(bank: Dictionary, item_id: String) -> int:
	var it := find_id(bank, item_id)
	return int(it.get("n", 0)) if not it.is_empty() else 0

## 可不可以存（托鏢同一規則，§5.2.2）：任務物品一律不行；bankable: false 不行；預設可以
static func bankable(item_row: Dictionary) -> bool:
	if item_row.is_empty():
		return false
	if bool(item_row.get("quest_item", false)):
		return false
	var b: Variant = item_row.get("bankable", true)
	return b != false

# ---------- 存取物品 ----------

## 從背包存入錢莊（§5.2.1 put 驗證順序：no_such_item → equipped_item → not_bankable → bank_full）。
## n <= 0 視為整疊；n 大於該疊數量 → no_such_item（數量不夠）。
## 回傳 { ok, reason, item_id, n, uid }（uid = 錢莊列的 uid）
static func put(bank: Dictionary, inv: Inventory, uid: String, n: int, tables: Dictionary, capacity: int,
		now_s: float, make_uid: Callable) -> Dictionary:
	var it := inv.find(uid)
	if it.is_empty():
		return _fail("no_such_item")
	var have := int(it["n"])
	if n <= 0:
		n = have
	if n > have:
		return _fail("no_such_item")
	if inv.is_equipped(uid):
		return _fail("equipped_item")
	var item_id := str(it["id"])
	if not bankable(CharData.row(tables, "items", item_id)):
		return _fail("not_bankable")
	if pieces(bank) + n > maxi(0, capacity):
		return _fail("bank_full")
	var taken: Array = take_from_inventory(inv, uid, n)
	var lots: Array = []
	for lot in taken:
		lots.append({ "born_s": float(lot["born_s"]), "n": int(lot["n"]), "stored_s": now_s })
	var row := add_lots(bank, item_id, lots, uid if int(it.get("n", 0)) <= 0 else "", make_uid)
	return { "ok": true, "reason": "", "item_id": item_id, "n": n, "uid": str(row.get("uid", "")) }

## 從錢莊取出放進背包（take 驗證順序：no_such_item → too_heavy／too_many）。
## carry_max < 0 不檢查負重。n <= 0 視為整列；n 大於存量 → no_such_item。
## 回傳 { ok, reason, item_id, n, uid }（uid = 背包裡最後放進的那疊）
static func take(bank: Dictionary, inv: Inventory, uid: String, n: int, tables: Dictionary, carry_max: int,
		now_s: float, make_uid: Callable) -> Dictionary:
	var row := find(bank, uid)
	if row.is_empty():
		return _fail("no_such_item")
	var have := int(row["n"])
	if n <= 0:
		n = have
	if n > have:
		return _fail("no_such_item")
	var item_id := str(row["id"])
	var why := fit_reason(inv, tables, carry_max, [[item_id, n]])
	if why != "":
		return _fail(why)
	var lots := take_lots(bank, uid, n, now_s)
	var r: Dictionary = inv.add_lots(item_id, lots, tables, carry_max, make_uid)
	if not r.get("ok", false):
		# 理論上不會發生（上面已先檢查）；放不下就原樣放回錢莊
		var back: Array = []
		for lot in lots:
			back.append({ "born_s": float(lot["born_s"]), "n": int(lot["n"]), "stored_s": now_s })
		add_lots(bank, item_id, back, uid, make_uid)
		return _fail("too_heavy")
	return { "ok": true, "reason": "", "item_id": item_id, "n": n, "uid": str(r.get("uid", "")) }

## 放得下嗎：gains = [[item_id, n], …]、removes = [[item_id, n], …]（先扣掉的材料）。
## 會超重 → too_heavy；會超過 300 件 → too_many；放得下 → ""
static func fit_reason(inv: Inventory, tables: Dictionary, carry_max: int, gains: Array, removes: Array = []) -> String:
	var dw := 0
	var dn := 0
	for g in gains:
		var k := int(g[1])
		dn += k
		dw += k * CharData.to_int(CharData.row(tables, "items", str(g[0])).get("weight", 0))
	for g in removes:
		var k := int(g[1])
		dn -= k
		dw -= k * CharData.to_int(CharData.row(tables, "items", str(g[0])).get("weight", 0))
	if carry_max >= 0 and dw > 0 and inv.weight(tables) + dw > carry_max:
		return "too_heavy"
	if dn > 0 and inv.pieces() + dn > Inventory.MAX_PIECES:
		return "too_many"
	return ""

## 從背包的某疊拿走 n 件（最舊的批先拿），回傳拿走的批 [{ born_s, n }]；裝備中的會被卸下（呼叫端先擋）
static func take_from_inventory(inv: Inventory, uid: String, n: int) -> Array:
	var it := inv.find(uid)
	if it.is_empty() or n <= 0:
		return []
	n = mini(n, int(it["n"]))
	var slot := inv.slot_of(uid)
	if slot != "":
		inv.equipped[slot] = ""
	var taken: Array = Inventory._take(it, n)
	if int(it["n"]) <= 0:
		inv.items.erase(it)
	return taken

## 放進錢莊：併進同物品的列（沒有就開新列；prefer_uid 非空時沿用，否則 make_uid）。lots 每批要有 stored_s。
static func add_lots(bank: Dictionary, item_id: String, lots: Array, prefer_uid: String, make_uid: Callable) -> Dictionary:
	var row := find_id(bank, item_id)
	if row.is_empty():
		var uid := prefer_uid
		if uid == "" or not find(bank, uid).is_empty():
			uid = str(make_uid.call())
		row = { "uid": uid, "id": item_id, "n": 0, "born_s": 0.0, "lots": [] }
		(bank["items"] as Array).append(row)
	var all: Array = (row["lots"] as Array).duplicate(true)
	all.append_array(lots)
	var clean := _clean_lots(all, 0.0, 0)
	row["lots"] = clean
	row["n"] = _sum(clean)
	row["born_s"] = float(clean[0]["born_s"]) if not clean.is_empty() else 0.0
	return row

## 從錢莊的某列拿走 n 件（最舊的批先拿），回傳「已解凍」的批 [{ born_s, n }]（born_s 平移存放時間）；
## 拿光就刪掉該列
static func take_lots(bank: Dictionary, uid: String, n: int, now_s: float) -> Array:
	var row := find(bank, uid)
	if row.is_empty() or n <= 0:
		return []
	var lots: Array = row["lots"]
	var out: Array = []
	var left := mini(n, int(row["n"]))
	while left > 0 and not lots.is_empty():
		var lot: Dictionary = lots[0]
		var cut := mini(left, int(lot["n"]))
		out.append({ "born_s": thaw_born(float(lot["born_s"]), float(lot.get("stored_s", now_s)), now_s), "n": cut })
		lot["n"] = int(lot["n"]) - cut
		left -= cut
		if int(lot["n"]) <= 0:
			lots.remove_at(0)
	row["n"] = _sum(lots)
	if int(row["n"]) <= 0:
		(bank["items"] as Array).erase(row)
	else:
		row["born_s"] = float(lots[0]["born_s"])
	return out

## 凍結的腐壞時鐘：取出時 born_s 往後平移「在錢莊裡的時間」
static func thaw_born(born_s: float, stored_s: float, now_s: float) -> float:
	return born_s + maxf(0.0, now_s - stored_s)

# ---------- 銀兩 ----------

## 存（amount > 0）或領（amount < 0）銀兩的驗證（§5.2.1 money）：
## 存 > 身上 not_enough_money、存後 > bank_money_cap → bank_money_cap；
## 領 > 存款 not_enough_bank_money、領後身上 > 600 萬 → money_cap；amount == 0 → bad_amount
static func money_reason(bank_money: int, carried: int, amount: int, bank_cap: int, carry_cap: int = CARRY_MONEY_CAP) -> String:
	if amount == 0:
		return "bad_amount"
	if amount > 0:
		if amount > carried:
			return "not_enough_money"
		if bank_money + amount > bank_cap:
			return "bank_money_cap"
		return ""
	var w := -amount
	if w > bank_money:
		return "not_enough_bank_money"
	if carried + w > carry_cap:
		return "money_cap"
	return ""

## 套用（呼叫端已用 money_reason 驗證）：回傳 { bank_money, carried }
static func apply_money(bank: Dictionary, carried: int, amount: int) -> Dictionary:
	bank["money"] = int(bank.get("money", 0)) + amount
	return { "bank_money": int(bank["money"]), "carried": carried - amount }

# ---------- 顯示 ----------

## bank_view 的 items（§5.2.1 view）：[{ uid, item_id, name, n, weight }]，依名稱排序穩定
static func view_rows(bank: Dictionary, tables: Dictionary) -> Array:
	var out: Array = []
	for it in bank.get("items", []):
		if not (it is Dictionary):
			continue
		var row := CharData.row(tables, "items", str(it["id"]))
		out.append({
			"uid": str(it["uid"]), "item_id": str(it["id"]), "name": str(row.get("name", it["id"])),
			"n": int(it["n"]), "weight": CharData.to_int(row.get("weight", 0)),
		})
	return out

# ---------- 內部 ----------

static func _fail(reason: String) -> Dictionary:
	return { "ok": false, "reason": reason, "item_id": "", "n": 0, "uid": "" }

static func _sum(lots: Array) -> int:
	var t := 0
	for lot in lots:
		t += int(lot["n"])
	return t

## 批清理：丟壞資料、依 born_s 排序；born_s 與 stored_s 都相同的併成一批。
## 舊資料沒有 lots 時用 (default_born, fallback_n) 當一批
static func _clean_lots(raw: Variant, default_born: float, fallback_n: int) -> Array:
	var src: Array = raw if raw is Array else []
	if src.is_empty() and fallback_n > 0:
		src = [{ "born_s": default_born, "n": fallback_n, "stored_s": default_born }]
	var out: Array = []
	for lot in src:
		if not (lot is Dictionary):
			continue
		var k := CharData.to_int(lot.get("n", 0))
		if k <= 0:
			continue
		var born := CharData.to_float(lot.get("born_s", default_born))
		out.append({ "born_s": born, "n": k, "stored_s": CharData.to_float(lot.get("stored_s", born)) })
	out.sort_custom(func(a, b): return float(a["born_s"]) < float(b["born_s"]) \
		or (float(a["born_s"]) == float(b["born_s"]) and float(a["stored_s"]) < float(b["stored_s"])))
	var merged: Array = []
	for lot in out:
		if not merged.is_empty():
			var last: Dictionary = merged[merged.size() - 1]
			if float(last["born_s"]) == float(lot["born_s"]) and float(last["stored_s"]) == float(lot["stored_s"]):
				last["n"] = int(last["n"]) + int(lot["n"])
				continue
		merged.append(lot)
	return merged
