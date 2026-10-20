class_name EscortWindow
extends NumberedDialog
## 鏢局窗（M3B_PLAN §7.2、§5.2.2–5.2.3）：npc_menu「鏢局」打開（鏢頭的 npc_menu 帶 escort 與 quests）。三個分頁：
## - 托鏢：收件人名、目的城下拉（附送達時間）、選物品（每樣可選數量，最多 10 樣）與銀兩、即時運費
##   → consign_send { npc, to, city, items: [{uid, n}], money }；
## - 取貨：切到這頁送 consign_list { npc }，主機回 consign_list（ui）→ 列出到站可領的與寄出還在路上的；
##   可領的「領取」→ consign_take { npc, id }；
## - 保鏢：既有任務選單（服務「任務」的同一份 quests）：可接 → quest_accept、可交付 → quest_turn_in；
##   本派不能運鏢（丐幫，sects.no_escort）時寫明。
## 數字鍵 1–9：目前分頁的第 n 個項目（托鏢頁＝物品勾選、取貨頁＝領取、保鏢頁＝接受／交付）。

const TAB_SEND := "SEND"
const TAB_TAKE := "TAKE"
const TAB_JOB := "JOB"
const TABS := [TAB_SEND, TAB_TAKE, TAB_JOB]
const TAB_LABELS := { TAB_SEND: "托鏢", TAB_TAKE: "取貨", TAB_JOB: "保鏢" }

var menu: Dictionary = {}
var sheet: Dictionary = {}
var tab := TAB_SEND
var tab_buttons: Dictionary = {}
var page: VBoxContainer
var to_edit: LineEdit
var city_opt: OptionButton
var money_edit: LineEdit
var fee_label: Label
var send_button: Button
var picks: Dictionary = {}           # uid -> n
var pick_boxes: Dictionary = {}      # uid -> CheckBox
var list_rows: Array = []            # consign_list 的列
var list_loaded := false
var footer: VBoxContainer            # M3b 審查：運費與「托鏢」鈕放在捲動區外（物品一多也看得到）

func dialog_size() -> Vector2:
	return Vector2(700, 440)

func _build_body() -> void:
	title_label.text = "鏢局"
	var bar := UiBuild.hbox(body, 6)
	for t in TABS:
		var b := UiBuild.button(bar, str(TAB_LABELS[t]), set_tab.bind(t), 80)
		b.name = "Tab_" + t
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		tab_buttons[t] = b
	var sc := UiBuild.scroll(body, 250)
	page = UiBuild.vbox(sc, 6)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer = UiBuild.vbox(body, 4)
	footer.name = "Footer"

func npc_id() -> String:
	return str(menu.get("npc", ""))

## p = 鏢頭的 npc_menu（帶 escort、quests）
func open_menu(p: Dictionary, start_tab: String = TAB_SEND) -> void:
	ensure_built()
	menu = p
	title_label.text = "%s・鏢局" % str(EconUi.escort_menu(p).get("city_name", p.get("npc_name", ""))) if not EconUi.escort_menu(p).is_empty() else "鏢局"
	picks.clear()
	list_rows = []
	list_loaded = false
	status_label.text = ""
	visible = true
	set_tab(start_tab)

## 主機重送的選單（接／交任務後 refresh）
func refresh_menu(p: Dictionary) -> void:
	menu = p
	if visible and tab == TAB_JOB:
		_render()

func apply_sheet(s: Dictionary) -> void:
	sheet = s
	if _built and visible and tab == TAB_SEND:
		_update_fee()

func _sheet() -> Dictionary:
	return sheet if not sheet.is_empty() else UiClient.sheet()

func set_tab(t: String) -> void:
	tab = t if t in TABS else TAB_SEND
	for k in tab_buttons:
		(tab_buttons[k] as Button).button_pressed = k == tab
	status_label.text = ""
	_render()
	if tab == TAB_TAKE and not list_loaded:
		request_list()

func _render() -> void:
	UiBuild.clear(page)
	UiBuild.clear(footer)
	clear_choices()
	match tab:
		TAB_SEND:
			_render_send()
		TAB_TAKE:
			_render_take()
		TAB_JOB:
			_render_job()

