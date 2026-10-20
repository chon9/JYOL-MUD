class_name BattleStatus
extends RefCounted
## 狀態效果與門派技能觸發（M3A_PLAN 5.6、5.7）。純邏輯，所有亂數用 Battle.rng。
## 決定性與 M1 金檔：只有單位真的帶著新狀態／新門派效果時才多擲亂數。
## M3B_PLAN O20（D12）：DEFENSE、RECOVER 也改走 try_proc（觸發扣 sect_skill_cost 各 PROC_COST，付不起不擲），金檔重產。

const PROC_COST := 3            # 門派效果每次觸發扣 sect_skill_cost 列的兩項各 3 點（D12；M3b 起含 DEFENSE、RECOVER、POISON_FANG）【設計提案】
const NEW_EFFECTS := ["RESIST", "EVADE", "COUNTER", "REST", "PARALYZE", "CONFUSE", "DISTRACT", "HEAVY"]
const HIT_EFFECTS := { "PARALYZE": "paralysis", "CONFUSE": "confusion", "DISTRACT": "distract" }
## M3B_PLAN §5.1.7：丐幫 乞討＝毒牙（POISON_FANG）：命中後觸發，對目標施加中毒，等級 = 1 + floor(門派技能 / 25)【設計提案】
const FANG_EFFECT := "POISON_FANG"
const FANG_STATUS := "poison"
const FANG_LEVEL_STEP := 25
const EVADE_HIT_DROP := 0.15    # EVADE：這一下命中率 −15 個百分點
const HEAVY_MULT := 1.5
const REST_PROC_PCT := 0.10     # REST：氣、內力各再回 10%
const DINGLI_BASE := 20         # 定力縮短狀態：每高於 20 的 10 點 −1 次【設計提案】
const DINGLI_STEP := 10
## status_effects.since 的值：2002-01-25 才有的狀態（M3a 審查修正；規則 later_battle_cmds 控制）
const LATER_SINCE := "gmdk"
## 氣血失調／昏迷（news 316 的 2001 狀態）：同一場戰鬥裡第 3 次吃藥起氣血失調，失調中再吃藥昏迷【設計提案：次數】
const MED_OVERUSE_AT := 3

## ---------------------------------------------------------------- 狀態列

static func row(status_id: String, tables: Dictionary) -> Dictionary:
	return BattleRules.status_row(status_id, tables)

## 施加後的持續次數：max(1, duration_actions − floor(max(0, 定力 − 20) / 10))
static func duration_for(u: BattleUnit, srow: Dictionary) -> int:
	var base := int(srow.get("duration_actions", 1))
	var cut := floori(maxi(0, u.attr("cal") - DINGLI_BASE) / float(DINGLI_STEP))
	return maxi(1, base - cut)

## 這個狀態現在能不能被施加：狀態列 `since` 是 2002-01-25（決戰光明頂，era id "gmdk"）才開的機制
## （痲痺、混亂、封穴、內傷、分心；研究 news 399／news 316）→ 只在規則 later_battle_cmds 開時才有。
static func available(b: Battle, srow: Dictionary) -> bool:
	return str(srow.get("since", "")) != LATER_SINCE or BattleCmds.later_cmds(b)

## 施加狀態（M3A_PLAN 5.7）：RESIST 抵抗 → 持續次數（定力縮短）→ REFRESH／LEVEL_MAX。
## 回傳事件（battle_proc_RESIST 或 battle_status_on）。check_resist=false：呼叫端已經擲過抵抗。
static func apply(b: Battle, u: BattleUnit, status_id: String, tables: Dictionary, level: int = 1,
		check_resist: bool = true) -> Array:
	if u == null or not u.is_active():
		return []
	var srow := row(status_id, tables)
	if not available(b, srow):
		return []
	if check_resist and (srow.get("resist_by", []) as Array).has("RESIST"):
		if try_proc(b, u, "RESIST", tables):
			return [proc_event(b, u, "RESIST", tables)]
	var n := duration_for(u, srow)
	var lv := maxi(1, level)
	var stacking := str(srow.get("stack", "REFRESH")) == "LEVEL_MAX"
	if stacking and u.statuses.has(status_id):
		lv = maxi(lv, u.status_level(status_id))
	u.statuses[status_id] = n
	u.status_levels[status_id] = lv
	var p := { "uid": u.uid, "name": u.unit_name(), "peer": u.peer, "status": status_id,
		"status_name": str(srow.get("name", status_id)) }
	if stacking:
		p["level"] = lv
	return [b.make_event("battle_status_on", p)]

