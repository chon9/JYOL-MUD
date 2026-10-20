extends "res://tests/test_case.gd"
## M3C_PLAN §4.2、§4.4（WP-NAV）：AutoWalkCore 的每一條停走規則（依序、第一個成立就停）、遇敵勝利續走、
## 續走選項關閉不續走、Esc 停止趕路；AutoWalker／MapPanel 的戰鬥接線。

var _nodes: Array = []
var sent: Array = []      # [[seq, kind, args]]
var _seq := 500
var _dir := ""
var _old_mem := false

## 假世界：甲區 r1 ─E─ r2 ─E─ r3 ═E═ 乙區 r4 ─E─ r5 ─E─ r6
## 另有岔路：r2 北 = 某派山門 gate、r3 北 = 牢房 jail、r4 北 = 帶路 NPC 房 guide、r5 北 = 需要條件的內室 inner
func _tables() -> Dictionary:
	var room := func(id: String, exits: Array, extra: Dictionary = {}) -> Dictionary:
		var ex: Array = []
		for e in exits:
			ex.append({ "dir": e[0], "to": e[1] })
		var r := { "id": id, "name": "房" + id, "exits": ex, "npcs": [], "requires": [] }
		r.merge(extra, true)
		return r
	return {
		"maps": {
			"ra": { "rooms": [room.call("r1", [["E", "r2"]]), room.call("r2", [["W", "r1"], ["E", "r3"], ["N", "gate"]]),
				room.call("r3", [["W", "r2"], ["E", "r4"], ["N", "jail"]]),
				room.call("gate", [["S", "r2"]]), room.call("jail", [["S", "r3"]], { "jail": true })] },
			"rb": { "rooms": [room.call("r4", [["W", "r3"], ["E", "r5"], ["N", "guide"]]), room.call("r5", [["W", "r4"], ["E", "r6"], ["N", "inner"]]),
				room.call("r6", [["W", "r5"]]), room.call("guide", [["S", "r4"]], { "npcs": ["n_guide"] }),
				room.call("inner", [["S", "r5"]], { "requires": [{ "type": "sect", "sect": "s1" }] })] },
		},
		"regions": { "ra": { "name": "甲區" }, "rb": { "name": "乙區" } },
		"npcs": { "n_guide": { "name": "帶路人", "services": ["GUIDE"] } },
		"sects": { "s1": { "id": "s1", "gate_room": "gate" } },
	}

const OK_SHEET := { "vitals": { "qi": 100, "qi_max": 100, "food": 80, "water": 80 }, "jail": {} }

func _v(room: String, exits: Array = []) -> Dictionary:
	return { "room": room, "exits": exits }

func _core(to: String, known_ids: Array = []) -> AutoWalkCore:
	var t := _tables()
	var g := RoutePlanner.graph(t)
	var known := {}
	for id in (known_ids if not known_ids.is_empty() else g.keys()):
		known[id] = true
	var c := AutoWalkCore.new()
	c.configure(t, g, known)
	c.start(RoutePlanner.find_path(g, "r1", to, known), "r1", "房" + to)
	return c

## 走一步：next_step 回 MOVE → 主機接受 → 新房間 view
func _step(c: AutoWalkCore, room_after: String, sheet: Dictionary = OK_SHEET) -> Dictionary:
	var act := c.next_step(_v(c.from_room), sheet)
	if str(act.get("action", "")) == "MOVE":
		c.on_move_result(true, "")
		assert_eq(c.next_step(_v(c.from_room), sheet).get("action"), "WAIT", "waits for the room view")
		c.observe(_v(room_after))
	return act

func before_each() -> void:
	sent.clear()
	_dir = temp_dir("m3cwalk")
	_old_mem = UiSettings.memory_only
	UiSettings.reset_for_tests(true)

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	UiSettings.reset_for_tests(_old_mem)
	if not _old_mem:
		UiSettings.reload()
	await tree.process_frame
	remove_dir_recursive(_dir)

# ---------------------------------------------------------------- 基本流程

