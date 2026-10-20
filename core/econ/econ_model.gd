class_name EconModel
extends RefCounted
## 生活技能鏈的每小時收入模型（M3C2_PLAN §4.1、§4.2，WP-ECON；純邏輯，balance_sim econ_hourly 用）。
##
## 綁定的時間模型：
## - 一次動作 = max(cooldown_s, 精成本 / 回精速度)；回精速度由呼叫端給（參考角色精上限 × REGEN_PCT / REGEN_INTERVAL_S）。
## - 「買精藥水」版本：一次動作 = cooldown_s，不夠的精用精藥水補（價格 / 回復量 兩／精，扣掉冷卻期間自然回的精）。
## - 成功率 = RecipeCheck.success_chance(L, 技能列, 配方)；失敗只扣精（＝ 每次成功的時間與花費 ÷ 成功率）。
## - 產物賣價 = 收購價（價格 × 0.3）；每小時另加 5% 時間走路與賣東西（OVERHEAD）。
## - 兩種材料來源：self（全部自己採／做）、shop（商店買得到的材料用買價；買不到的照樣自己採）。
## - 採集一次會同時得到好幾種東西：算某一樣產物的成本時，其餘產物照收購價抵掉（賣掉）。
## 每條鏈取「鏈內每一種可賣產物 × {self, shop} × {自然回精, 精藥水}」中每小時最高者。
## 每小時收入 = 每件（收購價 − 花費）/（時間 × OVERHEAD）× 3600；用 Dinkelbach 迭代找最佳生產方式。

const OVERHEAD := 1.05
const DEPTH_MAX := 6
const ITER_MAX := 16
const POTION_ID := "c_jingyao"

## ctx（呼叫端建）：
## { tables, level: int, regen: float（精／秒）, potion_per_jing: float（兩／精）, hunt_monsters: Array, hunt_fight_s: float,
##   skills: Array[String], gather_only: bool, shop: Dictionary（{item: 每件買價}；self 模式給空字典）, potion: bool }

## 精藥水每點精的價錢（價格 / restore jing）；找不到時 0.6（30 兩回 50）
static func potion_per_jing(tables: Dictionary) -> float:
	var r: Dictionary = tables.get("items", {}).get(POTION_ID, {})
	for e in r.get("effects", []):
		if e is Dictionary and str(e.get("stat", "")) == "jing" and int(e.get("value", 0)) > 0:
			return float(r.get("price", 30)) / float(e["value"])
	return 0.6

## 商店買價表（econ 的 shop 模式；用最低買價 MIN_BUY_PCT，與防循環一致）
static func shop_prices(tables: Dictionary) -> Dictionary:
	var pct := EconCalc.min_buy_pct(tables)
	var items: Dictionary = tables.get("items", {})
	var out := {}
	for iid in EconCalc.shop_items(tables):
		out[iid] = float(EconCalc.buy_price(items.get(iid, {}), pct))
	return out

static func sell_of(tables: Dictionary, item_id: String) -> float:
	return float(EconCalc.sell_price(tables.get("items", {}).get(item_id, {})))

## 一次動作：[秒, 花費]
static func action(ctx: Dictionary, jing: int, cd: float) -> Array:
	var rg := maxf(0.0001, float(ctx.regen))
	if bool(ctx.get("potion", false)):
		return [cd, maxf(0.0, jing - rg * cd) * float(ctx.potion_per_jing)]
	return [maxf(cd, jing / rg), 0.0]

## 採集一次（成功時）各產物的期望數量 { item: E[n] }（含 n_per_levels）
static func gather_expect(row: Dictionary, level: int) -> Dictionary:
	var out := {}
	for e in RecipeCheck.eligible_yields(row, level):
		var r := RecipeCheck.yield_range(e, level)
		out[str(e["item"])] = float(out.get(str(e["item"]), 0.0)) + float(e.get("chance", 1.0)) * (int(r[0]) + int(r[1])) / 2.0
	return out

