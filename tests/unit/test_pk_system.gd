extends "res://tests/test_case.gd"
## WP-PK：PkSystem 與 CorpseSystem 的單元測試（M2_PLAN 4.6.4、5.2、5.3）。
## 用假主機（不需要 WorldServer、WP-HOST 的多玩家基底或 WP-PARTY 的 start_pvp），資料表用真的 GameData.tables。
## 經由真主機的整合版本在 test_world_pk.gd、test_world_corpse.gd。

# ------------------------------------------------------------------ 假主機
class FakeWs extends RefCounted:
	var world := { "corpses": [], "char_names": {} }
	var time_scale := 1.0
	var out: Array = []        # { to: peer|"all"|"room:<id>", key, p }
	var saves := 0
	var world_first_saves := 0
	func save_now(world_first := false) -> Error:
		saves += 1
		if world_first:
			world_first_saves += 1
		return OK
	func queue_event(peer_id: int, _ch: String, key: String, p: Dictionary, _ui := false) -> void:
		out.append({ "to": peer_id, "key": key, "p": p })
	func broadcast_event(_ch: String, key: String, p: Dictionary, _ui := false) -> void:
		out.append({ "to": "all", "key": key, "p": p })
	func queue_room_event(room_id: String, _ch: String, key: String, p: Dictionary, _except := 0) -> void:
		out.append({ "to": "room:" + room_id, "key": key, "p": p })

class FakeRegions extends RefCounted:
	var dirty: Array = []
	func mark_room_dirty(room_id: String, _except := 0) -> void:
		dirty.append(room_id)

class FakeBattles extends RefCounted:
	var started: Array = []
	var pvp: Array = []
	var next_bid := 0              # 0 = start_pvp 失敗
	func start(s: Session, ids: Array, kind: String) -> int:
		started.append({ "peer": s.peer_id, "ids": ids.duplicate(), "kind": kind })
		s.battle_id = 77
		return 77
	func start_pvp(atk: Session, def: Session, kind: String) -> int:
		pvp.append({ "atk": atk.peer_id, "def": def.peer_id, "kind": kind })
		if next_bid != 0:
			atk.battle_id = next_bid
			def.battle_id = next_bid
		return next_bid

class FakeParty extends RefCounted:
	var of_char: Dictionary = {}
	func player_tags(o: Session) -> Dictionary:
		return { "party_id": str(of_char.get(str(o.character.id), "")) }

class FakeStore extends RefCounted:
	var chars: Dictionary = {}
	func load_char(_identity: String, char_id: String):
		return chars.get(char_id)

class FakeHost extends RefCounted:
	var ws := FakeWs.new()
	var tables: Dictionary = GameData.tables
	var options: Dictionary = {}
	var rules: Dictionary = { "corpse_window": "CLASSIC_30" }
	var index := WorldIndex.new(GameData.tables)
	var regions := FakeRegions.new()
	var battles := FakeBattles.new()
	var party = null
	var char_store := FakeStore.new()
	var list: Array = []
	var now := 1000.0
	var saved: Array = []
	var _id := 0
	func now_s() -> float:
		return now
	func sessions() -> Array:
		return list
	func session_for_char(char_id: String) -> Session:
		for s in list:
			if s.character != null and str(s.character.id) == char_id:
				return s
		return null
	func tell(s: Session, ch: String, key: String, p: Dictionary, ui := false) -> void:
		if not p.has("peer"):
			p["peer"] = s.peer_id
		ws.queue_event(s.peer_id, ch, key, p, ui)
	func room_name(room_id: String) -> String:
		return str(index.room(room_id).get("name", room_id))
	func item_name(item_id: String) -> String:
		return str(tables.get("items", {}).get(item_id, {}).get("name", item_id))
	func new_id(prefix: String) -> String:
		_id += 1
		return "%s%08x" % [prefix, _id]
	func _uid() -> String:
		return new_id("it_")
	func give_item(ch, item_id: String, n: int, born_s: float = -1.0, lots: Array = []) -> Dictionary:
		var cap := int(options.get("_carry_max", 1000000))
		if not lots.is_empty():
			return ch.inventory.add_lots(item_id, lots, tables, cap, Callable(self, "_uid"))
		return ch.inventory.add(item_id, n, tables, now if born_s < 0.0 else born_s, cap, Callable(self, "_uid"))
	func save_char(ch) -> Error:
		saved.append(str(ch.id))
		return OK
	func world_span(real_s: float) -> float:
		return real_s * ws.time_scale
	func char_ref_by_name(n: String) -> Dictionary:
		var e: Variant = ws.world["char_names"].get(n.strip_edges().to_lower())
		return e if e is Dictionary else {}

