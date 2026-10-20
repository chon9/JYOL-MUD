extends Node
## M1 驗收 bot（M1_PLAN 6.4、WORLD_2001 §9.3）：從創角一路「走路」玩到血刀洞迷宮的鬼王。
## 世界照原作 2001 地理：城市之間只能走路（驛站馬車是伺服器選項，預設關），送信要自己把信走到目的地驛站。
## 執行：godot --headless --path . -- --no-steam --offline --world=m1_accept --profile=m1bot \
##       --bot=res://tests/bots/m1_playthrough_bot.gd --time-scale=50 --quit-after=1800
## 規則：只透過 NetworkManager.send_intent() 與 ClientState 的訊號／欄位互動；一次只送一個 intent，
## 等到同 seq 的 intent_result 才送下一個。成功印 M1_ACCEPT_OK（結束碼 0）；失敗印 M1_ACCEPT_FAIL step=<n>（結束碼 2）；
## 逾時由 --quit-after 以 1 結束。

const CHAR_NAME := "驗收俠客"
const MIN_SEND_INTERVAL_MS := 52          # 避免觸發 20/秒 速率限制
const RESULT_TIMEOUT_MS := 10000
const BATTLE_TIMEOUT_MS := 180000
const MEAL_HOURS := ["卯", "午", "酉"]
const INN_RESERVE := 150                  # 銀兩高於此值才去客棧／茶棚休息（住宿 15–20 兩），否則原地等自然回復
const LETTER_MONEY := 100                 # WORLD_2001 §5.2
const LETTER_FAME := 2
const GOTO_ATTEMPTS := 40                 # 長程步行途中回客棧休息、死亡重生都會重新規劃
const MAX_TRAIN_MOVES := 4000

var step := 0
var _done := false
var _results: Dictionary = {}             # seq -> [ok, reason]
var _events: Array = []                   # 全部事件（只保留最近的）
var _last_send_ms := 0

# 戰鬥模型（由 battle_state + 戰鬥事件維護）
var _in_battle := false
var _closed := false
var _close_result: Dictionary = {}
var _my_uid := 0
var _await_me := false
var _units: Dictionary = {}               # uid -> { pos: Vector2i, side, alive, qi, qi_max }
var _escape: Array = []                   # [Vector2i]
var _move_range := 2
var _arts: Array = []
var _bid := 0

# 統計
var wins := 0
var deaths := 0
var kills_by_name: Dictionary = {}
var art_used := false
var _suicide := false                     # 23：只 DEFEND，撐到死亡以驗證死亡規則
var _visited: Array = []                  # 走過的房間（檢查路線經過哪裡）
var _aborted := false                     # _goto 的 abort 條件成立（不是失敗）
var xp_reward_seen := false

func _ready() -> void:
	SceneRouter.exit_code = 1
	ClientState.intent_result.connect(_on_result)
	ClientState.events_received.connect(_on_events)
	ClientState.battle_opened.connect(_on_battle_opened)
	ClientState.battle_closed.connect(_on_battle_closed)
	ClientState.rejected.connect(func(r: String): _fail("rejected: " + r))
	print("[M1Bot] ready (time_scale=%.1f)" % WorldServer.time_scale)
	_run.call_deferred()

# ---------- 基礎 ----------
func _on_result(seq: int, ok: bool, reason: String) -> void:
	_results[seq] = [ok, reason]

func _on_events(batch: Array) -> void:
	for e in batch:
		if not (e is Dictionary):
			continue
		_events.append(e)
		if e.get("ch", "") == "BATTLE":
			_battle_event(e)
	if _events.size() > 4000:
		_events = _events.slice(_events.size() - 2000)

func _frames(n := 1) -> void:
	for i in n:
		await get_tree().process_frame

func _send(kind: String, args: Dictionary = {}, settle := true) -> Dictionary:
	while Time.get_ticks_msec() - _last_send_ms < MIN_SEND_INTERVAL_MS:
		await get_tree().process_frame
	_last_send_ms = Time.get_ticks_msec()
	var seq := NetworkManager.send_intent(kind, args)
	if seq < 0:
		_fail("send_intent %s: not connected" % kind)
		return { "ok": false, "reason": "not_connected" }
	var t0 := Time.get_ticks_msec()
	while not _results.has(seq):
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > RESULT_TIMEOUT_MS:
			_fail("no intent_result for %s (seq %d)" % [kind, seq])
			return { "ok": false, "reason": "timeout" }
	var r: Array = _results[seq]
	_results.erase(seq)
	if settle:
		await _frames(2)   # 讓主機 flush 事件
	return { "ok": bool(r[0]), "reason": str(r[1]) }

## 送出並要求成功；失敗時記錄 step 失敗
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
	print("M1_ACCEPT_FAIL step=%d %s" % [step, msg])
	SceneRouter.exit_code = 2
	get_tree().create_timer(0.3, true, false, true).timeout.connect(func(): SceneRouter.quit(2))

func _ok_finish() -> void:
	if _done:
		return
	_done = true
	print("M1_ACCEPT_OK wins=%d deaths=%d kills=%s" % [wins, deaths, str(kills_by_name)])
	SceneRouter.exit_code = 0
	get_tree().create_timer(0.3, true, false, true).timeout.connect(func(): SceneRouter.quit(0))

func _step(n: int, title: String) -> void:
	step = n
	print("[M1Bot] step %d: %s" % [n, title])

func _last_event(key: String) -> Dictionary:
	for i in range(_events.size() - 1, -1, -1):
		if _events[i].get("key", "") == key:
			return _events[i]
	return {}

func _event_count(key: String) -> int:
	var n := 0
	for e in _events:
		if e.get("key", "") == key:
			n += 1
	return n

