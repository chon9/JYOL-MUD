class_name Battle
extends RefCounted
## ATB 格子戰鬥狀態機（M1_PLAN 3.4.1；TECH_ARCH 10.2、10.7、13.4）。
## 純邏輯：不碰 Autoload、場景樹或網路。輸入＝指令，輸出＝事件陣列。
## 決定性：同種子 + 同單位規格 + 同指令序列（含送達的 tick）→ 完全相同的事件陣列。

enum State { SETUP, RUNNING, AWAIT_COMMAND, RESOLVING, ENDED }
enum Result { NONE, VICTORY, DEFEAT, ALL_FLED, ABORTED }
const GAUGE_FULL := 100.0
const TICK := 0.1
const W := 12
const H := 8
const MAX_TICKS := 18000            # 30 分鐘遊戲時間仍未分勝負 → ABORTED
const MOVE_GAUGE := 50.0            # MOVE 後時間棒設為 50（4.6）
const RESULT_NAMES := ["NONE", "VICTORY", "DEFEAT", "ALL_FLED", "ABORTED"]

var id: int = 0
var state: State = State.SETUP
var result: Result = Result.NONE
var tick_no: int = 0
var units: Array = []               # Array[BattleUnit]
var grid: BattleGrid
var rng: RandomNumberGenerator
var opts: Dictionary = {}

var _pending: Array = []            # READY 中、等待結算的單位（依結算順序）
var _deadlines: Dictionary = {}     # uid -> 逾時的 tick（等待模式）
var _await_start_tick: int = 0
var _round_wait_ticks: int = 0      # 本輪累計等待（10.7 #3）
var _round_acted: Dictionary = {}   # 本輪已行動的真人 uid
var _gauges_dirty := false
var _events: Array = []

## M3A_PLAN 5.9 波次：第一波是開戰時加入的敵人；之後每一波是怪物規格陣列（side 1）
var wave_specs: Array = []          # 還沒出場的波次：Array[Array[spec]]
var wave_no: int = 1
var wave_total: int = 1

func _init(p_id: int, p_seed: int, p_opts: Dictionary) -> void:
	id = p_id
	rng = RandomNumberGenerator.new()
	rng.seed = p_seed
	opts = p_opts.duplicate(true)
	grid = BattleGrid.new()

func wait_mode() -> bool:
	return bool(opts.get("wait_mode", true))

func add_unit(spec: Dictionary) -> int:
	if state != State.SETUP:
		push_warning("Battle.add_unit after start() ignored")
		return 0
	var u := BattleUnit.new(units.size() + 1, spec)
	units.append(u)
	return u.uid

## 波次（M3A_PLAN 5.9）：開戰前呼叫。specs_by_wave = 第 2 波以後每一波的怪物規格陣列。
func set_waves(specs_by_wave: Array) -> void:
	wave_specs = []
	for w in specs_by_wave:
		if w is Array and not w.is_empty():
			wave_specs.append(w.duplicate(true))
	wave_no = 1
	wave_total = 1 + wave_specs.size()

func start(tables: Dictionary) -> Array:
	_events = []
	if state != State.SETUP:
		return []
	grid.place_units(units, rng)
	grid.place_escape_tiles(int(opts.get("escape_tiles", 2)), units, rng)
	for u in units:
		u.rate = BattleFormulas.atb_gain(u, tables)
		u.gauge = 0.0
		u.state = BattleUnit.CHARGING
	state = State.RUNNING
	_emit_gauges()
	return _flush()

## 主機每 0.1 秒（世界時間）呼叫一次；dt 超過一個 TICK 時依序跑多個 tick。
## 回傳值也包含上次輸出之後 join_unit() 產生、還沒被 drain_events() 取走的事件（M2）。
func step(dt: float, tables: Dictionary) -> Array:
	var n := maxi(1, roundi(dt / TICK))
	for i in n:
		if state == State.ENDED or state == State.SETUP:
			break
		_tick(tables)
	return _flush()