var h: FakeHost
var pk: PkSystem
var corpses: CorpseSystem
var _peer := 100

func before_each() -> void:
	h = FakeHost.new()
	pk = PkSystem.new(h)
	corpses = CorpseSystem.new(h)
	_peer = 100

func after_each() -> void:
	pk.host = null
	corpses.host = null
	pk = null
	corpses = null
	h = null

func _player(n: String, room := "xw_road", xp := 2000) -> Session:
	_peer += 1
	var s := Session.new(_peer, "local_%032d" % _peer, n)
	var c := Character.new()
	c.id = "ch_%08d" % _peer
	c.identity = s.identity
	c.name = n
	c.combat_xp = xp
	c.location = { "region": h.index.region_of(room), "room": room }
	s.character = c
	h.list.append(s)
	h.ws.world["char_names"][n.to_lower()] = { "identity": s.identity, "char_id": c.id }
	return s

func _evs(to: Variant, key: String) -> Array:
	return h.ws.out.filter(func(e): return e["key"] == key and typeof(e["to"]) == typeof(to) and e["to"] == to)

func _cid(s: Session) -> String:
	return str(s.character.id)

# ================================================================== 叫戰
func test_challenge_reason_order() -> void:
	var a := _player("甲")
	var b := _player("乙")
	h.options["pk_mode"] = "OFF"
	assert_eq(pk.challenge(a, _cid(b))["reason"], "pk_disabled")
	h.options["pk_mode"] = "CHALLENGE_ONLY"
	assert_eq(pk.challenge(a, _cid(a))["reason"], "bad_target")
	assert_eq(pk.challenge(a, "ch_nobody")["reason"], "target_not_here")
	b.character.location = { "region": "xixia_wild", "room": "xw_grass" }
	assert_eq(pk.challenge(a, _cid(b))["reason"], "target_not_here", "other room")
	b.character.location = { "region": "xixia_wild", "room": "xw_road" }
	a.character.location = { "region": "xixia", "room": "xx_square" }
	b.character.location = { "region": "xixia", "room": "xx_square" }
	assert_eq(pk.challenge(a, _cid(b))["reason"], "pk_not_allowed_here", "city")
	a.character.location = { "region": "xixia_wild", "room": "xw_road" }
	b.character.location = { "region": "xixia_wild", "room": "xw_road" }
	b.battle_id = 5
	assert_eq(pk.challenge(a, _cid(b))["reason"], "target_busy")
	b.battle_id = 0
	var party := FakeParty.new()
	h.party = party
	party.of_char = { _cid(a): "pt_1", _cid(b): "pt_1" }
	assert_eq(pk.challenge(a, _cid(b))["reason"], "target_in_party")
	party.of_char = { _cid(a): "pt_1", _cid(b): "pt_2" }
	assert_true(pk.challenge(a, _cid(b))["ok"], "different parties ok")
	assert_eq(pk.challenge(a, _cid(b))["reason"], "challenge_pending")
	var c := _player("丙")
	c.character.prefs["accept_challenge"] = false
	h.ws.out.clear()
	assert_eq(pk.challenge(a, _cid(c))["reason"], "challenge_refused")
	assert_true(_evs(c.peer_id, "challenge_request").is_empty(), "refused: no prompt")

