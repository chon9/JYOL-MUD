extends "res://tests/unit/test_world_fixture.gd"
## WP-AMBIENT：WanderSystem（STORY_PLAN §5.2、§9.1）。
## 大部分測試用假主機 + 真的 GameData.tables（地圖、NPC、怪物）+ docs/story_staging/_ambient.json 的
## wanderers／monsters／npcs／模板（WP-MERGE 之前資料表還沒有 wanderers；合併後資料相同）。
## test_real_* 用真的 WorldServer／GameHost（test_world_fixture）走完整 intent 路徑；GameHost 還沒有 wander 時略過。

const FRAGMENT := "res://docs/story_staging/_ambient.json"

# ------------------------------------------------------------------ 假主機
class FakeWs extends RefCounted:
	var world := {}
	var time_scale := 1.0
	var out: Array = []        # { to: peer | "all" | "room:<id>", ch, key, p, ui }
	func queue_event(peer_id: int, ch: String, key: String, p: Dictionary, ui := false) -> void:
		out.append({ "to": peer_id, "ch": ch, "key": key, "p": p, "ui": ui })
	func broadcast_event(ch: String, key: String, p: Dictionary, ui := false) -> void:
		out.append({ "to": "all", "ch": ch, "key": key, "p": p, "ui": ui })
	func queue_room_event(room_id: String, ch: String, key: String, p: Dictionary, _except := 0) -> void:
		out.append({ "to": "room:" + room_id, "ch": ch, "key": key, "p": p, "ui": false })

class FakeRegions extends RefCounted:
	var dirty: Array = []
	func mark_room_dirty(room_id: String, _except := 0) -> void:
		dirty.append(room_id)

class FakeBattle extends RefCounted:
	var res: Dictionary = {}
	func outcome() -> Dictionary:
		return res

class FakeBattles extends RefCounted:
	var active: Dictionary = {}
	var started: Array = []
	var next_bid := 500
	func start(s: Session, ids: Array, kind: String) -> int:
		return start_ex(s, ids, kind, {})
	func start_ex(s: Session, ids: Array, kind: String, opts: Dictionary) -> int:
		next_bid += 1
		started.append({ "peer": s.peer_id, "ids": ids.duplicate(), "kind": kind, "opts": opts.duplicate(), "bid": next_bid })
		s.battle_id = next_bid
		active[next_bid] = { "battle": FakeBattle.new(), "chars": { s.peer_id: s.character } }
		return next_bid
	## 戰鬥結束：side 0 的玩家（peers）勝或敗
	func finish(bid: int, victory: bool, sessions: Array) -> void:
		var e: Dictionary = active[bid]
		var units := {}
		var uid := 1
		for s in sessions:
			units[uid] = { "uid": uid, "kind": "PLAYER", "side": 0, "peer": s.peer_id }
			uid += 1
			s.battle_id = 0
		units[uid] = { "uid": uid, "kind": "MONSTER", "side": 1, "peer": 0 }
		e["battle"].res = { "result": "VICTORY" if victory else "DEFEAT", "winner_side": 0 if victory else 1, "units": units }
		active.erase(bid)

class FakeHost extends RefCounted:
	var ws := FakeWs.new()
	var tables: Dictionary = {}
	var options: Dictionary = {}
	var rules: Dictionary = {}
	var index: WorldIndex
	var rng := RandomNumberGenerator.new()
	var regions := FakeRegions.new()
	var battles := FakeBattles.new()
	var rumor = null
	var wander = null
	var quests = null
	var sects = null
	var list: Array = []
	var now := 0.0
	var day := 7200.0
	func now_s() -> float:
		return now
	func day_s() -> float:
		return day
	func clock() -> Dictionary:
		return WorldClock.clock(now, day)
	func world_span(real_s: float) -> float:
		return real_s * ws.time_scale
	func real_span(world_s: float) -> float:
		return world_s / maxf(ws.time_scale, 0.001)
	func sessions() -> Array:
		return list
	func session_for_peer(peer: int) -> Session:
		for s in list:
			if s.peer_id == peer:
				return s
		return null
	func tell(s: Session, ch: String, key: String, p: Dictionary, ui := false) -> void:
		if not p.has("peer"):
			p["peer"] = s.peer_id
		ws.queue_event(s.peer_id, ch, key, p, ui)

