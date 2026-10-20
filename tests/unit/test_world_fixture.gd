extends "res://tests/test_case.gd"
## WP-WORLD 整合測試的共用基底（本檔沒有 test_ 方法，執行器只會載入它）。
## 用真正的 Autoload、真正的 res://data，以離線 peer（unique id 1）跑完整的 intent 路徑（G2）。
## 這些測試跨 WP（CHAR、BATTLE、DATA），合併後才會全綠（M1_PLAN G10）。

var ws: Node
var cs: Node
var sm: Node
var dir := ""
var world_name := "w_fixture"
var seq := 1000
var _old_root := ""
var events: Array = []          # 本機收到的全部事件（flush 後）
var results: Array = []         # [seq, ok, reason]
var my_uid := 0
var _await_me := false
var _last_await_tick := -1

func before_each() -> void:
	ws = tree.root.get_node("WorldServer")
	cs = tree.root.get_node("ClientState")
	sm = tree.root.get_node("SaveManager")
	tree.root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_restore_rules()
	dir = temp_dir("world")
	_old_root = sm.root_dir
	sm.root_dir = dir
	events.clear()
	results.clear()
	my_uid = 0
	_await_me = false
	assert_eq(ws.start(world_name), OK, "start")
	ws.rng.seed = 20261017
	cs.begin_local_session()
	if ws.sessions.has(1):
		ws.sessions[1].rate_limiter = TokenBucket.new(1000000.0, 1000000.0)   # 測試一口氣送很多 intent
	ws.flush()
	cs.events_received.connect(_on_events)
	cs.intent_result.connect(_on_result)
	cs.battle_opened.connect(_on_battle_opened)

func after_each() -> void:
	cs.events_received.disconnect(_on_events)
	cs.intent_result.disconnect(_on_result)
	cs.battle_opened.disconnect(_on_battle_opened)
	ws.stop()
	cs.capture_remote = Callable()   # 先 stop（host_closing 還會送給假的遠端 peer），再清掉擷取
	remote.clear()
	cs.reset()
	sm.root_dir = _old_root
	_restore_rules()
	remove_dir_recursive(dir)

func _restore_rules() -> void:
	var so: Dictionary = GameData.default_server_options()
	GameData.activate(so.get("enabled_eras", ["1.0A"]), so.get("rule_profile", {}))

## M3B_PLAN §2：新世界預設 1.0A＋1.0B；測 1.0A-only 世界行為的測試先切到指定的 era（資料視圖、世界存檔、房間索引）
func use_eras(eras: Array) -> void:
	assert_true(GameData.activate(eras, ws.world.get("rule_profile", {})), "activate %s" % str(eras))
	ws.world["enabled_eras"] = eras.duplicate()
	ws.options["enabled_eras"] = eras.duplicate()
	if ws.game != null:
		ws.game.index.build(GameData.tables)

func use_preset(preset: String) -> void:
	assert_true(GameData.activate(["1.0A"], { "preset": preset }), "activate " + preset)
	assert_eq(GameData.rules.get("death_rule", ""), {
		"classic_strict": "STRICT_2001", "classic_standard": "STANDARD",
		"later_official": "STANDARD", "friends_casual": "CASUAL" }.get(preset, ""), "preset " + preset)

func _on_events(batch: Array) -> void:
	for e in batch:
		events.append(e)
		if e.get("key", "") == "battle_await":
			var units: Array = e.get("p", {}).get("units", [])
			for u in units:
				if int(u) == my_uid and my_uid != 0:
					_await_me = true

func _on_result(s: int, ok: bool, reason: String) -> void:
	results.append([s, ok, reason])

func _on_battle_opened(state: Dictionary) -> void:
	my_uid = int(state.get("my_uid", 0))

# ---------- 取用 ----------
func game_ok() -> bool:
	return assert_true(ws.game != null, "GameHost unavailable: %s" % ws.game_error)

func host():
	return ws.game