func test_challenge_events_and_pending() -> void:
	var a := _player("甲")
	var b := _player("乙")
	h.ws.time_scale = 50.0
	h.options["pending_ttl_real_s"] = 60
	assert_true(pk.challenge(a, _cid(b))["ok"])
	assert_eq(_evs(a.peer_id, "challenge_sent")[0]["p"]["name"], "乙")
	var req: Dictionary = _evs(b.peer_id, "challenge_request")[0]["p"]
	assert_eq(req["name"], "甲")
	assert_eq(req["from_char"], _cid(a))
	assert_eq(req["ttl"], 60)
	assert_true(b.sheet_dirty)
	var pend := pk.pending_for(b)
	assert_eq(pend.size(), 1)
	assert_eq(pend[0]["from_char"], _cid(a))
	assert_eq(pend[0]["name"], "甲")
	assert_eq(pend[0]["left_s"], 60, "real seconds")
	assert_eq(pk.pending_for(a), [])
	# H5：60 真實秒 × 50 = 3000 世界秒才到期
	h.now += 1.2 * 50.0
	pk.tick(h.now)
	assert_eq(pk.pending_for(b).size(), 1, "not expired after 1.2 real seconds")
	assert_eq(pk.pending_for(b)[0]["left_s"], 59)
	h.now = 1000.0 + 3000.0
	pk.tick(h.now)
	assert_eq(pk.pending_for(b).size(), 0, "expired")
	assert_eq(_evs(a.peer_id, "challenge_expired").size(), 1)
	assert_eq(_evs(a.peer_id, "challenge_expired")[0]["p"]["name"], "乙")
	pk.tick(h.now + 10.0)
	assert_eq(_evs(a.peer_id, "challenge_expired").size(), 1, "sent once")
	assert_eq(pk.challenge_reply(b, _cid(a), true)["reason"], "no_challenge")

func test_challenge_decline() -> void:
	var a := _player("甲")
	var b := _player("乙")
	assert_true(pk.challenge(a, _cid(b))["ok"])
	var r := pk.challenge_reply(b, _cid(a), false)
	assert_true(r["ok"])
	assert_eq(_evs(a.peer_id, "challenge_declined")[0]["p"]["name"], "乙")
	assert_true(h.battles.pvp.is_empty())
	assert_eq(pk.challenge_reply(b, _cid(a), false)["reason"], "no_challenge")

## M2 第三輪審查：被拒絕或到期後，同一對人要冷卻一段時間才能再叫戰（不能連發洗提示）
func test_challenge_retry_cooldown_after_decline_and_expiry() -> void:
	var a := _player("甲")
	var b := _player("乙")
	var c := _player("丙")
	assert_true(pk.challenge(a, _cid(b))["ok"])
	assert_true(pk.challenge_reply(b, _cid(a), false)["ok"])
	assert_eq(pk.challenge(a, _cid(b))["reason"], "challenge_cooldown", "right after a decline")
	assert_true(pk.challenge(a, _cid(c))["ok"], "other targets are not affected")
	assert_true(pk.challenge(b, _cid(a))["ok"], "the other direction is not affected")
	h.now += pk._world_span(float(PkSystem.DEFAULT_RETRY_COOLDOWN_REAL_S)) + 0.5
	assert_true(pk.challenge(a, _cid(b))["ok"], "after the cooldown")
	h.now += pk._world_span(float(pk.ttl_real_s())) + 1.0
	pk.tick(h.now)   # 到期
	assert_eq(pk.challenge(a, _cid(b))["reason"], "challenge_cooldown", "right after expiry")
	h.options["pending_retry_cooldown_real_s"] = 0
	assert_true(pk.challenge(a, _cid(b))["ok"], "0 = no cooldown")

func test_challenge_accept_starts_pvp() -> void:
	var a := _player("甲")
	var b := _player("乙")
	h.battles.next_bid = 9
	assert_true(pk.challenge(a, _cid(b))["ok"])
	var r := pk.challenge_reply(b, _cid(a), true)
	assert_true(r["ok"], str(r))
	assert_eq(h.battles.pvp, [ { "atk": a.peer_id, "def": b.peer_id, "kind": "CHALLENGE" } ])
	var st := _evs("room:xw_road", "challenge_start")
	assert_eq(st.size(), 1)
	assert_eq(st[0]["p"], { "atk_name": "甲", "def_name": "乙", "atk_peer": a.peer_id, "def_peer": b.peer_id })
	assert_eq(pk.pending.size(), 0)