func submit(peer: int, cmd: Dictionary, tables: Dictionary) -> String:
	if state == State.ENDED:
		return "battle_over"
	var u: BattleUnit = _unit_for_peer(peer)
	if u == null or not _pending.has(u) or u.state != BattleUnit.READY or u.is_ai():
		return "not_ready"
	var norm := BattleRules.normalize_cmd(cmd)
	if norm.is_empty():
		return "bad_cmd"
	var err := BattleRules.validate_cmd(self, u, norm, tables)
	if err != "":
		return err
	u.queued_cmd = norm
	u.timeouts = 0
	u.afk = false
	return ""

## ---------------------------------------------------------------- M2：中途加入、PvP

## 中途加入（M2_PLAN 4.6.3）：只在 RUNNING／AWAIT_COMMAND／RESOLVING 可用。
## 放在 spec.side 那一方最外側欄（side 0：x=0，side 1：x=11）依 Y_ORDER 找空格（不放在逃跑格上），
## 滿了往內一欄（最多到己方半場）；沒有空格回 0。gauge 0、CHARGING。
## 事件 battle_join（模板）、battle_unit_join（ui）、battle_gauges 留在事件緩衝：由 drain_events() 或下一次 step() 帶出。
## M2_PLAN 缺漏：契約簽名只有 spec；battle_unit_join 的單位快照需要 tables（招式清單），所以加一個可省略的 tables 參數。
func join_unit(spec: Dictionary, tables: Dictionary = {}) -> int:
	if state != State.RUNNING and state != State.AWAIT_COMMAND and state != State.RESOLVING:
		return 0
	var side := 1 if int(spec.get("side", 0)) == 1 else 0
	var cell := join_cell(side)
	if cell == Vector2i(-1, -1):
		return 0
	var u := BattleUnit.new(units.size() + 1, spec)
	u.side = side
	u.pos = cell
	u.start_pos = cell
	u.gauge = 0.0
	u.rate = BattleFormulas.atb_gain(u, tables)
	u.state = BattleUnit.CHARGING
	units.append(u)
	if grid.units != units:
		grid.units = units
	_events.append(make_event("battle_join", { "uid": u.uid, "name": u.unit_name(), "peer": u.peer }))
	_events.append(make_event("battle_unit_join", { "unit": _unit_snapshot(u, tables) }, true))
	_emit_gauges()
	return u.uid

## 取走事件緩衝（join_unit 之後立刻轉送用）
func drain_events() -> Array:
	return _flush()

## 中途加入的出場格：最外側欄 → 往內，每欄依 Y_ORDER
func join_cell(side: int) -> Vector2i:
	var half := W >> 1
	var cols: Array = range(0, half) if side == 0 else range(W - 1, half - 1, -1)
	for x in cols:
		for y in BattleGrid.Y_ORDER:
			var p := Vector2i(x, y)
			if grid.is_free(p) and not grid.is_escape(p):
				return p
	return Vector2i(-1, -1)

## 戰鬥中的玩家單位數（含已倒下、已逃走的；名額一經占用就不釋出）
func humans() -> int:
	var n := 0
	for u in units:
		if u.is_player():
			n += 1
	return n

## 勝方：0 / 1；未分勝負、全逃、中止 → -1。
## _check_end 的結果是以 side 0 為準（VICTORY＝side 0 勝）；PvP 時 side 1 的玩家由 BattleSystem 依此換算。
func winner_side() -> int:
	match result:
		Result.VICTORY:
			return 0
		Result.DEFEAT:
			return 1 if units.any(func(u): return u.side == 1 and u.is_active()) else -1
	return -1

func uid_for_peer(peer: int) -> int:
	var u: BattleUnit = _unit_for_peer(peer)
	return u.uid if u != null else 0

func is_over() -> bool:
	return state == State.ENDED

## 玩家斷線：他的單位改為自動「防」、不再等他下令，戰鬥照常進行到分出勝負（死亡照樣受罰）。
## 回傳是否找到該玩家的單位。
func detach_peer(peer: int) -> bool:
	var u: BattleUnit = _unit_for_peer(peer)
	if u == null:
		return false
	u.detached = true
	u.afk = true
	if _pending.has(u) and u.queued_cmd.is_empty():
		u.queued_cmd = { "cmd": "DEFEND", "auto": true }
	return true

