class_name AmbientSystem
extends RefCounted
## NPC 依時辰的閒聊、環境句、對善惡／名聲的反應（STORY_PLAN §5.3、§5.4）。
## - talk_key：`talk_<npc>@<時段>` 模板存在就用它（DAWN 卯辰、DAY 巳午未申、DUSK 酉、NIGHT 戌亥子丑寅）。
## - greet_key：data/reactions.json 的 greet（npc_reactions 不是 OFF 時）。
## - price_pct／refuse_reason：只有 npc_reactions == "FULL"；永不影響 RESPAWN、TRAVEL、QUEST、TEACH、JOIN、JAIL、GUIDE、
##   守衛（GUARD）與查小鏞（D15）。價格與拒絕【設計提案・非原作】（研究：1.0 查無依善惡改價的記載）。
## - 環境句：data/ambient.json；玩家進房 25% 機率送一則（同一玩家 90 真實秒冷卻），只送本人（CH_SCENE）。
##   原作沒有自動閒聊的記載 →【設計提案・非原作】，伺服器選項 ambient_lines。
##
## 主機鉤子（WP-ENGINE 以 host.m2_call(host.ambient, …) 呼叫；全部可缺）：
##   talk_key(s, npc_id)、greet_key(s, npc_id)、price_pct(s, npc_id, service)、refuse_reason(s, npc_id, service)、
##   on_enter_room(s)、tick(dt)（輪詢進房，補上沒接 on_enter_room 的情況）。
## STORY_PLAN 缺漏：K3 的 `_init(p_host: GameHost)` 不加型別（同 PkSystem），讓單元測試可傳入假主機。
## STORY_PLAN 缺漏：§5.4 refuse_reason 回傳 String（"" = 不拒）；這裡回傳要送的拒絕模板 id（例 rx_refuse_evil），
##   呼叫端回原因碼 npc_refuse 並以 CH_SCENE 送該模板。

const PERIOD_DAWN := "DAWN"
const PERIOD_DAY := "DAY"
const PERIOD_DUSK := "DUSK"
const PERIOD_NIGHT := "NIGHT"
const PERIOD_OF := {
	"卯": PERIOD_DAWN, "辰": PERIOD_DAWN,
	"巳": PERIOD_DAY, "午": PERIOD_DAY, "未": PERIOD_DAY, "申": PERIOD_DAY,
	"酉": PERIOD_DUSK,
	"戌": PERIOD_NIGHT, "亥": PERIOD_NIGHT, "子": PERIOD_NIGHT, "丑": PERIOD_NIGHT, "寅": PERIOD_NIGHT,
}
const MODE_OFF := "OFF"
const MODE_FLAVOR := "FLAVOR"
const MODE_FULL := "FULL"
const MODES := [MODE_OFF, MODE_FLAVOR, MODE_FULL]
## 永不受價格／拒絕影響（§5.4）
const NEVER_SERVICES := ["RESPAWN", "TRAVEL", "QUEST", "TEACH", "JOIN", "JAIL", "GUIDE"]
const NEVER_KINDS := ["GUARD"]
const CHA_NAME := "查小鏞"
const PRICE_MIN_PCT := 10
const PRICE_MAX_PCT := 1000
const LINE_CHANCE_PCT := 25
const LINE_COOLDOWN_REAL_S := 90.0
## 審查修正（敘事）：在同一個房間站久了也會聽到閒話（原本只有進房才擲）【設計提案・非原作】
const IDLE_LINE_REAL_S := 180.0
const IDLE_LINE_CHANCE_PCT := 50
## 審查修正：列帶 "first_visit": true → 這個角色第一次符合條件時一定送（不擲骰、不看冷卻），記在 ch.ext.ambient.once
const ONCE_KEY := "once"
## 審查修正（第四輪）：同一句環境句對同一位玩家 LINE_NO_REPEAT_REAL_S 真實秒內不再出現（荒野夜裡的狼嚎一晚聽七次）；
## 那一區沒有別句可說就不說【設計提案・非原作】
const LINE_NO_REPEAT_REAL_S := 900.0

var host
var _seen_room: Dictionary = {}     # peer -> 上次看到的房間（輪詢進房）
var _next_line_s: Dictionary = {}   # peer -> 下一次可以送環境句的世界時間（不存檔）
var _idle_rng := RandomNumberGenerator.new()
var _idle_line_s: Dictionary = {}   # peer -> 站著不動時下一次擲閒話的世界時間（不存檔）
var _heard: Dictionary = {}         # peer -> { 環境句 id: 送出的世界時間 }（不存檔）