func s() -> Session:
	return ws.sessions.get(1)

func ch():
	return s().character if s() != null else null

func tables() -> Dictionary:
	return GameData.tables

func sheet() -> Dictionary:
	return cs.sheet

func view() -> Dictionary:
	return cs.region_view

# ---------- intent ----------
func send(kind: String, args: Dictionary = {}) -> Dictionary:
	seq += 1
	var r: Dictionary = ws.handle_intent(1, seq, kind, args)
	ws.flush()
	return r

func ok(kind: String, args: Dictionary = {}) -> Dictionary:
	var r := send(kind, args)
	assert_true(r.get("ok", false), "%s %s -> %s" % [kind, str(args), str(r.get("reason", ""))])
	return r

func reason(kind: String, args: Dictionary = {}) -> String:
	return str(send(kind, args).get("reason", ""))

# ---------- 事件 ----------
func evs(key: String) -> Array:
	var out: Array = []
	for e in events:
		if e.get("key", "") == key:
			out.append(e)
	return out

func last(key: String) -> Dictionary:
	var a := evs(key)
	return a[a.size() - 1] if not a.is_empty() else {}

func lastp(key: String) -> Dictionary:
	return last(key).get("p", {})

func clear_events() -> void:
	events.clear()

# ---------- 角色與世界操作 ----------
func make_char(char_name := "測試俠客", city := "xixia", alloc := { "wit": 5 }, gender := "M"):
	ok("char_roll")
	var r := ok("char_create", { "name": char_name, "gender": gender, "birth_month": 3, "birth_city": city, "alloc": alloc })
	return ch() if r.get("ok", false) else null

## 測試捷徑：直接把角色放到某個房間（不扣錢、不遇敵）
func goto(room: String) -> void:
	host().regions.teleport(s(), room)
	host().flush_session(s(), true)
	ws.flush()

func item_count(item_id: String) -> int:
	return int(ch().inventory.count(item_id)) if ch() != null else 0

func first_uid(item_id: String) -> String:
	for it in ch().inventory.items:
		if str(it.get("id", "")) == item_id:
			return str(it.get("uid", ""))
	return ""

func give(item_id: String, n := 1) -> String:
	var r: Dictionary = host().give_item(ch(), item_id, n)
	assert_true(r.get("ok", false), "give %s ×%d: %s" % [item_id, n, str(r)])
	return str(r.get("uid", ""))

## 把世界時間撥到某個時辰的起點之後 1 秒，並讓主機跑一個 tick（晝夜轉換）
func set_shichen(idx: int) -> void:
	var day: float = float(ws.options.get("game_day_real_s", 7200))
	ws.world["world_time_s"] = ws.world_time() + WorldClock.seconds_until_shichen(ws.world_time(), idx, day) + 1.0
	ws.advance(0.1)

## 讓角色變得很強（整合測試只驗流程，不驗平衡）
func make_strong() -> void:
	var c = ch()
	for a in ["str", "agi", "con", "guts", "cal"]:
		c.attrs[a] = 120
	c.skills.set_level("basic_fist", 60, tables())
	c.skills.set_level("basic_blade", 60, tables())
	c.skills.set_level("basic_dodge", 60, tables())
	c.skills.set_level("basic_parry", 60, tables())
	c.clamp_vitals(tables(), ws.options)
	Survival.rest_full(c, tables(), ws.options)

func start_battle(monsters: Array, kind := "ENCOUNTER") -> int:
	clear_events()
	var bid: int = host().battles.start(s(), monsters, kind)
	ws.flush()
	return bid

# ---------- 戰鬥驅動 ----------
func _my_unit(b):
	for u in b.units:
		if int(u.uid) == my_uid:
			return u
	return null