func test_challenge_accept_rechecks() -> void:
	var a := _player("甲")
	var b := _player("乙")
	h.battles.next_bid = 9
	assert_true(pk.challenge(a, _cid(b))["ok"])
	a.character.location = { "region": "xixia_wild", "room": "xw_grass" }
	assert_eq(pk.challenge_reply(b, _cid(a), true)["reason"], "target_not_here")
	a.character.location = { "region": "xixia_wild", "room": "xw_road" }
	assert_true(pk.challenge(a, _cid(b))["ok"])
	h.options["pk_mode"] = "OFF"
	assert_eq(pk.challenge_reply(b, _cid(a), true)["reason"], "pk_disabled")
	h.options["pk_mode"] = "CLASSIC"
	assert_true(pk.challenge(a, _cid(b))["ok"])
	a.battle_id = 3
	assert_eq(pk.challenge_reply(b, _cid(a), true)["reason"], "target_busy")
	a.battle_id = 0
	assert_true(pk.challenge(a, _cid(b))["ok"])
	h.list.erase(a)   # 叫戰者離線（未經 on_leave）
	assert_eq(pk.challenge_reply(b, _cid(a), true)["reason"], "target_not_here")
	assert_true(h.battles.pvp.is_empty())

## M2 審查：叫戰之後兩人才組隊 → 接受時回 target_in_party，不開打
func test_challenge_accept_rechecks_same_party() -> void:
	var a := _player("甲")
	var b := _player("乙")
	h.battles.next_bid = 9
	assert_true(pk.challenge(a, _cid(b))["ok"])
	var fp := FakeParty.new()
	h.party = fp
	fp.of_char[_cid(a)] = "pt_1"
	fp.of_char[_cid(b)] = "pt_1"
	assert_eq(pk.challenge_reply(b, _cid(a), true)["reason"], "target_in_party")
	assert_true(h.battles.pvp.is_empty(), "teammates never fight")
	assert_eq(pk.pending.size(), 0, "challenge consumed")

func test_challenge_only_mode_allows_challenge() -> void:
	var a := _player("甲")
	var b := _player("乙")
	h.options["pk_mode"] = "CHALLENGE_ONLY"
	h.battles.next_bid = 4
	assert_true(pk.challenge(a, _cid(b))["ok"])
	assert_true(pk.challenge_reply(b, _cid(a), true)["ok"])
	assert_eq(pk.force_pk(a, _cid(b))["reason"], "pk_challenge_only")

func test_on_leave_drops_pending() -> void:
	var a := _player("甲")
	var b := _player("乙")
	var c := _player("丙")
	assert_true(pk.challenge(a, _cid(b))["ok"])
	assert_true(pk.challenge(c, _cid(a))["ok"])
	assert_true(pk.challenge(c, _cid(b))["ok"])
	pk.on_leave(a)
	assert_eq(pk.pending.size(), 1, "only c→b left")
	assert_eq(pk.pending_for(b)[0]["from_char"], _cid(c))
	h.now += 99999.0
	pk.tick(h.now)
	assert_true(_evs(a.peer_id, "challenge_expired").is_empty(), "dropped ones never expire-notify")

# ================================================================== 強制 PK
func test_force_pk_reason_order() -> void:
	var a := _player("甲")
	var b := _player("乙", "xw_road", 100)
	h.options["pk_mode"] = "OFF"
	assert_eq(pk.force_pk(a, _cid(b))["reason"], "pk_disabled")
	h.options["pk_mode"] = "CHALLENGE_ONLY"
	assert_eq(pk.force_pk(a, _cid(b))["reason"], "pk_challenge_only")
	h.options["pk_mode"] = "CLASSIC"
	assert_eq(pk.force_pk(a, _cid(a))["reason"], "bad_target")
	assert_eq(pk.force_pk(a, "ch_x")["reason"], "target_not_here")
	a.character.location = { "region": "xixia", "room": "xx_gate_e" }
	b.character.location = { "region": "xixia", "room": "xx_gate_e" }
	assert_eq(pk.force_pk(a, _cid(b))["reason"], "pk_not_allowed_here")
	a.character.location = { "region": "xixia_wild", "room": "xw_road" }
	b.character.location = { "region": "xixia_wild", "room": "xw_road" }
	b.battle_id = 2
	assert_eq(pk.force_pk(a, _cid(b))["reason"], "target_busy")
	b.battle_id = 0
	var party := FakeParty.new()
	party.of_char = { _cid(a): "pt_9", _cid(b): "pt_9" }
	h.party = party
	assert_eq(pk.force_pk(a, _cid(b))["reason"], "target_in_party")
	h.party = null
	assert_eq(pk.force_pk(a, _cid(b))["reason"], "target_newbie_protected", "default protect 500")
	h.options["newbie_pk_protect_xp"] = 0
	h.battles.next_bid = 12
	var r := pk.force_pk(a, _cid(b))
	assert_true(r["ok"], str(r))
	assert_eq(h.battles.pvp, [ { "atk": a.peer_id, "def": b.peer_id, "kind": "FORCED" } ])
	assert_eq(_evs("room:xw_road", "force_pk_start").size(), 1)