func _init(p_host) -> void:
	host = p_host

# ======================================================================== 選項

func reactions_mode() -> String:
	var m := str(host.options.get("npc_reactions", MODE_FULL))
	return m if m in MODES else MODE_FULL

func lines_enabled() -> bool:
	return host.options.get("ambient_lines", true) != false

static func period_of(shichen: String) -> String:
	return str(PERIOD_OF.get(shichen, PERIOD_DAY))

func period() -> String:
	return period_of(str(host.clock().get("shichen_name", "")))

# ======================================================================== 交談（§5.3）

## NpcSystem.talk 用：
## 1. data/ambient.json 的交談列（有 "talk" 欄位；審查修正：NPC 依任務進度與結局換話）：
##    { id, npc, talk: 模板 id, requires: [條件…], periods: [], priority }，priority 大的先，第一條成立的就用；
## 2. 否則 `talk_<npc>@<時段>` 存在就回它，否則回 NPC 的 talk 欄位（或 talk_<npc>）
func talk_key(s: Session, npc_id: String) -> String:
	var rule := talk_rule(s, npc_id)
	if rule != "":
		return rule
	var row := _npc(npc_id)
	var base := str(row.get("talk", ""))
	if base == "":
		base = "talk_" + npc_id
	var variant := "%s@%s" % [base, period()]
	return variant if _has_template(variant) else base

## 交談列（ambient.json 有 talk 欄位的列）：這位玩家此刻第一條成立的模板 id；沒有回 ""
func talk_rule(s: Session, npc_id: String) -> String:
	if s == null or s.character == null:
		return ""
	var t: Variant = host.tables.get("ambient", {})
	if not (t is Dictionary):
		return ""
	var rows: Array = []
	for rid in t:
		var r: Variant = t[rid]
		if r is Dictionary and str(r.get("npc", "")) == npc_id and str(r.get("talk", "")) != "":
			rows.append(r)
	if rows.is_empty():
		return ""
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var px := int(x.get("priority", 0))
		var py := int(y.get("priority", 0))
		if px != py:
			return px > py
		return str(x.get("id", "")) < str(y.get("id", "")))
	var per := period()
	for r in rows:
		var key := str(r["talk"])
		if not _has_template(key):
			continue
		var ps: Variant = r.get("periods", [])
		if ps is Array and not (ps as Array).is_empty() and not (per in ps):
			continue
		var req: Variant = r.get("requires", [])
		if reqs_ok(req if req is Array else [], s):
			return key
	return ""

## 招呼語（§5.4）：第一條符合的 reactions 列的 greet；npc_reactions == OFF 時 ""
func greet_key(s: Session, npc_id: String) -> String:
	if s == null or s.character == null or reactions_mode() == MODE_OFF:
		return ""
	var nrow := _npc(npc_id)
	if nrow.is_empty():
		return ""
	for r in sorted_rows():
		var g := str(r.get("greet", ""))
		if g != "" and _row_matches(r, npc_id, nrow, "", s) and _has_template(g):
			return g
	return ""

## NpcSystem.talk 用（審查修正）：同一位 NPC 對同一個角色，同一種態度只招呼一次；
## 態度改變（符合的 reactions 列換了）才再招呼。記在 ch.ext.ambient.greeted（存檔）。
func talk_greet(s: Session, npc_id: String) -> String:
	if s == null or s.character == null or reactions_mode() == MODE_OFF:
		return ""
	var nrow := _npc(npc_id)
	if nrow.is_empty():
		return ""
	var hit: Dictionary = {}
	for r in sorted_rows():
		var g := str(r.get("greet", ""))
		if g != "" and _row_matches(r, npc_id, nrow, "", s) and _has_template(g):
			hit = r
			break
	var greeted := _greeted(s.character)
	if hit.is_empty():
		greeted.erase(npc_id)
		return ""
	var rid := str(hit.get("id", ""))
	if str(greeted.get(npc_id, "")) == rid:
		return ""
	greeted[npc_id] = rid
	return str(hit["greet"])

func _greeted(ch) -> Dictionary:
	var e: Variant = ch.get("ext")
	if not (e is Dictionary):
		return {}
	var amb: Variant = e.get("ambient")
	if not (amb is Dictionary):
		amb = {}
		e["ambient"] = amb
	var g: Variant = amb.get("greeted")
	if not (g is Dictionary):
		g = {}
		amb["greeted"] = g
	return g