static func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _choose(b, policy: String) -> Dictionary:
	var me = _my_unit(b)
	if me == null or policy == "defend":
		return { "cmd": "DEFEND" }
	var enemies: Array = []
	for u in b.units:
		if int(u.side) != int(me.side) and u.is_active():
			enemies.append(u)
	if policy == "flee":
		if b.grid.is_escape(me.pos):
			return { "cmd": "FLEE" }
		var best_e := me.pos as Vector2i
		var bd := 999
		for p in b.grid.reachable(me.pos, BattleFormulas.move_range(me)):
			for e in b.grid.escape:
				if _dist(p, e) < bd:
					bd = _dist(p, e)
					best_e = p
		if best_e != me.pos:
			return { "cmd": "MOVE", "target": [best_e.x, best_e.y] }
		return { "cmd": "DEFEND" }
	for e in enemies:
		if _dist(me.pos, e.pos) == 1:
			return { "cmd": "ATTACK", "target": [e.pos.x, e.pos.y] }
	var best: Vector2i = me.pos
	var best_d := 999
	for e in enemies:
		best_d = mini(best_d, _dist(me.pos, e.pos))
	for p in b.grid.reachable(me.pos, BattleFormulas.move_range(me)):
		for e in enemies:
			var d := _dist(p, e.pos)
			if d < best_d:
				best_d = d
				best = p
	if best != me.pos:
		return { "cmd": "MOVE", "target": [best.x, best.y] }
	return { "cmd": "DEFEND" }

## 跑到戰鬥結束（或 max_s 世界秒數）；回傳 ClientState.last_battle_result
func drive_battle(policy := "fight", max_s := 900.0) -> Dictionary:
	var t := 0.0
	var bid: int = s().battle_id
	while s().battle_id != 0 and t < max_s:
		var entry: Dictionary = host().battles.active.get(bid, {})
		if entry.is_empty():
			break
		var b = entry["battle"]
		var wait_mode: bool = bool(ws.options.get("wait_mode", true))
		var me = _my_unit(b)
		var ready: bool = _await_me or (not wait_mode and me != null and str(me.state) == "READY")
		if ready:
			var cmd := _choose(b, policy)
			cmd["battle_id"] = bid
			var r := send("battle_cmd", cmd)
			if not r.get("ok", false):
				var d := send("battle_cmd", { "battle_id": bid, "cmd": "DEFEND" })
				if not d.get("ok", false) and str(d.get("reason", "")) != "not_ready":
					fail("battle_cmd DEFEND failed: %s (after %s: %s)" % [str(d), str(cmd), str(r)])
			_await_me = false
		ws.advance(0.1)
		t += 0.1
	assert_eq(s().battle_id, 0, "battle should be over within %d s" % int(max_s))
	return cs.last_battle_result

# ---------- 多玩家輔助（M2_PLAN 4.6.10） ----------
## 假的遠端 session：peer 100 起遞增，送往它們的 deliver_* 經 ClientState.capture_remote 收進 remote[peer]
## remote[peer] = { identity, name, seq, events[], results[], sheet{}, view{}, battle_open{}, battle_close{},
##   char_list[], welcome{}, roster[], kick, rejected }
var remote: Dictionary = {}
var _fx_next_peer := 100

func _new_box(identity := "", display := "") -> Dictionary:
	return { "identity": identity, "name": display, "seq": 0, "events": [], "results": [], "sheet": {}, "view": {},
		"battle_open": {}, "battle_close": {}, "char_list": [], "welcome": {}, "roster": [], "kick": "", "rejected": "" }

func _capture(peer_id: int, what: String, payload: Variant) -> void:
	if not remote.has(peer_id):
		remote[peer_id] = _new_box()
	var box: Dictionary = remote[peer_id]
	match what:
		"events":
			(box["events"] as Array).append_array(payload)
		"result":
			(box["results"] as Array).append(payload)
		"view":
			box["view"] = payload
		_:
			box[what] = payload

func _ensure_capture() -> void:
	if not cs.capture_remote.is_valid():
		cs.capture_remote = _capture

