extends "res://tests/test_case.gd"
## WP-AMBIENT：AmbientSystem（STORY_PLAN §5.3、§5.4、§9.1）。
## 假主機 + 真的 GameData.tables + docs/story_staging/_ambient.json 的 reactions／ambient／模板（WP-MERGE 之前資料表還沒有）。

const FRAGMENT := "res://docs/story_staging/_ambient.json"

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

class FakeQuests extends RefCounted:
	var hidden: Array = []
	func npc_visible(_ch, npc_id: String) -> bool:
		return not (npc_id in hidden)

class FakeHost extends RefCounted:
	var ws := FakeWs.new()
	var tables: Dictionary = {}
	var options: Dictionary = {}
	var rules: Dictionary = {}
	var index: WorldIndex
	var rng := RandomNumberGenerator.new()
	var quests = null
	var wander = null
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
	func sessions() -> Array:
		return list
	func tell(s: Session, ch: String, key: String, p: Dictionary, ui := false) -> void:
		if not p.has("peer"):
			p["peer"] = s.peer_id
		ws.queue_event(s.peer_id, ch, key, p, ui)

var h: FakeHost
var a: AmbientSystem
var _peer := 100

func before_each() -> void:
	h = FakeHost.new()
	var t: Dictionary = GameData.tables.duplicate()
	var frag: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENT))
	for pair in ["npcs", "text_templates", "reactions", "ambient"]:
		var tbl: Dictionary = (t.get(pair, {}) as Dictionary).duplicate()
		if frag is Dictionary:
			for row in frag.get(pair, []):
				tbl[str(row["id"])] = row
		t[pair] = tbl
	h.tables = t
	h.index = WorldIndex.new(t)
	h.rng.seed = 99
	a = AmbientSystem.new(h)
	_peer = 100

func after_each() -> void:
	a.host = null
	a = null
	h = null

func _player(n: String, room := "xx_square", xp := 2000, morality := 0, fame := 0) -> Session:
	_peer += 1
	var s := Session.new(_peer, "local_%032d" % _peer, n)
	var c := Character.new()
	c.id = "ch_%08d" % _peer
	c.name = n
	c.combat_xp = xp
	c.morality = morality
	c.fame = fame
	c.location = { "region": h.index.region_of(room), "room": room }
	s.character = c
	h.list.append(s)
	return s

func _to_hour(idx: int) -> void:
	h.now += WorldClock.seconds_until_shichen(h.now, idx, h.day)

# ================================================================== 時段與交談
func test_periods() -> void:
	assert_eq(AmbientSystem.period_of("卯"), "DAWN")
	assert_eq(AmbientSystem.period_of("辰"), "DAWN")
	for x in ["巳", "午", "未", "申"]:
		assert_eq(AmbientSystem.period_of(x), "DAY", x)
	assert_eq(AmbientSystem.period_of("酉"), "DUSK")
	for x in ["戌", "亥", "子", "丑", "寅"]:
		assert_eq(AmbientSystem.period_of(x), "NIGHT", x)

func test_talk_key_period_variant() -> void:
	var s := _player("甲")
	_to_hour(5)
	assert_eq(a.talk_key(s, "n_wujieshan"), "talk_n_wujieshan", "day: base line")
	_to_hour(11)
	assert_eq(a.talk_key(s, "n_wujieshan"), "talk_n_wujieshan@NIGHT", "night variant exists")
	assert_eq(a.talk_key(s, "n_xx_smith"), "talk_n_xx_smith", "no night variant: base")
	h.tables["text_templates"]["talk_n_xx_smith@DUSK"] = { "id": "talk_n_xx_smith@DUSK", "self": "x" }
	_to_hour(9)
	assert_eq(a.talk_key(s, "n_xx_smith"), "talk_n_xx_smith@DUSK")
	assert_eq(a.talk_key(s, "n_unknown"), "talk_n_unknown", "unknown npc: talk_<npc>")

func test_every_story_npc_has_night_line() -> void:
	var tpl: Dictionary = h.tables["text_templates"]
	for nid in h.tables["npcs"]:
		var row: Dictionary = h.tables["npcs"][nid]
		if not (str(row.get("kind", "")) in ["STORY", "QUEST"]):
			continue
		var base := str(row.get("talk", ""))
		if base == "" or not tpl.has(base):
			continue
		# 本碎片負責合併前就存在的 STORY／QUEST NPC；其他碎片的新 NPC 自己給 @NIGHT
		if GameData.tables.get("npcs", {}).has(nid):
			assert_true(tpl.has(base + "@NIGHT"), "night line for " + nid)

