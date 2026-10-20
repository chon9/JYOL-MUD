extends "res://tests/test_case.gd"
## WP-AMBIENT：RumorSystem 與 PkSystem 的傳聞接線（STORY_PLAN §5.1、§9.1）。
## 假主機 + 真的 GameData.tables + docs/story_staging/_ambient.json 的模板；任務列用本檔的小型 fixture（不依賴內容碎片）。

const FRAGMENT := "res://docs/story_staging/_ambient.json"

# ------------------------------------------------------------------ 假主機
class FakeWs extends RefCounted:
	var world := {}
	var time_scale := 1.0
	var out: Array = []
	func queue_event(peer_id: int, ch: String, key: String, p: Dictionary, ui := false) -> void:
		out.append({ "to": peer_id, "ch": ch, "key": key, "p": p, "ui": ui })
	func broadcast_event(ch: String, key: String, p: Dictionary, ui := false) -> void:
		out.append({ "to": "all", "ch": ch, "key": key, "p": p, "ui": ui })
	func queue_room_event(room_id: String, ch: String, key: String, p: Dictionary, _except := 0) -> void:
		out.append({ "to": "room:" + room_id, "ch": ch, "key": key, "p": p, "ui": false })

class FakeRegions extends RefCounted:
	func mark_room_dirty(_room_id: String, _except := 0) -> void:
		pass

class FakeHost extends RefCounted:
	var ws := FakeWs.new()
	var tables: Dictionary = {}
	var options: Dictionary = {}
	var rules: Dictionary = {}
	var index: WorldIndex
	var rng := RandomNumberGenerator.new()
	var regions := FakeRegions.new()
	var battles = null
	var party = null
	var char_store = null
	var rumor = null
	var list: Array = []
	var now := 0.0
	var day := 7200.0
	var saved: Array = []
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
	func save_char(ch) -> Error:
		saved.append(str(ch.id))
		return OK

var h: FakeHost
var r: RumorSystem
var _peer := 100

func before_each() -> void:
	h = FakeHost.new()
	var t: Dictionary = GameData.tables.duplicate()
	var tpl: Dictionary = (t.get("text_templates", {}) as Dictionary).duplicate()
	var frag: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENT))
	if frag is Dictionary:
		for row in frag.get("text_templates", []):
			tpl[str(row["id"])] = row
	t["text_templates"] = tpl
	var quests: Dictionary = (t.get("quests", {}) as Dictionary).duplicate()
	quests["q_tst_rumor"] = { "id": "q_tst_rumor", "name": "測試傳聞任務",
		"rumors": { "first": "rmr_q_tst_first", "each": "rmr_q_tst_each" },
		"outcomes": { "good": { "label": "好結局" } } }
	t["quests"] = quests
	t["rumors"] = {
		"rmr_tst_fore": { "id": "rmr_tst_fore", "kind": "FORESHADOW", "quest": "q_tst_rumor", "text": "rmr_tst_fore",
			"requires_world": { "not_first": "q_tst_rumor" }, "hours": [], "weight": 1, "era": "1.0A", "src": "proposal" },
		"rmr_tst_fore_night": { "id": "rmr_tst_fore_night", "kind": "FORESHADOW", "quest": "q_tst_rumor",
			"text": "rmr_tst_fore", "hours": ["子"], "weight": 0, "era": "1.0A", "src": "proposal" },
	}
	h.tables = t
	h.index = WorldIndex.new(t)
	h.rng.seed = 7
	r = RumorSystem.new(h)
	h.rumor = r
	_peer = 100

func after_each() -> void:
	r.host = null
	h.rumor = null
	r = null
	h = null

func _player(n: String, room := "xx_square") -> Session:
	_peer += 1
	var s := Session.new(_peer, "local_%032d" % _peer, n)
	var c := Character.new()
	c.id = "ch_%08d" % _peer
	c.identity = s.identity
	c.name = n
	c.combat_xp = 2000
	c.location = { "region": h.index.region_of(room), "room": room }
	s.character = c
	h.list.append(s)
	return s

func _rumors() -> Array:
	return h.ws.out.filter(func(e): return e["key"] == Protocol.E_RUMOR)

func _all_rumors() -> Array:
	return h.ws.out.filter(func(e): return e["key"] == Protocol.E_RUMOR and typeof(e["to"]) == TYPE_STRING and e["to"] == "all")