var h: FakeHost
var w: WanderSystem
var _peer := 100

## 生效資料 + _ambient 碎片（同 id 以碎片為準，WP-MERGE 規則）
static func build_tables() -> Dictionary:
	var t: Dictionary = GameData.tables.duplicate()
	var frag: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENT))
	if not (frag is Dictionary):
		return t
	for pair in [["npcs", "npcs"], ["monsters", "monsters"], ["text_templates", "text_templates"],
			["wanderers", "wanderers"], ["reactions", "reactions"], ["ambient", "ambient"]]:
		var tbl: Dictionary = (t.get(pair[0], {}) as Dictionary).duplicate()
		for row in frag.get(pair[1], []):
			if row is Dictionary:
				tbl[str(row["id"])] = row.duplicate(true)
		t[pair[0]] = tbl
	return t

func before_each() -> void:
	if current_test.begins_with("test_real_"):
		super.before_each()
		return
	h = FakeHost.new()
	h.tables = build_tables()
	h.index = WorldIndex.new(h.tables)
	h.rng.seed = 4242
	# 測試要確定性：出手機率改成 100%
	for wid in h.tables["wanderers"]:
		h.tables["wanderers"][wid]["aggro"]["chance_pct"] = 100
	w = WanderSystem.new(h)
	h.wander = w
	_peer = 100

func after_each() -> void:
	if current_test.begins_with("test_real_"):
		super.after_each()   # _restore_rules 重新 activate：注入的 wanderers 一併清掉
		return
	if h.rumor != null:
		h.rumor.host = null
	w.host = null
	h.wander = null
	h.rumor = null
	w = null
	h = null

func _player(n: String, room: String, xp := 5000, morality := 0) -> Session:
	_peer += 1
	var s := Session.new(_peer, "local_%032d" % _peer, n)
	var c := Character.new()
	c.id = "ch_%08d" % _peer
	c.identity = s.identity
	c.name = n
	c.combat_xp = xp
	c.morality = morality
	c.location = { "region": h.index.region_of(room), "room": room }
	s.character = c
	h.list.append(s)
	return s

func _move(s: Session, room: String) -> void:
	s.character.location = { "region": h.index.region_of(room), "room": room }

func _to_hour(idx: int) -> void:
	h.now += WorldClock.seconds_until_shichen(h.now, idx, h.day)

func _evs(to: Variant, key: String) -> Array:
	return h.ws.out.filter(func(e): return e["key"] == key and typeof(e["to"]) == typeof(to) and e["to"] == to)

func _roam_regions(wid: String) -> Array:
	for e in h.tables["wanderers"][wid]["schedule"]:
		if str(e["mode"]) == "ROAM":
			return e["regions"]
	return []

# ================================================================== 資料
func test_fragment_rows_loaded() -> void:
	assert_true(h.tables.has("wanderers"), "wanderers table")
	for wid in ["w_nanhai", "w_yeerniang", "w_etou_xe", "w_etou_dlw", "w_etou_ss"]:
		var r: Dictionary = h.tables["wanderers"].get(wid, {})
		assert_false(r.is_empty(), wid)
		assert_true(h.index.has_room(str(r.get("home_room", ""))), wid + " home_room")
		assert_true(h.tables["monsters"].has(str(r.get("monster", ""))), wid + " monster")
		assert_true(h.tables["npcs"].has(str(r.get("npc", ""))), wid + " npc")
		for e in r["schedule"]:
			for reg in e.get("regions", []):
				assert_true(h.tables["regions"].has(reg), "%s region %s" % [wid, reg])
				assert_false(str(h.tables["regions"][reg]["type"]) in ["CITY", "SECT"], "roam region not city/sect")
	for key in [WanderSystem.T_WARN, WanderSystem.T_ATTACK, WanderSystem.T_ESCAPED, WanderSystem.T_CALL,
			WanderSystem.T_CALL_SENT, WanderSystem.T_HOME, WanderSystem.T_OUT, WanderSystem.T_MOVE_OUT, WanderSystem.T_MOVE_IN,
			"rmr_w_nanhai_roam", "rmr_w_nanhai_defeated", "rmr_w_yeerniang_defeated", "rmr_w_etou_defeated", "e_pk_kill"]:
		assert_true(h.tables["text_templates"].has(key), "template " + key)

