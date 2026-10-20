extends "res://tests/bots/m3b_bot.gd"
## M3c 驗收 bot（M3C_PLAN §12.3）：一個「玩家」的驅動器，由 tools/m3c_acceptance.gd 的 worker 在同一行程裡建立。
## 沿用 M3b／故事驗收 bot：WorldServer 是真的主機（GameHost、全部系統、--debug-intents），玩家是假的遠端 peer，
## 所有動作都經 WorldServer.handle_intent；走路一步一步 move（不 teleport；teleport 只用來把 bot 送回起點）。
## 這裡加 M3c 劇本要用的：創角帶 look、戰鬥開場快照與結算（battle_open／battle_close）、走路時記錄已探索房間、
## 以 AutoWalkCore 驅動跨區趕路、強化到能打頭目。

var look := -1                     # 創角時帶的 look（-1 = 不帶，舊客戶端）
var battle_opens: Array = []       # battle_open 的 state
var battle_closes: Array = []      # battle_close 的 result
var known: Dictionary = {}         # 走過的房間（＝客戶端的 MapMemory.visited；nav_walk 用）

func on_capture(what: String, payload: Variant) -> void:
	match what:
		"battle_open":
			battle_opens.append(payload)
		"battle_close":
			battle_closes.append(payload)
		_:
			super.on_capture(what, payload)

func create_char() -> bool:
	if not connect_session():
		return false
	if not must("char_roll"):
		return false
	var args := { "name": pname, "gender": gender, "birth_month": 3, "birth_city": city, "alloc": { "wit": 5 } }
	if look >= 0:
		args["look"] = look
	if not must("char_create", args):
		return false
	char_id = str(ch().id)
	known[room()] = true
	if not debug("money", 20000):
		return false
	if not keep_weak:
		make_strong()
		debug("combat_xp", BOT_COMBAT_XP)
	refill()
	return err == ""

## 頭目級：屬性、兵器與基本武功拉高，實戰提高（武學上限）；打鬼王、讀秘笈用
func make_very_strong() -> void:
	for a in STRONG_ATTRS:
		debug("attr:" + a, 260)
	for sk in STRONG_SKILLS:
		if SkillBook.kind_of(sk, tables()) != "":
			debug("skill:" + sk, 220)
	debug("combat_xp", 300000)
	refill()

## 走路並記錄已探索房間（同 walk；每一步之後把所在房間記進 known）
func walk_record(target: String) -> bool:
	if not host().index.has_room(target):
		return fail("walk_record: unknown room " + target)
	known[room()] = true
	var steps := 0
	while room() != target:
		if err != "":
			return false
		clear_battles()
		var p := path_to(target)
		if p.is_empty():
			break
		if str(p[0]) == "?":
			return fail("walk_record: no path %s -> %s" % [room(), target])
		var r := send("move", { "dir": str(p[0]) })
		if not r.get("ok", false):
			if str(r.get("reason", "")) == "in_battle":
				clear_battles()
				continue
			return fail("move %s at %s -> %s" % [str(p[0]), room(), str(r.get("reason", ""))])
		steps += 1
		moves += 1
		known[room()] = true
		if steps > MAX_WALK_STEPS:
			return fail("walk_record: too many steps to " + target)
		advance(0.2)
		clear_battles()
		known[room()] = true
		_top_up()
	return true

## 走到 target 路上、下一步就要進入 region 之前停下（設善惡為負的角色要先出城、還沒進山門）
func walk_until_region(target: String, region_id: String) -> bool:
	var steps := 0
	while room() != target:
		if err != "":
			return false
		clear_battles()
		var p := path_to(target)
		if p.is_empty() or str(p[0]) == "?":
			return fail("walk_until_region: no path %s -> %s" % [room(), target])
		var nxt := _next_room(str(p[0]))
		if nxt != "" and host().index.region_of(nxt) == region_id:
			return true
		var r := send("move", { "dir": str(p[0]) })
		if not r.get("ok", false):
			if str(r.get("reason", "")) == "in_battle":
				clear_battles()
				continue
			return fail("move %s at %s -> %s" % [str(p[0]), room(), str(r.get("reason", ""))])
		steps += 1
		moves += 1
		if steps > MAX_WALK_STEPS:
			return fail("walk_until_region: too many steps")
		advance(0.2)
		clear_battles()
		_top_up()
	return true

