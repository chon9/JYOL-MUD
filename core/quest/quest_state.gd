class_name QuestState
extends RefCounted
## 每角色故事狀態（STORY_PLAN §4.7、§4.12）。純邏輯，不碰 Autoload。
##
## ch.quests = {
##   "active": { qid: { "v": 2, "stage": "s_abao", "objs": { "o_abao": 1 }, "vars": { "pick": "abao" },
##                      "since_world_s": 1234.0, "stage_since_world_s": 2345.0, "escort": "",
##                      "given": { item_id: n }, "paid": { key: n } } },   # given、paid 選填（審查修正）
##   "done":   { qid: { "n": 1, "outcome": "abao", "world_s": 3456.0, "failed": 0 } },
##   "cd":     { qid: 9999.0 },
##   "paid":   { qid: { key: n } }   # 選填（審查修正：放棄前已領的中途獎勵）
## }
## 舊格式（M1）：active[qid] = { step, counts }、done[qid] = int → migrate() 自動轉換。

const V := 2
## 審查修正：中途獎勵（reward 動作、learn add）的發放紀錄。active[qid].paid = { key: n }（這一次）；
## quests.paid = { qid: { key: n } }（放棄／失敗前已領、重接時抵掉；完成時清掉）
const PAID_KEY := "paid"

## 整份 quests 字典轉成新格式（回傳新字典；輸入不動）
static func migrate(quests: Dictionary) -> Dictionary:
	var out := { "active": {}, "done": {}, "cd": {} }
	var src_active: Variant = quests.get("active", {})
	if src_active is Dictionary:
		for qid in src_active:
			var e: Variant = src_active[qid]
			if e is Dictionary:
				out["active"][str(qid)] = migrate_active(e)
	var src_done: Variant = quests.get("done", {})
	if src_done is Dictionary:
		for qid in src_done:
			var d := migrate_done(src_done[qid])
			if int(d["n"]) > 0 or int(d["failed"]) > 0:
				out["done"][str(qid)] = d
	var src_cd: Variant = quests.get("cd", {})
	if src_cd is Dictionary:
		for qid in src_cd:
			if typeof(src_cd[qid]) in [TYPE_INT, TYPE_FLOAT]:
				out["cd"][str(qid)] = float(src_cd[qid])
	var src_paid: Variant = quests.get(PAID_KEY, null)
	if src_paid is Dictionary:
		var pd := {}
		for qid in src_paid:
			var m := _counts(src_paid[qid])
			if not m.is_empty():
				pd[str(qid)] = m
		if not pd.is_empty():
			out[PAID_KEY] = pd
	return out

