class_name RogueAlly
extends RefCounted
## 江湖試煉的 AI 隊友（ROGUE_PLAN §4.1、§4.5；WP-ALLY）【設計提案・非原作】。
## 純邏輯：不碰 Autoload。tables 由呼叫端傳入（主機用 host.tables；balance_sim 用自己的視圖）。
## - spec_for：RogueRun.allies 的一筆 → 完整戰鬥者規格（side 0、peer 0、kind ALLY、ai ally），
##   依玩家當下戰力 × 份額縮放（RoguePower.scale_to；那個檔還不存在時不縮放），氣依上一場留下的 qi_pct。
## - apply_outcome：戰後把單位結果寫回隊友字典（倒下 → alive=false；活著 → qi_pct）。

const KIND := "ALLY"
const AI := "ally"
const POWER_PATH := "res://core/rogue/rogue_power.gd"

static var _power_script: Script = null
static var _power_checked := false

## ally = { slot, card_id, monster, npc, name, share, qi_pct, alive }；資料缺（怪物列不存在）→ {}
static func spec_for(ally: Dictionary, my_unit_power: float, tables: Dictionary) -> Dictionary:
	var mid := str(ally.get("monster", ""))
	if mid == "":
		return {}
	var spec := Encounter.monster_spec(mid, tables)
	if spec.is_empty():
		return {}
	# 有 NPC 時用 NPC 的名字與立繪（同 BattleSystem._npc_unit_spec）；數值仍是怪物列
	var npc := str(ally.get("npc", ""))
	var nrow: Variant = tables.get("npcs", {}).get(npc, {}) if npc != "" else {}
	if nrow is Dictionary and not (nrow as Dictionary).is_empty():
		var nm := str(nrow.get("name", npc))
		spec["ref"] = npc
		spec["npc"] = npc
		spec["name"] = nm
		spec["short"] = str(nrow.get("short", nm.substr(0, 2) if nm.length() > 2 else nm))
	var given := str(ally.get("name", ""))
	if given != "":
		spec["name"] = given
		if str(spec.get("short", "")) == "":
			spec["short"] = given.substr(0, 2) if given.length() > 2 else given
	spec["monster_row"] = mid
	spec["kind"] = KIND
	spec["ai"] = AI
	spec["side"] = 0
	spec["peer"] = 0
	spec["rg_ally"] = str(ally.get("slot", ""))
	# 跟著你成長：每場依玩家戰力 × 份額重新縮放（§4.1）
	var share := float(ally.get("share", 0.0))
	if my_unit_power > 0.0 and share > 0.0:
		var ps := _power()
		if ps != null:
			spec = _fit(ps, spec, my_unit_power * share, tables)
	var qmax := maxi(1, int(spec.get("qi_max", spec.get("qi", 1))))
	var pct := clampf(float(ally.get("qi_pct", 1.0)), 0.0, 1.0)
	spec["qi_max"] = qmax
	spec["qi"] = maxi(1, roundi(qmax * pct))
	spec["neili"] = int(spec.get("neili_max", 0))
	return spec

## 戰後：unit_out = { died 或 alive, qi, qi_max }（BattleUnit 可用 unit_out() 轉；Battle.outcome() 的單位沒有 qi_max
## 時 qi_pct 不變）。died → alive=false、qi_pct 0；否則 qi_pct = qi / qi_max。回新字典（不改 ally）。
static func apply_outcome(ally: Dictionary, unit_out: Dictionary) -> Dictionary:
	var a := ally.duplicate(true)
	var died := bool(unit_out.get("died", false)) or (unit_out.has("alive") and not bool(unit_out.get("alive", true))) \
		or str(unit_out.get("state", "")) == BattleUnit.DEAD
	if died:
		a["alive"] = false
		a["qi_pct"] = 0.0
		return a
	var qmax := int(unit_out.get("qi_max", 0))
	if qmax > 0 and unit_out.has("qi"):
		a["qi_pct"] = clampf(float(unit_out.get("qi", 0)) / float(qmax), 0.0, 1.0)
	return a

## BattleUnit → apply_outcome 用的字典（WP-RUN 的 on_battle_finished 用）
static func unit_out(u: BattleUnit) -> Dictionary:
	if u == null:
		return {}
	return { "uid": u.uid, "died": u.is_dead(), "alive": not u.is_dead(), "fled": u.is_fled(), "qi": u.qi, "qi_max": u.qi_max(),
		"rg_ally": str(u.spec.get("rg_ally", "")), "name": u.unit_name(), "state": u.state }

## 一場戰鬥裡的隊友單位（spec.rg_ally 非空）
static func ally_units(b: Battle) -> Array:
	if b == null:
		return []
	return b.units.filter(func(u): return str(u.spec.get("rg_ally", "")) != "")

