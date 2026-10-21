extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §2.2–§2.4、§2.7（WP-LAW）介面：佈告欄名單視窗（列、表頭、加碼、領賞按鈕只在官爺處）、NPC 選單的
## 佈告欄／官爺頁（領照、領賞、看名單；耳聾官爺回聽錯）、天師的消災視窗（最多次數、價錢、送出）。

var dlg: BountyDialog = null
var npc_dlg: NpcDialog = null
var cl: CleanseDialog = null

func before_each() -> void:
	world_name = "w_ui_m3d_board"
	UiSettings.reset_for_tests(true)
	super.before_each()
	cs.world_info = ws.world_info()
	if host() != null and host().get("law") != null:
		host().law.hunter_chance_pct = 0

func after_each() -> void:
	for n in [dlg, npc_dlg, cl]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	await tree.process_frame
	dlg = null
	npc_dlg = null
	cl = null
	super.after_each()

func _sender(kind: String, args: Dictionary) -> int:
	seq += 1
	ws.handle_intent(1, seq, kind, args)
	ws.flush()
	return seq

func _gate() -> IntentGate:
	var g := IntentGate.new()
	g.set_sender(_sender)
	return g

func _all(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c.is_queued_for_deletion():
			continue
		out.append(c)
		out.append_array(_all(c))
	return out

func _find(root: Node, nm: String) -> Node:
	for c in _all(root):
		if c.name == nm:
			return c
	return null

func _texts(root: Node) -> String:
	var out: PackedStringArray = []
	for c in _all(root):
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append((c as Button).text)
	return "|".join(out)

func _setup_villain() -> int:
	var v: int = add_player("惡人甲")
	var c = session_of(v).character
	c.combat_xp = 5000
	c.pk = 4
	c.pk_stamp_s = c.online_s
	host().law.refresh_board()
	return v

func test_pure_helpers() -> void:
	assert_eq(BountyDialog.money_text(1234567), "1,234,567")
	assert_eq(BountyDialog.money_text(100), "100")
	assert_eq(BountyDialog.row_text({ "name": "甲", "sect_name": "少林派", "pk": 4, "morality": -200, "amount": 4500,
		"listed_text": "第 2 日 午時" }), PackedStringArray(["甲", "少林派", "4", "-200", "4,500", "第 2 日 午時"]))
	assert_eq(BountyDialog.head_text({ "enabled": false }), BountyDialog.OFF_TEXT)
	assert_true(BountyDialog.head_text({ "licensed": true, "claims_total": 300, "refreshed_text": "第 1 日 辰時" }).contains("待領賞金 300 兩"))
	assert_eq(CleanseDialog.max_times(95, 99999), 9)
	assert_eq(CleanseDialog.max_times(500, 250), 2)

func test_board_dialog_rows_add_and_claim() -> void:
	if not game_ok():
		return
	make_char("看榜客")
	_setup_villain()
	goto("xx_square")
	ch().money = 20000
	ok("bounty_board", { "npc": "n_law_board_xx" })
	var p := lastp("bounty_board")
	assert_false(p.is_empty(), "bounty_board event")
	dlg = BountyDialog.new()
	dlg.gate = _gate()
	tree.root.add_child(dlg)
	dlg.add_child(dlg.gate)
	dlg.open_board(p)
	await tree.process_frame
	var t := _texts(dlg)
	assert_true(t.contains("惡人甲"), "row name")
	assert_true(t.contains("4,000"), "amount")
	assert_true(t.contains("無門無派"), "sect")
	assert_true(t.contains("你沒有賞金獵人執照"), "head")
	assert_eq(_find(dlg, "ClaimButton"), null, "no claim at the board (only officers)")
	# 加碼
	var add_b := _find(dlg, "Add_1") as Button
	assert_true(add_b != null, "add button")
	add_b.pressed.emit()
	var le := _find(dlg, "AddMoney") as LineEdit
	le.text = "600"
	(_find(dlg, "AddOk") as Button).pressed.emit()
	await tree.process_frame
	assert_eq(int(ch().money), 19400, "pool added")
	var p2 := lastp("bounty_board")
	dlg.open_board(p2)
	await tree.process_frame
	assert_true(_texts(dlg).contains("4,600"), "amount includes the pool")
	assert_true(dlg.press_number(1), "number key 1 → first 加碼")

func test_officer_menu_license_and_claim_button() -> void:
	if not game_ok():
		return
	make_char("獵人乙")
	_setup_villain()
	goto("xx_square")
	ch().money = 1000
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()
	npc_dlg = NpcDialog.new()
	npc_dlg.gate = _gate()
	tree.root.add_child(npc_dlg)
	npc_dlg.add_child(npc_dlg.gate)
	npc_dlg.open_menu({ "npc": "n_law_guanye_xx_a", "npc_name": "官爺", "services": ["LICENSE"] })
	await tree.process_frame
	(npc_dlg.service_buttons["LICENSE"] as Button).pressed.emit()
	await tree.process_frame
	var get_b := _find(npc_dlg, "LicenseGet") as Button
	assert_true(get_b != null and not get_b.disabled, "領取執照 button")
	get_b.pressed.emit()
	await tree.process_frame
	assert_true(LawSystem.has_license(ch()), "licensed via the menu")
	assert_eq(int(ch().money), 900)
	# 看名單（官爺處）→ 名單視窗有「領賞」鈕（沒有賞金時灰）
	var p := {}
	ok("bounty_board", { "npc": "n_law_guanye_xx_a" })
	p = lastp("bounty_board")
	assert_eq(str(p.get("npc_service", "")), "LICENSE")
	dlg = BountyDialog.new()
	dlg.gate = _gate()
	tree.root.add_child(dlg)
	dlg.add_child(dlg.gate)
	dlg.open_board(p)
	await tree.process_frame
	var cb := _find(dlg, "ClaimButton") as Button
	assert_true(cb != null and cb.disabled, "claim button disabled with no claims")
	host().law.data()["claims"][str(ch().id)] = [{ "target_name": "惡人甲", "amount": 4000, "s": 0.0 }]
	ok("bounty_board", { "npc": "n_law_guanye_xx_a" })
	dlg.open_board(lastp("bounty_board"))
	await tree.process_frame
	cb = _find(dlg, "ClaimButton") as Button
	assert_false(cb.disabled, "claim enabled")
	assert_true(cb.text.contains("4,000"))
	cb.pressed.emit()
	await tree.process_frame
	assert_eq(int(ch().money), 4900, "claimed through the dialog")
	# 耳聾的那位
	npc_dlg.open_menu({ "npc": "n_law_guanye_xx_b", "npc_name": "官爺", "services": ["LICENSE"] })
	(npc_dlg.service_buttons["LICENSE"] as Button).pressed.emit()
	await tree.process_frame
	(_find(npc_dlg, "LicenseBoard") as Button).pressed.emit()
	await tree.process_frame
	assert_true(npc_dlg.status_label.text != "", "deaf officer: error shown")

func test_board_menu_and_locked_ranks() -> void:
	if not game_ok():
		return
	make_char("看榜丙")
	goto("xx_square")
	npc_dlg = NpcDialog.new()
	npc_dlg.gate = _gate()
	tree.root.add_child(npc_dlg)
	npc_dlg.add_child(npc_dlg.gate)
	npc_dlg.open_menu({ "npc": "n_law_board_xx", "npc_name": "佈告欄", "services": ["BOARD"] })
	(npc_dlg.service_buttons["BOARD"] as Button).pressed.emit()
	await tree.process_frame
	var t := _texts(npc_dlg)
	assert_true(t.contains(UiKeys.BOARD_MENU_BOUNTY), "觀看懸賞名單")
	assert_true(t.contains("尚未開放"), "other ranks locked")
	(_find(npc_dlg, "BoardBounty") as Button).pressed.emit()
	await tree.process_frame
	assert_false(lastp("bounty_board").is_empty(), "board requested")

func test_cleanse_dialog() -> void:
	if not game_ok():
		return
	make_char("殺星丁")
	goto("xw_road")
	ch().killing_intent = 95
	ch().money = 5000
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()
	cl = CleanseDialog.new()
	cl.gate = _gate()
	tree.root.add_child(cl)
	cl.add_child(cl.gate)
	cl.open_for({ "npc": "n_law_tianshi_xx", "npc_name": "天師" }, "KILLING")
	await tree.process_frame
	assert_true(cl.info_label.text.contains("最多可以化解 9 次"), cl.info_label.text)
	assert_eq(int(cl.times_box.max_value), 9)
	cl.times_box.value = 9
	assert_true(cl.cost_label.text.contains("900"))
	cl.ok_button.pressed.emit()
	await tree.process_frame
	assert_eq(int(ch().killing_intent), 5)
	assert_eq(int(ch().money), 4100)
	assert_false(cl.visible, "closes after success")

## M3d 審查：消災按鈕灰掉要寫原因；空名單收起捲動框
func test_review_reasons_and_empty_board() -> void:
	assert_eq(CleanseDialog.block_reason("PK", { "pk": 0, "money": 99999 }), "你身上沒有 PK值，不必消。")
	assert_true(CleanseDialog.block_reason("PK", { "pk": 2, "money": 10 }).contains("銀兩不夠"))
	assert_eq(CleanseDialog.block_reason("PK", { "pk": 2, "money": 10000 }), "")
	assert_true(CleanseDialog.block_reason("KILLING", { "killing_intent": 5, "money": 9999 }).contains("殺氣不到"))
	assert_true(CleanseDialog.block_reason("KILLING", { "killing_intent": 50, "money": 50 }).contains("銀兩不夠"))
	assert_eq(CleanseDialog.block_reason("KILLING", { "killing_intent": 50, "money": 500 }), "")
	dlg = BountyDialog.new()
	dlg.gate = _gate()
	tree.root.add_child(dlg)
	dlg.add_child(dlg.gate)
	dlg.open_board({ "rows": [], "enabled": true, "refreshed_text": "第 1 日 午時", "npc_service": "BOARD" })
	await tree.process_frame
	var sc := _find(dlg, "BoardScroll") as Control
	assert_true(sc != null and not sc.visible, "空名單：捲動框收起")
	assert_true(_texts(dlg).contains(BountyDialog.EMPTY_TEXT))
	dlg.open_board({ "rows": [{ "name": "惡甲", "sect_name": "無門無派", "pk": 4, "morality": 0, "amount": 4000, "listed_text": "第 1 日" }],
		"enabled": true, "npc_service": "BOARD" })
	await tree.process_frame
	assert_true(sc.visible, "有人：捲動框顯示")

## M3d 審查（第 3 輪）：自己那一列的「加碼」灰掉（不能替自己加碼）；名單框跟著列數、表頭不在捲動框裡；
## 官爺的「領取執照」在 PK值、上榜、錢不夠時灰掉並寫原因
func test_review3_board_self_row_height_and_license_reasons() -> void:
	if not game_ok():
		return
	make_char("看榜戊")
	dlg = BountyDialog.new()
	dlg.gate = _gate()
	tree.root.add_child(dlg)
	dlg.add_child(dlg.gate)
	var rows := [{ "name": "看榜戊", "sect_name": "無門無派", "pk": 4, "morality": 0, "amount": 4000, "listed_text": "第 1 日", "self": true },
		{ "name": "惡乙", "sect_name": "無門無派", "pk": 5, "morality": 0, "amount": 5000, "listed_text": "第 1 日" }]
	dlg.open_board({ "rows": rows, "enabled": true, "npc_service": "BOARD" })
	await tree.process_frame
	var a1 := _find(dlg, "Add_1") as Button
	var a2 := _find(dlg, "Add_2") as Button
	assert_true(a1.disabled and a1.tooltip_text == BountyDialog.SELF_ADD_TIP, "自己那一列灰掉＋提示")
	assert_false(a2.disabled, "別人那一列可以加碼")
	assert_true(dlg.press_number(1), "數字鍵 1 → 第一顆可按的（別人那列）")
	var sc := _find(dlg, "BoardScroll") as Control
	assert_true(sc.custom_minimum_size.y <= BountyDialog.board_height(2) + 0.5, "兩列：框的高度跟著列數")
	assert_true(BountyDialog.board_height(1) < 60.0 and BountyDialog.board_height(50) == BountyDialog.SCROLL_MAX_H)
	var hd := _find(dlg, "BoardHeader") as Control
	assert_true(hd != null and hd.visible and not sc.is_ancestor_of(hd), "表頭在捲動框外面")
	assert_eq(NpcDialog.license_block({ "pk": 0, "money": 500, "law": {} }, false), "")
	assert_eq(NpcDialog.license_block({ "pk": 0, "money": 500 }, true), "你已經有執照了")
	assert_true(NpcDialog.license_block({ "pk": 2, "money": 500 }, false).contains("PK值"))
	assert_true(NpcDialog.license_block({ "pk": 0, "money": 500, "law": { "listed": true } }, false).contains("名單"))
	assert_true(NpcDialog.license_block({ "pk": 0, "money": 50 }, false).contains("銀兩"))
	# 主機帶出 self
	_setup_villain()
	goto("xx_square")
	ok("bounty_board", { "npc": "n_law_board_xx" })
	for r in lastp("bounty_board").get("rows", []):
		assert_false(bool(r.get("self", true)), "別人的列 self = false")

## M3d 審查第三輪：灰掉的按鈕原因直接寫在畫面上（不只滑鼠提示）——自己那列的加碼、名單底下與官爺頁的「領賞（0 兩）」
func test_review3_visible_reasons() -> void:
	if not game_ok():
		return
	make_char("看榜己")
	dlg = BountyDialog.new()
	dlg.gate = _gate()
	tree.root.add_child(dlg)
	dlg.add_child(dlg.gate)
	var rows := [{ "name": "看榜己", "sect_name": "無門無派", "pk": 4, "morality": 0, "amount": 4000, "listed_text": "第 1 日", "self": true }]
	dlg.open_board({ "rows": rows, "enabled": true, "npc_service": "LICENSE", "claims_total": 0 })
	await tree.process_frame
	var a1 := _find(dlg, "Add_1") as Button
	assert_eq(a1.text, BountyDialog.SELF_ADD_TEXT, "自己那列的鈕寫「自己」")
	var why := _find(dlg, "SelfAddWhy") as Label
	assert_true(why != null and why.visible and why.text.contains(BountyDialog.SELF_ADD_TIP), "名單下方寫出不能替自己加碼")
	var cw := _find(dlg, "ClaimWhy") as Label
	assert_true(cw != null and cw.text == BountyDialog.NO_CLAIM_TIP, "領賞灰掉 → 旁邊寫原因")
	# 官爺頁
	var nd := NpcDialog.new()
	nd.gate = _gate()
	tree.root.add_child(nd)
	nd.add_child(nd.gate)
	nd.ensure_built()
	nd.show_license()
	await tree.process_frame
	var lw := _find(nd, "LicenseClaimWhy") as Label
	assert_true(lw != null and lw.text == BountyDialog.NO_CLAIM_TIP, "官爺頁：領賞灰掉 → 寫原因")
	nd.queue_free()