# ================================================================== 安全房間
func test_safe_rooms() -> void:
	assert_true(w.is_safe_room("xx_square"), "CITY")
	assert_true(w.is_safe_room("xx_street"), "CITY street")
	assert_true(w.is_safe_room("sl_gate"), "SECT")
	assert_true(w.is_safe_room("xw_road"), "first room outside the gate")
	assert_true(w.is_safe_room("dlw_road"), "first room outside Dali north gate")
	assert_true(w.is_safe_room("sy_foot"), "next to Shaolin gate")
	assert_true(w.is_safe_room("sy_teahouse"), "INN room")
	assert_true(w.is_safe_room("de_oasis"), "rest point")
	assert_false(w.is_safe_room("xw_grass"))
	assert_false(w.is_safe_room("xe_mine"))
	assert_false(w.is_safe_room("ws_slope"))

# ================================================================== 排程
func test_schedule_home_then_roam_then_home() -> void:
	h.rumor = RumorSystem.new(h)
	_to_hour(4)   # 辰
	w.tick(0.1)
	assert_eq(w.room_of("w_nanhai"), "xx_street", "day: home")
	assert_eq(str(w.state("w_nanhai")["mode"]), "HOME")
	var watcher := _player("看熱鬧", "xx_street")
	w.tick(0.1)
	_to_hour(10)  # 戌
	w.tick(0.1)
	var room := w.room_of("w_nanhai")
	assert_eq(str(w.state("w_nanhai")["mode"]), "ROAM", "night: roam")
	assert_true(w.roam_ok(room, _roam_regions("w_nanhai")), "roam room allowed: " + room)
	assert_eq(room, "xw_grass", "nearest non-safe wild room from xx_street")
	assert_eq(_evs("room:xx_street", WanderSystem.T_OUT).size(), 2, "both villains left town (room line)")
	assert_eq(_evs("all", Protocol.E_RUMOR).size(), 1, "roam rumor (throttled per kind: only the first of the two)")
	_to_hour(3)   # 卯（隔天）
	w.tick(0.1)
	assert_eq(w.room_of("w_nanhai"), "xx_street", "dawn: back home")
	assert_false(_evs("room:" + room, WanderSystem.T_HOME).is_empty(), "'returns to town' to the old room")
	assert_true(watcher.battle_id == 0)

func test_roam_stays_in_allowed_regions_and_out_of_safe_rooms() -> void:
	_to_hour(10)
	w.tick(0.1)
	var regs := _roam_regions("w_nanhai")
	var seen := {}
	var interval := float(h.tables["wanderers"]["w_nanhai"]["move_every_ke"]) * w.ke_len()
	for i in 200:
		h.now += interval
		if int(h.clock()["shichen_idx"]) == 3:   # 天亮了：重新回到戌時
			_to_hour(10)
		w.tick(0.1)
		var r := w.room_of("w_nanhai")
		if str(w.state("w_nanhai")["mode"]) != "ROAM":
			continue
		seen[r] = true
		assert_true(r in h.index.rooms, "room exists")
		assert_true(h.index.region_of(r) in regs, "allowed region: " + r)
		assert_false(w.is_safe_room(r), "never a safe room: " + r)
	assert_true(seen.size() >= 3, "actually moves around (%d rooms)" % seen.size())
	assert_false(seen.has("xw_road"), "never at the gate room")

func test_frozen_host_does_not_move() -> void:
	_to_hour(10)
	w.tick(0.1)
	var r := w.room_of("w_nanhai")
	for i in 50:
		w.tick(1.0)   # 世界時間沒有前進（主機離線凍結時 now 不變）
	assert_eq(w.room_of("w_nanhai"), r)

