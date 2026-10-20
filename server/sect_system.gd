class_name SectSystem
extends RefCounted
## 門派系統（M3A_PLAN §6）：停止傳功、門規（STATE／EVENT）與三種後果（JAIL／EXPEL／BAN）、叛派與開除、
## 思過處（坐牢、出獄、贖人、公敵被抓）、敵對入山、引路、試煉（十八銅人）、門派技能的取得與衰減。
## GameHost 以路徑 load() 建立（K3／H4）；所有呼叫點先判斷 host.sects != null。
## 期間一律以角色累計上線秒數 ch.online_s 計（K4）；1 遊戲日 = server_options.game_day_real_s。

const STATE_TRIGGERS := ["ENTER", "BATTLE", "LEARN", "PK", "TICK", "TALK"]
## 坐牢中允許的 intent（§6.6）。研究 jy1-2-5-4【已證實】：囚犯只剩傳音入密與輕聲細語（不能用其他指令）→
## 練功（self_study）、打坐（meditate）、運功（exert）、換裝（equip／unequip）都不放行（M3a 審查 A8）。
## 【設計提案】的偏離：use_item（只為了吃喝，刑期最長 6 小時上線時間，不讓人在牢裡餓死渴死）、
## look／talk（看房間、跟看守人問剩餘刑期）、quest_abandon／mail_list／mail_read（純查看）。
## 另外放行：battle_cmd（押入思過處要等戰鬥結束，理論上不會在牢裡打仗，防禦性放行）、
## scout_decline（關掉殘留的偵察視窗）、jail_ransom（任何人都能贖人，含自己）、debug_set（驗收快轉刑期）。
const JAIL_ALLOWED := ["look", "talk", "chat", "use_item",
	"quest_abandon", "mail_list", "mail_read", "battle_cmd", "scout_decline", "jail_ransom", "debug_set"]
## 坐牢中能用的聊天頻道【已證實：只留傳音入密、輕聲細語】
const JAIL_CHANNELS := [Protocol.CH_CHAT_WHISPER, Protocol.CH_CHAT_SAY]
## 敵對入山：同一角色兩次觸發的最短間隔（上線秒＝真實秒）
const HOSTILE_COOLDOWN_S := 30.0
const OUTCOME_JAIL := "JAIL"
const OUTCOME_EXPEL := "EXPEL"
const OUTCOME_BAN := "BAN"
## 犯戒（sects.breach_outcome == "LOCKOUT"；恆山）：不得進山（山門以外）、本派師父不教，直到向 repent_npc 悔過
const OUTCOME_LOCKOUT := "LOCKOUT"
const R_SECT_LOCKOUT := "sect_lockout"
const REQ_SECT_LOCKOUT := "req_sect_lockout"
const REASON_TEXT := { "BREACH": "違反門規", "ENEMY": "身為公敵被擒" }
## 違規後果給玩家看的字（sect_breach.outcome_text；outcome 仍帶代碼給程式用；M3a 審查 C3）
const OUTCOME_TEXT := { "JAIL": "押入思過處", "EXPEL": "逐出師門", "BAN": "禁止學武", "LOCKOUT": "犯戒，悔過之前不得進山、不得學武" }

# ---- M3b（M3B_PLAN §5.1） ----
const SCOPE_SECT := "SECT"
const SCOPE_CAPITAL := "CAPITAL"
const JAIL_AUTO := "AUTO"
const ASSEMBLY_DAILY := "DAILY"
const ASSEMBLY_MONTHLY := "MONTHLY"
const ASSEMBLY_LAST_DAY_KEY := "gb_assembly_last_day"     # world.json（§4.13）：上一次聚會的遊戲日
const ASSEMBLY_LAST_S_KEY := "sect_assembly_last_s"       # world.json：上一次聚會的世界時間（離線補升用；M3B_PLAN 缺漏：只寫了日）
const PROMOTE_JOIN := "JOIN"
const PROMOTE_QUEST := "QUEST"
const PROMOTE_AUTO := "AUTO"
const RANK_WAIT_TEXT := { "assembly": "等下次聚會", "requires": "條件不足", "cost": "名聲或歷練不夠扣" }
const BEG_CD_KEY := "beg_cd"                # ch.counters[beg_cd][npc_id] = 冷卻到期的世界時間
const DEFAULT_BEG_KINDS := ["SHOP", "FUNC", "QUEST", "STORY"]
const NO_BEG_KINDS := ["MASTER", "GUARD", "VILLAIN"]   # 師父、守衛、惡人預設不能乞討（§4.8）
const HARASS_THROTTLE_S := 60.0             # 同一角色 60 秒內最多被追咬一次（上線秒）
const HARASS_INDOOR_SERVICES := ["INN", "BANK", "SHOP"]
const ERA_1_0B := "1.0B"
const BATTLE_SEIZE := "SEIZE"
const BATTLE_HARASS := "HARASS"
const R_HIDE_BEG := "_hide"                 # beg_reason 內部用：這位 NPC 不顯示乞討

var host: GameHost
## char_id -> { sect, capture }：正在打（或剛打完、等 capture_on_death）的敵對入山戰
var _guard: Dictionary = {}
## char_id -> { npc, trial }：正在進行的試煉
var _trials: Dictionary = {}
## char_id -> 上次敵對入山觸發時的 online_s
var _hostile_at: Dictionary = {}
## char_id -> 上次被小黃追咬時的 online_s（M3B_PLAN §5.1.3）
var _harass_at: Dictionary = {}

func _init(p_host: GameHost) -> void:
	host = p_host

# ======================================================================== 查詢

func sect_row(sect_id: String) -> Dictionary:
	if sect_id == "":
		return {}
	return host.tables.get("sects", {}).get(sect_id, {})

func sect_name(sect_id: String) -> String:
	return str(sect_row(sect_id).get("name", sect_id))

## 本派的門規列（依 id 排序）。只回傳適用於目前 sect_violation_mode 的列（`modes`；沒寫 = 全部模式）：
## JAIL／BAN 用 2001-11-15 以後官方的坐牢名單（jy2-22），EXPEL 用 2001-08 的叛派名單（news 141）。
## npc：只回傳 `on_npc` 含這個 NPC 的列（TALK 觸發）；空字串時排除所有 `on_npc` 列。
func rules_of(sect_id: String, kind: String = "", npc: String = "") -> Array:
	var out: Array = []
	var t: Dictionary = host.tables.get("sect_rules", {})
	var ids: Array = t.keys()
	ids.sort()
	var mode := configured_mode()
	for rid in ids:
		var r: Variant = t[rid]
		if not (r is Dictionary) or str(r.get("sect", "")) != sect_id:
			continue
		if str(r.get("tier", "BREACH")) != "BREACH":
			continue
		if kind != "" and str(r.get("kind", "")) != kind:
			continue
		var modes: Variant = r.get("modes", [])
		if modes is Array and not (modes as Array).is_empty() and not (mode in modes):
			continue
		var on_npc: Variant = r.get("on_npc", [])
		var npc_rule := on_npc is Array and not (on_npc as Array).is_empty()
		if npc_rule != (npc != "") or (npc_rule and not (npc in on_npc)):
			continue
		out.append(r)
	return out

## 伺服器設定的 sect_violation_mode（沒有執法者的派會在 effective_mode 改成 BAN；門規名單看這個原始值）
func configured_mode() -> String:
	var mode := str(host.rules.get("sect_violation_mode", OUTCOME_JAIL))
	return mode if mode in [OUTCOME_JAIL, OUTCOME_EXPEL, OUTCOME_BAN] else OUTCOME_JAIL

## 某地區屬於哪一派（sects.gate_region）；不是門派地區回 ""
func sect_of_region(region_id: String) -> String:
	if region_id == "":
		return ""
	var sects: Dictionary = host.tables.get("sects", {})
	var ids: Array = sects.keys()
	ids.sort()
	for sid in ids:
		if str(sects[sid].get("gate_region", "")) == region_id:
			return str(sid)
	return ""

## NPC 屬於哪一派：join_sect，否則看 NPC 所在（或 npcs.region）的地區是不是門派地區
func npc_sect(npc_id: String) -> String:
	var row := host.npc_row(npc_id)
	if row.is_empty():
		return ""
	var js := str(row.get("join_sect", ""))
	if js != "":
		return js
	var region := host.index.region_of(host.index.room_of_npc(npc_id))
	if region == "":
		region = str(row.get("region", ""))
	return sect_of_region(region)

## 主機端的條件判定環境（Requirements ctx；M3A_PLAN 3.7）
func req_ctx(s: Session) -> Dictionary:
	var ctx := { Requirements.CTX_SHICHEN: str(host.clock()["shichen_name"]) }
	if s != null and s.character != null:
		ctx[Requirements.CTX_PARTY_SIZE] = idle_party_here(s).size()
	return ctx

## 同隊、同房間、不在戰鬥中的隊員（含自己，自己排第一）
func idle_party_here(s: Session) -> Array:
	var out: Array = [s]
	var party = host.get("party")
	if party == null or not (party as Object).has_method("members_in_room"):
		return out
	for o in party.members_in_room(s):
		if o != null and o != s and o.character != null and o.battle_id == 0:
			out.append(o)
	return out

func check_reqs(conds: Variant, s: Session) -> String:
	if not (conds is Array) or (conds as Array).is_empty():
		return ""
	return Requirements.check(conds, s.character, host.tables, host.options, host.rules, req_ctx(s))

func is_jailed(s: Session) -> bool:
	return s != null and s.character != null and s.character.is_jailed()

## GameHost._run_intent 的坐牢關卡：回 "" 或 "jailed"
func jail_gate(s: Session, kind: String) -> String:
	if not is_jailed(s):
		return ""
	return "" if kind in JAIL_ALLOWED else Protocol.R_JAILED

func day_s() -> float:
	return host.day_s()

func _opt_int(key: String, def: int) -> int:
	return int(host.options.get(key, def))

## 違反門規實際採用的後果（§6.3 第 2 點）：jail_enabled == false、本派沒有執法者或沒有思過處 → JAIL 改 BAN。
## 例外：sects.breach_outcome == "LOCKOUT"（恆山：研究 mengpai/7「犯戒→不能進入恆山、不能學、NPC 不觸發，直到悔過」，
## 官方門規頁執法者「無（因為進不了恆山）」）→ JAIL／BAN 模式一律犯戒；EXPEL（2001-08 叛派名單）照樣開除（M3a 審查 #1）
func effective_mode(sect_id: String) -> String:
	var mode := configured_mode()
	if mode != OUTCOME_EXPEL and str(sect_row(sect_id).get("breach_outcome", "")) == OUTCOME_LOCKOUT:
		return OUTCOME_LOCKOUT
	if mode == OUTCOME_JAIL and jail_room_for(sect_id, "BREACH") == "":
		mode = OUTCOME_BAN
	return mode

## 這一派能不能押人：規則開著、有執法者、有存在的思過處
func can_jail_in(sect_id: String) -> bool:
	if host.rules.get("jail_enabled", true) == false:
		return false
	var row := sect_row(sect_id)
	if row.is_empty() or not bool(row.get("enforcer", false)):
		return false
	var room := str(row.get("jail_room", ""))
	return room != "" and host.index.has_room(room)

