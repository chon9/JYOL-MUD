extends Node
## M2 多客戶端 bot（M2_PLAN 6.2）：四個角色（leader／member／pker／victim）各一個程序，由 tools/m2_acceptance.gd 啟動。
## 參數：--bot=res://tests/bots/m2_party_bot.gd --m2-role=<leader|member|pker|victim> --m2-run=<4 hex>
##       --m2-sync=<絕對路徑> [--m2-phase=return]
## 規則：只透過 NetworkManager.send_intent()／reconnect() 與 ClientState 互動；一次只送一個 intent。
## 同步只用檔案柵欄：<sync>/<role>.<step>（聊天本身是受測物，不拿來同步）。
## 成功印 M2_BOT_OK role=<r>（結束碼 0）；失敗印 M2_BOT_FAIL role=<r> step=<n> <原因>（結束碼 2）。

const ROLES := ["leader", "member", "pker", "victim"]
const NAME_PREFIX := { "leader": "隊長", "member": "隊員", "pker": "狂徒", "victim": "路人" }
const MIN_SEND_INTERVAL_MS := 60
const RESULT_TIMEOUT_MS := 15000
const BATTLE_TIMEOUT_MS := 300000
## 柵欄要比「最慢的一方」走得久：調息（≤150 s）＋一場戰鬥（≤BATTLE_TIMEOUT_MS）＋走路，否則慢的人一定讓等的人逾時
## （M2 第三輪審查：柵欄 300 s ＝ 戰鬥逾時，等頭目的路人必定先失敗）
const BARRIER_TIMEOUT_MS := 600000
const ROUTE := ["xx_gate_e", "xw_road", "xw_grass", "xw_hill"]
const BOSS_ROOM := "xw_hill"
const STANDBY_ROOM := "xw_grass"
const PK_ROOM := "xw_road"
const BOSS_NPC := "n_bandit_chief"
const BOSS_ATTEMPTS := 3

var role := ""
var run := ""
var sync_dir := ""
var phase := ""
var step := 0
var _done := false
var _results: Dictionary = {}
var _events: Array = []
var _last_send_ms := 0

# 戰鬥模型
var _in_battle := false
var _closed := false
var _close_result: Dictionary = {}
var _open_state: Dictionary = {}
var _open_count := 0
var _my_uid := 0
var _my_side := 0
var _await_me := false
var _units: Dictionary = {}
var _escape: Array = []
var _move_range := 2
var _bid := 0
var _defend_only := false
var _disconnected := false
var _bb := 0          # 最近一次 _mark 時的事件數：下一步等別人觸發的事件從這裡找（別人過柵欄前我一定已經寫了柵欄檔）
var _bb_open := 0     # 同上，battle_opened 次數

func _ready() -> void:
	SceneRouter.exit_code = 1
	var args := CliArgs.current()
	role = str(args.get("m2-role", ""))
	run = str(args.get("m2-run", ""))
	sync_dir = str(args.get("m2-sync", ""))
	phase = str(args.get("m2-phase", "")) if args.get("m2-phase") is String else ""
	ClientState.intent_result.connect(func(seq: int, ok: bool, reason: String): _results[seq] = [ok, reason])
	ClientState.events_received.connect(_on_events)
	ClientState.battle_opened.connect(_on_battle_opened)
	ClientState.battle_closed.connect(_on_battle_closed)
	ClientState.rejected.connect(func(r: String): _fail("rejected: " + r))
	NetworkManager.session_ended.connect(func(reason: String):
		_disconnected = true
		print("[M2Bot:%s] session ended: %s" % [role, reason]))
	print("[M2Bot:%s] ready run=%s sync=%s phase=%s" % [role, run, sync_dir, phase])
	if not (role in ROLES) or run == "" or sync_dir == "":
		_fail("bad args: role=%s run=%s sync=%s" % [role, run, sync_dir])
		return
	_run.call_deferred()

# ======================================================================== 基礎
func _on_events(batch: Array) -> void:
	for e in batch:
		if not (e is Dictionary):
			continue
		_events.append(e)
		if str(e.get("ch", "")) == "BATTLE":
			_battle_event(e)
	if _events.size() > 8000:
		_events = _events.slice(_events.size() - 4000)

func _frames(n := 1) -> void:
	for i in n:
		await get_tree().process_frame

func _sleep(secs: float) -> void:
	await get_tree().create_timer(secs, true, false, true).timeout

func _send(kind: String, args: Dictionary = {}, settle := true) -> Dictionary:
	while Time.get_ticks_msec() - _last_send_ms < MIN_SEND_INTERVAL_MS:
		await get_tree().process_frame
	_last_send_ms = Time.get_ticks_msec()
	var seq := NetworkManager.send_intent(kind, args)
	if seq < 0:
		return { "ok": false, "reason": "not_connected" }
	var t0 := Time.get_ticks_msec()
	while not _results.has(seq):
		await get_tree().process_frame
		if _done:
			return { "ok": false, "reason": "done" }
		if Time.get_ticks_msec() - t0 > RESULT_TIMEOUT_MS:
			return { "ok": false, "reason": "timeout" }
	var r: Array = _results[seq]
	_results.erase(seq)
	if settle:
		await _sleep(0.15)   # 讓主機 flush 事件與 sheet（0.25 秒批次）
	return { "ok": bool(r[0]), "reason": str(r[1]) }

func _must(kind: String, args: Dictionary = {}) -> bool:
	var r := await _send(kind, args)
	if not r["ok"]:
		_fail("%s %s -> %s" % [kind, str(args), r["reason"]])
		return false
	return true

func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	print("M2_BOT_FAIL role=%s step=%d %s" % [role, step, msg])
	_mark("failed", msg)
	SceneRouter.exit_code = 2
	get_tree().create_timer(0.3, true, false, true).timeout.connect(func(): SceneRouter.quit(2))

func _ok_finish() -> void:
	if _done:
		return
	_done = true
	print("M2_BOT_OK role=%s" % role)
	SceneRouter.exit_code = 0
	get_tree().create_timer(0.3, true, false, true).timeout.connect(func(): SceneRouter.quit(0))

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond

func _step(n: int, title: String) -> void:
	step = n
	print("[M2Bot:%s] step %d: %s" % [role, n, title])

