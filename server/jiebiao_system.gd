class_name JiebiaoSystem
extends RefCounted
## 劫鏢（危險鏢）主機端（M3D_PLAN §5.2；1.0B；研究 2001-11-15 設計文）。GameHost.jiebiao；GameHost 依 M3D_SYSTEMS 以路徑 load()。
##
## 押鏢方：鏢局二掌櫃（n_ev_jb_<城>）的 12 條危險鏢 q_ev_jb_*（任務 group "jiebiao"、列欄位 jiebiao { value, kind, from, to }）。
##   接鏢（QuestSystem.jb_on_accept）→ 扣押金＝鏢價、記 ext.jiebiao.active；ESCORT 送達 → 還押金＋鏢價（2 × 鏢價）、
##   名聲 +3（任務結局）、這位二掌櫃的不接鏢冷卻 30／60／120 分（世界秒）。失敗（任何戰鬥中逃走、死亡、被劫、
##   登出／斷線、放棄）→ 任務 fail、押金沒收。主機關閉不算失敗（存檔照留，登入時繼續）。
##   押鏢中進 WILD 房間：特殊地雷 15%（每 3 間最多一次）→ 劫匪 ×2–4（ENCOUNTER，拉隊友；逃走＝失敗）。
## 劫鏢方：rob_escort { target_char } → PvP 種類 ROB（BattleSystem 在 side 1 加鏢單位）；開戰當下每位 side 0 玩家劫鏢標記 1 小時
##   （守城官兵照 PK > 3 的人數追殺：WP-LAW 讀 JiebiaoRules.rob_marked）；劫鏢方不能逃；鏢單位倒下或押鏢者死亡／逃走＝劫鏢成功，
##   存活的劫鏢者平分 floor(鏢價 × 80%)；劫鏢算強制 PK：每位劫鏢者 PK值 +1（殺了押鏢者的那位已由 PkSystem 的 FORCED 結算加過，不重複）。
## 防刷（T9、§5.2.4）：押金是押鏢者自己的錢、分贓只是 80% 的押金 → 朋友互劫合計 −20%；送達的 +V 有冷卻擋連刷。

const RECONCILE_REAL_S := 1.0
const FAIL_REASON_KEY := "ev_jb_fail"      # 任務失敗的說明模板（QuestSystem._fail 的 reason_key）
const WHY_FLED := "fled"
const WHY_DIED := "died"
const WHY_ROBBED := "robbed"
const WHY_LOGOUT := "logout"
const WHY_ABANDON := "abandon"
const E_AMBUSH := "ev_jb_ambush"
const E_ROB_START := "ev_jb_rob_start"
const E_ROB_REPELLED := "ev_jb_rob_repelled"
const E_ROB_SHARE := "ev_jb_rob_share"
const E_ROB_MARKED := "ev_jb_rob_marked"

var host = null
var _acc := 0.0

func _init(p_host) -> void:
	host = p_host

# ---------------------------------------------------------------- 角色資料（ext.jiebiao）
## ext.jiebiao（不存在就建）：{ active: {quest, value, kind, from, to, since_s, giver, done_n, rooms_since}, cd: {npc: until_s}, rob_until_s }
static func data_of(ch) -> Dictionary:
	var e: Variant = ch.ext.get(JiebiaoRules.EXT_KEY, null)
	if not (e is Dictionary):
		e = {}
		ch.ext[JiebiaoRules.EXT_KEY] = e
	if not ((e as Dictionary).get("cd") is Dictionary):
		e["cd"] = {}
	return e

## 進行中的危險鏢（沒有回 {}）
static func active_of(ch) -> Dictionary:
	if ch == null:
		return {}
	var e: Variant = ch.ext.get(JiebiaoRules.EXT_KEY, null)
	if not (e is Dictionary):
		return {}
	var a: Variant = (e as Dictionary).get("active", null)
	return a if a is Dictionary and str((a as Dictionary).get("quest", "")) != "" else {}

func enabled() -> bool:
	return host.options.get("jiebiao_enabled", true) != false

## 1.0B 資料視圖（1.0A-only 世界看不到二掌櫃與危險鏢）
func era_on() -> bool:
	return host.tables.get("npcs", {}).has("n_ev_jb_xx")

func now_s() -> float:
	return float(host.now_s())

