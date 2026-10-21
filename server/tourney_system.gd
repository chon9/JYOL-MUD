class_name TourneySystem
extends RefCounted
## 門派比武與武林大會主機端（M3D_PLAN §5.3；【後期版 2002・設計提案】R14）。GameHost.tourney；GameHost 依 M3D_SYSTEMS 以路徑 load()。
##
## 種類：WULIN（武林大會，所有人）、SECT:<sect>（門派比武，該派弟子）。地點：西夏比武場擂臺 xx_biwu、休息區 xx_biwu_rest（safe）。
## 排程：日曆（WorldClock：武林大會每月 15 日午時開打、8 日起報名；門派比武每月 1／2 日依 §5.3.7 的時辰、上月 24 日起報名）
##   或主機開辦（tourney_host，HOST，報名 signup_s 真實秒）。同一時間只進行一場比賽（同時到點的排隊）。
## 對戰表：TourneyRules.bracket（單淘汰、輪空自動晉級、上屆冠軍放下半區種子位、seed 可重現）。
## 點名：每場開始前 ev_tourney_call（選手與兩間房），選手要在擂臺或休息區、閒置、不在牢裡；每 30 真實秒點一次，3 次不到判負
##   （兩人都不到 → 都判負，下一輪對手輪空）。比賽：BattleSystem.start_pvp(a, b, "DUEL", { duel_limit_s: 600 })。
## 報名條件（TourneyRules.entry_reason；M3d 審查）：武林大會 實戰 ≥ 1 萬、沒有 PK值；門派比武 該派弟子、實戰 ≥ 1000（恆山、全真另有
##   實戰、善惡、門技；恆山、少林沒有 PK值）。報名時查；開打時與每一場點名時重查（叛派、PK 了 → 當作棄權）。
## 名次與獎勵：WULIN 名聲 3000／2000／1200×2／300×4、冠軍「武林盟主」＋盟主令牌（下一屆開打時收回）；
##   SECT 冠軍稱號（晚期官方表）＋名聲 1000、歷練 800；全真 2–7 名天璇…搖光真人。不發神兵（R14）。
## 防刷（D4）：報名 < 4 人＝表演賽（照打不發獎）；同一種比賽每 30 遊戲日最多發一次獎勵；同一身分只能一個角色報名同一場。
## 世界存檔 world.tourney：{ current: { kind: 場次 }, history: [最近 10 場], champions: { kind: char_id },
##   last_reward_day: { kind: day }, holders: { kind: { char_id: 稱號 } }, cal_done: { kind: cycle }, seq }

const WORLD_KEY := "tourney"
const EXT_KEY := "tourney"
const HISTORY_KEEP := 10
const TICK_REAL_S := 0.5
const PHASE_SIGNUP := "SIGNUP"
const PHASE_RUNNING := "RUNNING"
const PHASE_DONE := "DONE"
const SRC_CALENDAR := "CALENDAR"
const SRC_HOST := "HOST"
const E_SIGNUP_OPEN := "ev_tourney_open"
const E_SIGNED := "ev_tourney_signed"
const E_WITHDRAWN := "ev_tourney_withdrawn"
const E_DISQUALIFIED := "ev_tourney_disqualified"   # M3d 審查：開打或點名時已不符合報名條件
const E_START := "ev_tourney_start"
const E_CANCELLED := "ev_tourney_cancelled"
const E_BYE := "ev_tourney_bye"
const E_FORFEIT := "ev_tourney_forfeit"
const E_DONE := "ev_tourney_done"
const E_REWARD := "ev_tourney_reward"
const E_TITLE_LOST := "ev_tourney_title_lost"
const RUMOR_WULIN := "rmr_ev_tourney_champion"
const RUMOR_SECT := "rmr_ev_sect_champion"

var host = null
var _acc := 0.0

func _init(p_host) -> void:
	host = p_host

# ---------------------------------------------------------------- 世界資料
func state() -> Dictionary:
	var w: Dictionary = host.ws.world
	var t: Variant = w.get(WORLD_KEY, null)
	if not (t is Dictionary):
		t = {}
		w[WORLD_KEY] = t
	for k in ["current", "champions", "last_reward_day", "last_reward_unix", "holders", "cal_done"]:
		if not ((t as Dictionary).get(k) is Dictionary):
			t[k] = {}
	if not ((t as Dictionary).get("history") is Array):
		t["history"] = []
	return t

func current() -> Dictionary:
	return state()["current"]

## 現實時間（系統時鐘，秒）；測試可以設 unix_override
var unix_override := -1.0
func unix_now() -> float:
	return unix_override if unix_override >= 0.0 else Time.get_unix_time_from_system()

func reward_cooldown_real_s() -> float:
	return maxf(0.0, float(host.options.get("tourney_reward_cooldown_real_days", TourneyRules.REWARD_COOLDOWN_REAL_DAYS))) 		* TourneyRules.REAL_DAY_S

## 伺服器選項 tourney_enabled，而且規則 later_events 開（M3d 審查第三輪：classic_strict＝2001 沒有門派比武與武林大會）
func enabled() -> bool:
	if host.options.get("tourney_enabled", true) == false:
		return false
	var r: Variant = host.rules
	return not (r is Dictionary) or (r as Dictionary).get("later_events", true) != false

func now_s() -> float:
	return float(host.now_s())

func today() -> int:
	return int(host.clock().get("day", 0))

