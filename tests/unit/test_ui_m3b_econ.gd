extends "res://tests/test_case.gd"
## WP-UI（M3B_PLAN §11.1 test_ui_m3b_econ）：錢莊窗、鏢局窗、製作窗——建窗、餵假資料、按鈕送出的 intent 形狀。
## 全部用假資料（資料列暫時放進 GameData，after_each 還原），不碰主機與存檔。

var _nodes: Array = []
var _old_sheet: Dictionary = {}
var _old_wi: Dictionary = {}
var _old_view: Dictionary = {}
var _patched: Dictionary = {}     # table -> { id: 原本的列或 null }

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	_old_sheet = ClientState.sheet
	_old_wi = ClientState.world_info
	_old_view = ClientState.region_view

func after_each() -> void:
	ClientState.sheet = _old_sheet
	ClientState.world_info = _old_wi
	ClientState.region_view = _old_view
	for t in _patched:
		var tbl: Dictionary = GameData.tables.get(t, {})
		for id in _patched[t]:
			if _patched[t][id] == null:
				tbl.erase(id)
			else:
				tbl[id] = _patched[t][id]
	_patched.clear()
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _frame() -> void:
	await tree.process_frame

func _put(table: String, id: String, row: Dictionary) -> void:
	if not GameData.tables.has(table):
		GameData.tables[table] = {}
	var tbl: Dictionary = GameData.tables[table]
	if not _patched.has(table):
		_patched[table] = {}
	if not _patched[table].has(id):
		_patched[table][id] = tbl.get(id, null)
	tbl[id] = row

func _gate(sent: Array, ok := true, reason := "") -> IntentGate:
	var g := IntentGate.new()
	_add(g)
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		var seq := sent.size()
		g.resolve.call_deferred(seq, ok, reason)
		return seq)
	return g

func _items() -> void:
	_put("items", "t_ec_sword", { "id": "t_ec_sword", "name": "測試劍", "weight": 3 })
	_put("items", "t_ec_ore", { "id": "t_ec_ore", "name": "測試礦", "weight": 2, "tab": "MATERIAL" })
	_put("items", "t_ec_letter", { "id": "t_ec_letter", "name": "密函", "weight": 0, "quest_item": true })
	_put("items", "t_ec_pick", { "id": "t_ec_pick", "name": "測試鎬", "weight": 4, "tool": true })
	_put("items", "t_ec_ingot", { "id": "t_ec_ingot", "name": "測試鐵塊", "weight": 2 })
	_put("items", "t_ec_coal", { "id": "t_ec_coal", "name": "測試木炭", "weight": 1 })
	_put("items", "t_ec_blade", { "id": "t_ec_blade", "name": "測試刀", "weight": 3 })

static func ec_sheet() -> Dictionary:
	return { "char_id": "ch_me", "name": "我", "money": 1000, "carry": 10, "carry_max": 200, "sect": "",
		"vitals": { "jing": 100, "jing_max": 100 },
		"skills": [ { "id": "t_life_smith", "name": "測試打鐵", "kind": "LIFE", "level": 5 },
			{ "id": "t_life_mine", "name": "測試挖礦", "kind": "LIFE", "level": 1 } ],
		"inventory": [
			{ "uid": "u1", "id": "t_ec_sword", "name": "測試劍", "n": 1, "weight": 3, "equipped_slot": "WEAPON" },
			{ "uid": "u2", "id": "t_ec_ore", "name": "測試礦", "n": 5, "weight": 2, "equipped_slot": "" },
			{ "uid": "u3", "id": "t_ec_letter", "name": "密函", "n": 1, "weight": 0, "equipped_slot": "" },
			{ "uid": "u4", "id": "t_ec_ingot", "name": "測試鐵塊", "n": 2, "weight": 2, "equipped_slot": "" } ] }

# ---------------------------------------------------------------- 錢莊