# ---------------------------------------------------------------- 接鏢（QuestSystem.jb_on_accept）
## 回 "" 或原因碼（回原因碼 → 任務不成立）：jiebiao_enabled → 已有進行中的危險鏢（jb_active）→ 冷卻（jb_cooldown）→ 押金（jb_no_deposit）
func on_accept(s: Session, qid: String) -> String:
	if s == null or s.character == null:
		return ""
	var row: Dictionary = host.tables.get("quests", {}).get(qid, {})
	var spec := JiebiaoRules.spec_of(row)
	if spec.is_empty():
		return ""
	var ch = s.character
	if not enabled():
		return Protocol.R_ERA_LOCKED
	if not active_of(ch).is_empty():
		return "jb_active"
	var why := JiebiaoRules.accept_reason(int(ch.combat_xp), int(ch.fame), int(ch.lilian), str(ch.sect))
	if why != "":
		return why
	var d := data_of(ch)
	var giver := str(row.get("giver", ""))
	if float((d["cd"] as Dictionary).get(giver, 0.0)) > now_s():
		return "jb_cooldown"
	var value := int(spec["value"])
	if int(ch.money) < value:
		return "jb_no_deposit"
	ch.money = int(ch.money) - value
	d["active"] = { "quest": qid, "value": value, "kind": str(spec["kind"]), "from": str(spec["from"]), "to": str(spec["to"]),
		"since_s": now_s(), "giver": giver, "done_n": QuestState.done_count(ch.quests, qid),
		"rooms_since": JiebiaoRules.MINE_GAP_ROOMS }
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_EV_JB_STARTED, { "value": value, "why": "",
		"kind_name": kind_name(str(spec["kind"])), "label": kind_name(str(spec["kind"])), "to_name": host.region_name(str(spec["to"])) })
	s.sheet_dirty = true
	_mark_room(s)
	return ""

static func kind_name(kind: String) -> String:
	return "護送鏢" if kind == JiebiaoRules.KIND_HU else "送貨鏢"

## QuestSystem.jb_on_fail（_fail 與 abandon；任務還在 active 裡）：押金沒收、清 active、ev_jb_failed
func on_quest_fail(s: Session, qid: String, why: String) -> void:
	if s == null or s.character == null:
		return
	var a := active_of(s.character)
	if a.is_empty() or str(a.get("quest", "")) != qid:
		return
	_clear(s, a, why if why != "" else WHY_ABANDON)

func _clear(s: Session, a: Dictionary, why: String) -> void:
	var d := data_of(s.character)
	d.erase("active")
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_EV_JB_FAILED, { "value": int(a.get("value", 0)), "why": why,
		"why_text": why_text(why), "reason_text": why_text(why) })
	s.sheet_dirty = true
	_mark_room(s)

static func why_text(why: String) -> String:
	match why:
		WHY_FLED:
			return "臨陣脫逃"
		WHY_DIED:
			return "人倒鏢失"
		WHY_ROBBED:
			return "鏢被劫走"
		WHY_LOGOUT:
			return "中途離開江湖"
		WHY_ABANDON:
			return "放棄押鏢"
	return why

## 讓危險鏢失敗（逃走、死亡、被劫、登出）：先清 active（QuestSystem 的 jb_on_fail 回呼時就不會重複），再讓任務 fail
func fail_active(s: Session, why: String) -> void:
	if s == null or s.character == null:
		return
	var a := active_of(s.character)
	if a.is_empty():
		return
	var qid := str(a.get("quest", ""))
	_clear(s, a, why)
	if host.quests != null and QuestState.is_active(s.character.quests, qid):
		host.quests._fail(s, qid, FAIL_REASON_KEY)

# ---------------------------------------------------------------- 送達（惰性對帳）
## active 的任務已經不在進行中：完成次數變多＝送達（付 2 × 鏢價、冷卻）；否則＝失敗（鉤子沒接到時的保險）。
## 任務還在進行中但 active 不見了（舊存檔、鉤子缺席）不處理：送達時沒有押金紀錄就不付錢（不會憑空生錢）
func reconcile(s: Session) -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	var a := active_of(ch)
	if a.is_empty():
		return
	var qid := str(a.get("quest", ""))
	if QuestState.is_active(ch.quests, qid):
		return
	if QuestState.done_count(ch.quests, qid) > int(a.get("done_n", 0)):
		_succeed(s, a)
	else:
		_clear(s, a, WHY_ABANDON)

func _succeed(s: Session, a: Dictionary) -> void:
	var ch = s.character
	var d := data_of(ch)
	d.erase("active")
	var value := int(a.get("value", 0))
	var got := int(ch.add_money(JiebiaoRules.payout(value)))
	var giver := str(a.get("giver", ""))
	if giver != "":
		(d["cd"] as Dictionary)[giver] = now_s() + JiebiaoRules.cooldown_s(host.rng.randf())
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_EV_JB_DONE, { "value": value, "why": "", "money": got })
	s.sheet_dirty = true
	_mark_room(s)
	host.save_char(ch)