func abort() -> Array:
	_events = []
	if state == State.ENDED:
		return []
	_pending.clear()
	_end(Result.ABORTED)
	return _flush()

func result_name() -> String:
	return RESULT_NAMES[result]

func unit(uid: int) -> BattleUnit:
	for u in units:
		if u.uid == uid:
			return u
	return null

func unit_at(p: Vector2i) -> BattleUnit:
	return grid.unit_at(p)

func active_humans() -> Array:
	return units.filter(func(u): return u.is_active() and not u.is_ai())

## 等待中、尚未下令的真人
func waiting_humans() -> Array:
	return _pending.filter(func(u): return not u.is_ai() and not u.detached and u.is_active() and u.queued_cmd.is_empty())

func pending_uids() -> Array:
	return _pending.map(func(u): return u.uid)

func round_wait_s() -> float:
	return _round_wait_ticks * TICK

## M3D_PLAN §3.3.3：戰鬥時間（秒）＝ tick 數 × TICK（合體技 3 秒窗、換裝兩秒、比武限時都用這個）
func time_s() -> float:
	return tick_no * TICK

func make_event(key: String, p: Dictionary, ui := false) -> Dictionary:
	var pp := p.duplicate()
	pp["bid"] = id
	var e := { "ch": "BATTLE", "key": key, "p": pp, "bid": id }
	if ui:
		e["ui"] = true
	return e

## ---------------------------------------------------------------- 快照與結果

func snapshot(tables: Dictionary) -> Dictionary:
	var list: Array = []
	for u in units:
		list.append(_unit_snapshot(u, tables))
	var esc: Array = []
	for p in grid.escape:
		esc.append([p.x, p.y])
	return { "bid": id, "w": W, "h": H, "tick": tick_no, "wait_mode": wait_mode(),
		"escape": esc, "units": list, "kind": str(opts.get("kind", "")),
		"wave": { "n": wave_no, "total": wave_total }, "no_flee": bool(opts.get("no_flee", false)),
		"later_battle_cmds": BattleCmds.later_cmds(self),
		# M3D_PLAN §7（WP-COMBAT）：規則 dodge_cmd、比武剩餘秒數（沒有限時 → -1）
		"dodge_cmd": bool(opts.get("dodge_cmd", true)),
		"duel_left_s": maxf(0.0, float(opts.duel_limit_s) - time_s()) if opts.has("duel_limit_s") else -1.0 }

func unit_snapshot(u: BattleUnit, tables: Dictionary) -> Dictionary:
	return _unit_snapshot(u, tables)