func test_walks_to_destination_and_progress_text() -> void:
	var c := _core("r6")
	assert_true(c.is_active())
	assert_eq(c.remaining(), 5)
	assert_eq(c.progress_text(), "趕路中：往房r6（剩5步）")
	var dirs: Array = []
	var rooms := ["r2", "r3", "r4", "r5", "r6"]
	for r in rooms:
		var act := _step(c, r)
		assert_eq(act.get("action"), "MOVE", str(act))
		dirs.append(act["dir"])
	assert_eq(dirs, ["E", "E", "E", "E", "E"])
	assert_eq(c.next_step(_v("r6"), OK_SHEET), { "action": "ARRIVED" })
	assert_eq(c.remaining(), 0)
	# 附註
	var c2 := AutoWalkCore.new()
	c2.start([{ "dir": "E", "to": "r2" }], "r1", "某地", "（只能走到房r2，再往前沒去過）")
	assert_eq(c2.progress_text(), "趕路中：往某地（剩1步）（只能走到房r2，再往前沒去過）")

func test_waits_for_result_and_view() -> void:
	var c := _core("r3")
	assert_eq(c.next_step(_v("r1"), OK_SHEET).get("action"), "MOVE")
	assert_eq(c.next_step(_v("r1"), OK_SHEET), { "action": "WAIT" }, "move pending")
	c.on_move_result(true, "")
	assert_eq(c.next_step(_v("r1"), OK_SHEET), { "action": "WAIT" }, "view pending")
	assert_eq(c.next_step(_v("r2"), OK_SHEET).get("dir"), "E", "next step after the view")

# ---------------------------------------------------------------- §4.4 停走規則（依序）

func test_rule1_defeat() -> void:
	var c := _core("r6")
	_step(c, "r2")
	c.on_battle_start()
	assert_eq(c.next_step(_v("r2"), OK_SHEET), { "action": "WAIT" }, "in battle")
	c.on_battle_end("DEFEAT", true)
	assert_eq(c.next_step(_v("r2"), OK_SHEET), { "action": "STOP", "reason": "你倒下了，停止趕路。" })
	assert_false(c.is_active())

func test_rule2_fled() -> void:
	for r in ["FLED", "ALL_FLED"]:
		var c := _core("r6")
		_step(c, "r2")
		c.on_battle_start()
		c.on_battle_end(r, true)
		assert_eq(c.next_step(_v("r2"), OK_SHEET), { "action": "STOP", "reason": "你逃離了戰鬥，停止趕路。" }, r)

func test_rule3_victory_but_resume_off() -> void:
	var c := _core("r6")
	_step(c, "r2")
	c.on_battle_start()
	c.on_battle_end("VICTORY", false)
	assert_eq(c.next_step(_v("r2"), OK_SHEET), { "action": "STOP", "reason": "戰鬥結束，停止趕路。" })

func test_victory_resumes_from_current_room() -> void:
	var c := _core("r6")
	_step(c, "r2")
	# 遇敵發生在送出下一步之後（move 已送、view 還沒到）
	assert_eq(c.next_step(_v("r2"), OK_SHEET).get("action"), "MOVE")
	c.on_move_result(true, "")
	c.observe(_v("r3"))
	c.on_battle_start()
	c.on_battle_end("VICTORY", true)
	var act := c.next_step(_v("r3"), OK_SHEET)
	assert_eq(act, { "action": "MOVE", "dir": "E", "to": "r4" }, "resumes from r3 toward r6")
	assert_eq(c.remaining(), 3)
	c.on_move_result(true, "")
	c.observe(_v("r4"))
	_step(c, "r5")
	_step(c, "r6")
	assert_eq(c.next_step(_v("r6"), OK_SHEET), { "action": "ARRIVED" })

func test_victory_with_low_qi_stops() -> void:
	var c := _core("r6")
	_step(c, "r2")
	c.on_battle_start()
	c.on_battle_end("VICTORY", true)
	var low := { "vitals": { "qi": 25, "qi_max": 100, "food": 80, "water": 80 } }
	assert_eq(c.next_step(_v("r2"), low), { "action": "STOP", "reason": "氣血不足三成，先休息吧。" })