## 這個資料視圖裡有的門派（1.0A-only 沒有丐幫）
func sect_ids() -> Array:
	var out: Array = []
	for sid in TourneyRules.SECT_SCHEDULE:
		if host.tables.get("sects", {}).has(sid):
			out.append(sid)
	return out

func kind_name(kind: String) -> String:
	var names := {}
	for sid in host.tables.get("sects", {}):
		names[sid] = str(host.tables["sects"][sid].get("name", sid))
	return TourneyRules.kind_name(kind, names)

func _world_span(real_s: float) -> float:
	return float(host.world_span(real_s)) if host.has_method("world_span") else real_s

func _real_span(world_s: float) -> float:
	return float(host.real_span(world_s)) if host.has_method("real_span") else world_s

# ---------------------------------------------------------------- 場次
func _new_event(kind: String, source: String, start_s: float, cycle: int) -> Dictionary:
	var st := state()
	st["seq"] = int(st.get("seq", 0)) + 1
	var ev := { "id": "%s#%d" % [kind, int(st["seq"])], "kind": kind, "source": source, "phase": PHASE_SIGNUP,
		"start_s": start_s, "cycle": cycle, "entrants": [], "rounds": [], "round": 0, "match": {}, "withdrawn": [],
		"exhibition": false, "seed": int(host.rng.randi() & 0x7FFFFFFF), "next_order": 0, "opened_s": now_s() }
	current()[kind] = ev
	var left_s := int(ceil(_real_span(maxf(0.0, start_s - now_s()))))
	var p := { "kind_name": kind_name(kind), "label": kind_name(kind), "start_left_s": left_s,
		"text": "約 %s後開打" % TourneySystem.duration_text(left_s) }
	var sect := TourneyRules.sect_of(kind)
	for s in host.sessions():
		if s.character == null:
			continue
		if sect != "" and str(s.character.sect) != sect:
			continue
		host.tell(s, Protocol.CH_SYSTEM, E_SIGNUP_OPEN, p.duplicate())
	return ev

func event_of(kind: String) -> Dictionary:
	var e: Variant = current().get(kind, null)
	return e if e is Dictionary else {}

func running_event() -> Dictionary:
	for k in current():
		var e: Dictionary = current()[k]
		if str(e.get("phase", "")) == PHASE_RUNNING:
			return e
	return {}

static func _entrant(ev: Dictionary, char_id: String) -> Dictionary:
	for e in ev.get("entrants", []):
		if e is Dictionary and str(e.get("char_id", "")) == char_id:
			return e
	return {}

static func _order_of(ev: Dictionary) -> Dictionary:
	var out := {}
	for e in ev.get("entrants", []):
		if e is Dictionary:
			out[str(e.get("char_id", ""))] = int(e.get("order", 0))
	return out

func _name_of(ev: Dictionary, char_id: String) -> String:
	var e := _entrant(ev, char_id)
	if not e.is_empty():
		return str(e.get("name", ""))
	return str(host.pvp_char_name(char_id)) if char_id != "" else ""

# ---------------------------------------------------------------- intent
## tourney_signup { npc, kind }：tourney_disabled → NPC（not_here／no_service）→ bad_value:kind → tourney_closed／tourney_running
## → tourney_not_eligible（門派比武不是該派弟子）→ tourney_signed（已報名，或同一身分已有角色報名）
func signup(s: Session, npc_id: String, kind_in: String) -> Dictionary:
	if not enabled():
		return GameHost.fail("tourney_disabled")
	var r: String = host.npc_check(s, npc_id, "TOURNEY")
	if r != "":
		return GameHost.fail(r)
	var ch = s.character
	var kind := normalize_kind(kind_in, str(ch.sect))
	if kind == "":
		return GameHost.fail("bad_value:kind")
	var ev := event_of(kind)
	if ev.is_empty():
		return GameHost.fail("tourney_closed")
	if str(ev.get("phase", "")) != PHASE_SIGNUP:
		return GameHost.fail("tourney_running")
	var why := entry_reason(ch, kind)
	if why != "":
		return GameHost.fail(why)
	for e in ev["entrants"]:
		if str(e.get("char_id", "")) == str(ch.id) or str(e.get("identity", "")) == s.identity:
			return GameHost.fail("tourney_signed")
	ev["next_order"] = int(ev.get("next_order", 0)) + 1
	(ev["entrants"] as Array).append({ "char_id": str(ch.id), "name": str(ch.name), "identity": s.identity,
		"sect": str(ch.sect), "order": int(ev["next_order"]) })
	host.tell(s, Protocol.CH_SYSTEM, E_SIGNED, { "kind_name": kind_name(kind), "label": kind_name(kind), "n": (ev["entrants"] as Array).size() })
	_push_state(ev)
	return GameHost.ok({ "kind": kind })

## 報名條件（TourneyRules.entry_reason）："" ＝可以
func entry_reason(ch, kind: String) -> String:
	if ch == null:
		return "tourney_not_eligible"
	var sect := str(ch.sect)
	var ss := str(host.tables.get("sects", {}).get(sect, {}).get("sect_skill", "")) if sect != "" else ""
	return TourneyRules.entry_reason(kind, { "sect": sect, "combat_xp": int(ch.combat_xp), "pk": int(ch.pk_value()),
		"morality": int(ch.morality), "sect_skill": int(ch.skills.level(ss)) if ss != "" else 0 })

