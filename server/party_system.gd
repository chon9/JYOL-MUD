class_name PartySystem
extends RefCounted
## 組隊（M2_PLAN 4.2 party_*、4.4.1、4.5.1、5.1）。只在主機上存在；不存檔（主機重開時隊伍全部解散，4.8）。
## 隊伍成員一律是「在線且選著角色」的玩家：離線或換角即離隊（on_leave）。
## GameHost 以路徑 load() 建立本系統（H4）；本檔只透過 host 的公開函式工作，不引用其他 M2 系統。

const DEFAULT_PARTY_MAX := 5
const DEFAULT_TTL_REAL_S := 60
## 被拒絕或到期後，同一人再邀同一人要等的真實秒數【設計提案】（M2 第三輪審查：防止拒絕後立刻連發洗提示）
const DEFAULT_RETRY_COOLDOWN_REAL_S := 10

var host     # GameHost（H3：dispose() 時設成 null）
var parties: Dictionary = {}     # party_id -> { "id", "leader": char_id, "members": [char_id]（加入順序） }
var _char_party: Dictionary = {} # char_id -> party_id
var invites: Dictionary = {}     # 被邀者 char_id -> { "from_char", "from_name", "to_name", "expires_s"（世界時間） }
var _seq := 0
var _cooldown: Dictionary = {}   # "邀請者|被邀者" → 冷卻結束的世界時間（不存檔）

func _init(p_host) -> void:
	host = p_host

# ---------------------------------------------------------------- 查詢

func party_id_of(char_id: String) -> String:
	return str(_char_party.get(char_id, ""))

func party_of(char_id: String) -> Dictionary:
	return parties.get(party_id_of(char_id), {})

func same_party(a_char: String, b_char: String) -> bool:
	var pa := party_id_of(a_char)
	return pa != "" and pa == party_id_of(b_char)

func is_leader(char_id: String) -> bool:
	var p := party_of(char_id)
	return not p.is_empty() and str(p["leader"]) == char_id

func party_max() -> int:
	return maxi(2, int(host.options.get("party_max", DEFAULT_PARTY_MAX)))

## 同房的隊友 session（不含 s 自己；只列在線且有角色的）。BattleSystem.start 再篩閒置者。
func members_in_room(s: Session) -> Array:
	var out: Array = []
	if s == null or s.character == null:
		return out
	var p := party_of(str(s.character.id))
	if p.is_empty():
		return out
	for cid in p["members"]:
		if str(cid) == str(s.character.id):
			continue
		var o: Session = host.session_for_char(str(cid))
		if o != null and o.character != null and o.room_id() == s.room_id():
			out.append(o)
	return out

## 在線隊員 session（含自己），依加入順序
func member_sessions(party_id: String) -> Array:
	var out: Array = []
	var p: Dictionary = parties.get(party_id, {})
	if p.is_empty():
		return out
	for cid in p["members"]:
		var o: Session = host.session_for_char(str(cid))
		if o != null:
			out.append(o)
	return out

# ---------------------------------------------------------------- 快照（4.5.1、4.5.2）

func sheet_for(s: Session) -> Dictionary:
	if s == null or s.character == null:
		return {}
	var p := party_of(str(s.character.id))
	if p.is_empty():
		return {}
	var members: Array = []
	for cid in p["members"]:
		var o: Session = host.session_for_char(str(cid))
		if o == null or o.character == null:
			continue
		members.append({
			"char_id": str(cid), "name": str(o.character.name), "peer": o.peer_id, "online": true,
			"room_name": host.room_name(o.room_id()), "in_battle": o.battle_id != 0,
			"leader": str(cid) == str(p["leader"]),
		})
	return { "id": str(p["id"]), "leader": str(p["leader"]), "members": members }

## 4.5.1 pending.party_invite：{} 或 { from_char, name, left_s }（left_s 為真實秒數）
func pending_for(s: Session) -> Dictionary:
	if s == null or s.character == null:
		return {}
	var inv: Dictionary = invites.get(str(s.character.id), {})
	if inv.is_empty():
		return {}
	return { "from_char": str(inv["from_char"]), "name": str(inv["from_name"]), "left_s": _left_real_s(inv) }