func test_wanderers_disabled_stays_home_but_talk_fights() -> void:
	h.options["wanderers_enabled"] = false
	_to_hour(10)
	w.tick(0.1)
	assert_eq(w.room_of("w_nanhai"), "xx_street", "no night roaming")
	var p := _player("甲", "xx_street")
	w.tick(0.1)
	assert_true(w.pending_prompt(p.peer_id).is_empty(), "no aggro")
	assert_true(w.on_talk(p, "n_nanhai"), "talking still starts the fight")
	assert_eq(str(h.battles.started[0]["kind"]), "FIGHT")

# ================================================================== 出手
func _night_with_nanhai_at(room: String) -> void:
	_to_hour(10)
	w.tick(0.1)
	assert_true(w.place("w_nanhai", room), "place")

func test_newbie_immune() -> void:
	_night_with_nanhai_at("xw_grass")
	var n := _player("新手", "xw_road", 100)
	w.tick(0.1)
	_move(n, "xw_grass")
	w.tick(0.1)
	assert_true(w.pending_prompt(n.peer_id).is_empty(), "combat_xp < 500: immune")
	assert_true(_evs(n.peer_id, Protocol.E_VILLAIN_PROMPT).is_empty())
	assert_false(w.would_attack(n, "w_nanhai"))

func test_prompt_on_enter_and_escape() -> void:
	_night_with_nanhai_at("xw_grass")
	var p := _player("甲", "xw_road")
	w.tick(0.1)
	_move(p, "xw_grass")
	w.tick(0.1)
	var pr := _evs(p.peer_id, Protocol.E_VILLAIN_PROMPT)
	assert_eq(pr.size(), 1, "prompt")
	assert_eq(str(pr[0]["p"]["wid"]), "w_nanhai")
	assert_eq(int(pr[0]["p"]["countdown_s"]), 3)
	assert_true(bool(pr[0]["ui"]), "ui event")
	assert_eq(_evs(p.peer_id, WanderSystem.T_WARN).size() + _evs(p.peer_id, WanderSystem.T_WARN + "_w_nanhai").size(), 1,
		"visible warning line（第三輪審查：有 villain_warn_<wid> 就用惡人自己的句子）")
	# 倒數內離開
	h.now += 1.0
	_move(p, "xw_road")
	w.tick(0.1)
	var cl := _evs(p.peer_id, Protocol.E_VILLAIN_CLEAR)
	assert_eq(cl.size(), 1)
	assert_eq(str(cl[0]["p"]["why"]), "ESCAPED")
	assert_true(h.battles.started.is_empty(), "no battle")
	# 冷卻中再走進去：不出手
	_move(p, "xw_grass")
	w.tick(0.1)
	assert_true(w.pending_prompt(p.peer_id).is_empty(), "cooldown")
	# 冷卻過了（1 遊戲日）
	_move(p, "xw_road")
	w.tick(0.1)
	h.now += h.day + 1.0
	_to_hour(10)
	w.tick(0.1)
	w.place("w_nanhai", "xw_grass")
	_move(p, "xw_grass")
	w.tick(0.1)
	assert_false(w.pending_prompt(p.peer_id).is_empty(), "cooldown over: prompt again")

func test_countdown_ends_in_no_flee_chase_battle() -> void:
	_night_with_nanhai_at("xw_grass")
	var p := _player("甲", "xw_road")
	w.tick(0.1)
	_move(p, "xw_grass")
	w.tick(0.1)
	h.now += 2.0
	w.tick(0.1)
	assert_true(h.battles.started.is_empty(), "still counting down")
	h.now += 1.5
	w.tick(0.1)
	assert_eq(h.battles.started.size(), 1, "battle after countdown")
	var b: Dictionary = h.battles.started[0]
	assert_eq(str(b["kind"]), "CHASE")
	assert_eq(b["ids"], ["m_nanhai"])
	assert_true(bool(b["opts"]["no_flee"]), "chase battle cannot flee")
	assert_true(bool(b["opts"]["pull_party"]), "pulls the party")
	assert_eq(str(_evs(p.peer_id, Protocol.E_VILLAIN_CLEAR)[0]["p"]["why"]), "FOUGHT")
	assert_eq(_evs(p.peer_id, WanderSystem.T_ATTACK).size(), 1)
	assert_true(w.pending_prompt(p.peer_id).is_empty())