## 不再符合報名條件（叛派、PK 了…）→ 當作棄權（通知本人）；回 true＝剛剛取消資格
func _disqualify_if_needed(ev: Dictionary, char_id: String, s: Session) -> bool:
	if s == null or s.character == null or (ev.get("withdrawn", []) as Array).has(char_id):
		return false
	var why := entry_reason(s.character, str(ev.get("kind", "")))
	if why == "":
		return false
	(ev["withdrawn"] as Array).append(char_id)
	host.tell(s, Protocol.CH_SYSTEM, E_DISQUALIFIED, { "kind_name": kind_name(str(ev.get("kind", ""))),
		"label": kind_name(str(ev.get("kind", ""))) })
	return true

## "WULIN"、"SECT"（自己的門派）、"SECT:<sect>"；不合法回 ""
func normalize_kind(kind: String, my_sect: String) -> String:
	if kind == "SECT":
		kind = TourneyRules.sect_kind(my_sect) if my_sect != "" else ""
	if not TourneyRules.valid_kind(kind):
		return ""
	if TourneyRules.is_sect_kind(kind) and not sect_ids().has(TourneyRules.sect_of(kind)):
		return ""
	return kind

## tourney_withdraw {}：報名中 → 取消報名；比賽中 → 棄權（輪到時直接判負）；都沒有 → tourney_closed。
## M3d 審查：intent 旗標 CI（戰鬥中不能送）——比武打到一半要棄權就用「逃」（DUEL 逃走＝判負），不會留下「已棄權卻贏了這場」的狀態
func withdraw(s: Session) -> Dictionary:
	var cid := str(s.character.id)
	var any := false
	for k in current().keys():
		var ev: Dictionary = current()[k]
		var e := _entrant(ev, cid)
		if e.is_empty():
			continue
		if str(ev.get("phase", "")) == PHASE_SIGNUP:
			(ev["entrants"] as Array).erase(e)
		elif not (ev["withdrawn"] as Array).has(cid):
			(ev["withdrawn"] as Array).append(cid)
		any = true
		host.tell(s, Protocol.CH_SYSTEM, E_WITHDRAWN, { "kind_name": kind_name(str(k)), "label": kind_name(str(k)) })
		_push_state(ev)
	return GameHost.ok() if any else GameHost.fail("tourney_closed")

## tourney_host { kind, signup_s }（主機或 admin_identities）：not_admin → tourney_disabled → bad_value:kind → tourney_running
func host_open(s: Session, kind: String, signup_s: int) -> Dictionary:
	if not host.is_admin(s):
		return GameHost.fail("not_admin")
	if not enabled():
		return GameHost.fail("tourney_disabled")
	var k := normalize_kind(kind, str(s.character.sect) if s.character != null else "")
	if k == "":
		return GameHost.fail("bad_value:kind")
	if not event_of(k).is_empty():
		return GameHost.fail("tourney_running")
	var secs := clampi(signup_s if signup_s > 0 else TourneyRules.HOST_SIGNUP_DEFAULT_S,
		TourneyRules.HOST_SIGNUP_MIN_S, TourneyRules.HOST_SIGNUP_MAX_S)
	var ev := _new_event(k, SRC_HOST, now_s() + _world_span(float(secs)), -1)
	_push_state(ev)
	return GameHost.ok({ "kind": k })

## tourney_info {}：送 tourney_state（自己報名的場次 → 武林大會 → 任何進行中 → 最近一場的結果）
func info(s: Session) -> Dictionary:
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_TOURNEY_STATE, state_for(s), true)
	return GameHost.ok()

# ---------------------------------------------------------------- tourney_state
func state_for(s: Session) -> Dictionary:
	var pick := {}
	var cid := str(s.character.id) if s != null and s.character != null else ""
	for k in current():
		if not _entrant(current()[k], cid).is_empty():
			pick = current()[k]
	if pick.is_empty():
		pick = event_of(TourneyRules.KIND_WULIN)
	if pick.is_empty():
		pick = running_event()
	if pick.is_empty():
		for k in current():
			pick = current()[k]
			break
	var p := {}
	if pick.is_empty():
		var hist: Array = state()["history"]
		if not hist.is_empty() and hist[hist.size() - 1] is Dictionary:
			var h: Dictionary = hist[hist.size() - 1]
			p = { "kind": str(h.get("kind", "")), "kind_name": str(h.get("kind_name", "")), "phase": PHASE_DONE,
				"entrants": (h.get("entrants", []) as Array).duplicate(), "bracket": (h.get("bracket", []) as Array).duplicate(true),
				"next_match": {}, "exhibition": bool(h.get("exhibition", false)), "places": (h.get("places", []) as Array).duplicate(true),
				"champion": str(h.get("champion", "")) }
		else:
			p = { "kind": "", "kind_name": "", "phase": PHASE_DONE, "entrants": [], "bracket": [], "next_match": {} }
	else:
		p = payload(pick)
	p["events"] = _events_summary()
	p["upcoming"] = _upcoming_text()
	p["signed"] = []
	for k in current():
		if not _entrant(current()[k], cid).is_empty():
			(p["signed"] as Array).append(str(k))
	# M3d 審查：每一場的報名條件與「我現在能不能報」（介面把報名鈕灰掉並寫出原因）
	var entry := {}
	for k in current():
		entry[str(k)] = { "text": TourneyRules.entry_text(str(k)),
			"why": entry_reason(s.character, str(k)) if s != null and s.character != null else "" }
	p["entry"] = entry
	p["my_sect_kind"] = TourneyRules.sect_kind(str(s.character.sect)) if s != null and s.character != null \
		and str(s.character.sect) != "" and sect_ids().has(str(s.character.sect)) else ""
	p["enabled"] = enabled()
	return p