func _unit_snapshot(u: BattleUnit, tables: Dictionary) -> Dictionary:
	var d := { "uid": u.uid, "name": u.unit_name(), "short": str(u.spec.get("short", "")), "side": u.side, "kind": u.kind(), "peer": u.peer,
		"pos": [u.pos.x, u.pos.y], "qi": u.qi, "qi_max": u.qi_max(),
		"gauge": u.gauge, "rate": u.rate, "state": u.state,
		"statuses": BattleStatus.snapshot(u, tables),   # M3A_PLAN 5.7：每個單位（含敵方）
		"dodging": u.dodging }   # M3D_PLAN §7：「閃」中（純表現）
	# M3C_PLAN §7.2（WP-FX）純表現：武器類型（玩家＝手上兵器、怪物＝怪物列 weapon_type）與兵器特效（物品列 fx，例 "claw"）
	d["wtype"] = u.weapon_type()
	d["wfx"] = Battle.weapon_fx_of(u, tables)
	# 純表現用欄位（3.9.3 追加，舊客戶端忽略即可）：敵方帶 ref（monster id）供選圖；玩家帶 look
	if not u.is_player():
		d["ref"] = str(u.spec.get("ref", ""))
		return d
	d["look"] = str(u.spec.get("look", ""))
	d["neili"] = u.neili
	d["neili_max"] = u.neili_max()
	d["jing"] = u.jing
	d["jing_max"] = u.jing_max()
	d["move_range"] = BattleFormulas.move_range(u)
	d["weapon"] = { "uid": u.weapon.uid, "name": u.weapon.name, "weapon_type": u.weapon.weapon_type }
	var wo: Array = []
	for w in u.weapon_options():
		wo.append({ "uid": str(w.get("uid", "")), "name": str(w.get("name", "")),
			"weapon_type": str(w.get("weapon_type", "FIST")) })
	d["weapon_options"] = wo
	var arts_out: Array = []
	var arts_t: Dictionary = tables.get("martial_arts", {})
	for a in u.arts():
		var row: Dictionary = arts_t.get(str(a), {})
		if row.is_empty():
			continue
		var lv := u.skill(str(a))
		var moves: Array = []
		for m in row.get("moves", []):
			moves.append({ "id": str(m.get("id", "")), "name": str(m.get("name", "")),
				"unlock_level": int(m.get("unlock_level", 1)), "range": int(m.get("range", 1)),
				"cost_inner": int(m.get("cost_inner", 0)), "cost_jing": int(m.get("cost_jing", 0)),
				"aoe": str(m.get("aoe", "SINGLE")),
				"usable": int(m.get("unlock_level", 1)) <= lv })   # M3a：範圍招式可用
		arts_out.append({ "id": str(a), "name": str(row.get("name", a)), "category": str(row.get("category", "")),
			"level": lv, "moves": moves })
	d["arts"] = arts_out
	_cmd_snapshot(u, d, tables)
	return d

## M3C_PLAN §7.2（WP-FX）：玩家目前兵器物品列的 fx（"claw"…）；怪物、空手 → ""。純表現，不影響任何判定
static func weapon_fx_of(u: BattleUnit, tables: Dictionary) -> String:
	if not u.is_player():
		return ""
	var iid := str(u.weapon.get("item_id", ""))
	if iid == "":
		return ""
	var row: Variant = tables.get("items", {}).get(iid, {})
	return str(row.get("fx", "")) if row is Dictionary else ""

## M3A_PLAN 7.1：玩家自己的單位的新指令欄位（cmd_avail、cmd_arts、hidden_items、battle_items、formation）
func _cmd_snapshot(u: BattleUnit, d: Dictionary, tables: Dictionary) -> void:
	d["shen"] = u.shen
	d["shen_max"] = u.shen_max()
	d["cmd_avail"] = BattleCmds.avail(self, u)
	# M3D_PLAN §3.4（WP-COMBAT）：穿著烙跑鞋而且這場允許 → 任何格子都能逃（客戶端「逃」不必站逃跑格）
	d["flee_anywhere"] = u.flee_anywhere() and not BattleRules.special_flee_blocked(self, u)
	var ca := {}
	for cat in ["POISON", "MEDIC", "HIDDEN", "FORMATION", "INNER", "ACUPOINT"]:
		var list: Array = []
		for a in u.cmd_arts(cat):
			var row := BattleCmds.art_row(str(a), tables)
			if row.is_empty():
				continue
			var m := BattleCmds.first_move(row)
			list.append({ "id": str(a), "name": str(row.get("name", a)), "level": u.skill(str(a)),
				"range": int(m.get("range", 1)), "cost_inner": int(m.get("cost_inner", 0)) })
		ca[cat] = list
	d["cmd_arts"] = ca
	var hid: Array = []
	for it in u.hidden_items():
		if it is Dictionary:
			hid.append({ "uid": str(it.get("uid", "")), "item_id": str(it.get("item_id", "")), "name": str(it.get("name", "")),
				"n": u.stack_left(it), "dmg": int(it.get("dmg", 0)) })
	d["hidden_items"] = hid
	d["hidden_range"] = BattleCmds.hidden_range(u, "", tables)
	var bi: Array = []
	for it in u.battle_items():
		if it is Dictionary:
			bi.append({ "uid": str(it.get("uid", "")), "item_id": str(it.get("item_id", "")), "name": str(it.get("name", "")),
				"n": u.stack_left(it), "effects": (it.get("effects", []) as Array).duplicate(true) })
	d["battle_items"] = bi
	var fm: Variant = null
	for a in u.cmd_arts("FORMATION"):
		var row := BattleCmds.art_row(str(a), tables)
		if row.get("formation", null) is Dictionary:
			var st: Array = []
			for x in row.formation.get("stations", []):
				st.append([int(x[0]), int(x[1])] if x is Array and x.size() >= 2 else [0, 0])
			fm = { "art": str(a), "name": str(row.get("name", a)), "party_size": int(row.formation.get("party_size", 1)),
				"stations": st }
			break
	d["formation"] = fm