# ================================================================== 發布、節流
func test_post_broadcasts_on_jianghu() -> void:
	h.now = 50.0
	assert_true(r.post("DEED", "rmr_deed_fame", { "name": "甲", "fame": 100, "peer": 3, "atk_peer": 4, "_force": false }))
	var e := _all_rumors()
	assert_eq(e.size(), 1)
	assert_eq(str(e[0]["ch"]), Protocol.CH_JIANGHU)
	assert_eq(e[0]["p"], { "text_key": "rmr_deed_fame", "params": { "name": "甲", "fame": 100 }, "kind": "DEED", "world_s": 50.0 },
		"payload shape; peer fields and internal flags stripped")
	assert_eq(r.recent(5).size(), 1)
	assert_eq((h.ws.world["rumors"] as Array).size(), 1, "kept in ws.world.rumors")

func test_throttle_per_kind_and_force() -> void:
	assert_true(r.post("DEED", "rmr_deed_fame", { "name": "甲" }))
	assert_false(r.post("DEED", "rmr_deed_evil", { "name": "乙" }), "same kind within 120 s")
	assert_true(r.post("VILLAIN", "rmr_w_nanhai_defeated", { "name": "乙" }), "another kind is fine")
	assert_true(r.post("DEED", "rmr_deed_saint", { "name": "丙", "_force": true }), "_force skips the gap")
	h.now += 119.0
	assert_false(r.post("DEED", "rmr_deed_evil", { "name": "丁" }))
	h.now += 2.0
	assert_true(r.post("DEED", "rmr_deed_evil", { "name": "丁" }), "gap passed")
	h.options["rumor_min_gap_s"] = 0
	assert_true(r.post("DEED", "rmr_deed_join", { "name": "戊", "sect_name": "武當派" }), "gap 0")

func test_throttle_scales_with_time_scale() -> void:
	h.ws.time_scale = 50.0
	assert_true(r.post("DEED", "rmr_deed_fame", { "name": "甲" }))
	h.now += 120.0   # 2.4 真實秒
	assert_false(r.post("DEED", "rmr_deed_evil", { "name": "乙" }), "120 real seconds, not world seconds")
	h.now += 120.0 * 50.0
	assert_true(r.post("DEED", "rmr_deed_evil", { "name": "乙" }))

func test_dedupe_same_rumor_even_forced() -> void:
	assert_true(r.post("QUEST", "rmr_q_tst_first", { "name": "甲", "_force": true }))
	assert_false(r.post("QUEST", "rmr_q_tst_first", { "name": "甲", "_force": true }), "duplicate within 10 s")
	h.now += 11.0
	assert_true(r.post("QUEST", "rmr_q_tst_first", { "name": "甲", "_force": true }))

func test_option_off() -> void:
	h.options["rumors_enabled"] = false
	assert_false(r.post("DEED", "rmr_deed_fame", { "name": "甲" }))
	assert_true(_rumors().is_empty())
	assert_true(r.recent(10).is_empty())

func test_keep_last_50_and_recent_order() -> void:
	h.options["rumor_min_gap_s"] = 0
	for i in 60:
		h.now += 11.0
		r.post("DEED", "rmr_deed_fame", { "name": "人%d" % i })
	assert_eq((h.ws.world["rumors"] as Array).size(), 50)
	var rec := r.recent(3)
	assert_eq(rec.size(), 3)
	assert_eq(str(rec[2]["params"]["name"]), "人59", "newest last")
	assert_eq(str(rec[0]["params"]["name"]), "人57")
	assert_eq(r.recent(100).size(), 50)

func test_region_scope() -> void:
	var a := _player("甲", "xx_square")
	var b := _player("乙", "dl_square")
	assert_true(r.post("VILLAIN", "rmr_w_etou_roam", { "region_name": "西夏" }, "REGION", "xixia"))
	assert_true(_all_rumors().is_empty(), "not world-wide")
	assert_eq(h.ws.out.filter(func(e): return e["to"] == a.peer_id).size(), 1)
	assert_eq(h.ws.out.filter(func(e): return e["to"] == b.peer_id).size(), 0)
	assert_eq(r.list_for(a).size(), 1)
	assert_eq(r.list_for(b).size(), 0, "list hides other regions' rumors")

func test_login_replays_last_five() -> void:
	h.options["rumor_min_gap_s"] = 0
	for i in 8:
		h.now += 11.0
		r.post("DEED", "rmr_deed_fame", { "name": "人%d" % i })
	var s := _player("新來的")
	h.ws.out.clear()
	r.on_login(s)
	var got := h.ws.out.filter(func(e): return e["to"] == s.peer_id and e["key"] == Protocol.E_RUMOR)
	assert_eq(got.size(), 5)
	assert_eq(str(got[4]["p"]["params"]["name"]), "人7")
	assert_true(bool(got[0]["p"]["replay"]))

