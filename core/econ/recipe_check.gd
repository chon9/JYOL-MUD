class_name RecipeCheck
extends RefCounted
## 生活技能第 2 版的純邏輯（M3B_PLAN §4.5、§5.2.4；WP-ECON）：模式、設施、工具、配方、採集與打獵掉落。
## LifeSystem 用它做驗證與擲骰；製作窗（WP-UI）也可以用同一套判斷顯示亮／灰。

const MODE_GATHER := "GATHER"
const MODE_CRAFT := "CRAFT"
const MODE_HUNT := "HUNT"
const MODES := [MODE_GATHER, MODE_CRAFT, MODE_HUNT]

## 技能列的模式。沒寫 mode 的舊列（第 1 版）：只有配方、沒有 yield → CRAFT（廚師），其餘 GATHER
static func mode_of(row: Dictionary) -> String:
	var m := str(row.get("mode", ""))
	if m in MODES:
		return m
	var y: Variant = row.get("yield", [])
	var rc: Variant = row.get("recipes", [])
	if (not (y is Array) or (y as Array).is_empty()) and rc is Array and not (rc as Array).is_empty():
		return MODE_CRAFT
	return MODE_GATHER

static func recipes_of(row: Dictionary) -> Array:
	var rc: Variant = row.get("recipes", [])
	return rc if rc is Array else []

static func find_recipe(row: Dictionary, recipe_id: String) -> Dictionary:
	if recipe_id == "":
		return {}
	for rc in recipes_of(row):
		if rc is Dictionary and str(rc.get("id", "")) == recipe_id:
			return rc
	return {}

## 要在哪種設施做：配方有 feature 欄就用配方的（"" = 隨地），否則用技能的
static func feature_for(row: Dictionary, recipe: Dictionary) -> String:
	if not recipe.is_empty() and recipe.has("feature"):
		return str(recipe.get("feature", ""))
	return str(row.get("feature", ""))

## 房間設施是否滿足（"" = 隨地都可以）
static func has_feature(room_features: Array, feature: String) -> bool:
	return feature == "" or feature in room_features

## 必須帶在身上的工具：技能的 tool ＋ tools ＋ 配方 tools（去重、去空字串）
static func tools_needed(row: Dictionary, recipe: Dictionary) -> Array:
	var out: Array = []
	var all: Array = [row.get("tool", "")]
	for src in [row.get("tools", []), recipe.get("tools", []) if not recipe.is_empty() else []]:
		if src is Array:
			all.append_array(src)
	for t in all:
		var id := str(t) if t != null else ""
		if id != "" and not (id in out):
			out.append(id)
	return out

## 缺哪些工具（item id 陣列；空 = 齊全）
static func missing_tools(inv: Inventory, tools: Array) -> Array:
	var out: Array = []
	for t in tools:
		if int(inv.count(str(t))) <= 0:
			out.append(str(t))
	return out

## 配方材料缺多少：[{ item, need, have }]
static func missing_inputs(inv: Inventory, recipe: Dictionary) -> Array:
	var out: Array = []
	for inp in recipe.get("inputs", []):
		if not (inp is Dictionary):
			continue
		var id := str(inp.get("item", ""))
		var need := maxi(1, int(inp.get("n", 1)))
		var have := int(inv.count(id))
		if have < need:
			out.append({ "item": id, "need": need, "have": have })
	return out

static func jing_cost(row: Dictionary, recipe: Dictionary) -> int:
	if not recipe.is_empty() and recipe.has("jing_cost"):
		return maxi(0, int(recipe.get("jing_cost", 0)))
	return maxi(0, int(row.get("jing_cost", 5)))

## 成功時熟練加幾倍（Learning.practice_life 呼叫次數）
static func prof_mult(recipe: Dictionary) -> int:
	if recipe.is_empty():
		return 1
	return maxi(1, int(recipe.get("prof", 1)))

## 配方的材料與產出：[[item, n], …]
static func inputs_of(recipe: Dictionary) -> Array:
	var out: Array = []
	for inp in recipe.get("inputs", []):
		if inp is Dictionary:
			out.append([str(inp.get("item", "")), maxi(1, int(inp.get("n", 1)))])
	return out

static func output_of(recipe: Dictionary) -> Array:
	var out: Dictionary = recipe.get("output", {}) if recipe.get("output") is Dictionary else {}
	if str(out.get("item", "")) == "":
		return []
	return [[str(out.get("item", "")), maxi(1, int(out.get("n", 1)))]]

## 這個等級會擲的 yield 列（yield[].min_level，預設 1）
static func eligible_yields(row: Dictionary, level: int) -> Array:
	var out: Array = []
	var y: Variant = row.get("yield", [])
	if not (y is Array):
		return out
	for e in y:
		if e is Dictionary and str(e.get("item", "")) != "" and level >= int(e.get("min_level", 1)):
			out.append(e)
	return out

## 數量範圍 [lo, hi]（n 可以是 [a, b] 或整數）
static func n_range(nr: Variant) -> Array:
	if nr is Array and (nr as Array).size() >= 2:
		var lo := int(nr[0])
		var hi := int(nr[1])
		return [mini(lo, hi), maxi(lo, hi)]
	if nr is float or nr is int:
		return [int(nr), int(nr)]
	return [1, 1]