func test_force_pk_without_start_pvp_fails_cleanly() -> void:
	var a := _player("甲")
	var b := _player("乙")
	h.battles.next_bid = 0
	assert_eq(pk.force_pk(a, _cid(b))["reason"], "target_busy", "start_pvp returned 0")
	assert_true(_evs("room:xw_road", "force_pk_start").is_empty(), "no start event when battle did not open")

# ================================================================== 系統開關
func test_set_pref() -> void:
	var a := _player("甲")
	assert_true(pk.set_pref(a, "accept_challenge", false)["ok"])
	assert_eq(a.character.prefs["accept_challenge"], false)
	assert_eq(_evs(a.peer_id, "pref_changed")[0]["p"]["label"], "接受叫戰")
	assert_eq(_evs(a.peer_id, "pref_changed")[0]["p"]["state"], "關")
	assert_true(pk.set_pref(a, "accept_party", true)["ok"])
	assert_eq(_evs(a.peer_id, "pref_changed")[1]["p"], { "label": "接受組隊邀請", "state": "開", "peer": a.peer_id })
	assert_true(a.sheet_dirty)

# ================================================================== 守衛
func test_guards_on_city_boundary() -> void:
	var a := _player("甲", "xx_gate_e")
	a.character.pk = 4
	assert_true(pk.on_move(a, "xx_gate_e", "xw_road"), "leaving city with pk 4")
	assert_eq(h.battles.started[0]["ids"], ["m_city_guard", "m_city_guard"])
	assert_eq(h.battles.started[0]["kind"], "GUARD")
	assert_eq(_evs(a.peer_id, "guard_attack")[0]["p"]["n"], 2)
	a.battle_id = 0
	a.character.pk = 0
	a.character.morality = -1
	assert_true(pk.on_move(a, "xw_road", "xx_gate_e"), "entering city with morality -1")
	assert_eq(h.battles.started[1]["ids"], ["m_city_guard"])
	a.battle_id = 0
	assert_false(pk.on_move(a, "xx_square", "xx_gate_e"), "moving inside the city")
	assert_false(pk.on_move(a, "xw_road", "xw_grass"), "moving outside")
	h.options["guards_enabled"] = false
	assert_false(pk.on_move(a, "xx_gate_e", "xw_road"), "guards disabled")
	h.options["guards_enabled"] = true
	a.character.morality = 0
	assert_false(pk.on_move(a, "xx_gate_e", "xw_road"), "clean character")
	a.character.pk = 4
	a.battle_id = 6
	assert_false(pk.on_move(a, "xx_gate_e", "xw_road"), "already fighting")
	assert_eq(h.battles.started.size(), 2)

## M3c 審查：新手（實戰 < newbie_pk_protect_xp）善惡為負時進出城不被官兵追殺（M3c 起新手區有善惡負的可殺 NPC，
## 殺一隻黃狗就會在每次進出城時被打死）；PK值 > 3 照舊追殺
func test_guards_spare_negative_morality_newbie() -> void:
	var a := _player("新手", "xx_gate_e", 0)
	a.character.morality = -3
	assert_false(pk.on_move(a, "xw_road", "xx_gate_e"), "newbie with morality -3: no guards")
	a.character.combat_xp = 499
	assert_false(pk.on_move(a, "xx_gate_e", "xw_road"), "still a newbie at 499")
	a.character.pk = 4
	assert_true(pk.on_move(a, "xx_gate_e", "xw_road"), "pk > 3 still hunted even as a newbie")
	a.battle_id = 0
	a.character.pk = 0
	a.character.combat_xp = 500
	assert_true(pk.on_move(a, "xw_road", "xx_gate_e"), "no longer a newbie: morality < 0 → guards")
	assert_eq(MoralityPk.guard_count(0, -1, true), 0)
	assert_eq(MoralityPk.guard_count(4, -1, true), 2)

