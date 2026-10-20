class_name ShopDialog
extends UiDialog
## 商店／交易窗（AUTHENTIC_UI_SPEC §8.8；M1_PLAN 3.12）：竹軸捲軸框，約 760×440，照原作的購物車流程：
## - 上方「買」「賣」分頁鈕、「本次交易共 [ n ] 兩」總價牌、⊠；
## - 我的物品（5×4，可賣的東西）｜商店貨品（5×4）｜待買／待賣（2×6）；
## - 點貨品（或我的物品）放進待買（待賣）欄，可以調數量：點一下 +1、Shift 點 +10、右鍵 −1；
## - 下方「身上銀兩」與 ✔／✘：按 ✔ 才逐筆送出 buy／sell（主機 intent 不變），全部回來後重新送 shop_list。
## 身上裝備著的（sellable[].equipped）放進待賣時格子紅框，按 ✔ 時先再確認一次（主機賣出時會先卸下，新手很容易把唯一的兵器賣掉）。

const EQUIPPED_MARK := "（已裝備）"
const CONFIRM_TEXT := "確定賣"
const COLS := 5
const ROWS := 4
const CART_COLS := 2
const CART_ROWS := 6
const SLOT := Vector2(44, 44)
const MODE_BUY := "BUY"
const MODE_SELL := "SELL"

var data: Dictionary = {}
var mode := MODE_BUY
var money_label: Label
var total_label: Label
var hint_label: Label
var mine_grid: GridContainer
var shop_grid: GridContainer
var cart_grid: GridContainer
var cart_title: Label
var btn_buy: Button
var btn_sell: Button
var btn_ok: JyButton
var btn_cancel: JyButton
var cart: Array = []                 # [{ key（item id 或 uid）, name, price, n, max, equipped }]
var _confirm_equipped := false
var _pending := 0

func frame_kind() -> int:
	return UiFrame.Kind.SCROLL

func dialog_size() -> Vector2:
	return Vector2(760, 440)

