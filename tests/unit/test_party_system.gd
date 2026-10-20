extends "res://tests/test_case.gd"
## M2_PLAN 6.1 test_party_system：PartySystem 的純邏輯（用假的 host，不開世界）。
## 邀請／接受／拒絕／過期（world_span）／滿員／非領隊邀請／踢人／移交／領隊離開接任／剩 1 人解散／離線即離隊，
## 以及 4.2 的驗證順序、4.5.1 sheet／pending、4.5.2 player_tags。

class FakeChar extends RefCounted:
	var id := ""
	var name := ""
	var location := {}
	var prefs := { "accept_challenge": true, "accept_party": true }
	func _init(p_id: String, p_name: String, room: String) -> void:
		id = p_id
		name = p_name
		location = { "region": "r", "room": room }

class FakeRegions extends RefCounted:
	var dirty_rooms: Array = []
	func mark_room_dirty(room_id: String, _except := 0) -> void:
		dirty_rooms.append(room_id)

class FakeHost extends RefCounted:
	var options := { "party_max": 5, "pending_ttl_real_s": 60 }
	var t := 1000.0
	var scale := 1.0
	var sess: Array = []
	var told: Array = []      # [peer, ch, key, p]
	var regions := FakeRegions.new()
	var ws = null
	var counter := 0
	func now_s() -> float:
		return t
	func world_span(real_s: float) -> float:
		return real_s * scale
	func session_for_char(char_id: String) -> Session:
		for s in sess:
			if s.character != null and s.character.id == char_id:
				return s
		return null
	func tell(s: Session, ch: String, key: String, p: Dictionary, _ui := false) -> void:
		if not p.has("peer"):
			p["peer"] = s.peer_id
		told.append([s.peer_id, ch, key, p])
	func room_name(room_id: String) -> String:
		return "房" + room_id
	func new_id(prefix: String) -> String:
		counter += 1
		return "%s%08x" % [prefix, counter]
	func pvp_char_name(_char_id: String) -> String:
		return ""

var host: FakeHost
var party: PartySystem
var a: Session
var b: Session
var c: Session
var d: Session
var e: Session
var f: Session

func before_each() -> void:
	host = FakeHost.new()
	party = PartySystem.new(host)
	a = _add(101, "ch_a", "阿甲")
	b = _add(102, "ch_b", "阿乙")
	c = _add(103, "ch_c", "阿丙")
	d = _add(104, "ch_d", "阿丁")
	e = _add(105, "ch_e", "阿戊")
	f = _add(106, "ch_f", "阿己")

func after_each() -> void:
	party.host = null
	party = null
	host = null

func _add(peer: int, cid: String, nm: String, room := "r1") -> Session:
	var s := Session.new(peer, "local_%d" % peer, nm)
	s.character = FakeChar.new(cid, nm, room)
	host.sess.append(s)
	return s

func _keys_for(s: Session) -> Array:
	var out: Array = []
	for t in host.told:
		if int(t[0]) == s.peer_id:
			out.append(str(t[2]))
	return out

func _ev(s: Session, key: String) -> Dictionary:
	for i in range(host.told.size() - 1, -1, -1):
		var t: Array = host.told[i]
		if int(t[0]) == s.peer_id and str(t[2]) == key:
			return t[3]
	return {}

func _join(leader: Session, member: Session) -> void:
	assert_eq(party.invite(leader, member.character.id).reason, "", "invite %s" % member.character.name)
	assert_eq(party.reply(member, leader.character.id, true).reason, "", "accept %s" % member.character.name)

# ---------------------------------------------------------------- 邀請與回覆