# ================================================================== 招呼語
func test_greetings() -> void:
	var newbie := _player("新手", "xx_inn", 100)
	assert_eq(a.greet_key(newbie, "n_xx_innkeeper"), "greet_newbie")
	var famous := _player("名人", "xx_inn", 5000, 0, 1500)
	assert_eq(a.greet_key(famous, "n_xx_innkeeper"), "greet_fame_shop", "shop greeting beats the general one")
	assert_eq(a.greet_key(famous, "n_wujieshan"), "greet_fame", "non-shop NPC")
	var evil := _player("惡人", "xx_inn", 5000, -600, 1500)
	assert_eq(a.greet_key(evil, "n_xx_innkeeper"), "greet_cold_evil", "evil beats fame")
	var worse := _player("大惡人", "xx_inn", 5000, -1200)
	assert_eq(a.greet_key(worse, "n_xx_innkeeper"), "greet_refuse_evil")
	var plain := _player("路人", "xx_inn", 5000)
	assert_eq(a.greet_key(plain, "n_xx_innkeeper"), "", "nothing special")
	var saint := _player("大俠", "xh_mid1", 5000, 800)
	assert_eq(a.greet_key(saint, "n_xh_canjizi"), "greet_evil_shop_cold", "evil sect shop vs good player")
	assert_eq(a.greet_key(newbie, "n_xx_guard"), "", "guards are not in any greet row")
	h.options["npc_reactions"] = "FLAVOR"
	assert_eq(a.greet_key(evil, "n_xx_innkeeper"), "greet_cold_evil", "FLAVOR keeps greetings")
	h.options["npc_reactions"] = "OFF"
	assert_eq(a.greet_key(evil, "n_xx_innkeeper"), "", "OFF: none")

# ================================================================== 價格與拒絕
func test_price_pct() -> void:
	var plain := _player("路人")
	assert_eq(a.price_pct(plain, "n_xx_pharmacist", "SHOP"), 100)
	var evil := _player("惡人", "xx_square", 5000, -600)
	assert_eq(a.price_pct(evil, "n_xx_pharmacist", "SHOP"), 120, "evil +20%")
	assert_eq(a.price_pct(evil, "n_xx_innkeeper", "INN"), 120, "inn too")
	var famous := _player("名人", "xx_square", 5000, 0, 1000)
	assert_eq(a.price_pct(famous, "n_xx_pharmacist", "SHOP"), 95, "fame −5%")
	var both := _player("惡名人", "xx_square", 5000, -600, 1000)
	assert_eq(a.price_pct(both, "n_xx_pharmacist", "SHOP"), 115, "deltas add up")
	assert_eq(a.price_pct(evil, "n_xh_canjizi", "SHOP"), 100, "evil sect shop does not mind evil")
	var good := _player("善人", "xx_square", 5000, 600)
	assert_eq(a.price_pct(good, "n_xh_canjizi", "SHOP"), 120, "evil sect shop charges the good more")
	assert_eq(a.price_pct(good, "n_xd_jingqi", "SHOP"), 120)
	assert_eq(a.price_pct(good, "n_xx_pharmacist", "SHOP"), 100)
	h.options["npc_reactions"] = "FLAVOR"
	assert_eq(a.price_pct(evil, "n_xx_pharmacist", "SHOP"), 100, "FLAVOR: prices untouched")
	h.options["npc_reactions"] = "OFF"
	assert_eq(a.price_pct(evil, "n_xx_pharmacist", "SHOP"), 100)

func test_refuse_reason() -> void:
	var evil := _player("惡人", "xx_square", 5000, -600)
	assert_eq(a.refuse_reason(evil, "n_xx_pharmacist", "SHOP"), "", "−600 only pays more")
	var worse := _player("大惡人", "xx_square", 5000, -1000)
	assert_eq(a.refuse_reason(worse, "n_xx_pharmacist", "SHOP"), "rx_refuse_evil")
	assert_eq(a.refuse_reason(worse, "n_xx_innkeeper", "INN"), "rx_refuse_evil")
	assert_eq(a.refuse_reason(worse, "n_xh_canjizi", "SHOP"), "", "evil shop serves the evil")
	var saint := _player("大俠", "xx_square", 5000, 1000)
	assert_eq(a.refuse_reason(saint, "n_xd_jingqi", "SHOP"), "rx_refuse_saint")
	assert_eq(a.refuse_reason(saint, "n_xx_pharmacist", "SHOP"), "")
	assert_true(h.tables["text_templates"].has("rx_refuse_evil"))
	assert_true(h.tables["text_templates"].has("rx_refuse_saint"))
	h.options["npc_reactions"] = "FLAVOR"
	assert_eq(a.refuse_reason(worse, "n_xx_pharmacist", "SHOP"), "", "FLAVOR never refuses")

