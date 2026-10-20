class_name QuestDef
extends RefCounted
## 任務資料第 2 版（STORY_PLAN §4.2–§4.6、§4.12）。純邏輯。
## normalize()：舊格式（steps）→ 新格式（stages），並補預設值；DataLoader.activate 在生效視圖上做，引擎只看新格式。
## validate()：lint 共用的結構檢查（data_lint 與單元測試呼叫）。

const OBJ_TYPES := ["TALK", "DELIVER", "COLLECT", "KILL", "FIGHT", "REACH", "BUY", "WAIT", "STATE", "ESCORT"]
const ACTIONS := ["accept", "complete", "var", "goto", "finish", "fail", "give", "take", "reward", "flag", "unflag",
	"learn", "fight", "escort_start", "escort_end", "tell", "rumor", "close"]
const FIGHT_WIN := ["WIN", "WIN_OR_FLEE", "ANY"]
const RUMOR_SCOPES := ["WORLD", "REGION"]
## 獎勵欄位（§4.9）：既有 + lilian、killing_intent、learn、rumor；
## learn_add（審查修正）：{ skill_id: n } = 在目前等級上「再升 n 級」（learn 是學到絕對等級，已高於則不變）。
## 例：藍鳳凰「基本毒術升一級」每次完成都要 +1（研究 2001-8-2 n820_736977）。
const REWARD_KEYS := ["money", "combat_xp", "learn_points", "fame", "morality", "items", "flags", "skill_prof",
	"lilian", "killing_intent", "learn", "learn_add", "rumor"]
## 結局列／目標列的 src 標記（審查修正）：src 是整列的出處；field_src 逐欄覆寫（{ "morality": "later", "lilian": "proposal" }）
const SRC_TAGS := ["verified", "later", "proposal", "unverified"]   # unverified：有出處但未能重抓【待考證】（M3b 審查）
const REWARD_INT_KEYS := ["money", "combat_xp", "learn_points", "fame", "morality", "lilian", "killing_intent"]
## §3.5 既有與新增的旗標（flag 動作可直接用；其他新旗標要有「前綴_」）
const KNOWN_FLAGS := ["wd_q_yinliu", "wd_q_heiyu", "wd_q_longmen", "wd_q_yitian", "wd_q_taiji", "em_shougongsha",
	"em_miejian_ok", "em_juejian_ok", "em_foguang_ok", "xd_xuehai_lv1", "lj_bahuang_learned",
	"hs_qizong", "hs_jianzong", "hs_zixia_ok", "xh_huagong_ok", "sl_riyuebian_ok"]
const END := "END"
const DEFAULT_OUTCOME := "default"
const LEGACY_STEP_FIELDS := { "TALK": "npc", "DELIVER": "npc", "KILL": "monster", "REACH": "room" }

# ---------------------------------------------------------------- normalize
## 舊→新並補預設值。回傳新字典（輸入不動）。已是第 2 版（有 stages）只補預設值。
## 舊格式的列保留原本的 steps／repeatable／rewards 欄位（給還在讀舊欄位的工具與測試），並標 "_legacy": true。
static func normalize(row: Dictionary) -> Dictionary:
	var r := row.duplicate(true)
	if not r.has("stages") and r.get("steps") is Array:
		_from_legacy(r)
	r["v"] = 2
	r["id"] = str(r.get("id", ""))
	r["name"] = str(r.get("name", r["id"]))
	r["chapter"] = str(r.get("chapter", ""))
	r["text"] = str(r.get("text", ""))
	r["giver"] = str(r.get("giver", ""))
	if not (r.get("requires") is Array):
		r["requires"] = []
	if not (r.get("give_items") is Array):
		r["give_items"] = []
	r["repeat"] = _repeat_of(r)
	r["abandon"] = r.get("abandon", true) != false
	r["party_credit"] = r.get("party_credit", true) != false
	r["offer"] = str(r.get("offer", "")) if r.get("offer") != null else ""
	if not (r.get("stages") is Array):
		r["stages"] = []
	var stages: Array = r["stages"]
	for i in stages.size():
		if stages[i] is Dictionary:
			stages[i] = _norm_stage(stages[i], i, stages)
	var start := str(r.get("start", ""))
	if start == "" and not stages.is_empty() and stages[0] is Dictionary:
		start = str(stages[0].get("id", ""))
	r["start"] = start
	if not (r.get("dialogues") is Dictionary):
		r["dialogues"] = {}
	for did in r["dialogues"]:
		if r["dialogues"][did] is Dictionary:
			r["dialogues"][did] = _norm_dialogue(r["dialogues"][did])
	if not (r.get("outcomes") is Dictionary):
		r["outcomes"] = {}
	var outcomes: Dictionary = r["outcomes"]
	for k in outcomes:
		if not (outcomes[k] is Dictionary):
			outcomes[k] = {}
		var o: Dictionary = outcomes[k]
		o["label"] = str(o.get("label", ""))
		o["rewards"] = norm_rewards(o.get("rewards", {}))
	if not (r.get("rumors") is Dictionary):
		r["rumors"] = {}
	return r