func payload(ev: Dictionary) -> Dictionary:
	var names: Array = []
	for e in ev.get("entrants", []):
		names.append(str(e.get("name", "")))
	var br: Array = []
	for rnd in ev.get("rounds", []):
		var row: Array = []
		for m in rnd:
			row.append({ "a": _name_of(ev, str(m.get("a", ""))), "b": _name_of(ev, str(m.get("b", ""))),
				"winner": _name_of(ev, str(m.get("winner", ""))) if bool(m.get("done", false)) else "",
				"done": bool(m.get("done", false)), "how": str(m.get("how", "")) })
		br.append(row)
	var nm := {}
	var m: Dictionary = ev.get("match", {})
	if not m.is_empty():
		nm = { "a": _name_of(ev, str(m.get("a", ""))), "b": _name_of(ev, str(m.get("b", ""))), "calls": int(m.get("calls", 0)),
			"fighting": int(m.get("bid", 0)) != 0 }
	return { "kind": str(ev.get("kind", "")), "kind_name": kind_name(str(ev.get("kind", ""))), "phase": str(ev.get("phase", "")),
		"entrants": names, "bracket": br, "next_match": nm, "exhibition": bool(ev.get("exhibition", false)),
		"source": str(ev.get("source", "")),
		"start_left_s": int(ceil(_real_span(maxf(0.0, float(ev.get("start_s", 0.0)) - now_s())))) }

func _events_summary() -> Array:
	var out: Array = []
	var keys: Array = current().keys()
	keys.sort()
	for k in keys:
		var ev: Dictionary = current()[k]
		out.append({ "kind": str(k), "kind_name": kind_name(str(k)), "phase": str(ev.get("phase", "")),
			"n": (ev.get("entrants", []) as Array).size(),
			"start_left_s": int(ceil(_real_span(maxf(0.0, float(ev.get("start_s", 0.0)) - now_s())))) })
	return out

## 下幾場的日曆（文字）：「第 15 日午時（還有 5 日）」——M3d 審查：跟時鐘列一樣用「第 N 日」，不用月日
func _upcoming_text() -> Array:
	var out: Array = []
	var day := today()
	for u in TourneyRules.upcoming(day, sect_ids()):
		if out.size() >= 4:
			break
		out.append({ "kind": str(u.kind), "kind_name": kind_name(str(u.kind)),
			"start_day": int(u.start_day),
			"text": TourneySystem.calendar_text(int(u.start_day), int(u.shichen), day) })
	return out

static func calendar_text(start_day: int, shichen: int, today_day: int) -> String:
	var left := start_day - today_day
	var tail := "（今天）" if left <= 0 else "（還有 %d 日）" % left
	return "第 %d 日%s時%s" % [start_day, WorldClock.SHICHEN[clampi(shichen, 0, 11)], tail]

## 報名者（在線）與擂臺、休息區的人
func _push_state(ev: Dictionary) -> void:
	var sent := {}
	var p := payload(ev)
	for e in ev.get("entrants", []):
		var s: Session = host.session_for_char(str(e.get("char_id", "")))
		if s != null and not sent.has(s.peer_id):
			sent[s.peer_id] = true
			var q := p.duplicate(true)
			q["events"] = _events_summary()
			host.tell(s, Protocol.CH_SYSTEM, Protocol.E_TOURNEY_STATE, q, true)
	for s in host.sessions():
		if s.character == null or sent.has(s.peer_id) or not (s.room_id() in TourneyRules.ARENA_ROOMS):
			continue
		sent[s.peer_id] = true
		var q2 := p.duplicate(true)
		q2["events"] = _events_summary()
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_TOURNEY_STATE, q2, true)

func _arena_event(key: String, p: Dictionary, also: Array = []) -> void:
	var sent := {}
	for s in host.sessions():
		if s.character == null:
			continue
		if s.room_id() in TourneyRules.ARENA_ROOMS or also.has(str(s.character.id)):
			if not sent.has(s.peer_id):
				sent[s.peer_id] = true
				host.tell(s, Protocol.CH_SCENE, key, p.duplicate())

# ---------------------------------------------------------------- 排程（GameHost.m3d_tick）
func tick(dt: float) -> void:
	_acc += _real_span(dt)
	if _acc < TICK_REAL_S:
		return
	_acc = 0.0
	step()

## 一次推進：日曆開報名 → 到點開打（同一時間一場）→ 進行中的場次（點名、開戰、晉級）
func step() -> void:
	if enabled():
		_calendar()
	if running_event().is_empty():
		var due: Array = []
		for k in current():
			var ev: Dictionary = current()[k]
			if str(ev.get("phase", "")) == PHASE_SIGNUP and now_s() >= float(ev.get("start_s", 0.0)):
				due.append(ev)
		due.sort_custom(func(a, b): return float(a.start_s) < float(b.start_s))
		for ev in due:
			if _start(ev):
				break
	var run := running_event()
	if not run.is_empty():
		_run(run)