func test_invite_accept_creates_party_with_inviter_as_leader() -> void:
	var r := party.invite(a, "ch_b")
	assert_true(r.ok)
	assert_eq(_ev(a, "party_invite_sent"), { "name": "阿乙", "peer": 101 })
	var inv := _ev(b, "party_invited")
	assert_eq(inv.name, "阿甲")
	assert_eq(inv.from_char, "ch_a")
	assert_eq(inv.ttl, 60)
	assert_eq(inv.peer, 102, "只送本人：self 變體")
	assert_true(a.sheet_dirty and b.sheet_dirty, "雙方 sheet")
	assert_eq(party.pending_for(b), { "from_char": "ch_a", "name": "阿甲", "left_s": 60 })
	assert_eq(party.pending_for(a), {}, "邀請者沒有待決邀請")
	assert_eq(party.party_id_of("ch_a"), "", "接受前還沒有隊伍")
	host.told.clear()
	assert_true(party.reply(b, "ch_a", true).ok)
	var pid := party.party_id_of("ch_a")
	assert_true(pid.begins_with("pt_"))
	assert_eq(party.party_id_of("ch_b"), pid)
	assert_true(party.is_leader("ch_a"))
	assert_eq(party.pending_for(b), {}, "回覆後清掉")
	var jb := _ev(b, "party_joined")
	assert_eq(jb, { "name": "阿乙", "peer": 102, "leader_name": "阿甲" }, "加入者：self（peer = 自己）")
	assert_eq(_ev(a, "party_joined").peer, 102, "領隊：other")
	var sh := party.sheet_for(b)
	assert_eq(sh.id, pid)
	assert_eq(sh.leader, "ch_a")
	assert_eq(sh.members.size(), 2)
	assert_eq(sh.members[0], { "char_id": "ch_a", "name": "阿甲", "peer": 101, "online": true,
		"room_name": "房r1", "in_battle": false, "leader": true }, "依加入順序；領隊在前")
	assert_eq(sh.members[1].char_id, "ch_b")
	assert_false(sh.members[1].leader)
	assert_eq(party.sheet_for(c), {}, "沒隊伍給 {}")
	assert_eq(party.player_tags(b), { "party_id": pid, "in_battle": false, "battle_id": 0 })
	assert_eq(party.player_tags(c), { "party_id": "", "in_battle": false, "battle_id": 0 })
	assert_true(host.regions.dirty_rooms.has("r1"), "房間 view 要刷新（players[].party_id）")
	assert_true(party.same_party("ch_a", "ch_b"))
	assert_false(party.same_party("ch_a", "ch_c"))

func test_third_member_join_events_to_whole_party() -> void:
	_join(a, b)
	host.told.clear()
	_join(a, c)
	assert_eq(_ev(c, "party_joined").leader_name, "阿甲")
	assert_eq(_ev(c, "party_joined").peer, 103)
	assert_eq(_ev(a, "party_joined").name, "阿丙")
	assert_eq(_ev(b, "party_joined").name, "阿丙", "全隊都收到")
	assert_eq(party.sheet_for(a).members.map(func(m): return m.char_id), ["ch_a", "ch_b", "ch_c"])

func test_decline() -> void:
	party.invite(a, "ch_b")
	host.told.clear()
	assert_true(party.reply(b, "ch_a", false).ok, "拒絕也回 ok")
	assert_eq(_ev(a, "party_declined"), { "name": "阿乙", "peer": 101 })
	assert_eq(party.party_id_of("ch_a"), "")
	assert_eq(party.reply(b, "ch_a", true).reason, "no_invite", "拒絕後邀請失效")
	# M2 第三輪審查：拒絕後同一對人有重邀冷卻【設計提案】，過了才可以再邀
	assert_eq(party.invite(a, "ch_b").reason, "invite_cooldown", "剛被拒絕：冷卻中")
	host.t += party._span(float(PartySystem.DEFAULT_RETRY_COOLDOWN_REAL_S)) + 0.5
	assert_true(party.invite(a, "ch_b").ok, "冷卻過後可以再邀")

func test_expire_uses_world_span() -> void:
	host.scale = 50.0   # --time-scale=50：60 真實秒 = 3000 世界秒
	party.invite(a, "ch_b")
	host.t += 1.2 * 50.0 + 0.5   # 已過 60 世界秒，但只過了約 1.2 真實秒
	party.tick(host.now_s())
	assert_false(party.pending_for(b).is_empty(), "不會在 1.2 真實秒內過期")
	assert_eq(int(party.pending_for(b).left_s), 59, "left_s 是真實秒數")
	host.told.clear()
	host.t = 1000.0 + 3000.0 + 0.1
	party.tick(host.now_s())
	assert_eq(party.pending_for(b), {}, "過期")
	assert_eq(_ev(a, "party_invite_expired"), { "name": "阿乙", "peer": 101 })
	assert_eq(_keys_for(b), [], "被邀者不收過期訊息（只刷新 sheet）")
	assert_true(b.sheet_dirty)
	assert_eq(party.reply(b, "ch_a", true).reason, "no_invite")

# ---------------------------------------------------------------- 驗證順序（4.2）

func test_invite_reason_order() -> void:
	assert_eq(party.invite(a, "ch_a").reason, "bad_target", "自己")
	assert_eq(party.invite(a, "ch_nobody").reason, "target_not_here", "不在線")
	var far := _add(120, "ch_far", "遠方", "r2")
	assert_eq(party.invite(a, "ch_far").reason, "target_not_here", "不同房")
	far.character.location["room"] = "r1"
	far.battle_id = 7
	assert_eq(party.invite(a, "ch_far").reason, "target_busy", "對方在戰鬥")
	far.battle_id = 0
	_join(c, d)
	assert_eq(party.invite(a, "ch_d").reason, "target_in_party")
	assert_eq(party.invite(d, "ch_e").reason, "not_leader", "我在隊伍但不是領隊")
	host.options["party_max"] = 2
	assert_eq(party.invite(c, "ch_e").reason, "party_full", "隊伍人數 ≥ party_max")
	host.options["party_max"] = 5
	assert_true(party.invite(c, "ch_e").ok)
	assert_eq(party.invite(a, "ch_e").reason, "invite_pending", "對方已有任何人的待決邀請")
	assert_eq(party.invite(c, "ch_e").reason, "invite_pending", "同一人重邀也一樣")
	f.character.prefs["accept_party"] = false
	host.told.clear()
	assert_eq(party.invite(a, "ch_f").reason, "invite_refused")
	assert_eq(_keys_for(f), [], "不送提示")
	assert_eq(party.pending_for(f), {})