# ---------------------------------------------------------------- GameHost 分派
func tick(dt: float) -> void:
	_acc += float(host.real_span(dt)) if host.has_method("real_span") else dt
	if _acc < RECONCILE_REAL_S:
		return
	_acc = 0.0
	for s in host.sessions():
		if s.character != null and s.battle_id == 0 and not active_of(s.character).is_empty():
			reconcile(s)

func on_login(s: Session) -> void:
	reconcile(s)
	if s != null and s.character != null and not active_of(s.character).is_empty():
		_mark_room(s)

## 登出／斷線（換角也算）：危險鏢失敗（主機關閉不經過這裡 → 不算失敗）
func on_logout(s: Session) -> void:
	if s == null or s.character == null:
		return
	reconcile(s)
	if not active_of(s.character).is_empty():
		fail_active(s, WHY_LOGOUT)

## 走進房間：先對帳（送達）；押鏢中的 WILD 房間擲特殊地雷
func on_enter_room(s: Session, _from: String, to: String) -> void:
	if s == null or s.character == null:
		return
	reconcile(s)
	var a := active_of(s.character)
	if a.is_empty() or s.battle_id != 0 or s.character.is_jailed():
		return
	var region := str(host.index.region_of(to))
	if str(host.tables.get("regions", {}).get(region, {}).get("type", "")) != "WILD":
		return
	if bool(host.index.room(to).get("safe", false)):
		return
	a["rooms_since"] = int(a.get("rooms_since", 0)) + 1
	if not JiebiaoRules.mine_hits(int(a["rooms_since"]), host.rng.randi_range(0, 99)):
		return
	if not host.tables.get("monsters", {}).has(JiebiaoRules.BANDIT_ID):
		return
	a["rooms_since"] = 0
	var n := JiebiaoRules.bandit_count(host.rng.randf())
	var ids: Array = []
	for i in n:
		ids.append(JiebiaoRules.BANDIT_ID)
	host.tell(s, Protocol.CH_SYSTEM, E_AMBUSH, { "n": n })
	host.battles.start_ex(s, ids, "ENCOUNTER", { "pull_party": true })

## 任何戰鬥（比武除外）中逃走或死亡 → 危險鏢失敗
func on_battle_settled(s: Session, ch, summary: Dictionary) -> void:
	if s == null or ch == null or s.character != ch:
		return
	if active_of(ch).is_empty():
		return
	var kind := str(summary.get("kind", ""))
	if kind == "DUEL" or kind == "ROB":
		return   # 劫鏢戰由 on_rob_end 判（BattleSystem._finish 在所有玩家結算之後呼叫）
	var per := str(summary.get("per", summary.get("result", "")))
	if bool(summary.get("died", false)):
		fail_active(s, WHY_DIED)
	elif per == "FLED":
		fail_active(s, WHY_FLED)

## 角色表：押鏢中的鏢與劫鏢標記剩餘（真實秒）
func sheet_fields(s: Session) -> Dictionary:
	if s == null or s.character == null:
		return {}
	var a := active_of(s.character)
	var e: Variant = s.character.ext.get(JiebiaoRules.EXT_KEY, {})
	var until := float(e.get("rob_until_s", 0.0)) if e is Dictionary else 0.0
	var out := { "jiebiao": { "active": {}, "rob_left_s": 0 } }
	if not a.is_empty():
		out["jiebiao"]["active"] = { "value": int(a.get("value", 0)), "kind": str(a.get("kind", "")),
			"kind_name": kind_name(str(a.get("kind", ""))), "to_name": host.region_name(str(a.get("to", ""))) }
	if until > now_s():
		out["jiebiao"]["rob_left_s"] = int(ceil(float(host.real_span(until - now_s()))))
	return out

## 房間玩家列：押鏢中「押鏢」、劫鏢標記中「劫鏢」
func player_tags(_viewer: Session, o: Session) -> Dictionary:
	if o == null or o.character == null:
		return {}
	var tags: Array = []
	if not active_of(o.character).is_empty():
		tags.append(JiebiaoRules.TAG_ESCORT)
	if JiebiaoRules.rob_marked(o.character.ext, now_s()):
		tags.append(JiebiaoRules.TAG_ROBBER)
	return { "tags": tags, "escorting": tags.has(JiebiaoRules.TAG_ESCORT) }

func _mark_room(s: Session) -> void:
	if s != null and s.character != null and host.regions != null:
		host.regions.mark_room_dirty(s.room_id())