func test_rule4_qi_below_30_percent() -> void:
	var c := _core("r6")
	var s := { "vitals": { "qi": 29, "qi_max": 100, "food": 80, "water": 80 } }
	assert_eq(c.next_step(_v("r1"), s), { "action": "STOP", "reason": AutoWalkCore.MSG_QI })
	var c2 := _core("r6")
	s["vitals"]["qi"] = 30
	assert_eq(c2.next_step(_v("r1"), s).get("action"), "MOVE", "exactly 30% is fine")
	# 也接受平鋪的 sheet.qi（M3C_PLAN §4.4 字面）
	var c3 := _core("r6")
	assert_eq(c3.next_step(_v("r1"), { "qi": 10, "qi_max": 100 }).get("reason"), AutoWalkCore.MSG_QI)

func test_rule5_food_and_water() -> void:
	var cases := [
		[{ "qi": 100, "qi_max": 100, "food": 19, "water": 19 }, AutoWalkCore.MSG_HUNGRY_THIRSTY],
		[{ "qi": 100, "qi_max": 100, "food": 19, "water": 50 }, AutoWalkCore.MSG_HUNGRY],
		[{ "qi": 100, "qi_max": 100, "food": 50, "water": 10 }, AutoWalkCore.MSG_THIRSTY],
	]
	for cs in cases:
		var c := _core("r6")
		assert_eq(c.next_step(_v("r1"), { "vitals": cs[0] }), { "action": "STOP", "reason": cs[1] }, str(cs[0]))
	assert_eq(AutoWalkCore.MSG_HUNGRY_THIRSTY, "又餓又渴，先吃點東西。")
	var ok := _core("r6")
	assert_eq(ok.next_step(_v("r1"), { "vitals": { "qi": 100, "qi_max": 100, "food": 20, "water": 20 } }).get("action"), "MOVE")

func test_rule6_locked_exit() -> void:
	var c := _core("r6")
	var v := _v("r1", [{ "dir": "E", "to": "r2", "to_name": "房r2", "locked": true, "lock_reason": "夜裡城門關了" }])
	assert_eq(c.next_step(v, OK_SHEET), { "action": "STOP", "reason": "前方房r2去不了：夜裡城門關了" })
	# 別的方向鎖住不影響
	var c2 := _core("r6")
	var v2 := _v("r1", [{ "dir": "E", "to": "r2", "locked": false }, { "dir": "N", "to": "x", "locked": true, "lock_reason": "?" }])
	assert_eq(c2.next_step(v2, OK_SHEET).get("action"), "MOVE")

func test_rule7_decision_rooms() -> void:
	var t := _tables()
	var g := RoutePlanner.graph(t)
	var c := AutoWalkCore.new()
	c.configure(t, g, {})
	var none := {}
	assert_true(c.decision_room("gate", none), "another sect's gate")
	assert_false(c.decision_room("gate", { "sect": "s1" }), "own sect's gate")
	assert_true(c.decision_room("jail", none), "jail: true")
	assert_true(c.decision_room("guide", none), "GUIDE npc")
	assert_true(c.decision_room("inner", none), "requires")
	assert_false(c.decision_room("inner", { "sect": "s1" }), "own-sect-only requires")
	assert_false(c.decision_room("r2", none))
	# 經過要自己決定的房間（不是終點）→ 停
	var t2 := _tables()
	t2["maps"]["ra"]["rooms"][1]["requires"] = [{ "type": "quest", "quest": "q1" }]   # r2
	var g2 := RoutePlanner.graph(t2)
	var c2 := AutoWalkCore.new()
	c2.configure(t2, g2, {})
	c2.start(RoutePlanner.steps(g2, ["r1", "r2", "r3"]), "r1", "房r3")
	assert_eq(c2.next_step(_v("r1"), OK_SHEET), { "action": "STOP", "reason": "前方是房r2，請自己決定要不要進去。" })
	# 終點本身是要決定的房間：照走
	var c3 := AutoWalkCore.new()
	c3.configure(t, g, {})
	c3.start(RoutePlanner.steps(g, ["r1", "r2", "gate"]), "r1", "山門")
	assert_eq(c3.next_step(_v("r1"), OK_SHEET).get("action"), "MOVE")
	c3.on_move_result(true, "")
	c3.observe(_v("r2"))
	assert_eq(c3.next_step(_v("r2"), OK_SHEET), { "action": "MOVE", "dir": "N", "to": "gate" }, "destination is exempt")

