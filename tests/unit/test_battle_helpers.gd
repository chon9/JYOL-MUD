extends "res://tests/test_case.gd"
## WP-BATTLE 測試共用工具（本檔沒有 test_ 方法；其他 test_battle_*.gd 繼承它）。
## 只依賴 core/battle 與 tests/fixtures/battle_tables.json（G10）。

const TABLES_PATH := "res://tests/fixtures/battle_tables.json"
static var _tables_cache: Dictionary = {}

static func tables() -> Dictionary:
	if _tables_cache.is_empty():
		var f := FileAccess.open(TABLES_PATH, FileAccess.READ)
		_tables_cache = JSON.parse_string(f.get_as_text())
	return _tables_cache

static func weapon(uid: String, item_id: String, wtype: String, atk: int, name: String) -> Dictionary:
	return { "uid": uid, "item_id": item_id, "weapon_type": wtype, "atk": atk, "name": name }

static func bare() -> Dictionary:
	return weapon("", "", "FIST", 0, "")

static func player_spec(over: Dictionary = {}) -> Dictionary:
	var s := {
		"kind": "PLAYER", "ref": "ch_test0001", "name": "測試俠客", "side": 0, "peer": 1, "ai": "",
		"attrs": { "str": 20, "guts": 19, "wit": 21, "luck": 19, "cal": 19, "agi": 20, "con": 20 },
		"qi": 180, "qi_max": 180, "neili": 0, "neili_max": 0, "jing": 92, "jing_max": 92, "shen": 88, "shen_max": 88,
		"skills": {}, "arts": [],
		"weapon": weapon("it_0001", "w_mudao", "BLADE", 4, "木刀"),
		"weapon_options": [ weapon("it_0001", "w_mudao", "BLADE", 4, "木刀"), weapon("it_0002", "w_mujian", "SWORD", 4, "木劍") ],
		"armor_power": 2, "effective_inner": 0, "lightness": 0, "sect_skill": {}, "killing_intent": 0,
		"carry_ratio": 0.12, "monster_row": "", "combat_xp": 0,
	}
	for k in over:
		if k == "attrs":
			for a in over.attrs:
				s.attrs[a] = over.attrs[a]
		else:
			s[k] = over[k]
	return s

static func monster(id: String, over: Dictionary = {}) -> Dictionary:
	var s := Encounter.monster_spec(id, tables())
	for k in over:
		if k == "attrs":
			for a in over.attrs:
				s.attrs[a] = over.attrs[a]
		else:
			s[k] = over[k]
	return s

static func default_opts(over: Dictionary = {}) -> Dictionary:
	var o := { "wait_mode": true, "wait_mode_timeout_s": 20, "wait_mode_timeout_min_s": 8,
		"wait_mode_round_budget_s": 45, "escape_tiles": 2 }
	o.merge(over, true)
	return o

static func make_battle(specs: Array, seed_v: int = 1234, opts: Dictionary = {}) -> Battle:
	var b := Battle.new(7, seed_v, default_opts(opts))
	for s in specs:
		b.add_unit(s)
	b.start(tables())
	return b

## 一直 step 直到 peer 的單位在等待清單裡（等待模式：AWAIT_COMMAND；否則 READY）。回傳期間的事件。
static func run_until_ready(b: Battle, peer: int, max_ticks: int = 2000) -> Array:
	var ev: Array = []
	for i in max_ticks:
		var uid := b.uid_for_peer(peer)
		var u := b.unit(uid)
		if b.is_over():
			break
		if u != null and u.state == BattleUnit.READY and b.pending_uids().has(uid) and u.queued_cmd.is_empty():
			if not b.wait_mode() or b.state == Battle.State.AWAIT_COMMAND:
				break
		ev.append_array(b.step(Battle.TICK, tables()))
	return ev

static func run_until_over(b: Battle, max_ticks: int = Battle.MAX_TICKS + 10) -> Array:
	var ev: Array = []
	for i in max_ticks:
		if b.is_over():
			break
		ev.append_array(b.step(Battle.TICK, tables()))
	return ev

static func keys_of(events: Array) -> Array:
	return events.map(func(e): return e.key)

static func find(events: Array, key: String) -> Array:
	return events.filter(func(e): return e.key == key)

## 用 BattleAI 替玩家決定指令（測試用自動玩家）
static func auto_cmd(b: Battle, peer: int) -> Dictionary:
	var u := b.unit(b.uid_for_peer(peer))
	return BattleAI.choose(b, u, tables(), RandomNumberGenerator.new())

## 自動打到結束：每當 peers 中的玩家在等待清單裡就送 auto_cmd。
## 回傳 { events, commands:[{tick, peer, cmd}] }（commands 可直接用於回放）
static func play(b: Battle, peers: Array, max_ticks: int = 20000) -> Dictionary:
	var ev: Array = []
	var cmds: Array = []
	for i in max_ticks:
		if b.is_over():
			break
		for peer in peers:
			var uid := b.uid_for_peer(peer)
			var u := b.unit(uid)
			if u != null and u.state == BattleUnit.READY and b.pending_uids().has(uid) and u.queued_cmd.is_empty():
				var c := auto_cmd(b, peer)
				if b.submit(peer, c, tables()) == "":
					cmds.append({ "tick": b.tick_no, "peer": peer, "cmd": c })
		ev.append_array(b.step(Battle.TICK, tables()))
	return { "events": ev, "commands": cmds }

## 依記錄的指令序列回放（指令在 b.tick_no == tick 時送出，再 step）
static func replay(b: Battle, commands: Array, max_ticks: int = 20000) -> Array:
	var ev: Array = []
	var i := 0
	for n in max_ticks:
		if b.is_over():
			break
		while i < commands.size() and int(commands[i].tick) == b.tick_no:
			b.submit(int(commands[i].peer), commands[i].cmd, tables())
			i += 1
		ev.append_array(b.step(Battle.TICK, tables()))
	return ev

static func approx(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps

## 把單位移到指定格（測試用；直接改位置）
static func place(b: Battle, uid: int, x: int, y: int) -> void:
	b.unit(uid).pos = Vector2i(x, y)

## ---------------------------------------------------------------- M3a：不跑 ATB 的直接下令

## 把單位設為 READY（不經過時間棒），方便直接驗證／結算單一指令
static func ready_unit(b: Battle, uid: int) -> BattleUnit:
	var u := b.unit(uid)
	u.state = BattleUnit.READY
	return u

## 驗證並結算一個指令：回傳 { err, events }（err 不是空字串時不結算）
static func do_cmd(b: Battle, uid: int, cmd: Dictionary, t: Dictionary = {}) -> Dictionary:
	var tb := t if not t.is_empty() else tables()
	var u := ready_unit(b, uid)
	var err := BattleRules.validate_cmd(b, u, cmd, tb)
	if err != "":
		u.state = BattleUnit.CHARGING
		return { "err": err, "events": [] }
	return { "err": "", "events": BattleRules.execute(b, u, cmd, tb, b.rng) }

## 隊友（side 0、另一個 peer）
static func ally_spec(peer: int, over: Dictionary = {}) -> Dictionary:
	var s := player_spec(over)
	s["peer"] = peer
	s["ref"] = "ch_test%04d" % peer
	s["name"] = "隊友%d" % peer
	return s