func _calendar() -> void:
	if not host.tables.get("npcs", {}).has(TourneyRules.CLERK_NPC):
		return   # 沒有報名員（比武場還沒建、資料視圖沒有）→ 不排
	var c: Dictionary = host.clock()
	var st := state()
	for t in TourneyRules.calendar_open(int(c.get("day", 1)), int(c.get("shichen_idx", 0)), sect_ids()):
		var kind := str(t.kind)
		if current().has(kind) or int(st["cal_done"].get(kind, -999)) == int(t.cycle):
			continue
		st["cal_done"][kind] = int(t.cycle)
		_new_event(kind, SRC_CALENDAR, TourneyRules.world_s_at(int(t.start_day), int(t.shichen), float(host.day_s())), int(t.cycle))

## 開打：人數不足取消；決定表演賽；收回上一屆的稱號與令牌；排第一輪。回 true＝開打了
func _start(ev: Dictionary) -> bool:
	var kind := str(ev.get("kind", ""))
	var ids: Array = []
	for e in ev["entrants"]:
		ids.append(str(e.get("char_id", "")))
	if ids.size() < TourneyRules.MIN_ENTRANTS:
		for cid in ids:
			var s: Session = host.session_for_char(cid)
			if s != null:
				host.tell(s, Protocol.CH_SYSTEM, E_CANCELLED, { "kind_name": kind_name(kind), "label": kind_name(kind) })
		_arena_event(E_CANCELLED, { "kind_name": kind_name(kind), "label": kind_name(kind) })
		current().erase(kind)
		return false
	# M3d 審查：開打時重查報名條件（報名後叛派、PK 了）→ 照樣排進對戰表、輪到時當作棄權
	for cid in ids:
		_disqualify_if_needed(ev, str(cid), host.session_for_char(str(cid)))
	var st := state()
	# M3d 審查第三輪：開打時就被取消資格的人不算報名人數（4 人報名、2 人叛派 → 只有 2 人真的打 → 表演賽）
	var real_n := 0
	for cid in ids:
		if not (ev.get("withdrawn", []) as Array).has(str(cid)):
			real_n += 1
	ev["exhibition"] = not TourneyRules.rewarded(real_n, today(), int(st["last_reward_day"].get(kind, -1)),
		unix_now(), float(st["last_reward_unix"].get(kind, -1.0)), reward_cooldown_real_s())
	# M3d 審查第三輪：表演賽不收回上一屆的稱號與令牌（不然兩個人打一場表演賽就能讓盟主下台）
	if not bool(ev["exhibition"]):
		_revoke(kind)
	var champ := str(st["champions"].get(kind, ""))
	var first := TourneyRules.bracket(ids, champ, int(ev.get("seed", 1)))
	var rnd: Array = []
	for pair in first:
		rnd.append({ "a": str(pair[0]), "b": str(pair[1]), "winner": "", "done": false, "how": "" })
	ev["rounds"] = [rnd]
	ev["round"] = 0
	ev["match"] = {}
	ev["phase"] = PHASE_RUNNING
	var p := { "kind_name": kind_name(kind), "label": kind_name(kind), "n": ids.size(), "exhibition": bool(ev["exhibition"]) }
	_arena_event(E_START, p, ids)
	_push_state(ev)
	return true

## 進行中：輪空自動晉級 → 下一場點名 → 開戰；一輪打完排下一輪；決賽打完發獎
func _run(ev: Dictionary) -> void:
	for guard in 64:
		var m: Dictionary = ev.get("match", {})
		if not m.is_empty():
			_tick_match(ev, m)
			return
		var rounds: Array = ev["rounds"]
		var rnd: Array = rounds[int(ev["round"])]
		var next_i := -1
		for i in rnd.size():
			var mm: Dictionary = rnd[i]
			if bool(mm.get("done", false)):
				continue
			var a := str(mm.get("a", ""))
			var b := str(mm.get("b", ""))
			if a == "" or b == "":
				_decide(ev, i, b if a == "" else a, "BYE")
				continue
			next_i = i
			break
		if next_i >= 0:
			ev["match"] = { "i": next_i, "a": str(rnd[next_i]["a"]), "b": str(rnd[next_i]["b"]), "calls": 0,
				"next_call_s": now_s(), "bid": 0 }
			_push_state(ev)
			continue
		# 這一輪打完
		var winners: Array = []
		for mm in rnd:
			winners.append(str(mm.get("winner", "")))
		if rnd.size() <= 1:
			_finish(ev)
			return
		var nr: Array = []
		for pair in TourneyRules.next_round(winners):
			nr.append({ "a": str(pair[0]), "b": str(pair[1]), "winner": "", "done": false, "how": "" })
		rounds.append(nr)
		ev["round"] = int(ev["round"]) + 1

## 選手在場：在線、在擂臺或休息區、閒置、不在牢裡、沒有棄權、仍符合報名條件
func present(ev: Dictionary, char_id: String) -> Session:
	if char_id == "" or (ev.get("withdrawn", []) as Array).has(char_id):
		return null
	var s: Session = host.session_for_char(char_id)
	if s == null or s.character == null or s.battle_id != 0 or s.character.is_jailed():
		return null
	if _disqualify_if_needed(ev, char_id, s):
		return null   # M3d 審查：叛派、PK 了 → 不能再上場（_tick_match 看到 withdrawn 直接判負）
	if not (s.room_id() in TourneyRules.ARENA_ROOMS):
		return null
	return s