func _next_room(dir: String) -> String:
	for ex in host().index.room(room()).get("exits", []):
		if ex is Dictionary and str(ex.get("dir", "")) == dir:
			return str(ex.get("to", ""))
	return ""

func _top_up() -> void:
	var c = ch()
	if c == null:
		return
	var d: Dictionary = c.derived(tables(), ws.options)
	if int(c.vitals.get("qi", 0)) < int(d.get("qi_max", 1)) / 2 or int(c.vitals.get("food", 0)) < 30 \
			or int(c.vitals.get("water", 0)) < 30:
		refill()

## 目前戰鬥給我的開場快照（與 BattleSystem 送給客戶端的同一份，已依我方遮蔽）
func battle_state() -> Dictionary:
	var o := s()
	if o == null or o.battle_id == 0:
		return {}
	var entry: Dictionary = host().battles.active.get(o.battle_id, {})
	if entry.is_empty():
		return {}
	return host().battles._state_for(entry, peer)

func my_snapshot_unit(state: Dictionary) -> Dictionary:
	var my_uid := int(state.get("my_uid", -1))
	for u in state.get("units", []):
		if u is Dictionary and int(u.get("uid", -2)) == my_uid:
			return u
	return {}

## view 裡的 NPC id
func view_npc_ids() -> Array:
	var out: Array = []
	for n in view.get("npcs", []):
		if n is Dictionary:
			out.append(str(n.get("id", "")))
	return out

func view_npc(npc_id: String) -> Dictionary:
	for n in view.get("npcs", []):
		if n is Dictionary and str(n.get("id", "")) == npc_id:
			return n
	return {}

## 用 AutoWalkCore 驅動跨區趕路（每一步都是主機驗證的 move）。
## 回 { result: "ARRIVED"|"STOP", reason, steps, battles, resumed }；
## encounter_at：第幾步之前先 debug_set encounter_next（-1 不設）；resume：續走選項
func auto_walk(core, encounter_at := -1, resume := true, max_iter := 4000) -> Dictionary:
	var steps := 0
	var battles := 0
	var resumed := 0
	var it := 0
	var pending_resume := false
	while it < max_iter and err == "":
		it += 1
		flush_view()
		if s().battle_id != 0:
			core.on_battle_start()
			var res := drive_battle("fight")
			battles += 1
			refill()
			flush_view()
			core.on_battle_end(res if res != "" else "ABORTED", resume)
			pending_resume = true
			continue
		var sh: Dictionary = fresh_sheet()
		var st: Dictionary = core.next_step(view, sh)
		match str(st.get("action", "")):
			"ARRIVED":
				return { "result": "ARRIVED", "reason": core.stop_reason, "steps": steps, "battles": battles, "resumed": resumed }
			"STOP":
				return { "result": "STOP", "reason": str(st.get("reason", "")), "steps": steps, "battles": battles, "resumed": resumed }
			"WAIT":
				advance(0.1)
			"MOVE":
				if pending_resume:
					resumed += 1
					pending_resume = false
				if encounter_at >= 0 and steps == encounter_at:
					debug("encounter_next", true)
				var r := send("move", { "dir": str(st.get("dir", "")) })
				core.on_move_result(bool(r.get("ok", false)), str(r.get("reason", "")))
				if r.get("ok", false):
					steps += 1
					moves += 1
					known[room()] = true
				advance(0.2)
	return { "result": "TIMEOUT", "reason": err, "steps": steps, "battles": battles, "resumed": resumed }