## { key: n }（n > 0 的整數）；其他型別回 {}
static func _counts(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			var n := _int(v[k])
			if n > 0:
				out[str(k)] = n
	return out

## 就地確保 quests 是新格式（主機在每個入口呼叫；已是新格式時幾乎不花成本）
static func ensure(quests: Dictionary) -> void:
	if not (quests.get("active") is Dictionary):
		quests["active"] = {}
	if not (quests.get("done") is Dictionary):
		quests["done"] = {}
	if not (quests.get("cd") is Dictionary):
		quests["cd"] = {}
	var active: Dictionary = quests["active"]
	for qid in active.keys():
		var e: Variant = active[qid]
		if not (e is Dictionary):
			active.erase(qid)
		elif not (e as Dictionary).has("stage"):
			active[qid] = migrate_active(e)
	var done: Dictionary = quests["done"]
	for qid in done.keys():
		if not (done[qid] is Dictionary):
			done[qid] = migrate_done(done[qid])

## 一筆進行中的狀態：舊 { step, counts } → { stage: "step_<i>", objs: { "o": n } }；新格式只做型別整理
static func migrate_active(e: Dictionary) -> Dictionary:
	if not e.has("stage") and e.has("step"):
		var n := 0
		var counts: Variant = e.get("counts", {})
		if counts is Dictionary:
			for k in counts:
				n = maxi(n, _int(counts[k]))
		var objs := {}
		if n > 0:
			objs["o"] = n
		return { "v": V, "stage": "step_%d" % _int(e.get("step", 0)), "objs": objs, "vars": {},
			"since_world_s": 0.0, "stage_since_world_s": 0.0, "escort": "" }
	var out := {
		"v": V, "stage": str(e.get("stage", "")), "objs": {}, "vars": {},
		"since_world_s": _float(e.get("since_world_s", 0.0)),
		"stage_since_world_s": _float(e.get("stage_since_world_s", 0.0)),
		"escort": str(e.get("escort", "")) if e.get("escort") != null else "",
	}
	var objs2: Variant = e.get("objs", {})
	if objs2 is Dictionary:
		for k in objs2:
			out["objs"][str(k)] = _int(objs2[k])
	var vars: Variant = e.get("vars", {})
	if vars is Dictionary:
		for k in vars:
			out["vars"][str(k)] = clean_value(vars[k])
	# given（審查修正）：這次任務交給玩家的物品，放棄／失敗時收回；沒有這個鍵的舊狀態照舊只收 give_items
	var given: Variant = e.get("given", null)
	if given is Dictionary:
		var g := {}
		for k in given:
			var n := _int(given[k])
			if n > 0:
				g[str(k)] = n
		out["given"] = g
	var paid: Variant = e.get(PAID_KEY, null)
	if paid is Dictionary:
		out[PAID_KEY] = _counts(paid)
	return out

## 一筆完成紀錄：int → { n, outcome: "default", world_s: 0, failed: 0 }
static func migrate_done(v: Variant) -> Dictionary:
	if v is Dictionary:
		return { "n": maxi(0, _int(v.get("n", 0))), "outcome": str(v.get("outcome", "default")),
			"world_s": _float(v.get("world_s", 0.0)), "failed": maxi(0, _int(v.get("failed", 0))) }
	return { "n": maxi(0, _int(v)), "outcome": "default", "world_s": 0.0, "failed": 0 }

## JSON 讀回的變數值：整數值的 float → int；字串、布林照舊；其他型別轉字串
static func clean_value(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if is_equal_approx(v, roundf(v)) else v
		TYPE_INT, TYPE_BOOL, TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return str(v)
	return str(v)

## 兩個變數值是否相等（JSON 的 1 與 1.0、"1" 與 1 不同型別時以字串比）
static func value_eq(a: Variant, b: Variant) -> bool:
	var ca: Variant = clean_value(a)
	var cb: Variant = clean_value(b)
	if typeof(ca) == typeof(cb):
		return ca == cb
	if typeof(ca) in [TYPE_INT, TYPE_FLOAT] and typeof(cb) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(ca), float(cb))
	return str(ca) == str(cb)

# ---------- 查詢（舊／新格式都可讀，不修改） ----------
static func active_entry(quests: Variant, qid: String) -> Dictionary:
	if not (quests is Dictionary):
		return {}
	var a: Variant = quests.get("active", {})
	if not (a is Dictionary) or not a.has(qid) or not (a[qid] is Dictionary):
		return {}
	var e: Dictionary = a[qid]
	return e if e.has("stage") else migrate_active(e)

static func is_active(quests: Variant, qid: String) -> bool:
	return quests is Dictionary and quests.get("active") is Dictionary and (quests["active"] as Dictionary).has(qid)

static func done_entry(quests: Variant, qid: String) -> Dictionary:
	if not (quests is Dictionary) or not (quests.get("done") is Dictionary):
		return {}
	var d: Dictionary = quests["done"]
	if not d.has(qid):
		return {}
	return migrate_done(d[qid])

static func done_count(quests: Variant, qid: String) -> int:
	return int(done_entry(quests, qid).get("n", 0))

static func last_outcome(quests: Variant, qid: String) -> String:
	var d := done_entry(quests, qid)
	return str(d.get("outcome", "")) if int(d.get("n", 0)) > 0 else ""

static func get_var(quests: Variant, qid: String, name: String) -> Variant:
	return active_entry(quests, qid).get("vars", {}).get(name)

## 冷卻到期的世界時間（沒有 = 0）
static func cooldown_until(quests: Variant, qid: String) -> float:
	if not (quests is Dictionary) or not (quests.get("cd") is Dictionary):
		return 0.0
	return _float(quests["cd"].get(qid, 0.0))

# ---------- 目標進度 ----------
## 目前階段每個目標的進度 [{ id, text, have, need, done }]。
## TALK／REACH／FIGHT／ESCORT／STATE／WAIT：need 1，have = objs 的完成記號；
## DELIVER：未交付時 have = 背包數量（不超過 need），交付後 done；COLLECT：背包數量；KILL／BUY：objs 計數。
static func objective_progress(def: Dictionary, st: Dictionary, ch, tables: Dictionary) -> Array:
	var out: Array = []
	var stage := stage_of(def, str(st.get("stage", "")))
	var objs: Dictionary = st.get("objs", {}) if st.get("objs") is Dictionary else {}
	for o in stage.get("objectives", []):
		if not (o is Dictionary):
			continue
		var oid := str(o.get("id", ""))
		var t := str(o.get("type", ""))
		var need := maxi(1, _int(o.get("count", 1)))
		var mark := _int(objs.get(oid, 0))
		var have := 0
		var done := false
		match t:
			"KILL", "BUY":
				have = mini(mark, need)
				done = mark >= need
			"COLLECT":
				have = mini(_inv_count(ch, str(o.get("item", ""))), need)
				done = have >= need
			"DELIVER":
				done = mark >= 1
				have = need if done else mini(_inv_count(ch, str(o.get("item", ""))), need)
			_:
				need = 1
				done = mark >= 1
				have = 1 if done else 0
		out.append({ "id": oid, "text": str(o.get("text", "")), "have": have, "need": need, "done": done })
	return out

static func stage_of(def: Dictionary, stage_id: String) -> Dictionary:
	for s in def.get("stages", []):
		if s is Dictionary and str(s.get("id", "")) == stage_id:
			return s
	return {}

static func _inv_count(ch, item_id: String) -> int:
	if ch == null or item_id == "":
		return 0
	return int(ch.inventory.count(item_id))

static func _int(v: Variant) -> int:
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			return int(v)
		TYPE_STRING:
			return int(v) if (v as String).is_valid_int() else 0
		TYPE_BOOL:
			return 1 if v else 0
	return 0

static func _float(v: Variant) -> float:
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0.0