func outcome() -> Dictionary:
	var out_units := {}
	for u in units:
		out_units[u.uid] = {
			"uid": u.uid, "kind": u.kind(), "ref": str(u.spec.get("ref", "")), "side": u.side, "peer": u.peer,
			"alive": not u.is_dead(), "died": u.is_dead(), "fled": u.is_fled(),
			"qi": u.qi, "neili": u.neili, "jing": u.jing, "shen": u.shen,
			"weapon_uid": str(u.weapon.get("uid", "")),
			"kills": u.kills.duplicate(),
			"killed_by": u.killed_by,
			# M3A_PLAN 5.8：戰後寫回用
			"used_items": u.used_items.duplicate(),
			"statuses": _status_levels(u),
			"status_left": u.statuses.duplicate(),   # 狀態 id -> 剩餘行動次數（戰後持續狀態寫回用）
			"start_statuses": u.start_statuses.duplicate(),
			"cured_statuses": u.cured_statuses.duplicate(),   # 戰鬥中被治好的狀態（戰後寫回：只有這些才清掉）
			"sect": u.sect(),
			# M3D_PLAN §3.3.3、§5.3.4（WP-COMBAT）：合體一擊次數與夥伴、總傷害與命中次數
			"combo_hits": u.combo_hits,
			"combo_with": u.combo_with.duplicate(),
			"dmg_dealt": u.dmg_dealt,
			"hits_landed": u.hits_landed,
		}
	return { "bid": id, "result": result_name(), "ticks": tick_no, "units": out_units, "winner_side": winner_side(),
		"wave": { "n": wave_no, "total": wave_total } }

static func _status_levels(u: BattleUnit) -> Dictionary:
	var out := {}
	for sid in u.statuses:
		out[str(sid)] = u.status_level(str(sid))
	return out

## ---------------------------------------------------------------- 內部：tick

func _tick(tables: Dictionary) -> void:
	tick_no += 1
	if state == State.AWAIT_COMMAND:
		_await_tick(tables)
	elif state == State.RUNNING:
		_running_tick(tables)
	if state != State.ENDED and tick_no >= MAX_TICKS:
		_pending.clear()
		_end(Result.ABORTED)
	if _gauges_dirty and state != State.ENDED:
		_emit_gauges()

func _running_tick(tables: Dictionary) -> void:
	var newly: Array = []
	for u in units:
		if not u.can_charge():
			continue
		u.rate = BattleFormulas.atb_gain(u, tables)
		u.gauge += u.rate
		if u.gauge >= GAUGE_FULL:
			u.overflow = u.gauge - GAUGE_FULL
			u.gauge = GAUGE_FULL
			u.state = BattleUnit.READY
			newly.append(u)
	if not newly.is_empty():
		# 同 tick 多個單位滿條：溢出量 → 機敏 → uid（TECH_ARCH 13.4）
		newly.sort_custom(func(a, b):
			if a.overflow != b.overflow:
				return a.overflow > b.overflow
			if a.attr("agi") != b.attr("agi"):
				return a.attr("agi") > b.attr("agi")
			return a.uid < b.uid)
		_pending.append_array(newly)
		_gauges_dirty = true
	if _pending.is_empty():
		return
	if wait_mode() and not waiting_humans().is_empty():
		_enter_await()
		return
	_resolve_pending(tables)

