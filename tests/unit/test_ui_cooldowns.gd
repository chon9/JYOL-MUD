extends "res://tests/test_case.gd"
## 客戶端冷卻倒數（CooldownTracker）：收到 sheet.cooldowns 記下本機到期時刻、自己倒數；
## 熱鍵列、指令窗、場景卷軸的按鈕文字「修煉（7 秒）」並灰掉，冷卻完回到原名。

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

func test_tracker_counts_down_locally() -> void:
	var t := CooldownTracker.new()
	var s1 := { "cooldowns": { "meditate": 6.2, "life": 0.0 }, "_rx_ms": 1000 }
	t.update(s1, 1000)
	assert_eq(t.left_s("meditate", 1000), 7, "ceil")
	assert_eq(t.left_s("meditate", 3000), 5)
	assert_eq(t.left_s("meditate", 7200), 0)
	assert_eq(t.left_s("life", 1000), 0)
	assert_eq(t.left_s("", 1000), 0)
	# 同一份角色表再套一次（開視窗時給舊角色表）：到期時刻照收件時刻算，不重設倒數
	t.update(s1, 5000)
	assert_eq(t.left_s("meditate", 5000), 3)
	# 新的角色表（主機送出當下重算）才更新
	t.update({ "cooldowns": { "meditate": 1.5, "life": 4.0 }, "_rx_ms": 5000 }, 5000)
	assert_eq(t.left_s("meditate", 5000), 2)
	assert_eq(t.left_s("life", 5000), 4)
	# 比上一份舊的角色表不採用
	t.update(s1, 5000)
	assert_eq(t.left_s("meditate", 5000), 2, "stale sheet ignored")
	# 沒有 cooldowns 的角色表（舊主機）不動
	t.update({ "_rx_ms": 5500 }, 5500)
	assert_eq(t.left_s("life", 5000), 4)

## 兩次動作的剩餘秒數一模一樣、中間沒有別的角色表：第二次照樣開始倒數（不靠數值比對去重）
func test_tracker_identical_values_restart() -> void:
	var t := CooldownTracker.new()
	t.update({ "cooldowns": { "meditate": 0.0, "life": 5.0 }, "_rx_ms": 1000 }, 1000)
	assert_eq(t.left_s("life", 6500), 0, "first cooldown over")
	t.update({ "cooldowns": { "meditate": 0.0, "life": 5.0 }, "_rx_ms": 7000 }, 7000)
	assert_eq(t.left_s("life", 7000), 5, "second identical cooldown starts")
	# 沒有收件時刻（直接餵）也一樣
	var u := CooldownTracker.new()
	u.update({ "cooldowns": { "life": 5.0 } }, 1000)
	u.update({ "cooldowns": { "life": 5.0 } }, 7000)
	assert_eq(u.left_s("life", 7000), 5)

## 浮點雜訊（5.0000000001）不會讓剛開始的倒數顯示成 6 秒
func test_tracker_no_off_by_one() -> void:
	var t := CooldownTracker.new()
	t.update({ "cooldowns": { "life": 5.0000000001, "meditate": 10.0000000004 }, "_rx_ms": 0 }, 0)
	assert_eq(t.left_s("life", 0), 5)
	assert_eq(t.left_s("meditate", 0), 10)
	assert_eq(t.left_s("life", 1), 5)

## ClientState 收到角色表時蓋上收件時刻
func test_client_state_stamps_receipt() -> void:
	var old: Dictionary = ClientState.sheet
	var before := Time.get_ticks_msec()
	ClientState._apply_sheet({ "cooldowns": { "life": 2.0 } })
	var rx := int(ClientState.sheet.get("_rx_ms", -1))
	assert_true(rx >= before and rx <= Time.get_ticks_msec(), "rx %d" % rx)
	ClientState.sheet = old