func _tick_match(ev: Dictionary, m: Dictionary) -> void:
	if int(m.get("bid", 0)) != 0:
		var act: Dictionary = host.battles.active.get(int(m["bid"]), {})
		# M3d 審查：bid 存在世界檔裡，當機重開後 BattleSystem 的編號從 1 重來 → 要確認是這一場比武的戰鬥，不是同號的別場
		if not act.is_empty() and str(act.get("opts", {}).get("tourney", "")) == str(ev.get("id", "")):
			return   # 打著
		m["bid"] = 0   # 戰鬥不見了（中止）：重新點名
		m["calls"] = 0
		m["next_call_s"] = now_s()
	var a := str(m["a"])
	var b := str(m["b"])
	var sa := present(ev, a)
	var sb := present(ev, b)
	if sa != null and sb != null:
		_fight(ev, m, sa, sb)
		return
	# 棄權的人不必等點名
	var wd: Array = ev.get("withdrawn", [])
	if wd.has(a) or wd.has(b):
		_forfeit(ev, m, sa != null, sb != null)
		return
	if now_s() < float(m.get("next_call_s", 0.0)):
		return
	if int(m.get("calls", 0)) >= TourneyRules.CALL_MAX:
		_forfeit(ev, m, sa != null, sb != null)
		return
	m["calls"] = int(m.get("calls", 0)) + 1
	m["next_call_s"] = now_s() + _world_span(TourneyRules.CALL_INTERVAL_REAL_S)
	for pair in [[a, sa], [b, sb]]:
		var p := { "name": _name_of(ev, str(pair[0])), "n": int(m["calls"]) }
		_arena_event(Protocol.E_EV_TOURNEY_CALL, p, [str(pair[0])])
	_push_state(ev)

## 點名 3 次不到：不在場的判負；兩人都不在 → 都判負（勝者 ""）
func _forfeit(ev: Dictionary, m: Dictionary, a_here: bool, b_here: bool) -> void:
	var wd: Array = ev.get("withdrawn", [])
	a_here = a_here and not wd.has(str(m["a"]))
	b_here = b_here and not wd.has(str(m["b"]))
	var w := ""
	if a_here and not b_here:
		w = str(m["a"])
	elif b_here and not a_here:
		w = str(m["b"])
	for x in [str(m["a"]), str(m["b"])]:
		if x != w:
			_arena_event(E_FORFEIT, { "name": _name_of(ev, x) }, [x])
	_decide(ev, int(m["i"]), w, "FORFEIT")
	ev["match"] = {}
	_arena_event(Protocol.E_EV_DUEL_RESULT, { "a": _name_of(ev, str(m["a"])), "b": _name_of(ev, str(m["b"])),
		"winner": _name_of(ev, w), "how": "FORFEIT", "how_text": how_text("FORFEIT", w),
		"atk_name": _name_of(ev, str(m["a"])), "def_name": _name_of(ev, str(m["b"])), "who": _name_of(ev, w) if w != "" else "無人",
		"text": how_text("FORFEIT", w) }, [str(m["a"]), str(m["b"])])
	_push_state(ev)

func _fight(ev: Dictionary, m: Dictionary, sa: Session, sb: Session) -> void:
	for s in [sa, sb]:
		if s.room_id() != TourneyRules.ARENA_ROOM and host.index.has_room(TourneyRules.ARENA_ROOM):
			host.regions.teleport(s, TourneyRules.ARENA_ROOM, false)
	var order := _order_of(ev)
	var bid := int(host.battles.start_pvp(sa, sb, "DUEL", { "duel_limit_s": TourneyRules.DUEL_LIMIT_S,
		"tourney": str(ev["id"]), "order": { str(m["a"]): int(order.get(str(m["a"]), 0)), str(m["b"]): int(order.get(str(m["b"]), 0)) } }))
	if bid == 0:
		return   # 有人忙：下一次再試
	m["bid"] = bid
	_push_state(ev)

## 秒數的中文（開放報名的通知）
static func duration_text(sec: int) -> String:
	if sec >= 3600:
		return "%d 小時 %d 分" % [sec / 3600, (sec % 3600) / 60]
	if sec >= 60:
		return "%d 分" % (sec / 60)
	return "%d 秒" % sec

## 結果說明（ev_duel_result 的 how_text）
static func how_text(how: String, winner: String) -> String:
	if winner == "":
		return "兩人都沒到場，雙雙判負"
	match how:
		"KO":
			return "擊倒對手"
		"JUDGE":
			return "時間到，裁判判定"
		"FORFEIT":
			return "對手棄權"
	return how

func _decide(ev: Dictionary, i: int, winner: String, how: String) -> void:
	var rnd: Array = ev["rounds"][int(ev["round"])]
	var mm: Dictionary = rnd[i]
	mm["winner"] = winner
	mm["done"] = true
	mm["how"] = how
	if how == "BYE" and winner != "":
		var s: Session = host.session_for_char(winner)
		if s != null:
			host.tell(s, Protocol.CH_SYSTEM, E_BYE, { "kind_name": kind_name(str(ev["kind"])), "label": kind_name(str(ev["kind"])) })