func test_reply_reason_order() -> void:
	assert_eq(party.reply(b, "ch_a", true).reason, "no_invite", "沒有邀請")
	party.invite(a, "ch_b")
	assert_eq(party.reply(b, "ch_c", true).reason, "no_invite", "不是這個人邀的")
	# target_offline：邀請者已離線
	host.sess.erase(a)
	assert_eq(party.reply(b, "ch_a", true).reason, "target_offline")
	host.sess.append(a)
	assert_eq(party.pending_for(b), {}, "target_offline 也刪除邀請")

func test_reply_already_in_party_and_party_full() -> void:
	# b 收到 a 的邀請後，透過別的途徑進了隊伍（直接模擬：c 邀 b 之前先放進 a 的邀請）
	party.invite(a, "ch_b")
	_force_member(c, b)
	assert_eq(party.reply(b, "ch_a", true).reason, "already_in_party")
	# party_full：接受時邀請者的隊伍已滿
	host.options["party_max"] = 2
	_join(a, d)
	party.invites["ch_e"] = { "from_char": "ch_a", "from_name": "阿甲", "to_name": "阿戊", "expires_s": host.t + 60.0 }
	assert_eq(party.reply(e, "ch_a", true).reason, "party_full")
	assert_eq(party.pending_for(e), {}, "失敗也刪除邀請")

## M2 審查：邀請者在對方回覆前加入別人的隊伍（不是領隊）→ 邀請作廢，不能替領隊收人
func test_reply_inviter_no_longer_leader() -> void:
	party.invite(a, "ch_b")
	_force_member(c, a)
	assert_eq(party.party_id_of("ch_a"), party.party_id_of("ch_c"))
	assert_eq(party.reply(b, "ch_a", true).reason, "no_invite")
	assert_eq(party.party_id_of("ch_b"), "", "b not added")
	assert_eq(party.sheet_for(c).members.size(), 2)

func _force_member(leader: Session, member: Session) -> void:
	var saved: Dictionary = party.invites.get(member.character.id, {})
	party.invites.erase(member.character.id)
	_join(leader, member)
	if not saved.is_empty():
		party.invites[member.character.id] = saved

func test_party_full_on_invite_with_max_five() -> void:
	_join(a, b)
	_join(a, c)
	_join(a, d)
	_join(a, e)
	assert_eq(party.sheet_for(a).members.size(), 5)
	assert_eq(party.invite(a, "ch_f").reason, "party_full", "上限 5")

# ---------------------------------------------------------------- 離隊、踢人、移交

func test_leave_member_and_events() -> void:
	_join(a, b)
	_join(a, c)
	host.told.clear()
	assert_true(party.leave(c).ok)
	assert_eq(_ev(c, "party_left"), { "name": "阿丙", "peer": 103 }, "離隊者 self")
	assert_eq(_ev(a, "party_left").peer, 103, "留下的人 other")
	assert_eq(_ev(b, "party_left").name, "阿丙")
	assert_eq(party.party_id_of("ch_c"), "")
	assert_eq(party.sheet_for(a).members.size(), 2)
	assert_eq(party.leave(c).reason, "not_in_party")

func test_leader_leaves_earliest_member_takes_over() -> void:
	_join(a, b)
	_join(a, c)
	host.told.clear()
	assert_true(party.leave(a).ok)
	assert_true(party.is_leader("ch_b"), "最早加入的成員接任")
	assert_eq(_ev(b, "party_leader"), { "name": "阿乙", "peer": 102 }, "新領隊 self")
	assert_eq(_ev(c, "party_leader").peer, 102)
	assert_eq(_keys_for(a), ["party_left"], "離開的人只收 party_left")
	assert_eq(party.sheet_for(c).leader, "ch_b")

func test_last_member_left_disbands() -> void:
	_join(a, b)
	var pid := party.party_id_of("ch_a")
	host.told.clear()
	assert_true(party.leave(b).ok)
	assert_eq(_keys_for(a), ["party_left", "party_disbanded"])
	assert_eq(_ev(a, "party_disbanded").peer, 101)
	assert_eq(party.party_id_of("ch_a"), "")
	assert_false(party.parties.has(pid), "隊伍刪除")
	assert_eq(party.sheet_for(a), {})

