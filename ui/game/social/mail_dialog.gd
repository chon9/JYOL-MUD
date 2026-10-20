class_name MailDialog
extends UiDialog
## 飛鴿傳書（M2_PLAN 4.10、4.4.3、5.4）：HUD「鴿」圓章打開。
## - 收件匣：開啟時送 mail_list；收到 mail_list（ui 事件，新到舊）重畫。點一封 → 右邊顯示內文，未讀的送 mail_read；「刪除」→ mail_delete；
##   「回信」→ 寫信頁並填好收件人。
## - 寫信：收件人（角色名，離線也收得到）＋內文 200 字 → mail_send；成功後清空並回到收件匣。
## ClientState 尚未合併 mail_list 欄位時也能用：直接聽 events_received 的 mail_list 事件。

const TAB_INBOX := 0
const TAB_COMPOSE := 1
const UNREAD_MARK := "［新］"
const READ_MARK := "　　　"

var tabs: TabBar
var inbox_page: HBoxContainer
var compose_page: VBoxContainer
var list_box: VBoxContainer
var read_from: Label
var read_text: Label
var delete_button: Button
var reply_button: Button
var reply_row: HBoxContainer
var write_button: Button            # 收件匣空的時候：讀信欄裡的「寫信」
const EMPTY_HINT := "收件匣是空的。
要寄信給別人，點上面的「寫信」或下面的按鈕，寫好後按「放出信鴿」；對方不在線也收得到。"
var to_edit: LineEdit
var body_edit: TextEdit
var count_label: Label
var send_button: Button
var mails: Array = []
var selected_id := ""
var mail_buttons: Dictionary = {}   # id -> Button

func frame_kind() -> int:
	return UiFrame.Kind.SCROLL

func dialog_size() -> Vector2:
	return Vector2(680, 420)

func _ready() -> void:
	super._ready()
	UiClient.connect_signal("events_received", _on_events)

func _exit_tree() -> void:
	UiClient.disconnect_signal("events_received", _on_events)

func _build_body() -> void:
	title_label.text = "飛鴿傳書"
	tabs = TabBar.new()
	tabs.add_tab("收件匣")
	tabs.add_tab("寫信")
	tabs.tab_changed.connect(show_tab)
	body.add_child(tabs)
	# 收件匣
	inbox_page = UiBuild.hbox(body, 10)
	inbox_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sc := UiBuild.scroll(inbox_page, 240)
	sc.custom_minimum_size = Vector2(250, 240)
	sc.size_flags_horizontal = Control.SIZE_FILL
	list_box = UiBuild.vbox(sc, 3)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reader := UiBuild.vbox(inbox_page, 6)
	reader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	read_from = UiBuild.accent(UiBuild.label(reader, "", 16, true))
	var rsc := UiBuild.scroll(reader, 160)
	read_text = UiBuild.label(rsc, "", 16, true)
	read_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rrow := UiBuild.hbox(reader, 8)
	reply_row = rrow
	reply_button = UiBuild.button(rrow, "回信", reply, 80)
	delete_button = UiBuild.button(rrow, "刪除", delete_selected, 80)
	write_button = UiBuild.button(reader, "寫信", func(): compose_to(""), 120)
	write_button.name = "WriteButton"
	# 寫信
	compose_page = UiBuild.vbox(body, 6)
	compose_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var trow := UiBuild.hbox(compose_page, 6)
	UiBuild.label(trow, "收信人", 15).custom_minimum_size = Vector2(64, 0)
	to_edit = UiBuild.line_edit(trow, "", "角色名字（對方不在線也收得到）", UiKeys.NAME_MAX_LEN * 2)
	body_edit = TextEdit.new()
	body_edit.name = "MailBody"
	body_edit.placeholder_text = "寫些什麼……（最多 %d 字）" % UiKeys.MAIL_MAX_LEN
	body_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body_edit.custom_minimum_size = Vector2(0, 180)
	body_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_edit.text_changed.connect(_on_body_changed)
	compose_page.add_child(body_edit)
	var srow := UiBuild.hbox(compose_page, 8)
	count_label = UiBuild.muted(UiBuild.label(srow, "", 14))
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_button = UiBuild.button(srow, "放出信鴿", send_mail, 120)
	_on_body_changed()
	show_tab(TAB_INBOX)
	_show_mail({})

func show_tab(i: int) -> void:
	if tabs.current_tab != i:
		tabs.current_tab = i
	inbox_page.visible = i == TAB_INBOX
	compose_page.visible = i == TAB_COMPOSE

## 打開收件匣：先畫 ClientState 記住的清單，再跟主機要最新的
func open_inbox() -> void:
	ensure_built()
	status_label.text = ""
	visible = true
	show_tab(TAB_INBOX)
	var cached := UiClient.mail_list()
	if not cached.is_empty():
		apply_mail_list(cached)
	refresh()