## 方便函式：把一場戰鬥的結果套到整串 allies（依 slot 對應）。回 { allies: 新陣列, fallen: [名字] }
static func apply_battle(allies: Array, b: Battle) -> Dictionary:
	var by_slot := {}
	for u in ally_units(b):
		by_slot[str(u.spec.get("rg_ally", ""))] = u
	var out: Array = []
	var fallen: Array = []
	for a in allies:
		if not (a is Dictionary):
			continue
		var slot := str(a.get("slot", ""))
		if not bool(a.get("alive", true)) or not by_slot.has(slot):
			out.append((a as Dictionary).duplicate(true))
			continue
		var na := apply_outcome(a, unit_out(by_slot[slot]))
		if not bool(na.get("alive", true)):
			var nm := str(na.get("name", ""))
			fallen.append(nm if nm != "" else by_slot[slot].unit_name())
		out.append(na)
	return { "allies": out, "fallen": fallen }

## 回合回復（§4.5）：活著的隊友 qi_pct + pct（首領回合全滿）
static func restore(ally: Dictionary, pct: float, full: bool) -> Dictionary:
	var a := ally.duplicate(true)
	if not bool(a.get("alive", true)):
		return a
	a["qi_pct"] = 1.0 if full else clampf(float(a.get("qi_pct", 1.0)) + pct, 0.0, 1.0)
	return a

## 縮放到目標戰力：先 RoguePower.scale_to（§3.7.3 的縮放器，s ∈ [0.5, 2.5]）；名人的數值列遠強於玩家
## （例如胡斐、張松溪的既有數值列，縮到 s = 0.5 仍是新手的數十倍）時再做第二段「削弱」：氣、內力、武功等級、兵器與護甲、
## 力根身一起乘 w（二分搜尋），讓隊友真的只有玩家戰力 × 份額——隊友是幫手，不是主角（§4.1、§9.2 rogue_ally_share）。
## ROGUE_PLAN 缺漏：§4.1 只寫了 scale_to；縮放器夾在 0.5 時份額不成立，所以加第二段（只影響隊友）。
const FIT_TOL := 0.05
const WEAKEN_MIN := 0.02
const WEAKEN_ITERS := 12

static func _fit(ps: Script, spec: Dictionary, target: float, tables: Dictionary) -> Dictionary:
	var res: Variant = ps.call("scale_to", spec, target, tables)
	var sp: Dictionary = spec
	if res is Dictionary and (res as Dictionary).get("spec") is Dictionary and not (res.spec as Dictionary).is_empty():
		sp = (res.spec as Dictionary).duplicate(true)
	var p := float(ps.call("unit_power", sp, tables))
	if target <= 0.0 or p <= target * (1.0 + FIT_TOL):
		return sp
	var lo := WEAKEN_MIN
	var hi := 1.0
	var best := weaken(sp, WEAKEN_MIN)
	var best_err := absf(float(ps.call("unit_power", best, tables)) - target)
	for i in WEAKEN_ITERS:
		var w := (lo + hi) / 2.0
		var cand := weaken(sp, w)
		var pw := float(ps.call("unit_power", cand, tables))
		var err := absf(pw - target)
		if err < best_err:
			best_err = err
			best = cand
		if pw > target:
			hi = w
		else:
			lo = w
	return best

## 第二段削弱（w ∈ (0, 1]）：氣、內力 × w（氣至少 1）；武功與基本武學等級 × w（至少 1）；兵器攻擊、護甲、內功值、輕功 × w；
## 力、根、身往 5 靠攏（5 + (v − 5) × w）。結果記 rg_weaken
static func weaken(spec: Dictionary, w: float) -> Dictionary:
	var out: Dictionary = spec.duplicate(true)
	w = clampf(w, 0.0, 1.0)
	for k in ["qi", "qi_max", "neili", "neili_max"]:
		if out.has(k):
			out[k] = maxi(1 if k.begins_with("qi") else 0, roundi(float(out[k]) * w))
	var attrs: Dictionary = out.get("attrs", {})
	for a in ["str", "con", "agi"]:
		if attrs.has(a):
			attrs[a] = maxi(1, roundi(5.0 + (float(attrs[a]) - 5.0) * w)) if int(attrs[a]) > 5 else int(attrs[a])
	out["attrs"] = attrs
	var sk: Dictionary = out.get("skills", {})
	for k in sk.keys():
		sk[k] = maxi(1, roundi(float(sk[k]) * w))
	out["skills"] = sk
	out["armor_power"] = roundi(float(out.get("armor_power", 0)) * w)
	if out.get("weapon") is Dictionary:
		var wp: Dictionary = out["weapon"]
		wp["atk"] = roundi(float(wp.get("atk", 0)) * w)
	for k in ["effective_inner", "lightness"]:
		if out.has(k):
			out[k] = roundi(float(out[k]) * w)
	out["rg_weaken"] = w
	return out

static func _power() -> Script:
	if not _power_checked:
		_power_checked = true
		if ResourceLoader.exists(POWER_PATH):
			_power_script = load(POWER_PATH) as Script
	return _power_script