func test_rule8_move_rejected() -> void:
	var c := _core("r6")
	c.next_step(_v("r1"), OK_SHEET)
	c.on_move_result(false, "overweight")
	assert_eq(c.next_step(_v("r1"), OK_SHEET), { "action": "STOP", "reason": "趕路中斷：overweight" })
	var c2 := _core("r6")
	c2.reason_text = func(code: String) -> String: return "背的東西太重" if code == "overweight" else ""
	c2.next_step(_v("r1"), OK_SHEET)
	c2.on_move_result(false, "overweight")
	assert_eq(c2.next_step(_v("r1"), OK_SHEET).get("reason"), "趕路中斷：背的東西太重")

func test_rule9_jailed() -> void:
	var c := _core("r6")
	var s := OK_SHEET.duplicate(true)
	s["jail"] = { "sect_name": "武當", "left_s": 100 }
	assert_eq(c.next_step(_v("r1"), s), { "action": "STOP", "reason": "身在牢中，無法趕路。" })

func test_rules_checked_in_order() -> void:
	# 氣不足（#4）與出口鎖住（#6）同時成立：先報 #4
	var c := _core("r6")
	var v := _v("r1", [{ "dir": "E", "to": "r2", "locked": true, "lock_reason": "鎖" }])
	var s := { "vitals": { "qi": 1, "qi_max": 100, "food": 1, "water": 1 }, "jail": { "x": 1 } }
	assert_eq(c.next_step(v, s).get("reason"), AutoWalkCore.MSG_QI)
	# 飢渴（#5）與坐牢（#9）：先報 #5
	var c2 := _core("r6")
	s["vitals"]["qi"] = 100
	assert_eq(c2.next_step(v, s).get("reason"), AutoWalkCore.MSG_HUNGRY_THIRSTY)
	# 戰敗（#1）優先於氣不足（#4）
	var c3 := _core("r6")
	_step(c3, "r2")
	c3.on_battle_start()
	c3.on_battle_end("DEFEAT", true)
	assert_eq(c3.next_step(_v("r2"), s).get("reason"), AutoWalkCore.MSG_DEFEAT)

func test_unexpected_room_stops_and_manual_stop() -> void:
	var c := _core("r6")
	_step(c, "r2")
	c.observe(_v("somewhere"))
	assert_false(c.is_active())
	assert_eq(c.next_step(_v("somewhere"), OK_SHEET), { "action": "STOP", "reason": AutoWalkCore.MSG_MOVED })
	var c2 := _core("r6")
	c2.stop()
	assert_eq(c2.next_step(_v("r1"), OK_SHEET), { "action": "STOP", "reason": "已停止趕路。" })

# ---------------------------------------------------------------- AutoWalker／MapPanel 接線（真資料）

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _sender(kind: String, args: Dictionary) -> int:
	_seq += 1
	sent.append([_seq, kind, args])
	return _seq

func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame

var _data: Dictionary = {}
func _real() -> Dictionary:
	if _data.is_empty():
		var loader := DataLoader.new()
		loader.load_all("res://data")
		_data = loader.activate(["1.0A"])
	return _data

func _room_view(room: String) -> Dictionary:
	var t := _real()
	var idx := MapData.room_index(t)
	var region: String = idx[room]["region"]
	return { "room": room, "room_name": str(idx[room]["room"]["name"]), "region": region,
		"region_name": MapData.region_name(t, region), "exits": [], "npcs": [] }

func _panel() -> MapPanel:
	var gate := _add(IntentGate.new()) as IntentGate
	gate.set_sender(_sender)
	var p := MapPanel.new()
	p.gate = gate
	p.tables_override = _real()
	p.memory = MapMemory.new(_dir)
	_add(p)
	p.walker.step_delay_s = 0.0
	p.walker.resume_delay_s = 0.0
	p.apply_sheet({ "char_id": "ch_walktest", "vitals": OK_SHEET["vitals"] })
	for r in ["xx_square", "xx_gate_e", "xw_road", "xw_grass"]:
		p.apply_view(_room_view(r))
	p.apply_view(_room_view("xx_square"))
	return p