func test_time_scale_countdown_is_real_seconds() -> void:
	h.ws.time_scale = 50.0
	_night_with_nanhai_at("xw_grass")
	var p := _player("甲", "xw_road")
	w.tick(0.1)
	_move(p, "xw_grass")
	w.tick(0.1)
	h.now += 100.0   # 2 真實秒
	w.tick(0.1)
	assert_true(h.battles.started.is_empty(), "3 real seconds = 150 world seconds")
	h.now += 60.0
	w.tick(0.1)
	assert_eq(h.battles.started.size(), 1)

func test_villain_moves_into_player_room() -> void:
	_to_hour(10)
	w.tick(0.1)
	var p := _player("甲", "xw_wood")
	w.tick(0.1)
	w.place("w_nanhai", "xw_wood")
	assert_eq(_evs(p.peer_id, Protocol.E_VILLAIN_PROMPT).size(), 1, "villain arriving triggers the check too")

func test_villain_reply_fight_and_call() -> void:
	_night_with_nanhai_at("xw_grass")
	var p := _player("甲", "xw_road")
	var friend := _player("乙", "xw_wood")      # 同地區（xixia_wild）
	var far := _player("丙", "xx_square")       # 不同地區
	w.tick(0.1)
	assert_eq(str(w.villain_reply(p, "w_nanhai", "FIGHT")["reason"]), "villain_none", "no prompt yet")
	_move(p, "xw_grass")
	w.tick(0.1)
	assert_true(bool(_evs(p.peer_id, Protocol.E_VILLAIN_PROMPT)[0]["p"]["can_call"]), "someone in the region can hear")
	assert_eq(str(w.villain_reply(p, "w_other", "FIGHT")["reason"]), "villain_none", "wrong wid")
	assert_true(w.villain_reply(p, "w_nanhai", "CALL")["ok"])
	assert_eq(_evs(friend.peer_id, WanderSystem.T_CALL).size(), 1, "same-region player hears the call")
	assert_true(_evs(far.peer_id, WanderSystem.T_CALL).is_empty(), "other region does not")
	assert_eq(str(_evs(friend.peer_id, WanderSystem.T_CALL)[0]["p"]["npc_name"]), "南海鱷神")
	assert_true(h.battles.started.is_empty(), "calling does not stop the countdown, nor start the fight")
	var r := w.villain_reply(p, "w_nanhai", "FIGHT")
	assert_true(r["ok"], "fight now")
	assert_eq(h.battles.started.size(), 1)
	assert_eq(str(h.battles.started[0]["kind"]), "CHASE")
	assert_eq(str(w.villain_reply(p, "w_nanhai", "FIGHT")["reason"]), "villain_none", "prompt consumed")

func test_no_prompt_when_busy_or_safe() -> void:
	_night_with_nanhai_at("xw_grass")
	var p := _player("甲", "xw_road")
	w.tick(0.1)
	p.battle_id = 99
	_move(p, "xw_grass")
	w.tick(0.1)
	assert_true(w.pending_prompt(p.peer_id).is_empty(), "in battle")
	p.battle_id = 0
	_move(p, "xw_road")
	w.tick(0.1)
	w.place("w_nanhai", "xw_road")   # debug 放進安全房間：也不出手
	assert_true(w.pending_prompt(p.peer_id).is_empty(), "safe room")

func test_yeerniang_only_attacks_good() -> void:
	_to_hour(10)
	w.tick(0.1)
	var neutral := _player("中立", "ws_ford", 5000, 0)
	var good := _player("善人", "ws_ford", 5000, 50)
	w.tick(0.1)
	w.place("w_yeerniang", "ws_ford")
	assert_true(w.pending_prompt(neutral.peer_id).is_empty(), "morality 0: ignored")
	assert_false(w.pending_prompt(good.peer_id).is_empty(), "morality > 0: attacked")
	var vf := w.view_for(neutral)
	assert_eq(vf.size(), 1)
	assert_false(bool(vf[0]["hostile"]))
	assert_true(bool(w.view_for(good)[0]["hostile"]))