# ================================================================== 任務
func test_first_posts_once_and_must_send() -> void:
	r.post("QUEST", "rmr_other", { "name": "x" })   # 同 kind 剛發過：first 仍必發
	h.ws.world["quest_firsts"] = { "q_tst_rumor": "甲" }
	r.poll()
	var e := _all_rumors().filter(func(x): return x["p"]["text_key"] == "rmr_q_tst_first")
	assert_eq(e.size(), 1, "first rumor despite throttle")
	assert_eq(str(e[0]["p"]["params"]["name"]), "甲")
	assert_eq(str(e[0]["p"]["params"]["quest_name"]), "測試傳聞任務")
	h.now += 500.0
	r.poll()
	assert_eq(_all_rumors().filter(func(x): return x["p"]["text_key"] == "rmr_q_tst_first").size(), 1, "only once")

func test_existing_firsts_not_reposted_after_restart() -> void:
	h.ws.world["quest_firsts"] = { "q_tst_rumor": "甲" }
	var r2 := RumorSystem.new(h)
	r2.poll()
	assert_true(_rumors().is_empty())
	r2.host = null

func test_each_on_completion_count() -> void:
	var s := _player("乙")
	s.character.quests = { "active": {}, "done": {} }
	r.poll()   # 基準
	s.character.quests["done"]["q_tst_rumor"] = { "n": 1, "outcome": "good", "world_s": 1.0, "failed": 0 }
	r.poll()
	var e := _all_rumors()
	assert_eq(e.size(), 1)
	assert_eq(str(e[0]["p"]["text_key"]), "rmr_q_tst_each")
	assert_eq(str(e[0]["p"]["params"]["outcome_label"]), "好結局")
	r.poll()
	assert_eq(_all_rumors().size(), 1, "no repeat without a new completion")

func test_each_skipped_for_the_first_finisher() -> void:
	var s := _player("甲")
	s.character.quests = { "active": {}, "done": {} }
	r.poll()
	s.character.quests["done"]["q_tst_rumor"] = { "n": 1, "outcome": "good" }
	h.ws.world["quest_firsts"] = { "q_tst_rumor": "甲" }
	r.poll()
	var keys := _all_rumors().map(func(x): return str(x["p"]["text_key"]))
	assert_eq(keys, ["rmr_q_tst_first"], "first, not each")

func test_foreshadow_daily_and_stops_after_completion() -> void:
	assert_true(r.maybe_foreshadow(h.clock()), "foreshadow while nobody finished")
	assert_eq(str(_all_rumors()[0]["p"]["kind"]), "FORESHADOW")
	assert_eq(str(_all_rumors()[0]["p"]["params"]["quest_name"]), "測試傳聞任務")
	h.now += 700.0
	assert_false(r.maybe_foreshadow(h.clock()), "at most once per game day")
	h.now += h.day
	assert_true(r.maybe_foreshadow(h.clock()), "next day")
	h.ws.world["quest_firsts"] = { "q_tst_rumor": "甲" }
	h.now += h.day
	assert_false(r.maybe_foreshadow(h.clock()), "stopped after someone finished")

func test_tick_drives_foreshadow_on_hour_change() -> void:
	r.tick(0.1)
	assert_eq(_all_rumors().size(), 1)
	r.tick(0.1)
	assert_eq(_all_rumors().size(), 1)

# ================================================================== 事蹟
func test_deeds_baseline_and_milestones() -> void:
	var s := _player("甲")
	var c = s.character
	c.fame = 700
	r.on_login(s)
	r.poll()
	assert_true(_rumors().is_empty(), "existing fame is the baseline")
	c.fame = 1200
	r.poll()
	var e := _all_rumors()
	assert_eq(e.size(), 1)
	assert_eq(str(e[0]["p"]["text_key"]), "rmr_deed_fame")
	assert_eq(int(e[0]["p"]["params"]["fame"]), 1000)
	h.now += 200.0
	c.morality = -150
	r.poll()
	assert_eq(str(_all_rumors()[1]["p"]["text_key"]), "rmr_deed_evil")
	h.now += 200.0
	r.poll()
	assert_eq(_all_rumors().size(), 2, "evil only once")
	c.sect = "wudang"
	h.now += 200.0
	r.poll()
	assert_eq(str(_all_rumors()[2]["p"]["text_key"]), "rmr_deed_join")
	c.sect = ""
	c.sect_traitor = ["wudang"]
	h.now += 200.0
	r.poll()
	assert_eq(str(_all_rumors()[3]["p"]["text_key"]), "rmr_deed_betray")

func test_throttled_deed_retries_later() -> void:
	var s := _player("甲")
	r.poll()
	r.post("DEED", "rmr_deed_saint", { "name": "別人" })
	s.character.fame = 150
	r.poll()
	assert_eq(_all_rumors().size(), 1, "throttled")
	h.now += 121.0
	r.poll()
	assert_eq(_all_rumors().size(), 2, "sent once the gap passed")
	assert_eq(str(_all_rumors()[1]["p"]["text_key"]), "rmr_deed_fame")