## 打獵一次（打贏）的期望：{ money, items: { item: E[n] } }（怪物掉錢與掉落＋獵人額外掉落，獵物平均）
static func hunt_expect(tables: Dictionary, row: Dictionary, level: int, monsters: Array) -> Dictionary:
	var items := {}
	var money := 0.0
	var nm := 0
	var h: Variant = row.get("hunt")
	for mid in monsters:
		var m: Dictionary = tables.get("monsters", {}).get(str(mid), {})
		if m.is_empty():
			continue
		nm += 1
		var mo: Variant = m.get("money", {})
		if mo is Dictionary and not (mo as Dictionary).is_empty():
			money += (int(mo.get("min", 0)) + int(mo.get("max", 0))) / 2.0
		for d in m.get("drops", []):
			var id := str(d.get("item", ""))
			items[id] = float(items.get(id, 0.0)) + float(d.get("chance", 0)) * (int(d.get("min", 1)) + int(d.get("max", 1))) / 2.0
		if h is Dictionary:
			for d in (h as Dictionary).get("drops", []):
				if level < int(d.get("min_level", 1)):
					continue
				var ms: Variant = d.get("monsters", [])
				if ms is Array and not (ms as Array).is_empty() and not (str(mid) in ms):
					continue
				var r := RecipeCheck.n_range(d.get("n", [1, 1]))
				var id2 := str(d.get("item", ""))
				items[id2] = float(items.get(id2, 0.0)) + float(d.get("chance", 1.0)) * (int(r[0]) + int(r[1])) / 2.0
	if nm == 0:
		return { "money": 0.0, "items": {} }
	for k in items:
		items[k] = float(items[k]) / nm
	return { "money": money / nm, "items": items }

## 一件 item 的最便宜生產方式（以 花費 + lam × 秒 比較）：[秒, 花費]；做不出來回 []
static func unit_cost(ctx: Dictionary, item: String, lam: float, depth: int = 0) -> Array:
	var tables: Dictionary = ctx.tables
	var level := int(ctx.level)
	var best: Array = []
	var shop: Dictionary = ctx.get("shop", {})
	if shop.has(item):
		best = [0.0, float(shop[item])]
	if depth > DEPTH_MAX:
		return best
	var ls: Dictionary = tables.get("life_skills", {})
	for sid in ctx.skills:
		var row: Dictionary = ls.get(str(sid), {})
		if row.is_empty():
			continue
		var jc := int(row.get("jing_cost", 5))
		var cd := float(row.get("cooldown_s", 5))
		if RecipeCheck.mode_of(row) == RecipeCheck.MODE_HUNT:
			var he := hunt_expect(tables, row, level, ctx.get("hunt_monsters", []))
			var hi: Dictionary = he.items
			if float(hi.get(item, 0.0)) > 0.0:
				var a := action(ctx, jc, cd)
				var credit := float(he.money)
				for k in hi:
					if k != item:
						credit += float(hi[k]) * sell_of(tables, k)
				best = _better(best, [(float(a[0]) + float(ctx.get("hunt_fight_s", 30.0))) / float(hi[item]),
					(float(a[1]) - credit) / float(hi[item])], lam)
		else:
			var ge := gather_expect(row, level)
			if float(ge.get(item, 0.0)) > 0.0:
				var a2 := action(ctx, jc, cd)
				var p := RecipeCheck.success_chance(level, row)
				var credit2 := 0.0
				for k in ge:
					if k != item:
						credit2 += p * float(ge[k]) * sell_of(tables, k)
				var per := p * float(ge[item])
				best = _better(best, [float(a2[0]) / per, (float(a2[1]) - credit2) / per], lam)
		if bool(ctx.get("gather_only", false)):
			continue
		for rc in RecipeCheck.recipes_of(row):
			if not (rc is Dictionary):
				continue
			var out := RecipeCheck.output_of(rc)
			if out.is_empty() or str(out[0][0]) != item or level < int(rc.get("min_level", 1)):
				continue
			var a3 := action(ctx, RecipeCheck.jing_cost(row, rc), cd)
			var p3 := RecipeCheck.success_chance(level, row, rc)
			var t := float(a3[0]) / p3
			var m := float(a3[1]) / p3
			var ok := true
			for inp in RecipeCheck.inputs_of(rc):
				if str(inp[0]).begins_with(EconCalc.TOOL_PREFIX):
					continue   # 工具不消耗
				var c := unit_cost(ctx, str(inp[0]), lam, depth + 1)
				if c.is_empty():
					ok = false
					break
				t += float(c[0]) * int(inp[1])
				m += float(c[1]) * int(inp[1])
			if ok:
				var n := maxi(1, int(out[0][1]))
				best = _better(best, [t / n, m / n], lam)
	return best