# ======================================================================== 停止傳功

## "" 或 sect_stop_teach／sect_banned／jailed（只管角色自己門派的師父；別派師父照 requires 判定）
func can_teach(s: Session, npc_id: String) -> String:
	if s == null or s.character == null:
		return ""
	var ch = s.character
	if ch.is_jailed():
		return Protocol.R_JAILED
	var sid := str(ch.sect)
	if sid == "" or npc_sect(npc_id) != sid:
		return ""
	return ch.teach_block_reason(host.tables, host.options, host.rules)

# ======================================================================== 拜入

func on_join(s: Session, sect_id: String, npc_id: String) -> void:
	var ch = s.character
	var row := sect_row(sect_id)
	ch.sect_record["joined_online_s"] = ch.online_s
	ch.sect_record["ban_until_online_s"] = 0.0
	ch.sect_record["lockout"] = ""
	ch.sect_record["daily_online_s"] = ch.online_s
	ch.sect_master = npc_id if bool(row.get("personal_master", false)) else ""
	ch.sect_rank = join_rank(sect_id)          # M3B_PLAN §5.1.1：拜入＝promote JOIN 的列（沒有位階表＝0）
	ch.sect_rank_pending = {}
	# 剛拜入時已經不成立的狀態規則直接記為 breached、不觸發（不會一入門就坐牢）
	var br := {}
	for r in rules_of(sect_id, "STATE"):
		if not _rule_ok(r, s):
			br[str(r.get("id", ""))] = true
	ch.sect_record["breached"] = br
	ch.add_sect_history(sect_id, "JOIN")
	s.sheet_dirty = true

# ======================================================================== 門規

func _rule_ok(r: Dictionary, s: Session) -> bool:
	var conds: Variant = r.get("ok_if", [])
	if not (conds is Array):
		return true
	return Requirements.check(conds, s.character, host.tables, host.options, host.rules, req_ctx(s)) == ""

## 狀態規則檢查（§6.3）：成立 → 不成立的轉換觸發一次；恢復成立時清掉記號。
## trigger == "TALK"（npc 非空）：只檢查 on_npc 含此 NPC 的列（武當 2001-08：善惡過低時跟特定師長交談即叛派）
func check_state(s: Session, trigger: String, npc: String = "") -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	var sid := str(ch.sect)
	if sid == "":
		return
	if trigger == "TALK" and (npc == "" or npc_sect(npc) != sid):
		return
	var br: Dictionary = ch.sect_record.get("breached", {})
	ch.sect_record["breached"] = br
	var first: Dictionary = {}
	for r in rules_of(sid, "STATE", npc if trigger == "TALK" else ""):
		var rid := str(r.get("id", ""))
		var good := _rule_ok(r, s)
		if good:
			br.erase(rid)
		elif not br.has(rid):
			br[rid] = true
			if first.is_empty():
				first = r
	if not first.is_empty():
		breach(s, first, trigger)

## 違反門規的後果（§6.3 第 2、3 點）；回傳實際採用的後果
func breach(s: Session, rule: Dictionary, _trigger: String = "") -> String:
	var ch = s.character
	var sid := str(rule.get("sect", ch.sect))
	if sid == "" or str(ch.sect) != sid:
		return ""
	var mode := effective_mode(sid)
	var rid := str(rule.get("id", ""))
	var days := 0
	match mode:
		OUTCOME_JAIL:
			days = _opt_int("jail_breach_days", 1)
		OUTCOME_BAN:
			days = _opt_int("ban_days", 1)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SECT_BREACH, {
		"sect_name": sect_name(sid), "rule_text": rule_text(rule), "outcome": mode,
		"outcome_text": str(OUTCOME_TEXT.get(mode, mode)), "days": days, "enforcer": enforcer_name(sid) })
	match mode:
		OUTCOME_JAIL:
			jail(s, sid, days, "BREACH", rid)
		OUTCOME_EXPEL:
			expel(s, "BREACH", rid)
		OUTCOME_LOCKOUT:
			lockout(s, sid, rid)
		_:
			ban(s, sid, days, rid)
	s.sheet_dirty = true
	return mode

## 門規文字：模板的 self 變體（只寫規則本身）；沒有模板時用門規 id。去掉頻道標籤與結尾句號，
## 由 sect_breach 模板接成「你違反了少林門規：善惡不得低於 −299（處置：押入思過處）。」（M3a 審查 C3）
func rule_text(rule: Dictionary) -> String:
	var key := str(rule.get("text", ""))
	var t: Variant = host.tables.get("text_templates", {}).get(key, {})
	if t is Dictionary and str(t.get("self", "")) != "":
		return clean_rule_text(str(t["self"]))
	return key if key != "" else str(rule.get("id", ""))

## 「【門規】少林弟子…。」→「少林弟子…」：去掉開頭的【…】標籤與結尾的。（模板本身已不帶，這裡防舊資料）
static func clean_rule_text(t: String) -> String:
	var s := t.strip_edges()
	if s.begins_with("【"):
		var end := s.find("】")
		if end > 0:
			s = s.substr(end + 1).strip_edges()
	while s.ends_with("。"):
		s = s.substr(0, s.length() - 1)
	return s

## 遊戲日 → 上線時間的字：「2 小時」「1 小時 30 分」「5 分」（jail_in.online_text；M3a 審查 C4）
func online_text(days: int) -> String:
	var secs := maxi(0, roundi(maxi(1, days) * day_s()))
	var h := secs / 3600
	var m := (secs % 3600) / 60
	if h > 0:
		return "%d 小時" % h if m == 0 else "%d 小時 %d 分" % [h, m]
	if m > 0:
		return "%d 分" % m
	return "%d 秒" % secs

func enforcer_name(sect_id: String) -> String:
	var list: Variant = sect_row(sect_id).get("enforcers", [])
	if list is Array and not (list as Array).is_empty():
		return host.npc_name(str(list[0]))
	return ""

## EVENT 規則
func _event_breach(s: Session, event: String, arg: String = "") -> void:
	var ch = s.character
	var sid := str(ch.sect)
	if sid == "":
		return
	for r in rules_of(sid, "EVENT"):
		if str(r.get("event", "")) != event:
			continue
		if event == "ENTER_REGION" and str(r.get("event_arg", "")) != arg:
			continue
		breach(s, r, event)
		return

# ======================================================================== 叛派、開除、坐牢、禁武

## 叛派（§6.5）：驗證在 intent 裡做完；這裡套懲罰並廣播
func betray(s: Session, npc_id: String) -> Dictionary:
	var ch = s.character
	var sid := str(ch.sect)
	if sid == "":
		return GameHost.fail("no_service")
	var res: Dictionary = ch.betray_penalty(host.tables, host.rules, "BETRAY")
	_penalty_events(s, res)
	host.ws.broadcast_event(Protocol.CH_SYSTEM, Protocol.E_SECT_BETRAY,
		{ "name": str(ch.name), "peer": s.peer_id, "sect_name": sect_name(sid), "npc_name": host.npc_name(npc_id) })
	_after_leave_sect(s)
	return GameHost.ok({ "penalty": res })

## 開除（= 叛派懲罰）；人在本派地圖時送到山門
func expel(s: Session, reason: String, rule_id: String) -> void:
	var ch = s.character
	var sid := str(ch.sect)
	if sid == "":
		return
	var res: Dictionary = ch.betray_penalty(host.tables, host.rules, "EXPEL")
	_penalty_events(s, res)
	host.ws.broadcast_event(Protocol.CH_SYSTEM, Protocol.E_SECT_EXPEL,
		{ "name": str(ch.name), "peer": s.peer_id, "sect_name": sect_name(sid), "reason": reason, "rule": rule_id })
	var gate := str(sect_row(sid).get("gate_room", ""))
	if s.battle_id == 0 and gate != "" and host.index.has_room(gate) \
			and host.index.region_of(s.room_id()) == str(sect_row(sid).get("gate_region", "")) and s.room_id() != gate:
		_drop_escorts(s)
		host.regions.teleport(s, gate, false)
	_after_leave_sect(s)

func _penalty_events(s: Session, res: Dictionary) -> void:
	for it in res.get("items_removed", []):
		host.item_lost_event(s, str(it.get("id", "")), int(it.get("n", 1)))

func _after_leave_sect(s: Session) -> void:
	s.sheet_dirty = true
	s.view_dirty = true
	host.regions.mark_room_dirty(s.room_id())

## 押入思過處（§6.6）。人在戰鬥中時先記下，等戰鬥結束由 enforce_jail 送進去
func jail(s: Session, sect_id: String, days: int, reason: String, rule_id: String) -> void:
	if s == null or s.character == null:
		return
	if not _jail_char(s.character, sect_id, days, reason, rule_id):
		ban(s, sect_id, _opt_int("ban_days", 1), rule_id)
		return
	if host.scout != null:
		host.scout.invalidate(s, ScoutSystem.WHY_MOVED)
	enforce_jail(s)
	s.sheet_dirty = true

## 純角色部分：寫 ch.jail；沒有牢房回 false。M3B_PLAN §5.1.4：牢房由 jail_room_for 決定（思過處或京城監獄）
func _jail_char(ch, sect_id: String, days: int, reason: String, rule_id: String) -> bool:
	var room := jail_room_for(sect_id, reason)
	if room == "" or not host.index.has_room(room):
		return false
	var d := maxi(1, days)
	ch.jail = { "sect": sect_id, "room": room, "until_online_s": ch.online_s + d * day_s(),
		"reason": reason, "rule": rule_id, "days": d, "notified": false,
		"scope": SCOPE_CAPITAL if room_scope(room) == SCOPE_CAPITAL else SCOPE_SECT }
	ch.add_sect_history(sect_id, "JAIL")
	return true

## 坐牢中而不在思過處（剛押、戰後、重生、登入）→ 瞬移進去；還沒通知 → jail_in（自己＋同房間）
func enforce_jail(s: Session) -> void:
	if s == null or s.character == null or s.battle_id != 0:
		return
	var ch = s.character
	if not ch.is_jailed():
		return
	# M3b 審查 3：押進監獄 → 護送對象（鏢車）走散，不會跟著進牢、出獄時也不會跟到衙門旁
	_drop_escorts(s)
	var room := str(ch.jail.get("room", ""))
	if room != "" and host.index.has_room(room) and s.room_id() != room:
		host.regions.teleport(s, room, false)
	if not bool(ch.jail.get("notified", true)):
		ch.jail["notified"] = true
		var sid := str(ch.jail.get("sect", ""))
		var p := { "name": str(ch.name), "peer": s.peer_id, "sect_name": sect_name(sid),
			"room_name": host.room_name(room), "days": int(ch.jail.get("days", 1)),
			"online_text": online_text(int(ch.jail.get("days", 1))),
			"reason_text": str(REASON_TEXT.get(str(ch.jail.get("reason", "")), "")), "enforcer": enforcer_name(sid),
			"left_s": ch.jail_left_s(), "scope": str(ch.jail.get("scope", SCOPE_SECT)) }
		# M3B_PLAN §8.3 _sect.json：京城監獄用 CAPITAL 變體模板（jail_in_capital）；模板不在時退回 jail_in
		var key := _scope_key(Protocol.E_JAIL_IN, str(ch.jail.get("scope", SCOPE_SECT)))
		host.tell(s, Protocol.CH_SYSTEM, key, p)
		host.ws.queue_room_event(room, Protocol.CH_SYSTEM, key, p.duplicate(), s.peer_id)
		s.sheet_dirty = true