## 4.5.2 players[] 的組隊與戰鬥欄位
func player_tags(o: Session) -> Dictionary:
	var pid := ""
	if o != null and o.character != null:
		pid = party_id_of(str(o.character.id))
	var bid: int = o.battle_id if o != null else 0
	return { "party_id": pid, "in_battle": bid != 0, "battle_id": bid }

# ---------------------------------------------------------------- intent

## party_invite（4.2）：bad_target → target_not_here → target_busy → target_in_party → not_leader → party_full
## → invite_pending → invite_refused → invite_cooldown → 建立待決邀請
func invite(s: Session, target_char: String) -> Dictionary:
	var me := str(s.character.id)
	if target_char == me:
		return _fail("bad_target")
	var t: Session = host.session_for_char(target_char)
	if t == null or t.character == null or t.room_id() != s.room_id():
		return _fail("target_not_here")
	if t.battle_id != 0:
		return _fail("target_busy")
	if party_id_of(target_char) != "":
		return _fail("target_in_party")
	var mine := party_of(me)
	if not mine.is_empty() and str(mine["leader"]) != me:
		return _fail("not_leader")
	if not mine.is_empty() and (mine["members"] as Array).size() >= party_max():
		return _fail("party_full")
	if invites.has(target_char):
		return _fail("invite_pending")
	if not _pref(t.character, "accept_party"):
		return _fail("invite_refused")   # 不送提示給對方
	if _cooling(me, target_char):
		return _fail("invite_cooldown")
	var ttl := int(host.options.get("pending_ttl_real_s", DEFAULT_TTL_REAL_S))
	invites[target_char] = {
		"from_char": me, "from_name": str(s.character.name), "to_name": str(t.character.name),
		"expires_s": host.now_s() + _span(float(ttl)),
	}
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_PARTY_INVITE_SENT, { "name": str(t.character.name) })
	host.tell(t, Protocol.CH_SYSTEM, Protocol.E_PARTY_INVITED,
		{ "name": str(s.character.name), "from_char": me, "ttl": ttl })
	s.sheet_dirty = true
	t.sheet_dirty = true
	return _ok()

## party_reply（4.2）：no_invite → 拒絕 → target_offline → already_in_party → no_invite（邀請者已不是領隊）→ party_full → 加入
func reply(s: Session, from_char: String, accept: bool) -> Dictionary:
	var me := str(s.character.id)
	var inv: Dictionary = invites.get(me, {})
	if inv.is_empty() or str(inv["from_char"]) != from_char:
		return _fail("no_invite")
	invites.erase(me)
	s.sheet_dirty = true
	var inviter: Session = host.session_for_char(from_char)
	if not accept:
		_start_cooldown(from_char, me)
		if inviter != null:
			host.tell(inviter, Protocol.CH_SYSTEM, Protocol.E_PARTY_DECLINED, { "name": str(s.character.name) })
		return _ok()
	if inviter == null or inviter.character == null:
		return _fail("target_offline")
	if party_id_of(me) != "":
		return _fail("already_in_party")
	var pid := party_id_of(from_char)
	# 邀請者在對方回覆前加入了別人的隊伍、已不是領隊：邀請作廢（M2 審查：非領隊不能替領隊收人）
	if pid != "" and str(parties[pid]["leader"]) != from_char:
		return _fail("no_invite")
	if pid != "" and (parties[pid]["members"] as Array).size() >= party_max():
		return _fail("party_full")
	if pid == "":
		pid = _create_party(from_char)
	_add_member(pid, me)
	var p: Dictionary = parties[pid]
	var leader_name := _char_name(str(p["leader"]))
	for o in member_sessions(pid):
		host.tell(o, Protocol.CH_SYSTEM, Protocol.E_PARTY_JOINED,
			{ "name": str(s.character.name), "peer": s.peer_id, "leader_name": leader_name })
	_touch(pid)
	return _ok()

## party_leave（4.2）：not_in_party → 離隊（戰鬥中也可，戰鬥不受影響）
func leave(s: Session) -> Dictionary:
	var me := str(s.character.id)
	if party_id_of(me) == "":
		return _fail("not_in_party")
	_remove_member(s, me, false)
	return _ok()

