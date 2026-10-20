class_name ConsignCalc
extends RefCounted
## 托鏢的純計算（M3B_PLAN §5.2.2、§4.7、§10；WP-ECON）：運費、送達時刻、路線查表、保管期限。

const DEFAULT_FEE_BASE := 20          # consign_fee_base【設計提案】
const DEFAULT_FEE_PER_WEIGHT := 2     # consign_fee_per_weight【設計提案】
const DEFAULT_HOLD_DAYS := 30         # consign_hold_days【設計提案】
const MAX_ITEMS := Protocol.CONSIGN_MAX_ITEMS   # 一次最多 10 個 uid（§5.2.2）
const SHICHEN_PER_DAY := 12

const STATUS_TRANSIT := "TRANSIT"
const STATUS_READY := "READY"
const STATUS_RETURNED := "RETURNED"
const STATUS_TAKEN := "TAKEN"

## 運費 = base + per_weight × 總重（總重 < 0 視為 0）
static func fee(total_weight: int, base: int = DEFAULT_FEE_BASE, per_weight: int = DEFAULT_FEE_PER_WEIGHT) -> int:
	return maxi(0, base) + maxi(0, per_weight) * maxi(0, total_weight)

## 一個時辰的世界秒數（一遊戲日 12 時辰）
static func shichen_s(day_s: float) -> float:
	return day_s / float(SHICHEN_PER_DAY)

## 送達時刻 = now + delay_shichen × 時辰長
static func arrive_s(now_s: float, delay_shichen: int, day_s: float) -> float:
	return now_s + float(maxi(0, delay_shichen)) * shichen_s(day_s)

## 到站後沒人領、退回寄件城的時刻
static func expire_s(ready_s: float, hold_days: int, day_s: float) -> float:
	return ready_s + float(maxi(1, hold_days)) * day_s

## escort_routes 中 from → to 的列（沒有回 {}）。tables = 生效視圖（era 已過濾）
static func route(tables: Dictionary, from_city: String, to_city: String) -> Dictionary:
	var rows: Variant = tables.get("escort_routes", {})
	if not (rows is Dictionary) or from_city == "" or to_city == "" or from_city == to_city:
		return {}
	var ids: Array = (rows as Dictionary).keys()
	ids.sort()
	for id in ids:
		var r: Variant = rows[id]
		if r is Dictionary and str(r.get("from_city", "")) == from_city and str(r.get("to_city", "")) == to_city:
			return r
	return {}

## 從某城出發的全部路線（依目的城 id 排序）
static func routes_from(tables: Dictionary, from_city: String) -> Array:
	var out: Array = []
	var rows: Variant = tables.get("escort_routes", {})
	if not (rows is Dictionary):
		return out
	for id in rows:
		var r: Variant = rows[id]
		if r is Dictionary and str(r.get("from_city", "")) == from_city and str(r.get("to_city", "")) != from_city:
			out.append(r)
	out.sort_custom(func(a, b): return str(a.get("to_city", "")) < str(b.get("to_city", "")))
	return out

## 「約 4 個時辰」
static func delay_text(delay_shichen: int) -> String:
	return "約 %d 個時辰" % maxi(0, delay_shichen)

## 一筆托鏢裡的物品總重：items = [{ id, n, … }]
static func items_weight(items: Array, tables: Dictionary) -> int:
	var w := 0
	for it in items:
		if it is Dictionary:
			w += int(it.get("n", 0)) * CharData.to_int(CharData.row(tables, "items", str(it.get("id", ""))).get("weight", 0))
	return w

## 狀態推進（tick 用）：TRANSIT 到時間 → READY；READY 過期 → RETURNED。回傳新狀態（不變就回原狀態）
static func next_status(c: Dictionary, now_s: float, hold_days: int, day_s: float) -> String:
	var st := str(c.get("status", STATUS_TRANSIT))
	match st:
		STATUS_TRANSIT:
			if now_s >= float(c.get("arrive_s", 0.0)):
				return STATUS_READY
		STATUS_READY:
			var ready := float(c.get("ready_s", c.get("arrive_s", 0.0)))
			if now_s >= expire_s(ready, hold_days, day_s):
				return STATUS_RETURNED
	return st