func test_bank_window_lists_and_sends_put_take_money() -> void:
	_items()
	var sent: Array = []
	var w := BankWindow.new()
	w.gate = _gate(sent)
	_add(w)
	await _frame()
	w.apply_sheet(ec_sheet())
	w.open_view({ "money": 500, "used": 3, "capacity": 1000, "money_cap": 6000000,
		"items": [ { "uid": "b1", "item_id": "t_ec_ore", "name": "測試礦", "n": 3, "weight": 2 } ] }, "n_t_banker")
	assert_true(w.visible)
	assert_eq(w.bank_money_label.text, "錢莊存款：500 兩")
	assert_eq(w.carry_money_label.text, "身上銀兩：1000 兩")
	assert_eq(w.used_label.text, "已用 3／1000 件")
	var ore := w.find_child("CARRY_u2", true, false) as Button
	assert_true(ore != null and ore.text.contains("測試礦 ×5") and ore.text.contains("重 10"), "身上欄：名稱、數量、重量")
	var bank_ore := w.find_child("BANK_b1", true, false) as Button
	assert_true(bank_ore != null and bank_ore.text.contains("×3"), "錢莊欄")
	# 裝備中、任務物品：標明不能存，選了「存入」也灰
	var sword := w.find_child("CARRY_u1", true, false) as Button
	assert_true(sword.text.contains("裝備中"), sword.text)
	w.select(BankWindow.SIDE_CARRY, "u1")
	assert_true(w.btn_put.disabled, "裝備中不能存")
	w.select(BankWindow.SIDE_CARRY, "u3")
	assert_true(w.btn_put.disabled, "任務物品不能存")
	assert_eq(EconUi.not_storable_reason({ "id": "t_ec_letter" }), "not_bankable")
	# 部分存入：選礦、數量 2
	w.select(BankWindow.SIDE_CARRY, "u2")
	assert_eq(int(w.n_spin.max_value), 5, "數量上限＝整堆")
	assert_eq(int(w.n_spin.value), 5, "預設整堆")
	w.n_spin.value = 2
	assert_false(w.btn_put.disabled)
	w.btn_put.pressed.emit()
	assert_eq(sent[0], ["bank_put", { "npc": "n_t_banker", "uid": "u2", "n": 2 }])
	await _frame()
	# 取出
	w.select(BankWindow.SIDE_BANK, "b1")
	w.n_spin.value = 1
	w.btn_take.pressed.emit()
	assert_eq(sent[1], ["bank_take", { "npc": "n_t_banker", "uid": "b1", "n": 1 }])
	await _frame()
	# 存錢、領錢
	w.money_edit.text = "300"
	w.btn_deposit.pressed.emit()
	assert_eq(sent[2], ["bank_money", { "npc": "n_t_banker", "amount": 300 }])
	await _frame()
	await _frame()
	assert_eq(w.money_edit.text, "", "成功後清空")
	w.money_edit.text = "200"
	w.btn_withdraw.pressed.emit()
	assert_eq(sent[3], ["bank_money", { "npc": "n_t_banker", "amount": -200 }])
	await _frame()
	# 本機就知道不行：不送、寫原因
	var n := sent.size()
	w.money_edit.text = "999999"
	w.btn_deposit.pressed.emit()
	assert_eq(sent.size(), n, "身上不夠不送")
	assert_true(w.status_label.text.contains("不夠"), w.status_label.text)
	w.money_edit.text = "600"
	w.btn_withdraw.pressed.emit()
	assert_eq(sent.size(), n, "存款不夠不送")
	# 錢莊滿了：存入灰掉
	w.open_view({ "money": 0, "used": 1000, "capacity": 1000, "items": [] }, "n_t_banker")
	w.select(BankWindow.SIDE_CARRY, "u2")
	assert_true(w.btn_put.disabled, "bank_full")
	assert_true(w.pick_label.text.contains("放滿"), w.pick_label.text)
	# 數字鍵：選身上第 2 列
	w.set_side(BankWindow.SIDE_CARRY)
	assert_true(w.press_number(2))
	assert_eq(str(w.selected[BankWindow.SIDE_CARRY]), "u2")
	# M3b 審查 4：錢莊那一欄空了（取出最後一件）→ 數字鍵換到身上那一欄，不會兩欄都沒有編號
	w.set_side(BankWindow.SIDE_BANK)
	assert_eq(w.side, BankWindow.SIDE_CARRY, "空的錢莊欄 → 換到身上欄")
	assert_true(w.press_number(1), "數字鍵選得到東西")