## 出獄：why ∈ served／ransom／admin。送回該派山門；公敵被抓的改過自新（移出 sect_enemies）
func release(s: Session, why: String) -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	if not ch.is_jailed():
		return
	var sid := str(ch.jail.get("sect", ""))
	var reason := str(ch.jail.get("reason", ""))
	var scope := str(ch.jail.get("scope", SCOPE_SECT))
	var jroom := str(ch.jail.get("room", ""))
	ch.jail = {}
	if reason == "ENEMY":
		ch.sect_enemies.erase(sid)
	ch.add_sect_history(sid, "RELEASE")
	# M3B_PLAN §5.1.4：京城監獄出獄送到牢房的 jail_release_to（京城衙門）；思過處照舊送回山門
	var gate := ""
	if scope == SCOPE_CAPITAL:
		gate = str(host.index.room(jroom).get("jail_release_to", ""))
	if gate == "" or not host.index.has_room(gate):
		gate = str(sect_row(sid).get("gate_room", ""))
	if gate == "" or not host.index.has_room(gate):
		gate = host.respawn_room(ch)
	_drop_escorts(s)
	if s.battle_id == 0:
		host.regions.teleport(s, gate, false)
	else:
		ch.location = { "region": host.index.region_of(gate), "room": gate }
	host.tell(s, Protocol.CH_SYSTEM, _scope_key(Protocol.E_JAIL_OUT, scope),
		{ "sect_name": sect_name(sid), "room_name": host.room_name(gate), "why": why, "scope": scope,
			"jail_name": host.room_name(jroom) })
	s.sheet_dirty = true
	s.view_dirty = true

## 禁止學武：本派師父不教，直到 ban_until_online_s（取較晚者）
func ban(s: Session, sect_id: String, days: int, _rule_id: String) -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	var until: float = ch.online_s + maxi(1, days) * day_s()
	ch.sect_record["ban_until_online_s"] = maxf(float(ch.sect_record.get("ban_until_online_s", 0.0)), until)
	s.sheet_dirty = true

# ======================================================================== 犯戒與悔過（恆山）

## 犯戒：記下觸犯的門規；人在山門以內 → 送到山門（戰鬥中先記下，戰後由 enforce_lockout 送）
func lockout(s: Session, sect_id: String, rule_id: String) -> void:
	if s == null or s.character == null or str(s.character.sect) != sect_id:
		return
	s.character.sect_record["lockout"] = rule_id if rule_id != "" else "BREACH"
	s.character.add_sect_history(sect_id, "LOCKOUT")
	enforce_lockout(s)
	s.sheet_dirty = true
	s.view_dirty = true

## 犯戒中而人在本派山門以內（戰後、登入）→ 瞬移到山門（ConditionSystem 每秒呼叫）
func enforce_lockout(s: Session) -> void:
	if s == null or s.character == null or s.battle_id != 0 or not s.character.is_locked_out():
		return
	if lockout_reason(s.character, s.room_id()) == "":
		return
	var gate := str(sect_row(str(s.character.sect)).get("gate_room", ""))
	if gate != "" and host.index.has_room(gate):
		_drop_escorts(s)
		host.regions.teleport(s, gate, false)

## RegionSystem.lock_reason：犯戒的弟子進不了本派地區山門以外的房間 → req_sect_lockout
func lockout_reason(ch, room_id: String) -> String:
	if ch == null or not ch.is_locked_out():
		return ""
	var row := sect_row(str(ch.sect))
	if host.index.region_of(room_id) != str(row.get("gate_region", "")) or room_id == str(row.get("gate_room", "")):
		return ""
	return REQ_SECT_LOCKOUT

## 跟本派 repent_npc（恆山知客弟子，在山門）交談＝悔過：本派狀態門規都已符合 → 解除犯戒；否則告訴還差哪一條。
## 向誰悔過、悔過要什麼條件原作【待考證】（研究 恆山 Open: who you repent to）→ 這裡是【設計提案】
func try_repent(s: Session, npc_id: String) -> void:
	if s == null or s.character == null or not s.character.is_locked_out():
		return
	var ch = s.character
	var sid := str(ch.sect)
	if npc_id == "" or str(sect_row(sid).get("repent_npc", "")) != npc_id:
		return
	for r in rules_of(sid, "STATE"):
		if not _rule_ok(r, s):
			host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SECT_REPENT_REFUSED,
				{ "npc_name": host.npc_name(npc_id), "sect_name": sect_name(sid), "rule_text": rule_text(r) })
			return
	ch.sect_record["lockout"] = ""
	ch.add_sect_history(sid, "REPENT")
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SECT_REPENT, { "npc_name": host.npc_name(npc_id), "sect_name": sect_name(sid) })
	s.sheet_dirty = true
	s.view_dirty = true

# ======================================================================== 贖人

## jail_ransom：npc 檢查 → no_prisoner → not_enough_money → 扣錢、release(target, "ransom")
func ransom(s: Session, npc_id: String, prisoner_name: String) -> Dictionary:
	var r := host.npc_check(s, npc_id, "JAIL")
	if r != "":
		return GameHost.fail(r)
	var room := jail_room_of_npc(npc_id)
	var t: Session = host.session_for_char_name(prisoner_name)
	if t == null or t.character == null or not t.character.is_jailed() or str(t.character.jail.get("room", "")) != room:
		return GameHost.fail(Protocol.R_NO_PRISONER)
	var price := _opt_int("jail_ransom", 100000)
	if int(s.character.money) < price:
		return GameHost.fail("not_enough_money")
	s.character.add_money(-price)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_JAIL_RANSOM_PAID,
		{ "name": str(t.character.name), "cost": price, "npc_name": host.npc_name(npc_id) })
	release(t, "ransom")
	host.save_char(t.character)
	return GameHost.ok()

## 看守人管的牢房：站在牢房裡（M3a 思過處）就是那一間；站在監獄門口（M3b 京城監獄看守人在 jc_jail_gate）→ 相鄰出口中的牢房。
## M3B_PLAN 缺漏：§5.1.4 說 prisoners_in(room) 不變，但 §8.3 把看守人放在監獄門口；這裡用相鄰的牢房
func jail_room_of_npc(npc_id: String) -> String:
	var room := host.index.room_of_npc(npc_id)
	if bool(host.index.room(room).get("jail", false)):
		return room
	for ex in host.index.room(room).get("exits", []):
		if ex is Dictionary and bool(host.index.room(str(ex.get("to", ""))).get("jail", false)):
			return str(ex["to"])
	return room

func prisoners_in(room_id: String) -> Array:
	var out: Array = []
	for o in host.sessions():
		if o.character != null and o.character.is_jailed() and str(o.character.jail.get("room", "")) == room_id:
			out.append({ "name": str(o.character.name), "left_s": o.character.jail_left_s() })
	out.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	return out

# ======================================================================== 走進房間

## RegionSystem 走路／瞬移後呼叫：ENTER_REGION 門規與門派技能衰減（換地區時）→ 狀態規則 → 敵對入山
func on_enter_room(s: Session, room_id: String) -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	var region := host.index.region_of(room_id)
	var changed := region != s.last_region
	s.last_region = region
	if ch.is_jailed():
		return
	if changed and str(ch.sect) != "":
		_enter_region_penalty(s, region)
		_event_breach(s, "ENTER_REGION", region)
	if ch.is_jailed() or s.character == null:
		return
	check_state(s, "ENTER")
	if not ch.is_jailed():
		if not hostile_entry(s, room_id):
			harass(s, room_id)

func _enter_region_penalty(s: Session, region: String) -> void:
	var ch = s.character
	var row := sect_row(str(ch.sect))
	var last: Dictionary = ch.sect_record.get("region_penalty", {})
	for p in row.get("sect_skill_penalties", []):
		if not (p is Dictionary) or str(p.get("trigger", "")) != "ENTER_REGION" or str(p.get("region", "")) != region:
			continue
		var key := "ENTER_REGION:" + region
		if last.has(key) and ch.online_s - float(last[key]) < day_s():
			continue   # 每遊戲日最多一次
		last[key] = ch.online_s
		ch.sect_record["region_penalty"] = last
		_decay(s, int(p.get("levels", 1)))

## 門派技能 −levels（最低 0）；事件 sect_skill_decay
func _decay(s: Session, levels: int) -> void:
	var ch = s.character
	var ss := str(sect_row(str(ch.sect)).get("sect_skill", ""))
	if ss == "" or levels <= 0:
		return
	var before: int = ch.skills.level(ss)
	if before <= 0:
		return
	var after := maxi(0, before - levels)
	ch.skills.set_level(ss, after, host.tables)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SECT_SKILL_DECAY, { "skill_name": host.skill_name(ss), "level": after })
	s.sheet_dirty = true

## 每累計上線 1 遊戲日一次：DAILY_IF 衰減（ConditionSystem 每秒呼叫）
func daily_tick(s: Session) -> void:
	if s == null or s.character == null or str(s.character.sect) == "":
		return
	var ch = s.character
	var last := float(ch.sect_record.get("daily_online_s", ch.sect_record.get("joined_online_s", 0.0)))
	if ch.online_s - last < day_s():
		return
	ch.sect_record["daily_online_s"] = last + day_s() * floorf((ch.online_s - last) / day_s())
	for p in sect_row(str(ch.sect)).get("sect_skill_penalties", []):
		if p is Dictionary and str(p.get("trigger", "")) == "DAILY_IF" and check_reqs(p.get("if", []), s) == "":
			_decay(s, int(p.get("levels", 1)))

## 敵對入山（§6.7）
func hostile_entry(s: Session, room_id: String) -> bool:
	if host.options.get("sect_hostile_entry", true) == false or s.battle_id != 0:
		return false
	var ch = s.character
	var sid := sect_of_region(host.index.region_of(room_id))
	if sid == "" or str(ch.sect) == sid:
		return false
	var row := sect_row(sid)
	var cid := str(ch.id)
	if _hostile_at.has(cid) and ch.online_s - float(_hostile_at[cid]) < HOSTILE_COOLDOWN_S \
			and float(_hostile_at[cid]) <= ch.online_s:
		return false
	var gate := str(row.get("gate_room", ""))
	for rule in row.get("hostile_entry", []):
		if not (rule is Dictionary):
			continue
		var where := str(rule.get("rooms", "ALL"))
		if where == "GATE" and room_id != gate:
			continue
		if where == "INNER" and room_id == gate:
			continue
		if check_reqs(rule.get("if", []), s) != "":
			continue
		if host.rng.randf() >= float(rule.get("chance", 1.0)):
			continue
		var mid := str(rule.get("monster", ""))
		if not host.tables.get("monsters", {}).has(mid):
			continue
		var cnt: Variant = rule.get("count", [1, 1])
		var lo := 1
		var hi := 1
		if cnt is Array and (cnt as Array).size() >= 2:
			lo = maxi(1, int(cnt[0]))
			hi = maxi(lo, int(cnt[1]))
		var n := host.rng.randi_range(lo, hi)
		var ids: Array = []
		for i in n:
			ids.append(mid)
		_hostile_at[cid] = ch.online_s
		_guard[cid] = { "sect": sid, "capture": bool(rule.get("capture", false)) }
		host.tell(s, Protocol.CH_BATTLE, Protocol.E_SECT_HOSTILE,
			{ "sect_name": sect_name(sid), "monster_name": host.monster_name(mid), "n": n })
		start_battle(s, ids, "SECT_GUARD", { "no_flee": bool(rule.get("no_flee", false)), "pull_party": true })
		return true
	return false

