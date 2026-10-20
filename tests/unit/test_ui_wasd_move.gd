extends "res://tests/test_case.gd"
## WASD 走路（擁有者要求）：W 北、S 南、A 西、D 東；兩鍵同按走斜向；照出口鈕走（沒有出口、灰掉都不走）；
## 打字、對話視窗開著時不走。

var _nodes: Array = []
var sent: Array = []
var _seq := 900
var _old_mem := false
const MS := "res://ui/game/main/main_screen.gd"

func before_each() -> void:
	sent.clear()
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

func _sender(kind: String, args: Dictionary) -> int:
	_seq += 1
	sent.append([_seq, kind, args])
	return _seq

func test_wasd_dir_mapping() -> void:
	var f: Callable = (load(MS) as GDScript).wasd_dir
	assert_eq(f.call(true, false, false, false), "N")
	assert_eq(f.call(false, true, false, false), "S")
	assert_eq(f.call(false, false, true, false), "W")
	assert_eq(f.call(false, false, false, true), "E")
	assert_eq(f.call(true, false, true, false), "NW", "W+A")
	assert_eq(f.call(true, false, false, true), "NE", "W+D")
	assert_eq(f.call(false, true, true, false), "SW", "A+S")
	assert_eq(f.call(false, true, false, true), "SE", "S+D")
	assert_eq(f.call(true, true, false, false), "", "opposite keys cancel")
	assert_eq(f.call(true, true, true, false), "W", "W+S cancel, A stays")
	assert_eq(f.call(false, false, false, false), "")
	for d in ["N", "S", "E", "W", "NE", "NW", "SE", "SW"]:
		assert_true(d in Protocol.DIRS, d + " is a protocol direction")

func _main() -> Node:
	var main: Node = (load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	_nodes.append(main)
	main.scene_panel._gate().set_sender(_sender)
	main.scene_panel.apply_view({ "room": "r1", "room_name": "測試房", "region_name": "測試",
		"exits": [{ "dir": "N", "to_name": "北房" }, { "dir": "NE", "to_name": "東北房" },
			{ "dir": "W", "to_name": "西房", "locked": true }], "npcs": [] })
	return main

func _key(kc: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = kc
	k.physical_keycode = kc
	k.pressed = true
	return k

func _moves() -> Array:
	return sent.filter(func(x): return x[1] == UiKeys.I_MOVE).map(func(x): return x[2]["dir"])

func _wait_combo() -> void:
	await tree.create_timer(0.2).timeout

func test_w_moves_north() -> void:
	var main := _main()
	await tree.process_frame
	main._shortcut_input(_key(KEY_W))
	await _wait_combo()
	assert_eq(_moves(), ["N"])

func test_w_plus_d_moves_northeast() -> void:
	var main := _main()
	await tree.process_frame
	main._shortcut_input(_key(KEY_W))
	main._shortcut_input(_key(KEY_D))
	await _wait_combo()
	assert_eq(_moves(), ["NE"], "two keys inside the combo window = one diagonal step")

func test_no_exit_or_locked_exit_does_nothing() -> void:
	var main := _main()
	await tree.process_frame
	main._shortcut_input(_key(KEY_S))   # 沒有南邊出口
	await _wait_combo()
	main._shortcut_input(_key(KEY_A))   # 西邊鎖住
	await _wait_combo()
	assert_eq(_moves(), [])

func test_typing_or_dialog_open_blocks() -> void:
	var main := _main()
	await tree.process_frame
	var le := LineEdit.new()
	main.add_child(le)
	le.grab_focus()
	main._shortcut_input(_key(KEY_W))
	await _wait_combo()
	assert_eq(_moves(), [], "typing in chat")
	le.release_focus()
	main.npc_dialog.visible = true
	main._shortcut_input(_key(KEY_W))
	await _wait_combo()
	assert_eq(_moves(), [], "dialog open")
	main.npc_dialog.visible = false
	var ctrl := _key(KEY_W)
	ctrl.ctrl_pressed = true
	main._shortcut_input(ctrl)
	await _wait_combo()
	assert_eq(_moves(), [], "Ctrl+W is not a move")
