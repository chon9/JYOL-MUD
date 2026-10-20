class_name OrgPanel
extends NumberedDialog
## 組織面板（M3B_PLAN §7.4、§5.3）：燈籠「指令 → 組織」打開（送 org_info，主機回 org_info（ui）時更新），
## 衙門書吏的「組織」服務也打開這個面板（多一段書吏：創立、連署清單）。
## - 有組織：組織名、你的位階與封號、成員表（在線 ●／○、位階、封號；點一列選取，數字鍵 1–9 選第 n 列）；
##   有權限才出現的按鈕：邀請（輸入角色名）→ org_invite { name }、開除 → org_kick { name }、設位階 → org_set_rank { name, rank }、
##   封號 → org_title { name, title }、改位階名稱 → org_rank_names { names }、移交 → org_lead { name }、
##   解散（兩段確認，第二段輸入組織名）→ org_disband { confirm: true }、退出 → org_leave {}。
## - 沒組織：「到各城衙門找書吏創立或連署」與天地會等會籍。
## - 書吏：創立（輸入名字、顯示費用與名聲條件）→ org_found { npc, name }；連署清單「連署」→ org_sign { npc, org }。
## 組織邀請用既有的待回覆提示（PendingPrompts）。

var info: Dictionary = {}           # OrgUi.normalize_info 之後
var sheet: Dictionary = {}
var clerk_menu: Dictionary = {}     # 從書吏打開時的 npc_menu
var head_label: Label
var me_label: Label
var soc_label: Label
var clerk_box: VBoxContainer
var members_box: VBoxContainer
var actions_box: VBoxContainer
var detail_box: VBoxContainer
var target := ""                    # 選取的成員名
var member_buttons: Dictionary = {} # name -> Button
var action_buttons: Dictionary = {} # 動作 id -> Control
var invite_edit: LineEdit
var found_edit: LineEdit
var _loaded := false

func dialog_size() -> Vector2:
	return Vector2(700, 460)