func test_guards_use_decayed_pk() -> void:
	var a := _player("甲", "xx_gate_e")
	a.character.pk = 4
	a.character.pk_stamp_s = 0.0
	a.character.online_s = 1800.0     # 目前值 3
	assert_false(pk.on_move(a, "xx_gate_e", "xw_road"), "decayed to 3")

# ================================================================== PvP 結束
func _summary(kind: String, killer: Session, victim: Session, killer_online := true) -> Dictionary:
	return { "bid": 1, "kind": kind, "room": "xw_road", "units": [
		{ "char_id": _cid(killer), "name": str(killer.character.name), "peer": killer.peer_id if killer_online else 0,
		  "side": 0, "died": false, "fled": false, "killed_by_char": "" },
		{ "char_id": _cid(victim), "name": str(victim.character.name), "peer": victim.peer_id,
		  "side": 1, "died": true, "fled": false, "killed_by_char": _cid(killer) } ] }

func test_forced_kill_deltas_and_broadcast() -> void:
	var a := _player("甲")
	var b := _player("乙")
	pk.on_pvp_end(_summary("FORCED", a, b))
	var c = a.character
	assert_eq(c.pk_value(), 1)
	assert_eq(c.killing_intent, 100)
	assert_eq(c.morality, -10)
	var kill := _evs("all", "pk_kill")
	assert_eq(kill.size(), 1)
	assert_eq(kill[0]["p"], { "atk_name": "甲", "def_name": "乙", "atk_peer": a.peer_id, "def_peer": b.peer_id,
		"room_name": h.room_name("xw_road") })
	assert_eq(_evs(a.peer_id, "pk_value_up")[0]["p"]["pk"], 1)
	assert_eq(_evs(a.peer_id, "morality_change")[0]["p"]["delta"], -10)
	assert_eq(_evs(a.peer_id, "morality_change")[0]["p"]["value"], -10)
	assert_eq(_evs(a.peer_id, "killing_intent_change")[0]["p"]["delta"], 100)
	assert_true(_evs(a.peer_id, "pk_wanted").is_empty())
	assert_has(h.saved, _cid(a), "killer saved")
	assert_eq(b.character.pk_value(), 0, "victim untouched")

func test_forced_kill_of_evil_and_wanted() -> void:
	var a := _player("甲")
	var b := _player("乙")
	b.character.morality = -300
	a.character.pk = 3
	pk.on_pvp_end(_summary("FORCED", a, b))
	assert_eq(a.character.morality, 10, "killing evil +10")
	assert_eq(a.character.pk_value(), 4)
	assert_eq(_evs(a.peer_id, "pk_wanted").size(), 1)
	assert_eq(_evs(a.peer_id, "pk_wanted")[0]["p"]["pk"], 4)

func test_challenge_kill_no_pk() -> void:
	var a := _player("甲")
	var b := _player("乙")
	pk.on_pvp_end(_summary("CHALLENGE", a, b))
	assert_eq(a.character.pk_value(), 0)
	assert_eq(a.character.killing_intent, 100)
	assert_eq(a.character.morality, 0)
	# M2 審查：叫戰是雙方同意的比武，不廣播全服；只告訴兩個當事人
	assert_true(_evs("all", "pk_kill").is_empty(), "challenge kill not broadcast")
	assert_eq(_evs(a.peer_id, "pk_kill").size(), 1, "killer told")
	assert_eq(_evs(b.peer_id, "pk_kill").size(), 1, "victim told")
	assert_eq(_evs(b.peer_id, "pk_kill")[0]["p"]["def_peer"], b.peer_id)
	assert_true(_evs(a.peer_id, "pk_value_up").is_empty())
	assert_true(_evs(a.peer_id, "morality_change").is_empty())

func test_offline_killer_updated_on_disk() -> void:
	var a := _player("甲")
	var b := _player("乙")
	h.list.erase(a)                  # 擊殺者已斷線
	h.char_store.chars[_cid(a)] = a.character
	pk.on_pvp_end(_summary("FORCED", a, b, false))
	assert_eq(a.character.pk_value(), 1)
	assert_has(h.saved, _cid(a))
	assert_eq(_evs("all", "pk_kill")[0]["p"]["atk_peer"], 0)
	assert_eq(_evs("all", "pk_kill")[0]["p"]["atk_name"], "甲")

