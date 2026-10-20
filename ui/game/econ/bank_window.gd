class_name BankWindow
extends NumberedDialog
## 錢莊窗（M3B_PLAN §7.1、§5.2.1）：npc_menu「錢莊」→ bank_open { npc }，主機回 bank_view（ui）時打開／更新。
## - 上方：錢莊存款、身上銀兩、銀兩數目輸入、「存錢」→ bank_money { npc, amount > 0 }、「領錢」→ amount < 0；
## - 中間：左「身上」、右「錢莊」兩欄清單（名稱、數量、重量），中間「存入 →」「← 取出」與數量輸入：
##   bank_put { npc, uid, n }、bank_take { npc, uid, n }（堆疊可部分存取）；
## - 底部「已用 n／1000 件」。裝備中、任務物品、錢莊放滿等本機就知道不行的灰掉並寫原因（主機仍是判定者）。
## 數字鍵 1–9：選目前那一欄的第 n 列（最後點過的欄；預設「身上」）。三城共用一個帳戶（O15），標題寫明。

const SIDE_CARRY := "CARRY"
const SIDE_BANK := "BANK"
const LIST_H := 220.0

var npc := ""
var view: Dictionary = {}           # EconUi.bank_view 之後的形狀
var sheet: Dictionary = {}
var bank_money_label: Label
var carry_money_label: Label
var money_edit: LineEdit
var btn_deposit: Button
var btn_withdraw: Button
var carry_list: VBoxContainer
var bank_list: VBoxContainer
var n_spin: SpinBox
var btn_put: Button
var btn_take: Button
var pick_label: Label
var used_label: Label
var side := SIDE_CARRY
var selected := { SIDE_CARRY: "", SIDE_BANK: "" }    # side -> uid
var row_buttons := { SIDE_CARRY: {}, SIDE_BANK: {} }  # side -> { uid: Button }

func dialog_size() -> Vector2:
	return Vector2(760, 440)