## BattleSystem.start_ex（WP-CMD）不存在時退回 start（沒有波次與 no_flee）
func start_battle(s: Session, ids: Array, kind: String, opts: Dictionary) -> int:
	var b = host.battles
	if b == null:
		return 0
	if (b as Object).has_method("start_ex"):
		return int(b.start_ex(s, ids, kind, opts))
	return int(b.start(s, ids, kind))

# ======================================================================== 戰鬥

## BattleSystem._settle_player（5.8 第 3 步）。summary = { kind, result, kills, killed_by, died, pvp_initiator, same_sect_kills }。
## same_sect_kills 不在這裡處理：KILL_SAME_SECT 由 PkSystem 呼叫 on_pvp_kill（同一件事只觸發一次）。
func on_battle_settled(s: Session, ch, summary: Dictionary) -> void:
	if ch == null:
		return
	var cid := str(ch.id)
	var kind := str(summary.get("kind", ""))
	var result := str(summary.get("result", ""))
	if kind == "TRIAL" and _trials.has(cid):
		var t: Dictionary = _trials[cid]
		_trials.erase(cid)
		if result == "VICTORY":
			var tr: Dictionary = t.get("trial", {})
			var flag := str(tr.get("reward_flag", ""))
			if flag != "":
				ch.flags[flag] = true
			if s != null:
				host.tell(s, Protocol.CH_SYSTEM, Protocol.E_TRIAL_PASSED, { "trial_name": trial_name(str(t.get("npc", "")), tr) })
	if kind == "SECT_GUARD" and not bool(summary.get("died", false)):
		_guard.erase(cid)
	if result == "VICTORY" and str(ch.sect) != "":
		_kill_gain(s, ch, summary.get("kills", []))
	_spar_settle(s, ch, summary)   # M3c2 WP-PACE：切磋獎勵（規則、每日上限、新手期）
	if s != null and s.character == ch:
		check_state(s, "BATTLE")

## sect_skill_gain KILL_ALIGNMENT：每殺一隻 alignment 相符的怪，門派技能熟練 +prof
func _kill_gain(s: Session, ch, kills: Variant) -> void:
	if not (kills is Array) or (kills as Array).is_empty():
		return
	var row := sect_row(str(ch.sect))
	var ss := str(row.get("sect_skill", ""))
	if ss == "":
		return
	var mons: Dictionary = host.tables.get("monsters", {})
	for g in row.get("sect_skill_gain", []):
		if not (g is Dictionary) or str(g.get("on", "")) != "KILL_ALIGNMENT":
			continue
		var n := 0
		for mid in kills:
			if str(mons.get(unit_monster(str(mid)), {}).get("alignment", "")) == str(g.get("alignment", "")):
				n += 1
		if n == 0:
			continue
		var before: int = ch.skills.level(ss)
		var res: Dictionary = ch.skills.add_prof(ss, int(g.get("prof", 0)) * n, host.tables, host.skill_cap(ch, ss))
		if s != null:
			host.npcs.skill_up_event(s, ss, before, int(res.get("after", before)))
			s.sheet_dirty = true

## 公敵被抓（§6.6、5.8 第 4 步）：回 {} 或 { jail: true, sect, room }。死亡懲罰照常，但不回記錄點
func capture_on_death(s: Session, ch, summary: Dictionary) -> Dictionary:
	if ch == null:
		return {}
	var cid := str(ch.id)
	var kind := str(summary.get("kind", ""))
	var x := ""
	if kind == "SECT_GUARD":
		var g: Dictionary = _guard.get(cid, {})
		var gs := str(g.get("sect", ""))
		if gs != "" and bool(g.get("capture", false)) and ch.sect_enemies.has(gs):
			x = gs
	_guard.erase(cid)
	# M3B_PLAN §5.1.5：捉拿公敵（SEIZE）的戰鬥：抓人的門派由開戰時記下（隊友不同派也算這一派抓的）
	if x == "" and kind == BATTLE_SEIZE:
		var szs := str(summary.get("seize_sect", ""))
		if szs != "" and ch.sect_enemies.has(szs):
			x = szs
	var kb: Variant = summary.get("killed_by", {})
	if x == "" and kb is Dictionary:
		var ks := str(kb.get("sect", ""))
		if ks == "" and str(kb.get("kind", "")) == "MONSTER":
			ks = str(host.tables.get("monsters", {}).get(unit_monster(str(kb.get("ref", ""))), {}).get("sect", ""))
		if ks != "" and ch.sect_enemies.has(ks):
			x = ks
	# M3B_PLAN §5.1.4：M3a 的 can_jail_in(x) 改成 jail_room_for(x, "ENEMY")（京城監獄收押公敵不看本派有沒有執法者）
	if x == "" or configured_mode() == OUTCOME_BAN or jail_room_for(x, "ENEMY") == "":
		return {}
	if not _jail_char(ch, x, _opt_int("jail_enemy_days", 3), "ENEMY", ""):
		return {}
	var room := str(ch.jail.get("room", ""))
	if s == null:
		ch.location = { "region": host.index.region_of(room), "room": room }
		ch.jail["notified"] = true   # 離線：上線時 relocated 不必再說一次被押
	return { "jail": true, "sect": x, "room": room, "room_name": host.room_name(room),
		"scope": str(ch.jail.get("scope", SCOPE_SECT)) }

## 戰鬥單位的 ref → 怪物列 id：攻擊 NPC 戰的主單位 ref 是 NPC id（M3C_PLAN §5.7），換成它的 attack.monster
func unit_monster(ref: String) -> String:
	if ref.begins_with("n_"):
		var a: Variant = host.npc_row(ref).get("attack", {})
		if a is Dictionary and str(a.get("monster", "")) != "":
			return str(a["monster"])
	return ref

## PkSystem 呼叫：強制 PK 的發起者殺死同門玩家 → KILL_SAME_SECT（叫戰、被出手者反殺不算）
func on_pvp_kill(killer: Session, victim_char, initiator: bool) -> void:
	if killer == null or killer.character == null or victim_char == null or not initiator:
		return
	var sid := str(killer.character.sect)
	if sid == "" or str(victim_char.sect) != sid or str(victim_char.id) == str(killer.character.id):
		return
	_event_breach(killer, "KILL_SAME_SECT")

# ======================================================================== M3c：攻擊 NPC 的門派後果（M3C_PLAN §5.6）

## 動手時（ATTACK 類）。attack 已由 NpcAttackSystem 補好 sect（實際門派）與 event（MIEPAI／ATTACK_MASTER／""）。
## - 本派弟子 × 本派 NPC：ATTACK_MASTER → force_betray（叛派）；其他 → ATTACK_SECT_NPC 門規（<p>_r_attack_npc → breach）
## - 外人 × SECT_GATE、滅派、SECT_MASTER → make_enemy（公敵）；外人 × SECT_DISCIPLE → 只開戰
func on_npc_attack(s: Session, npc_id: String, attack: Dictionary) -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	var sid := str(attack.get("sect", ""))
	if sid == "":
		sid = npc_sect(npc_id)
	if sid == "":
		return
	var ev := str(attack.get("event", ""))
	var cat := str(attack.get("category", ""))
	if str(ch.sect) == sid:
		if ev == "ATTACK_MASTER":
			force_betray(s, sid, "ATTACK_MASTER")
		else:
			_event_breach(s, "ATTACK_SECT_NPC")
		return
	if cat == "SECT_GATE" or cat == "SECT_MASTER" or ev == "MIEPAI" or ev == "ATTACK_MASTER":
		make_enemy(s, sid, "MIEPAI" if ev == "MIEPAI" else ("ATTACK_MASTER" if ev == "ATTACK_MASTER" else "ATTACK_GATE"))

## 殺了才算（KILL 類；主單位死、玩家方勝）：s 可能為 null（擊殺者已離線：門規只能在線處理，降級照算）
## - 華山、恆山弟子殺 GOOD → KILL_GOOD_NPC 門規（hs／hg_r_kill_good_npc）
## - 少林、恆山：sect_skill_penalties KILL_NPC_ALIGNMENT（佛法／慈悲降級）
## - 峨嵋斷惡：既有 sect_skill_gain KILL_ALIGNMENT 經 on_battle_settled（kills 的 NPC id 由 unit_monster 換成怪物列）
func on_npc_killed(s: Session, ch, npc_id: String, attack: Dictionary, alignment: String) -> void:
	if ch == null or str(ch.sect) == "":
		return
	var row := sect_row(str(ch.sect))
	var ss := str(row.get("sect_skill", ""))
	for p in row.get("sect_skill_penalties", []):
		if not (p is Dictionary) or str(p.get("trigger", "")) != "KILL_NPC_ALIGNMENT":
			continue
		if str(p.get("alignment", "")) != "" and str(p.get("alignment", "")) != alignment:
			continue
		if s != null and s.character == ch:
			_decay(s, int(p.get("levels", 1)))
		elif ss != "" and ch.skills.level(ss) > 0:
			ch.skills.set_level(ss, maxi(0, ch.skills.level(ss) - int(p.get("levels", 1))), host.tables)
	if alignment == "GOOD" and s != null and s.character == ch:
		_event_breach(s, "KILL_GOOD_NPC")

## 成為某派公敵（已是公敵不重複）：加入 ch.sect_enemies、送 na_sect_enemy；之後既有 hostile_entry、執法者捉拿、ENEMY 監獄照常
func make_enemy(s: Session, sect_id: String, cause: String) -> void:
	if s == null or s.character == null or sect_id == "" or sect_row(sect_id).is_empty():
		return
	var ch = s.character
	if ch.sect_enemies.has(sect_id):
		return
	ch.sect_enemies.append(sect_id)
	ch.add_sect_history(sect_id, "ENEMY")
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_NA_SECT_ENEMY,
		{ "sect_name": sect_name(sect_id), "name": str(ch.name), "cause": cause })
	_after_leave_sect(s)