func test_no_killer_no_change() -> void:
	var a := _player("甲")
	var b := _player("乙")
	var s := _summary("FORCED", a, b)
	s["units"][1]["killed_by_char"] = ""
	pk.on_pvp_end(s)
	assert_eq(a.character.pk_value(), 0)
	assert_true(_evs("all", "pk_kill").is_empty())

func test_player_tags() -> void:
	var a := _player("甲", "xw_road", 100)
	a.character.morality = 150
	assert_eq(pk.player_tags(a), { "align": "GOOD", "newbie": true })
	a.character.combat_xp = 500
	a.character.morality = -150
	assert_eq(pk.player_tags(a), { "align": "EVIL", "newbie": false })

# ================================================================== 屍體
func _corpse(owner: Session, items: Array) -> String:
	return corpses.create(owner.character, "xw_road", items)

func _items() -> Array:
	return [ { "uid": "it_a1", "id": "c_jingyao", "n": 2, "born_s": 0.0 },
		{ "uid": "it_a2", "id": "w_mudao", "n": 1, "born_s": 0.0 } ]

func test_corpse_create_has_new_fields() -> void:
	var a := _player("甲")
	var id := _corpse(a, _items())
	var c := corpses.find(id)
	assert_eq(c["authorized"], [])
	assert_eq(c["public_notified"], false)
	assert_eq(c["window"], "CLASSIC_30")
	assert_eq(corpses.private_s(c), 600.0)
	assert_eq(corpses.expire_s(c), 1800.0)
	c["window"] = "LATER_10"
	assert_eq(corpses.private_s(c), 600.0, "D6")
	assert_eq(corpses.expire_s(c), 1800.0, "D6")

func test_corpse_protection_authorization_public() -> void:
	var owner := _player("甲")
	var other := _player("乙")
	var friend := _player("丙")
	var id := _corpse(owner, _items())
	assert_eq(corpses.loot(other, id)["reason"], "corpse_protected")
	var v: Array = corpses.in_room("xw_road", other)
	assert_eq(v[0]["can_loot"], false)
	assert_false(v[0].has("items"), "items hidden when protected")
	assert_eq(v[0]["public"], false)
	assert_eq(v[0]["left_s"], 600)
	# 授權
	assert_eq(corpses.authorize(other, id, "丙")["reason"], "not_corpse_owner")
	assert_eq(corpses.authorize(owner, "cp_none", "丙")["reason"], "corpse_not_found")
	assert_eq(corpses.authorize(owner, id, "無此人")["reason"], "no_such_player")
	assert_eq(corpses.authorize(owner, id, "甲")["reason"], "bad_target")
	assert_true(corpses.authorize(owner, id, "丙")["ok"])
	assert_eq(_evs(owner.peer_id, "corpse_authorized")[0]["p"]["name"], "丙")
	assert_eq(_evs(friend.peer_id, "corpse_auth_granted")[0]["p"]["owner_name"], "甲")
	var vf: Array = corpses.in_room("xw_road", friend)
	assert_eq(vf[0]["authorized_me"], true)
	assert_false(vf[0].has("authorized_names"), "only the owner sees the list")
	var vown: Array = corpses.in_room("xw_road", owner)
	assert_eq(vown[0]["authorized_names"], ["丙"], "owner sees who is authorised (M2 review)")
	assert_eq(vown[0]["auth_max"], 4)
	assert_eq(vf[0]["can_loot"], true)
	assert_eq(vf[0]["items"].size(), 2)
	assert_eq(vf[0]["items"][0], { "uid": "it_a1", "id": "c_jingyao", "name": h.item_name("c_jingyao"), "n": 2 })
	# 單件撿
	assert_eq(corpses.loot(friend, id, "it_zz")["reason"], "no_item")
	var r := corpses.loot(friend, id, "it_a2")
	assert_true(r["ok"], str(r))
	assert_eq(friend.character.inventory.count("w_mudao"), 1)
	assert_eq(CorpseSystem.pieces(corpses.find(id)), 2)
	assert_eq(_evs(friend.peer_id, "corpse_looted_other")[0]["p"], { "owner_name": "甲", "n_items": 1, "peer": friend.peer_id })
	assert_eq(_evs(owner.peer_id, "corpse_looted_by")[0]["p"]["name"], "丙")
	assert_eq(_evs(owner.peer_id, "corpse_looted_by")[0]["p"]["n_items"], 1)
	# 公開期
	h.now += 600.0
	assert_true(corpses.is_public(corpses.find(id), h.now))
	var vo: Array = corpses.in_room("xw_road", other)
	assert_eq(vo[0]["can_loot"], true)
	assert_eq(vo[0]["public"], true)
	assert_eq(vo[0]["left_s"], 1200, "public: until expiry")
	assert_true(corpses.loot(other, id)["ok"])
	assert_eq(other.character.inventory.count("c_jingyao"), 2)
	assert_true(corpses.find(id).is_empty(), "empty corpse removed")