func _build_body() -> void:
	title_label.text = "組織"
	var sc := UiBuild.scroll(body, 360)
	var col := UiBuild.vbox(sc, 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clerk_box = UiBuild.vbox(col, 6)
	clerk_box.name = "Clerk"
	head_label = UiBuild.accent(UiBuild.label(col, "", 17, true))
	head_label.name = "OrgHeader"
	me_label = UiBuild.label(col, "", 15, true)
	me_label.name = "OrgMe"
	soc_label = UiBuild.muted(UiBuild.label(col, "", 14, true))
	soc_label.name = "Societies"
	members_box = UiBuild.vbox(col, 2)
	members_box.name = "Members"
	actions_box = UiBuild.vbox(col, 6)
	actions_box.name = "Actions"
	detail_box = UiBuild.vbox(col, 6)
	detail_box.name = "Detail"

## 指令窗「組織」：先用角色表畫，再向主機要 org_info
func open_panel() -> int:
	ensure_built()
	clerk_menu = {}
	visible = true
	status_label.text = ""
	if not _loaded:
		info = OrgUi.normalize_info(_info_from_sheet())
	_render()
	return send(UiKeys.I_ORG_INFO, {})

## 衙門書吏（npc_menu 的 ORG 服務）
func open_clerk(menu: Dictionary) -> void:
	ensure_built()
	clerk_menu = menu
	visible = true
	status_label.text = ""
	if not _loaded:
		info = OrgUi.normalize_info(_info_from_sheet())
	_render()

func npc_id() -> String:
	return str(clerk_menu.get("npc", ""))

## 主機的 org_info（ui）
func apply_info(p: Dictionary) -> void:
	ensure_built()
	info = OrgUi.normalize_info(p)
	_loaded = true
	if visible:
		_render()

## 主機重送的書吏選單（連署、創立之後）；M3b 審查：一併重要 org_info，上半部（我的連署／組織）跟著更新
func refresh_menu(p: Dictionary) -> void:
	clerk_menu = p
	if visible:
		_render()
		send(UiKeys.I_ORG_INFO, {})

func apply_sheet(s: Dictionary) -> void:
	var had := OrgUi.in_org(sheet)
	sheet = s
	if not _built or not visible:
		return
	# 加入／離開組織：主機的 org_info 會跟著來；先依角色表更新標題
	if had != OrgUi.in_org(s) and not OrgUi.in_org(s):
		info = OrgUi.normalize_info({})
	_render()

func _sheet() -> Dictionary:
	return sheet if not sheet.is_empty() else UiClient.sheet()

func _my_char() -> String:
	var c := UiClient.my_char_id()
	return c if c != "" else str(_sheet().get("char_id", ""))

func _info_from_sheet() -> Dictionary:
	var o := OrgUi.sheet_org(_sheet())
	var p := { "societies": _sheet().get("societies", []) }
	if not o.is_empty():
		p["org"] = o
	return p

func has_org() -> bool:
	return str((info.get("org", {}) as Dictionary).get("id", "")) != "" or OrgUi.in_org(_sheet())

func my_rank() -> int:
	return OrgUi.rank_in(info, _my_char(), _sheet())

func target_rank() -> int:
	for m in info.get("members", []):
		if str(m["name"]) == target:
			return int(m["rank"])
	return -1

func _render() -> void:
	clear_choices()
	member_buttons.clear()
	action_buttons.clear()
	UiBuild.clear(members_box)
	UiBuild.clear(actions_box)
	UiBuild.clear(detail_box)
	_render_clerk()
	var soc := OrgUi.societies(info)
	if soc.is_empty():
		soc = OrgUi.societies(_sheet())
	soc_label.text = "會籍：%s" % "、".join(PackedStringArray(soc)) if not soc.is_empty() else ""
	soc_label.visible = soc_label.text != ""
	if not has_org():
		head_label.text = "你不在任何組織裡。"
		me_label.text = "到各城衙門找書吏創立組織，或在別人發起時去連署。"
		target = ""
		return
	head_label.text = OrgUi.org_header(info) if str((info.get("org", {}) as Dictionary).get("name", "")) != "" \
		else str(OrgUi.sheet_org(_sheet()).get("name", ""))
	me_label.text = OrgUi.my_line(info, _my_char(), _sheet())
	var ms: Array = info.get("members", [])
	if not ms.any(func(m): return str(m["name"]) == target):
		target = ""
	var i := 0
	for m in ms:
		i += 1
		var row := UiBuild.hbox(members_box, 2)
		NumberedDialog.numbered_label(row, i)
		var nm := str(m["name"])
		var b := UiBuild.button(row, OrgUi.member_line(m))
		b.name = "Member_" + nm
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = nm == target
		b.pressed.connect(func(): select_member(nm))
		member_buttons[nm] = b
		add_choice(b)
	var pt: Variant = (info.get("org", {}) as Dictionary).get("petition", null)
	if ms.is_empty() and pt is Dictionary:
		var names: Array = pt.get("signers", []) if pt.get("signers", []) is Array else []
		var txt := "連署中：還要 %d 位江湖人到各城衙門找書吏簽名，滿了組織就成立。" % maxi(0,
			UiBuild.num(pt.get("need", 0)) - UiBuild.num(pt.get("signed", 0)))
		var left := OrgUi.petition_left_text(pt)   # M3b 審查 3：顯示到期時間
		if left != "":
			txt += "\n期限：" + left + "；過期沒湊滿就作廢，手續費全額退還。"
		if not names.is_empty():
			txt += "\n已簽名：" + "、".join(PackedStringArray(names))
		UiBuild.label(members_box, txt, 15)
	elif ms.is_empty():
		UiBuild.muted(UiBuild.label(members_box, "（成員名單讀取中……）" if not _loaded else "（沒有成員資料）", 14))
	_render_actions()

func select_member(name: String) -> void:
	target = name
	for k in member_buttons:
		(member_buttons[k] as Button).button_pressed = k == name
	UiBuild.clear(actions_box)
	UiBuild.clear(detail_box)
	action_buttons.clear()
	_render_actions()

func _act_button(parent: Node, id: String, text: String, cb: Callable) -> Button:
	var b := UiBuild.button(parent, text, cb)
	b.name = "Act_" + id
	action_buttons[id] = b
	return b

func _render_actions() -> void:
	var r := my_rank()
	var tr := target_rank()
	var has_t := target != ""
	# M3b 審查：連署中的發起人只能撤回連署（主機 my.can_disband；手續費全額退還）
	if OrgUi.is_petition(info):
		var my: Variant = info.get("my", {})
		if (my is Dictionary and bool((my as Dictionary).get("can_disband", false))) or r == OrgUi.ROLE_LEADER:
			var rowp := UiBuild.hbox(actions_box, 6)
			var wb := _act_button(rowp, "withdraw", "撤回連署", show_disband)
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				wb.add_theme_color_override(k, UiTheme.JY_RED)
		return
	if OrgUi.can_invite(r):
		var row := UiBuild.hbox(actions_box, 6)
		invite_edit = UiBuild.line_edit(row, "", "要邀請的角色名", UiKeys.NAME_MAX_LEN)
		invite_edit.name = "InviteName"
		_act_button(row, "invite", "邀請", func(): do_invite(invite_edit.text))
	# M3b 審查 3：幫主的動作原本全擠在一行（對「名字」＋開除＋位階＋設位階＋封號欄＋封號＋移交 ≈ 630px，700px 的對話框裝不下長名字）
	# → 對象名字自成一行，開除／位階一行，封號／移交一行
	if has_t:
		var tl := UiBuild.muted(UiBuild.label(actions_box, "對「%s」：" % target, 14))
		tl.name = "ActTarget"
		tl.clip_text = true
		tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var row2 := UiBuild.hbox(actions_box, 6)
	if r >= 0 and r < OrgUi.ROLE_MEMBER:
		var kb := _act_button(row2, "kick", "開除", func(): ask_kick())
		kb.disabled = not has_t or not OrgUi.can_kick(r, tr)
	if OrgUi.can_set_rank(r):
		var ob := OptionButton.new()
		ob.name = "RankPick"
		var names: Array = info.get("rank_names", UiKeys.ORG_DEFAULT_RANK_NAMES)
		for k in range(1, UiKeys.ORG_RANKS):
			ob.add_item(str(names[k]) if k < names.size() else str(UiKeys.ORG_DEFAULT_RANK_NAMES[k]), k)
		if tr >= 1:
			ob.select(ob.get_item_index(tr))
		row2.add_child(ob)
		action_buttons["rank_pick"] = ob
		var sb := _act_button(row2, "set_rank", "設位階", func(): do_set_rank(ob.get_selected_id()))
		# M3b 審查 4：沒選對象、選到幫主或自己時，位階下拉選單也一起停用（以前只停用按鈕，下拉還能點）
		var rank_off := not has_t or tr == OrgUi.ROLE_LEADER or target == _my_name()
		sb.disabled = rank_off
		ob.disabled = rank_off
	var row2b := UiBuild.hbox(actions_box, 6)
	if OrgUi.can_title(r):
		var te := UiBuild.line_edit(row2b, "", "封號（0–6 字）", UiKeys.ORG_TITLE_MAX)
		te.name = "TitleEdit"
		te.custom_minimum_size = Vector2(120, 0)
		action_buttons["title_edit"] = te
		var tb := _act_button(row2b, "title", "封號", func(): do_title(te.text))
		tb.disabled = not has_t
	if OrgUi.can_transfer(r):
		var lb := _act_button(row2b, "lead", "移交", func(): ask_transfer())
		lb.disabled = not has_t or target == _my_name()
	var row3 := UiBuild.hbox(actions_box, 6)
	if OrgUi.can_rank_names(r):
		_act_button(row3, "rank_names", "改位階名稱", show_rank_names)
	if OrgUi.can_disband(r):
		var db := _act_button(row3, "disband", "解散組織", show_disband)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			db.add_theme_color_override(k, UiTheme.JY_RED)
	var leave := _act_button(row3, "leave", "退出組織", ask_leave)
	var lw := OrgUi.leave_block(r)
	if lw != "":
		leave.disabled = true
		leave.tooltip_text = OrgUi.local_text(lw)

func _my_name() -> String:
	return str(_sheet().get("name", ""))

# ---------------------------------------------------------------- 動作
func do_invite(name: String) -> int:
	var n := name.strip_edges()
	if n == "":
		status_label.text = OrgUi.local_text("need_name")
		return -1
	return send(UiKeys.I_ORG_INVITE, { "name": n }, [action_buttons.get("invite")] if action_buttons.has("invite") else [], _clear_invite)

func _clear_invite() -> void:
	if invite_edit != null and is_instance_valid(invite_edit):
		invite_edit.text = ""

func ask_kick() -> void:
	if target == "":
		status_label.text = OrgUi.local_text("need_target")
		return
	var who := target
	_confirm("確定要把「%s」開除出組織？" % who, "開除", func(): send(UiKeys.I_ORG_KICK, { "name": who }, [], _refresh), true)

func do_set_rank(rank: int) -> int:
	if target == "":
		status_label.text = OrgUi.local_text("need_target")
		return -1
	return send(UiKeys.I_ORG_SET_RANK, { "name": target, "rank": clampi(rank, 1, UiKeys.ORG_RANKS - 1) }, [action_buttons.get("set_rank")], _refresh)

func do_title(title: String) -> int:
	if target == "":
		status_label.text = OrgUi.local_text("need_target")
		return -1
	if not OrgUi.title_ok(title):
		status_label.text = OrgUi.local_text("bad_title")
		return -1
	return send(UiKeys.I_ORG_TITLE, { "name": target, "title": title.strip_edges() }, [action_buttons.get("title")], _refresh)

func ask_transfer() -> void:
	if target == "":
		status_label.text = OrgUi.local_text("need_target")
		return
	var who := target
	_confirm("確定要把幫主之位移交給「%s」？移交後你成為幫眾。" % who, "移交", func(): send(UiKeys.I_ORG_LEAD, { "name": who }, [], _refresh), true)

func ask_leave() -> void:
	var lw := OrgUi.leave_block(my_rank())
	if lw != "":
		status_label.text = OrgUi.local_text(lw)
		return
	_confirm("確定要退出組織「%s」？" % str((info.get("org", {}) as Dictionary).get("name", OrgUi.sheet_org(_sheet()).get("name", ""))),
		"退出", func(): send(UiKeys.I_ORG_LEAVE, {}, [], _refresh), true)

## 改位階名稱：5 格（幫主 … 幫眾），每個 1–4 字
func show_rank_names() -> void:
	UiBuild.clear(detail_box)
	UiBuild.label(detail_box, "位階名稱（由高到低，每個 1–4 個字）：", 15)
	var row := UiBuild.hbox(detail_box, 4)
	var edits: Array = []
	var names: Array = info.get("rank_names", UiKeys.ORG_DEFAULT_RANK_NAMES)
	for i in UiKeys.ORG_RANKS:
		var e := UiBuild.line_edit(row, str(names[i]) if i < names.size() else "", "", UiKeys.ORG_RANK_NAME_MAX)
		e.name = "RankName%d" % i
		e.custom_minimum_size = Vector2(80, 0)
		edits.append(e)
	var row2 := UiBuild.hbox(detail_box, 8)
	var ok := UiBuild.button(row2, "確定", Callable(), 80)
	ok.name = "RankNamesOk"
	ok.pressed.connect(func(): do_rank_names(edits.map(func(x): return (x as LineEdit).text), ok))
	UiBuild.button(row2, "取消", func(): UiBuild.clear(detail_box), 80)

func do_rank_names(names: Array, lock: Button = null) -> int:
	var clean: Array = []
	for n in names:
		if not OrgUi.rank_name_ok(str(n)):
			status_label.text = OrgUi.local_text("bad_rank_name")
			return -1
		clean.append(str(n).strip_edges())
	if clean.size() != UiKeys.ORG_RANKS:
		status_label.text = OrgUi.local_text("bad_rank_name")
		return -1
	return send(UiKeys.I_ORG_RANK_NAMES, { "names": clean }, [lock] if lock != null else [], func():
		UiBuild.clear(detail_box)
		_refresh())

## 解散第一段：說明後果
func show_disband() -> void:
	UiBuild.clear(detail_box)
	var org_name := str((info.get("org", {}) as Dictionary).get("name", OrgUi.sheet_org(_sheet()).get("name", "")))
	var msg := "解散「%s」後所有成員都會離開組織，組織名稱與位階設定一併消失，無法復原。" % org_name
	if OrgUi.is_petition(info):
		msg = "撤回「%s」的連署：已簽的名字作廢，手續費全額退還。" % org_name
	var l := UiBuild.label(detail_box, msg, 15, true)
	l.name = "DisbandText"
	l.add_theme_color_override("font_color", UiTheme.JY_RED.lightened(0.35))
	var row := UiBuild.hbox(detail_box, 8)
	var b := UiBuild.button(row, "我意已決", show_disband_confirm)
	b.name = "DisbandStep1"
	UiBuild.button(row, "再想想", func(): UiBuild.clear(detail_box))

## 解散第二段：輸入組織名才能送出
func show_disband_confirm() -> void:
	UiBuild.clear(detail_box)
	var org_name := str((info.get("org", {}) as Dictionary).get("name", OrgUi.sheet_org(_sheet()).get("name", "")))
	UiBuild.label(detail_box, "請輸入組織名「%s」確認解散：" % org_name, 15, true)
	var row := UiBuild.hbox(detail_box, 8)
	var le := UiBuild.line_edit(row, "", org_name, UiKeys.ORG_NAME_MAX)
	le.name = "DisbandWord"
	var ok := UiBuild.button(row, "解散", Callable(), 80)
	ok.name = "DisbandOk"
	ok.disabled = true
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ok.add_theme_color_override(k, UiTheme.JY_RED)
	le.text_changed.connect(func(t: String): ok.disabled = not OrgUi.disband_word_ok(t, org_name))
	ok.pressed.connect(func():
		if OrgUi.disband_word_ok(le.text, org_name):
			send(UiKeys.I_ORG_DISBAND, { "confirm": true }, [ok], func():
				UiBuild.clear(detail_box)
				_refresh()))
	UiBuild.button(row, "取消", func(): UiBuild.clear(detail_box), 80)
	NumberedDialog.focus_later(le)

## 面板內的確認列（不另開確認框：確認框和這個面板同在對話框層，互斥）
func _confirm(text: String, ok_label: String, on_ok: Callable, danger := false) -> void:
	UiBuild.clear(detail_box)
	var l := UiBuild.label(detail_box, text, 15, true)
	l.name = "ConfirmText"
	var row := UiBuild.hbox(detail_box, 8)
	var ok := UiBuild.button(row, ok_label, Callable(), 80)
	ok.name = "ConfirmOk"
	if danger:
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			ok.add_theme_color_override(k, UiTheme.JY_RED)
	ok.pressed.connect(func():
		UiBuild.clear(detail_box)
		on_ok.call())
	var cancel := UiBuild.button(row, "取消", func(): UiBuild.clear(detail_box), 80)
	NumberedDialog.focus_later(cancel)

## 動作成功後重新要一次 org_info
func _refresh() -> void:
	if is_instance_valid(self) and visible:
		send(UiKeys.I_ORG_INFO, {})

# ---------------------------------------------------------------- 書吏
func _render_clerk() -> void:
	UiBuild.clear(clerk_box)
	clerk_box.visible = not clerk_menu.is_empty()
	if clerk_menu.is_empty():
		return
	var c := OrgUi.clerk(clerk_menu)
	UiBuild.accent(UiBuild.label(clerk_box, "%s：組織登記" % str(clerk_menu.get("npc_name", "書吏")), 16))
	var ft := UiBuild.label(clerk_box, OrgUi.found_text(c), 14, true)
	ft.name = "FoundText"
	var row := UiBuild.hbox(clerk_box, 6)
	# 重畫（org_info、角色表更新）時保留已打的名字
	var keep_found := found_edit.text if found_edit != null and is_instance_valid(found_edit) else ""
	found_edit = UiBuild.line_edit(row, keep_found, "組織名（2–8 字）", UiKeys.ORG_NAME_MAX)
	found_edit.name = "FoundName"
	var fb := UiBuild.button(row, "創立", Callable(), 80)
	fb.name = "Found"
	if c.get("can_found", true) == false or OrgUi.in_org(_sheet()):
		fb.disabled = true
		fb.tooltip_text = "你已經在組織裡" if OrgUi.in_org(_sheet()) else "目前不符合創立條件"
	fb.pressed.connect(func(): do_found(found_edit.text, fb))
	var ps: Variant = c.get("petitions", [])
	UiBuild.muted(UiBuild.label(clerk_box, "連署中的組織：", 14))
	var any := false
	for p in (ps if ps is Array else []):
		if not (p is Dictionary):
			continue
		any = true
		var r := UiBuild.hbox(clerk_box, 6)
		var l := UiBuild.label(r, OrgUi.petition_line(p), 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var oid := str(p.get("id", ""))
		var sb := UiBuild.button(r, "連署", Callable(), 70)
		sb.name = "Sign_" + oid
		if p.get("can_sign", true) == false or p.get("mine", false) == true or p.get("signed_by_me", false) == true:
			sb.disabled = true
			if p.get("mine", false) == true:
				sb.tooltip_text = "這是你發起的連署"
			elif p.get("signed_by_me", false) == true:
				sb.tooltip_text = "你已經簽過了"
			else:
				sb.tooltip_text = UiClient.reason_inline(str(p.get("reason", ""))) if str(p.get("reason", "")) != "" else "你不能連署這個組織"
		sb.pressed.connect(func(): send(UiKeys.I_ORG_SIGN, { "npc": npc_id(), "org": oid }, [sb]))
	if not any:
		UiBuild.muted(UiBuild.label(clerk_box, "（目前沒有）", 14))
	clerk_box.add_child(HSeparator.new())

func do_found(name: String, lock: Button = null) -> int:
	var why := OrgUi.name_block(name)
	if why != "":
		status_label.text = OrgUi.local_text(why)
		return -1
	return send(UiKeys.I_ORG_FOUND, { "npc": npc_id(), "name": name.strip_edges() }, [lock] if lock != null else [])