## M3C2_PLAN §4.4：yield[].n_per_levels（int，預設 0＝不變）——每多 N 級，採集數量上下限各 +1。
## 「多」從該列的 min_level（預設 1）算起：加成 = ⌊max(0, 等級 − min_level) / N⌋。
## M3C2_PLAN 缺漏：計畫沒寫從幾級開始算 → 從該列的 min_level 算（高階產物剛解鎖時是基本數量）。
static func n_bonus(e: Dictionary, level: int) -> int:
	var per := int(e.get("n_per_levels", 0))
	if per <= 0:
		return 0
	return maxi(0, level - int(e.get("min_level", 1))) / per

## 這個等級的數量範圍 [lo, hi]（n 範圍＋n_per_levels 加成）
static func yield_range(e: Dictionary, level: int) -> Array:
	var r := n_range(e.get("n", [1, 1]))
	var b := n_bonus(e, level)
	return [int(r[0]) + b, int(r[1]) + b]

## M3C2_PLAN §4.4：成功率 = min(0.95, success_base + success_per_level × 等級)；
## 預設 0.5／0.005（既有規則）；技能列可以寫，配方列再覆寫技能列
const SUCCESS_BASE := 0.5
const SUCCESS_PER_LEVEL := 0.005
const SUCCESS_MAX := 0.95

static func success_chance(level: int, row: Dictionary = {}, recipe: Dictionary = {}) -> float:
	var base := SUCCESS_BASE
	var per := SUCCESS_PER_LEVEL
	for src in [row, recipe]:
		if (src as Dictionary).has("success_base"):
			base = float(src["success_base"])
		if (src as Dictionary).has("success_per_level"):
			per = float(src["success_per_level"])
	return clampf(base + per * level, 0.0, SUCCESS_MAX)

## 採集最多可能拿到多少（放不放得下的保守檢查）：[[item, n_max], …]
static func gather_max(row: Dictionary, level: int) -> Array:
	var out: Array = []
	for e in eligible_yields(row, level):
		var r := yield_range(e, level)
		if int(r[1]) > 0:
			out.append([str(e["item"]), int(r[1])])
	return out

## 採集擲骰：[[item, n], …]
static func roll_gather(row: Dictionary, level: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for e in eligible_yields(row, level):
		if rng.randf() >= float(e.get("chance", 1.0)):
			continue
		var r := yield_range(e, level)
		var n := rng.randi_range(int(r[0]), int(r[1]))
		if n > 0:
			out.append([str(e["item"]), n])
	return out

## 打獵：房間 hunt_table 依權重擲一隻（[{ monster, w }]）；空表回 ""
static func pick_hunt_monster(table: Variant, rng: RandomNumberGenerator) -> String:
	if not (table is Array):
		return ""
	var total := 0
	for e in table:
		if e is Dictionary and str(e.get("monster", "")) != "":
			total += maxi(0, int(e.get("w", 1)))
	if total <= 0:
		return ""
	var roll := rng.randi_range(1, total)
	for e in table:
		if not (e is Dictionary) or str(e.get("monster", "")) == "":
			continue
		roll -= maxi(0, int(e.get("w", 1)))
		if roll <= 0:
			return str(e["monster"])
	return ""

## 打獵勝利的額外掉落（hunt.drops；monsters 有寫時只對打倒的那些怪）：[[item, n], …]
static func roll_hunt_drops(row: Dictionary, level: int, kills: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var h: Variant = row.get("hunt")
	if not (h is Dictionary):
		return out
	for d in (h as Dictionary).get("drops", []):
		if not (d is Dictionary) or str(d.get("item", "")) == "":
			continue
		if level < int(d.get("min_level", 1)):
			continue
		var mons: Variant = d.get("monsters", [])
		if mons is Array and not (mons as Array).is_empty():
			var hit := false
			for k in kills:
				if str(k) in mons:
					hit = true
					break
			if not hit:
				continue
		if rng.randf() >= float(d.get("chance", 1.0)):
			continue
		var r := n_range(d.get("n", [1, 1]))
		var n := rng.randi_range(int(r[0]), int(r[1]))
		if n > 0:
			out.append([str(d["item"]), n])
	return out

## 一個配方對某角色的狀態（製作窗用；與 LifeSystem.work 的驗證順序一致）：
## { id, name, ok, reason, min_level, missing_tools: [id], missing_inputs: [{ item, need, have }] }
static func recipe_status(row: Dictionary, recipe: Dictionary, level: int, inv: Inventory, room_features: Array) -> Dictionary:
	var reason := ""
	var mt := missing_tools(inv, tools_needed(row, recipe))
	var mi := missing_inputs(inv, recipe)
	if not has_feature(room_features, feature_for(row, recipe)):
		reason = "no_feature"
	elif level < 1:
		reason = "not_known"
	elif not mt.is_empty():
		reason = "no_tool"
	elif level < int(recipe.get("min_level", 1)):
		reason = "recipe_level"
	elif not mi.is_empty():
		reason = "no_ingredients"
	return {
		"id": str(recipe.get("id", "")), "name": str(recipe.get("name", recipe.get("id", ""))),
		"ok": reason == "", "reason": reason, "min_level": int(recipe.get("min_level", 1)),
		"feature": feature_for(row, recipe), "missing_tools": mt, "missing_inputs": mi,
	}