static func _repeat_of(r: Dictionary) -> Dictionary:
	var rp: Variant = r.get("repeat")
	if rp is Dictionary:
		return { "max": maxi(0, _int(rp.get("max", 1))), "cooldown_days": maxf(0.0, _float(rp.get("cooldown_days", 0.0))) }
	if bool(r.get("repeatable", false)):
		return { "max": 0, "cooldown_days": 0.0 }
	return { "max": 1, "cooldown_days": 0.0 }

static func _from_legacy(r: Dictionary) -> void:
	var stages: Array = []
	var steps: Array = r["steps"]
	for i in steps.size():
		var st: Variant = steps[i]
		if not (st is Dictionary):
			continue
		var t := str(st.get("type", ""))
		var o := { "id": "o", "type": t, "text": str(st.get("text", "")) }
		var field := str(LEGACY_STEP_FIELDS.get(t, "npc"))
		o[field] = str(st.get("target", ""))
		match t:
			"DELIVER":
				o["item"] = str(st.get("item", ""))
				o["count"] = maxi(1, _int(st.get("count", 1)))
				o["consume"] = true
			"KILL":
				o["count"] = maxi(1, _int(st.get("count", 1)))
		stages.append({ "id": "step_%d" % i, "title": str(st.get("text", "")), "log": "", "objectives": [o] })
	for i in stages.size():
		stages[i]["next"] = stages[i + 1]["id"] if i + 1 < stages.size() else END
	r["stages"] = stages
	if not r.has("outcomes"):
		r["outcomes"] = { DEFAULT_OUTCOME: { "label": "", "rewards": norm_rewards(r.get("rewards", {})) } }
	r["_legacy"] = true

static func _norm_stage(st: Dictionary, i: int, all: Array) -> Dictionary:
	var s := st
	s["id"] = str(s.get("id", "stage_%d" % i))
	s["title"] = str(s.get("title", ""))
	s["log"] = str(s.get("log", ""))
	s["hint_room"] = str(s.get("hint_room", ""))
	s["any"] = bool(s.get("any", false))
	for k in ["objectives", "on_enter", "on_complete", "room_actions", "fail_if"]:
		if not (s.get(k) is Array):
			s[k] = []
	for o in s["objectives"]:
		if o is Dictionary:
			o["id"] = str(o.get("id", ""))
			o["type"] = str(o.get("type", ""))
			o["text"] = str(o.get("text", ""))
			if o.has("count"):
				o["count"] = maxi(1, _int(o["count"]))
			if str(o["type"]) == "DELIVER" and not o.has("consume"):
				o["consume"] = true
	for a in s["room_actions"]:
		if a is Dictionary:
			a["id"] = str(a.get("id", ""))
			if not (a.get("do") is Array):
				a["do"] = []
			if not (a.get("hours") is Array):
				a["hours"] = []
			if not (a.get("requires") is Array):
				a["requires"] = []
			a["repeat"] = a.get("repeat", true) != false
	s["next"] = norm_next(s.get("next"), i, all)
	return s