## 本派弟子對丁春秋／血刀老祖下手＝叛派（照既有叛派懲罰：本門武功減半、sect_traitor、sect_enemies），全服 na_master_betray
func force_betray(s: Session, sect_id: String, rule_id: String) -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	if str(ch.sect) != sect_id or sect_id == "":
		return
	var res: Dictionary = ch.betray_penalty(host.tables, host.rules, "BETRAY")
	_penalty_events(s, res)
	host.ws.broadcast_event(Protocol.CH_SYSTEM, Protocol.E_NA_MASTER_BETRAY,
		{ "name": str(ch.name), "peer": s.peer_id, "sect_name": sect_name(sect_id),
			"npc_name": host.npc_name(str(sect_row(sect_id).get("head_npc", ""))), "rule": rule_id })
	_after_leave_sect(s)

# ======================================================================== 引路、試煉

func trial_name(npc_id: String, tr: Dictionary) -> String:
	var n := str(tr.get("name", ""))
	return n if n != "" else host.npc_name(npc_id) + "的試煉"

## 試煉（§6.9）：npc 檢查 → 自己 requires → 隊伍（同隊、同房、閒置的人數在範圍內，每位都符合）→ 開戰
func start_trial(s: Session, npc_id: String) -> Dictionary:
	var r := host.npc_check(s, npc_id, "TRIAL")
	if r != "":
		return GameHost.fail(r)
	var tr: Variant = host.npc_row(npc_id).get("trial", {})
	if not (tr is Dictionary) or not (tr.get("waves", []) is Array) or (tr["waves"] as Array).is_empty():
		return GameHost.fail("no_service")
	var req := check_reqs(tr.get("requires", []), s)
	if req != "":
		return GameHost.fail(req)
	var why := trial_party_check(s, tr)
	if why != "":
		return GameHost.fail(why)
	var waves: Array = []
	for w in tr["waves"]:
		if w is Array:
			var ids: Array = []
			for m in w:
				if host.tables.get("monsters", {}).has(str(m)):
					ids.append(str(m))
			if not ids.is_empty():
				waves.append(ids)
	if waves.is_empty():
		return GameHost.fail("no_service")
	for o in idle_party_here(s):
		_trials[str(o.character.id)] = { "npc": npc_id, "trial": (tr as Dictionary).duplicate(true) }
	var bid := start_battle(s, waves[0], "TRIAL", { "waves": waves, "no_flee": bool(tr.get("no_flee", true)),
		"party_only": true, "pull_party": true })
	return GameHost.ok({ "battle_id": bid })

func trial_party_check(s: Session, tr: Dictionary) -> String:
	var members := idle_party_here(s)
	var lo := int(tr.get("party_min", 1))
	var hi := int(tr.get("party_max", 99))
	if members.size() < lo or members.size() > hi:
		return Protocol.R_TRIAL_PARTY
	for o in members:
		if check_reqs(tr.get("requires", []), o) != "":
			return Protocol.R_TRIAL_PARTY
	return ""

## 瞬移前讓護送對象走散（QuestSystem.drop_escorts；沒有 QuestSystem 的測試宿主略過）
func _drop_escorts(s: Session) -> void:
	if host.quests != null and host.quests.has_method("drop_escorts"):
		host.quests.drop_escorts(s)

## 引路（§6.8）：npc 檢查 → requires → 護送中不行 → 瞬移（同一門派地區內）
func guide(s: Session, npc_id: String) -> Dictionary:
	var r := host.npc_check(s, npc_id, "GUIDE")
	if r != "":
		return GameHost.fail(r)
	var g: Variant = host.npc_row(npc_id).get("guide", {})
	var to := str(g.get("to_room", "")) if g is Dictionary else ""
	if to == "" or not host.index.has_room(to):
		return GameHost.fail("no_service")
	var req := check_reqs(g.get("requires", []), s)
	if req != "":
		return GameHost.fail(req)
	# M3b 審查 3：護送途中不能讓人引路（同驛站馬車：鏢車得一步一步跟著走）
	if host.quests != null and not host.quests.escort_npcs(s.character).is_empty():
		return GameHost.fail("escorting")
	host.regions.teleport(s, to)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_NPC_GUIDE, { "npc_name": host.npc_name(npc_id), "room_name": host.room_name(to) })
	host.quests.on_reach(s)
	return GameHost.ok()

# ======================================================================== npc_menu

## npc_menu 的 M3a 欄位（§6.12）：betray、jail、trial、guide、teach_blocked
func menu_fields(s: Session, npc_id: String) -> Dictionary:
	var row := host.npc_row(npc_id)
	var services: Array = row.get("services", [])
	var ch = s.character if s != null else null
	var out := { "betray": false, "jail": null, "trial": null, "guide": null, "teach_blocked": "", "rank": null, "beg": null }
	if ch == null:
		return out
	# M3B_PLAN §6：RANK 服務（本派弟子才看得到）、乞討（本派有 practice 的人才看得到）
	if "RANK" in services and str(ch.sect) != "" and npc_sect(npc_id) == str(ch.sect):
		out["rank"] = rank_menu(s)
	if not practice_of(str(ch.sect)).is_empty():
		var why := beg_reason(s, npc_id)
		# M3b 審查：永遠不會施捨的 NPC（師父、本派自己人、no_beg）不列「乞討」（灰掉的一行只是雜訊；指令「乞討」仍回 cant_beg）
		if why != R_HIDE_BEG and why != "cant_beg":
			out["beg"] = { "ok": why == "", "reason": why, "left_s": beg_left_real_s(s, npc_id) }
	if "BETRAY" in services and str(ch.sect) != "" and npc_sect(npc_id) == str(ch.sect):
		out["betray"] = true
	if "JAIL" in services:
		out["jail"] = { "prisoners": prisoners_in(jail_room_of_npc(npc_id)), "ransom": _opt_int("jail_ransom", 100000) }
	if "TRIAL" in services:
		var tr: Variant = row.get("trial", {})
		if tr is Dictionary:
			var why := check_reqs(tr.get("requires", []), s)
			if why == "":
				why = trial_party_check(s, tr)
			out["trial"] = { "name": trial_name(npc_id, tr), "party_min": int(tr.get("party_min", 1)),
				"party_max": int(tr.get("party_max", 99)), "ok": why == "", "reason": why }
	if "GUIDE" in services:
		var g: Variant = row.get("guide", {})
		if g is Dictionary:
			out["guide"] = { "room_name": host.room_name(str(g.get("to_room", ""))), "ok": check_reqs(g.get("requires", []), s) == "" }
	if "TEACH" in services:
		out["teach_blocked"] = can_teach(s, npc_id)
	return out

# ======================================================================== M3b：監獄一般化（M3B_PLAN §5.1.4）

## 房間的 jail_scope（jail: true 的房間；預設 SECT）；不是牢房回 ""
func room_scope(room_id: String) -> String:
	var r := host.index.room(room_id)
	if not bool(r.get("jail", false)):
		return ""
	return SCOPE_CAPITAL if str(r.get("jail_scope", SCOPE_SECT)) == SCOPE_CAPITAL else SCOPE_SECT

## 生效資料裡的京城監獄（jail_scope CAPITAL；lint 保證最多一間），沒有回 ""
func capital_jail_room() -> String:
	var ids: Array = host.index.rooms.keys()
	ids.sort()
	for rid in ids:
		if room_scope(str(rid)) == SCOPE_CAPITAL:
			return str(rid)
	return ""

## 伺服器選項 jail_location（AUTO／SECT／CAPITAL）解析成「被捉拿的公敵」實際關的 SECT 或 CAPITAL（O12）：
## AUTO = 京城監獄房間生效時用 CAPITAL，否則 SECT；CAPITAL 但沒有京城監獄（1.0A 世界）也退回 SECT。
## 違反門規另看 breach_jail_resolved（AUTO 不送京城）
func jail_location_resolved() -> String:
	var opt := str(host.options.get("jail_location", JAIL_AUTO))
	if opt == SCOPE_SECT:
		return SCOPE_SECT
	return SCOPE_CAPITAL if capital_jail_room() != "" else SCOPE_SECT

## 本派有沒有執法者（規則開著才算）：CAPITAL 模式下違反門規要有執法者才坐牢（O12）
func has_enforcer(sect_id: String) -> bool:
	if host.rules.get("jail_enabled", true) == false:
		return false
	var row := sect_row(sect_id)
	return not row.is_empty() and bool(row.get("enforcer", false))

## 違反門規關哪裡（M3b 審查修正）：只有選項明寫 CAPITAL 且京城監獄生效時才關京城監獄；
## AUTO／SECT 都維持 1.0A【已證實】的各派思過處。官方「門派監獄」頁沒寫監獄在京城、也沒寫取代思過處【待考證】，
## 所以 AUTO 只把「被捉拿的公敵」（1.0B 捉拿公敵，jail_location_resolved）送京城監獄【設計提案】
func breach_jail_resolved() -> String:
	if str(host.options.get("jail_location", JAIL_AUTO)) == SCOPE_CAPITAL and capital_jail_room() != "":
		return SCOPE_CAPITAL
	return SCOPE_SECT

## 這一派、這個原因（BREACH 違反門規／ENEMY 公敵被抓）要關到哪一間牢房；"" = 不能關（→ BAN）
func jail_room_for(sect_id: String, reason: String) -> String:
	if host.rules.get("jail_enabled", true) == false:
		return ""
	if reason == "ENEMY":
		if jail_location_resolved() == SCOPE_CAPITAL:
			return capital_jail_room()
	elif breach_jail_resolved() == SCOPE_CAPITAL:
		return capital_jail_room() if has_enforcer(sect_id) else ""
	return str(sect_row(sect_id).get("jail_room", "")) if can_jail_in(sect_id) else ""

## jail_in／jail_out 的京城監獄變體模板（<key>_capital）；沒有模板時退回原 key
func _scope_key(key: String, scope: String) -> String:
	if scope != SCOPE_CAPITAL:
		return key
	var k2 := key + "_capital"
	return k2 if host.tables.get("text_templates", {}).has(k2) else key

# ======================================================================== M3b：位階與聚會（M3B_PLAN §5.1.1）

## 生效的 sect_ranks 列，依 rank 排序
func rank_rows(sect_id: String) -> Array:
	return Character.sect_rank_rows(host.tables, sect_id)

func rank_row(sect_id: String, rank: int) -> Dictionary:
	for r in rank_rows(sect_id):
		if int(r.get("rank", -1)) == rank:
			return r
	return {}

func rank_name(sect_id: String, rank: int) -> String:
	return str(rank_row(sect_id, rank).get("name", ""))

## 拜入時的位階：promote JOIN 的列；沒有位階表 0
func join_rank(sect_id: String) -> int:
	for r in rank_rows(sect_id):
		if str(r.get("promote", "")) == PROMOTE_JOIN:
			return int(r.get("rank", 0))
	return 0

## 這一派生效列中最大的 rank（1.0B 世界的丐幫 = 2）
func max_rank(sect_id: String) -> int:
	var m := 0
	for r in rank_rows(sect_id):
		m = maxi(m, int(r.get("rank", 0)))
	return m

## 有位階表的門派（依 id 排序）
func ranked_sects() -> Array:
	var out: Array = []
	var sects: Dictionary = host.tables.get("sects", {})
	var ids: Array = sects.keys()
	ids.sort()
	for sid in ids:
		if not rank_rows(str(sid)).is_empty():
			out.append(str(sid))
	return out