func _build_body() -> void:
	title_label.text = "錢莊"
	var top := UiBuild.hbox(body, 10)
	bank_money_label = UiBuild.label(top, "", 16)
	bank_money_label.name = "BankMoney"
	carry_money_label = UiBuild.label(top, "", 16)
	carry_money_label.name = "CarryMoney"
	carry_money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money_edit = UiBuild.line_edit(top, "", "銀兩", 8)
	money_edit.name = "MoneyEdit"
	money_edit.custom_minimum_size = Vector2(110, 0)
	money_edit.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn_deposit = UiBuild.button(top, "存錢", func(): send_money(true))
	btn_deposit.name = "Deposit"
	btn_withdraw = UiBuild.button(top, "領錢", func(): send_money(false))
	btn_withdraw.name = "Withdraw"
	var cols := UiBuild.hbox(body, 10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	carry_list = _column(cols, "身上", SIDE_CARRY)
	var mid := UiBuild.vbox(cols, 8)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.custom_minimum_size = Vector2(120, 0)
	UiBuild.muted(UiBuild.label(mid, "數量", 14))
	n_spin = SpinBox.new()
	n_spin.name = "Amount"
	n_spin.min_value = 1
	n_spin.max_value = 1
	n_spin.value = 1
	mid.add_child(n_spin)
	n_spin.value_changed.connect(func(_v: float): _update_actions())
	btn_put = UiBuild.button(mid, "存入 →", put_selected)
	btn_put.name = "Put"
	btn_take = UiBuild.button(mid, "← 取出", take_selected)
	btn_take.name = "Take"
	pick_label = UiBuild.muted(UiBuild.label(mid, "", 13, true))
	pick_label.name = "PickHint"
	pick_label.custom_minimum_size = Vector2(120, 0)
	bank_list = _column(cols, "錢莊（三城通用）", SIDE_BANK)
	used_label = UiBuild.label(body, "", 15)
	used_label.name = "Used"

func _column(parent: Node, title: String, s: String) -> VBoxContainer:
	var v := UiBuild.vbox(parent, 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UiBuild.accent(UiBuild.label(v, title, 16))
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	t.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			set_side(s))
	var box := UiBuild.framed(v, UiFrame.Kind.INK)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sc := UiBuild.scroll(box, LIST_H)
	var list := UiBuild.vbox(sc, 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return list

func npc_id() -> String:
	return npc

## 打開／更新：p = bank_view payload；npc_id = 送 bank_open 的那位錢莊 NPC
func open_view(p: Dictionary, npc_id_: String = "") -> void:
	ensure_built()
	if npc_id_ != "":
		npc = npc_id_
	elif str(p.get("npc", "")) != "":
		npc = str(p.get("npc", ""))
	view = EconUi.bank_view(p)
	if str(p.get("npc_name", "")) != "":
		title_label.text = "%s・錢莊" % str(p.get("npc_name", ""))
	status_label.text = ""
	visible = true
	_render()

## 角色表更新（身上物品、銀兩）
func apply_sheet(s: Dictionary) -> void:
	sheet = s
	if _built and visible:
		_render()

func _sheet() -> Dictionary:
	return sheet if not sheet.is_empty() else UiClient.sheet()

func carry_rows() -> Array:
	var inv: Variant = _sheet().get("inventory", [])
	return (inv as Array).filter(func(x): return x is Dictionary) if inv is Array else []

func bank_rows() -> Array:
	return (view.get("items", []) as Array).filter(func(x): return x is Dictionary)

func set_side(s: String) -> void:
	side = s
	_render()

func _render() -> void:
	var sh := _sheet()
	bank_money_label.text = "錢莊存款：%d 兩" % UiBuild.num(view.get("money", 0))
	carry_money_label.text = "身上銀兩：%d 兩" % UiBuild.num(sh.get("money", 0))
	used_label.text = EconUi.bank_used_text(view)
	clear_choices()
	# M3b 審查 4：數字鍵跟著的那一欄空了（例如取出錢莊最後一件），換到另一欄，數字鍵才選得到東西
	var rows_now := { SIDE_CARRY: carry_rows(), SIDE_BANK: bank_rows() }
	var other := SIDE_BANK if side == SIDE_CARRY else SIDE_CARRY
	if (rows_now[side] as Array).is_empty() and not (rows_now[other] as Array).is_empty():
		side = other
	_fill(carry_list, SIDE_CARRY, carry_rows())
	_fill(bank_list, SIDE_BANK, bank_rows())
	_update_actions()

func _fill(list: VBoxContainer, s: String, rows: Array) -> void:
	UiBuild.clear(list)
	(row_buttons[s] as Dictionary).clear()
	var keep := false
	var i := 0
	for r in rows:
		var uid := str(r.get("uid", ""))
		i += 1
		var row := UiBuild.hbox(list, 2)
		if s == side:
			NumberedDialog.numbered_label(row, i)
		var b := UiBuild.button(row, EconUi.item_line(r))
		b.name = "%s_%s" % [s, uid]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = str(selected[s]) == uid
		if s == SIDE_CARRY:
			var why := EconUi.not_storable_reason(r)
			if why != "":
				b.text += "（%s）" % ("裝備中" if why == "equipped_item" else "不能存")
				b.tooltip_text = EconUi.store_block_text(why)
		b.pressed.connect(func(): select(s, uid))
		(row_buttons[s] as Dictionary)[uid] = b
		if s == side:
			add_choice(b)
		if str(selected[s]) == uid:
			keep = true
	if not keep:
		selected[s] = ""
	if rows.is_empty():
		UiBuild.muted(UiBuild.label(list, "（沒有東西）" if s == SIDE_CARRY else "（錢莊裡沒有寄存的東西）", 15))

## 選一列（同一欄只選一列）；數量預設整堆
func select(s: String, uid: String) -> void:
	side = s
	selected[s] = uid
	var r := find_row(s, uid)
	var n := maxi(1, UiBuild.num(r.get("n", 1)))
	n_spin.max_value = n
	n_spin.value = n
	_render()

func find_row(s: String, uid: String) -> Dictionary:
	for r in (carry_rows() if s == SIDE_CARRY else bank_rows()):
		if str(r.get("uid", "")) == uid:
			return r
	return {}

func _update_actions() -> void:
	var cr := find_row(SIDE_CARRY, str(selected[SIDE_CARRY]))
	var br := find_row(SIDE_BANK, str(selected[SIDE_BANK]))
	var n := int(n_spin.value)
	var put_why := "" if not cr.is_empty() else "pick"
	if put_why == "":
		put_why = EconUi.put_block(cr, mini(n, maxi(1, UiBuild.num(cr.get("n", 1)))), view)
	btn_put.disabled = put_why != ""
	btn_put.tooltip_text = "" if put_why in ["", "pick"] else EconUi.item_block_text(put_why)
	btn_take.disabled = br.is_empty()
	var hint := ""
	if side == SIDE_CARRY and put_why not in ["", "pick"]:
		hint = EconUi.item_block_text(put_why)
	elif side == SIDE_BANK and not br.is_empty():
		var tw := EconUi.take_block(br, n, _sheet())
		if tw != "":
			hint = "可能%s" % EconUi.item_block_text(tw)
	pick_label.text = hint

func put_selected() -> int:
	var uid := str(selected[SIDE_CARRY])
	if uid == "" or btn_put.disabled:
		return -1
	var r := find_row(SIDE_CARRY, uid)
	var n := EconUi.clamp_n(int(n_spin.value), UiBuild.num(r.get("n", 1)))
	return send(UiKeys.I_BANK_PUT, { "npc": npc, "uid": uid, "n": n }, [btn_put])

func take_selected() -> int:
	var uid := str(selected[SIDE_BANK])
	if uid == "":
		return -1
	var r := find_row(SIDE_BANK, uid)
	var n := EconUi.clamp_n(int(n_spin.value), UiBuild.num(r.get("n", 1)))
	return send(UiKeys.I_BANK_TAKE, { "npc": npc, "uid": uid, "n": n }, [btn_take])

## 存錢（deposit = true）或領錢；本機就知道不行時不送、直接寫原因
func send_money(deposit: bool) -> int:
	var amt := int(money_edit.text.strip_edges().to_int())
	amt = absi(amt)
	var signed := amt if deposit else -amt
	var why := EconUi.money_block(signed, UiBuild.num(_sheet().get("money", 0)), view) if amt > 0 else "bad_amount"
	if why != "":
		status_label.text = EconUi.money_block_text(why)
		return -1
	return send(UiKeys.I_BANK_MONEY, { "npc": npc, "amount": signed }, [btn_deposit, btn_withdraw], func(): money_edit.text = "")