## 送出的 move 被主機接受、房間 view 到了
func _accept(p: MapPanel, room: String) -> void:
	p.walker.gate.resolve(sent[sent.size() - 1][0], true, "")
	p.apply_view(_room_view(room))
	await _frames(2)

func test_panel_victory_resume_and_option_off() -> void:
	var p := _panel()
	p._on_room_clicked("xw_grass")
	assert_true(p.is_walking())
	assert_eq(sent.size(), 1)
	assert_true(p.status_label.text.begins_with("趕路中：往"), p.status_label.text)
	assert_true(p.status_label.text.contains("剩3步"), p.status_label.text)
	await _accept(p, "xx_gate_e")
	assert_eq(sent.size(), 2)
	p.walker.gate.resolve(sent[1][0], true, "")
	p.apply_view(_room_view("xw_road"))
	# 遇敵（主畫面 open_battle → close_battle → _on_battle_finished 的順序）
	p.on_battle()
	await _frames(2)
	assert_eq(sent.size(), 2, "paused in battle")
	assert_true(p.is_walking())
	p.on_battle_result({ "result": "VICTORY" })
	assert_true(UiSettings.get_bool(MapPanel.AUTO_RESUME_KEY), "auto resume defaults on")
	p.on_battle_closed()
	await _frames(3)
	assert_eq(sent.size(), 3, "resumed after victory")
	assert_eq(sent[2][2], { "dir": "E" })
	await _accept(p, "xw_grass")
	assert_false(p.is_walking())
	assert_eq(p.status_label.text, "已抵達。")

	# 選項關閉：打贏也停
	UiSettings.set_value(MapPanel.AUTO_RESUME_KEY, false)
	p._on_room_clicked("xx_square")
	assert_true(p.is_walking())
	await _accept(p, "xw_road")
	p.on_battle()
	p.on_battle_result({ "result": "VICTORY" })
	p.on_battle_closed()
	await _frames(3)
	assert_false(p.is_walking())
	assert_eq(p.status_label.text, "戰鬥結束，停止趕路。")

func test_esc_stops_walking_first() -> void:
	var p := _panel()
	assert_false(p.esc_stop(), "not walking: Esc does nothing here")
	p._on_room_clicked("xw_grass")
	assert_true(p.is_walking())
	assert_true(p.esc_stop())
	assert_false(p.is_walking())
	assert_eq(p.status_label.text, "已停止趕路。")
	# 主畫面：趕路中 Esc 不關視窗
	var main: Node = (load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate()
	_add(main)
	await tree.process_frame
	main.map_panel.memory = MapMemory.new(_dir)
	main.map_panel.tables_override = _real()
	main.map_panel.walker.gate.set_sender(_sender)
	main.toggle_panel("map")
	for r in ["xx_square", "xx_gate_e", "xx_square"]:
		main.map_panel.apply_view(_room_view(r))
	main.map_panel._on_room_clicked("xx_gate_e")
	assert_true(main.map_panel.is_walking())
	var k := InputEventKey.new()
	k.keycode = KEY_ESCAPE
	k.pressed = true
	main._shortcut_input(k)
	assert_false(main.map_panel.is_walking(), "Esc stopped walking")
	assert_true(main.panel_frame.visible, "map window still open")
	main._shortcut_input(k)
	assert_false(main.panel_frame.visible, "second Esc closes the window")

func test_panel_defeat_and_flee_stop() -> void:
	for r in [["DEFEAT", AutoWalkCore.MSG_DEFEAT], ["FLED", AutoWalkCore.MSG_FLED]]:
		var p := _panel()
		p._on_room_clicked("xw_grass")
		p.on_battle()
		p.on_battle_result({ "result": r[0] })
		# 戰敗重生／逃走後的新位置在戰鬥畫面收起時才套用：原因仍是戰敗／逃走，不是「位置變了」
		p.apply_view(_room_view("xx_station"))
		p.on_battle_closed()
		await _frames(3)
		assert_false(p.is_walking(), r[0])
		assert_eq(p.status_label.text, r[1])