func test_daytime_talk_fight() -> void:
	_to_hour(5)   # 巳
	w.tick(0.1)
	var neutral := _player("中立", "xx_street", 100, 0)
	var good := _player("善人", "xx_street", 100, 10)
	w.tick(0.1)
	assert_true(w.pending_prompt(good.peer_id).is_empty(), "HOME: never attacks first")
	assert_false(w.on_talk(neutral, "n_yeerniang"), "Ye Erniang ignores morality 0")
	assert_true(w.on_talk(good, "n_yeerniang"), "morality > 0: talking starts the fight")
	assert_eq(str(h.battles.started[0]["kind"]), "FIGHT", "flee allowed")
	assert_eq(h.battles.started[0]["ids"], ["m_yeerniang"])
	assert_true(w.on_talk(neutral, "n_nanhai"), "Nanhai fights anyone who talks to him (newbies too)")
	assert_eq(_evs(neutral.peer_id, Protocol.E_FIGHT_START).size(), 1)
	assert_false(w.on_talk(neutral, "n_xx_smith"), "not a wanderer")

func test_defeat_respawn_and_rumor() -> void:
	h.rumor = RumorSystem.new(h)
	_night_with_nanhai_at("xw_grass")
	var p := _player("甲", "xw_road")
	var q := _player("乙", "xw_road")
	w.tick(0.1)
	_move(p, "xw_grass")
	w.tick(0.1)
	w.villain_reply(p, "w_nanhai", "FIGHT")
	var bid := int(h.battles.started[0]["bid"])
	h.battles.finish(bid, true, [p])
	h.ws.out.clear()
	w.tick(0.1)
	assert_eq(w.room_of("w_nanhai"), "", "gone after defeat")
	assert_false(w.alive("w_nanhai"))
	assert_true(float(w.state("w_nanhai")["respawn_s"]) > h.now)
	assert_false(w.npc_shown("n_nanhai", "xx_street"))
	var rum := _evs("all", Protocol.E_RUMOR)
	assert_eq(rum.size(), 1, "VILLAIN rumor")
	assert_eq(str(rum[0]["p"]["kind"]), "VILLAIN")
	assert_eq(str(rum[0]["p"]["text_key"]), "rmr_w_nanhai_defeated")
	assert_eq(str(rum[0]["p"]["params"]["name"]), "甲")
	assert_eq(int(h.rumor._ext(p.character)["deeds"]["villains"].get("w_nanhai", 0)), 1, "deed recorded")
	# 戰敗不算擊敗
	_move(q, "xw_grass")
	w.tick(0.1)
	assert_true(w.pending_prompt(q.peer_id).is_empty(), "nobody there")
	# 重生
	h.now += h.day + 1.0
	_to_hour(10)
	w.tick(0.1)
	assert_true(w.alive("w_nanhai"), "respawned")
	assert_ne_room(w.room_of("w_nanhai"))

func assert_ne_room(r: String) -> void:
	assert_true(r != "", "has a room")

func test_lost_fight_keeps_villain() -> void:
	_night_with_nanhai_at("xw_grass")
	var p := _player("甲", "xw_road")
	w.tick(0.1)
	_move(p, "xw_grass")
	w.tick(0.1)
	w.villain_reply(p, "w_nanhai", "FIGHT")
	h.battles.finish(int(h.battles.started[0]["bid"]), false, [p])
	w.tick(0.1)
	assert_true(w.alive("w_nanhai"), "player lost: villain stays")

func test_chase_npcs_option() -> void:
	_to_hour(4)
	w.tick(0.1)
	assert_true(w.alive("w_etou_xe"), "chase NPC present by default")
	assert_eq(h.index.region_of(w.room_of("w_etou_xe")), "xixia_east")
	assert_eq(str(w.state("w_etou_xe")["mode"]), "ROAM", "roams all day")
	assert_true(w.npc_shown("n_amb_etou_xe", w.room_of("w_etou_xe")))
	h.options["chase_npcs"] = false
	w.tick(0.1)
	assert_eq(w.room_of("w_etou_xe"), "", "option off: gone")
	assert_false(w.npc_shown("n_amb_etou_xe", "xe_mine"))
	var p := _player("甲", "xe_mine")
	assert_false(w.on_talk(p, "n_amb_etou_xe"))
	h.options["chase_npcs"] = true
	w.tick(0.1)
	assert_true(w.alive("w_etou_xe"), "back when re-enabled")