# ---------------------------------------------------------------- 托鏢
func _render_send() -> void:
	var e := EconUi.escort_menu(menu)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	page.add_child(g)
	UiBuild.label(g, "收件人", 15)
	var keep_to := to_edit.text if to_edit != null and is_instance_valid(to_edit) else ""
	to_edit = UiBuild.line_edit(g, keep_to, "對方的角色名", UiKeys.NAME_MAX_LEN)
	to_edit.name = "ToName"
	to_edit.text_changed.connect(func(_t): _update_fee())
	UiBuild.label(g, "目的城", 15)
	city_opt = OptionButton.new()
	city_opt.name = "City"
	var rs := EconUi.routes(menu)
	for i in rs.size():
		city_opt.add_item(EconUi.route_label(rs[i]), i)
		city_opt.set_item_metadata(i, str(rs[i].get("city", "")))
	city_opt.item_selected.connect(func(_i): _update_fee())
	g.add_child(city_opt)
	UiBuild.label(g, "銀兩", 15)
	var keep_m := money_edit.text if money_edit != null and is_instance_valid(money_edit) else ""
	money_edit = UiBuild.line_edit(g, keep_m, "0", 8)
	money_edit.name = "Money"
	money_edit.text_changed.connect(func(_t): _update_fee())
	if rs.is_empty():
		UiBuild.error(UiBuild.label(page, "這裡的鏢局目前沒有可托鏢的路線。", 15, true))
	UiBuild.muted(UiBuild.label(page, "要寄的物品（最多 %d 樣；裝備中與任務物品不能寄）：" % UiKeys.CONSIGN_ITEMS_MAX, 14, true))
	pick_boxes.clear()
	var i := 0
	for it in _sheet().get("inventory", []):
		if not (it is Dictionary):
			continue
		var uid := str(it.get("uid", ""))
		i += 1
		var row := UiBuild.hbox(page, 6)
		NumberedDialog.numbered_label(row, i)
		var cb := CheckBox.new()
		cb.name = "Pick_" + uid
		cb.text = EconUi.item_line(it)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# M3b 審查：淺米色列上用深色字（預設的淺色字看不清）
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			cb.add_theme_color_override(k, UiTheme.JY_BTN_TEXT)
		cb.add_theme_color_override("font_disabled_color", UiTheme.JY_BRONZE)
		row.add_child(cb)
		var max_n := maxi(1, UiBuild.num(it.get("n", 1)))
		var sp := SpinBox.new()
		sp.name = "PickN_" + uid
		sp.min_value = 1
		sp.max_value = max_n
		sp.value = clampi(UiBuild.num(picks.get(uid, max_n)), 1, max_n)
		sp.visible = max_n > 1
		row.add_child(sp)
		var why := EconUi.not_storable_reason(it)
		if why != "":
			cb.disabled = true
			cb.tooltip_text = EconUi.store_block_text(why)
			picks.erase(uid)
		cb.button_pressed = picks.has(uid)
		cb.toggled.connect(func(on: bool):
			if on:
				picks[uid] = int(sp.value)
			else:
				picks.erase(uid)
			_update_fee())
		sp.value_changed.connect(func(v: float):
			if picks.has(uid):
				picks[uid] = int(v)
				_update_fee())
		pick_boxes[uid] = cb
		add_choice(cb)
	fee_label = UiBuild.label(footer, "", 15, true)
	fee_label.name = "Fee"
	var foot := UiBuild.hbox(footer, 8)
	send_button = UiBuild.button(foot, "托鏢", send_consign, 110)
	send_button.name = "SendConsign"
	UiBuild.muted(UiBuild.label(foot, "不會被劫；%d 遊戲日沒人領就退回寄件城。" % _hold_days(e), 13, true)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_fee()

func _hold_days(e: Dictionary) -> int:
	return UiBuild.num(e.get("hold_days", UiClient.world_info().get("consign_hold_days", 30)))

func selected_city() -> String:
	if city_opt == null or not is_instance_valid(city_opt) or city_opt.selected < 0:
		return ""
	return str(city_opt.get_item_metadata(city_opt.selected))

func money_amount() -> int:
	if money_edit == null or not is_instance_valid(money_edit):
		return 0
	return maxi(0, money_edit.text.strip_edges().to_int())

func current_fee() -> int:
	var fp := EconUi.fee_params(menu)
	return EconUi.consign_fee(EconUi.picked_weight(_sheet(), picks), fp.x, fp.y)

func _update_fee() -> void:
	if fee_label == null or not is_instance_valid(fee_label):
		return
	var fp := EconUi.fee_params(menu)
	var w := EconUi.picked_weight(_sheet(), picks)
	var fee := EconUi.consign_fee(w, fp.x, fp.y)
	fee_label.text = "運費：%d 兩（基本 %d ＋ 每重 %d × 重 %d）%s" % [fee, fp.x, fp.y, w,
		"　另寄銀兩 %d 兩" % money_amount() if money_amount() > 0 else ""]
	var why := _send_block()
	if send_button != null and is_instance_valid(send_button):
		send_button.disabled = why != ""
		send_button.tooltip_text = EconUi.send_block_text(why) if why != "" else ""

func _send_block() -> String:
	var name := to_edit.text if to_edit != null and is_instance_valid(to_edit) else ""
	return EconUi.send_block(name, selected_city(), EconUi.picks_to_items(_sheet(), picks), money_amount(), current_fee(), _sheet())

func send_consign() -> int:
	var why := _send_block()
	if why != "":
		status_label.text = EconUi.send_block_text(why)
		return -1
	var args := { "npc": npc_id(), "to": to_edit.text.strip_edges(), "city": selected_city(),
		"items": EconUi.picks_to_items(_sheet(), picks), "money": money_amount() }
	return send(UiKeys.I_CONSIGN_SEND, args, [send_button], func():
		picks.clear()
		if money_edit != null and is_instance_valid(money_edit):
			money_edit.text = ""
		if tab == TAB_SEND:
			_render())

# ---------------------------------------------------------------- 取貨
func request_list() -> int:
	return send(UiKeys.I_CONSIGN_LIST, { "npc": npc_id() })

## p = consign_list payload
func apply_list(p: Dictionary) -> void:
	ensure_built()
	list_rows = EconUi.consign_rows(p)
	list_loaded = true
	if tab == TAB_TAKE:
		_render()

func _render_take() -> void:
	var e := EconUi.escort_menu(menu)
	if not list_loaded:
		UiBuild.muted(UiBuild.label(page, "查詢中……", 15))
		return
	var me := UiClient.my_char_id()
	if me == "":
		me = str(_sheet().get("char_id", ""))
	var i := 0
	for r in list_rows:
		var row := UiBuild.hbox(page, 6)
		var take := EconUi.can_take(r, me)
		if take:
			i += 1
			NumberedDialog.numbered_label(row, i)
		var l := UiBuild.label(row, EconUi.consign_line(r, me), 15, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if take:
			var cid := str(r.get("id", ""))
			var b := UiBuild.button(row, "領取", Callable(), 70)
			b.name = "Take_" + cid
			b.pressed.connect(func(): send(UiKeys.I_CONSIGN_TAKE, { "npc": npc_id(), "id": cid }, [b], request_list))
			add_choice(b)
	if list_rows.is_empty():
		UiBuild.muted(UiBuild.label(page, "（%s的鏢局沒有你的貨）" % str(e.get("city_name", "這裡")), 15))

# ---------------------------------------------------------------- 保鏢
func _render_job() -> void:
	var sect_id := str(_sheet().get("sect", ""))
	if sect_id != "" and bool(UiClient.row("sects", sect_id).get("no_escort", false)):
		UiBuild.error(UiBuild.label(page, "%s弟子不能接保鏢工作。" % UiClient.name_of("sects", sect_id), 15, true))
	var qs: Variant = menu.get("quests", [])
	var i := 0
	for q in (qs if qs is Array else []):
		if not (q is Dictionary):
			continue
		var row := UiBuild.hbox(page, 6)
		var qid := str(q.get("id", ""))
		var state := str(q.get("state", ""))
		var btn: Button = null
		match state:
			"AVAILABLE":
				btn = Button.new()
				btn.text = "接下"
				btn.name = "JobAccept_" + qid
				btn.pressed.connect(func(): send(UiKeys.I_QUEST_ACCEPT, { "npc": npc_id(), "quest": qid }, [btn]))
			"READY":
				btn = Button.new()
				if bool(q.get("resume", false)):
					# M3b 審查 3：鏢車走散 → 重新領車（quest_talk 走 _escort_restart）
					btn.text = "重領鏢車"
					btn.name = "JobResume_" + qid
					btn.pressed.connect(func(): send(UiKeys.I_QUEST_TALK, { "npc": npc_id(), "quest": qid }, [btn]))
				else:
					btn.text = "交鏢"
					btn.name = "JobTurnIn_" + qid
					btn.pressed.connect(func(): send(UiKeys.I_QUEST_TURN_IN, { "npc": npc_id(), "quest": qid }, [btn]))
		if btn != null:
			i += 1
			NumberedDialog.numbered_label(row, i)
		var t := "%s　[%s]" % [str(q.get("name", qid)), UiKeys.QUEST_STATE_LABELS.get(state, state)]
		var l := UiBuild.label(row, t, 15, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if btn != null:
			row.add_child(btn)
			add_choice(btn)
		if state == "LOCKED" and str(q.get("locked_why", "")) != "":
			UiBuild.muted(UiBuild.label(page, "　　需要：" + str(q.get("locked_why", "")), 14, true))
	if i == 0 and (not (qs is Array) or (qs as Array).is_empty()):
		UiBuild.muted(UiBuild.label(page, "（目前沒有保鏢工作）", 15))