func test_labels_and_keys() -> void:
	assert_eq(CooldownTracker.label("修煉", 7), "修煉（7 秒）")
	assert_eq(CooldownTracker.label("修煉", 0), "修煉")
	assert_eq(CooldownTracker.suffix(7), "（7 秒）")
	assert_eq(CooldownTracker.suffix(0), "")
	assert_eq(CooldownTracker.key_for("meditate"), "meditate")
	assert_eq(CooldownTracker.key_for("work:life_woodcut"), "life")
	assert_eq(CooldownTracker.key_for("work:life_cooking"), "life")
	assert_eq(CooldownTracker.key_for("exert_qi"), "")
	assert_eq(CooldownTracker.key_for("look"), "scout", "查看偵察（主機只在野外給非 0）")

func test_hotbar_label_counts_down_and_returns() -> void:
	var h := Hotbar.new()
	_add(h)
	await tree.process_frame
	h.apply_sheet({ "char_id": "ch_cd", "vitals": { "neili": 30, "neili_max": 50 }, "cooldowns": { "meditate": 7.0, "life": 0.0 } })
	h._update_states()
	var med: HotbarSlot = h.slots[Hotbar.ROW_CMD][0]
	assert_eq(med.text, "修煉（7 秒）")
	assert_eq(med.visible_text(), "修煉（7 秒）", "drawn on the face, not only Button.text")
	assert_eq(med.glyph, "修煉")
	assert_true(med.disabled, "disabled while cooling")
	assert_eq(med.cooldown_text, "（7 秒）")
	assert_false(h.trigger(Hotbar.ROW_CMD, 0), "F1 does nothing while cooling")
	h.apply_sheet({ "char_id": "ch_cd", "vitals": { "neili": 30, "neili_max": 50 }, "cooldowns": { "meditate": 0.0, "life": 0.0 } })
	h._update_states()
	assert_eq(med.text, "修煉")
	assert_eq(med.visible_text(), "修煉")
	assert_false(med.disabled)
	assert_eq(med.cooldown_text, "")
	# 生活技能放在熱鍵列也一樣（所有生活技能共用 life）
	h.set_payload(Hotbar.ROW_CMD, 5, "cmd:work:life_woodcut")
	h.apply_sheet({ "char_id": "ch_cd", "vitals": { "neili": 30, "neili_max": 50 }, "cooldowns": { "meditate": 0.0, "life": 3.0 } })
	h._update_states()
	var wc: HotbarSlot = h.slots[Hotbar.ROW_CMD][5]
	assert_eq(wc.text, "砍柴（3 秒）")
	assert_eq(wc.visible_text(), "砍柴（3 秒）")
	assert_true(wc.disabled)

func test_command_panel_shows_countdown() -> void:
	var p := CommandPanel.new()
	_add(p)
	await tree.process_frame
	p.set_tab("MARTIAL")
	p.apply_sheet({ "vitals": { "neili": 30, "neili_max": 50 }, "cooldowns": { "meditate": 7.0, "life": 0.0 } })
	var b: JyButton = p.buttons["meditate"]
	assert_eq(b.text, "修煉內力（7 秒）")
	assert_eq(b.visible_text(), "修煉（7 秒）", "face: 修煉 / （7 秒）")
	assert_true(b.disabled)
	assert_eq(b.cooldown_text, "（7 秒）")
	p.apply_sheet({ "vitals": { "neili": 30, "neili_max": 50 }, "cooldowns": { "meditate": 0.0, "life": 0.0 } })
	assert_eq(b.text, "修煉內力")
	assert_eq(b.visible_text(), "修煉")
	assert_false(b.disabled)
	p.set_tab("ACTION")
	p.apply_sheet({ "vitals": {}, "cooldowns": { "meditate": 0.0, "life": 2.0 } })
	var w: JyButton = p.buttons["work:life_fishing"]
	assert_eq(w.text, "垂釣（2 秒）")
	assert_true(w.visible_text().ends_with("（2 秒）"), w.visible_text())
	assert_true(w.disabled)

func test_busy_text_falls_back_to_sheet_cooldown() -> void:
	var tpl := { "err_busy": { "self": "【系統】你正忙著，還要 {n} 秒。" } }
	assert_eq(TextRenderer.render_reason("busy", tpl, { "n": 3 }), "【系統】你正忙著，還要 3 秒。")
	assert_eq(TextRenderer.render_reason_inline("busy", tpl, { "n": 3 }), "你正忙著，還要 3 秒。")