## next → [{ "if": [...], "goto": "<stage>|END:<x>" }, …]（最後一項無條件）
static func norm_next(nx: Variant, i: int = -1, all: Array = []) -> Array:
	if nx == null or (nx is String and nx == ""):
		# 沒寫 next：下一個階段；最後一個結束
		if i >= 0 and i + 1 < all.size() and all[i + 1] is Dictionary:
			return [{ "goto": str(all[i + 1].get("id", "")) }]
		return [{ "goto": END + ":" + DEFAULT_OUTCOME }]
	if nx is String:
		return [{ "goto": norm_goto(nx) }]
	var out: Array = []
	if nx is Array:
		for e in nx:
			if e is Dictionary:
				var c := { "goto": norm_goto(str(e.get("goto", ""))) }
				if e.get("if") is Array and not (e["if"] as Array).is_empty():
					c["if"] = e["if"]
				out.append(c)
	return out

## "END" → "END:default"；其餘不變
static func norm_goto(g: String) -> String:
	return END + ":" + DEFAULT_OUTCOME if g == END else g

static func is_end(g: String) -> bool:
	return g == END or g.begins_with(END + ":")

static func outcome_of(g: String) -> String:
	if g == END:
		return DEFAULT_OUTCOME
	return g.substr(END.length() + 1) if g.begins_with(END + ":") else ""

static func _norm_dialogue(d: Dictionary) -> Dictionary:
	if not (d.get("nodes") is Dictionary):
		d["nodes"] = {}
	d["start"] = str(d.get("start", ""))
	d["resume"] = str(d.get("resume", d["start"])) if d.get("resume") != null else d["start"]
	if str(d["resume"]) == "":
		d["resume"] = d["start"]
	for nid in d["nodes"]:
		var n: Variant = d["nodes"][nid]
		if not (n is Dictionary):
			d["nodes"][nid] = {}
			continue
		n["speaker"] = str(n.get("speaker", "npc"))
		n["text"] = str(n.get("text", ""))
		if not (n.get("do") is Array):
			n["do"] = []
		if n.get("choices") is Array:
			for c in n["choices"]:
				if c is Dictionary:
					c["id"] = str(c.get("id", ""))
					c["label"] = str(c.get("label", ""))
					if not (c.get("do") is Array):
						c["do"] = []
					if not (c.get("requires") is Array):
						c["requires"] = []
					c["goto"] = str(c.get("goto", END)) if c.get("goto") != null else END
		else:
			n["choices"] = []
		n["goto"] = str(n.get("goto", "")) if n.get("goto") != null else ""
	return d

## 獎勵字典補型別（整數欄位轉 int、items／flags 陣列、skill_prof／learn 字典）
static func norm_rewards(v: Variant) -> Dictionary:
	var r: Dictionary = (v as Dictionary).duplicate(true) if v is Dictionary else {}
	for k in REWARD_INT_KEYS:
		if r.has(k):
			r[k] = _int(r[k])
	if not (r.get("items") is Array):
		r["items"] = []
	for it in r["items"]:
		if it is Dictionary:
			it["n"] = maxi(1, _int(it.get("n", 1)))
	if not (r.get("flags") is Array):
		r["flags"] = []
	for k in ["skill_prof", "learn", "learn_add"]:
		if not (r.get(k) is Dictionary):
			r[k] = {}
		for sid in r[k]:
			r[k][sid] = _int(r[k][sid])
	r["rumor"] = str(r.get("rumor", "")) if r.get("rumor") != null else ""
	return r

# ---------------------------------------------------------------- 查詢
static func stage(def: Dictionary, stage_id: String) -> Dictionary:
	for s in def.get("stages", []):
		if s is Dictionary and str(s.get("id", "")) == stage_id:
			return s
	return {}

static func objective(def: Dictionary, stage_id: String, obj_id: String) -> Dictionary:
	for o in stage(def, stage_id).get("objectives", []):
		if o is Dictionary and str(o.get("id", "")) == obj_id:
			return o
	return {}

static func dialogue(def: Dictionary, dlg_id: String) -> Dictionary:
	var d: Variant = def.get("dialogues", {}).get(dlg_id, {})
	return d if d is Dictionary else {}