## 任務獎勵 sect_rank（§4.9）：assembly → 記待升（等聚會）；否則立即 _promote
func queue_rank(s: Session, sect_id: String, rank: int) -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	if str(ch.sect) != sect_id or rank <= int(ch.sect_rank):
		return
	var row := rank_row(sect_id, rank)
	if row.is_empty():
		return
	if bool(row.get("assembly", false)):
		var pend: Dictionary = ch.sect_rank_pending
		if str(pend.get("sect", "")) == sect_id and int(pend.get("rank", 0)) >= rank:
			return
		ch.sect_rank_pending = { "sect": sect_id, "rank": rank, "since_world_s": host.now_s() }
		_rank_wait(s, sect_id, rank, "assembly")
		s.sheet_dirty = true
		return
	_promote(ch, sect_id, rank, s)

## 升到 rank 的阻礙："" ／ requires（requires 不成立）／ cost（不夠扣）／ bad（不是本派、沒有這一列）
func promote_block(ch, sect_id: String, rank: int, s: Session = null) -> String:
	if ch == null or str(ch.sect) != sect_id:
		return "bad"
	var row := rank_row(sect_id, rank)
	if row.is_empty():
		return "bad"
	var reqs: Variant = row.get("requires", [])
	if reqs is Array and not (reqs as Array).is_empty():
		var ctx := req_ctx(s) if s != null else {}
		if Requirements.check(reqs, ch, host.tables, host.options, host.rules, ctx) != "":
			return "requires"
	var cost: Variant = row.get("cost", {})
	if cost is Dictionary:
		if int(ch.fame) < int(cost.get("fame", 0)) or int(ch.lilian) < int(cost.get("lilian", 0)) \
				or int(ch.money) < int(cost.get("money", 0)):
			return "cost"
	return ""

## 再檢查 requires、扣 cost、sect_rank = rank、清待升、事件（自己＋同派在線 other）。回傳是否升了
func _promote(ch, sect_id: String, rank: int, s: Session = null) -> bool:
	if s == null and ch != null:
		s = host.session_for_char(str(ch.id))
	var why := promote_block(ch, sect_id, rank, s)
	if why != "":
		if s != null and why != "bad":
			_rank_wait(s, sect_id, rank, why)
		return false
	var cost: Variant = rank_row(sect_id, rank).get("cost", {})
	if cost is Dictionary:
		ch.fame = int(ch.fame) - int(cost.get("fame", 0))
		ch.lilian = maxi(0, int(ch.lilian) - int(cost.get("lilian", 0)))
		ch.add_money(-int(cost.get("money", 0)))
	ch.sect_rank = rank
	var pend: Dictionary = ch.sect_rank_pending
	if str(pend.get("sect", "")) == sect_id and int(pend.get("rank", 0)) <= rank:
		ch.sect_rank_pending = {}
	ch.add_sect_history(sect_id, "RANK_%d" % rank)
	if s != null:
		var p := { "name": str(ch.name), "peer": s.peer_id, "sect_name": sect_name(sect_id), "rank_name": rank_name(sect_id, rank),
			"rank": rank }
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SECT_RANK_UP, p)
		for o in host.sessions():
			if o != s and o.character != null and str(o.character.sect) == sect_id:
				host.ws.queue_event(o.peer_id, Protocol.CH_SYSTEM, Protocol.E_SECT_RANK_UP, p.duplicate())
		s.sheet_dirty = true
	else:
		host.save_char(ch)
	return true

func _rank_wait(s: Session, sect_id: String, rank: int, reason: String) -> void:
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_RANK_WAIT, { "sect_name": sect_name(sect_id),
		"rank_name": rank_name(sect_id, rank), "reason": reason, "reason_text": str(RANK_WAIT_TEXT.get(reason, reason)) })

## 聚會模式（選項 gb_assembly；O8）
func assembly_mode() -> String:
	return ASSEMBLY_MONTHLY if str(host.options.get("gb_assembly", ASSEMBLY_DAILY)) == ASSEMBLY_MONTHLY else ASSEMBLY_DAILY

## 世界時間 now 之前（含）最近一次聚會的遊戲日：DAILY = 今天（遊戲日 d 的辰時 = 世界時間 (d−1) × 日長，
## 因為新世界從第 1 日辰時開始，WorldClock.START_SHICHEN）；MONTHLY = 最近的 day % 30 == 1
func last_assembly_day(now: float) -> int:
	var day_len := maxf(day_s(), 12.0)
	var d := floori(maxf(now, 0.0) / day_len) + 1
	if assembly_mode() == ASSEMBLY_MONTHLY:
		d -= posmod(d - 1, 30)
	return maxi(1, d)

func assembly_time_of_day(d: int) -> float:
	return float(d - 1) * maxf(day_s(), 12.0)

## 開服：world 還沒有聚會紀錄（新世界、舊世界第一次）→ 記成「最近一次已經聚過」，從下一次聚會算起
func init_assembly(now: float) -> void:
	var w: Dictionary = host.ws.world
	if not w.has(ASSEMBLY_LAST_DAY_KEY):
		var d := last_assembly_day(now)
		w[ASSEMBLY_LAST_DAY_KEY] = d
		w[ASSEMBLY_LAST_S_KEY] = assembly_time_of_day(d)

## 每次換時辰、每分鐘（含 debug 快轉）：最近一次聚會還沒舉行過 → 舉行（同一遊戲日只聚一次）
func assembly_tick(now_world_s: float) -> void:
	var w: Dictionary = host.ws.world
	if not w.has(ASSEMBLY_LAST_DAY_KEY):
		init_assembly(now_world_s)
		return
	var d := last_assembly_day(now_world_s)
	if d <= int(w.get(ASSEMBLY_LAST_DAY_KEY, 0)):
		return
	hold_assembly(d)

## 舉行一次聚會（debug assembly_now 也呼叫）：記下日與時刻 → 每個有位階表的門派，在線弟子：
## 有待升 → _promote；AUTO 列 requires 成立 → 升一級（每次最多一級）
func hold_assembly(day: int = -1) -> void:
	var w: Dictionary = host.ws.world
	if day < 0:
		day = last_assembly_day(host.now_s())
	w[ASSEMBLY_LAST_DAY_KEY] = day
	w[ASSEMBLY_LAST_S_KEY] = host.now_s()
	for sid in ranked_sects():
		var gate := str(sect_row(sid).get("gate_room", ""))
		for o in host.sessions():
			if o.character == null or str(o.character.sect) != sid:
				continue
			host.tell(o, Protocol.CH_SYSTEM, Protocol.E_SECT_ASSEMBLY,
				{ "sect_name": sect_name(sid), "room_name": host.room_name(gate) if gate != "" else "" })
			_assembly_for(o)

func _assembly_for(s: Session) -> void:
	var ch = s.character
	var sid := str(ch.sect)
	var pend: Dictionary = ch.sect_rank_pending
	if str(pend.get("sect", "")) == sid and int(pend.get("rank", 0)) > int(ch.sect_rank):
		_promote(ch, sid, int(pend["rank"]), s)
		return
	if not pend.is_empty() and str(pend.get("sect", "")) != sid:
		ch.sect_rank_pending = {}   # 換了門派的舊待升作廢
	var nxt := rank_row(sid, int(ch.sect_rank) + 1)
	if not nxt.is_empty() and str(nxt.get("promote", "")) == PROMOTE_AUTO and promote_block(ch, sid, int(nxt["rank"]), s) == "":
		_promote(ch, sid, int(nxt["rank"]), s)

## 登入：錯過了至少一次聚會（待升之後有聚會）→ 補升
func on_login(s: Session) -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	var pend: Dictionary = ch.sect_rank_pending
	if pend.is_empty():
		return
	if str(pend.get("sect", "")) != str(ch.sect):
		ch.sect_rank_pending = {}
		return
	var last_s := float(host.ws.world.get(ASSEMBLY_LAST_S_KEY, -1.0))
	if last_s > float(pend.get("since_world_s", 0.0)):
		_promote(ch, str(ch.sect), int(pend.get("rank", 0)), s)

## RANK 服務的選單資料：{ sect_name, level, name, pending, rows: [ { rank, name, current, reached, requires_text, quest, quest_name,
## cost_text, promote, assembly } ], assembly_mode, assembly_text }
func rank_menu(s: Session) -> Dictionary:
	var ch = s.character if s != null else null
	var sid := str(ch.sect) if ch != null else ""
	var rows: Array = []
	for r in rank_rows(sid):
		var rk := int(r.get("rank", 0))
		var texts: Array = []
		for c in r.get("requires", []):
			if c is Dictionary:
				texts.append(Requirements.describe(c, host.tables))
		var cost: Variant = r.get("cost", {})
		var ct: PackedStringArray = []
		if cost is Dictionary:
			for k in ["fame", "lilian", "money"]:
				if int(cost.get(k, 0)) > 0:
					ct.append("%s %d" % [{ "fame": "名聲", "lilian": "歷練", "money": "銀兩" }[k], int(cost[k])])
		var qid := str(r.get("quest", ""))
		rows.append({ "rank": rk, "name": str(r.get("name", "")), "current": ch != null and rk == int(ch.sect_rank),
			"reached": ch != null and rk <= int(ch.sect_rank), "requires_text": texts,
			"quest": qid, "quest_name": host.quest_name(qid) if qid != "" else "",
			"cost_text": "、".join(ct), "promote": str(r.get("promote", "")), "assembly": bool(r.get("assembly", false)) })
	var sheet: Variant = ch.rank_sheet(host.tables) if ch != null else null
	return { "sect_name": sect_name(sid), "level": int(ch.sect_rank) if ch != null else 0,
		"name": rank_name(sid, int(ch.sect_rank)) if ch != null else "",
		"pending": sheet.get("pending") if sheet is Dictionary else null, "rows": rows,
		"assembly_mode": assembly_mode(),
		"assembly_text": "每月初一辰時在總舵聚會" if assembly_mode() == ASSEMBLY_MONTHLY else "每日辰時在總舵聚會" }

# ======================================================================== M3b：乞討（門派技能行動練習，M3B_PLAN §5.1.2）

## 本派的 practice（沒有回 {}）
func practice_of(sect_id: String) -> Dictionary:
	var p: Variant = sect_row(sect_id).get("practice", null)
	return p if p is Dictionary else {}

## 這位 NPC 能不能乞討（不看冷卻與精神）："" 或 cant_beg
func _beggable(npc_id: String, pr: Dictionary) -> String:
	var row := host.npc_row(npc_id)
	if row.is_empty() or bool(row.get("no_beg", false)):
		return Protocol.R_CANT_BEG
	var kind := str(row.get("kind", ""))
	var kinds: Variant = pr.get("npc_kinds", DEFAULT_BEG_KINDS)
	if not (kinds is Array) or (kinds as Array).is_empty():
		kinds = DEFAULT_BEG_KINDS
	if kind in NO_BEG_KINDS or not (kind in kinds):
		return Protocol.R_CANT_BEG
	return ""

func _beg_cd(ch) -> Dictionary:
	var cd: Variant = ch.counters.get(BEG_CD_KEY, {})
	if not (cd is Dictionary):
		cd = {}
	ch.counters[BEG_CD_KEY] = cd
	return cd