## 價格百分比（100 = 原價）：所有符合列的 price_pct 增減相加（例：惡名 +20、名聲 −5 → 115）
func price_pct(s: Session, npc_id: String, service: String) -> int:
	if s == null or s.character == null or reactions_mode() != MODE_FULL:
		return 100
	var nrow := _npc(npc_id)
	if nrow.is_empty() or never_affected(npc_id, nrow, service):
		return 100
	var pct := 100
	for r in sorted_rows():
		if not r.has("price_pct") or not _row_matches(r, npc_id, nrow, service, s):
			continue
		pct += int(r["price_pct"]) - 100
	return clampi(pct, PRICE_MIN_PCT, PRICE_MAX_PCT)

## 拒絕服務的模板 id（"" = 不拒）：第一條符合且有 refuse 的列
func refuse_reason(s: Session, npc_id: String, service: String) -> String:
	if s == null or s.character == null or reactions_mode() != MODE_FULL:
		return ""
	var nrow := _npc(npc_id)
	if nrow.is_empty() or never_affected(npc_id, nrow, service):
		return ""
	for r in sorted_rows():
		var rf := str(r.get("refuse", ""))
		if rf != "" and _row_matches(r, npc_id, nrow, service, s):
			return rf
	return ""

## 守衛、查小鏞、師父、驛站…（D15、§5.4）
static func never_affected(npc_id: String, nrow: Dictionary, service: String) -> bool:
	if service in NEVER_SERVICES:
		return true
	if str(nrow.get("kind", "")) in NEVER_KINDS or "GUARD" in nrow.get("services", []):
		return true
	return str(nrow.get("name", "")) == CHA_NAME or (npc_id.ends_with("_cha") and "RESPAWN" in nrow.get("services", []))

## reactions 列依 priority（大的先，預設 0）再依 id 排序
func sorted_rows() -> Array:
	var t: Variant = host.tables.get("reactions", {})
	var out: Array = []
	if t is Dictionary:
		for rid in t:
			if t[rid] is Dictionary:
				out.append(t[rid])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a.get("priority", 0))
		var pb := int(b.get("priority", 0))
		if pa != pb:
			return pa > pb
		return str(a.get("id", "")) < str(b.get("id", "")))
	return out

## 列欄位：npcs（指定 NPC，選填）、exclude_npcs、npc_kinds、npc_alignment、services、when（玩家條件）。
## service == ""（招呼語）：列有 services 時，NPC 至少提供其中一項才算。
func _row_matches(r: Dictionary, npc_id: String, nrow: Dictionary, service: String, s: Session) -> bool:
	var only: Variant = r.get("npcs", [])
	if only is Array and not (only as Array).is_empty() and not (npc_id in only):
		return false
	var ex: Variant = r.get("exclude_npcs", [])
	if ex is Array and npc_id in ex:
		return false
	var kinds: Variant = r.get("npc_kinds", [])
	if kinds is Array and not (kinds as Array).is_empty() and not (str(nrow.get("kind", "")) in kinds):
		return false
	var al: Variant = r.get("npc_alignment", [])
	if al is Array and not (al as Array).is_empty() and not (str(nrow.get("alignment", "")) in al):
		return false
	var sv: Variant = r.get("services", [])
	if sv is Array and not (sv as Array).is_empty():
		if service != "":
			if not (service in sv):
				return false
		else:
			var any := false
			for x in nrow.get("services", []):
				if x in sv:
					any = true
			if not any:
				return false
	var when: Variant = r.get("when", [])
	return reqs_ok(when if when is Array else [], s)

# ======================================================================== 環境句（§5.3）

## 進房鉤子（RegionSystem.move、NpcSystem.travel 之後呼叫 on_enter_room(s, from, to)；可缺：tick 也會輪詢）
func on_enter_room(s: Session, _from := "", _to := "") -> void:
	if s == null or s.character == null:
		return
	_seen_room[s.peer_id] = s.room_id()
	maybe_line(s)

## 換時辰（GameHost.check_clock）：環境句與時辰變體都是即時查，這裡不用做事
func on_clock(_idx: int = -1) -> void:
	pass