## 移除狀態（解藥、逼毒、衝穴…）；回傳 battle_status_off 事件
static func remove(b: Battle, u: BattleUnit, status_id: String, tables: Dictionary) -> Array:
	if not u.statuses.has(status_id):
		return []
	u.statuses.erase(status_id)
	u.status_levels.erase(status_id)
	u.cured_statuses[status_id] = true   # 戰後寫回：治好的才從角色身上拿掉（行動次數用完的不算；M3a 審查 B1）
	var srow := row(status_id, tables)
	return [b.make_event("battle_status_off", { "uid": u.uid, "name": u.unit_name(), "peer": u.peer,
		"status": status_id, "status_name": str(srow.get("name", status_id)) })]

## 有沒有某種旗標的狀態（skip_actions、random_action）
static func has_flag(u: BattleUnit, flag: String, tables: Dictionary) -> String:
	for sid in u.statuses:
		if bool(row(str(sid), tables).get(flag, false)):
			return str(sid)
	return ""

## ---------------------------------------------------------------- 倍率

static func atk_mult(u: BattleUnit, tables: Dictionary) -> float:
	var m := 1.0
	for sid in u.statuses:
		m *= float(row(str(sid), tables).get("atk_mult", 1.0))
	if u.statuses.has("formation") and not u.formation.is_empty():
		m *= float(u.formation.get("atk", 1.0))
	return m

static func def_mult(u: BattleUnit, tables: Dictionary) -> float:
	var m := 1.0
	for sid in u.statuses:
		m *= float(row(str(sid), tables).get("def_mult", 1.0))
	if u.statuses.has("formation") and not u.formation.is_empty():
		m *= float(u.formation.get("def", 1.0))
	return m

static func gauge_mult(u: BattleUnit, tables: Dictionary) -> float:
	var m := 1.0
	for sid in u.statuses:
		m *= float(row(str(sid), tables).get("gauge_mult", 1.0))
	return m

## 每次行動開始扣的氣上限比例：qi_pct_per_action + qi_pct_per_level × 等級
static func action_pct(u: BattleUnit, status_id: String, srow: Dictionary) -> float:
	return float(srow.get("qi_pct_per_action", 0.0)) + float(srow.get("qi_pct_per_level", 0.0)) * u.status_level(status_id)

## ---------------------------------------------------------------- 門派技能觸發（5.6）

static func has_effect(u: BattleUnit, effect: String) -> bool:
	var ss := u.sect_skill()
	return str(ss.get("effect", "")) == effect and int(ss.get("level", 0)) >= 1

## 觸發消耗的兩項（sect_skill.cost 覆寫 → sects 表 sect_skill_cost → spec.sect 的那一列）
static func proc_cost(u: BattleUnit, tables: Dictionary) -> Array:
	var ss := u.sect_skill()
	if ss.get("cost", null) is Array:
		return ss.cost
	var sid := str(ss.get("id", ""))
	var sects: Dictionary = tables.get("sects", {})
	var srow: Dictionary = sects.get(u.sect(), {})
	if srow.is_empty() or str(srow.get("sect_skill", "")) != sid:
		srow = {}
		for r in sects.values():
			if r is Dictionary and str(r.get("sect_skill", "")) == sid:
				srow = r
				break
	var c: Variant = srow.get("sect_skill_cost", [])
	return c if c is Array else []

static func _stat(u: BattleUnit, k: String) -> int:
	match k:
		"jing": return u.jing
		"shen": return u.shen
		"neili": return u.neili
		"qi": return u.qi
	return 0

static func _pay(u: BattleUnit, k: String, n: int) -> void:
	match k:
		"jing": u.jing = maxi(0, u.jing - n)
		"shen": u.shen = maxi(0, u.shen - n)
		"neili": u.neili = maxi(0, u.neili - n)