# ---------------------------------------------------------------- validate
## tables：生效視圖（npcs、items、monsters、maps、martial_arts、basic_skills、life_skills、text_templates…）；
## 某個表不在 tables 裡就略過那類參照檢查（單元測試用小表）。回傳錯誤字串（空 = 通過）。
static func validate(row: Dictionary, tables: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var qid := str(row.get("id", "?"))
	var L := "quests.%s" % qid
	if row.has("stages") and row.has("steps") and not bool(row.get("_legacy", false)):
		errs.append("%s: stages and steps are mutually exclusive" % L)
	if not row.has("stages") and not (row.get("steps") is Array):
		errs.append("%s: needs stages[] (or legacy steps[])" % L)
		return errs
	var q := normalize(row)
	var stages: Array = q["stages"]
	if stages.is_empty():
		errs.append("%s: stages[] is empty" % L)
		return errs
	var stage_ids := {}
	for s in stages:
		if not (s is Dictionary):
			errs.append("%s: stage is not an object" % L)
			continue
		var sid := str(s["id"])
		if sid == "" or stage_ids.has(sid):
			errs.append("%s: empty or duplicate stage id '%s'" % [L, sid])
		stage_ids[sid] = true
	if not stage_ids.has(str(q["start"])):
		errs.append("%s: start '%s' is not a stage" % [L, q["start"]])
	var outcomes: Dictionary = q["outcomes"]
	var dialogues: Dictionary = q["dialogues"]
	if str(q["offer"]) != "" and not dialogues.has(str(q["offer"])):
		errs.append("%s: offer dialogue '%s' missing" % [L, q["offer"]])
	errs.append_array(DataSchema.check_conditions(q.get("requires", []), L + ".requires"))
	var rooms := _room_set(tables)
	var all_obj_ids := {}
	for s in stages:
		if not (s is Dictionary):
			continue
		var SL := "%s.%s" % [L, s["id"]]
		var oids := {}
		for o in s["objectives"]:
			if not (o is Dictionary):
				errs.append("%s: objective is not an object" % SL)
				continue
			var oid := str(o["id"])
			if oid == "" or oids.has(oid):
				errs.append("%s: empty or duplicate objective id '%s'" % [SL, oid])
			oids[oid] = true
			all_obj_ids[oid] = true
			errs.append_array(_check_objective(o, "%s.%s" % [SL, oid], tables, rooms, dialogues))
		if (s["objectives"] as Array).is_empty():
			errs.append("%s: objectives[] is empty" % SL)
		var nx: Array = s["next"]
		if nx.is_empty():
			errs.append("%s: next is empty" % SL)
		for i in nx.size():
			var e: Dictionary = nx[i]
			var last := i == nx.size() - 1
			if last and e.has("if"):
				errs.append("%s: last next entry must be unconditional" % SL)
			if not last and not e.has("if"):
				errs.append("%s: next entry %d is unconditional but not last" % [SL, i])
			if e.has("if"):
				errs.append_array(DataSchema.check_conditions(e["if"], SL + ".next.if"))
			errs.append_array(_check_goto(str(e["goto"]), SL + ".next", stage_ids, outcomes))
		errs.append_array(DataSchema.check_conditions(s["fail_if"], SL + ".fail_if"))
		for k in ["on_enter", "on_complete"]:
			errs.append_array(check_actions(s[k], "%s.%s" % [SL, k], q, tables, stage_ids))
		var aids := {}
		for a in s["room_actions"]:
			if not (a is Dictionary):
				errs.append("%s: room action is not an object" % SL)
				continue
			var AL := "%s.room_actions.%s" % [SL, a["id"]]
			if str(a["id"]) == "" or aids.has(str(a["id"])):
				errs.append("%s: empty or duplicate room action id" % AL)
			aids[str(a["id"])] = true
			if str(a.get("label", "")) == "":
				errs.append("%s: label missing" % AL)
			if not rooms.is_empty() and not rooms.has(str(a.get("room", ""))):
				errs.append("%s: room '%s' missing" % [AL, str(a.get("room", ""))])
			errs.append_array(_check_hours(a["hours"], AL))
			errs.append_array(DataSchema.check_conditions(a["requires"], AL + ".requires"))
			errs.append_array(check_actions(a["do"], AL, q, tables, stage_ids))
	# 對話
	for did in dialogues:
		errs.append_array(_check_dialogue(dialogues[did], "%s.dialogues.%s" % [L, did], q, tables, stage_ids))
	# 動作裡的 complete obj 要指到某個目標
	for oid in _complete_targets(q):
		if not all_obj_ids.has(oid):
			errs.append("%s: complete obj '%s' is not an objective" % [L, oid])
	# 結局
	for k in outcomes:
		errs.append_array(_check_rewards(outcomes[k].get("rewards", {}), "%s.outcomes.%s" % [L, k], tables))
	for g in _all_gotos(q):
		if is_end(g):
			var oc := outcome_of(g)
			if not outcomes.has(oc):
				errs.append("%s: END:%s has no outcomes.%s" % [L, oc, oc])
	# 圖：每個階段從 start 走得到、每個階段都能走到 END
	errs.append_array(_check_graph(q, L))
	if not (q.get("repeat") is Dictionary):
		errs.append("%s: bad repeat" % L)
	return errs

static func _room_set(tables: Dictionary) -> Dictionary:
	var out := {}
	var maps: Variant = tables.get("maps", {})
	if maps is Dictionary:
		for rid in maps:
			for room in maps[rid].get("rooms", []):
				if room is Dictionary:
					out[str(room.get("id", ""))] = true
	return out

static func _has(tables: Dictionary, table: String, id: String) -> bool:
	return not tables.has(table) or (tables[table] as Dictionary).has(id)

static func _skill_exists(tables: Dictionary, sid: String) -> bool:
	if not (tables.has("martial_arts") or tables.has("basic_skills") or tables.has("life_skills")):
		return true
	for t in ["martial_arts", "basic_skills", "life_skills"]:
		if tables.get(t, {}).has(sid):
			return true
	for sect in tables.get("sects", {}):
		if str(tables["sects"][sect].get("sect_skill", "")) == sid:
			return true
	return false

static func _check_hours(hours: Variant, where: String) -> PackedStringArray:
	var errs := PackedStringArray()
	if not (hours is Array):
		errs.append("%s: hours must be an array" % where)
		return errs
	for h in hours:
		if not (str(h) in DataSchema.SHICHEN):
			errs.append("%s: bad shichen '%s'" % [where, str(h)])
	return errs

static func _check_objective(o: Dictionary, L: String, tables: Dictionary, rooms: Dictionary, dialogues: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var t := str(o["type"])
	if not (t in OBJ_TYPES):
		errs.append("%s: bad objective type '%s'" % [L, t])
		return errs
	var need := {
		"TALK": ["npc"], "DELIVER": ["npc", "item"], "COLLECT": ["item"], "KILL": ["monster"], "FIGHT": [],
		"REACH": ["room"], "BUY": ["item"], "WAIT": [], "STATE": ["requires"], "ESCORT": ["npc", "to_room"],
	}
	for f in need[t]:
		if not o.has(f) or (o[f] is String and str(o[f]) == ""):
			errs.append("%s: %s missing '%s'" % [L, t, f])
	if o.has("npc") and str(o["npc"]) != "" and not _has(tables, "npcs", str(o["npc"])):
		errs.append("%s: npc '%s' missing" % [L, o["npc"]])
	if o.has("item") and str(o["item"]) != "" and not _has(tables, "items", str(o["item"])):
		errs.append("%s: item '%s' missing" % [L, o["item"]])
	if o.has("monster") and str(o["monster"]) != "" and not _has(tables, "monsters", str(o["monster"])):
		errs.append("%s: monster '%s' missing" % [L, o["monster"]])
	for rk in ["room", "to_room"]:
		if o.has(rk) and not rooms.is_empty() and not rooms.has(str(o[rk])):
			errs.append("%s: %s '%s' missing" % [L, rk, o[rk]])
	if o.has("dialogue") and str(o["dialogue"]) != "" and not dialogues.has(str(o["dialogue"])):
		errs.append("%s: dialogue '%s' missing" % [L, o["dialogue"]])
	if o.has("hours"):
		errs.append_array(_check_hours(o["hours"], L))
	match t:
		"FIGHT":
			if not (str(o.get("win", "WIN")) in FIGHT_WIN):
				errs.append("%s: FIGHT win must be one of %s" % [L, str(FIGHT_WIN)])
		"WAIT":
			if not o.has("days") and not o.has("hours"):
				errs.append("%s: WAIT needs days or hours" % L)
			if o.has("days") and _float(o["days"]) < 0.0:
				errs.append("%s: WAIT days < 0" % L)
		"STATE":
			errs.append_array(DataSchema.check_conditions(o.get("requires", []), L + ".requires"))
	return errs

static func _check_goto(g: String, where: String, stage_ids: Dictionary, outcomes: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	if g == "":
		errs.append("%s: empty goto" % where)
	elif is_end(g):
		if not outcomes.has(outcome_of(g)):
			errs.append("%s: %s has no outcome" % [where, g])
	elif not stage_ids.has(g):
		errs.append("%s: goto stage '%s' missing" % [where, g])
	return errs

## 動作陣列（對話選項、節點、on_enter、on_complete、房間動作共用）
static func check_actions(acts: Variant, L: String, q: Dictionary, tables: Dictionary, stage_ids: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	if not (acts is Array):
		errs.append("%s: do must be an array" % L)
		return errs
	for a in acts:
		if not (a is Dictionary):
			errs.append("%s: action is not an object" % L)
			continue
		var d := str(a.get("do", ""))
		if not (d in ACTIONS):
			errs.append("%s: unknown action '%s'" % [L, d])
			continue
		match d:
			"complete":
				if str(a.get("obj", "")) == "":
					errs.append("%s: complete needs obj" % L)
			"var":
				# value：固定值；random：[值…] 隨機取一個（審查修正：日月鞭法的「隨機佛經」）
				if str(a.get("name", "")) == "" or (not a.has("value") and not a.has("random")):
					errs.append("%s: var needs name and value (or random)" % L)
				elif a.has("random"):
					if not (a["random"] is Array) or (a["random"] as Array).is_empty():
						errs.append("%s: var random must be a non-empty array" % L)
					else:
						for rv in a["random"]:
							if not (typeof(rv) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL]):
								errs.append("%s: var random values must be string/int/bool" % L)
				elif not (typeof(a["value"]) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL]):
					errs.append("%s: var value must be string/int/bool" % L)
			"goto":
				if not stage_ids.has(str(a.get("stage", ""))):
					errs.append("%s: goto stage '%s' missing" % [L, str(a.get("stage", ""))])
			"finish":
				var oc := str(a.get("outcome", DEFAULT_OUTCOME))
				if not q.get("outcomes", {}).has(oc):
					errs.append("%s: finish outcome '%s' missing" % [L, oc])
			"fail":
				var rk := str(a.get("reason", ""))
				if rk != "" and tables.has("text_templates") and not tables["text_templates"].has(rk):
					errs.append("%s: fail reason template '%s' missing" % [L, rk])
			"give", "take":
				var it := str(a.get("item", ""))
				if it == "" or not _has(tables, "items", it):
					errs.append("%s: %s item '%s' missing" % [L, d, it])
				if a.has("n") and _int(a["n"]) < 1:
					errs.append("%s: %s n < 1" % [L, d])
			"reward":
				errs.append_array(_check_rewards(a.get("rewards", a), L, tables, true))
			"flag", "unflag":
				var fl := str(a.get("flag", ""))
				if not flag_name_ok(fl):
					errs.append("%s: flag '%s' must be a §3.5 flag or start with a prefix_" % [L, fl])
			"learn":
				var sk := str(a.get("skill", ""))
				if sk == "" or not _skill_exists(tables, sk):
					errs.append("%s: learn skill '%s' missing" % [L, sk])
				# level：學到絕對等級；add：在目前等級上再升 add 級（審查修正）
				if a.has("add"):
					if _int(a.get("add", 0)) < 1:
						errs.append("%s: learn add < 1" % L)
				elif _int(a.get("level", 0)) < 1:
					errs.append("%s: learn level < 1" % L)
			"fight":
				var ms: Variant = a.get("monsters", [])
				var waves: Variant = a.get("waves", [])
				if (not (ms is Array) or (ms as Array).is_empty()) and (not (waves is Array) or (waves as Array).is_empty()):
					errs.append("%s: fight needs monsters or waves" % L)
				var all_m: Array = []
				if ms is Array:
					all_m.append_array(ms)
				if waves is Array:
					for w in waves:
						if w is Array:
							all_m.append_array(w)
				for m in all_m:
					if not _has(tables, "monsters", str(m)):
						errs.append("%s: fight monster '%s' missing" % [L, str(m)])
				if a.has("npc") and str(a["npc"]) != "" and not _has(tables, "npcs", str(a["npc"])):
					errs.append("%s: fight npc '%s' missing" % [L, str(a["npc"])])
			"escort_start", "escort_end":
				var n := str(a.get("npc", ""))
				if d == "escort_start" and (n == "" or not _has(tables, "npcs", n)):
					errs.append("%s: escort npc '%s' missing" % [L, n])
			"tell":
				var k := str(a.get("key", ""))
				if k == "" or (tables.has("text_templates") and not tables["text_templates"].has(k)):
					errs.append("%s: tell template '%s' missing" % [L, k])
			"rumor":
				if str(a.get("key", "")) == "":
					errs.append("%s: rumor needs key" % L)
				if a.has("scope") and not (str(a["scope"]) in RUMOR_SCOPES):
					errs.append("%s: rumor scope must be WORLD or REGION" % L)
	return errs

static func flag_name_ok(fl: String) -> bool:
	if fl in KNOWN_FLAGS:
		return true
	var u := fl.find("_")
	return u >= 2 and u < fl.length() - 1

static func _check_rewards(rw: Variant, L: String, tables: Dictionary, inline := false) -> PackedStringArray:
	var errs := PackedStringArray()
	if not (rw is Dictionary):
		errs.append("%s: rewards must be an object" % L)
		return errs
	for k in rw:
		if inline and k == "do":
			continue
		if not (str(k) in REWARD_KEYS):
			errs.append("%s: unknown reward key '%s'" % [L, k])
	for it in rw.get("items", []):
		if not (it is Dictionary) or not _has(tables, "items", str(it.get("id", ""))):
			errs.append("%s: reward item '%s' missing" % [L, str(it.get("id", "")) if it is Dictionary else str(it)])
	for k in ["skill_prof", "learn", "learn_add"]:
		var d: Variant = rw.get(k, {})
		if d is Dictionary:
			for sid in d:
				if not _skill_exists(tables, str(sid)):
					errs.append("%s: %s skill '%s' missing" % [L, k, sid])
	return errs

static func _check_dialogue(d: Variant, L: String, q: Dictionary, tables: Dictionary, stage_ids: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	if not (d is Dictionary):
		errs.append("%s: not an object" % L)
		return errs
	var nodes: Dictionary = d.get("nodes", {})
	if nodes.is_empty():
		errs.append("%s: nodes is empty" % L)
	for k in ["start", "resume"]:
		if not nodes.has(str(d.get(k, ""))):
			errs.append("%s: %s node '%s' missing" % [L, k, str(d.get(k, ""))])
	for nid in nodes:
		var n: Dictionary = nodes[nid]
		var NL := "%s.%s" % [L, nid]
		var sp := str(n.get("speaker", "npc"))
		if not (sp in ["npc", "player"]) and not _has(tables, "npcs", sp):
			errs.append("%s: speaker '%s' missing" % [NL, sp])
		errs.append_array(check_actions(n.get("do", []), NL + ".do", q, tables, stage_ids))
		var choices: Array = n.get("choices", [])
		var g := str(n.get("goto", ""))
		if not choices.is_empty() and g != "":
			errs.append("%s: choices and goto are exclusive" % NL)
		if g != "" and g != END and not nodes.has(g):
			errs.append("%s: goto node '%s' missing" % [NL, g])
		var cids := {}
		for c in choices:
			if not (c is Dictionary):
				errs.append("%s: choice is not an object" % NL)
				continue
			var cid := str(c.get("id", ""))
			if cid == "" or cids.has(cid) or cid.begins_with("_"):
				errs.append("%s: empty, duplicate or reserved choice id '%s'" % [NL, cid])
			cids[cid] = true
			if str(c.get("label", "")) == "":
				errs.append("%s.%s: label missing" % [NL, cid])
			errs.append_array(DataSchema.check_conditions(c.get("requires", []), "%s.%s.requires" % [NL, cid]))
			errs.append_array(check_actions(c.get("do", []), "%s.%s" % [NL, cid], q, tables, stage_ids))
			var cg := str(c.get("goto", END))
			if cg != END and not nodes.has(cg):
				errs.append("%s.%s: goto node '%s' missing" % [NL, cid, cg])
	return errs

## 所有動作裡 complete 的 obj
static func _complete_targets(q: Dictionary) -> Array:
	var out: Array = []
	for a in _all_actions(q):
		if str(a.get("do", "")) == "complete":
			out.append(str(a.get("obj", "")))
		if str(a.get("do", "")) == "fight" and str(a.get("obj", "")) != "":
			out.append(str(a.get("obj", "")))
	return out

static func _all_actions(q: Dictionary) -> Array:
	var out: Array = []
	for s in q.get("stages", []):
		if not (s is Dictionary):
			continue
		for k in ["on_enter", "on_complete"]:
			for a in s.get(k, []):
				if a is Dictionary:
					out.append(a)
		for ra in s.get("room_actions", []):
			if ra is Dictionary:
				for a in ra.get("do", []):
					if a is Dictionary:
						out.append(a)
	for did in q.get("dialogues", {}):
		out.append_array(_dialogue_actions(q["dialogues"][did]))
	return out

static func _dialogue_actions(d: Variant) -> Array:
	var out: Array = []
	if not (d is Dictionary):
		return out
	for nid in d.get("nodes", {}):
		var n: Variant = d["nodes"][nid]
		if not (n is Dictionary):
			continue
		for a in n.get("do", []):
			if a is Dictionary:
				out.append(a)
		for c in n.get("choices", []):
			if c is Dictionary:
				for a in c.get("do", []):
					if a is Dictionary:
						out.append(a)
	return out

## next 的 goto 與 finish 動作的 END:x
static func _all_gotos(q: Dictionary) -> Array:
	var out: Array = []
	for s in q.get("stages", []):
		if s is Dictionary:
			for e in s.get("next", []):
				out.append(str(e.get("goto", "")))
	for a in _all_actions(q):
		if str(a.get("do", "")) == "finish":
			out.append(END + ":" + str(a.get("outcome", DEFAULT_OUTCOME)))
	return out

## 階段圖：邊 = next 的 goto ＋ 本階段觸得到的動作（on_enter／on_complete／房間動作／目標對話）裡的 goto／finish。
## 每個階段要從 start 走得到；每個走得到的階段都要能走到 END（沒有死循環）。
static func _check_graph(q: Dictionary, L: String) -> PackedStringArray:
	var errs := PackedStringArray()
	var edges := {}   # stage -> [target]（target = stage id 或 "END"）
	for s in q["stages"]:
		if not (s is Dictionary):
			continue
		var sid := str(s["id"])
		var outs: Array = []
		for e in s["next"]:
			var g := str(e.get("goto", ""))
			outs.append(END if is_end(g) else g)
		var acts: Array = []
		for k in ["on_enter", "on_complete"]:
			acts.append_array(s[k])
		for ra in s["room_actions"]:
			if ra is Dictionary:
				acts.append_array(ra.get("do", []))
		for o in s["objectives"]:
			if o is Dictionary and str(o.get("dialogue", "")) != "":
				acts.append_array(_dialogue_actions(dialogue(q, str(o["dialogue"]))))
		for a in acts:
			if not (a is Dictionary):
				continue
			match str(a.get("do", "")):
				"goto":
					outs.append(str(a.get("stage", "")))
				"finish", "fail":
					outs.append(END)
		edges[sid] = outs
	var start := str(q["start"])
	if not edges.has(start):
		return errs
	var seen := { start: true }
	var stack: Array = [start]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		for t in edges.get(cur, []):
			if t != END and edges.has(t) and not seen.has(t):
				seen[t] = true
				stack.append(t)
	for sid in edges:
		if not seen.has(sid):
			errs.append("%s: stage '%s' unreachable from start" % [L, sid])
	# 反向：能到 END 的階段
	var can_end := {}
	var changed := true
	while changed:
		changed = false
		for sid in edges:
			if can_end.has(sid):
				continue
			for t in edges[sid]:
				if t == END or can_end.has(t):
					can_end[sid] = true
					changed = true
					break
	for sid in seen:
		if not can_end.has(sid):
			errs.append("%s: stage '%s' can never reach END (loop)" % [L, sid])
	return errs

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