func test_chase_npc_attacks_in_daytime() -> void:
	_to_hour(5)
	w.tick(0.1)
	var room := w.room_of("w_etou_dlw")
	assert_eq(h.index.region_of(room), "dali_wild")
	var p := _player("甲", room)
	w.tick(0.1)
	w.place("w_etou_dlw", room)
	assert_false(w.pending_prompt(p.peer_id).is_empty(), "chase NPC attacks in the day")

func test_dialogue_blocks_prompt() -> void:
	_night_with_nanhai_at("xw_grass")
	var p := _player("甲", "xw_road")
	w.tick(0.1)
	if "dialogue" in p:
		p.set("dialogue", { "npc": "n_x", "quest": "q", "dlg": "d", "node": "n0" })
		_move(p, "xw_grass")
		w.tick(0.1)
		assert_true(w.pending_prompt(p.peer_id).is_empty(), "in a dialogue")
	else:
		assert_true(w._idle(p), "Session.dialogue not merged yet: idle")

func test_state_round_trip() -> void:
	_night_with_nanhai_at("xw_creek")
	var p := _player("甲", "xw_road")
	w.tick(0.1)
	_move(p, "xw_creek")
	w.tick(0.1)
	_move(p, "xw_road")
	w.tick(0.1)   # ESCAPED → 冷卻
	var saved: Variant = JSON.parse_string(JSON.stringify(h.ws.world))
	h.ws.world = saved
	var w2 := WanderSystem.new(h)
	assert_eq(w2.room_of("w_nanhai"), "xw_creek", "position survives save/load")
	assert_true(float(w2.state("w_nanhai")["cd"].get(str(p.character.id), 0.0)) > h.now, "cooldown survives")
	assert_true(w2.pending_prompt(p.peer_id).is_empty(), "prompts are not saved")
	w2.host = null

func test_disconnect_cancels_prompt() -> void:
	_night_with_nanhai_at("xw_grass")
	var p := _player("甲", "xw_road")
	w.tick(0.1)
	_move(p, "xw_grass")
	w.tick(0.1)
	assert_false(w.pending_prompt(p.peer_id).is_empty())
	h.list.erase(p)
	h.now += 5.0
	w.tick(0.1)
	assert_true(h.battles.started.is_empty(), "no battle for a disconnected player")
	assert_true(w.pending_prompt(p.peer_id).is_empty())

func test_place_unknown() -> void:
	assert_false(w.place("w_nobody", "xw_grass"))
	assert_false(w.place("w_nanhai", "no_such_room"))

# ================================================================== 主機鉤子（WP-ENGINE 的呼叫形狀）
func test_engine_hook_shapes() -> void:
	_to_hour(10)
	w.on_clock(10)
	assert_eq(str(w.state("w_nanhai")["mode"]), "ROAM", "on_clock applies the schedule")
	w.place("w_nanhai", "xw_grass")
	var p := _player("甲", "xw_road")
	w.on_login(p)
	_move(p, "xw_grass")
	w.on_moved(p, "xw_road", "xw_grass")
	assert_false(w.pending_prompt(p.peer_id).is_empty(), "on_moved(s, from, to) checks at once")
	w.on_moved(p, "xw_road", "xw_grass")
	assert_eq(_evs(p.peer_id, Protocol.E_VILLAIN_PROMPT).size(), 1, "same room twice: one prompt")
	w.villain_reply(p, "w_nanhai", "FIGHT")
	h.battles.finish(int(h.battles.started[0]["bid"]), true, [p])
	w.on_battle_settled(p, p.character, {})
	assert_false(w.alive("w_nanhai"), "on_battle_settled settles the defeat without waiting for tick")
	assert_true(w.debug_place("w_nanhai", "xw_wood"), "debug_place alias")
	w.on_time_jump(h.day)
	w.on_leave(p)
	assert_true(w.pending_prompt(p.peer_id).is_empty())

# ================================================================== 真主機（WorldServer + GameHost + WP-ENGINE 的鉤子）
## 把碎片的 wanderers 與模板放進生效資料（GameHost.tables 即時讀 GameData.tables）
func _inject_fragment() -> void:
	var t := build_tables()
	for wid in t["wanderers"]:
		t["wanderers"][wid]["aggro"]["chance_pct"] = 100   # 確定性
	GameData.tables["wanderers"] = t["wanderers"]
	GameData.tables["text_templates"] = t["text_templates"]
	GameData.tables["monsters"] = t["monsters"]