func _wait_until(cond: Callable, timeout_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if _done or Time.get_ticks_msec() - t0 > timeout_ms:
			return false
		await get_tree().process_frame
	return true

func _events_since(key: String, from_index: int) -> Array:
	var out: Array = []
	for i in range(maxi(0, from_index), _events.size()):
		if str(_events[i].get("key", "")) == key:
			out.append(_events[i])
	return out

func _wait_event(key: String, from_index: int, timeout_ms: int, pred := Callable()) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while not _done:
		for e in _events_since(key, from_index):
			if not pred.is_valid() or pred.call(e.get("p", {})):
				return e
		if Time.get_ticks_msec() - t0 > timeout_ms:
			break
		await get_tree().process_frame
	return {}

# ---------- 檔案柵欄 ----------
func _path_of(r: String, s: String) -> String:
	return sync_dir.path_join("%s.%s" % [r, s])

func _mark(s: String, content := "") -> void:
	_bb = _events.size()
	_bb_open = _open_count
	if sync_dir == "":
		return
	var f := FileAccess.open(_path_of(role, s), FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()

func _has(r: String, s: String) -> bool:
	return FileAccess.file_exists(_path_of(r, s))

func _read(r: String, s: String) -> String:
	var p := _path_of(r, s)
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""

## 等 roles 都寫了 s；等待中若同房有隊友的戰鬥可加入就加入並打完（遇敵互助）
func _barrier(roles: Array, s: String, timeout_ms := BARRIER_TIMEOUT_MS, help := false) -> bool:
	var t0 := Time.get_ticks_msec()
	while not _done:
		var all_in := true
		for r in roles:
			if not _has(r, s):
				all_in = false
				if _has(r, "failed"):
					_fail("%s failed while waiting for %s: %s" % [r, s, _read(r, "failed")])
					return false
		if all_in:
			return true
		if Time.get_ticks_msec() - t0 > timeout_ms:
			_fail("barrier %s timed out waiting for %s" % [s, str(roles.filter(func(r): return not _has(r, s)))])
			return false
		if help and not _in_battle:
			await _join_if_possible()
		await _sleep(0.1)
	return false

# ---------- 角色表 ----------
func _sheet() -> Dictionary:
	return ClientState.sheet

func _view() -> Dictionary:
	return ClientState.region_view

func _room() -> String:
	return str(_sheet().get("location", {}).get("room", ""))

func _vital(k: String) -> int:
	return int(_sheet().get("vitals", {}).get(k, 0))

func _char_name(r: String) -> String:
	return str(NAME_PREFIX[r]) + run

func _my_name() -> String:
	return _char_name(role)

func _char_id_of(name: String) -> String:
	for p in _view().get("players", []):
		if str(p.get("name", "")) == name:
			return str(p.get("char_id", ""))
	return ""

func _party() -> Dictionary:
	var p: Variant = _sheet().get("party", {})
	return p if p is Dictionary else {}

func _party_size() -> int:
	return (_party().get("members", []) as Array).size()

func _inventory_entries() -> int:
	var n := 0
	for it in _sheet().get("inventory", []):
		if it is Dictionary:
			n += 1
	return n

# ======================================================================== 戰鬥
func _on_battle_opened(state: Dictionary) -> void:
	_in_battle = true
	_closed = false
	_close_result = {}
	_open_state = state
	_open_count += 1
	_await_me = false
	_bid = int(state.get("bid", 0))
	_my_uid = int(state.get("my_uid", 0))
	_my_side = int(state.get("my_side", 0))
	_units.clear()
	_escape.clear()
	for p in state.get("escape", []):
		_escape.append(Vector2i(int(p[0]), int(p[1])))
	for u in state.get("units", []):
		_add_unit(u)
	print("[M2Bot:%s] battle %d opened kind=%s my_side=%d units=%d" % [role, _bid, str(state.get("kind", "")),
		_my_side, _units.size()])

func _add_unit(u: Dictionary) -> void:
	var uid := int(u.get("uid", 0))
	var pos: Array = u.get("pos", [0, 0])
	_units[uid] = { "pos": Vector2i(int(pos[0]), int(pos[1])), "side": int(u.get("side", 0)), "alive": true,
		"qi": int(u.get("qi", 1)), "qi_max": maxi(1, int(u.get("qi_max", 1))), "name": str(u.get("name", "")),
		"kind": str(u.get("kind", "")) }
	if uid == _my_uid:
		_move_range = int(u.get("move_range", 2))

func _on_battle_closed(result: Dictionary) -> void:
	_closed = true
	_in_battle = false
	_close_result = result
	print("[M2Bot:%s] battle %d closed: %s died=%s rewards=%s" % [role, int(result.get("bid", 0)),
		str(result.get("result", "")), str(result.get("you_died", false)), str(result.get("rewards", {}))])

func _battle_event(e: Dictionary) -> void:
	var p: Dictionary = e.get("p", {})
	var key := str(e.get("key", ""))
	match key:
		"battle_await":
			for u in p.get("units", []):
				if int(u) == _my_uid:
					_await_me = true
		"battle_unit_join":
			var u: Variant = p.get("unit", {})
			if u is Dictionary:
				_add_unit(u)
		"battle_move":
			var uid := int(p.get("uid", 0))
			if _units.has(uid):
				var to: Array = p.get("to", [0, 0])
				_units[uid]["pos"] = Vector2i(int(to[0]), int(to[1]))
		"battle_kill", "battle_death", "battle_flee":
			var uid2 := int(p.get("uid", 0))
			if _units.has(uid2):
				_units[uid2]["alive"] = false
		"battle_rest", "battle_wound_tick":
			var uid4 := int(p.get("uid", 0))
			if _units.has(uid4) and p.has("qi"):
				_units[uid4]["qi"] = int(p["qi"])
		_:
			if p.has("def_uid") and p.has("def_qi"):
				var d := int(p["def_uid"])
				if _units.has(d):
					_units[d]["qi"] = int(p["def_qi"])

## 戰鬥結束時敵方全倒（死亡／逃走）＝我方贏（自己倒下時 close.result 是 DEFEAT，但隊伍可能贏了）
func _team_won() -> bool:
	var any_enemy := false
	for uid in _units:
		if int(_units[uid]["side"]) != _my_side:
			any_enemy = true
			if _units[uid]["alive"]:
				return false
	return any_enemy

static func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _occupied(p: Vector2i) -> bool:
	for uid in _units:
		if uid != _my_uid and _units[uid]["alive"] and _units[uid]["pos"] == p:
			return true
	return false

func _reachable(from: Vector2i, steps: int) -> Array:
	var out: Array = []
	var seen := { from: 0 }
	var q: Array = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if int(seen[c]) >= steps:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= 12 or n.y >= 8 or seen.has(n) or _occupied(n):
				continue
			seen[n] = int(seen[c]) + 1
			out.append(n)
			q.append(n)
	return out

## 自己這一方只剩自己、敵方有野狼 → 逃（M2_PLAN 6.2 戰鬥 AI；單人打不贏野狼）
func _should_flee() -> bool:
	var mates := 0
	var wolf := false
	for uid in _units:
		var u: Dictionary = _units[uid]
		if not u["alive"]:
			continue
		if int(u["side"]) == _my_side and str(u.get("kind", "")) == "PLAYER":
			mates += 1
		elif int(u["side"]) != _my_side and str(u["name"]).contains("野狼"):
			wolf = true
	return mates <= 1 and wolf and str(_open_state.get("kind", "")) == "ENCOUNTER"

func _decide() -> Dictionary:
	if _defend_only:
		return { "cmd": "DEFEND" }
	var me: Dictionary = _units.get(_my_uid, {})
	if me.is_empty():
		return { "cmd": "DEFEND" }
	var pos: Vector2i = me["pos"]
	var low: bool = float(me["qi"]) < 0.25 * float(me["qi_max"])
	var flee := (low or _should_flee()) and not _escape.is_empty() and str(_open_state.get("kind", "")) in ["ENCOUNTER", "GUARD"]
	if flee and pos in _escape:
		return { "cmd": "FLEE" }
	var enemies: Array = []
	for uid in _units:
		if _units[uid]["alive"] and int(_units[uid]["side"]) != _my_side:
			enemies.append(_units[uid])
	var adj: Dictionary = {}
	for e in enemies:
		if _dist(pos, e["pos"]) == 1 and (adj.is_empty() or int(e["qi"]) < int(adj["qi"])):
			adj = e
	if not adj.is_empty() and not flee:
		return { "cmd": "ATTACK", "target": [adj["pos"].x, adj["pos"].y] }
	var targets: Array = []
	if flee:
		targets = _escape
	else:
		for e in enemies:
			targets.append(e["pos"])
	if targets.is_empty():
		return { "cmd": "DEFEND" }
	var best_d := 999
	for t in targets:
		best_d = mini(best_d, _dist(pos, t))
	var cand := pos
	var cand_d := 999
	for c in _reachable(pos, _move_range):
		var d := 999
		for t in targets:
			d = mini(d, _dist(c, t))
		if d < cand_d or (d == cand_d and (c.x < cand.x or (c.x == cand.x and c.y < cand.y))):
			cand_d = d
			cand = c
	if cand != pos and cand_d < best_d:
		return { "cmd": "MOVE", "target": [cand.x, cand.y] }
	if not adj.is_empty():
		return { "cmd": "ATTACK", "target": [adj["pos"].x, adj["pos"].y] }
	return { "cmd": "DEFEND" }

func _fight() -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while not _closed:
		if _done:
			return {}
		if _disconnected:
			return {}
		if Time.get_ticks_msec() - t0 > BATTLE_TIMEOUT_MS:
			_fail("battle %d did not end" % _bid)
			return {}
		if _await_me:
			_await_me = false
			var cmd := _decide()
			cmd["battle_id"] = _bid
			var r := await _send("battle_cmd", cmd, false)
			if not r["ok"] and not (r["reason"] in ["battle_over", "battle_not_found", "not_ready"]):
				await _send("battle_cmd", { "battle_id": _bid, "cmd": "DEFEND" }, false)
			continue
		await get_tree().process_frame
	var res := _close_result
	await _sleep(0.3)   # 結算後的 sheet／view（重生位置）
	return res

func _handle_battle() -> Dictionary:
	if _in_battle or (not ClientState.battle_state.is_empty() and not _closed):
		return await _fight()
	return {}

## 同房有隊友的戰鬥可加入（view.battles joinable）→ battle_join 並打完
func _join_if_possible(only_bid := 0) -> Dictionary:
	if _in_battle:
		return {}
	for b in _view().get("battles", []):
		if not bool(b.get("joinable", false)):
			continue
		if only_bid != 0 and int(b.get("bid", 0)) != only_bid:
			continue
		var r := await _send("battle_join", { "battle_id": int(b.get("bid", 0)) })
		if r["ok"]:
			print("[M2Bot:%s] joined battle %d" % [role, int(b.get("bid", 0))])
			await _wait_until(func(): return _in_battle or _closed, 3000)
			return { "joined": true, "close": await _fight() }
	return {}

# ======================================================================== 移動
func _graph() -> Dictionary:
	var g := {}
	var maps: Dictionary = GameData.tables.get("maps", {})
	for rid in maps:
		for room in maps[rid].get("rooms", []):
			var edges: Array = []
			for ex in room.get("exits", []):
				edges.append([str(ex.get("to", "")), str(ex.get("dir", ""))])
			g[str(room.get("id", ""))] = edges
	return g

func _path(from: String, to: String) -> Array:
	var g := _graph()
	var prev := { from: null }
	var q: Array = [from]
	while not q.is_empty():
		var cur: String = q.pop_front()
		if cur == to:
			break
		for e in g.get(cur, []):
			if not prev.has(e[0]):
				prev[e[0]] = [cur, e]
				q.append(e[0])
	if not prev.has(to) or from == to:
		return []
	var out: Array = []
	var c := to
	while c != from:
		out.push_front(prev[c][1])
		c = prev[c][0]
	return out

## 原地調息到 ratio（站著不動不會遇敵；自然回復每 10 世界秒 2%）
func _rest_in_place(ratio := 0.9, timeout_ms := 150000) -> bool:
	var t0 := Time.get_ticks_msec()
	while _vital("qi") < int(_vital("qi_max") * ratio):
		if _done or Time.get_ticks_msec() - t0 > timeout_ms:
			return false
		if not _in_battle:
			await _join_if_possible()
		await _sleep(0.2)
	return true

## 走到 room；途中遇敵就打，到達時同房隊友的戰鬥能加入就加入；死亡（重生）就重新規劃
func _goto(room: String, auto_join := true) -> bool:
	for attempt in 30:
		if _done:
			return false
		if _room() == room:
			return true
		var path := _path(_room(), room)
		if path.is_empty():
			_fail("no path %s -> %s" % [_room(), room])
			return false
		var cur := _room()
		for e in path:
			if _done:
				return false
			if _room() != cur:
				break
			if _vital("qi") < int(_vital("qi_max") * 0.5):
				if not await _rest_in_place(0.8):
					_fail("could not rest at %s" % _room())
					return false
			var r := await _send("move", { "dir": e[1] })
			if not r["ok"]:
				if r["reason"] == "in_battle":
					await _wait_until(func(): return _in_battle, 2000)
					await _handle_battle()
					break
				_fail("move %s from %s -> %s" % [e[1], cur, r["reason"]])
				return false
			var dest: String = e[0]
			await _wait_until(func(): return _in_battle or _room() == dest, 1500)
			await _handle_battle()
			if _room() == dest and not _in_battle and auto_join:
				await _sleep(0.3)   # 房間視圖（battles）
				await _join_if_possible()
			if _room() != dest:
				break
			cur = dest
		if _room() == room:
			return true
	_fail("could not reach %s (at %s)" % [room, _room()])
	return false

## 隊伍一起走：每到一房寫柵欄，等 group 都到了再走下一步
func _walk_together(group: Array, rooms: Array, tag: String) -> bool:
	for r in rooms:
		if not await _goto(r):
			return false
		_mark("%s.%s" % [tag, r])
		if not await _barrier(group, "%s.%s" % [tag, r], BARRIER_TIMEOUT_MS, true):
			return false
		# 柵欄期間被拉進戰鬥或死亡：回到這一房
		if _room() != r and not await _goto(r):
			return false
	return true

# ======================================================================== 劇本
func _run() -> void:
	await _frames(2)
	if not await _wait_until(func(): return ClientState.in_world, 30000):
		_fail("never entered the world")
		return
	if phase == "return":
		await _member_return()
		return
	var steps := [_s1, _s2, _s3, _s4_6, _s7, _s8, _s9, _s10, _s11, _s12, _s13, _s14, _s15]
	for f in steps:
		if _done:
			return
		var ok: bool = await f.call()
		if not ok:
			_fail("step failed")
			return
		if role == "member" and step >= 12:
			return   # 隊員在第 12 步離線結束
	_mark("final")
	_ok_finish()

# ---- 1：建角 ----
func _s1() -> bool:
	_step(1, "connect + create character")
	if not await _must("char_list"):
		return false
	for c in ClientState.char_list.duplicate():
		if not await _must("char_delete", { "char_id": str(c["char_id"]), "confirm_name": str(c["name"]) }):
			return false
	for i in 300:
		var before := _events.size()
		if not await _must("char_roll"):
			return false
		var ev := await _wait_event("char_rolled", before, 5000)
		if ev.is_empty():
			return _check(false, "no char_rolled")
		var p: Dictionary = ev.get("p", {})
		if int(p.get("str", 0)) >= 22 and int(p.get("con", 0)) >= 19:
			break
	if not await _must("char_create", { "name": _my_name(), "gender": "M", "birth_month": 3, "birth_city": "xixia",
			"alloc": { "wit": 5 } }):
		return false
	if not await _wait_until(func(): return str(_sheet().get("char_id", "")) != "" and _room() != "", 5000):
		return _check(false, "no sheet after char_create")
	_mark("char", str(_sheet().get("char_id", "")))
	_mark("ready")
	return await _barrier(ROLES, "ready")

# ---- 2：組隊（路人第一次拒絕） ----
func _s2() -> bool:
	_step(2, "party")
	if role == "leader":
		var others := ["member", "pker", "victim"]
		if not await _wait_until(func():
				for r in others:
					if _char_id_of(_char_name(r)) == "":
						return false
				return true, 15000):
			return _check(false, "others not in view.players: %s" % str(_view().get("players", [])))
		var want := 1
		for r in others:
			var tid := _char_id_of(_char_name(r))
			var before := _events.size()
			if not await _must("party_invite", { "target": tid }):
				return false
			if _event_count_since("party_invite_sent", before) < 1 and (await _wait_event("party_invite_sent", before, 3000)).is_empty():
				return _check(false, "no party_invite_sent")
			if r == "victim":
				if (await _wait_event("party_declined", before, 20000)).is_empty():
					return _check(false, "victim's first refusal: no party_declined")
				# 拒絕後有重邀冷卻（pending_retry_cooldown_real_s【設計提案】，M2 第三輪審查）：先確認被擋，再等冷卻過去
				await _sleep(0.3)
				var r0 := await _send("party_invite", { "target": tid })
				if not _check(not r0["ok"] and r0["reason"] == "invite_cooldown", "re-invite right after a refusal -> %s" % str(r0)):
					return false
				var t_cd := Time.get_ticks_msec()
				while true:
					await _sleep(1.0)
					var r1 := await _send("party_invite", { "target": tid })
					if r1["ok"]:
						break
					if r1["reason"] != "invite_cooldown" or Time.get_ticks_msec() - t_cd > 60000:
						return _check(false, "re-invite after the cooldown -> %s" % str(r1))
			want += 1
			var w := want
			if not await _wait_until(func(): return _party_size() >= w, 20000):
				return _check(false, "party size %d < %d after inviting %s" % [_party_size(), w, r])
	else:
		var replies := 0
		var t0 := Time.get_ticks_msec()
		var seen := 0
		while _party_size() < 2:
			if _done or Time.get_ticks_msec() - t0 > 120000:
				return _check(false, "never joined the party")
			var inv := _events_since("party_invited", seen)
			if not inv.is_empty():
				seen = _events.size()
				var from := str(inv[-1].get("p", {}).get("from_char", ""))
				var accept := not (role == "victim" and replies == 0)
				replies += 1
				print("[M2Bot:%s] party_invited from %s -> accept=%s" % [role, from, str(accept)])
				if not await _must("party_reply", { "from": from, "accept": accept }):
					return false
			await _sleep(0.1)
	if not await _wait_until(func(): return _party_size() == 4, 30000):
		return _check(false, "party size %d != 4" % _party_size())
	var leader_id := _read("leader", "char")
	if not _check(str(_party().get("leader", "")) == leader_id, "leader %s != %s" % [str(_party().get("leader", "")), leader_id]):
		return false
	_mark("party")
	return await _barrier(ROLES, "party")

func _event_count_since(key: String, from_index: int) -> int:
	return _events_since(key, from_index).size()

# ---- 3：隊伍頻道、密語、謠言 ----
func _s3() -> bool:
	_step(3, "chat channels")
	var party_text := "集合" + run
	var whisper_text := "密語" + run
	var rumor_text := "謠言" + run
	var base := _bb
	if role == "leader":
		var water := _vital("water")
		if not await _must("chat", { "ch": "CHAT_PARTY", "text": party_text }):
			return false
		if not await _wait_until(func(): return _vital("water") <= water - 1, 5000):
			return _check(false, "party chat did not cost water (%d -> %d)" % [water, _vital("water")])
	else:
		var e := await _wait_event("chat_party", base, 20000, func(p): return str(p.get("text", "")) == party_text)
		if not _check(not e.is_empty(), "no chat_party '%s'" % party_text):
			return false
	_mark("chat1")
	if not await _barrier(ROLES, "chat1"):
		return false
	if role == "member":
		if not await _must("chat", { "ch": "CHAT_WHISPER", "to": _char_name("victim"), "text": whisper_text }):
			return false
		_mark("whisper.sent")
	elif role == "victim":
		var e2 := await _wait_event("chat_whisper", base, 20000, func(p): return str(p.get("text", "")) == whisper_text)
		if not _check(not e2.is_empty(), "victim got no chat_whisper"):
			return false
	else:
		if not await _barrier(["member"], "whisper.sent"):
			return false
		await _sleep(2.0)
		var leaked := _events_since("chat_whisper", base).filter(func(e): return str(e.get("p", {}).get("text", "")) == whisper_text)
		if not _check(leaked.is_empty(), "whisper leaked to %s" % role):
			return false
	_mark("chat2")
	if not await _barrier(ROLES, "chat2"):
		return false
	if role == "pker":
		await _sleep(0.6)
		if not await _must("chat", { "ch": "CHAT_RUMOR", "text": rumor_text }):
			return false
	else:
		var e3 := await _wait_event("chat_rumor", base, 20000, func(p): return str(p.get("text", "")) == rumor_text)
		if not _check(not e3.is_empty(), "no chat_rumor"):
			return false
		var p3: Dictionary = e3.get("p", {})
		if not _check(str(p3.get("from", "x")) == "" and int(p3.get("from_peer", -1)) == 0,
				"rumor not anonymous: %s" % str(p3)):
			return false
	_mark("chat3")
	return await _barrier(ROLES, "chat3")

# ---- 4–6：走到狼嚎丘、3 人開戰被拉入、第 4 人中途加入，打贏山賊頭目 ----
func _s4_6() -> bool:
	_step(4, "walk to the bandit chief")
	var trio := ["leader", "member", "pker"]
	var rooms := ROUTE.slice(0, 3)   # xx_gate_e、xw_road、xw_grass：四人一起
	if not await _walk_together(ROLES, rooms, "walk"):
		return false
	for attempt in range(1, BOSS_ATTEMPTS + 1):
		var res := await _boss_attempt(attempt, trio)
		if _done:
			return false
		if res == "ok":
			return true
		if res == "fail":
			return _check(false, "boss attempt %d failed" % attempt)
	return _check(false, "boss_lost (or the 4th never joined) after %d attempts" % BOSS_ATTEMPTS)

## 回傳 "ok" / "retry"
func _boss_attempt(k: int, trio: Array) -> String:
	_step(5, "boss attempt %d" % k)
	var tag := "boss%d" % k
	if role in trio:
		if not await _goto(BOSS_ROOM):
			return "fail"
		_mark(tag + ".at")
		if not await _barrier(trio, tag + ".at", BARRIER_TIMEOUT_MS, true):
			return "fail"
		if _room() != BOSS_ROOM and not await _goto(BOSS_ROOM):
			return "fail"
		if not await _rest_in_place(0.9):
			return "fail" if _check(false, "could not rest before the boss") else "fail"
		if _room() != BOSS_ROOM and not await _goto(BOSS_ROOM):
			return "fail"
		_mark(tag + ".ready")
	else:
		if not await _goto(STANDBY_ROOM):
			return "fail"
		if not await _rest_in_place(0.9):
			return "fail" if _check(false, "victim could not rest") else "fail"
		_mark(tag + ".ready")
	if not await _barrier(ROLES, tag + ".ready"):
		return "fail"
	var opens_before := _bb_open
	if role == "leader":
		var others_here := func():
			for r in ["member", "pker"]:
				if _char_id_of(_char_name(r)) == "":
					return false
			return true
		if not await _wait_until(others_here, 10000):
			_fail("member/pker not in xw_hill view")
			return "fail"
		if not await _must("talk", { "npc": BOSS_NPC }):
			return "fail"
		if not await _must("fight", { "npc": BOSS_NPC }):
			return "fail"
		if not await _wait_until(func(): return _open_count > opens_before, 3000):
			_fail("leader got no battle_opened after fight")
			return "fail"
		if not _check(str(_open_state.get("kind", "")) == "FIGHT", "boss kind %s" % str(_open_state.get("kind", ""))):
			return "fail"
		_mark(tag + ".started", str(_bid))
	elif role in trio:
		# 沒有自己送任何 intent：被拉進領隊的頭目戰（battle_opened）；之後才讀領隊寫的 bid 核對
		if not await _wait_until(func(): return _open_count > opens_before, 30000):
			_fail("not pulled into the boss battle (opens %d->%d)" % [opens_before, _open_count])
			return "fail"
		if not await _wait_until(func(): return _has("leader", tag + ".started"), 3000):
			_fail("leader never wrote %s.started" % tag)
			return "fail"
		var bid := int(_read("leader", tag + ".started"))
		if not _check(_bid == bid and str(_open_state.get("kind", "")) == "FIGHT",
				"pulled into battle %d kind %s, leader's is %d" % [_bid, str(_open_state.get("kind", "")), bid]):
			return "fail"
	var close := {}
	var joined := false
	if role == "victim":
		if not await _barrier(["leader"], tag + ".started"):
			return "fail"
		var bid2 := int(_read("leader", tag + ".started"))
		if not await _goto(BOSS_ROOM, false):
			return "fail"
		# 進丘時自己遇敵（野狼）的話上面已經打完或逃掉；接著找頭目那場
		var t0 := Time.get_ticks_msec()
		while not joined and Time.get_ticks_msec() - t0 < 20000 and not _done:
			if _room() != BOSS_ROOM:
				break   # 死了
			var jb := false
			for b in _view().get("battles", []):
				if int(b.get("bid", 0)) == bid2:
					jb = bool(b.get("joinable", false))
			if not jb:
				var still := false
				for b in _view().get("battles", []):
					if int(b.get("bid", 0)) == bid2:
						still = true
				if not still and Time.get_ticks_msec() - t0 > 2000:
					break   # 頭目那場已經結束
				await _sleep(0.1)
				continue
			var jbase := _events.size()
			var r := await _send("battle_join", { "battle_id": bid2 })
			if not r["ok"]:
				print("[M2Bot:victim] battle_join -> %s" % r["reason"])
				await _sleep(0.3)
				continue
			if not await _wait_until(func(): return _in_battle and _bid == bid2, 3000):
				_fail("battle_join ok but no battle_opened")
				return "fail"
			if (await _wait_event("battle_join", jbase, 3000)).is_empty():
				_fail("no battle_join event")
				return "fail"
			joined = true
			_mark(tag + ".joined")
		if joined:
			close = await _fight()
	else:
		close = await _fight()
	var won := _team_won() if not close.is_empty() else false
	if not close.is_empty() and not bool(close.get("you_died", false)) and str(close.get("result", "")) == "VICTORY":
		if not _check(int(close.get("rewards", {}).get("combat_xp", 0)) > 0, "survivor got no combat_xp: %s" % str(close)):
			return "fail"
	var got_xp := int(close.get("rewards", {}).get("combat_xp", 0)) if not close.is_empty() else 0
	_mark(tag + ".done", "%s|%d" % ["won" if won else "lost", got_xp])
	if not await _barrier(ROLES, tag + ".done"):
		return "fail"
	var ok := false
	var shares: PackedStringArray = []
	for r in ROLES:
		var d := _read(r, tag + ".done")
		if d.begins_with("won"):
			ok = true
		shares.append("%s=%s" % [r, d.get_slice("|", 1)])
	if role == "leader":
		print("[M2Bot:leader] boss rewards (combat_xp each; shared 1/√n among survivors): " + ", ".join(shares))
	ok = ok and _has("victim", tag + ".joined")
	print("[M2Bot:%s] boss attempt %d: team_won=%s victim_joined=%s" % [role, k, str(ok), str(_has("victim", tag + ".joined"))])
	await _sleep(0.5)
	return "ok" if ok else "retry"

# ---- 7：狂徒離隊，全員到東門外官道 ----
func _s7() -> bool:
	_step(7, "pker leaves the party; everyone to xw_road")
	var base := _bb
	if role == "pker":
		await _sleep(0.5)
		if not await _must("party_leave"):
			return false
		if not await _wait_until(func(): return _party().is_empty(), 5000):
			return _check(false, "pker still in party")
	else:
		var e := await _wait_event("party_left", base, 20000, func(p): return int(p.get("peer", 0)) != ClientState.my_peer_id)
		if not _check(not e.is_empty(), "no party_left for the pker"):
			return false
	if role == "victim":
		# 嚴格死亡規則：之前死過就身無長物；強制 PK 後的屍體至少要有兩樣東西（單件撿取後仍在）
		if _inventory_entries() < 2:
			if not await _restock():
				return false
	if not await _goto(PK_ROOM):
		return false
	_mark("road")
	return await _barrier(ROLES, "road", BARRIER_TIMEOUT_MS, false)

func _restock() -> bool:
	var npcs: Dictionary = GameData.tables.get("npcs", {})
	var inn := ""
	for nid in npcs:
		if str(npcs[nid].get("room", "")) == "xx_inn" and "SHOP" in npcs[nid].get("services", []):
			inn = nid
	print("[M2Bot:%s] restocking at %s" % [role, inn])
	if inn == "" or not await _goto("xx_inn"):
		return _check(false, "no inn to restock")
	for it in ["c_mantou", "c_water"]:
		if not await _must("buy", { "npc": inn, "item": it, "n": 1 }):
			return false
	return _check(_inventory_entries() >= 2, "restock failed: %d entries" % _inventory_entries())

# ---- 8：叫戰被拒、關閉接受叫戰 ----
func _s8() -> bool:
	_step(8, "challenge declined / refused")
	var base := _bb
	if role == "pker":
		var lid := _char_id_of(_char_name("leader"))
		if not _check(lid != "", "leader not in view"):
			return false
		if not await _must("challenge", { "target": lid }):
			return false
		if (await _wait_event("challenge_declined", base, 20000)).is_empty():
			return _check(false, "no challenge_declined")
		if not await _barrier(["leader"], "s8.pref"):
			return false
		var r := await _send("challenge", { "target": lid })
		if not _check(not r["ok"] and r["reason"] == "challenge_refused", "second challenge -> %s" % str(r)):
			return false
	elif role == "leader":
		var e := await _wait_event("challenge_request", base, 20000)
		if not _check(not e.is_empty(), "no challenge_request"):
			return false
		if not await _must("challenge_reply", { "from": str(e.get("p", {}).get("from_char", "")), "accept": false }):
			return false
		if not await _must("set_pref", { "key": "accept_challenge", "value": false }):
			return false
		if not await _wait_until(func(): return not bool(_sheet().get("prefs", {}).get("accept_challenge", true)), 5000):
			return _check(false, "prefs.accept_challenge still true")
		_mark("s8.pref")
	_mark("s8")
	return await _barrier(ROLES, "s8")

# ---- 9：強制 PK 殺死路人 ----
func _s9() -> bool:
	_step(9, "force_pk")
	var base := _bb
	var opens := _bb_open
	if role == "pker":
		var vid := _char_id_of(_char_name("victim"))
		if not _check(vid != "", "victim not in view"):
			return false
		var mo0 := int(_sheet().get("morality", 0))
		var ki0 := int(_sheet().get("killing_intent", 0))
		if not await _must("force_pk", { "target": vid }):
			return false
		if not await _wait_until(func(): return _open_count > opens, 3000):
			return _check(false, "pker got no battle_opened")
		if not _check(str(_open_state.get("kind", "")) == "FORCED" and _my_side == 0, "pker open %s side %d" % [str(_open_state.get("kind", "")), _my_side]):
			return false
		var close := await _fight()
		if not _check(str(close.get("result", "")) == "VICTORY", "pker result %s" % str(close)):
			return false
		var e := await _wait_event("pk_kill", base, 5000)
		if not _check(not e.is_empty(), "pker got no pk_kill"):
			return false
		if not await _wait_until(func(): return int(_sheet().get("pk", -1)) == 1, 5000):
			return _check(false, "pker sheet.pk = %s" % str(_sheet().get("pk")))
		# 5.2：強制擊殺非惡人 → 殺氣 +100、善惡 FORCED_KILL_MORALITY（−10；事件與角色表）
		if not await _wait_until(func(): return int(_sheet().get("killing_intent", -1)) == ki0 + 100 \
				and int(_sheet().get("morality", 0)) == mo0 + MoralityPk.FORCED_KILL_MORALITY, 5000):
			return _check(false, "pker killing_intent %d->%s morality %d->%s" % [ki0, str(_sheet().get("killing_intent")),
				mo0, str(_sheet().get("morality"))])
		if not _check(not _events_since("killing_intent_change", base).is_empty() and not _events_since("morality_change", base).is_empty(),
				"no killing_intent_change / morality_change events"):
			return false
		print("[M2Bot:pker] after the kill: pk=%d killing_intent %d->%d morality %d->%d" % [int(_sheet().get("pk", 0)), ki0,
			int(_sheet().get("killing_intent", 0)), mo0, int(_sheet().get("morality", 0))])
	elif role == "victim":
		_defend_only = true
		if not await _wait_until(func(): return _open_count > opens, 20000):
			return _check(false, "victim got no battle_opened")
		if not _check(str(_open_state.get("kind", "")) == "FORCED" and _my_side == 1, "victim open %s side %d" % [str(_open_state.get("kind", "")), _my_side]):
			return false
		var close2 := await _fight()
		_defend_only = false
		if not _check(bool(close2.get("you_died", false)), "victim did not die: %s" % str(close2)):
			return false
	else:
		var e2 := await _wait_event("pk_kill", base, 300000)
		if not _check(not e2.is_empty(), "%s got no pk_kill broadcast" % role):
			return false
	if role == "leader":
		var vname := _char_name("victim")
		if not await _wait_until(func(): return not _victim_corpse().is_empty(), 5000):
			return _check(false, "leader sees no corpse of %s: %s" % [vname, str(_view().get("corpses", []))])
		_mark("corpse", str(_victim_corpse().get("id", "")))
	_mark("s9")
	return await _barrier(ROLES, "s9")

func _victim_corpse() -> Dictionary:
	for c in _view().get("corpses", []):
		if str(c.get("owner_name", "")) == _char_name("victim"):
			return c
	return {}

# ---- 10：擊殺者撿屍被擋 ----
func _s10() -> bool:
	_step(10, "killer loot refused")
	if role == "pker":
		var cid := _read("leader", "corpse")
		var r := await _send("loot_corpse", { "corpse_id": cid })
		if not _check(not r["ok"] and r["reason"] == "corpse_protected", "pker loot -> %s" % str(r)):
			return false
	_mark("s10")
	return await _barrier(ROLES, "s10")

# ---- 11：死者授權隊長，隊長撿 1 件 ----
func _s11() -> bool:
	_step(11, "corpse authorize + single loot")
	var cid := _read("leader", "corpse")
	var base := _bb
	if role == "victim":
		var mine := false
		for c in _sheet().get("my_corpses", []):
			if str(c.get("id", "")) == cid:
				mine = true
		if not _check(mine, "corpse %s not in my_corpses %s" % [cid, str(_sheet().get("my_corpses", []))]):
			return false
		if not await _must("corpse_authorize", { "corpse_id": cid, "name": _char_name("leader") }):
			return false
		var e := await _wait_event("corpse_looted_by", base, 30000)
		if not _check(not e.is_empty(), "victim got no corpse_looted_by"):
			return false
	elif role == "leader":
		if (await _wait_event("corpse_auth_granted", base, 30000)).is_empty():
			return _check(false, "leader got no corpse_auth_granted")
		if not await _wait_until(func(): return bool(_victim_corpse().get("can_loot", false)) and not (_victim_corpse().get("items", []) as Array).is_empty(), 5000):
			return _check(false, "corpse not lootable for leader: %s" % str(_victim_corpse()))
		var c0 := _victim_corpse()
		var n_before := int(c0.get("n_items", 0))
		var first: Dictionary = (c0.get("items", []) as Array)[0]
		if not _check(not bool(c0.get("public", true)), "corpse already public (protection over)"):
			return false
		if not await _must("loot_corpse", { "corpse_id": cid, "item_uid": str(first.get("uid", "")) }):
			return false
		if (await _wait_event("corpse_looted_other", base, 5000)).is_empty():
			return _check(false, "no corpse_looted_other")
		var want := n_before - int(first.get("n", 1))
		if not await _wait_until(func(): return int(_victim_corpse().get("n_items", -1)) == want, 5000):
			return _check(false, "corpse n_items %s != %d" % [str(_victim_corpse()), want])
		_mark("corpse_n", str(want))
	_mark("s11")
	return await _barrier(ROLES, "s11")

# ---- 12：隊員離線 ----
func _s12() -> bool:
	_step(12, "member goes offline")
	if role == "member":
		_mark("leaving")
		await _sleep(0.5)
		NetworkManager.leave()
		_done = true
		print("M2_BOT_OK role=member")
		SceneRouter.exit_code = 0
		get_tree().create_timer(0.5, true, false, true).timeout.connect(func(): get_tree().quit(0))
		return true
	return true

# ---- 13：飛鴿傳書（離線收件、在線收件） ----
func _s13() -> bool:
	_step(13, "mail")
	if role == "leader":
		if not await _barrier(["orchestrator"], "member.left"):
			return false
		var base := _events.size()
		if not await _must("mail_send", { "to": _char_name("member"), "text": "隊員，頭目的刀在我這。" + run }):
			return false
		if (await _wait_event("mail_sent", base, 5000)).is_empty():
			return _check(false, "no mail_sent")
		_mark("mail1")
		var e := await _wait_event("mail_arrived", base, 60000)
		if not _check(not e.is_empty(), "no mail_arrived from victim"):
			return false
		if not await _wait_until(func(): return int(_sheet().get("mail_unread", 0)) == 1, 5000):
			return _check(false, "mail_unread %s != 1" % str(_sheet().get("mail_unread")))
		if not await _must("mail_list"):
			return false
		var mid := str(e.get("p", {}).get("id", ""))
		if not await _wait_until(func(): return _mail_by_id(mid).size() > 0, 5000):
			return _check(false, "mail %s not in mail_list %s" % [mid, str(ClientState.mail_list)])
		if not _check(str(_mail_by_id(mid).get("from_name", "")) == _char_name("victim"), "mail from %s" % str(_mail_by_id(mid))):
			return false
		if not await _must("mail_read", { "id": mid }):
			return false
		if not await _wait_until(func(): return bool(_mail_by_id(mid).get("read", false)) and int(_sheet().get("mail_unread", 1)) == 0, 5000):
			return _check(false, "mail not marked read: %s" % str(_mail_by_id(mid)))
		_mark("mail_id", mid)
	elif role == "victim":
		if not await _barrier(["leader"], "mail1"):
			return false
		var base2 := _events.size()
		if not await _must("mail_send", { "to": _char_name("leader"), "text": "隊長，屍體上的東西你先收著。" + run }):
			return false
		if (await _wait_event("mail_sent", base2, 5000)).is_empty():
			return _check(false, "victim: no mail_sent")
	_mark("s13")
	return await _barrier(["leader", "pker", "victim"], "s13")

func _mail_by_id(mid: String) -> Dictionary:
	for m in ClientState.mail_list:
		if m is Dictionary and str(m.get("id", "")) == mid:
			return m
	return {}

# ---- 14：記錄、等主機重開 ----
var _before := {}
func _s14() -> bool:
	_step(14, "record state; wait for host restart")
	_before = {
		"day": int(_sheet().get("clock", {}).get("day", 0)),
		"pk": int(_sheet().get("pk", 0)),
		"char_id": str(_sheet().get("char_id", "")),
		"room": _room(),
		"morality": int(_sheet().get("morality", 0)),
		"killing_intent": int(_sheet().get("killing_intent", 0)),
	}
	if role == "leader":
		var c := _victim_corpse()
		_before["corpse_id"] = str(c.get("id", ""))
		_before["corpse_n"] = int(c.get("n_items", -1))
	print("[M2Bot:%s] before restart: %s" % [role, str(_before)])
	_disconnected = false
	_mark("restart.ready", JSON.stringify(_before))
	return true

# ---- 15：重連、恢復檢查 ----
func _s15() -> bool:
	_step(15, "reconnect after host restart")
	if not await _wait_until(func(): return _disconnected or not ClientState.in_world, 120000):
		return _check(false, "host never went down")
	if not await _barrier(["orchestrator"], "host.restarted", 180000):
		return false
	var t0 := Time.get_ticks_msec()
	var last_try := 0
	while not ClientState.in_world:
		if _done:
			return false
		if Time.get_ticks_msec() - t0 > 90000:
			return _check(false, "not welcomed within 90 s of host restart")
		if NetworkManager.mode == NetworkManager.Mode.NONE and Time.get_ticks_msec() - last_try > 2000:
			last_try = Time.get_ticks_msec()
			var err := NetworkManager.reconnect()
			print("[M2Bot:%s] reconnect() -> %s" % [role, error_string(err)])
		await _sleep(0.2)
	_results.clear()
	if not await _must("char_select", { "char_id": str(_before["char_id"]) }):
		return false
	if not await _wait_until(func(): return str(_sheet().get("char_id", "")) == str(_before["char_id"]) and _room() != "", 10000):
		return _check(false, "no sheet after char_select")
	await _sleep(0.6)
	if not _check(_party().is_empty(), "party survived the restart: %s" % str(_party())):
		return false
	if not _check(int(_sheet().get("clock", {}).get("day", -1)) >= int(_before["day"]), "clock day %s < %d" % [str(_sheet().get("clock")), int(_before["day"])]):
		return false
	if not _check(_room() == str(_before["room"]), "room %s != %s" % [_room(), str(_before["room"])]):
		return false
	if role == "pker" and not _check(int(_sheet().get("pk", -1)) == 1, "pker pk after restart = %s" % str(_sheet().get("pk"))):
		return false
	if not _check(int(_sheet().get("morality", 0)) == int(_before["morality"]) \
			and int(_sheet().get("killing_intent", 0)) == int(_before["killing_intent"]),
			"morality/killing_intent changed across the restart: %s vs %s" % [str(_before), str([_sheet().get("morality"), _sheet().get("killing_intent")])]):
		return false
	if role == "leader":
		if not await _wait_until(func(): return str(_victim_corpse().get("id", "")) == str(_before["corpse_id"]), 5000):
			return _check(false, "corpse %s gone after restart: %s" % [str(_before["corpse_id"]), str(_view().get("corpses", []))])
		if not _check(int(_victim_corpse().get("n_items", -1)) == int(_before["corpse_n"]), "corpse items %s != %d" % [str(_victim_corpse()), int(_before["corpse_n"])]):
			return false
		var mid := _read("leader", "mail_id")
		if not await _must("mail_list"):
			return false
		if not await _wait_until(func(): return bool(_mail_by_id(mid).get("read", false)), 5000):
			return _check(false, "mail %s not read after restart: %s" % [mid, str(ClientState.mail_list)])
	return true

# ---- 16：隊員回來收信 ----
func _member_return() -> void:
	_step(16, "member returns, reads offline mail")
	var cid := _read("member", "char")
	var base := _events.size()
	if not await _must("char_select", { "char_id": cid }):
		return
	var e := await _wait_event("mail_waiting", base, 10000)
	if not _check(not e.is_empty(), "no mail_waiting on enter"):
		return
	if not _check(int(e.get("p", {}).get("n", 0)) == 1, "mail_waiting n=%s" % str(e.get("p"))):
		return
	if not await _must("mail_list"):
		return
	if not await _wait_until(func():
			for m in ClientState.mail_list:
				if str(m.get("from_name", "")) == _char_name("leader"):
					return true
			return false, 5000):
		_fail("leader's mail not in list: %s" % str(ClientState.mail_list))
		return
	var mid := ""
	for m in ClientState.mail_list:
		if str(m.get("from_name", "")) == _char_name("leader"):
			mid = str(m.get("id", ""))
	if not await _must("mail_read", { "id": mid }):
		return
	_mark("final")
	_ok_finish()