## BattleSystem._finish（DUEL）：記勝負、轉播結果、晉級
func on_duel_end(entry: Dictionary, out: Dictionary) -> void:
	var eid := str(entry.get("opts", {}).get("tourney", ""))
	if eid == "":
		return
	var ev := {}
	for k in current():
		if str(current()[k].get("id", "")) == eid:
			ev = current()[k]
	if ev.is_empty():
		return
	var m: Dictionary = ev.get("match", {})
	var bid := int((entry["battle"] as Battle).id)
	if m.is_empty() or int(m.get("bid", 0)) != bid:
		return
	var result := str(out.get("result", ""))
	if result == "ABORTED":
		m["bid"] = 0
		m["calls"] = 0
		m["next_call_s"] = now_s()
		return   # 主機關閉或超過 30 分鐘：重打
	var ws := int(out.get("winner_side", -1))
	var w := ""
	if ws == 0:
		w = str(m["a"])
	elif ws == 1:
		w = str(m["b"])
	var how := str(out.get("duel_how", "KO"))
	_decide(ev, int(m["i"]), w, how)
	ev["match"] = {}
	_arena_event(Protocol.E_EV_DUEL_RESULT, { "a": _name_of(ev, str(m["a"])), "b": _name_of(ev, str(m["b"])),
		"winner": _name_of(ev, w), "how": how, "how_text": how_text(how, w),
		"atk_name": _name_of(ev, str(m["a"])), "def_name": _name_of(ev, str(m["b"])), "who": _name_of(ev, w) if w != "" else "無人",
		"text": how_text(how, w) }, [str(m["a"]), str(m["b"])])
	_push_state(ev)

# ---------------------------------------------------------------- 名次、獎勵、稱號
func _finish(ev: Dictionary) -> void:
	var kind := str(ev["kind"])
	var st := state()
	var order := _order_of(ev)
	var pl := TourneyRules.places(ev["rounds"], order)
	var exhibition := bool(ev.get("exhibition", false))
	var champion := ""
	if not pl.is_empty() and int(pl[0].place) == 1:
		champion = str(pl[0].id)
	var place_rows: Array = []
	# M3d 審查第三輪：名聲與稱號照「名次」查，不照名單位置——決賽兩人都沒到（沒有冠軍）時，亞軍不會拿到冠軍那格
	var slots := TourneyRules.rank_slots(pl)
	var fame_slots := TourneyRules.rank_slots(pl, true)
	for i in pl.size():
		var cid := str(pl[i].id)
		var slot := int(slots[i])
		place_rows.append({ "name": _name_of(ev, cid), "place": int(pl[i].place) })
		if exhibition:
			continue
		var rw := {}
		var title := ""
		if kind == TourneyRules.KIND_WULIN:
			var f := TourneyRules.wulin_fame(int(fame_slots[i]))
			if f > 0:
				rw["fame"] = f
		elif slot == 0:
			rw = { "fame": TourneyRules.SECT_CHAMPION_FAME, "lilian": TourneyRules.SECT_CHAMPION_LILIAN }
		title = TourneyRules.title_for(kind, slot)
		_award(ev, cid, rw, title)
	# M3d 審查第三輪：表演賽的冠軍不改種子（champions）；正式比賽不論有沒有冠軍都開始發獎冷卻
	if champion != "" and not exhibition:
		st["champions"][kind] = champion
	if not exhibition:
		st["last_reward_day"][kind] = today()
		st["last_reward_unix"][kind] = unix_now()
	if not exhibition and champion != "":
		var p := { "name": _name_of(ev, champion), "kind_name": kind_name(kind), "label": kind_name(kind),
			"title": TourneyRules.title_for(kind, 0), "_force": true }
		var key := RUMOR_WULIN if kind == TourneyRules.KIND_WULIN else RUMOR_SECT
		if not bool(host.m2_call(host.get("rumor"), "post", ["DEED", key, p, "WORLD", ""], false)):
			p.erase("_force")
			host.ws.broadcast_event(Protocol.CH_JIANGHU, key, p)
	ev["phase"] = PHASE_DONE
	var names: Array = []
	for e in ev["entrants"]:
		names.append(str(e.get("name", "")))
	var pay := payload(ev)
	var hist: Array = st["history"]
	hist.append({ "id": str(ev["id"]), "kind": kind, "kind_name": kind_name(kind), "day": today(), "exhibition": exhibition,
		"champion": _name_of(ev, champion), "places": place_rows, "entrants": names, "bracket": pay["bracket"] })
	while hist.size() > HISTORY_KEEP:
		hist.pop_front()
	var ids: Array = []
	for e in ev["entrants"]:
		ids.append(str(e.get("char_id", "")))
	_arena_event(E_DONE, { "kind_name": kind_name(kind), "label": kind_name(kind), "champion": _name_of(ev, champion),
		"name": _name_of(ev, champion) if champion != "" else "無人", "exhibition": exhibition }, ids)
	_push_state(ev)
	current().erase(kind)

