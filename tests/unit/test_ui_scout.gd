extends "res://tests/test_case.gd"
## 查看偵察的介面（docs/GDD.md §5.10【設計提案・非原作】）：ScoutDialog 的文字、迎戰（Enter）／離開（Esc、⊠）送的 intent、
## scout_closed 與換房間時關閉；熱鍵列與指令窗的「查看（5 秒）」倒數。全部用假資料。

var _nodes: Array = []

func before_each() -> void:
	UiSettings.reset_for_tests(true)

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _gate(sent: Array, ok := true, reason := "") -> IntentGate:
	var g := IntentGate.new()
	_add(g)
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		var seq := sent.size()
		g.resolve.call_deferred(seq, ok, reason)
		return seq)
	return g

static func offer(id := "sc_1") -> Dictionary:
	return { "offer_id": id, "room": "dlw_road", "room_name": "北門外大道", "ttl_s": 30.0,
		"monsters": [ { "id": "m_rabbit", "name": "野兔", "n": 2 } ], "text": "你發現附近有：野兔 ×2" }

func _dialog(sent: Array, ok := true, reason := "") -> ScoutDialog:
	var d := ScoutDialog.new()
	d.gate = _gate(sent, ok, reason)
	_add(d)
	return d

func test_offer_window_text() -> void:
	var d := _dialog([])
	await tree.process_frame
	d.open_offer(offer())
	assert_true(d.visible)
	assert_eq(d.message_label.text, "你發現附近有：野兔 ×2")
	assert_eq(d.title_label.text, "查看・北門外大道")
	assert_eq(d.accept_button.text, "迎戰")
	assert_eq(d.leave_button.text, "離開")
	assert_true(d.countdown_label.text.contains("秒內決定"), d.countdown_label.text)
	assert_eq(ScoutDialog.offer_text({ "monsters": [ { "name": "野兔", "n": 2 }, { "name": "野狼", "n": 1 } ] }),
		"你發現附近有：野兔 ×2、野狼 ×1", "舊主機沒有 text 時自己組")

func test_accept_sends_offer_id_only() -> void:
	var sent: Array = []
	var d := _dialog(sent)
	await tree.process_frame
	d.open_offer(offer("sc_abc"))
	d.accept()
	assert_eq(sent, [["scout_accept", { "offer_id": "sc_abc" }]])
	d.accept()
	assert_eq(sent.size(), 1, "連按不重送")
	await tree.process_frame
	await tree.process_frame
	assert_false(d.visible, "成功後關掉（戰鬥畫面接手）")

func test_accept_failure_shows_reason() -> void:
	var sent: Array = []
	var d := _dialog(sent, false, "scout_expired")
	await tree.process_frame
	d.open_offer(offer())
	d.accept()
	await tree.process_frame
	await tree.process_frame
	assert_true(d.visible, "失敗時留著顯示原因")
	assert_true(d.status_label.text != "", "原因：%s" % d.status_label.text)
	d.close()
	assert_false(d.visible)
	assert_eq(sent.size(), 1, "已經回覆過，關掉不再送離開")

func test_leave_sends_decline() -> void:
	var sent: Array = []
	var d := _dialog(sent)
	await tree.process_frame
	d.open_offer(offer("sc_x"))
	d.close()   # 「離開」、⊠、Esc（主畫面 _close_dialogs）都走 close()
	assert_false(d.visible)
	assert_eq(sent, [["scout_decline", { "offer_id": "sc_x" }]])
	d.close()
	assert_eq(sent.size(), 1, "沒有提示時不送")

func test_enter_accepts() -> void:
	var sent: Array = []
	var d := _dialog(sent)
	await tree.process_frame
	d.open_offer(offer("sc_k"))
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	d._shortcut_input(ev)
	assert_eq(sent, [["scout_accept", { "offer_id": "sc_k" }]])

func test_closed_event_and_room_change() -> void:
	var sent: Array = []
	var d := _dialog(sent)
	await tree.process_frame
	d.open_offer(offer("sc_1"))
	d.on_closed({ "offer_id": "sc_other", "why": "replaced" })
	assert_true(d.visible, "別的提示的 scout_closed 不關")
	d.on_closed({ "offer_id": "sc_1", "why": "expired" })
	assert_false(d.visible)
	d.open_offer(offer("sc_2"))
	d.on_room("dlw_road")
	assert_true(d.visible, "同一個房間")
	d.on_room("dlw_lake")
	assert_false(d.visible, "換房間就關")
	assert_eq(sent.size(), 0, "主機收回的提示不再送離開")

func test_hotbar_look_counts_down_only_with_scout_cooldown() -> void:
	var h := Hotbar.new()
	_add(h)
	await tree.process_frame
	h.apply_sheet({ "char_id": "ch_sc", "vitals": { "neili": 30, "neili_max": 50 },
		"cooldowns": { "meditate": 0.0, "life": 0.0, "scout": 5.0 } })
	h._update_states()
	var look: HotbarSlot = h.slots[Hotbar.ROW_CMD][2]   # 預設 F3 = 查看
	assert_eq(look.glyph, "查看")
	assert_eq(look.visible_text(), "查看（5 秒）")
	assert_true(look.disabled)
	h.apply_sheet({ "char_id": "ch_sc", "vitals": { "neili": 30, "neili_max": 50 },
		"cooldowns": { "meditate": 0.0, "life": 0.0, "scout": 0.0 } })
	h._update_states()
	assert_eq(look.visible_text(), "查看")
	assert_false(look.disabled, "安全的房間（scout = 0）隨時能查看")

func test_command_panel_look_countdown() -> void:
	var p := CommandPanel.new()
	_add(p)
	await tree.process_frame
	p.set_tab("ACTION")
	p.apply_sheet({ "cooldowns": { "scout": 4.0 } })
	var b: JyButton = p.buttons["look"]
	assert_eq(b.text, "查看（4 秒）")
	assert_true(b.disabled)