func refresh() -> void:
	send(UiKeys.I_MAIL_LIST, {})

## 寫信給某人（玩家選單「寄信」、回信）
func compose_to(name: String) -> void:
	ensure_built()
	status_label.text = ""
	visible = true
	to_edit.text = name
	show_tab(TAB_COMPOSE)
	if body_edit.is_inside_tree():
		body_edit.grab_focus()

## mails = 4.4.3：[ { id, from_name, text, sent_clock, read } ]（新到舊）
func apply_mail_list(list: Array) -> void:
	ensure_built()
	mails = list.filter(func(m): return m is Dictionary)
	UiBuild.clear(list_box)
	mail_buttons.clear()
	for m in mails:
		var id := str(m.get("id", ""))
		# 未讀用「新」字（M2 審查：「●」在 Windows 上被畫成彩色 emoji 大紅圓）
		var t := "%s%s　%s" % [UNREAD_MARK if not bool(m.get("read", false)) else READ_MARK, str(m.get("from_name", "?")), str(m.get("sent_clock", ""))]
		var b := UiBuild.button(list_box, t)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "未讀" if not bool(m.get("read", false)) else "已讀"
		b.pressed.connect(select_mail.bind(id))
		mail_buttons[id] = b
	# 空的：右邊讀信欄已經寫了「收件匣是空的」與寫信說明，左邊的信件清單整欄藏起來，不再重複一次（M2 第三輪審查）
	var list_scroll := list_box.get_parent() as Control
	if list_scroll != null:
		list_scroll.visible = not mails.is_empty()
	_show_mail(find_mail(selected_id))

func find_mail(id: String) -> Dictionary:
	for m in mails:
		if str(m.get("id", "")) == id:
			return m
	return {}

func unread_count() -> int:
	return mails.filter(func(m): return not bool(m.get("read", false))).size()

func select_mail(id: String) -> void:
	var m := find_mail(id)
	selected_id = id if not m.is_empty() else ""
	_show_mail(m)
	if not m.is_empty() and not bool(m.get("read", false)):
		send(UiKeys.I_MAIL_READ, { "id": id })

func _show_mail(m: Dictionary) -> void:
	# 收件匣空的：不顯示用不到的回信／刪除，讀信欄改放怎麼寫信的說明（M2 審查：一大片空白加兩顆灰按鈕）
	var empty := mails.is_empty()
	reply_row.visible = not empty
	write_button.visible = empty
	if m.is_empty():
		read_from.text = "（點左邊的信來看）" if not empty else ""
		read_text.text = EMPTY_HINT if empty else ""
		delete_button.disabled = true
		reply_button.disabled = true
		return
	read_from.text = "%s的來信　%s" % [str(m.get("from_name", "?")), str(m.get("sent_clock", ""))]
	read_text.text = str(m.get("text", ""))
	delete_button.disabled = false
	reply_button.disabled = false
	for id in mail_buttons:
		(mail_buttons[id] as Button).add_theme_color_override("font_color", UiTheme.CINNABAR if id == selected_id else UiTheme.INK)

func delete_selected() -> void:
	if selected_id == "":
		return
	var id := selected_id
	send(UiKeys.I_MAIL_DELETE, { "id": id }, [delete_button], func():
		if selected_id == id:
			selected_id = "")

func reply() -> void:
	var m := find_mail(selected_id)
	if not m.is_empty():
		compose_to(str(m.get("from_name", "")))

## 內文上限 200 字：超過就截掉（主機也會擋 text_too_long）
func _on_body_changed() -> void:
	if body_edit.text.length() > UiKeys.MAIL_MAX_LEN:
		var col := body_edit.get_caret_column()
		body_edit.text = body_edit.text.left(UiKeys.MAIL_MAX_LEN)
		body_edit.set_caret_line(body_edit.get_line_count() - 1)
		body_edit.set_caret_column(mini(col, body_edit.get_line(body_edit.get_line_count() - 1).length()))
	count_label.text = "%d／%d 字" % [body_edit.text.length(), UiKeys.MAIL_MAX_LEN]

func send_mail() -> void:
	var to := to_edit.text.strip_edges()
	var text := body_edit.text.strip_edges()
	if to == "":
		status_label.text = "請填收信人的名字。"
		return
	if text == "":
		status_label.text = "信裡還沒有寫字。"
		return
	send(UiKeys.I_MAIL_SEND, { "to": to, "text": text }, [send_button], func():
		body_edit.text = ""
		_on_body_changed()
		show_tab(TAB_INBOX))

func _on_events(batch: Array) -> void:
	for e in batch:
		if not (e is Dictionary):
			continue
		match str(e.get("key", "")):
			UiKeys.E_MAIL_LIST:
				var p: Dictionary = e.get("p", {})
				var list: Variant = p.get("mails", [])
				apply_mail_list(list if list is Array else [])
			UiKeys.E_MAIL_ARRIVED:
				if visible:
					refresh()