# ---------------------------------------------------------------- 劫鏢
## rob_escort：era_locked → bad_target → target_not_here → rob_no_escort → rob_xp → pk_disabled／pk_challenge_only
## → pk_not_allowed_here → target_busy → rob_same_party → target_newbie_protected → 開戰（ROB）＋劫鏢標記
func rob(s: Session, target_char: String) -> Dictionary:
	if not era_on():
		return GameHost.fail(Protocol.R_ERA_LOCKED)
	var ch = s.character
	if target_char == str(ch.id):
		return GameHost.fail("bad_target")
	var t: Session = host.session_for_char(target_char)
	if t == null or t == s or t.character == null or t.room_id() != s.room_id():
		return GameHost.fail("target_not_here")
	var a := active_of(t.character)
	if a.is_empty() or not enabled():
		return GameHost.fail("rob_no_escort")
	if int(ch.combat_xp) < JiebiaoRules.MIN_COMBAT_XP:
		return GameHost.fail("rob_xp")
	# M3d 審查：自己押著危險鏢不能去劫別人的鏢（劫鏢戰的死亡另由 on_rob_end 判；這裡先擋，免得一邊押鏢一邊搶）
	if not active_of(ch).is_empty():
		return GameHost.fail("jb_active")
	var pk = host.get("pk")
	if pk != null:
		var mode := str(pk.pk_mode())
		if mode == "OFF":
			return GameHost.fail("pk_disabled")
		if mode == "CHALLENGE_ONLY":
			return GameHost.fail("pk_challenge_only")
	if not _pk_allowed_at(s.room_id()):
		return GameHost.fail("pk_not_allowed_here")
	if t.battle_id != 0 or t.character.is_jailed():
		return GameHost.fail("target_busy")
	if pk != null and bool(pk.same_party(s, t)):
		return GameHost.fail("rob_same_party")
	if pk != null and bool(pk.newbie_protected(t.character)):
		return GameHost.fail("target_newbie_protected")
	var jb := { "target_char": target_char, "quest": str(a.get("quest", "")), "value": int(a.get("value", 0)),
		"kind": str(a.get("kind", JiebiaoRules.KIND_HUO)) }
	# M3d 審查：同房隊友只拉「自己也能劫鏢」的人——實戰 ≥ 劫鏢門檻（也一定過新手保護）、沒有賞金獵人執照、沒有押著危險鏢；
	# 其他隊友留在原地，不會被扣上劫鏢標記與 PK值【設計提案】
	var px := 0
	if pk != null and (pk as Object).has_method("protect_xp"):
		px = int(pk.protect_xp())
	else:
		px = int(host.options.get("newbie_pk_protect_xp", 500))
	var skip: Array = []
	var party = host.get("party")
	if party != null:
		for o in party.members_in_room(s):
			if o == null or o.character == null:
				continue
			# M3d 審查第三輪：自己押著危險鏢的隊友也不拉（同發起人的 jb_active 規則）
			if LawSystem.has_license(o.character) or not active_of(o.character).is_empty():
				skip.append(str(o.character.id))
	var bid := int(host.battles.start_pvp(s, t, "ROB", { "pull_party": true, "jb": jb,
		"pull_min_xp": maxi(px, JiebiaoRules.MIN_COMBAT_XP), "pull_skip_chars": skip }))
	if bid == 0:
		return GameHost.fail("target_busy")
	# 劫鏢標記：開戰當下給每一位 side 0 玩家（成不成功都給；登出不清）
	var until := now_s() + JiebiaoRules.ROB_MARK_S
	var names: Array = []
	for p in host.battles.side_players(bid, 0):
		var rc = p.get("ch")
		if rc == null:
			continue
		data_of(rc)["rob_until_s"] = until
		names.append(str(rc.name))
		var rs: Session = host.session_for_char(str(rc.id))
		if rs != null:
			host.tell(rs, Protocol.CH_SYSTEM, E_ROB_MARKED, {})
			rs.sheet_dirty = true
	host.ws.queue_room_event(s.room_id(), Protocol.CH_SCENE, E_ROB_START,
		{ "atk_name": str(ch.name), "def_name": str(t.character.name), "kind_name": kind_name(str(jb["kind"])), "label": kind_name(str(jb["kind"])),
			"atk_peer": s.peer_id, "def_peer": t.peer_id })
	host.regions.mark_room_dirty(s.room_id())
	return GameHost.ok({ "battle_id": bid })

func _pk_allowed_at(room_id: String) -> bool:
	var pk = host.get("pk")
	if pk != null and (pk as Object).has_method("pk_allowed_at"):
		return bool(pk.pk_allowed_at(room_id))
	var region := str(host.index.region_of(room_id))
	return bool(host.tables.get("regions", {}).get(region, {}).get("pk_allowed", false))