## 發名聲、歷練、稱號（盟主另給令牌）；不在線的角色從角色檔改、存檔
func _award(ev: Dictionary, char_id: String, rw: Dictionary, title: String) -> void:
	if rw.is_empty() and title == "":
		return
	var e := _entrant(ev, char_id)
	var s: Session = host.session_for_char(char_id)
	var ch = s.character if s != null else null
	if ch == null and not e.is_empty() and host.char_store != null:
		ch = host.char_store.load_char(str(e.get("identity", "")), char_id)
	if ch == null:
		return
	var kind := str(ev["kind"])
	var got: Dictionary = ch.apply_rewards(rw, host.rules) if not rw.is_empty() else {}
	if title != "":
		var holders: Dictionary = state()["holders"].get_or_add(kind, {})
		holders[char_id] = title
		var t := _ext(ch)
		var list: Array = []
		for x in t.get("titles", []):
			if x is Dictionary and str(x.get("kind", "")) != kind:
				list.append(x)
		list.append({ "kind": kind, "title": title, "until_s": -1.0 })
		t["titles"] = list
		if kind == TourneyRules.KIND_WULIN and int(ch.inventory.count(TourneyRules.TOKEN_ITEM)) == 0 \
				and host.tables.get("items", {}).has(TourneyRules.TOKEN_ITEM):
			host.give_item(ch, TourneyRules.TOKEN_ITEM, 1)
			if s != null:
				host.item_gain_event(s, TourneyRules.TOKEN_ITEM, 1)
	if s != null:
		host.tell(s, Protocol.CH_SYSTEM, E_REWARD, { "kind_name": kind_name(kind), "label": kind_name(kind), "amount": int(got.get("lilian", 0)), "fame": int(got.get("fame", 0)),
			"lilian": int(got.get("lilian", 0)), "title": title,
			"title_text": ("獲得稱號「%s」。" % title) if title != "" else "",
			"text": ("獲得稱號「%s」。" % title) if title != "" else "" })
		s.sheet_dirty = true
		host.regions.mark_room_dirty(s.room_id())
	host.save_char(ch)

static func _ext(ch) -> Dictionary:
	var t: Variant = ch.ext.get(EXT_KEY, null)
	if not (t is Dictionary):
		t = {}
		ch.ext[EXT_KEY] = t
	if not ((t as Dictionary).get("titles") is Array):
		t["titles"] = []
	return t

## 下一屆同種比賽開打：上一屆的稱號全部收回（盟主令牌：在線的立刻收回，不在線的登入時收回）
func _revoke(kind: String) -> void:
	var holders: Dictionary = state()["holders"]
	var old: Variant = holders.get(kind, {})
	holders[kind] = {}
	if not (old is Dictionary):
		return
	for cid in old:
		var s: Session = host.session_for_char(str(cid))
		if s != null and s.character != null:
			_cleanup(s)
			host.tell(s, Protocol.CH_SYSTEM, E_TITLE_LOST, { "title": str(old[cid]) })

## 稱號是否仍有效：持有表裡有、門派比武的稱號還要仍是該派弟子（叛派收回）
func title_valid(ch, kind: String, title: String) -> bool:
	var h: Variant = state()["holders"].get(kind, {})
	if not (h is Dictionary) or str((h as Dictionary).get(str(ch.id), "")) != title:
		return false
	var sect := TourneyRules.sect_of(kind)
	return sect == "" or str(ch.sect) == sect

func titles_of(ch) -> Array:
	var out: Array = []
	if ch == null:
		return out
	var t: Variant = ch.ext.get(EXT_KEY, null)
	if not (t is Dictionary):
		return out
	for x in t.get("titles", []):
		if x is Dictionary and title_valid(ch, str(x.get("kind", "")), str(x.get("title", ""))):
			out.append(str(x.get("title", "")))
	return out

## 失效的稱號從 ext 拿掉；不是盟主卻帶著盟主令牌 → 收回
func _cleanup(s: Session) -> void:
	var ch = s.character
	var t: Variant = ch.ext.get(EXT_KEY, null)
	if t is Dictionary and (t as Dictionary).get("titles") is Array:
		var keep: Array = []
		for x in t["titles"]:
			if x is Dictionary and title_valid(ch, str(x.get("kind", "")), str(x.get("title", ""))):
				keep.append(x)
		t["titles"] = keep
	var is_lord := titles_of(ch).has(TourneyRules.WULIN_TITLE)
	var n := int(ch.inventory.count(TourneyRules.TOKEN_ITEM))
	if n > 0 and not is_lord:
		for it in ch.inventory.items.duplicate():
			if str(it.get("id", "")) == TourneyRules.TOKEN_ITEM:
				ch.inventory.remove(str(it.get("uid", "")), int(it.get("n", 1)))
		host.item_lost_event(s, TourneyRules.TOKEN_ITEM, n)
	s.sheet_dirty = true

# ---------------------------------------------------------------- GameHost 分派
func on_login(s: Session) -> void:
	if s == null or s.character == null:
		return
	_cleanup(s)
	for k in current():
		if not _entrant(current()[k], str(s.character.id)).is_empty():
			host.tell(s, Protocol.CH_SYSTEM, Protocol.E_TOURNEY_STATE, state_for(s), true)
			break

func sheet_fields(s: Session) -> Dictionary:
	if s == null or s.character == null:
		return {}
	return { "titles": titles_of(s.character) }

## 房間玩家列：盟主（發光）與門派稱號
func player_tags(_viewer: Session, o: Session) -> Dictionary:
	if o == null or o.character == null:
		return {}
	var tags: Array = []
	for t in titles_of(o.character):
		tags.append(TourneyRules.WULIN_TAG if t == TourneyRules.WULIN_TITLE else str(t))
	return { "tags": tags } if not tags.is_empty() else {}

func on_char_deleted(char_id: String) -> void:
	for k in current():
		var ev: Dictionary = current()[k]
		var e := _entrant(ev, char_id)
		if e.is_empty():
			continue
		if str(ev.get("phase", "")) == PHASE_SIGNUP:
			(ev["entrants"] as Array).erase(e)
		elif not (ev["withdrawn"] as Array).has(char_id):
			(ev["withdrawn"] as Array).append(char_id)
	for k in state()["holders"]:
		var h: Variant = state()["holders"][k]
		if h is Dictionary:
			(h as Dictionary).erase(char_id)