func test_never_affected_services_and_npcs() -> void:
	var worse := _player("大惡人", "xx_square", 5000, -5000)
	for svc in ["RESPAWN", "TRAVEL", "QUEST", "TEACH", "JOIN", "JAIL", "GUIDE"]:
		assert_eq(a.price_pct(worse, "n_xx_innkeeper", svc), 100, svc)
		assert_eq(a.refuse_reason(worse, "n_xx_innkeeper", svc), "", svc)
	assert_eq(a.refuse_reason(worse, "n_xx_cha", "RESPAWN"), "", "查小鏞")
	assert_true(AmbientSystem.never_affected("n_xx_cha", h.tables["npcs"]["n_xx_cha"], "SHOP"), "查小鏞 by name")
	assert_true(AmbientSystem.never_affected("n_xx_guard", h.tables["npcs"]["n_xx_guard"], "SHOP"), "guard")
	for rid in h.tables["reactions"]:
		for svc in h.tables["reactions"][rid].get("services", []):
			assert_false(svc in AmbientSystem.NEVER_SERVICES, "reaction rows never list protected services: " + rid)

# ================================================================== 環境句
func test_line_candidates() -> void:
	var s := _player("甲", "xx_inn")
	_to_hour(5)
	var ids := a.candidates(s).map(func(r): return str(r["id"]))
	assert_true("amb_g_xx_inn_news" in ids, "room line")
	assert_false("amb_g_xx_night" in ids, "night line not in the day")
	_to_hour(11)
	ids = a.candidates(s).map(func(r): return str(r["id"]))
	assert_true("amb_g_xx_night" in ids, "region line at night")
	assert_true("amb_g_xx_inn_news" in ids)
	s.character.location = { "region": "hengshan_foot", "room": "hf_teahouse" }
	ids = a.candidates(s).map(func(r): return str(r["id"]))
	assert_true("amb_g_hf_teaman_road" in ids, "npc line when the NPC is here")
	var q := FakeQuests.new()
	q.hidden = ["n_hf_teaman"]
	h.quests = q
	ids = a.candidates(s).map(func(r): return str(r["id"]))
	assert_false("amb_g_hf_teaman_road" in ids, "NPC hidden by appear: no line")
	s.character.location = { "region": "xixia", "room": "xx_square" }
	_to_hour(5)
	ids = a.candidates(s).map(func(r): return str(r["id"]))
	assert_false("amb_g_hf_teaman_road" in ids, "NPC not here")

func test_lines_on_enter_chance_and_cooldown() -> void:
	var s := _player("甲", "xx_inn")
	var sent := 0
	for i in 400:
		a._next_line_s.clear()
		a._heard.clear()   # 第四輪審查：同一句不重複另有測試（test_world_story_review4）；這裡只量機率
		if a.maybe_line(s):
			sent += 1
	assert_true(sent > 50 and sent < 160, "about 25%% (%d / 400)" % sent)
	h.ws.out.clear()
	a._next_line_s.clear()
	a._heard.clear()
	var first := false
	for i in 100:
		if a.maybe_line(s):
			first = true
			break
	assert_true(first)
	var e: Array = h.ws.out.filter(func(x): return x["to"] == s.peer_id)
	assert_eq(e.size(), 1)
	assert_eq(str(e[0]["ch"]), Protocol.CH_SCENE)
	assert_true(h.tables["text_templates"].has(str(e[0]["key"])), "template exists")
	for i in 200:
		assert_false(a.maybe_line(s), "90 s cooldown")
	h.now += 91.0
	a._heard.clear()   # 90 秒冷卻之後（同一句的 15 分鐘不重複另測）
	var again := false
	for i in 200:
		if a.maybe_line(s):
			again = true
			break
	assert_true(again, "after the cooldown")

func test_lines_option_and_polling() -> void:
	var s := _player("甲", "xx_square")
	a.tick(0.1)   # 基準（登入不算進房）
	h.options["ambient_lines"] = false
	for i in 50:
		s.character.location = { "region": "xixia", "room": "xx_inn" if i % 2 == 0 else "xx_square" }
		a.tick(0.1)
		h.now += 100.0
	assert_true(h.ws.out.is_empty(), "option off: never")
	h.options["ambient_lines"] = true
	for i in 60:
		s.character.location = { "region": "xixia", "room": "xx_inn" if i % 2 == 0 else "xx_square" }
		a.tick(0.1)
		h.now += 100.0
	assert_false(h.ws.out.is_empty(), "polling sends lines on room change")

func test_fragment_ambient_rows_valid() -> void:
	for rid in h.tables["ambient"]:
		var r: Dictionary = h.tables["ambient"][rid]
		if not str(rid).begins_with("amb_g_"):
			continue
		assert_true(h.tables["text_templates"].has(str(r["text"])), "template for " + rid)
		if str(r.get("room", "")) != "":
			assert_true(h.index.has_room(str(r["room"])), "room for " + rid)
		if str(r.get("region", "")) != "":
			assert_true(h.tables["regions"].has(str(r["region"])), "region for " + rid)
		if str(r.get("npc", "")) != "":
			assert_true(h.tables["npcs"].has(str(r["npc"])), "npc for " + rid)
		for p in r.get("periods", []):
			assert_true(p in ["DAWN", "DAY", "DUSK", "NIGHT"], "period " + str(p))