## BattleSystem._finish（所有玩家結算之後、PkSystem 之前）：分贓、押鏢失敗、劫鏢者 PK值 +1
func on_rob_end(entry: Dictionary, out: Dictionary) -> void:
	var jb: Variant = entry.get("opts", {}).get("jb", {})
	if not (jb is Dictionary) or str(out.get("result", "")) == "ABORTED":
		return
	var units: Dictionary = out.get("units", {})
	var target_char := str(jb.get("target_char", ""))
	var value := int(jb.get("value", 0))
	var rob_uid := int(entry.get("rob_uid", 0))
	var cart_dead := false
	var t_lost := false
	var robbers: Array = []        # [{ uid, ch, alive }]
	var killers: Dictionary = {}   # 殺了 side 1 玩家的 uid
	for k in units:
		var u: Dictionary = units[k]
		if int(u.get("uid", 0)) == rob_uid and rob_uid != 0:
			cart_dead = bool(u.get("died", false))
		if str(u.get("kind", "")) != "PLAYER":
			continue
		if int(u.get("side", 0)) == 1:
			if str(u.get("ref", "")) == target_char and (bool(u.get("died", false)) or bool(u.get("fled", false))):
				t_lost = true
			if bool(u.get("died", false)) and int(u.get("killed_by", 0)) != 0:
				killers[int(u.get("killed_by", 0))] = true
		else:
			var rc = entry["chars"].get(int(u.get("peer", 0)))
			if rc == null:
				continue
			robbers.append({ "uid": int(u.get("uid", 0)), "ch": rc,
				"alive": not bool(u.get("died", false)) and not bool(u.get("fled", false)) })
	var success := cart_dead or t_lost
	var names: Array = []
	var alive: Array = []
	for r in robbers:
		names.append(str(r["ch"].name))
		if bool(r["alive"]):
			alive.append(r)
	var share := JiebiaoRules.rob_share(value, alive.size()) if success else 0
	var t: Session = host.session_for_char(target_char)
	var peers: Array = []
	for r in robbers:
		var rc = r["ch"]
		var rs: Session = host.session_for_char(str(rc.id))
		if success and bool(r["alive"]) and share > 0:
			var got := int(rc.add_money(share))
			if rs != null:
				host.tell(rs, Protocol.CH_SYSTEM, E_ROB_SHARE, { "money": got, "value": value })
		# 劫鏢算強制 PK（R15）：PK值 +1；殺了押鏢者的那位已由 PkSystem 以 FORCED 結算加過
		if not killers.has(int(r["uid"])) and rc.has_method("add_pk"):
			var before: int = int(rc.pk_value()) if rc.has_method("pk_value") else 0
			var after: int = int(rc.add_pk(1))
			if rs != null and after > before:
				host.tell(rs, Protocol.CH_SYSTEM, Protocol.E_PK_VALUE_UP, { "pk": after })
		if rs != null:
			peers.append(rs)
			rs.sheet_dirty = true
		host.save_char(rc)
	if t != null:
		peers.append(t)
	var rtext := "、".join(PackedStringArray(names))
	var p := { "robbers": names, "robbers_text": rtext, "names": rtext, "share": share, "amount": share, "value": value }
	for ps in peers:
		host.tell(ps, Protocol.CH_SYSTEM, Protocol.E_EV_JB_ROBBED if success else E_ROB_REPELLED, p.duplicate(true))
	if success and t != null and t.character != null:
		var a := active_of(t.character)
		if not a.is_empty() and str(a.get("quest", "")) == str(jb.get("quest", "")):
			fail_active(t, WHY_ROBBED)
	# M3d 審查：「任何戰鬥（比武除外）中逃走或死亡 → 危險鏢失敗」也適用劫鏢戰的其他玩家（on_battle_settled 對 ROB 先跳過，
	# 由這裡判）：被拉進來的隊友、或押著鏢的劫鏢者（rob() 已擋，舊存檔與中途加入的保險）死了或逃了 → 他自己的鏢失敗
	for k in units:
		var u: Dictionary = units[k]
		if str(u.get("kind", "")) != "PLAYER" or str(u.get("ref", "")) == target_char:
			continue
		var died := bool(u.get("died", false))
		if not died and not bool(u.get("fled", false)):
			continue
		var os: Session = host.session_for_char(str(u.get("ref", "")))
		if os != null and os.character != null and not active_of(os.character).is_empty():
			fail_active(os, WHY_DIED if died else WHY_FLED)
	host.regions.mark_room_dirty(str(entry.get("room", "")))