## 對這位 NPC 的乞討冷卻還剩幾秒（真實秒；0 = 可以）
func beg_left_real_s(s: Session, npc_id: String) -> float:
	if s == null or s.character == null:
		return 0.0
	var until := float(_beg_cd(s.character).get(npc_id, 0.0))
	return maxf(0.0, host.real_span(until - host.now_s()))

## 乞討的驗證（§5.1.2 的順序，前三步由 GameHost 做）：no_practice → npc_not_here → cant_beg → beg_cooldown
## → not_enough_jing／not_enough_shen；全部通過回 ""
func beg_reason(s: Session, npc_id: String) -> String:
	var ch = s.character
	var pr := practice_of(str(ch.sect))
	if pr.is_empty():
		return Protocol.R_NO_PRACTICE
	if host.npc_here(s, npc_id) != "":
		return "npc_not_here"
	var why := _beggable(npc_id, pr)
	if why != "":
		return why
	if float(_beg_cd(ch).get(npc_id, 0.0)) > host.now_s():
		return Protocol.R_BEG_COOLDOWN
	var cost: Variant = pr.get("cost", {})
	if cost is Dictionary:
		for k in ["jing", "shen", "neili"]:
			if int(cost.get(k, 0)) > 0 and int(ch.vitals.get(k, 0)) < int(cost[k]):
				return "not_enough_" + k
	return ""

## beg intent：成功扣精神、門派技能熟練 +prof、擲施捨、事件 beg（自己＋同房間 other）。不受 teach_requires（善惡）限制
func beg(s: Session, npc_id: String) -> Dictionary:
	var why := beg_reason(s, npc_id)
	if why != "":
		var r := GameHost.fail(why)
		if why == Protocol.R_BEG_COOLDOWN:
			r["left_s"] = maxi(1, ceili(beg_left_real_s(s, npc_id) - 1e-6))
		return r
	var ch = s.character
	var sid := str(ch.sect)
	var pr := practice_of(sid)
	var cost: Variant = pr.get("cost", {})
	if cost is Dictionary:
		for k in ["jing", "shen", "neili"]:
			if int(cost.get(k, 0)) > 0:
				ch.vitals[k] = maxi(0, int(ch.vitals.get(k, 0)) - int(cost[k]))
	_beg_cd(ch)[npc_id] = host.now_s() + float(pr.get("per_npc_cd_s", 600))
	# 熟練：randi_range(prof)；門派技能上限照 GameHost.skill_cap（門派 cap 與實戰上限）
	var ss := str(sect_row(sid).get("sect_skill", ""))
	var gain := 0
	if ss != "":
		var pv: Variant = pr.get("prof", [3, 6])
		var lo := 1
		var hi := 1
		if pv is Array and (pv as Array).size() >= 2:
			lo = maxi(0, int(pv[0]))
			hi = maxi(lo, int(pv[1]))
		elif typeof(pv) in [TYPE_INT, TYPE_FLOAT]:
			lo = int(pv)
			hi = lo
		gain = host.rng.randi_range(lo, hi)
		var before: int = ch.skills.level(ss)
		var pb: int = ch.skills.prof(ss)
		var res: Dictionary = ch.skills.add_prof(ss, gain, host.tables, host.skill_cap(ch, ss))
		gain = int(ch.skills.prof(ss)) - pb
		host.npcs.skill_up_event(s, ss, before, int(res.get("after", before)))
	# 施捨：依序擲，最多給一樣（銀兩或物品）
	var money := 0
	var item_id := ""
	var item_n := 0
	for a in pr.get("alms", []):
		if not (a is Dictionary) or host.rng.randf() >= float(a.get("chance", 0.0)):
			continue
		if a.has("money"):
			var mv: Variant = a["money"]
			var want := host.rng.randi_range(int(mv[0]), int(mv[1])) if mv is Array and (mv as Array).size() >= 2 else int(mv)
			money = ch.add_money(maxi(0, want))
		elif str(a.get("item", "")) != "" and host.tables.get("items", {}).has(str(a["item"])):
			var g: Dictionary = host.give_item(ch, str(a["item"]), maxi(1, int(a.get("n", 1))))
			if g.get("ok", false):
				item_id = str(a["item"])
				item_n = maxi(1, int(a.get("n", 1)))
		break
	var alms := ""
	if money > 0:
		alms = "，得了 %d 兩" % money
	elif item_id != "":
		alms = "，得了%s" % host.item_name(item_id)
	var p := { "name": str(ch.name), "peer": s.peer_id, "npc_name": host.npc_name(npc_id), "gain_prof": gain,
		"money": money, "item_name": host.item_name(item_id) if item_id != "" else "", "alms_text": alms,
		"skill_name": host.skill_name(ss) if ss != "" else "" }
	host.tell(s, Protocol.CH_SCENE, Protocol.E_BEG, p)
	host.ws.queue_room_event(s.room_id(), Protocol.CH_SCENE, Protocol.E_BEG, p.duplicate(), s.peer_id)
	if item_id != "":
		host.item_gain_event(s, item_id, item_n)
	s.sheet_dirty = true
	return GameHost.ok({ "gain_prof": gain, "money": money, "item": item_id })

# ======================================================================== M3b：小黃追咬（M3B_PLAN §5.1.3）

## 走進房間後：本派 harass 規則（地區機率）→ 開 HARASS 戰。回傳是否開戰
func harass(s: Session, room_id: String) -> bool:
	if s == null or s.character == null or s.battle_id != 0:
		return false
	var ch = s.character
	var rules_v: Variant = sect_row(str(ch.sect)).get("harass", [])
	if not (rules_v is Array) or (rules_v as Array).is_empty():
		return false
	if not harass_room_ok(room_id):
		return false
	var cid := str(ch.id)
	if _harass_at.has(cid) and ch.online_s - float(_harass_at[cid]) < HARASS_THROTTLE_S and float(_harass_at[cid]) <= ch.online_s:
		return false
	var region := host.index.region_of(room_id)
	for rule in rules_v:
		if not (rule is Dictionary):
			continue
		var regs: Variant = rule.get("regions", {})
		if not (regs is Dictionary) or not (regs as Dictionary).has(region):
			continue
		var unless: Variant = rule.get("unless", [])
		if unless is Array and not (unless as Array).is_empty() \
				and Requirements.ok(unless, ch, host.tables, host.options, host.rules, req_ctx(s)):
			continue
		if host.rng.randf() >= float(regs[region]):
			continue
		var mid := str(rule.get("monster", ""))
		if not host.tables.get("monsters", {}).has(mid):
			continue
		var cnt: Variant = rule.get("count", [1, 1])
		var lo := 1
		var hi := 1
		if cnt is Array and (cnt as Array).size() >= 2:
			lo = maxi(1, int(cnt[0]))
			hi = maxi(lo, int(cnt[1]))
		var n := host.rng.randi_range(lo, hi)
		var ids: Array = []
		for i in n:
			ids.append(mid)
		_harass_at[cid] = ch.online_s
		host.tell(s, Protocol.CH_BATTLE, _harass_key(str(ch.sect), rule),
			{ "monster_name": host.monster_name(mid), "n": n, "sect_name": sect_name(str(ch.sect)), "name": str(ch.name) })
		start_battle(s, ids, BATTLE_HARASS, { "no_flee": false, "pull_party": false })
		return true
	return false

## 只在街道類房間：不是 safe／牢房、沒有 INN／BANK／SHOP 的 NPC（室內）
func harass_room_ok(room_id: String) -> bool:
	var room := host.index.room(room_id)
	if room.is_empty() or bool(room.get("safe", false)) or bool(room.get("jail", false)):
		return false
	for nid in host.index.npcs_in(room_id):
		for svc in host.npc_row(str(nid)).get("services", []):
			if str(svc) in HARASS_INDOOR_SERVICES:
				return false
	return true

## 追咬的事件 key：規則的 text → harass_<門派 prefix>（gaibang 碎片的 harass_gb）→ harass
func _harass_key(sect_id: String, rule: Dictionary) -> String:
	var tt: Dictionary = host.tables.get("text_templates", {})
	var k := str(rule.get("text", ""))
	if k != "" and tt.has(k):
		return k
	var k2 := "harass_" + str(sect_row(sect_id).get("prefix", ""))
	return k2 if tt.has(k2) else Protocol.E_HARASS

# ======================================================================== M3b：捉拿公敵（M3B_PLAN §5.1.5，1.0B）

func era_on(era: String) -> bool:
	return GameData.enabled_eras.has(era)

func seize_enabled() -> bool:
	return host.options.get("seize_enabled", true) != false

## o 是不是 viewer 的本派公敵（player_tags.seizable；不檢查地點、新手）
func seizable(viewer: Session, o: Session) -> bool:
	if viewer == null or o == null or viewer == o or viewer.character == null or o.character == null:
		return false
	if not era_on(ERA_1_0B) or not seize_enabled():
		return false
	var sid := str(viewer.character.sect)
	return sid != "" and o.character.sect_enemies.has(sid)

## seize_enemy 的驗證（前三步由 GameHost 做）：era_locked → seize_disabled → no_sect → not_here → not_enemy
## → target_newbie_protected → no_pk_here → target_busy；通過回 [""、目標 Session]
func seize_check(s: Session, target_name: String) -> Array:
	if not era_on(ERA_1_0B):
		return [Protocol.R_ERA_LOCKED, null]
	if not seize_enabled():
		return [Protocol.R_SEIZE_DISABLED, null]
	var ch = s.character
	var sid := str(ch.sect)
	if sid == "":
		return ["no_sect", null]
	var t: Session = host.session_for_char_name(target_name)
	if t == null or t == s or t.character == null or t.room_id() != s.room_id():
		return ["not_here", null]
	if not t.character.sect_enemies.has(sid):
		return [Protocol.R_NOT_ENEMY, t]
	# M3c 第三輪審查：身上有神兵的新手不受保護（PkSystem.newbie_protected；PK 系統不在時照舊只看實戰）
	var newbie := int(t.character.combat_xp) < int(host.options.get("newbie_pk_protect_xp", 500))
	if host.get("pk") != null and host.pk.has_method("newbie_protected"):
		newbie = bool(host.pk.newbie_protected(t.character))
	if newbie:
		return [Protocol.R_TARGET_NEWBIE_PROTECTED, t]
	var region := host.index.region_of(s.room_id())
	var pk_ok := bool(host.tables.get("regions", {}).get(region, {}).get("pk_allowed", false))
	if not pk_ok and region != str(sect_row(sid).get("gate_region", "")):
		return [Protocol.R_NO_PK_HERE, t]
	if t.battle_id != 0 or t.character.is_jailed():
		return [Protocol.R_TARGET_BUSY, t]
	return ["", t]