## party_kick（4.2）：not_in_party → not_leader → bad_target → target_not_in_party → 移出
func kick(s: Session, target_char: String) -> Dictionary:
	var me := str(s.character.id)
	var pid := party_id_of(me)
	if pid == "":
		return _fail("not_in_party")
	if str(parties[pid]["leader"]) != me:
		return _fail("not_leader")
	if target_char == me:
		return _fail("bad_target")
	if party_id_of(target_char) != pid:
		return _fail("target_not_in_party")
	var t: Session = host.session_for_char(target_char)
	var t_name := _char_name(target_char)
	var p := { "name": t_name, "peer": t.peer_id if t != null else 0, "leader_name": str(s.character.name) }
	for o in member_sessions(pid):   # 全隊（含被踢者）
		host.tell(o, Protocol.CH_SYSTEM, Protocol.E_PARTY_KICKED, p.duplicate())
	_remove_member(t, target_char, true)
	return _ok()

## party_lead（4.2）：not_in_party → not_leader → bad_target → target_not_in_party → 移交
func lead(s: Session, target_char: String) -> Dictionary:
	var me := str(s.character.id)
	var pid := party_id_of(me)
	if pid == "":
		return _fail("not_in_party")
	if str(parties[pid]["leader"]) != me:
		return _fail("not_leader")
	if target_char == me:
		return _fail("bad_target")
	if party_id_of(target_char) != pid:
		return _fail("target_not_in_party")
	parties[pid]["leader"] = target_char
	_announce_leader(pid)
	_touch(pid)
	return _ok()

# ---------------------------------------------------------------- 主機掛鉤（4.6.1）

## 待決邀請到期：邀請者收 party_invite_expired（被邀者只刷新 sheet）
func tick(now: float) -> void:
	if invites.is_empty():
		return
	for to_char in invites.keys():
		var inv: Dictionary = invites[to_char]
		if float(inv["expires_s"]) > now:
			continue
		invites.erase(to_char)
		_start_cooldown(str(inv["from_char"]), str(to_char))
		var inviter: Session = host.session_for_char(str(inv["from_char"]))
		if inviter != null:
			host.tell(inviter, Protocol.CH_SYSTEM, Protocol.E_PARTY_INVITE_EXPIRED, { "name": str(inv["to_name"]) })
			inviter.sheet_dirty = true
		var t: Session = host.session_for_char(str(to_char))
		if t != null:
			t.sheet_dirty = true

## 離線、換角、關服之前：刪除他發出與收到的邀請，並離隊（照 party_leave 的規則與事件）
func on_leave(s: Session) -> void:
	if s == null or s.character == null:
		return
	var me := str(s.character.id)
	if invites.has(me):
		var inv: Dictionary = invites[me]
		invites.erase(me)
		var inviter: Session = host.session_for_char(str(inv["from_char"]))
		if inviter != null:
			inviter.sheet_dirty = true
	for to_char in invites.keys():
		if str(invites[to_char]["from_char"]) == me:
			invites.erase(to_char)
			var t: Session = host.session_for_char(str(to_char))
			if t != null:
				t.sheet_dirty = true
	if party_id_of(me) != "":
		_remove_member(s, me, false)

## 隊員換房間：隊伍面板的所在地要更新
func on_moved(s: Session) -> void:
	if s == null or s.character == null:
		return
	_touch(party_id_of(str(s.character.id)))

## 隊員開戰／戰鬥結束（BattleSystem 呼叫）：隊伍面板的「戰鬥中」要更新
func on_battle_changed(s: Session) -> void:
	on_moved(s)

# ---------------------------------------------------------------- 內部

func _start_cooldown(from_char: String, to_char: String) -> void:
	var cd := maxi(0, int(host.options.get("pending_retry_cooldown_real_s", DEFAULT_RETRY_COOLDOWN_REAL_S)))
	if cd > 0:
		_cooldown[from_char + "|" + to_char] = host.now_s() + _span(float(cd))

func _cooling(from_char: String, to_char: String) -> bool:
	var k := from_char + "|" + to_char
	if int(host.options.get("pending_retry_cooldown_real_s", DEFAULT_RETRY_COOLDOWN_REAL_S)) <= 0:
		return false   # 主機關掉冷卻：立即生效，舊的紀錄一併不算
	if not _cooldown.has(k):
		return false
	if float(_cooldown[k]) > host.now_s():
		return true
	_cooldown.erase(k)
	return false