func _build_body() -> void:
	var top := UiBuild.hbox(body, 8)
	btn_buy = UiBuild.button(top, "買", set_mode.bind(MODE_BUY))
	btn_sell = UiBuild.button(top, "賣", set_mode.bind(MODE_SELL))
	for b in [btn_buy, btn_sell]:
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(48, 0)
		b.focus_mode = Control.FOCUS_NONE
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(24, 0)
	top.add_child(sp)
	UiBuild.label(top, "本次交易共", 15)
	total_label = UiBuild.plate(top, "0", 15, 110)
	total_label.add_theme_color_override("font_color", UiTheme.JY_TEXT)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiBuild.label(top, "兩", 15)
	var cols := UiBuild.hbox(body, 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mine_grid = _zone(cols, "我的物品", COLS, ROWS)
	shop_grid = _zone(cols, "商店貨品", COLS, ROWS)
	cart_grid = _zone(cols, "待買", CART_COLS, CART_ROWS)
	cart_title = cart_grid.get_parent().get_parent().get_child(0) as Label
	hint_label = UiBuild.muted(UiBuild.label(body, "", 13, true))
	var bot := UiBuild.hbox(body, 8)
	money_label = UiBuild.label(bot, "", 16)
	money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_ok = UiBuild.jy_button(bot, JyButton.Style.CONFIRM, "確定交易", _on_ok)
	btn_cancel = UiBuild.jy_button(bot, JyButton.Style.CANCEL, "清空", clear_cart)

## 一區：標題＋栗色格（可捲動）；回傳 GridContainer
func _zone(parent: Node, title: String, c: int, r: int) -> GridContainer:
	var v := UiBuild.vbox(parent, 2)
	UiBuild.label(v, title, 15)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 高度剛好是整數列（列距 4 只算在列與列之間）：待買 2×6 只露 4 列時，不會在下緣露出半格（審查）
	sc.custom_minimum_size = Vector2(c * (SLOT.x + 4) + 10, mini(r, 4) * (SLOT.y + 4) - 4)
	v.add_child(sc)
	var g := GridContainer.new()
	g.columns = c
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	sc.add_child(g)
	return g

func npc_id() -> String:
	return str(data.get("npc", ""))

## p = shop_list payload（3.8.2）
func open_shop(p: Dictionary) -> void:
	ensure_built()
	data = p
	title_label.text = "%s的鋪子" % str(p.get("npc_name", ""))
	money_label.text = "身上銀兩：%d 兩" % UiBuild.num(UiClient.sheet().get("money", 0))
	# 清掉已經不在清單上的待賣（賣掉了）
	cart = cart.filter(func(c): return _row_for(str(c["key"])) != {})
	_render()
	visible = true

func set_mode(m: String) -> void:
	if m != mode:
		mode = m
		cart.clear()
	_confirm_equipped = false
	_render()

func _row_for(key: String) -> Dictionary:
	var list: Array = data.get("items", []) if mode == MODE_BUY else data.get("sellable", [])
	for it in list:
		if it is Dictionary and str(it.get("id" if mode == MODE_BUY else "uid", "")) == key:
			return it
	return {}

func _render() -> void:
	btn_buy.button_pressed = mode == MODE_BUY
	btn_sell.button_pressed = mode == MODE_SELL
	cart_title.text = "待買" if mode == MODE_BUY else "待賣"
	hint_label.text = ("點商店貨品放進待買（Shift +10、右鍵 −1），按右下「確定」成交。" if mode == MODE_BUY
		else "點我的物品放進待賣（收購價為定價的三成；紅框＝裝備中），按右下「確定」成交。")
	# 我的物品（可賣的）
	UiBuild.clear(mine_grid)
	var sellable: Array = data.get("sellable", [])
	for it in sellable:
		if not (it is Dictionary):
			continue
		var equipped := bool(it.get("equipped", false))
		var b := _slot(mine_grid, "%s%s ×%d　%d 兩" % [str(it.get("name", "")), EQUIPPED_MARK if equipped else "", maxi(1, UiBuild.num(it.get("n", 1))), UiBuild.num(it.get("price", 0))],
			str(it.get("name", "")), maxi(1, UiBuild.num(it.get("n", 1))))
		b.marked = equipped
		b.disabled = mode != MODE_SELL
		var uid := str(it.get("uid", ""))
		b.pressed.connect(func(): add_to_cart(uid, 10 if Input.is_key_pressed(KEY_SHIFT) else 1))
	_pad(mine_grid, sellable.size(), COLS * ROWS)
	# 商店貨品
	UiBuild.clear(shop_grid)
	var items: Array = data.get("items", [])
	for it in items:
		if not (it is Dictionary):
			continue
		var desc := str(UiClient.row("items", str(it.get("id", ""))).get("desc", ""))
		var b := _slot(shop_grid, "%s　%d 兩%s" % [str(it.get("name", it.get("id", ""))), UiBuild.num(it.get("price", 0)), ("\n" + desc) if desc != "" else ""],
			str(it.get("name", it.get("id", ""))), 0)
		b.disabled = mode != MODE_BUY
		var item_id := str(it.get("id", ""))
		b.pressed.connect(func(): add_to_cart(item_id, 10 if Input.is_key_pressed(KEY_SHIFT) else 1))
	_pad(shop_grid, items.size(), COLS * ROWS)
	if items.is_empty() and mode == MODE_BUY:
		hint_label.text = "（不賣東西）"
	# M3b（M3B_PLAN §5.1.6）：shop_list.refused → 照樣列出貨品，但買不了（例：京城兵器鋪不賣給丐幫弟子）；賣東西不受影響
	if is_refused() and mode == MODE_BUY:
		for c in shop_grid.get_children():
			if c is BaseButton:
				(c as BaseButton).disabled = true
		hint_label.text = refused_text()
	# 待買／待賣
	UiBuild.clear(cart_grid)
	for c in cart:
		var b := _slot(cart_grid, "%s ×%d　共 %d 兩" % [str(c["name"]), int(c["n"]), int(c["n"]) * int(c["price"])], str(c["name"]), int(c["n"]))
		b.marked = bool(c["equipped"])
		var key := str(c["key"])
		b.pressed.connect(func(): add_to_cart(key, 10 if Input.is_key_pressed(KEY_SHIFT) else 1))
		b.gui_input.connect(func(ev: InputEvent):
			var mb := ev as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				add_to_cart(key, -1))
	_pad(cart_grid, cart.size(), CART_COLS * CART_ROWS)
	total_label.text = str(cart_total())
	btn_ok.disabled = cart.is_empty() or _pending > 0
	btn_cancel.disabled = cart.is_empty()

func is_refused() -> bool:
	return data.get("refused", false) == true

## 拒賣的話：shop_list 帶的 refuse_text／refused_text（模板 id 或文字），沒有就用預設句
func refused_text() -> String:
	for k in ["refused_text", "refuse_text"]:
		var t := str(data.get(k, ""))
		if t == "":
			continue
		var tpl: Variant = UiClient.templates().get(t, null)
		if tpl is Dictionary:
			return TextRenderer.strip_channel_tag(TextRenderer.fill(str((tpl as Dictionary).get("self", (tpl as Dictionary).get("other", ""))), data))
		return TextRenderer.strip_channel_tag(t)
	return "掌櫃搖搖頭，不肯把東西賣給你。"

func _slot(g: GridContainer, text: String, name: String, n: int) -> JyButton:
	var b := UiBuild.slot(g, text)
	b.glyph = name.left(2)
	b.count = n
	b.custom_minimum_size = SLOT
	b.tooltip_text = text
	return b

func _pad(g: GridContainer, used: int, total: int) -> void:
	for i in maxi(0, total - used):
		var e := UiBuild.slot(g, "")
		e.custom_minimum_size = SLOT
		e.disabled = true
		e.mouse_default_cursor_shape = Control.CURSOR_ARROW

## 放進（或拿出）待買／待賣；delta 可為負
func add_to_cart(key: String, delta: int) -> void:
	var row := _row_for(key)
	if row.is_empty():
		return
	var mx := 99 if mode == MODE_BUY else mini(99, maxi(1, UiBuild.num(row.get("n", 1))))
	for i in cart.size():
		if str(cart[i]["key"]) == key:
			cart[i]["n"] = clampi(int(cart[i]["n"]) + delta, 0, mx)
			if int(cart[i]["n"]) <= 0:
				cart.remove_at(i)
			_confirm_equipped = false
			_render()
			return
	if delta <= 0:
		return
	cart.append({ "key": key, "name": str(row.get("name", key)), "price": UiBuild.num(row.get("price", 0)),
		"n": clampi(delta, 1, mx), "equipped": bool(row.get("equipped", false)) })
	_confirm_equipped = false
	_render()

func cart_total() -> int:
	var t := 0
	for c in cart:
		t += int(c["n"]) * int(c["price"])
	return t

func clear_cart() -> void:
	cart.clear()
	_confirm_equipped = false
	_render()

## ✔：逐筆送出；待賣裡有裝備中的東西時先要求再按一次
func _on_ok() -> void:
	if cart.is_empty() or _pending > 0:
		return
	if mode == MODE_SELL and not _confirm_equipped:
		var eq: PackedStringArray = []
		for c in cart:
			if bool(c["equipped"]):
				eq.append(str(c["name"]))
		if not eq.is_empty():
			_confirm_equipped = true
			status_label.text = "%s正裝備在身上，賣掉會先卸下。確定要賣就再按一次「確定」（%s）。" % ["、".join(eq), CONFIRM_TEXT]
			return
	_confirm_equipped = false
	var batch := cart.duplicate(true)
	cart.clear()
	_pending = batch.size()
	_render()
	for c in batch:
		var args := { "npc": npc_id(), "n": int(c["n"]) }
		var kind := UiKeys.I_BUY
		if mode == MODE_BUY:
			args["item"] = str(c["key"])
		else:
			kind = UiKeys.I_SELL
			args["item_uid"] = str(c["key"])
		send(kind, args, [], _one_done)
		# 失敗時 send() 會在 status_label 顯示原因；_one_done 只在成功時呼叫，所以另外用 gate 結果計數
	_watch_pending()

func _one_done() -> void:
	pass

## 等這批 intent 全部有結果（成功或失敗）再刷新清單
func _watch_pending() -> void:
	while is_inside_tree() and _gate().pending_count() > 0:
		await get_tree().process_frame
	_pending = 0
	if is_inside_tree():
		refresh_list()
		_render()

func refresh_list() -> void:
	_gate().send(UiKeys.I_SHOP_LIST, { "npc": npc_id() })