func test_bank_view_defaults_and_money_rules() -> void:
	var v := EconUi.bank_view({ "items": [ { "uid": "a", "n": 4 }, { "uid": "b" } ] })
	assert_eq(v["used"], 5, "沒給 used：依件數合計")
	assert_eq(v["capacity"], 1000)
	assert_eq(v["money_cap"], 6000000)
	assert_eq(EconUi.money_block(100, 50, v), "not_enough_money")
	assert_eq(EconUi.money_block(100, 500, { "money": 5999950, "money_cap": 6000000 }), "bank_money_cap")
	assert_eq(EconUi.money_block(-100, 0, { "money": 50 }), "not_enough_bank_money")
	assert_eq(EconUi.money_block(-100, 5999950, { "money": 500 }), "money_cap")
	assert_eq(EconUi.money_block(100, 500, v), "")

func test_main_screen_opens_bank_on_bank_view() -> void:
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.handle_event({ "ch": "SYSTEM", "key": "npc_menu", "ui": true,
		"p": { "npc": "n_t_banker", "npc_name": "錢莊老闆", "services": ["BANK"], "bank": true } })
	assert_true(main.npc_dialog.visible)
	assert_eq((main.npc_dialog.service_buttons["BANK"] as Button).text, "錢莊")
	main.handle_event({ "ch": "SYSTEM", "key": "bank_view", "ui": true, "p": { "money": 7, "items": [], "used": 0, "capacity": 1000 } })
	assert_true(main.bank_window.visible)
	assert_false(main.npc_dialog.visible, "對話框互斥")
	assert_eq(main.bank_window.npc_id(), "n_t_banker", "沒帶 npc：用剛才的 NPC")
	assert_true(main._close_dialogs(), "Esc 關得掉")
	assert_false(main.bank_window.visible)

func test_npc_bank_service_sends_bank_open() -> void:
	var sent: Array = []
	var d := NpcDialog.new()
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	d.open_menu({ "npc": "n_t_banker", "npc_name": "錢莊老闆", "services": ["BANK"] })
	(d.service_buttons["BANK"] as Button).pressed.emit()
	assert_eq(sent, [["bank_open", { "npc": "n_t_banker" }]])

# ---------------------------------------------------------------- 鏢局

static func escort_menu() -> Dictionary:
	return { "npc": "n_t_biaotou", "npc_name": "鏢頭", "services": ["ESCORT", "QUEST"],
		"escort": { "city": "xixia", "city_name": "西夏", "ready": 1,
			"routes": [ { "city": "dali", "city_name": "大理", "delay_text": "約 4 時辰" },
				{ "city": "jingcheng", "city_name": "京城", "delay_text": "約 3 時辰" } ] },
		"quests": [ { "id": "q_t_biao", "name": "保鏢：西夏往大理", "state": "AVAILABLE" },
			{ "id": "q_t_biao2", "name": "保鏢：西夏往京城", "state": "READY" } ] }

