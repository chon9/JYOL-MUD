extends "res://tests/test_case.gd"
## 擁有者回報：自動趕路走一步就不動。本機主機先送房間 view、後送 intent_result，
## AutoWalker 在結果到之前就推進到下一步，晚到的結果被丟掉 → core.move_pending 卡住。

var sent: Array = []
var _seq := 700
var _nodes: Array = []

func before_each() -> void:
	sent.clear()

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

func _sender(kind: String, args: Dictionary) -> int:
	_seq += 1
	sent.append([_seq, kind, args])
	return _seq

func _v(room: String) -> Dictionary:
	return { "room": room, "exits": [] }

const PATH := [{ "dir": "E", "to": "r2" }, { "dir": "E", "to": "r3" }, { "dir": "E", "to": "r4" }]
const SHEET := { "vitals": { "qi": 100, "qi_max": 100 }, "food": 100, "water": 100 }

func test_core_view_before_result_keeps_walking() -> void:
	var c := AutoWalkCore.new()
	c.start(PATH, "r1", "終點")
	assert_eq(c.next_step(_v("r1"), SHEET).get("action"), "MOVE")
	c.observe(_v("r2"))          # 房間先到
	var nxt := c.next_step(_v("r2"), SHEET)
	assert_eq(nxt.get("action"), "MOVE", "second step goes out even though the first result has not arrived")
	assert_eq(nxt.get("to"), "r3")

func test_walker_view_before_result_walks_to_the_end() -> void:
	var gate := IntentGate.new()
	gate.set_sender(_sender)
	tree.root.add_child(gate)
	_nodes.append(gate)
	var w := AutoWalker.new()
	w.gate = gate
	w.step_delay_s = 0.0
	tree.root.add_child(w)
	_nodes.append(w)
	w.view = _v("r1")
	w.sheet = SHEET
	w.start(PATH, "r1", "終點")
	for room in ["r2", "r3", "r4"]:
		await tree.process_frame
		await tree.process_frame
		assert_true(sent.size() > 0, "a move was sent before reaching " + room)
		var last: Array = sent[sent.size() - 1]
		w.on_view(_v(room))               # 本機主機：view 先到
		gate.resolve(last[0], true, "")   # 結果後到
	await tree.process_frame
	await tree.process_frame
	assert_eq(sent.filter(func(x): return x[1] == UiKeys.I_MOVE).size(), 3, "all three steps sent")
	assert_false(w.is_walking(), "arrived")
	assert_eq(w.last_text, AutoWalkCore.MSG_ARRIVED)