## 新 8 種效果的觸發：效果相符 → 消耗付得起（不夠就不觸發、不擲骰）→ 擲 proc_chance → 扣消耗。
## 門派技能的戰鬥觸發是 2002-01-25（決戰光明頂，news 399 第 6 條）才開的 → 規則 later_battle_cmds 關時一律不觸發（M3a 審查修正）。
static func try_proc(b: Battle, u: BattleUnit, effect: String, tables: Dictionary) -> bool:
	if u == null or not u.is_active() or not has_effect(u, effect) or not BattleCmds.later_cmds(b):
		return false
	var cost := proc_cost(u, tables)
	for k in cost:
		if _stat(u, str(k)) < PROC_COST:
			return false
	if b.rng.randf() >= BattleFormulas.proc_chance(int(u.sect_skill().get("level", 0))):
		return false
	for k in cost:
		_pay(u, str(k), PROC_COST)
	return true

## battle_proc_<EFFECT> { uid, name, peer, skill_name }（HEAVY、COUNTER 另帶 def_uid）
static func proc_event(b: Battle, u: BattleUnit, effect: String, tables: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var p := { "uid": u.uid, "name": u.unit_name(), "peer": u.peer,
		"skill_name": BattleRules.sect_skill_name(u.sect_skill(), tables) }
	p.merge(extra, true)
	return b.make_event("battle_proc_" + effect, p)

## 毒牙的中毒等級（M3B_PLAN §5.1.7）
static func fang_level(sect_skill_level: int) -> int:
	return 1 + floori(maxi(0, sect_skill_level) / float(FANG_LEVEL_STEP))

## 自己的攻擊／招式命中（目標沒死）後：PARALYZE／CONFUSE／DISTRACT；M3b 加 POISON_FANG（毒牙：中毒）
static func on_hit_procs(b: Battle, att: BattleUnit, def: BattleUnit, tables: Dictionary) -> Array:
	var eff := str(att.sect_skill().get("effect", ""))
	if eff == FANG_EFFECT:
		if not def.is_active() or not try_proc(b, att, eff, tables):
			return []
		var fev: Array = [proc_event(b, att, eff, tables, { "def_uid": def.uid })]
		fev.append_array(apply(b, def, FANG_STATUS, tables, fang_level(int(att.sect_skill().get("level", 0)))))
		return fev
	if not HIT_EFFECTS.has(eff) or not def.is_active():
		return []
	if not try_proc(b, att, eff, tables):
		return []
	var ev: Array = [proc_event(b, att, eff, tables, { "def_uid": def.uid })]
	ev.append_array(apply(b, def, str(HIT_EFFECTS[eff]), tables))
	return ev

## 戰鬥中吃藥（「裝」底下的回復藥）之後：已經氣血失調 → 昏迷；本場第 MED_OVERUSE_AT 次起 → 氣血失調（news 316 的 2001 狀態；
## 研究 gaoshou/28「氣血失調 from medicine overuse…more medicine can cause 昏迷」；次數【設計提案】）
static func on_medicine(b: Battle, u: BattleUnit, tables: Dictionary) -> Array:
	if u == null or not u.is_active():
		return []
	u.med_taken += 1
	var st: Dictionary = tables.get("status_effects", {})
	if u.statuses.has("qixue") and st.has("coma"):
		return apply(b, u, "coma", tables, 1, false)
	if u.med_taken >= MED_OVERUSE_AT and st.has("qixue"):
		return apply(b, u, "qixue", tables, 1, false)
	return []

## 快照用：[{ id, name, glyph, color, n, level }]（依 id 排序）
static func snapshot(u: BattleUnit, tables: Dictionary) -> Array:
	var out: Array = []
	var ids := u.statuses.keys()
	ids.sort()
	for sid in ids:
		var srow := row(str(sid), tables)
		out.append({ "id": str(sid), "name": str(srow.get("name", sid)), "glyph": str(srow.get("glyph", "")),
			"color": str(srow.get("color", "")), "n": int(u.statuses[sid]), "level": u.status_level(str(sid)) })
	return out