func _create_party(leader_char: String) -> String:
	_seq += 1
	var pid := "pt_%d" % _seq
	if host.has_method("new_id"):
		pid = host.new_id("pt_")
	parties[pid] = { "id": pid, "leader": leader_char, "members": [leader_char] }
	_char_party[leader_char] = pid
	return pid

func _add_member(pid: String, char_id: String) -> void:
	var members: Array = parties[pid]["members"]
	if not members.has(char_id):
		members.append(char_id)
	_char_party[char_id] = pid

## 移出一名成員（離隊或被踢）。kicked＝true 時 party_kicked 已送過，不再送 party_left。
## 領隊離開 → 最早加入的成員接任（party_leader）；剩 1 人 → 解散（party_disbanded）。
func _remove_member(s: Session, char_id: String, kicked: bool) -> void:
	var pid := party_id_of(char_id)
	if pid == "":
		return
	var p: Dictionary = parties[pid]
	var name := _char_name(char_id) if s == null or s.character == null else str(s.character.name)
	var peer: int = s.peer_id if s != null else 0
	if not kicked:
		for o in member_sessions(pid):   # 離隊者＋留下的人
			host.tell(o, Protocol.CH_SYSTEM, Protocol.E_PARTY_LEFT, { "name": name, "peer": peer })
	(p["members"] as Array).erase(char_id)
	_char_party.erase(char_id)
	if s != null:
		s.sheet_dirty = true
		_mark_room(s)
	var members: Array = p["members"]
	if members.size() <= 1:
		for cid in members:
			_char_party.erase(str(cid))
			var o: Session = host.session_for_char(str(cid))
			if o != null:
				host.tell(o, Protocol.CH_SYSTEM, Protocol.E_PARTY_DISBANDED, {})
				o.sheet_dirty = true
				_mark_room(o)
		parties.erase(pid)
		return
	if str(p["leader"]) == char_id:
		p["leader"] = str(members[0])
		_announce_leader(pid)
	_touch(pid)

func _announce_leader(pid: String) -> void:
	var p: Dictionary = parties[pid]
	var lead_char := str(p["leader"])
	var ls: Session = host.session_for_char(lead_char)
	var pl := { "name": _char_name(lead_char), "peer": ls.peer_id if ls != null else 0 }
	for o in member_sessions(pid):
		host.tell(o, Protocol.CH_SYSTEM, Protocol.E_PARTY_LEADER, pl.duplicate())

## 隊伍內容變了：全隊 sheet 與所在房間的 view 都要重送（view.players[].party_id）
func _touch(pid: String) -> void:
	if pid == "":
		return
	for o in member_sessions(pid):
		o.sheet_dirty = true
		_mark_room(o)

func _mark_room(o: Session) -> void:
	if o == null or o.character == null:
		return
	if host.regions != null:
		host.regions.mark_room_dirty(o.room_id())
	o.view_dirty = true

func _char_name(char_id: String) -> String:
	var o: Session = host.session_for_char(char_id)
	if o != null and o.character != null:
		return str(o.character.name)
	if host.has_method("pvp_char_name"):
		return str(host.pvp_char_name(char_id))
	return char_id

## 系統開關（PK 擁有 Character.prefs，4.6.5）；欄位還不存在時視為開
static func _pref(ch, key: String) -> bool:
	var prefs: Variant = ch.get("prefs") if ch is Object else null
	if prefs is Dictionary:
		return bool(prefs.get(key, true))
	return true

## 真實秒數 → 世界秒數（H5）
func _span(real_s: float) -> float:
	if host.has_method("world_span"):
		return float(host.world_span(real_s))
	return real_s * _time_scale()

func _time_scale() -> float:
	var ws = host.ws
	if ws != null and ws.get("time_scale") != null:
		return maxf(float(ws.get("time_scale")), 0.001)
	return 1.0

func _left_real_s(inv: Dictionary) -> int:
	var left_world := maxf(0.0, float(inv["expires_s"]) - host.now_s())
	var one := _span(1.0)
	return ceili(left_world / maxf(one, 0.001) - 1e-6)

static func _ok() -> Dictionary:
	return { "ok": true, "reason": "" }

static func _fail(reason: String) -> Dictionary:
	return { "ok": false, "reason": reason }
