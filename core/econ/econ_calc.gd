class_name EconCalc
extends RefCounted
## 製作經濟的防循環檢查（M3C2_PLAN §4.3，WP-ECON；純邏輯）。balance_sim econ_loop 與 data_lint 的 WP-ECON 區塊共用。
##
## 規則（綁定）：
## - 最低買價 = 物品價格 × MIN_BUY_PCT / 100；MIN_BUY_PCT = 100 ＋ reactions 裡所有 services 含 SHOP 的列
##   (price_pct − 100) 中負值的總和（沒有負值時 100）。取整照商店（NpcSystem.adjusted_price：四捨五入、最少 1）。
## - 「商店買得到」的閉包：npcs.shop.items 的物品＋「是配方產物、且配方材料全部在閉包內」的物品
##   （以「材料最低買價總和 / 產量」視為可買；同一物品有多條路取最便宜的）。
## - 對每個材料全部在閉包內的配方：Σ 產物收購價 × n 必須 **嚴格小於** Σ 材料（閉包）買價 × n。
## - 工具（t_*）不算消耗材料。

const SELL_RATE := 0.3          # ＝ NpcSystem.SELL_RATE（server/npc_system.gd 凍結；core 不引用 server）
const TOOL_PREFIX := "t_"
const CLOSURE_PASSES := 32

## reactions 的最低商店價格百分比（M3C2_PLAN §4.3）
static func min_buy_pct(tables: Dictionary) -> int:
	var neg := 0
	var rx: Variant = tables.get("reactions", {})
	if rx is Dictionary:
		for id in rx:
			var r: Variant = rx[id]
			if not (r is Dictionary) or not r.has("price_pct"):
				continue
			var sv: Variant = r.get("services", [])
			if not (sv is Array) or not ("SHOP" in (sv as Array)):
				continue
			var d := int(r["price_pct"]) - 100
			if d < 0:
				neg += d
	return maxi(1, 100 + neg)

## 商店的實際買價（同 NpcSystem.adjusted_price）
static func buy_price(item_row: Dictionary, pct: int) -> int:
	var base := int(item_row.get("price", 0))
	if pct == 100 or base <= 0:
		return base
	return maxi(1, roundi(base * pct / 100.0))

static func sellable(item_row: Dictionary) -> bool:
	return not item_row.is_empty() and not bool(item_row.get("no_sell", false)) and not bool(item_row.get("quest_item", false))

## 收購價（同 NpcSystem.sell_price；不能賣的回 0）
static func sell_price(item_row: Dictionary) -> int:
	if not sellable(item_row):
		return 0
	return maxi(1, floori(int(item_row.get("price", 0)) * SELL_RATE))

## 商店有賣的物品 { item_id: true }（只算 items 表裡存在的）
static func shop_items(tables: Dictionary) -> Dictionary:
	var out := {}
	var items: Dictionary = tables.get("items", {})
	var npcs: Variant = tables.get("npcs", {})
	if not (npcs is Dictionary):
		return out
	for nid in npcs:
		var n: Variant = npcs[nid]
		if not (n is Dictionary):
			continue
		var shop: Variant = n.get("shop")
		if not (shop is Dictionary):
			continue
		var lst: Variant = shop.get("items", [])
		if lst is Array:
			for iid in lst:
				if items.has(str(iid)):
					out[str(iid)] = true
	return out

## 所有配方：[[skill_id, recipe]]（照 id 排序，結果穩定）
static func all_recipes(tables: Dictionary) -> Array:
	var out: Array = []
	var ls: Variant = tables.get("life_skills", {})
	if not (ls is Dictionary):
		return out
	var ids: Array = (ls as Dictionary).keys()
	ids.sort()
	for sid in ids:
		var row: Variant = ls[sid]
		if row is Dictionary:
			for rc in RecipeCheck.recipes_of(row):
				if rc is Dictionary:
					out.append([str(sid), rc])
	return out

## 配方的消耗材料（去掉工具）：[[item, n]]
static func consumed_inputs(recipe: Dictionary) -> Array:
	var out: Array = []
	for inp in RecipeCheck.inputs_of(recipe):
		if not str(inp[0]).begins_with(TOOL_PREFIX):
			out.append(inp)
	return out

## 「商店買得到」的閉包：{ item_id: 每件的最低成本（float）}
static func buy_basis(tables: Dictionary) -> Dictionary:
	var pct := min_buy_pct(tables)
	var items: Dictionary = tables.get("items", {})
	var basis := {}
	for iid in shop_items(tables):
		basis[iid] = float(buy_price(items.get(iid, {}), pct))
	var recipes := all_recipes(tables)
	for _pass in CLOSURE_PASSES:
		var changed := false
		for e in recipes:
			var rc: Dictionary = e[1]
			var out := RecipeCheck.output_of(rc)
			var ins := consumed_inputs(rc)
			if out.is_empty() or ins.is_empty():
				continue
			var cost := 0.0
			var ok := true
			for inp in ins:
				if not basis.has(inp[0]):
					ok = false
					break
				cost += float(basis[inp[0]]) * int(inp[1])
			if not ok:
				continue
			var per := cost / maxi(1, int(out[0][1]))
			var oid := str(out[0][0])
			if not basis.has(oid) or per < float(basis[oid]) - 0.000001:
				basis[oid] = per
				changed = true
		if not changed:
			break
	return basis

## 違規清單（空 = 沒有循環）：每條「skill_id.recipe_id: 收購 X ≥ 材料最低買價 Y」
static func loop_violations(tables: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var basis := buy_basis(tables)
	var items: Dictionary = tables.get("items", {})
	for e in all_recipes(tables):
		var rc: Dictionary = e[1]
		var out := RecipeCheck.output_of(rc)
		var ins := consumed_inputs(rc)
		if out.is_empty() or ins.is_empty():
			continue
		var cost := 0.0
		var ok := true
		for inp in ins:
			if not basis.has(inp[0]):
				ok = false
				break
			cost += float(basis[inp[0]]) * int(inp[1])
		if not ok:
			continue
		var sell := sell_price(items.get(str(out[0][0]), {})) * int(out[0][1])
		if float(sell) >= cost - 0.000001:
			errs.append("%s.%s: 商店材料做出來的成品收購 %d ≥ 材料最低買價 %.2f（%s）" % [e[0], str(rc.get("id", "")),
				sell, cost, ", ".join(ins.map(func(x): return "%s×%d" % [x[0], x[1]]))])
	return errs

## 閉包內的配方數（報表用）
static func closure_recipe_count(tables: Dictionary) -> int:
	var basis := buy_basis(tables)
	var n := 0
	for e in all_recipes(tables):
		var ins := consumed_inputs(e[1])
		if ins.is_empty() or RecipeCheck.output_of(e[1]).is_empty():
			continue
		if ins.all(func(x): return basis.has(x[0])):
			n += 1
	return n