func test_escort_send_tab_fee_and_intent() -> void:
	_items()
	var sent: Array = []
	var w := EscortWindow.new()
	w.gate = _gate(sent)
	_add(w)
	await _frame()
	w.apply_sheet(ec_sheet())
	w.open_menu(escort_menu())
	assert_true(w.visible)
	assert_true(w.title_label.text.contains("西夏"), w.title_label.text)
	assert_eq(w.city_opt.item_count, 2)
	assert_eq(w.city_opt.get_item_text(0), "大理（約 4 時辰）", "目的城附送達時間")
	assert_true((w.find_child("Pick_u1", true, false) as CheckBox).disabled, "裝備中不能寄")
	assert_true((w.find_child("Pick_u3", true, false) as CheckBox).disabled, "任務物品不能寄")
	assert_true(w.send_button.disabled, "還沒填收件人")
	# 選礦 ×2（每件重 2）→ 運費 20 + 2×4 = 28
	var cb := w.find_child("Pick_u2", true, false) as CheckBox
	var sp := w.find_child("PickN_u2", true, false) as SpinBox
	cb.button_pressed = true
	sp.value = 2
	assert_eq(w.current_fee(), 28)
	assert_true(w.fee_label.text.begins_with("運費：28 兩"), w.fee_label.text)
	w.to_edit.text = "天天"
	w.to_edit.text_changed.emit(w.to_edit.text)
	w.money_edit.text = "50"
	w.money_edit.text_changed.emit(w.money_edit.text)
	w.city_opt.select(1)
	w.city_opt.item_selected.emit(1)
	assert_false(w.send_button.disabled, w.send_button.tooltip_text)
	# M3b 審查：運費與托鏢鈕在捲動區外（footer）；勾選框用深色字
	assert_true(w.footer.is_ancestor_of(w.send_button) and w.footer.is_ancestor_of(w.fee_label), "托鏢鈕、運費在 footer")
	assert_false(w.page.is_ancestor_of(w.send_button), "不在捲動的物品清單裡")
	for pb in w.pick_boxes.values():
		assert_eq((pb as CheckBox).get_theme_color("font_color"), UiTheme.JY_BTN_TEXT, "勾選框深色字")
	w.send_button.pressed.emit()
	assert_eq(sent, [["consign_send", { "npc": "n_t_biaotou", "to": "天天", "city": "jingcheng",
		"items": [ { "uid": "u2", "n": 2 } ], "money": 50 }]])
	await _frame()
	await _frame()
	assert_true(w.picks.is_empty(), "成功後清掉勾選")
	# 本機檢查：寄給自己、錢不夠
	assert_eq(EconUi.send_block("我", "dali", [ { "uid": "x", "n": 1 } ], 0, 20, ec_sheet()), "self_target")
	assert_eq(EconUi.send_block("天天", "dali", [], 0, 20, ec_sheet()), "nothing_to_send")
	assert_eq(EconUi.send_block("天天", "dali", [], 990, 20, ec_sheet()), "not_enough_money")
	assert_eq(EconUi.consign_fee(0, 20, 2), 20)
	# 主機給的運費參數優先
	assert_eq(EconUi.fee_params({ "escort": { "fee_base": 30, "fee_per_weight": 5 } }), Vector2i(30, 5))

func test_escort_take_tab_lists_and_takes() -> void:
	var sent: Array = []
	var w := EscortWindow.new()
	w.gate = _gate(sent)
	_add(w)
	await _frame()
	ClientState.sheet = { "char_id": "ch_me", "name": "我" }
	w.apply_sheet(ClientState.sheet)
	w.open_menu(escort_menu())
	(w.tab_buttons[EscortWindow.TAB_TAKE] as Button).pressed.emit()
	assert_eq(sent[0], ["consign_list", { "npc": "n_t_biaotou" }], "切到取貨就查")
	await _frame()
	w.apply_list({ "rows": [
		{ "id": "c1", "from_char": "ch_x", "from_name": "天天", "to_char": "ch_me", "to_name": "我", "status": "READY",
			"items": [ { "item_id": "t_ec_ore", "name": "測試礦", "n": 3 } ], "money": 200 },
		{ "id": "c2", "from_char": "ch_me", "from_name": "我", "to_char": "ch_y", "to_name": "阿乙", "to_city": "dali",
			"to_city_name": "大理", "status": "TRANSIT", "items": [], "money": 10, "left_s": 600 } ] })
	var b := w.find_child("Take_c1", true, false) as Button
	assert_true(b != null, "到站的可領")
	assert_true(w.find_child("Take_c2", true, false) == null, "路上的不能領")
	var txt := ""
	for l in w.page.find_children("*", "Label", true, false):
		txt += (l as Label).text + "\n"
	assert_true(txt.contains("天天寄來：測試礦 ×3、200 兩（已到站）"), txt)
	assert_true(txt.contains("寄給阿乙（往大理）") and txt.contains("運送中"), txt)
	assert_true(w.press_number(1), "數字鍵 1 ＝ 第一個領取")
	assert_eq(sent[1], ["consign_take", { "npc": "n_t_biaotou", "id": "c1" }])