## 等到 cond 成立；逾時回 false
func _wait_until(cond: Callable, timeout_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if _done or Time.get_ticks_msec() - t0 > timeout_ms:
			return false
		await get_tree().process_frame
	return true

# ---------- 角色表查詢 ----------
func _sheet() -> Dictionary:
	return ClientState.sheet

func _room() -> String:
	return str(_sheet().get("location", {}).get("room", ""))

func _vital(k: String) -> int:
	return int(_sheet().get("vitals", {}).get(k, 0))

func _money() -> int:
	return int(_sheet().get("money", 0))

func _xp() -> int:
	return int(_sheet().get("combat_xp", 0))

func _skill_level(id: String) -> int:
	for s in _sheet().get("skills", []):
		if str(s.get("id", "")) == id:
			return int(s.get("level", 0))
	return 0

func _skill_prof(id: String) -> int:
	for s in _sheet().get("skills", []):
		if str(s.get("id", "")) == id:
			return int(s.get("prof", 0))
	return 0

func _items(id: String) -> Array:
	var out: Array = []
	for it in _sheet().get("inventory", []):
		if str(it.get("id", "")) == id:
			out.append(it)
	return out

func _count(id: String) -> int:
	var n := 0
	for it in _items(id):
		n += int(it.get("n", 1))
	return n

func _first_uid(id: String) -> String:
	var it := _items(id)
	return str(it[0].get("uid", "")) if not it.is_empty() else ""

func _quest_ids() -> Array:
	var out: Array = []
	for q in _sheet().get("quests", []):
		out.append(str(q.get("id", "")))
	return out

func _shichen() -> String:
	return str(_sheet().get("clock", {}).get("text", "")).left(1)

# ---------- 戰鬥 ----------
func _on_battle_opened(state: Dictionary) -> void:
	_in_battle = true
	_closed = false
	_close_result = {}
	_await_me = false
	_bid = int(state.get("bid", 0))
	_my_uid = int(state.get("my_uid", 0))
	_units.clear()
	_escape.clear()
	for p in state.get("escape", []):
		_escape.append(Vector2i(int(p[0]), int(p[1])))
	for u in state.get("units", []):
		var uid := int(u.get("uid", 0))
		_units[uid] = { "pos": Vector2i(int(u["pos"][0]), int(u["pos"][1])), "side": int(u.get("side", 0)),
			"alive": true, "qi": int(u.get("qi", 1)), "qi_max": maxi(1, int(u.get("qi_max", 1))),
			"name": str(u.get("name", "")) }
		if uid == _my_uid:
			_move_range = int(u.get("move_range", 2))
			_arts = u.get("arts", [])

func _on_battle_closed(result: Dictionary) -> void:
	_closed = true
	_in_battle = false
	_close_result = result
	var res := str(result.get("result", ""))
	if res == "VICTORY":
		wins += 1
		if int(result.get("rewards", {}).get("combat_xp", 0)) > 0:
			xp_reward_seen = true
	if bool(result.get("you_died", false)):
		deaths += 1
	print("[M1Bot] battle %d closed: %s died=%s rewards=%s xp=%d" % [int(result.get("bid", 0)), res,
		str(result.get("you_died", false)), str(result.get("rewards", {})), _xp()])

func _battle_event(e: Dictionary) -> void:
	var p: Dictionary = e.get("p", {})
	var key := str(e.get("key", ""))
	match key:
		"battle_await":
			for u in p.get("units", []):
				if int(u) == _my_uid:
					_await_me = true
		"battle_move":
			var uid := int(p.get("uid", 0))
			if _units.has(uid):
				var to: Array = p.get("to", [0, 0])
				_units[uid]["pos"] = Vector2i(int(to[0]), int(to[1]))
		"battle_kill", "battle_death":
			var uid2 := int(p.get("uid", 0))
			if _units.has(uid2):
				_units[uid2]["alive"] = false
			if key == "battle_kill":
				var nm := str(p.get("name", ""))
				kills_by_name[nm] = int(kills_by_name.get(nm, 0)) + 1
		"battle_flee":
			var uid3 := int(p.get("uid", 0))
			if _units.has(uid3):
				_units[uid3]["alive"] = false
		"battle_rest", "battle_wound_tick":
			var uid4 := int(p.get("uid", 0))
			if _units.has(uid4) and p.has("qi"):
				_units[uid4]["qi"] = int(p["qi"])
		_:
			if p.has("def_uid") and p.has("def_qi"):
				var d := int(p["def_uid"])
				if _units.has(d):
					_units[d]["qi"] = int(p["def_qi"])

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

func _art_cmd(target: Vector2i) -> Dictionary:
	for a in _arts:
		if str(a.get("id", "")) != "sl_changquan":
			continue
		var best := {}
		for m in a.get("moves", []):
			if bool(m.get("usable", false)) and int(m.get("cost_inner", 0)) == 0 and int(m.get("cost_jing", 0)) == 0:
				best = m
				break   # 黑虎掏心（第一招）
		if not best.is_empty():
			return { "cmd": "ART", "art": "sl_changquan", "move": str(best["id"]), "power_tenths": 10,
				"target": [target.x, target.y] }
	return {}

func _decide() -> Dictionary:
	if _suicide:
		return { "cmd": "DEFEND" }
	var me: Dictionary = _units.get(_my_uid, {})
	if me.is_empty():
		return { "cmd": "DEFEND" }
	var pos: Vector2i = me["pos"]
	var low: bool = float(me["qi"]) < 0.25 * float(me["qi_max"])
	if low and pos in _escape:
		return { "cmd": "FLEE" }
	var enemies: Array = []
	for uid in _units:
		if _units[uid]["alive"] and int(_units[uid]["side"]) != int(me["side"]):
			enemies.append(_units[uid])
	var adj: Dictionary = {}
	for e in enemies:
		if _dist(pos, e["pos"]) == 1 and (adj.is_empty() or int(e["qi"]) < int(adj["qi"])):
			adj = e
	if not adj.is_empty() and not low:
		var art := _art_cmd(adj["pos"])
		if not art.is_empty():
			return art
		return { "cmd": "ATTACK", "target": [adj["pos"].x, adj["pos"].y] }
	var targets: Array = []
	if low and not _escape.is_empty():
		targets = _escape
	else:
		for e in enemies:
			targets.append(e["pos"])
	if targets.is_empty():
		return { "cmd": "DEFEND" }
	var best: Vector2i = pos
	var best_d := 999
	for t in targets:
		best_d = mini(best_d, _dist(pos, t))
	var found := false
	var cand_d := 999
	var cand := pos
	for c in _reachable(pos, _move_range):
		var d := 999
		for t in targets:
			d = mini(d, _dist(c, t))
		if d < cand_d or (d == cand_d and (c.x < cand.x or (c.x == cand.x and c.y < cand.y))):
			cand_d = d
			cand = c
			found = true
	if found and cand_d < best_d:
		best = cand
	if best != pos:
		return { "cmd": "MOVE", "target": [best.x, best.y] }
	if not adj.is_empty():
		return { "cmd": "ATTACK", "target": [adj["pos"].x, adj["pos"].y] }
	return { "cmd": "DEFEND" }

## 打到 battle_close；回傳 s2c_battle_close 的結果
func _fight() -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while not _closed:
		if _done:
			return {}
		if Time.get_ticks_msec() - t0 > BATTLE_TIMEOUT_MS:
			_fail("battle %d did not end" % _bid)
			return {}
		if _await_me:
			_await_me = false
			var cmd := _decide()
			cmd["battle_id"] = _bid
			var r := await _send("battle_cmd", cmd, false)
			if r["ok"] and cmd["cmd"] == "ART":
				art_used = true
			if not r["ok"] and not (r["reason"] in ["battle_over", "battle_not_found", "not_ready"]):
				await _send("battle_cmd", { "battle_id": _bid, "cmd": "DEFEND" }, false)
			continue
		await get_tree().process_frame
	return _close_result

## 若剛剛的 intent 開了戰鬥就打完它
func _handle_battle() -> Dictionary:
	if _in_battle or (not ClientState.battle_state.is_empty() and not _closed):
		return await _fight()
	return {}

# ---------- 生活與移動 ----------
## 原地等精氣神回復（不移動就不會遇敵）
func _rest_in_place(ratio := 0.9) -> bool:
	var t0 := Time.get_ticks_msec()
	while _vital("qi") < int(_vital("qi_max") * ratio) or _vital("jing") < int(_vital("jing_max") * 0.5):
		if _done or Time.get_ticks_msec() - t0 > 60000:
			return false
		await get_tree().create_timer(0.1, true, false, true).timeout
	return true

## 7：氣 < 50% 時回客棧休息（錢不夠就原地等自然回復）
func _ensure_healthy() -> bool:
	if _vital("qi") >= int(_vital("qi_max") * 0.5) and _vital("jing") >= 10:
		return true
	if _money() >= INN_RESERVE:
		var inn := _nearest_inn()
		if inn[0] != "":
			if not await _goto(inn[0], false):
				return false
			var rest := await _send("inn_rest", { "npc": inn[1] })
			if rest["ok"]:
				await _eat_and_sell(inn[1])
				return true
	return await _rest_in_place()

## 沿步行出口找最近的客棧／茶棚／綠洲（有 INN 服務的 NPC）：[room, npc]
func _nearest_inn() -> Array:
	var inns := {}
	var npcs: Dictionary = GameData.tables.get("npcs", {})
	for nid in npcs:
		if "INN" in npcs[nid].get("services", []):
			inns[str(npcs[nid].get("room", ""))] = nid
	var g := _graph()
	var start := _room()
	var seen := { start: true }
	var q: Array = [start]
	while not q.is_empty():
		var cur: String = q.pop_front()
		if inns.has(cur):
			return [cur, inns[cur]]
		for e in g.get(cur, []):
			var nxt: String = e[0]
			if not seen.has(nxt) and (not _room_requires(nxt)):
				seen[nxt] = true
				q.append(nxt)
	return ["", ""]

## 在客棧：賣掉材料、肚子餓就買饅頭和清水
func _eat_and_sell(npc: String) -> void:
	for mat in ["r_rabbitskin", "r_wolfskin", "r_pork"]:
		var uid := _first_uid(mat)
		while uid != "" and not _done:
			var r := await _send("sell", { "npc": npc, "item_uid": uid, "n": maxi(1, _count_uid(uid)) })
			if not r["ok"]:
				break
			uid = _first_uid(mat)
	if int(_vital("food")) < 50 and _money() > 40:
		var b1 := await _send("buy", { "npc": npc, "item": "c_mantou", "n": 2 })
		if b1["ok"]:
			for i in 2:
				var u := _first_uid("c_mantou")
				if u != "":
					await _send("use_item", { "item_uid": u })
	if int(_vital("water")) < 50 and _money() > 40:
		var b2 := await _send("buy", { "npc": npc, "item": "c_water", "n": 2 })
		if b2["ok"]:
			for i in 2:
				var u2 := _first_uid("c_water")
				if u2 != "":
					await _send("use_item", { "item_uid": u2 })

func _count_uid(uid: String) -> int:
	for it in _sheet().get("inventory", []):
		if str(it.get("uid", "")) == uid:
			return int(it.get("n", 1))
	return 0

## 路線圖：房間出口（步行）；伺服器開了馬車選項（world_info.stagecoach_enabled）才加驛站路線
func _graph() -> Dictionary:
	var g := {}   # room -> [[to, "move"/"travel", dir_or_npc, dest, weight]]
	var maps: Dictionary = GameData.tables.get("maps", {})
	for rid in maps:
		for room in maps[rid].get("rooms", []):
			var edges: Array = []
			for ex in room.get("exits", []):
				edges.append([str(ex.get("to", "")), "move", str(ex.get("dir", "")), "", 1])
			g[str(room.get("id", ""))] = edges
	if not bool(ClientState.world_info.get("stagecoach_enabled", false)):
		return g
	var npcs: Dictionary = GameData.tables.get("npcs", {})
	for nid in npcs:
		var row: Dictionary = npcs[nid]
		if not ("TRAVEL" in row.get("services", [])):
			continue
		var from := str(row.get("room", ""))
		for rt in row.get("travel", []):
			if g.has(from):
				g[from].append([str(rt.get("to_room", "")), "travel", nid, str(rt.get("to_room", "")), 8])
	return g

func _room_requires(room_id: String) -> bool:
	for rid in GameData.tables.get("maps", {}):
		for room in GameData.tables["maps"][rid].get("rooms", []):
			if str(room.get("id", "")) == room_id:
				return not (room.get("requires", []) as Array).is_empty()
	return false

func _path(from: String, to: String) -> Array:
	var g := _graph()
	var dist := { from: 0 }
	var prev := {}
	var open: Array = [from]
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if int(dist[open[i]]) < int(dist[open[best_i]]):
				best_i = i
		var cur: String = open.pop_at(best_i)
		if cur == to:
			break
		for e in g.get(cur, []):
			var nxt: String = e[0]
			if nxt != to and _room_requires(nxt):
				continue
			var nd := int(dist[cur]) + int(e[4])
			if not dist.has(nxt) or nd < int(dist[nxt]):
				dist[nxt] = nd
				prev[nxt] = [cur, e]
				if not (nxt in open):
					open.append(nxt)
	if not prev.has(to) and from != to:
		return []
	var out: Array = []
	var c := to
	while c != from:
		out.push_front(prev[c][1])
		c = prev[c][0]
	return out

## 走到 room（途中遇敵就打；死亡或位置不對就重新規劃）。heal：每步前檢查氣
## abort：每一步前呼叫，回傳 true 就停下來回傳 false（_aborted = true，不算失敗）
func _goto(room: String, heal := true, abort := Callable()) -> bool:
	_aborted = false
	for attempt in GOTO_ATTEMPTS:
		if _done:
			return false
		if _room() == room:
			return true
		if abort.is_valid() and abort.call():
			_aborted = true
			return false
		var path := _path(_room(), room)
		if path.is_empty():
			_fail("no path %s -> %s" % [_room(), room])
			return false
		var cur := _room()
		for e in path:
			if _done:
				return false
			if heal and e[1] == "move" and not await _ensure_healthy():
				_fail("could not recover before moving")
				return false
			if _room() != cur:
				break   # 回客棧休息或死亡重生：重新規劃
			if abort.is_valid() and abort.call():
				_aborted = true
				return false
			if e[1] == "move":
				var r := await _send("move", { "dir": e[2] })
				if not r["ok"]:
					_fail("move %s from %s -> %s" % [e[2], cur, r["reason"]])
					return false
				# 踩地雷：battle_opened／房間更新可能比 intent_result 晚到，先等其中之一（否則會漏打一場、拿舊房間規劃下一步）
				var dest: String = e[0]
				await _wait_until(func(): return _in_battle or _room() == dest, 1000)
			else:
				var r2 := await _send("travel", { "npc": e[2], "dest": e[3] })
				if not r2["ok"]:
					_fail("travel %s -> %s: %s" % [e[2], e[3], r2["reason"]])
					return false
			await _handle_battle()
			if not (_room() in _visited) or _visited.back() != _room():
				_visited.append(_room())
			if _room() != e[0]:
				break
			cur = e[0]
		if _room() == room:
			return true
	_fail("could not reach %s" % room)
	return false

# ---------- 劇本 ----------
func _run() -> void:
	await _frames(2)
	if not await _wait_until(func(): return ClientState.in_world, 30000):
		_fail("never entered the world")
		return
	# 依序執行；任一步回傳 false 就停（_check／_fail 已印出原因）
	if not await _s1():
		_fail("step 1")
		return
	if not await _s2():
		_fail("step 2")
		return
	if not await _s3():
		_fail("step 3")
		return
	if not await _s4():
		_fail("step 4")
		return
	if not await _s5():
		_fail("step 5")
		return
	if not await _s6():
		_fail("step 6")
		return
	if not await _s7():
		_fail("step 7")
		return
	if not await _s8():
		_fail("step 8")
		return
	if not await _s9():
		_fail("step 9")
		return
	if not await _s10():
		_fail("step 10")
		return
	if not await _s11():
		_fail("step 11")
		return
	if not await _s12():
		_fail("step 12")
		return
	if not await _s13():
		_fail("step 13")
		return
	if not await _s14():
		_fail("step 14")
		return
	if not await _s15():
		_fail("step 15")
		return
	if not await _s16():
		_fail("step 16")
		return
	if not await _s17():
		_fail("step 17")
		return
	if not await _s18():
		_fail("step 18")
		return
	if not await _s19():
		_fail("step 19")
		return
	if not await _s20():
		_fail("step 20")
		return
	if not await _s21():
		_fail("step 21")
		return
	if not await _s22():
		_fail("step 22")
		return
	if not await _s23():
		_fail("step 23")
		return
	if not await _s24():
		_fail("step 24")
		return
	_step(25, "done")
	_ok_finish()

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond

func _s1() -> bool:
	_step(1, "char_list + delete old characters")
	if not await _must("char_list"):
		return false
	for c in ClientState.char_list.duplicate():
		if not await _must("char_delete", { "char_id": str(c["char_id"]), "confirm_name": str(c["name"]) }):
			return false
	await _must("char_list")
	return _check(ClientState.char_list.is_empty(), "char list not empty: %s" % str(ClientState.char_list))

## 可無限重擲（GDD 2.1）：重擲到臂力 ≥ 22、根骨 ≥ 19，讓新手打得動野兔（每一次擲骰都檢查範圍）
func _s2() -> bool:
	_step(2, "char_roll")
	for i in 300:
		var before := _event_count("char_rolled")
		if not await _must("char_roll"):
			return false
		if not await _wait_until(func(): return _event_count("char_rolled") > before, 5000):
			return _check(false, "no char_rolled event")
		var p: Dictionary = _last_event("char_rolled").get("p", {})
		for a in ["str", "guts", "wit", "luck", "cal", "agi", "con"]:
			var v := int(p.get(a, -1))
			if not _check(v >= 13 and v <= 25, "rolled %s=%d" % [a, v]):
				return false
		if int(p.get("str", 0)) >= 22 and int(p.get("con", 0)) >= 19:
			print("[M1Bot] rolled %s after %d tries" % [str(p), i + 1])
			return true
	return true

func _s3() -> bool:
	_step(3, "char_create")
	if not await _must("char_create", { "name": CHAR_NAME, "gender": "M", "birth_month": 3, "birth_city": "xixia",
			"alloc": { "wit": 5 } }):
		return false
	if not await _wait_until(func(): return str(_sheet().get("char_id", "")) != "", 5000):
		return _check(false, "no sheet")
	var eq: Dictionary = _sheet().get("equipped", {})
	var weapon_ok := false
	var armor_ok := false
	for it in _sheet().get("inventory", []):
		if str(it.get("uid", "")) == str(eq.get("WEAPON", "-")) and it.get("id", "") == "w_mudao":
			weapon_ok = true
		if str(it.get("uid", "")) == str(eq.get("ARMOR", "-")) and it.get("id", "") == "a_bupao":
			armor_ok = true
	return _check(_room() == "xx_square", "room %s" % _room()) \
		and _check(int(_sheet().get("learn_points", 0)) == 100, "learn_points") \
		and _check(_money() == 100, "money %d" % _money()) \
		and _check(_count("c_jingyao") == 5, "c_jingyao ×%d" % _count("c_jingyao")) \
		and _check(weapon_ok and armor_ok, "木刀/布衣 equipped") \
		and _check(ClientState.char_list.size() == 1, "char_list size %d" % ClientState.char_list.size())

## M3B_PLAN §11.3：1.0A-only 世界京城出生被拒；世界開了 1.0B（新世界預設）時京城出生**成功**，
## 斷言在 jc_square 後選回原角色、刪掉京城角色，再照原劇本
func _s4() -> bool:
	var eras: Variant = ClientState.world_info.get("enabled_eras", ["1.0A"])
	if not (eras is Array and "1.0B" in eras):
		_step(4, "jingcheng birth rejected")
		var r := await _send("char_create", { "name": "京城俠客", "gender": "M", "birth_month": 3,
			"birth_city": "jingcheng", "alloc": { "wit": 5 } })
		return _check(not r["ok"] and r["reason"] == "bad_value:birth_city", "got %s" % str(r))
	_step(4, "jingcheng birth allowed (1.0B)")
	var main_id := str(_sheet().get("char_id", ""))
	if not await _must("char_roll"):
		return false
	if not await _must("char_create", { "name": "京城俠客", "gender": "M", "birth_month": 3, "birth_city": "jingcheng",
			"alloc": { "wit": 5 } }):
		return false
	if not await _wait_until(func(): return str(_sheet().get("char_id", "")) != main_id and _room() == "jc_square", 5000):
		return _check(false, "京城出生 room %s" % _room())
	var jc_id := str(_sheet().get("char_id", ""))
	if not await _must("char_select", { "char_id": main_id }):
		return false
	if not await _wait_until(func(): return str(_sheet().get("char_id", "")) == main_id and _room() == "xx_square", 5000):
		return _check(false, "reselect main char: room %s" % _room())
	if not await _must("char_delete", { "char_id": jc_id, "confirm_name": "京城俠客" }):
		return false
	await _must("char_list")
	return _check(ClientState.char_list.size() == 1, "char_list after delete %s" % str(ClientState.char_list))

func _s5() -> bool:
	_step(5, "q_rabbit")
	if not await _must("talk", { "npc": "n_wujieshan" }):
		return false
	if not await _must("quest_accept", { "npc": "n_wujieshan", "quest": "q_rabbit" }):
		return false
	return _check("q_rabbit" in _quest_ids(), "quests %s" % str(_quest_ids()))

func _s6() -> bool:
	_step(6, "respawn at xx_gate_e")
	if not await _must("move", { "dir": "E" }):
		return false
	if not await _must("talk", { "npc": "n_xx_cha" }):
		return false
	if not await _must("set_respawn", { "npc": "n_xx_cha" }):
		return false
	return _check(str(_sheet().get("respawn", {}).get("room", "")) == "xx_gate_e", "respawn %s" % str(_sheet().get("respawn")))

func _s7() -> bool:
	_step(7, "train in xixia wild")
	var moves := 0
	while not (_xp() >= 250 and _count("r_bigrabbitskin") >= 1):
		if _done:
			return false
		moves += 1
		if moves > MAX_TRAIN_MOVES:
			return _check(false, "training did not finish: xp=%d skin=%d" % [_xp(), _count("r_bigrabbitskin")])
		if not await _ensure_healthy():
			return _check(false, "could not heal")
		# 進荒草坡（有大野兔、野狼）前先在官道原地調息到八成以上（站著不動不會遇敵）
		if _room() == "xw_road" and _vital("qi") < int(_vital("qi_max") * 0.8):
			if not await _rest_in_place(0.85):
				return _check(false, "could not rest")
		var target := "xw_grass" if _room() != "xw_grass" else "xw_road"
		if not await _goto(target):
			return false
		if moves % 25 == 0:
			print("[M1Bot] training: xp=%d wins=%d deaths=%d skins=%d money=%d" % [_xp(), wins, deaths,
				_count("r_bigrabbitskin"), _money()])
	return _check(wins >= 1, "no victory") \
		and _check(xp_reward_seen, "no battle_reward with combat_xp > 0") \
		and _check(int(kills_by_name.get(_monster_name("m_rabbit"), 0)) > 0, "no rabbit kill: %s" % str(kills_by_name)) \
		and _check(int(kills_by_name.get(_monster_name("m_bigrabbit"), 0)) > 0, "no big rabbit kill: %s" % str(kills_by_name))

func _monster_name(id: String) -> String:
	return str(GameData.tables.get("monsters", {}).get(id, {}).get("name", id))

# Protocol v5: quests_done rows are dictionaries {id, name, chapter, outcome_label, n}.
func _quest_done(qid: String) -> bool:
	for d in _sheet().get("quests_done", []):
		if (d is Dictionary and str(d.get("id", "")) == qid) or (d is String and d == qid):
			return true
	return false

func _s8() -> bool:
	_step(8, "turn in q_rabbit")
	if not await _goto("xx_square"):
		return false
	var money := _money()
	var lp := int(_sheet().get("learn_points", 0))
	if not await _must("quest_turn_in", { "npc": "n_wujieshan", "quest": "q_rabbit" }):
		return false
	return _check(_money() == money + 100, "money %d -> %d" % [money, _money()]) \
		and _check(int(_sheet().get("learn_points", 0)) == lp + 25, "learn points") \
		and _check(_quest_done("q_rabbit"), "quests_done")

func _s9() -> bool:
	_step(9, "fishing")
	if not await _goto("xw_creek"):
		return false
	if not await _must("learn", { "npc": "n_xw_fisher", "skill": "life_fishing" }):
		return false
	var done := 0
	var tries := 0
	while done < 3 and tries < 60:
		tries += 1
		var r := await _send("work", { "skill": "life_fishing" })
		if r["ok"]:
			done += 1
		elif r["reason"] == "busy" or r["reason"] == "not_enough_jing":
			await get_tree().create_timer(0.2, true, false, true).timeout
		else:
			return _check(false, "work life_fishing: %s" % r["reason"])
	return _check(done == 3, "worked %d times" % done) \
		and _check(_count("t_yugan") >= 1, "no 魚竿") \
		and _check(_skill_prof("life_fishing") > 0, "fishing prof")

## 10：西夏驛站接信 → 馬車被拒（stagecoach_disabled）→ 走西路到大理驛站交信
func _s10() -> bool:
	return await _deliver_letter(10, "xx_station", "n_xx_station", "q_letter", "dl_station", "n_dl_station", "de_oasis")

## 13：大理驛站接信，走回西夏驛站交信
func _s13() -> bool:
	return await _deliver_letter(13, "dl_station", "n_dl_station", "q_letter_dl", "xx_station", "n_xx_station", "de_oasis")

func _deliver_letter(n: int, giver_room: String, giver: String, quest: String, dest_room: String, dest_npc: String,
		via: String) -> bool:
	_step(n, "%s: walk the letter %s -> %s" % [quest, giver_room, dest_room])
	for attempt in 4:
		if not await _goto(giver_room):
			return false
		if not (quest in _quest_ids()):
			if not await _must("talk", { "npc": giver }):
				return false
			if not await _must("quest_accept", { "npc": giver, "quest": quest }):
				return false
		if not _check(_count("i_letter") >= 1, "no letter after accepting %s" % quest):
			return false
		var tr := await _send("travel", { "npc": giver, "dest": dest_room })
		if not _check(not tr["ok"] and tr["reason"] == "stagecoach_disabled", "travel should be refused: %s" % str(tr)):
			return false
		_visited = [_room()]
		var arrived := await _goto(dest_room, true, func(): return _count("i_letter") < 1)
		if _done:
			return false
		if not arrived:
			# STRICT_2001：死在路上，信跟著背包進了屍體 → 放棄任務、回去重接（WORLD_2001 §5.1、§9.3）
			print("[M1Bot] lost the letter on the road (attempt %d, rule %s): abandon and re-accept" % [attempt, _death_rule()])
			if not await _must("quest_abandon", { "quest": quest }):
				return false
			continue
		var fame := int(_sheet().get("fame", 0))
		var rewards_before := _event_count("reward")
		if not await _must("quest_turn_in", { "npc": dest_npc, "quest": quest }):
			return false
		if not await _wait_until(func(): return _event_count("reward") > rewards_before, 5000):
			return _check(false, "no reward event")
		var rw: Dictionary = _last_event("reward").get("p", {})
		print("[M1Bot] letter delivered: %d moves, reward %s" % [_visited.size() - 1, str(rw)])
		return _check(_room() == dest_room, "room %s" % _room()) \
			and _check(via in _visited, "route did not pass %s: %s" % [via, str(_visited)]) \
			and _check(int(rw.get("money", 0)) == LETTER_MONEY, "letter money %s" % str(rw)) \
			and _check(int(rw.get("fame", 0)) == LETTER_FAME, "letter fame %s" % str(rw)) \
			and _check(int(_sheet().get("fame", 0)) == fame + LETTER_FAME, "fame %d -> %d" % [fame, int(_sheet().get("fame", 0))]) \
			and _check(not (quest in _quest_ids()), "%s still active" % quest) \
			and _check(_count("i_letter") == 0, "letter not handed over")
	return _check(false, "%s never delivered" % quest)

## 14：從西夏走東路到少林山門（經恆山茶棚、華山腳下、嵩陽茶棚；1.0B 世界可改走京城南郊，不進京城）
func _s14() -> bool:
	_step(14, "walk the east road to shaolin")
	_visited = [_room()]
	if not await _goto("sl_gate"):
		return false
	# M3b：1.0B 世界多了京城南郊（華山古道 → 南郊岔路 → 嵩山古道 → 嵩山松林），比嵩陽茶棚那條近；1.0A 世界仍必須走嵩陽茶棚
	var eras: Variant = ClientState.world_info.get("enabled_eras", ["1.0A"])
	var has_b: bool = eras is Array and "1.0B" in eras
	var must_pass := ["hf_teahouse", "hy_foot"]
	if not has_b:
		must_pass.append("sy_teahouse")
	for r in must_pass:
		if not _check(r in _visited, "east road did not pass %s: %s" % [r, str(_visited)]):
			return false
	if has_b and not ("sy_teahouse" in _visited or "jcw_crossroad" in _visited):
		return _check(false, "east road passed neither 嵩陽茶棚 nor 南郊岔路: %s" % str(_visited))
	for r in _visited:
		if not _check(not str(r).begins_with("jc_") and (has_b or not str(r).begins_with("jcw_")), "walked through %s" % r):
			return false
	print("[M1Bot] reached shaolin after %d moves" % (_visited.size() - 1))
	return _check(_room() == "sl_gate", "room %s" % _room())

func _s15() -> bool:
	_step(15, "join shaolin")
	if not await _goto("sl_gate"):
		return false
	if not await _must("set_respawn", { "npc": "n_sl_cha" }):
		return false
	if not await _must("join_sect", { "npc": "n_sl_zhike" }):
		return false
	return _check(str(_sheet().get("sect", "")) == "shaolin", "sect") \
		and _check(not _last_event("sect_join").is_empty(), "sect_join event")

func _s16() -> bool:
	_step(16, "sl_changquan gated by foxa")
	if not await _goto("sl_wuchang"):
		return false
	var r := await _send("learn", { "npc": "n_sl_huizhen", "skill": "sl_changquan" })
	return _check(not r["ok"] and r["reason"] == "req_skill_min", "got %s" % str(r))

## 反覆消點直到等級達標；處理精、內力不足
func _learn_until(npc: String, skill: String, level: int, times: int) -> bool:
	var guard := 0
	while _skill_level(skill) < level:
		guard += 1
		if guard > 400 or _done:
			return _check(false, "learn %s stuck at %d" % [skill, _skill_level(skill)])
		var r := await _send("learn", { "npc": npc, "skill": skill, "times": times })
		if r["ok"]:
			continue
		match r["reason"]:
			"not_enough_jing":
				var uid := _first_uid("c_jingyao")
				if uid != "" and _vital("jing") < int(_vital("jing_max") * 0.5):
					await _send("use_item", { "item_uid": uid })
				else:
					await _wait_until(func(): return _vital("jing") >= int(_vital("jing_max") * 0.9), 30000)
			"not_enough_neili":
				var m := await _send("meditate")
				if not m["ok"]:
					if m["reason"] == "not_enough_jing":
						await _wait_until(func(): return _vital("jing") >= int(_vital("jing_max") * 0.9), 30000)
					else:
						await get_tree().create_timer(0.25, true, false, true).timeout
			"not_enough_shen":
				await _wait_until(func(): return _vital("shen") >= int(_vital("shen_max") * 0.9), 30000)
			_:
				return _check(false, "learn %s: %s" % [skill, r["reason"]])
	return true

func _s17() -> bool:
	_step(17, "basic_inner ≥ 2")
	if not await _goto("sl_wuchang"):
		return false
	if not await _learn_until("n_sl_huizhen", "basic_inner", 2, 5):
		return false
	return _check(_skill_level("basic_inner") >= 2, "basic_inner") \
		and _check(_vital("neili_max") >= 10, "neili_max %d" % _vital("neili_max"))

func _s18() -> bool:
	_step(18, "foxa → 10")
	if not await _goto("sl_gate"):
		return false
	var lp := int(_sheet().get("learn_points", 0))
	if not await _learn_until("n_sl_zhike", "foxa", 10, 10):
		return false
	return _check(_skill_level("foxa") == 10, "foxa %d" % _skill_level("foxa")) \
		and _check(int(_sheet().get("learn_points", 0)) < lp, "learn points spent")

func _s19() -> bool:
	_step(19, "learn sl_changquan")
	if not await _goto("sl_wuchang"):
		return false
	if not await _learn_until("n_sl_huizhen", "sl_changquan", 1, 1):
		return false
	return _check(int(_sheet().get("special_arts", 0)) == 1, "special_arts %s" % str(_sheet().get("special_arts")))

func _s20() -> bool:
	_step(20, "shaolin meal")
	if not await _goto("sl_zhaitang"):
		return false
	var before := _shichen()
	var r := await _send("meal", { "npc": "n_sl_zhaiseng" })
	var after := _shichen()
	if r["ok"]:
		return _check(before in MEAL_HOURS or after in MEAL_HOURS, "meal accepted at %s/%s" % [before, after])
	if r["reason"] == "already_ate":
		return _check(before in MEAL_HOURS or after in MEAL_HOURS, "already_ate at %s" % before)
	return _check(r["reason"] == "not_meal_time" and (not (before in MEAL_HOURS) or not (after in MEAL_HOURS)),
		"meal %s at %s/%s" % [r["reason"], before, after])

func _s11() -> bool:
	_step(11, "farming + q_rice")
	if not await _goto("dlw_paddy"):
		return false
	var prof0 := _skill_prof("life_farming")
	if not await _must("learn", { "npc": "n_taoyun", "skill": "life_farming" }):
		return false
	if not await _must("quest_accept", { "npc": "n_taoyun", "quest": "q_rice" }):
		return false
	var tries := 0
	while _count("r_rice") < 6 and tries < 200:
		tries += 1
		var r := await _send("work", { "skill": "life_farming" })
		if not r["ok"]:
			if r["reason"] == "not_enough_jing":
				await _wait_until(func(): return _vital("jing") >= 30, 30000)
			elif r["reason"] != "busy":
				return _check(false, "work life_farming: %s" % r["reason"])
			await get_tree().create_timer(0.1, true, false, true).timeout
	var prof1 := _skill_prof("life_farming")
	if not await _must("quest_turn_in", { "npc": "n_taoyun", "quest": "q_rice" }):
		return false
	return _check(_quest_done("q_rice"), "q_rice done") \
		and _check(prof1 > prof0, "farming prof")

func _s12() -> bool:
	_step(12, "cooking")
	if not await _goto("dl_inn"):
		return false
	if not await _must("learn", { "npc": "n_dl_cook", "skill": "life_cooking" }):
		return false
	var tries := 0
	while _count("c_baifan") < 1 and tries < 100:
		tries += 1
		var r := await _send("work", { "skill": "life_cooking", "recipe": "rc_baifan" })
		if not r["ok"]:
			if r["reason"] == "no_ingredients":
				return _check(false, "no rice left")
			if r["reason"] == "not_enough_jing":
				await _wait_until(func(): return _vital("jing") >= 30, 30000)
			await get_tree().create_timer(0.1, true, false, true).timeout
	if not _check(_count("c_baifan") >= 1, "no 白飯"):
		return false
	var food := _vital("food")
	if not await _must("use_item", { "item_uid": _first_uid("c_baifan") }):
		return false
	return _check(_vital("food") > food or _vital("food") >= 100, "food %d -> %d" % [food, _vital("food")])

## 21：鬼王在西夏東北的血刀洞迷宮（WORLD_2001 D4）：從少林走回去，經血刀洞口進洞
func _s21() -> bool:
	_step(21, "walk to the 血刀洞迷宮 (guiwang)")
	_visited = [_room()]
	if not await _goto("gw_entrance"):
		return false
	print("[M1Bot] reached the cave after %d moves" % (_visited.size() - 1))
	return _check("xe_xuedao" in _visited, "did not enter via xe_xuedao: %s" % str(_visited)) \
		and _check(str(_sheet().get("location", {}).get("region", "")) == "guiwang", "region")

func _s22() -> bool:
	_step(22, "fight in guiwang cave")
	for attempt in 4:
		if not await _goto("gw_entrance"):
			return false
		var fought := false
		var guard := 0
		while not fought and guard < 200:
			guard += 1
			if not await _ensure_healthy():
				return false
			# _ensure_healthy 可能走去最近的客棧／茶棚（例如恆山茶棚只有東西出口）而不回來
			if _room() != "gw_entrance" and _room() != "gw_hall":
				if not await _goto("gw_entrance"):
					return false
			var dir := "N" if _room() == "gw_entrance" else "S"
			var xp_before := _xp()
			var arts_before := _art_levels()
			var r := await _send("move", { "dir": dir })
			if not r["ok"]:
				return _check(false, "move %s: %s" % [dir, r["reason"]])
			var dest := "gw_hall" if dir == "N" else "gw_entrance"
			await _wait_until(func(): return _in_battle or _room() == dest, 1000)
			if _in_battle or not ClientState.battle_state.is_empty():
				var res := await _handle_battle()
				fought = true
				if bool(res.get("you_died", false)):
					# STANDARD 只降「最高」特殊武功一級，不一定是長拳；STRICT_2001 每門各降一級
					var arts_after := _art_levels()
					var lost := 0
					for k in arts_before:
						lost += max(0, int(arts_before[k]) - int(arts_after.get(k, 0)))
					var rule := _death_rule()
					var expect_loss := 0
					if rule == "STRICT_2001":
						expect_loss = arts_before.size()
					elif rule != "CASUAL" and xp_before > 500:
						expect_loss = 1
					if not _check(_room() == "sl_gate", "respawn at %s" % _room()):
						return false
					if not _check(lost == expect_loss, "arts lost %d, expected %d (xp %d, %s)" % [lost, expect_loss, xp_before, rule]):
						return false
		if art_used:
			return true
		print("[M1Bot] no ART used yet (attempt %d), fighting again" % attempt)
	return _check(art_used, "never used ART in a battle")

## 主機在 welcome 給的已展開規則（ClientState.world_info.rule_profile）
func _death_rule() -> String:
	return str(ClientState.world_info.get("rule_profile", {}).get("death_rule", "STANDARD"))

func _skill_levels() -> Dictionary:
	var out := {}
	for sk in _sheet().get("skills", []):
		if str(sk.get("kind", "")) != "LIFE" and int(sk.get("level", 0)) >= 1:
			out[str(sk.get("id", ""))] = int(sk.get("level", 0))
	return out

func _art_levels() -> Dictionary:
	var out := {}
	for sk in _sheet().get("skills", []):
		if str(sk.get("kind", "")) == "ART" and int(sk.get("level", 0)) >= 1:
			out[str(sk.get("id", ""))] = int(sk.get("level", 0))
	return out

func _item_total() -> int:
	var n := 0
	for it in _sheet().get("inventory", []):
		n += int(it.get("n", 1))
	return n

func _equipped_total() -> int:
	var n := 0
	for it in _sheet().get("inventory", []):
		if str(it.get("equipped_slot", "")) != "":
			n += int(it.get("n", 1))
	return n

## 23：在鬼王洞只 DEFEND 撐到死亡，依目前世界的 death_rule 斷言懲罰（M1_PLAN 6.2）
func _s23() -> bool:
	var rule := _death_rule()
	_step(23, "death rule %s" % rule)
	var expect: Variant = CliArgs.current().get("bot-expect-rule")
	if expect is String and not _check(expect == rule, "world death_rule %s, expected %s" % [rule, expect]):
		return false
	for attempt in 6:
		if not await _goto("gw_entrance"):
			return false
		if not await _ensure_healthy():
			return false
		if not await _goto("gw_entrance"):
			return false
		var skills_before := _skill_levels()
		var money_before := _money()
		var items_before := _item_total()
		var equipped_before := _equipped_total()
		var xp_before := _xp()
		var ev_before := { "death_strict": _event_count("death_strict"), "death_standard": _event_count("death_standard"),
			"death_standard_safe": _event_count("death_standard_safe"), "death_casual": _event_count("death_casual") }
		var guard := 0
		var res := {}
		while res.is_empty() and guard < 200:
			guard += 1
			var r := await _send("move", { "dir": "N" if _room() == "gw_entrance" else "S" })
			if not r["ok"]:
				return _check(false, "move: %s" % r["reason"])
			if _in_battle or not ClientState.battle_state.is_empty():
				_suicide = true
				res = await _handle_battle()
				_suicide = false
		if not bool(res.get("you_died", false)):
			print("[M1Bot] survived DEFEND-only battle (attempt %d), retrying" % attempt)
			continue
		var t_closed := WorldServer.world_time()
		await _frames(4)
		var after := _skill_levels()
		var money_after := _money()
		print("[M1Bot] death under %s: skills %s -> %s, money %d -> %d, items %d -> %d" % [rule, str(skills_before),
			str(after), money_before, money_after, items_before, _item_total()])
		if not _check(_room() == "sl_gate", "respawn at %s" % _room()):
			return false
		# 重生時內力歸 0；讀表前世界時間可能已過了幾個 10 秒回復週期（--time-scale 高、CPU 忙時），
		# 所以容許 ceil(內力上限×1%) × 經過的回復次數
		var regen_ticks := floori((WorldServer.world_time() - t_closed) / 10.0) + 2   # +2：結算到 t_closed 之間也可能跨一次
		var neili_max := int((_sheet().get("vitals", {}) as Dictionary).get("neili_max", 0))
		var neili_bound := ceili(neili_max * 0.01) * regen_ticks
		if not _check(_vital("neili") <= neili_bound, "neili after respawn %d (bound %d)" % [_vital("neili"), neili_bound]):
			return false
		match rule:
			"STRICT_2001":
				for sid in skills_before:
					if not _check(int(after.get(sid, 0)) == int(skills_before[sid]) - 1, "strict: %s %d -> %d" % [sid, skills_before[sid], int(after.get(sid, 0))]):
						return false
				return _check(_item_total() == 0, "strict: inventory not empty") 					and _check(money_after == money_before, "strict: money changed") 					and _check(_event_count("death_strict") > int(ev_before["death_strict"]), "no death_strict")
			"CASUAL":
				return _check(after == skills_before, "casual: skills changed %s" % str(after)) 					and _check(_item_total() == items_before, "casual: items changed") 					and _check(money_after == money_before - int(floor(money_before * 0.1)), "casual: money %d -> %d" % [money_before, money_after]) 					and _check(_event_count("death_casual") > int(ev_before["death_casual"]), "no death_casual")
			_:
				if xp_before <= 500:
					return _check(after == skills_before and _item_total() == items_before, "standard newbie lost something") 						and _check(_event_count("death_standard_safe") > int(ev_before["death_standard_safe"]), "no death_standard_safe")
				var dropped_levels := 0
				for sid in skills_before:
					dropped_levels += int(skills_before[sid]) - int(after.get(sid, 0))
				return _check(dropped_levels == 1, "standard: lost %d levels" % dropped_levels) 					and _check(_item_total() == items_before - equipped_before, "standard: items %d -> %d (equipped %d)" % [items_before, _item_total(), equipped_before]) 					and _check(money_after == money_before, "standard: money changed") 					and _check(_event_count("death_standard") > int(ev_before["death_standard"]), "no death_standard")
	return _check(false, "never died while defending")

func _s24() -> bool:
	_step(24, "reselect and check save file")
	var cid := str(_sheet().get("char_id", ""))
	if not await _must("char_select", { "char_id": cid }):
		return false
	if not NetworkManager.is_host():
		# 連線客戶端：存檔在主機那邊，只檢查重新選角成功
		return _check(str(_sheet().get("char_id", "")) == cid, "reselected")
	var path := ProjectSettings.globalize_path(SaveManager.character_path(WorldServer.world_id, ClientState.identity, cid))
	if not _check(FileAccess.file_exists(path), "missing save " + path):
		return false
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _check(d is Dictionary and int(d.get("schema_version", 0)) == 1, "bad save file") \
		and _check(str(_sheet().get("char_id", "")) == cid, "reselected")