func _enter_await() -> void:
	state = State.AWAIT_COMMAND
	_await_start_tick = tick_no
	_deadlines.clear()
	var waiting := waiting_humans()
	var max_deadline := tick_no
	for u in waiting:
		var t := BattleRules.unit_timeout(self, u, opts)
		var d := tick_no + ceili(t / TICK - 0.0001)
		_deadlines[u.uid] = d
		max_deadline = maxi(max_deadline, d)
	_events.append(make_event("battle_await", { "units": waiting.map(func(u): return u.uid),
		"deadline_tick": max_deadline }, true))
	_gauges_dirty = true

func _await_tick(tables: Dictionary) -> void:
	_round_wait_ticks += 1
	for u in waiting_humans():
		if tick_no >= int(_deadlines.get(u.uid, tick_no)):
			u.timeouts += 1
			if u.timeouts >= 2:
				u.afk = true
			u.queued_cmd = { "cmd": "DEFEND", "auto": true }
			_events.append(make_event("battle_timeout", { "uid": u.uid, "name": u.unit_name(), "peer": u.peer,
				"afk": u.afk }))
	if waiting_humans().is_empty():
		state = State.RUNNING
		_resolve_pending(tables)

func _resolve_pending(tables: Dictionary) -> void:
	state = State.RESOLVING
	for u in _pending.duplicate():
		if not u.is_active():
			_pending.erase(u)
			continue
		var cmd: Dictionary
		if u.is_ai():
			cmd = BattleRules.normalize_cmd(BattleAI.choose(self, u, tables, rng))
		elif u.queued_cmd.is_empty() and u.detached:
			cmd = { "cmd": "DEFEND" }   # 斷線的玩家：自動防守
			_round_acted[u.uid] = true
		elif u.queued_cmd.is_empty():
			continue   # 非等待模式：還沒下令的玩家停在滿條
		else:
			cmd = u.queued_cmd
			_round_acted[u.uid] = true
		# 同批前面的行動可能讓指令失效（目標死亡、格子被占）→ 改為「防」
		if cmd.is_empty() or BattleRules.validate_cmd(self, u, cmd, tables) != "":
			cmd = { "cmd": "DEFEND" }
		u.queued_cmd = {}
		_pending.erase(u)
		_events.append_array(BattleRules.execute(self, u, cmd, tables, rng))
		_gauges_dirty = true
		if _check_end(tables):
			return
	state = State.RUNNING
	var humans := active_humans()
	if not humans.is_empty() and humans.all(func(h): return _round_acted.has(h.uid)):
		_round_acted.clear()
		_round_wait_ticks = 0

func _check_end(tables: Dictionary = {}) -> bool:
	if opts.has("duel_limit_s") and has_method("_duel_check") and bool(call("_duel_check")): return true   # M3d WP-EVENTS
	if bool(opts.get("end_on_players_down", false)) and _rg_players_down(): return true   # ROGUE WP-ALLY
	var allies := units.any(func(u): return u.side == 0 and u.is_active())
	var enemies := units.any(func(u): return u.side == 1 and u.is_active())
	if allies and enemies:
		return false
	if allies and not enemies and not wave_specs.is_empty():
		_next_wave(tables)
		return false
	if allies and not enemies:
		_end(Result.VICTORY)
	elif units.any(func(u): return u.side == 0 and u.is_dead()):
		_end(Result.DEFEAT)
	else:
		_end(Result.ALL_FLED)
	return true

func _end(r: Result) -> void:
	result = r
	state = State.ENDED
	_pending.clear()
	_events.append(make_event("battle_end", { "result": result_name() }, true))

## 下一波從右側邊緣空格放入（battle_wave、每隻一個 battle_unit_join），戰鬥不結束
func _next_wave(tables: Dictionary) -> void:
	var specs: Array = wave_specs.pop_front()
	wave_no += 1
	_events.append(make_event("battle_wave", { "n": wave_no, "total": wave_total }))
	for spec in specs:
		var cell := join_cell(1)
		if cell == Vector2i(-1, -1):
			break
		var sp: Dictionary = spec.duplicate(true)
		sp["side"] = 1
		var u := BattleUnit.new(units.size() + 1, sp)
		u.side = 1
		u.pos = cell
		u.start_pos = cell
		u.gauge = 0.0
		u.rate = BattleFormulas.atb_gain(u, tables)
		u.state = BattleUnit.CHARGING
		units.append(u)
		if grid.units != units:
			grid.units = units
		_events.append(make_event("battle_unit_join", { "unit": _unit_snapshot(u, tables) }, true))
	_gauges_dirty = true