func _real_ready() -> bool:
	if not game_ok():
		return false
	if host().get("wander") == null:
		assert_true(true, "GameHost has no WanderSystem yet (WP-ENGINE not merged): skipped")
		return false
	_inject_fragment()
	return true

func test_real_night_prompt_then_chase_battle() -> void:
	if not _real_ready():
		return
	var hw = host().wander
	assert_true(hw is WanderSystem, "GameHost loaded WanderSystem")
	make_char("夜行人")
	ch().combat_xp = 5000
	set_shichen(10)
	ws.advance(0.2)
	assert_eq(str(hw.state("w_nanhai")["mode"]), "ROAM", "night")
	clear_events()
	goto("xw_grass")   # 入夜時南海鱷神出城最近的野外房間就是荒草坡：走進去（瞬移也會被輪詢到）即被盯上
	ws.advance(0.2)
	assert_true(hw.place("w_nanhai", "xw_grass"))   # 已有警告：不重複
	ws.flush()
	assert_eq(evs(Protocol.E_VILLAIN_PROMPT).size(), 1, "one prompt reaches the client")
	assert_eq(s().battle_id, 0, "countdown first")
	ws.advance(3.5 * float(ws.time_scale))
	ws.flush()
	assert_true(s().battle_id != 0, "chase battle after the countdown")
	var entry: Dictionary = host().battles.active.get(s().battle_id, {})
	assert_eq(str(entry.get("kind", "")), "CHASE")
	assert_true(bool(entry.get("opts", {}).get("no_flee", false)), "cannot flee")
	assert_eq(str(lastp(Protocol.E_VILLAIN_CLEAR).get("why", "")), "FOUGHT")

func test_real_escape_by_moving_and_villain_reply() -> void:
	if not _real_ready():
		return
	var hw = host().wander
	make_char("夜行人")
	ch().combat_xp = 5000
	set_shichen(10)
	goto("xw_grass")
	ws.advance(0.2)
	hw.place("w_nanhai", "xw_grass")
	ws.flush()
	assert_eq(reason(Protocol.I_VILLAIN_REPLY, { "wid": "w_other", "choice": "FIGHT" }), Protocol.R_VILLAIN_NONE)
	assert_true(send(Protocol.I_VILLAIN_REPLY, { "wid": "w_nanhai", "choice": "CALL" })["ok"], "call for help")
	ok("move", { "dir": "W" })   # 回到東門外官道（安全房間）
	assert_eq(str(lastp(Protocol.E_VILLAIN_CLEAR).get("why", "")), "ESCAPED")
	assert_eq(s().battle_id, 0)

func test_real_day_talk_fight_and_view() -> void:
	if not _real_ready():
		return
	make_char("路人")
	set_shichen(5)
	ws.advance(0.2)
	goto("xx_street")
	ws.advance(0.2)
	var wl: Array = view().get("wanderers", [])
	assert_true(wl.any(func(x): return str(x.get("wid", "")) == "w_nanhai"), "view.wanderers lists Nanhai at home")
	ok("talk", { "npc": "n_nanhai" })
	assert_true(s().battle_id != 0, "talking to Nanhai starts the fight")
	assert_eq(str(host().battles.active.get(s().battle_id, {}).get("kind", "")), "FIGHT", "flee allowed")

func test_real_rumor_list_intent() -> void:
	if not _real_ready():
		return
	if host().get("rumor") == null:
		return
	make_char("聽眾")
	host().rumor.post("DEED", "rmr_deed_fame", { "name": "某人", "fame": 100 })
	ws.flush()
	assert_false(evs(Protocol.E_RUMOR).is_empty(), "jianghu_rumor delivered")
	ok(Protocol.I_RUMOR_LIST)
	var items: Array = lastp(Protocol.E_RUMOR_LIST).get("items", [])
	assert_eq(items.size(), 1)
	assert_eq(str(items[0].get("text_key", "")), "rmr_deed_fame")