static func make_identity(n: int) -> String:
	var h := "%08x%08x" % [n, 0x5eed]
	while h.length() < 32:
		h += "%08x" % (randi() & 0x7FFFFFFF)
	return "local_" + h.substr(0, 32)

## 只連線、握手（不建角）；回傳 peer。identity 空字串 → 自動產生
func connect_player(display := "", identity := "") -> int:
	_ensure_capture()
	var peer := _fx_next_peer
	_fx_next_peer += 1
	var ident := identity if identity != "" else make_identity(peer)
	remote[peer] = _new_box(ident, display)
	ws.on_peer_connected(peer)
	var why: String = ws.handle_hello(peer, {
		"protocol": Protocol.VERSION, "game_version": Protocol.GAME_VERSION,
		"content_hash": GameData.content_hash, "identity": ident, "display_name": display if display != "" else "客%d" % peer,
	})
	assert_eq(why, "", "hello peer %d" % peer)
	if ws.sessions.has(peer):
		ws.sessions[peer].rate_limiter = TokenBucket.new(1000000.0, 1000000.0)
	ws.flush()
	return peer

## 建立假的遠端 session，經 capture_remote 收件，建角並進入世界；回傳 peer
func add_player(char_name: String, city := "xixia") -> int:
	var peer := connect_player(char_name)
	var r1 := send_as(peer, "char_roll")
	assert_true(r1.get("ok", false), "char_roll as %d: %s" % [peer, str(r1)])
	var r2 := send_as(peer, "char_create", { "name": char_name, "gender": "M", "birth_month": 3, "birth_city": city,
		"alloc": { "wit": 5 } })
	assert_true(r2.get("ok", false), "char_create %s as %d: %s" % [char_name, peer, str(r2)])
	return peer

func send_as(peer: int, kind: String, args: Dictionary = {}) -> Dictionary:
	if not remote.has(peer):
		remote[peer] = _new_box()
	remote[peer]["seq"] = int(remote[peer]["seq"]) + 1
	var r: Dictionary = ws.handle_intent(peer, int(remote[peer]["seq"]), kind, args)
	ws.flush()
	return r

func reason_as(peer: int, kind: String, args: Dictionary = {}) -> String:
	return str(send_as(peer, kind, args).get("reason", ""))

func evs_for(peer: int, key: String) -> Array:
	var out: Array = []
	for e in remote.get(peer, {}).get("events", []):
		if e is Dictionary and e.get("key", "") == key:
			out.append(e)
	return out

func clear_events_for(peer: int) -> void:
	if remote.has(peer):
		remote[peer]["events"] = []

func sheet_for(peer: int) -> Dictionary:
	return remote.get(peer, {}).get("sheet", {})

func view_for(peer: int) -> Dictionary:
	return remote.get(peer, {}).get("view", {})

func battle_open_for(peer: int) -> Dictionary:
	return remote.get(peer, {}).get("battle_open", {})

func session_of(peer: int) -> Session:
	return ws.sessions.get(peer)

func identity_of(peer: int) -> String:
	return str(remote.get(peer, {}).get("identity", ""))

## 測試捷徑：把 peer 的角色直接放到某個房間
func goto_as(peer: int, room: String) -> void:
	var o := session_of(peer)
	if not assert_true(o != null and o.character != null, "goto_as %d: no character" % peer):
		return
	host().regions.teleport(o, room)
	host().flush_session(o, true)
	ws.flush()

## 模擬斷線（WorldServer.on_peer_disconnected）
func drop_player(peer: int) -> void:
	ws.on_peer_disconnected(peer)
	ws.flush()

## stop() 後以同一 world_id start()，舊 peer 全部消失；本機玩家重新進入（未選角）
func restart_world() -> void:
	ws.stop()
	remote.clear()
	assert_eq(ws.start(world_name), OK, "restart")
	ws.rng.seed = 20261017
	cs.begin_local_session()
	if ws.sessions.has(1):
		ws.sessions[1].rate_limiter = TokenBucket.new(1000000.0, 1000000.0)
	ws.flush()