func test_escort_job_tab_uses_quest_menu() -> void:
	var sent: Array = []
	var w := EscortWindow.new()
	w.gate = _gate(sent)
	_add(w)
	await _frame()
	_put("sects", "t_gb", { "id": "t_gb", "name": "丐幫", "no_escort": true })
	w.apply_sheet({ "char_id": "ch_me", "sect": "t_gb" })
	w.open_menu(escort_menu(), EscortWindow.TAB_JOB)
	var acc := w.find_child("JobAccept_q_t_biao", true, false) as Button
	assert_true(acc != null)
	acc.pressed.emit()
	assert_eq(sent[0], ["quest_accept", { "npc": "n_t_biaotou", "quest": "q_t_biao" }])
	await _frame()
	(w.find_child("JobTurnIn_q_t_biao2", true, false) as Button).pressed.emit()
	assert_eq(sent[1], ["quest_turn_in", { "npc": "n_t_biaotou", "quest": "q_t_biao2" }])
	var txt := ""
	for l in w.page.find_children("*", "Label", true, false):
		txt += (l as Label).text
	assert_true(txt.contains("丐幫弟子不能接保鏢工作"), txt)

func test_main_screen_escort_and_consign_list_routing() -> void:
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.handle_event({ "ch": "SYSTEM", "key": "npc_menu", "ui": true, "p": escort_menu() })
	(main.npc_dialog.service_buttons["ESCORT"] as Button).pressed.emit()
	assert_true(main.escort_window.visible)
	assert_false(main.npc_dialog.visible)
	main.escort_window.set_tab(EscortWindow.TAB_TAKE)
	main.handle_event({ "ch": "SYSTEM", "key": "consign_list", "ui": true, "p": { "rows": [] } })
	assert_true(main.escort_window.list_loaded)
	# NPC 不在房間了 → 關掉
	main.apply_view({ "room": "r_x", "room_name": "別處", "exits": [], "npcs": [], "features": [] })
	assert_false(main.escort_window.visible)

# ---------------------------------------------------------------- 製作窗

func _life() -> void:
	_put("life_skills", "t_life_mine", { "id": "t_life_mine", "name": "測試挖礦", "mode": "GATHER", "feature": "MINE",
		"tool": "t_ec_pick", "verb": "挖礦", "jing_cost": 5, "yield": [ { "item": "t_ec_ore", "chance": 1.0, "n": [1, 1] } ], "recipes": [] })
	_put("life_skills", "t_life_smith", { "id": "t_life_smith", "name": "測試打鐵", "mode": "CRAFT", "feature": "FORGE",
		"tool": "", "jing_cost": 5, "yield": [], "recipes": [
			{ "id": "t_rc_ingot", "name": "煉鐵塊", "inputs": [ { "item": "t_ec_ore", "n": 3 } ], "output": { "item": "t_ec_ingot", "n": 1 }, "min_level": 1 },
			{ "id": "t_rc_blade", "name": "打刀", "inputs": [ { "item": "t_ec_ingot", "n": 2 }, { "item": "t_ec_coal", "n": 1 } ],
				"output": { "item": "t_ec_blade", "n": 1 }, "min_level": 1 },
			{ "id": "t_rc_high", "name": "高級貨", "inputs": [ { "item": "t_ec_ore", "n": 1 } ], "output": { "item": "t_ec_blade", "n": 1 }, "min_level": 20 },
			{ "id": "t_rc_tool", "name": "要鎬的", "tools": ["t_ec_pick"], "inputs": [ { "item": "t_ec_ore", "n": 1 } ],
				"output": { "item": "t_ec_ingot", "n": 2 }, "min_level": 1 },
			{ "id": "t_rc_kiln", "name": "別處做的", "feature": "KILN", "inputs": [], "output": { "item": "t_ec_coal", "n": 1 }, "min_level": 1 } ] })
	_put("life_skills", "t_life_sew", { "id": "t_life_sew", "name": "測試裁縫", "mode": "CRAFT", "feature": "", "tool": "", "jing_cost": 5,
		"yield": [], "recipes": [ { "id": "t_rc_cloth", "name": "縫衣", "inputs": [ { "item": "t_ec_ore", "n": 1 } ], "output": { "item": "t_ec_blade", "n": 1 }, "min_level": 1 } ] })