func test_corpse_owner_loots_own() -> void:
	var owner := _player("甲")
	var id := _corpse(owner, _items())
	assert_eq(corpses.mine(owner.character)[0]["n_items"], 3)
	assert_eq(corpses.loot(owner, id, "it_a1")["n_items"], 2)
	# M2 審查：翻屍體先寫 world.json 再寫角色檔（當機時最多消失，不會複製）
	assert_eq(h.ws.world_first_saves, 1, "loot saves world.json first")
	assert_eq(_evs(owner.peer_id, "corpse_looted")[0]["p"]["n_items"], 2)
	assert_true(_evs(owner.peer_id, "corpse_looted_other").is_empty())
	owner.character.location = { "region": "xixia_wild", "room": "xw_grass" }
	assert_eq(corpses.loot(owner, id)["reason"], "corpse_not_found", "other room")

func test_corpse_auth_full_and_repeat() -> void:
	var owner := _player("甲")
	var id := _corpse(owner, _items())
	for n in ["一", "二", "三", "四", "五"]:
		_player(n)
	h.options["corpse_auth_max"] = 4
	for n in ["一", "二", "三", "四"]:
		assert_true(corpses.authorize(owner, id, n)["ok"], n)
	assert_true(corpses.authorize(owner, id, "二")["ok"], "re-authorizing the same person is fine")
	assert_eq(corpses.find(id)["authorized"].size(), 4)
	assert_eq(corpses.authorize(owner, id, "五")["reason"], "corpse_auth_full")

func test_corpse_authorize_offline_player_by_name() -> void:
	var owner := _player("甲")
	var id := _corpse(owner, _items())
	h.ws.world["char_names"]["離線人"] = { "identity": "local_x", "char_id": "ch_offline1" }
	assert_true(corpses.authorize(owner, id, "離線人")["ok"])
	assert_eq(corpses.find(id)["authorized"], ["ch_offline1"])
	assert_true(h.ws.saves > 0, "world saved")

func test_corpse_public_notified_once_and_expire() -> void:
	var owner := _player("甲")
	var id := _corpse(owner, _items())
	var t0 := h.now
	h.now = t0 + 599.0
	corpses.expire(h.now)
	assert_true(_evs(owner.peer_id, "corpse_public").is_empty())
	h.now = t0 + 600.0
	corpses.expire(h.now)
	h.now = t0 + 660.0
	corpses.expire(h.now)
	assert_eq(_evs(owner.peer_id, "corpse_public").size(), 1, "only once")
	assert_eq(corpses.find(id)["public_notified"], true)
	assert_eq(corpses.mine(owner.character)[0]["public"], true)
	h.now = t0 + 1800.0
	corpses.expire(h.now)
	assert_true(corpses.find(id).is_empty())
	assert_eq(_evs(owner.peer_id, "corpse_expired").size(), 1)

func test_corpse_left_s_uses_time_scale() -> void:
	var owner := _player("甲")
	var id := _corpse(owner, _items())
	h.ws.time_scale = 10.0
	assert_eq(corpses.left_s(corpses.find(id), h.now), 60, "600 world s / 10")
	assert_eq(corpses.left_s(corpses.find(id), h.now + 595.0), 1)

func test_corpse_overweight_leaves_items() -> void:
	var owner := _player("甲")
	var id := _corpse(owner, _items())
	h.options["_carry_max"] = 0
	var r := corpses.loot(owner, id)
	assert_false(r["ok"])
	assert_true(r["reason"] in ["overweight", "inventory_full"], r["reason"])
	assert_eq(CorpseSystem.pieces(corpses.find(id)), 3, "nothing lost")