static func _better(a: Array, b: Array, lam: float) -> Array:
	if a.is_empty():
		return b
	return b if float(b[1]) + lam * float(b[0]) < float(a[1]) + lam * float(a[0]) else a

## 一樣產物的每小時收入（Dinkelbach：lam ← 目前的每秒收入，直到收斂）；做不出來回 NAN
static func product_rate(ctx: Dictionary, item: String, lam0: float) -> float:
	var lam := maxf(0.0001, lam0)
	var sell := sell_of(ctx.tables, item)
	var rate := NAN
	for _i in ITER_MAX:
		var c := unit_cost(ctx, item, lam)
		if c.is_empty() or float(c[0]) <= 0.0:
			return rate
		var per_s := (sell - float(c[1])) / float(c[0])
		var r := per_s * 3600.0 / OVERHEAD
		if not is_nan(rate) and absf(r - rate) < 0.5:
			return r
		rate = r
		lam = maxf(0.0001, per_s)
	return rate

## 製作技能的成品（M3c2 審查 #6）：craft_skills 的配方產物，扣掉 gather_skills 本來就採得到的（例：種麻收的麻不算製作品）
static func craft_products(tables: Dictionary, craft_skills: Array, gather_skills: Array) -> Dictionary:
	var raw := {}
	var ls: Dictionary = tables.get("life_skills", {})
	for sid in gather_skills:
		for e in (ls.get(str(sid), {}) as Dictionary).get("yield", []):
			if e is Dictionary:
				raw[str(e.get("item", ""))] = true
	var out := {}
	for sid in craft_skills:
		for rc in RecipeCheck.recipes_of(ls.get(str(sid), {})):
			if rc is Dictionary:
				var o := RecipeCheck.output_of(rc)
				if not o.is_empty() and not raw.has(str(o[0][0])):
					out[str(o[0][0])] = true
	return out

## 鏈內可賣的產物（採集／打獵產物；gather_only 以外再加配方產物）
static func products(ctx: Dictionary) -> Array:
	var out := {}
	var ls: Dictionary = ctx.tables.get("life_skills", {})
	for sid in ctx.skills:
		var row: Dictionary = ls.get(str(sid), {})
		if row.is_empty():
			continue
		if RecipeCheck.mode_of(row) == RecipeCheck.MODE_HUNT:
			for k in hunt_expect(ctx.tables, row, int(ctx.level), ctx.get("hunt_monsters", [])).items:
				out[k] = true
		else:
			for k in gather_expect(row, int(ctx.level)):
				out[k] = true
		if not bool(ctx.get("gather_only", false)):
			for rc in RecipeCheck.recipes_of(row):
				if rc is Dictionary and int(ctx.level) >= int(rc.get("min_level", 1)):
					var o := RecipeCheck.output_of(rc)
					if not o.is_empty():
						out[str(o[0][0])] = true
	var ids := out.keys().filter(func(k): return sell_of(ctx.tables, str(k)) > 0.0)
	ids.sort()
	return ids

## 一條鏈在某等級的最佳：{ rate: float（兩／小時）, item, mode: "self"／"shop"（＋"+藥"）}
## base：{ tables, regen, potion_per_jing, hunt_monsters, hunt_fight_s }；lam0 = 起始猜測（兩／秒）
## only_items（M3c2 審查 #6）：非空時只算這些產物（例：只看製作技能的成品，量「製作是否比賣原料划算」）
static func chain_best(base: Dictionary, skills: Array, level: int, gather_only: bool, lam0: float, only_items: Dictionary = {}) -> Dictionary:
	var best := { "rate": -INF, "item": "", "mode": "" }
	var shop_p := shop_prices(base.tables)
	for use_shop in [false, true]:
		for potion in [false, true]:
			var ctx := base.duplicate()
			ctx.level = level
			ctx.skills = skills
			ctx.gather_only = gather_only
			ctx.shop = shop_p if use_shop else {}
			ctx.potion = potion
			for it in products(ctx):
				if not only_items.is_empty() and not only_items.has(str(it)):
					continue
				var r := product_rate(ctx, str(it), lam0)
				if not is_nan(r) and r > float(best.rate):
					best = { "rate": r, "item": str(it), "mode": ("shop" if use_shop else "self") + ("+藥" if potion else "") }
	return best