func test_craft_entries_states_and_reasons() -> void:
	_items()
	_life()
	var skills := { "t_life_mine": UiClient.row("life_skills", "t_life_mine"), "t_life_smith": UiClient.row("life_skills", "t_life_smith"),
		"t_life_sew": UiClient.row("life_skills", "t_life_sew") }
	var es := EconUi.craft_entries({ "features": ["FORGE"] }, ec_sheet(), skills)
	assert_eq(es.size(), 1, "打鐵爐：只有打鐵（隨地的裁縫沒學，不列）")
	var rs: Array = es[0]["recipes"]
	var by := {}
	for r in rs:
		by[r["id"]] = r
	assert_false(by.has("t_rc_kiln"), "配方 feature 覆寫：燒炭爐的配方不在打鐵爐列")
	assert_true(by["t_rc_ingot"]["ok"], "礦 5 個夠 3 個")
	assert_eq(by["t_rc_blade"]["why"], "缺：測試木炭×1")
	assert_eq(by["t_rc_high"]["why"], "需 20 級")
	assert_eq(by["t_rc_tool"]["why"], "缺工具：測試鎬")
	assert_eq(by["t_rc_ingot"]["inputs"], "測試礦×3")
	assert_eq(by["t_rc_ingot"]["output"], "測試鐵塊")
	# 礦場：挖礦缺工具；有了鎬就能挖
	es = EconUi.craft_entries({ "features": ["MINE"] }, ec_sheet(), skills)
	assert_eq(es.size(), 1)
	assert_eq(es[0]["gather"]["why"], "缺工具：測試鎬")
	var s2 := ec_sheet()
	(s2["inventory"] as Array).append({ "uid": "u9", "id": "t_ec_pick", "name": "測試鎬", "n": 1, "weight": 4, "equipped_slot": "" })
	es = EconUi.craft_entries({ "features": ["MINE"] }, s2, skills)
	assert_true(es[0]["gather"]["ok"])
	# 學了裁縫：隨地可做
	(s2["skills"] as Array).append({ "id": "t_life_sew", "name": "測試裁縫", "kind": "LIFE", "level": 1 })
	es = EconUi.craft_entries({ "features": [] }, s2, skills)
	assert_eq(es.map(func(e): return e["id"]), ["t_life_sew"])
	# 精不足
	s2["vitals"] = { "jing": 1, "jing_max": 100 }
	es = EconUi.craft_entries({ "features": [] }, s2, skills)
	assert_true(str(es[0]["recipes"][0]["why"]).begins_with("精不足"), str(es[0]["recipes"][0]["why"]))
	# 沒學會但這裡有設施：列出、灰掉
	es = EconUi.craft_entries({ "features": ["MINE"] }, { "skills": [], "inventory": [] }, skills)
	assert_eq(es[0]["gather"]["why"], "還沒學會測試挖礦")
	assert_eq(EconUi.work_args("life_mining", ""), { "skill": "life_mining" })
	assert_eq(EconUi.work_args("life_smithing", "rc_x"), { "skill": "life_smithing", "recipe": "rc_x" })