func _emit_gauges() -> void:
	_gauges_dirty = false
	var list: Array = []
	# 等待下令時全場時間棒暫停：charging 一律 false，否則客戶端會把「有人在充」當成等待結束而清掉 battle_await
	var flowing := state == State.RUNNING
	for u in units:
		list.append([u.uid, u.gauge, u.rate, flowing and u.can_charge()])
	_events.append(make_event("battle_gauges", { "tick": tick_no, "units": list }, true))

func _unit_for_peer(peer: int) -> BattleUnit:
	if peer <= 0:
		return null
	for u in units:
		if u.peer == peer:
			return u
	return null

func _flush() -> Array:
	var out := _events
	_events = []
	return out

# ==== M3d WP-EVENTS ====
## M3D_PLAN §5.3.4：比武（DUEL）的限時判定與強制結束（劫鏢的鏢單位倒下、比武棄權）。
## 結果記在 opts["ev_end"] = { winner_side, how }（how：JUDGE／FORFEIT／ROBBED）；BattleSystem 結算時讀。

## 限時到了 → TourneyRules.judge：總傷害 → 命中次數 → 目前氣／最大氣 → 先報名者（spec.duel_order 小者）勝；回 true＝已結束
func _duel_check() -> bool:
	if state == State.ENDED or state == State.SETUP or not opts.has("duel_limit_s"):
		return false
	if time_s() + 0.0001 < float(opts["duel_limit_s"]):
		return false
	var stats: Array = [_ev_side_stats(0), _ev_side_stats(1)]
	var w := TourneyRules.judge(stats[0], stats[1])
	ev_end(w, "JUDGE")
	return true

## 一方的判定統計：{ dmg, hits, qi, qi_max, order }（比武是一對一；多人時加總，order 取最小）
func _ev_side_stats(side: int) -> Dictionary:
	var st := { "dmg": 0, "hits": 0, "qi": 0, "qi_max": 0, "order": 1 << 30 }
	for u in units:
		if u.side != side:
			continue
		st["dmg"] = int(st["dmg"]) + int(u.dmg_dealt)
		st["hits"] = int(st["hits"]) + int(u.hits_landed)
		if not u.is_fled():
			st["qi"] = int(st["qi"]) + maxi(0, int(u.qi))
		st["qi_max"] = int(st["qi_max"]) + maxi(1, int(u.qi_max()))
		st["order"] = mini(int(st["order"]), int(u.spec.get("duel_order", 1 << 30)))
	return st

## 強制結束：winner_side 那一方勝（0 → VICTORY、1 → DEFEAT；winner_side() 依 side 1 還有人在場判 1）
func ev_end(winner_side_: int, how: String) -> void:
	if state == State.ENDED:
		return
	opts["ev_end"] = { "winner_side": winner_side_, "how": how }
	_pending.clear()
	_end(Result.VICTORY if winner_side_ == 0 else Result.DEFEAT)

# ==== ROGUE WP-ALLY ====
## ROGUE_PLAN §4.4（O6）：江湖試煉的戰鬥（opts.end_on_players_down）——我方（side 0）有玩家單位、
## 而且所有玩家單位都倒下（死亡或逃走）→ 立刻判負，就算 AI 隊友還活著也一樣（隊友不能代打）。回 true＝已結束。
## 註：同一下行動裡最後一個敵人與最後一位玩家同時倒下時也判負（winner_side() 此時回 -1）；試煉以「玩家倒下」為準。
func _rg_players_down() -> bool:
	if state == State.ENDED:
		return false
	var has_player := false
	for u in units:
		if u.side == 0 and u.is_player():
			has_player = true
			if u.is_active():
				return false
	if not has_player:
		return false
	_end(Result.DEFEAT)
	return true