## 捉拿公敵：開 SEIZE 的 PvP（拉本隊同房閒置隊友；目標不拉隊友；目標可逃）。抓的人不加 PK 值、殺氣、善惡（PkSystem 處理）
func seize(s: Session, target_name: String) -> Dictionary:
	var chk := seize_check(s, target_name)
	if str(chk[0]) != "":
		return GameHost.fail(str(chk[0]))
	var t: Session = chk[1]
	var sid := str(s.character.sect)
	var b = host.battles
	if b == null or not (b as Object).has_method("start_pvp"):
		return GameHost.fail("bad_cmd")
	var room := s.room_id()
	var bid := int(b.start_pvp(s, t, BATTLE_SEIZE, { "pull_party": true, "seize_sect": sid }))
	if bid == 0:
		return GameHost.fail(Protocol.R_TARGET_BUSY)
	var p := { "atk_name": str(s.character.name), "def_name": str(t.character.name), "atk_peer": s.peer_id,
		"def_peer": t.peer_id, "sect_name": sect_name(sid) }
	host.ws.queue_room_event(room, Protocol.CH_SCENE, Protocol.E_SEIZE_START, p)
	s.sheet_dirty = true
	t.sheet_dirty = true
	return GameHost.ok({ "battle_id": bid })

## PkSystem.on_pvp_end 的 SEIZE 分支：被抓的公敵（已由 capture_on_death 關押）→ 全服 seize_done
func on_seize_end(summary: Dictionary) -> void:
	var units: Array = summary.get("units", [])
	var sid := str(summary.get("seize_sect", ""))
	for v in units:
		if not (v is Dictionary) or not bool(v.get("died", false)):
			continue
		var o: Session = host.session_for_char(str(v.get("char_id", "")))
		var ch = o.character if o != null else null
		if ch == null or not ch.is_jailed() or str(ch.jail.get("reason", "")) != "ENEMY":
			continue
		var by := host.pvp_char_name(str(v.get("killed_by_char", "")))
		host.ws.broadcast_event(Protocol.CH_SYSTEM, Protocol.E_SEIZE_DONE,
			{ "name": str(ch.name), "sect_name": sect_name(sid if sid != "" else str(ch.jail.get("sect", ""))), "by_name": by,
				"room_name": host.room_name(str(ch.jail.get("room", ""))) })

## 房間 players[] 的 M3b 標記（RegionSystem.player_entry 合併）
func player_tags(viewer: Session, o: Session) -> Dictionary:
	return { "seizable": seizable(viewer, o) }


# ==== M3c2 WP-PACE ====
## M3C2_PLAN §2.3.3：切磋獎勵。十派切磋弟子（m_<派>_dizi、m_hs_trainee；資料 no_rewards false、combat_xp、learn_points）打贏時
## 由 BattleSystem 照 BattleRewards 發實戰與學點（BattleSystem 凍結在本包之外），這裡在 on_battle_settled 依規則收回：
## - 規則 spar_rewards 關 → 實戰、學點全部收回（送 ch_spar_rule）；
## - 本遊戲日已領 spar_daily_cap 場 → 全部收回（送 ch_spar_capped）；沒超過 → counters.spar_day.n += 1；
## - 學點另受「最高本派武功 < novice_learn_below」限制（實戰不受；收回學點時送 ch_no_lp why novice）。
## 收回的量：用 BattleRewards.xp_for／lp_for 從戰後實戰反推戰前實戰（固定點；隊伍分成 1/√n 依序試 n = 1…8）。
## M3C2_PLAN 缺漏：更乾淨的做法是 BattleSystem 在 apply_rewards 之前呼叫 spar_adjust() 改寫獎勵（交整合者決定；
## 有呼叫時 on_battle_settled 不再收回，見 _spar_pre）。
const SPAR_DAY_KEY := "spar_day"
const SPAR_DEFAULT_CAP := 30
## char_id -> true：這場的獎勵已由 spar_adjust() 在發放前處理過
var _spar_pre: Dictionary = {}

## 切磋弟子的怪物列 id？（純邏輯在 Learning.is_spar_monster，balance_sim 共用）
static func is_spar_monster(mid: String) -> bool:
	return Learning.is_spar_monster(mid)

func spar_cap() -> int:
	return clampi(_opt_int("spar_daily_cap", SPAR_DEFAULT_CAP), 0, 200)

## 本遊戲日的切磋計數（換日重設；就地寫回 counters）
func spar_day(ch) -> Dictionary:
	var today := int(host.clock().get("day", 0))   # M3c2 整合：子時換日（同 QuestSystem.day_index）
	var sd: Variant = ch.counters.get(SPAR_DAY_KEY, null)
	if not (sd is Dictionary) or CharData.to_int((sd as Dictionary).get("day", -1), -1) != today:
		sd = { "day": today, "n": 0 }
		ch.counters[SPAR_DAY_KEY] = sd
	return sd

## 這場切磋的處理結果：{ "xp": bool（實戰保留）, "lp": bool（學點保留）, "why": ""|"rule"|"capped"|"novice" }；
## count = true 時記一場（只有真的給了獎勵才記）
func spar_decide(ch, count: bool) -> Dictionary:
	if host.rules.get("spar_rewards", false) != true:
		return { "xp": false, "lp": false, "why": "rule" }
	var sd := spar_day(ch)
	if CharData.to_int(sd.get("n", 0)) >= spar_cap():
		return { "xp": false, "lp": false, "why": "capped" }
	if count:
		sd["n"] = CharData.to_int(sd.get("n", 0)) + 1
	if not Learning.is_novice(ch, host.tables, host.rules) or Learning.novice_lp_left(ch, host.rules) <= 0:
		return { "xp": true, "lp": false, "why": "novice" }
	return { "xp": true, "lp": true, "why": "" }

## 這場打倒的切磋弟子（怪物列）
func _spar_rows(kills: Variant) -> Array:
	var out: Array = []
	if not (kills is Array):
		return out
	var mons: Dictionary = host.tables.get("monsters", {})
	for k in kills:
		var mid := unit_monster(str(k))
		if is_spar_monster(mid) and mons.has(mid) and not bool(mons[mid].get("no_rewards", false)):
			out.append(mons[mid])
	return out

## 發放前鉤子（M3c2 整合：BattleSystem._settle_player 在 apply_rewards 之前呼叫）：就地改 r 的 combat_xp／learn_points。
## dead_refs：這場被打倒的全部怪物 ref（BattleRewards 對每位存活玩家都算全部死掉的怪）；share：1/√存活玩家數。
## 沒傳 dead_refs → 退回用 r.kills、share 1（舊呼叫法）
func spar_adjust(s: Session, ch, r: Dictionary, kind: String, dead_refs: Array = [], share := 1.0) -> void:
	if ch == null or kind != "FIGHT":
		return
	var rows := _spar_rows(dead_refs if not dead_refs.is_empty() else r.get("kills", []))
	if rows.is_empty():
		return
	_spar_pre[str(ch.id)] = true
	var x0 := int(ch.combat_xp)
	var d := spar_decide(ch, true)
	var xp := 0
	var lp := 0
	for row in rows:
		xp += BattleRewards.xp_for(row, x0, share)
		lp += BattleRewards.lp_for(row, x0, share)
	if not bool(d["xp"]):
		r["combat_xp"] = maxi(0, int(r.get("combat_xp", 0)) - xp)
	if not bool(d["lp"]):
		r["learn_points"] = maxi(0, int(r.get("learn_points", 0)) - lp)
	else:
		# M3c2 審查：一場最多 Learning.SPAR_LP_MAX；雜務＋切磋學點的一輩子上限（novice_lp_cap）
		var keep := mini(Learning.spar_lp(lp), Learning.novice_lp_left(ch, host.rules))
		r["learn_points"] = maxi(0, int(r.get("learn_points", 0)) - (lp - keep))
		Learning.note_novice_lp(ch, keep)
	_spar_tell(s, str(d["why"]))

## 戰後反推：戰後實戰 x1 → 戰前實戰與這幾隻切磋弟子給的 { xp, lp }；找不到一致的分成 → { ok: false }。
## prefer_n：先試的隊伍人數（同房間的隊友數＋自己）；實戰係數夾在上下限時不同人數都可能一致，所以先試最可能的那個
static func spar_given(rows: Array, x1: int, prefer_n := 1) -> Dictionary:
	var order: Array = [clampi(prefer_n, 1, 8)]
	for k in range(1, 9):
		if not (k in order):
			order.append(k)
	for n in order:
		var share := 1.0 / sqrt(float(n))
		var x0 := x1
		for _i in 12:
			var g := 0
			for row in rows:
				g += BattleRewards.xp_for(row, x0, share)
			x0 = maxi(0, x1 - g)
		var g2 := 0
		var l2 := 0
		for row in rows:
			g2 += BattleRewards.xp_for(row, x0, share)
			l2 += BattleRewards.lp_for(row, x0, share)
		if x0 + g2 == x1:
			return { "ok": true, "xp": g2, "lp": l2, "x0": x0, "n": n }
	return { "ok": false, "xp": 0, "lp": 0 }

func _spar_settle(s: Session, ch, summary: Dictionary) -> void:
	if ch == null or str(summary.get("kind", "")) != "FIGHT" or str(summary.get("result", "")) != "VICTORY":
		return
	var cid := str(ch.id)
	if _spar_pre.has(cid):
		_spar_pre.erase(cid)
		return
	var rows := _spar_rows(summary.get("kills", []))
	if rows.is_empty():
		return
	var d := spar_decide(ch, true)
	if bool(d["xp"]) and bool(d["lp"]):
		return
	var g := spar_given(rows, int(ch.combat_xp), _party_here(s))
	if not bool(g.get("ok", false)):
		push_warning("[SectSystem] spar reward rollback: no consistent split for %s" % cid)
		return
	if not bool(d["xp"]):
		ch.combat_xp = maxi(0, int(ch.combat_xp) - int(g["xp"]))
	if not bool(d["lp"]):
		ch.learn_points = maxi(0, int(ch.learn_points) - int(g["lp"]))
	else:
		var keep := mini(Learning.spar_lp(int(g["lp"])), Learning.novice_lp_left(ch, host.rules))
		ch.learn_points = maxi(0, int(ch.learn_points) - (int(g["lp"]) - keep))
		Learning.note_novice_lp(ch, keep)
	if s != null:
		s.sheet_dirty = true
	_spar_tell(s, str(d["why"]))

## 同房間的隊友數＋自己（切磋會把同房間的隊友拉進來；獎勵分成 1/√人數）
func _party_here(s: Session) -> int:
	if s == null:
		return 1
	var party = host.get("party")
	if party == null or not (party as Object).has_method("members_in_room"):
		return 1
	var n := 1
	for o in party.members_in_room(s):
		if o != null and o != s and o.character != null:
			n += 1
	return n

func _spar_tell(s: Session, why: String) -> void:
	if s == null:
		return
	match why:
		"capped":
			host.tell(s, Protocol.CH_SYSTEM, Protocol.E_CH_SPAR_CAPPED, {})
		"rule":
			host.tell(s, Protocol.CH_SYSTEM, "ch_spar_rule", {})
		"novice":
			var t: Variant = host.tables.get("text_templates", {}).get("ch_no_lp_novice", {})
			host.tell(s, Protocol.CH_SYSTEM, Protocol.E_CH_NO_LP, { "quest_name": "", "why": "novice",
				"text": str((t as Dictionary).get("self", "")) if t is Dictionary else "" })