func test_craft_window_buttons_send_work() -> void:
	_items()
	_life()
	var sent: Array = []
	var w := CraftWindow.new()
	w.gate = _gate(sent)
	_add(w)
	await _frame()
	w.open_craft({ "room": "r_forge", "room_name": "打鐵舖", "features": ["FORGE"] }, ec_sheet())
	assert_true(w.room_label.text.contains("打鐵爐"), w.room_label.text)
	var ok := w.find_child("Recipe_t_rc_ingot", true, false) as Button
	assert_false(ok.disabled)
	var bad := w.find_child("Recipe_t_rc_blade", true, false) as Button
	assert_true(bad.disabled)
	var why := w.find_child("Why_t_rc_blade", true, false) as Label
	assert_true(why != null and why.text.contains("測試木炭"), "缺什麼寫出來")
	assert_true((w.find_child("Why_t_rc_high", true, false) as Label).text.contains("需 20 級"))
	ok.pressed.emit()
	assert_eq(sent, [["work", { "skill": "t_life_smith", "recipe": "t_rc_ingot" }]])
	await _frame()
	# 數字鍵 1 ＝ 第一個可做的
	assert_true(w.press_number(1))
	assert_eq(sent[1], ["work", { "skill": "t_life_smith", "recipe": "t_rc_ingot" }])
	await _frame()
	# 採集鈕直接送 work { skill }
	var s2 := ec_sheet()
	(s2["inventory"] as Array).append({ "uid": "u9", "id": "t_ec_pick", "name": "測試鎬", "n": 1, "weight": 4, "equipped_slot": "" })
	w.open_craft({ "room": "r_mine", "room_name": "礦場", "features": ["MINE"] }, s2)
	(w.find_child("Gather_t_life_mine", true, false) as Button).pressed.emit()
	assert_eq(sent[2], ["work", { "skill": "t_life_mine" }])
	await _frame()
	# 冷卻中：全部灰掉並顯示秒數
	s2["cooldowns"] = { "life": 4.0 }
	s2["_rx_ms"] = Time.get_ticks_msec()
	w.apply_sheet(s2)
	var g := w.find_child("Gather_t_life_mine", true, false) as Button
	assert_true(g.disabled, "冷卻中灰掉")
	assert_true(g.text.contains("秒"), g.text)

func test_scene_craft_button_and_main_opens_craft() -> void:
	_items()
	_life()
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.apply_sheet(ec_sheet())
	main.apply_view({ "room": "r_forge", "room_name": "打鐵舖", "region_name": "西夏", "exits": [], "npcs": [], "features": ["FORGE"] })
	var cb: Button = main.scene_panel.craft_button
	assert_true(cb != null, "有打鐵爐：動作列有「製作」")
	cb.pressed.emit()
	assert_true(main.craft_window.visible)
	main.apply_view({ "room": "r_street", "room_name": "大街", "region_name": "西夏", "exits": [], "npcs": [], "features": [] })
	assert_true(main.scene_panel.craft_button == null, "沒有設施、也沒有隨地配方：沒有「製作」")
	# 礦場：場景直接有「挖礦」鈕（FEATURE_LIFE）
	assert_eq(UiKeys.FEATURE_LIFE.get("MINE"), "life_mining")
	assert_eq(UiKeys.FEATURE_LIFE.get("HUNT"), "life_hunting")
	# 指令窗「製作」
	main.run_command(Hotbar.CMD_PREFIX + "craft")
	assert_true(main.craft_window.visible)

# ---------------------------------------------------------------- 商店拒賣（§5.1.6）

func test_shop_refused_greys_buying() -> void:
	var d := ShopDialog.new()
	_add(d)
	await _frame()
	d.open_shop({ "npc": "n_t_smith", "npc_name": "鐵匠", "items": [ { "id": "t_ec_sword", "name": "測試劍", "price": 10 } ],
		"sellable": [], "refused": true, "refuse_text": "我們不賣東西給叫化子。" })
	assert_true(d.is_refused())
	var any_enabled := false
	for c in d.shop_grid.get_children():
		if c is BaseButton and not (c as BaseButton).disabled and (c as JyButton).glyph != "":
			any_enabled = true
	assert_false(any_enabled, "拒賣：貨品灰掉")
	assert_eq(d.hint_label.text, "我們不賣東西給叫化子。")
	d.open_shop({ "npc": "n_t_smith", "npc_name": "鐵匠", "items": [ { "id": "t_ec_sword", "name": "測試劍", "price": 10 } ], "sellable": [] })
	assert_false(d.is_refused())