func tick(_dt: float = 0.0) -> void:
	if host == null:
		return
	var live := {}
	for s in host.sessions():
		if s.character == null:
			continue
		live[s.peer_id] = true
		var r: String = s.room_id()
		if not _seen_room.has(s.peer_id):
			_seen_room[s.peer_id] = r   # 登入不算進房
			continue
		if str(_seen_room[s.peer_id]) != r:
			_seen_room[s.peer_id] = r
			maybe_line(s)
		else:
			_maybe_idle_line(s)
	for peer in _seen_room.keys():
		if not live.has(peer):
			_seen_room.erase(peer)
			_next_line_s.erase(peer)
			_idle_line_s.erase(peer)
			_heard.erase(peer)

## 站在同一個房間：每 IDLE_LINE_REAL_S 真實秒擲一次 IDLE_LINE_CHANCE_PCT（仍受 90 秒冷卻）
func _maybe_idle_line(s: Session) -> bool:
	var now: float = host.now_s()
	if not _idle_line_s.has(s.peer_id):
		_idle_line_s[s.peer_id] = now + _world_span(IDLE_LINE_REAL_S)
		return false
	if now < float(_idle_line_s[s.peer_id]):
		return false
	_idle_line_s[s.peer_id] = now + _world_span(IDLE_LINE_REAL_S)
	if not lines_enabled() or s.battle_id != 0 or now < float(_next_line_s.get(s.peer_id, -1.0)):
		return false
	# 站著的閒話用自己的亂數（不改動戰鬥、遇敵用的主機亂數序列）
	if _idle_rng.randi_range(1, 100) > IDLE_LINE_CHANCE_PCT:
		return false
	return _send_line(s, pick_line(s, _idle_rng))

## 進房：先送「第一次一定聽到」的列（first_visit）；否則擲 25%（冷卻中不擲）；送出回 true
func maybe_line(s: Session) -> bool:
	if not lines_enabled() or s.battle_id != 0:
		return false
	_idle_line_s[s.peer_id] = host.now_s() + _world_span(IDLE_LINE_REAL_S)
	var first := first_visit_line(s)
	if not first.is_empty():
		_once(s.character)[str(first.get("id", ""))] = true
		return _send_line(s, first)
	var now: float = host.now_s()
	if now < float(_next_line_s.get(s.peer_id, -1.0)):
		return false
	if host.rng.randi_range(1, 100) > LINE_CHANCE_PCT:
		return false
	return _send_line(s, pick_line(s))

func _send_line(s: Session, pick: Dictionary) -> bool:
	if pick.is_empty():
		return false
	var room: String = s.room_id()
	var npc := str(pick.get("npc", ""))
	host.tell(s, Protocol.CH_SCENE, str(pick["text"]), {
		"name": str(s.character.name), "npc_name": str(_npc(npc).get("name", "")) if npc != "" else "",
		"room_name": str(host.index.room(room).get("name", room)),
		"region_name": str(host.tables.get("regions", {}).get(host.index.region_of(room), {}).get("name", "")) })
	_next_line_s[s.peer_id] = host.now_s() + _world_span(LINE_COOLDOWN_REAL_S)
	var lid := str(pick.get("id", ""))
	if lid != "":
		var h: Dictionary = _heard.get_or_add(s.peer_id, {})
		h[lid] = host.now_s()
	return true

## 這位玩家此刻符合條件、還沒聽過的 first_visit 列（依 id 排序取第一條）；沒有回 {}
func first_visit_line(s: Session) -> Dictionary:
	if s == null or s.character == null:
		return {}
	var seen := _once(s.character)
	for r in candidates(s):
		if r.get("first_visit", false) == true and not seen.has(str(r.get("id", ""))):
			return r
	return {}

func _once(ch) -> Dictionary:
	var e: Variant = ch.get("ext")
	if not (e is Dictionary):
		return {}
	var amb: Variant = e.get("ambient")
	if not (amb is Dictionary):
		amb = {}
		e["ambient"] = amb
	var o: Variant = amb.get(ONCE_KEY)
	if not (o is Dictionary):
		o = {}
		amb[ONCE_KEY] = o
	return o