# ================================================================== 存檔
func test_save_round_trip() -> void:
	h.options["rumor_min_gap_s"] = 0
	r.post("DEED", "rmr_deed_fame", { "name": "甲", "fame": 100 })
	h.now += 20.0
	r.post("VILLAIN", "rmr_w_nanhai_defeated", { "name": "乙", "room_name": "荒草坡" })
	var before := r.recent(10)
	h.ws.world = JSON.parse_string(JSON.stringify(h.ws.world))
	var r2 := RumorSystem.new(h)
	var after := r2.recent(10)
	assert_eq(after.size(), 2)
	for i in 2:
		assert_eq(str(after[i]["text_key"]), str(before[i]["text_key"]))
		assert_eq(str(after[i]["params"].get("name", "")), str(before[i]["params"].get("name", "")))
		assert_eq(int(after[i]["world_s"]), int(before[i]["world_s"]))
	r2.host = null

# ================================================================== PkSystem 接線（§5.1 #4）
func _pvp(kind: String, a: Session, b: Session) -> Dictionary:
	return { "bid": 1, "kind": kind, "room": "xw_road", "units": [
		{ "char_id": str(a.character.id), "name": str(a.character.name), "peer": a.peer_id, "side": 0, "died": false,
		  "fled": false, "killed_by_char": "" },
		{ "char_id": str(b.character.id), "name": str(b.character.name), "peer": b.peer_id, "side": 1, "died": true,
		  "fled": false, "killed_by_char": str(a.character.id) } ] }

func test_forced_pk_kill_default_records_rumor_and_keeps_m2_broadcast() -> void:
	var a := _player("甲", "xw_road")
	var b := _player("乙", "xw_road")
	var pk := PkSystem.new(h)
	assert_false(pk.pk_rumor_live, "default: record-only (M2 tests keep the world pk_kill)")
	pk.on_pvp_end(_pvp("FORCED", a, b))
	assert_true(_rumors().is_empty(), "no second live broadcast")
	assert_eq(h.ws.out.filter(func(e): return e["to"] is String and e["to"] == "all" and e["key"] == "pk_kill").size(), 1)
	var rec := r.recent(5)
	assert_eq(rec.size(), 1, "kept in the rumor log")
	assert_eq(str(rec[0]["kind"]), "PK")
	assert_eq(str(rec[0]["text_key"]), "e_pk_kill")
	assert_eq(rec[0]["params"], { "atk_name": "甲", "def_name": "乙", "room_name": h.room_name("xw_road") })
	assert_true(r.post("PK", "e_pk_kill", { "atk_name": "丙", "def_name": "丁" }), "record-only does not use up the PK gap")
	pk.host = null

func test_forced_pk_kill_goes_through_rumor() -> void:
	var a := _player("甲", "xw_road")
	var b := _player("乙", "xw_road")
	var pk := PkSystem.new(h)
	pk.pk_rumor_live = true
	pk.on_pvp_end(_pvp("FORCED", a, b))
	var rum := _all_rumors()
	assert_eq(rum.size(), 1, "PK rumor")
	assert_eq(str(rum[0]["p"]["kind"]), "PK")
	assert_eq(str(rum[0]["p"]["text_key"]), "e_pk_kill")
	assert_eq(rum[0]["p"]["params"], { "atk_name": "甲", "def_name": "乙", "room_name": h.room_name("xw_road") })
	assert_true(h.ws.out.filter(func(e): return e["to"] is String and e["to"] == "all" and e["key"] == "pk_kill").is_empty(),
		"no duplicate world broadcast")
	assert_eq(h.ws.out.filter(func(e): return e["to"] is int and e["to"] == a.peer_id and e["key"] == "pk_kill").size(), 1)
	assert_eq(h.ws.out.filter(func(e): return e["to"] is int and e["to"] == b.peer_id and e["key"] == "pk_kill").size(), 1)
	pk.host = null

func test_forced_pk_kill_falls_back_when_rumors_off() -> void:
	h.options["rumors_enabled"] = false
	var a := _player("甲", "xw_road")
	var b := _player("乙", "xw_road")
	var pk := PkSystem.new(h)
	pk.pk_rumor_live = true
	pk.on_pvp_end(_pvp("FORCED", a, b))
	assert_true(_rumors().is_empty())
	assert_eq(h.ws.out.filter(func(e): return e["to"] is String and e["to"] == "all" and e["key"] == "pk_kill").size(), 1,
		"old M2 broadcast")
	pk.host = null

func test_challenge_kill_never_a_rumor() -> void:
	var a := _player("甲", "xw_road")
	var b := _player("乙", "xw_road")
	var pk := PkSystem.new(h)
	pk.on_pvp_end(_pvp("CHALLENGE", a, b))
	assert_true(_rumors().is_empty())
	pk.host = null