func test_kick_reason_order_and_events() -> void:
	assert_eq(party.kick(a, "ch_b").reason, "not_in_party")
	_join(a, b)
	_join(a, c)
	assert_eq(party.kick(b, "ch_c").reason, "not_leader")
	assert_eq(party.kick(a, "ch_a").reason, "bad_target")
	assert_eq(party.kick(a, "ch_d").reason, "target_not_in_party")
	host.told.clear()
	assert_true(party.kick(a, "ch_c").ok)
	var expect := { "name": "阿丙", "peer": 103, "leader_name": "阿甲" }
	assert_eq(_ev(c, "party_kicked"), expect, "被踢者 self")
	assert_eq(_ev(a, "party_kicked"), expect)
	assert_eq(_ev(b, "party_kicked"), expect, "全隊")
	assert_false(_keys_for(c).has("party_left"), "被踢不另送 party_left")
	assert_eq(party.party_id_of("ch_c"), "")
	host.told.clear()
	assert_true(party.kick(a, "ch_b").ok)
	assert_eq(_keys_for(a), ["party_kicked", "party_disbanded"], "踢到剩 1 人 → 解散")

func test_lead_transfer() -> void:
	assert_eq(party.lead(a, "ch_b").reason, "not_in_party")
	_join(a, b)
	_join(a, c)
	assert_eq(party.lead(b, "ch_c").reason, "not_leader")
	assert_eq(party.lead(a, "ch_a").reason, "bad_target")
	assert_eq(party.lead(a, "ch_d").reason, "target_not_in_party")
	host.told.clear()
	assert_true(party.lead(a, "ch_c").ok)
	assert_true(party.is_leader("ch_c"))
	for s in [a, b, c]:
		assert_eq(_ev(s, "party_leader"), { "name": "阿丙", "peer": 103 }, "全隊")
	assert_eq(party.sheet_for(a).members.map(func(m): return m.char_id), ["ch_a", "ch_b", "ch_c"], "順序不變")
	assert_true(party.invite(c, "ch_d").ok, "新領隊可以邀請")
	assert_eq(party.invite(a, "ch_e").reason, "not_leader")

# ---------------------------------------------------------------- 離線、換角、同房查詢

func test_on_leave_offline_leaves_party_and_clears_invites() -> void:
	_join(a, b)
	_join(a, c)
	party.invite(a, "ch_d")              # a 發出的邀請
	party.invites["ch_a"] = { "from_char": "ch_e", "from_name": "阿戊", "to_name": "阿甲", "expires_s": host.t + 60.0 }
	host.told.clear()
	party.on_leave(a)
	host.sess.erase(a)
	assert_eq(party.party_id_of("ch_a"), "", "離線即離隊")
	assert_true(party.is_leader("ch_b"), "領隊離線 → 接任")
	assert_eq(_ev(b, "party_left").peer, 101)
	assert_eq(party.pending_for(d), {}, "他發出的邀請刪除")
	assert_true(d.sheet_dirty)
	assert_false(party.invites.has("ch_a"), "他收到的邀請刪除")
	assert_true(party.reply(d, "ch_a", true).reason == "no_invite")
	# 換角：同一個 session 選別的角色前呼叫 on_leave
	party.on_leave(b)
	assert_eq(party.party_id_of("ch_c"), "", "剩 1 人解散")
	assert_true(party.parties.is_empty())

func test_members_in_room() -> void:
	_join(a, b)
	_join(a, c)
	c.character.location["room"] = "r2"
	var ms := party.members_in_room(a)
	assert_eq(ms.size(), 1)
	assert_true(ms[0] == b, "只列同房、不含自己")
	assert_eq(party.members_in_room(d), [], "沒隊伍")
	b.battle_id = 3
	assert_eq(party.members_in_room(a).size(), 1, "戰鬥中的也列出（閒置由 BattleSystem 篩）")
	assert_eq(party.player_tags(b), { "party_id": party.party_id_of("ch_a"), "in_battle": true, "battle_id": 3 })
	assert_true(party.sheet_for(a).members[1].in_battle)
	assert_eq(party.sheet_for(a).members[2].room_name, "房r2")

func test_on_moved_marks_party_dirty() -> void:
	_join(a, b)
	a.sheet_dirty = false
	b.sheet_dirty = false
	party.on_moved(b)
	assert_true(a.sheet_dirty and b.sheet_dirty, "隊伍面板的所在地要更新")
	c.sheet_dirty = false
	party.on_moved(c)
	assert_false(c.sheet_dirty, "沒隊伍不動")