## 這位玩家此刻可用的環境句（依 weight 抽一條）；沒有回 {}
func pick_line(s: Session, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = host.rng
	var c: Array = []
	var heard: Dictionary = _heard.get(s.peer_id, {}) if s != null else {}
	var cutoff: float = host.now_s() - _world_span(LINE_NO_REPEAT_REAL_S)
	for r in candidates(s):
		var lid := str(r.get("id", ""))
		if heard.has(lid) and float(heard[lid]) > cutoff:
			continue
		c.append(r)
	var total := 0
	for r in c:
		total += maxi(0, int(r.get("weight", 1)))
	if total <= 0:
		return {}
	var roll: int = rng.randi_range(1, total)
	for r in c:
		roll -= maxi(0, int(r.get("weight", 1)))
		if roll <= 0:
			return r
	return c[c.size() - 1]

## 列：{ id, room | region | npc, periods: [], requires: [], weight, text, first_visit? }
func candidates(s: Session) -> Array:
	var out: Array = []
	var t: Variant = host.tables.get("ambient", {})
	if not (t is Dictionary) or s == null or s.character == null:
		return out
	var room: String = s.room_id()
	var region: String = host.index.region_of(room)
	var per := period()
	var here: Array = host.index.npcs_in(room)
	var ids: Array = (t as Dictionary).keys()
	ids.sort()
	for rid in ids:
		var r: Variant = t[rid]
		if not (r is Dictionary) or str(r.get("text", "")) == "" or not _has_template(str(r["text"])):
			continue
		var rr := str(r.get("room", ""))
		var rg := str(r.get("region", ""))
		var npc := str(r.get("npc", ""))
		if rr == "" and rg == "" and npc == "":
			continue
		if rr != "" and rr != room:
			continue
		if rg != "" and rg != region:
			continue
		if npc != "" and (not (npc in here) or not _npc_visible(s, npc, room)):
			continue
		var ps: Variant = r.get("periods", [])
		if ps is Array and not (ps as Array).is_empty() and not (per in ps):
			continue
		var req: Variant = r.get("requires", [])
		if not reqs_ok(req if req is Array else [], s):
			continue
		if int(r.get("weight", 1)) <= 0:
			continue
		out.append(r)
	return out

## appear（QuestSystem.npc_visible）與遊蕩惡人位置（WanderSystem.npc_shown）；系統不在時視為可見
func _npc_visible(s: Session, npc_id: String, room: String) -> bool:
	var q = host.get("quests")
	if q != null and q.has_method("npc_visible") and not bool(q.npc_visible(s.character, npc_id)):
		return false
	var w = host.get("wander")
	if w != null and w.has_method("npc_shown") and not bool(w.npc_shown(npc_id, room)):
		return false
	return true

# ======================================================================== 輔助

func _npc(npc_id: String) -> Dictionary:
	var r: Variant = host.tables.get("npcs", {}).get(npc_id, {})
	return r if r is Dictionary else {}

func _has_template(key: String) -> bool:
	return host.tables.get("text_templates", {}).has(key)

## 角色數值條件在這裡直接算（與 WanderSystem.local_cond 相同），其餘交給 Requirements
func reqs_ok(reqs: Array, s: Session) -> bool:
	var sh := str(host.clock().get("shichen_name", ""))
	for c in reqs:
		if not (c is Dictionary):
			continue
		var v: Variant = local_cond(c, s.character, sh)
		if v == null:
			var ctx := { "shichen": sh }
			var sects = host.get("sects")
			if sects != null and sects.has_method("req_ctx"):
				ctx = sects.req_ctx(s)
			if Requirements.check([c], s.character, host.tables, host.options, host.rules, ctx) != "":
				return false
		elif not bool(v):
			return false
	return true

static func local_cond(c: Dictionary, ch, shichen: String) -> Variant:
	var v := int(c.get("value", 0))
	match str(c.get("type", "")):
		"morality_min":
			return int(ch.morality) >= v
		"morality_max":
			return int(ch.morality) <= v
		"fame_min":
			return int(ch.fame) >= v
		"fame_max":
			return int(ch.fame) <= v
		"combat_xp_min":
			return int(ch.combat_xp) >= v
		"combat_xp_max":
			return int(ch.combat_xp) <= v
		"lilian_min":
			var l: Variant = ch.get("lilian")
			return int(l if l != null else 0) >= v
		"sect":
			return str(ch.sect) != "" and str(ch.sect) == str(c.get("sect", c.get("value", "")))
		"no_sect":
			return str(ch.sect) == ""
		"hour_in":
			var hs: Variant = c.get("hours", [])
			return not (hs is Array) or (hs as Array).is_empty() or shichen in hs
	return null

func _world_span(real_s: float) -> float:
	if host.has_method("world_span"):
		return float(host.world_span(real_s))
	return real_s
