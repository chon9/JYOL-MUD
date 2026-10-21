class_name NpcDialog
extends UiDialog
## NPC 對話框（M1_PLAN 3.12）：收到 npc_menu 開啟。對話文字（最近一則 talk 事件）＋服務按鈕：
## 交易 → shop_list；請教 → learn_list；住宿 → inn_rest；記錄 → set_respawn；驛站 → 路線 → travel；
## 拜師 → 確認 → join_sect；任務 → quests（AVAILABLE → quest_accept；READY → quest_turn_in；ACTIVE 只顯示進度，
## 沒有交付鈕）；用齋 → meal；切磋 → fight。closed == true 時服務灰色並顯示「打烊了」。
## 接／交任務成功後主機會重送 npc_menu（refresh == true）→ refresh_menu() 就地更新，保留對話文字與目前分頁。
## M3a（M3A_PLAN §6.12、§7.6、§7.7）：
## - 拜師 → 確認窗：門派名、性別與善惡等入門條件、門規摘要（sect_rules 文字）→ join_sect；
## - 叛教 → 兩段確認：先列出會減半的武功與其他後果，再要求輸入「叛教」兩字 → sect_betray { npc, confirm: true }；
## - 思過處（看守人）→ 囚犯清單與「贖人（十萬兩）」→ jail_ransom { npc, name }；
## - 試煉 → 顯示隊伍條件（人數、同隊同房）與能不能開始 → sect_trial；引路 → 直接送 npc_guide。

## M3b（M3B_PLAN §4.8、§7）：
## - 錢莊 → bank_open { npc }（主機回 bank_view，主畫面開錢莊窗）；鏢局 → window_requested("ESCORT")（主畫面開鏢局窗）；
## - 組織（衙門書吏）→ window_requested("ORG")（主畫面開組織面板的書吏段）；
## - 袋位 → 就地列出本派每一袋的條件與任務（SectUi.rank_page）；
## - npc_menu.beg 有值時多一個「乞討」選項 → beg { npc }；不能乞討時灰掉並寫原因（冷卻剩幾分、精神不足）。

## M3c（M3C_PLAN §5.8，WP-NPCPK）：npc_menu.attack 非空（{ ok, reason, label, warn }）時多一個紅字選項（例「滅派」「硬闖」）；
## 不能動手時灰掉並寫原因；按下先在文字框展開確認（內文同 Ctrl+點的確認框：NpcAttackUi.confirm_text），
## 紅色「動手」→ npc_attack { npc, mode: MIEPAI }。

## 版面（AUTHENTIC_UI_SPEC §8.7，680×416）：水墨暈染底；左側 180×240 黑底立繪框（ArtRegistry 的 NPC 全身圖，
## 沒有圖時畫墨色剪影）＋名牌；右側 INK 文字框：對話文字、金色分隔線、編號選項「1.交易」（滑過變黃、數字鍵 1–9 直接選）。

signal window_requested(kind: String, menu: Dictionary)

const PORTRAIT := Vector2(180, 240)
const ATTACK_CHOICE := "NPC_ATTACK"   # M3c：npc_menu.attack 的選項（不是服務）

var menu: Dictionary = {}
var talk_label: Label
var closed_label: Label
var services_box: VBoxContainer
var detail_box: VBoxContainer
var footer_box: HBoxContainer          # 捲動區外、固定在文字框底部的確認按鈕列（拜師；M3a 審查 C1）
var portrait: TextureRect
var portrait_note: Label            # 沒有這位 NPC 自己的立繪時：剪影下方小字「立繪待補」（審查：每位 NPC 都同一張圖）
var name_label: Label
var service_buttons: Dictionary = {}   # service -> Button
var choice_order: Array = []           # 編號順序的服務
var section := ""                      # 目前展開的服務分頁（"QUEST" 等；"" = 無）

func frame_kind() -> int:
	return UiFrame.Kind.INKWASH

func dialog_size() -> Vector2:
	return Vector2(680, 416)

func _build_body() -> void:
	title_label.visible = false
	close_button.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	var row := UiBuild.hbox(body, 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := UiBuild.vbox(row, 6)
	var pf := PanelContainer.new()
	var pst := StyleBoxFlat.new()
	pst.bg_color = Color.BLACK
	pst.border_color = UiTheme.JY_GOLD
	pst.set_border_width_all(2)
	pst.set_corner_radius_all(6)
	pst.set_content_margin_all(4)
	pf.add_theme_stylebox_override("panel", pst)
	left.add_child(pf)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pf.add_child(portrait)
	portrait_note = UiBuild.label(pf, "立繪待補", 12)
	portrait_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_note.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	portrait_note.add_theme_color_override("font_color", Color("8a7a5c"))
	portrait_note.visible = false
	var plate := PanelContainer.new()
	var nst := StyleBoxFlat.new()
	nst.bg_color = Color("1a120c")
	nst.border_color = UiTheme.JY_ROPE
	nst.set_border_width_all(2)
	nst.set_corner_radius_all(4)
	nst.set_content_margin_all(4)
	plate.add_theme_stylebox_override("panel", nst)
	left.add_child(plate)
	name_label = UiBuild.label(plate, "", 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var box := UiBuild.framed(row, UiFrame.Kind.INK)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := UiBuild.vbox(box, 4)
	var sc := UiBuild.scroll(inner)
	footer_box = UiBuild.hbox(inner, 8)
	footer_box.name = "Footer"
	footer_box.visible = false
	var v := UiBuild.vbox(sc, 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talk_label = UiBuild.label(v, "", 18, true)
	talk_label.custom_minimum_size = Vector2(380, 0)
	talk_label.add_theme_constant_override("line_spacing", 4)
	closed_label = UiBuild.error(UiBuild.label(v, "打烊了，明天請早。", 16))
	closed_label.visible = false
	v.add_child(HSeparator.new())
	services_box = UiBuild.vbox(v, 2)
	detail_box = UiBuild.vbox(v, 6)

func npc_id() -> String:
	return str(menu.get("npc", ""))

## p = npc_menu payload（3.8.2）
func open_menu(p: Dictionary, talk_text: String = "") -> void:
	ensure_built()
	menu = p
	title_label.text = str(p.get("npc_name", ""))
	name_label.text = str(p.get("npc_name", ""))
	_set_portrait(str(p.get("npc", "")))
	talk_label.text = TextRenderer.strip_channel_tag(talk_text) if talk_text != "" else "%s看了你一眼。" % str(p.get("npc_name", ""))
	talk_label.visible = true
	status_label.text = ""
	section = ""
	_build_services(p)
	visible = true

## 主機重送的 npc_menu（refresh == true）：只更新選單資料與服務按鈕，對話文字、狀態列與展開中的分頁保留
func refresh_menu(p: Dictionary) -> void:
	ensure_built()
	menu = p
	title_label.text = str(p.get("npc_name", ""))
	name_label.text = str(p.get("npc_name", ""))
	var keep := section
	_build_services(p)
	section = keep if keep in ["QUEST", "TRAVEL"] else ""
	if keep == "QUEST":
		show_quests()
	elif keep == "TRAVEL":
		show_routes()

## 立繪：ArtRegistry 的 NPC 全身圖；沒有圖時用一般人形染成墨色剪影
func _set_portrait(npc: String) -> void:
	var tex := ArtRegistry.unit_texture(npc, "NPC", "idle") if npc != "" else null
	portrait.modulate = Color.WHITE
	portrait_note.visible = tex == null
	if tex == null:
		tex = LookPicker.sheet_look_texture(UiClient.sheet())   # M3c（整合者，§3.4）：剪影用自己的外觀（取不到用 player_m）
		portrait.modulate = Color(0.25, 0.22, 0.2, 0.9)
	portrait.texture = tex

func _build_services(p: Dictionary) -> void:
	var is_closed := bool(p.get("closed", false))
	closed_label.visible = is_closed
	UiBuild.clear(services_box)
	_clear_detail()
	service_buttons.clear()
	choice_order.clear()
	var n := 0
	for svc in p.get("services", []):
		var s := str(svc)
		if s == "BETRAY" and p.get("betray", false) != true:
			continue   # §6.5：只有本派弟子對自己的掌門才看得到「叛教」（npc_menu.betray）
		var label := UiKeys.service_label(s)
		if s == "INN":
			label += "（%d 兩）" % UiBuild.num(p.get("inn_price", 0))
		elif s == "GUIDE" and p.get("guide", null) is Dictionary and str(p["guide"].get("room_name", "")) != "":
			label += "（往%s）" % str(p["guide"].get("room_name", ""))
		n += 1
		var row := UiBuild.hbox(services_box, 2)
		var num := UiBuild.accent(UiBuild.label(row, "%d." % n, 18))
		num.custom_minimum_size = Vector2(24, 0)
		var b := UiBuild.button(row, label)
		b.theme_type_variation = "ChoiceButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = is_closed
		if is_closed:
			UiBuild.muted(UiBuild.label(row, "（打烊了）", 14))
		elif s == "JOIN" and NpcDialog.joined_this_sect(p, UiClient.sheet()):
			# 已經是這一派的弟子：拜師灰掉並說明（M3a 審查 C10）
			b.disabled = true
			UiBuild.muted(UiBuild.label(row, "（已是本門弟子）", 14))
		b.pressed.connect(_on_service.bind(s, b))
		if s == "TEACH" and str(p.get("teach_blocked", "")) != "":
			b.tooltip_text = SectUi.block_text(str(p.get("teach_blocked", "")))
		service_buttons[s] = b
		choice_order.append(s)
	# M3b 乞討（不是服務；npc_menu.beg 有值才出現）
	var beg := SectUi.beg_state(p)
	if p.get("beg", null) is Dictionary:
		n += 1
		var brow := UiBuild.hbox(services_box, 2)
		var bnum := UiBuild.accent(UiBuild.label(brow, "%d." % n, 18))
		bnum.custom_minimum_size = Vector2(24, 0)
		var bb := UiBuild.button(brow, UiKeys.BEG_LABEL)
		bb.name = "BegButton"
		bb.theme_type_variation = "ChoiceButton"
		bb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var why := SectUi.beg_block_text(beg)
		bb.disabled = is_closed or why != ""
		if why != "":
			var wl := UiBuild.muted(UiBuild.label(brow, "（%s）" % why, 14))
			wl.name = "BegWhy"
			bb.tooltip_text = why
		bb.pressed.connect(_on_service.bind(UiKeys.BEG_CHOICE, bb))
		service_buttons[UiKeys.BEG_CHOICE] = bb
		choice_order.append(UiKeys.BEG_CHOICE)
	# M3c 滅派／硬闖（npc_menu.attack）
	var am: Variant = p.get("attack", {})
	if am is Dictionary and not (am as Dictionary).is_empty():
		n += 1
		var arow := UiBuild.hbox(services_box, 2)
		var anum := UiBuild.accent(UiBuild.label(arow, "%d." % n, 18))
		anum.custom_minimum_size = Vector2(24, 0)
		var ab := UiBuild.button(arow, str(am.get("label", "滅派")))
		ab.name = "AttackButton"
		ab.theme_type_variation = "ChoiceButton"
		ab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			ab.add_theme_color_override(k, UiTheme.JY_RED.lightened(0.15))
		ab.disabled = am.get("ok", false) != true
		if ab.disabled:
			var awhy := UiClient.reason_inline(str(am.get("reason", "")))
			var al := UiBuild.muted(UiBuild.label(arow, "（%s）" % awhy, 14))
			al.name = "AttackWhy"
			ab.tooltip_text = awhy
		elif str(am.get("warn", "")) != "":
			ab.tooltip_text = str(am.get("warn", ""))
		ab.pressed.connect(_on_service.bind(ATTACK_CHOICE, ab))
		service_buttons[ATTACK_CHOICE] = ab
		choice_order.append(ATTACK_CHOICE)
	n = _m3d_add_arts_choices(n, is_closed)   # M3d WP-LAW Day-0：WP-ARTS 的選單項（_m3d_arts_menu）
	if (p.get("services", []) as Array).is_empty() and not service_buttons.has(UiKeys.BEG_CHOICE) 			and not service_buttons.has(ATTACK_CHOICE):
		UiBuild.muted(UiBuild.label(services_box, "（閒聊而已）", 15))

## 角色表的門派就是這位 NPC 收徒的門派
static func joined_this_sect(p: Dictionary, sh: Dictionary) -> bool:
	var js := str(p.get("join_sect", ""))
	if js == "":
		return false
	var mine := str(sh.get("sect", ""))
	if mine == "":
		var si: Variant = sh.get("sect_info", {})
		mine = str((si as Dictionary).get("id", "")) if si is Dictionary else ""
	return mine == js

## 數字鍵 1–9 直接選
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	var i := int(k.keycode) - int(KEY_1)
	if i < 0 or i >= mini(9, choice_order.size()):
		return
	var b: Button = service_buttons[choice_order[i]]
	if not b.disabled:
		b.pressed.emit()
	get_viewport().set_input_as_handled()

## 清掉展開的分頁（含捲動區外的確認按鈕列）
func _clear_detail() -> void:
	UiBuild.clear(detail_box)
	if footer_box != null:
		UiBuild.clear(footer_box)
		footer_box.visible = false

func _on_service(svc: String, b: Button) -> void:
	_clear_detail()
	section = svc
	var npc := npc_id()
	match svc:
		"SHOP":
			send(UiKeys.I_SHOP_LIST, { "npc": npc }, [b])
		"TEACH":
			send(UiKeys.I_LEARN_LIST, { "npc": npc }, [b])
		"INN":
			send(UiKeys.I_INN_REST, { "npc": npc }, [b])
		"RESPAWN":
			send(UiKeys.I_SET_RESPAWN, { "npc": npc }, [b])
		"MEAL":
			send(UiKeys.I_MEAL, { "npc": npc }, [b])
		"FIGHT":
			send(UiKeys.I_FIGHT, { "npc": npc }, [b], close)
		"TRAVEL":
			show_routes()
		"JOIN":
			show_join()
		"QUEST":
			show_quests()
		"BETRAY":
			show_betray()
		"JAIL":
			show_jail()
		"TRIAL":
			show_trial()
		"GUIDE":
			send(UiKeys.I_NPC_GUIDE, { "npc": npc }, [b], close)
		# M3b
		"BANK":
			send(UiKeys.I_BANK_OPEN, { "npc": npc }, [b])
		"ESCORT":
			window_requested.emit("ESCORT", menu)
		"ORG":
			window_requested.emit("ORG", menu)
		"RANK":
			show_rank()
		UiKeys.BEG_CHOICE:
			send(UiKeys.I_BEG, { "npc": npc }, [b], _after_beg)
		ATTACK_CHOICE:
			show_attack()
		# M3d WP-LAW（M3D_PLAN §2）
		"BOARD":
			show_board()
		"LICENSE":
			show_license()
		"CLEANSE":
			open_cleanse()
		_:
			# M3d WP-LAW Day-0：WP-EVENTS 的服務（TOURNEY）與 WP-ARTS 的選單項
			if not _m3d_events_service(svc, npc):
				_m3d_arts_pressed(svc, b)

## 乞討成功：主機沒有重送選單時，本地先把「乞討」灰掉（同一位 NPC 有冷卻；§5.1.2 per_npc_cd_s）
func _after_beg() -> void:
	if not (menu.get("beg", null) is Dictionary):
		return
	var pr := SectUi.practice(SectUi.my_sect(UiClient.sheet()))
	menu["beg"] = { "ok": false, "reason": "beg_cooldown", "left_s": UiBuild.num(pr.get("per_npc_cd_s", 0)) }
	var keep := section
	_build_services(menu)
	section = keep

## M3c 滅派／硬闖的確認（M3C_PLAN §5.8 第 3 點）：同 Ctrl+點的確認文字＋紅色「動手」（捲動區外）
func show_attack() -> void:
	UiBuild.clear(detail_box)
	var am: Variant = menu.get("attack", {})
	if not (am is Dictionary) or (am as Dictionary).is_empty():
		return
	var entry := NpcAttackUi.entry_from_menu(menu)
	var l := UiBuild.label(detail_box, NpcAttackUi.confirm_text(entry, UiClient.sheet(), UiClient.region_view(), NpcAttackUi.MODE_MIEPAI), 15, true)
	l.name = "AttackText"
	l.add_theme_color_override("font_color", UiTheme.JY_RED.lightened(0.35))
	footer_box.visible = true
	var b := UiBuild.button(footer_box, NpcAttackUi.OK_LABEL)
	b.name = "AttackOk"
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, UiTheme.JY_RED.lightened(0.2))
	b.disabled = am.get("ok", false) != true
	b.pressed.connect(func():
		if not b.disabled:
			send(UiKeys.I_NPC_ATTACK, { "npc": npc_id(), "mode": NpcAttackUi.MODE_MIEPAI }, [b], close))
	UiBuild.button(footer_box, NpcAttackUi.CANCEL_LABEL, func(): _clear_detail())

## 袋位頁（陳長老；§7.5）：每一袋的條件、任務、升法
func show_rank() -> void:
	UiBuild.clear(detail_box)
	var mr: Variant = menu.get("rank", {})
	var rows := SectUi.rank_page(mr if mr is Dictionary else {}, UiClient.sheet())
	var head := SectUi.rank_text(UiClient.sheet())
	if head != "":
		UiBuild.accent(UiBuild.label(detail_box, "你目前的" + head, 16, true))
	for r in rows:
		var l := UiBuild.label(detail_box, SectUi.rank_page_line(r), 15, true)
		l.name = "Rank_%d" % int(r["rank"])
		if str(r.get("state", "")) in ["NEXT", "PENDING"]:
			l.add_theme_color_override("font_color", UiTheme.JY_SYS_YELLOW)
	if rows.is_empty():
		UiBuild.muted(UiBuild.label(detail_box, "（本派沒有袋位）", 15))

func show_routes() -> void:
	UiBuild.clear(detail_box)
	UiBuild.muted(UiBuild.label(detail_box, "要去哪裡？", 16))
	for r in menu.get("routes", []):
		if not (r is Dictionary):
			continue
		var b := UiBuild.button(detail_box, "%s（%d 兩）" % [str(r.get("to_name", r.get("to_room", ""))), UiBuild.num(r.get("price", 0))])
		b.pressed.connect(func(): send(UiKeys.I_TRAVEL, { "npc": npc_id(), "dest": str(r.get("to_room", "")) }, [b], close))
	if detail_box.get_child_count() <= 1:
		UiBuild.muted(UiBuild.label(detail_box, "（目前沒有路線）", 15))

## 拜師確認（§7.6）：門派名、性別與入門條件、門規摘要
func show_join() -> void:
	UiBuild.clear(detail_box)
	var sect_id := str(menu.get("join_sect", ""))
	var fallback := str(menu.get("sect_name", sect_id))
	var l := UiBuild.label(detail_box, SectUi.join_text(sect_id, fallback), 16, true)
	l.name = "JoinText"
	# 看得出來現在不符合的條件，紅字另列（例：男角色看到「只收女弟子」）；確定鈕變灰、原因放在提示（跟「贖人」一樣）。
	# 角色表看不出來的條件（任務、引薦書…）照樣由主機判定（M3a UI 審查 #1）
	var unmet := SectUi.unmet_conditions(sect_id, UiClient.sheet())
	if not unmet.is_empty():
		var u := UiBuild.label(detail_box, "你目前不符合：" + "；".join(unmet), 16, true)
		u.name = "JoinUnmet"
		u.add_theme_color_override("font_color", UiTheme.JY_RED.lightened(0.35))
	# 按鈕固定在捲動區外：條件與門規再長也看得到（M3a 審查 C1）
	footer_box.visible = true
	var b := UiBuild.button(footer_box, "確定拜師")
	b.name = "JoinOk"
	if not unmet.is_empty():
		b.disabled = true
		b.tooltip_text = "你目前不符合：" + "；".join(unmet)
	b.pressed.connect(func():
		if not b.disabled:
			send(UiKeys.I_JOIN_SECT, { "npc": npc_id() }, [b], func(): _clear_detail()))
	UiBuild.button(footer_box, "再想想", func(): _clear_detail())

## 叛教第一段：列出會減半的武功與其他後果（§6.5）
func show_betray() -> void:
	UiBuild.clear(detail_box)
	var sh := UiClient.sheet()
	var sect_id := str(sh.get("sect", SectUi.sect_info(sh).get("id", menu.get("join_sect", ""))))
	var l := UiBuild.label(detail_box, SectUi.betray_text(sh, sect_id, SectUi.halves_basics()), 15, true)
	l.name = "BetrayText"
	l.add_theme_color_override("font_color", UiTheme.JY_RED.lightened(0.35))
	var row := UiBuild.hbox(detail_box)
	var b := UiBuild.button(row, "我意已決")
	b.name = "BetrayStep1"
	b.pressed.connect(show_betray_confirm)
	UiBuild.button(row, "再想想", func(): UiBuild.clear(detail_box))

## 叛教第二段：輸入「叛教」兩字才能送出
func show_betray_confirm() -> void:
	UiBuild.clear(detail_box)
	UiBuild.label(detail_box, "此舉無法挽回。請在下面輸入「%s」兩字確認：" % UiKeys.BETRAY_WORD, 16, true)
	var row := UiBuild.hbox(detail_box)
	var le := UiBuild.line_edit(row, "", UiKeys.BETRAY_WORD, 4)
	le.name = "BetrayWord"
	le.custom_minimum_size = Vector2(120, 0)
	var b := UiBuild.button(row, "叛出師門")
	b.name = "BetrayOk"
	b.disabled = true
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, UiTheme.JY_RED)
	le.text_changed.connect(func(t: String): b.disabled = not SectUi.betray_word_ok(t))
	b.pressed.connect(func():
		if SectUi.betray_word_ok(le.text):
			send(UiKeys.I_SECT_BETRAY, { "npc": npc_id(), "confirm": true }, [b], close))
	UiBuild.button(row, "取消", func(): UiBuild.clear(detail_box))
	le.grab_focus.call_deferred()

## 思過處看守人（§6.6、§7.7）：囚犯與剩餘時間，「贖人（十萬兩）」
func show_jail() -> void:
	UiBuild.clear(detail_box)
	var j: Variant = menu.get("jail", null)
	if not (j is Dictionary):
		UiBuild.muted(UiBuild.label(detail_box, "（思過處裡沒有人）", 15))
		return
	var ransom := UiBuild.num(j.get("ransom", 100000))
	var money := UiBuild.num(UiClient.sheet().get("money", 0))
	var prisoners: Array = (j.get("prisoners", []) as Array) if j.get("prisoners", []) is Array else []
	if prisoners.is_empty():
		UiBuild.muted(UiBuild.label(detail_box, "（思過處裡沒有人）", 15))
		return
	UiBuild.muted(UiBuild.label(detail_box, "正在思過的人（任何人都能替人贖身，包括自己）：", 15))
	for pr in prisoners:
		if not (pr is Dictionary):
			continue
		var row := UiBuild.hbox(detail_box, 8)
		var nm := str(pr.get("name", ""))
		var l := UiBuild.label(row, "%s　剩 %s" % [nm, SectUi.duration_text(float(pr.get("left_s", 0)))], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := UiBuild.button(row, "贖人（%s）" % SectUi.money_text(ransom))
		b.name = "Ransom_" + nm
		if money < ransom:
			b.disabled = true
			b.tooltip_text = "銀兩不夠（要 %d 兩）" % ransom
			# 原因直接印在下面（以前只有滑鼠移上去才看得到；M3a 審查 C6）
			var why := UiBuild.error(UiBuild.label(detail_box, "銀兩不夠：贖人要 %s，你身上只有 %s。" % [
				SectUi.money_text(ransom), SectUi.money_text(money)], 15, true))
			why.name = "RansomWhy_" + nm
		b.pressed.connect(func(): send(UiKeys.I_JAIL_RANSOM, { "npc": npc_id(), "name": nm }, [b], func(): UiBuild.clear(detail_box)))

## 試煉（§6.9）：試煉名、隊伍人數與能不能開始
func show_trial() -> void:
	UiBuild.clear(detail_box)
	var tr: Variant = menu.get("trial", null)
	if not (tr is Dictionary):
		UiBuild.muted(UiBuild.label(detail_box, "（目前沒有試煉）", 15))
		return
	var pmin := UiBuild.num(tr.get("party_min", 1))
	var pmax := UiBuild.num(tr.get("party_max", pmin))
	var party := "%d 人" % pmin if pmin == pmax else "%d–%d 人" % [pmin, pmax]
	var l := UiBuild.label(detail_box, "%s：需要 %s 一同闖陣（同一隊伍、同在此處、都不在戰鬥中，每人都要合乎資格）。一旦開陣，不能逃跑。" % [
		str(tr.get("name", "試煉")), party], 16, true)
	l.name = "TrialText"
	var row := UiBuild.hbox(detail_box)
	var ok := bool(tr.get("ok", false))
	var b := UiBuild.button(row, "開始試煉")
	b.name = "TrialOk"
	b.disabled = not ok
	if not ok:
		var why := UiClient.reason_inline(str(tr.get("reason", "")))
		var wl := UiBuild.error(UiBuild.label(detail_box, why, 15, true))
		wl.name = "TrialWhy"
		b.tooltip_text = why
	b.pressed.connect(func(): send(UiKeys.I_SECT_TRIAL, { "npc": npc_id() }, [b], close))
	UiBuild.button(row, "再想想", func(): UiBuild.clear(detail_box))

func show_quests() -> void:
	UiBuild.clear(detail_box)
	var qs: Array = menu.get("quests", [])
	if qs.is_empty():
		UiBuild.muted(UiBuild.label(detail_box, "（沒有可接的任務）", 15))
	for q in qs:
		if not (q is Dictionary):
			continue
		var row := UiBuild.hbox(detail_box, 8)
		var state := str(q.get("state", ""))
		var l := UiBuild.label(row, "%s　[%s]" % [str(q.get("name", q.get("id", ""))), UiKeys.QUEST_STATE_LABELS.get(state, state)], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var qid := str(q.get("id", ""))
		match state:
			"AVAILABLE":
				if StoryUi.has_offer(qid):
					var bt := UiBuild.button(row, "詳談")
					bt.name = "QuestTalk_" + qid
					bt.tooltip_text = "聽聽對方怎麼說，再決定要不要幫忙"
					bt.pressed.connect(func(): send(UiKeys.I_QUEST_TALK, { "npc": npc_id(), "quest": qid }, [bt]))
				else:
					var b := UiBuild.button(row, "接受")
					b.pressed.connect(func(): send(UiKeys.I_QUEST_ACCEPT, { "npc": npc_id(), "quest": qid }, [b], _mark_quest.bind(qid, "ACTIVE")))
			"ACTIVE":
				if StoryUi.npc_has_current_objective(qid, npc_id(), UiClient.sheet()):
					var ba := UiBuild.button(row, "交談")
					ba.name = "QuestTalk_" + qid
					ba.pressed.connect(func(): send(UiKeys.I_QUEST_TALK, { "npc": npc_id(), "quest": qid }, [ba]))
			"LOCKED":
				# 說清楚差什麼（擁有者回報：只看到 [LOCKED]，不知道為什麼）
				var why := str(q.get("locked_why", ""))
				if why != "":
					var wl := UiBuild.muted(UiBuild.label(detail_box, "　　需要：" + why, 14))
					wl.name = "QuestLockedWhy_" + qid
					l.tooltip_text = "還不能接：需要" + why
			"COOLDOWN":
				var left := StoryUi.cooldown_left(q, UiClient.sheet())
				if left > 0.0:
					l.text = "%s　[冷卻中，%s後可再接]" % [str(q.get("name", qid)), StoryUi.span_text(left)]
			"READY":
				if bool(q.get("resume", false)):
					# M3b 審查 3：護送對象走散 → 重新交給你（quest_talk）
					var b3 := UiBuild.button(row, "重新領回")
					b3.name = "QuestResume_" + qid
					b3.pressed.connect(func(): send(UiKeys.I_QUEST_TALK, { "npc": npc_id(), "quest": qid }, [b3]))
				else:
					var b2 := UiBuild.button(row, "交付")
					b2.pressed.connect(func(): send(UiKeys.I_QUEST_TURN_IN, { "npc": npc_id(), "quest": qid }, [b2], _mark_quest.bind(qid, "")))
			# ACTIVE：主機判定還不能在這裡交付（東西不夠、或要交給別人），不給按鈕；進度看任務面板

## 送出成功、主機的 npc_menu（refresh）還沒到之前先在本地更新：接下 → ACTIVE；交付 → 先拿掉
## （intent_result 比事件早到；之後的 refresh 會以主機的真實狀態覆蓋）
func _mark_quest(qid: String, state: String) -> void:
	var qs: Array = menu.get("quests", [])
	for i in range(qs.size() - 1, -1, -1):
		var q: Variant = qs[i]
		if q is Dictionary and str(q.get("id", "")) == qid:
			if state == "":
				qs.remove_at(i)
			else:
				q["state"] = state
	show_quests()

# ==== M3d WP-LAW ====（M3D_PLAN §2：佈告欄、官爺、天師與半仙；§9.2 其他 WP 的預留呼叫行）
var cleanse_dialog: CleanseDialog = null
## WP-ARTS 的選單項（choice -> { label, intent, args }），由 _m3d_add_arts_choices 填
var m3d_arts_items: Dictionary = {}

## 佈告欄：觀看懸賞名單；其他排名（十大惡人等）本包「尚未開放」（M3D_PLAN §1.2）
func show_board() -> void:
	UiBuild.clear(detail_box)
	var b := UiBuild.button(detail_box, UiKeys.BOARD_MENU_BOUNTY)
	b.name = "BoardBounty"
	b.pressed.connect(func(): send(UiKeys.I_BOUNTY_BOARD, { "npc": npc_id() }, [b]))
	for t in ["十大惡人", "十大善人", "十大富豪"]:
		var row := UiBuild.hbox(detail_box, 6)
		var d := UiBuild.button(row, t)
		d.disabled = true
		UiBuild.muted(UiBuild.label(row, "（%s）" % UiKeys.BOARD_RANKS_LOCKED, 14))

## 官爺：領執照（100 兩）、領賞、觀看懸賞名單；耳聾的那位主機一律回 license_deaf
func show_license() -> void:
	UiBuild.clear(detail_box)
	var law: Variant = UiClient.sheet().get("law", {})
	var lw: Dictionary = law if law is Dictionary else {}
	var licensed: bool = lw.get("licensed", false) == true
	var claims := UiBuild.num(lw.get("claims", 0))
	var st := UiBuild.label(detail_box, "你%s賞金獵人執照。%s" % ["持有" if licensed else "沒有",
		"待領賞金 %s 兩。" % BountyDialog.money_text(claims) if claims > 0 else ""], 15, true)
	st.name = "LicenseState"
	var b1 := UiBuild.button(detail_box, "領取賞金獵人執照（%d 兩）" % BountyRules.LICENSE_FEE)
	b1.name = "LicenseGet"
	# M3d 審查：領不到時直接灰掉並寫原因（原本只有「已經有執照」會灰，PK值、在名單上、錢不夠都要按了才知道）
	var why := NpcDialog.license_block(UiClient.sheet(), licensed)
	if why != "":
		b1.disabled = true
		b1.tooltip_text = why
		var wl := UiBuild.muted(UiBuild.label(detail_box, why, 13, true))
		wl.name = "LicenseWhy"
	b1.pressed.connect(func(): send(UiKeys.I_BOUNTY_LICENSE, { "npc": npc_id() }, [b1], show_license))
	var b2 := UiBuild.button(detail_box, "領賞（%s 兩）" % BountyDialog.money_text(claims))
	b2.name = "LicenseClaim"
	if claims <= 0:
		b2.disabled = true
		b2.tooltip_text = BountyDialog.NO_CLAIM_TIP
		# M3d 審查第三輪：灰掉的原因直接寫在按鈕下面（原本只有滑鼠提示）
		var cw := UiBuild.muted(UiBuild.label(detail_box, BountyDialog.NO_CLAIM_TIP, 13, true))
		cw.name = "LicenseClaimWhy"
	b2.pressed.connect(func(): send(UiKeys.I_BOUNTY_CLAIM, { "npc": npc_id() }, [b2], show_license))
	var b3 := UiBuild.button(detail_box, UiKeys.BOARD_MENU_BOUNTY)
	b3.name = "LicenseBoard"
	b3.pressed.connect(func(): send(UiKeys.I_BOUNTY_BOARD, { "npc": npc_id() }, [b3]))
	UiBuild.muted(UiBuild.label(detail_box, "只有身上沒有 PK值、自己不在名單上的人能領執照；領照後只要身上有了 PK值，執照就自動失效。持照緝拿名單上的人不算惡意 PK。", 13, true))

## 領執照灰掉的原因（"" ＝可以領）：已有執照／PK值 > 0／自己在名單上／錢不夠（BountyRules.license_reason 的順序）
static func license_block(sh: Dictionary, licensed: bool) -> String:
	if licensed:
		return "你已經有執照了"
	var law: Variant = sh.get("law", {})
	var listed: bool = law is Dictionary and (law as Dictionary).get("listed", false) == true
	match BountyRules.license_reason(UiBuild.num(sh.get("pk", 0)), listed, UiBuild.num(sh.get("money", 0))):
		"license_pk":
			return "你身上有 PK值，官爺不發執照（PK值要先消到 0）"
		"license_listed":
			return "你自己就在懸賞名單上，領不到執照"
		"not_enough_money":
			return "身上的銀兩不夠 %d 兩" % BountyRules.LICENSE_FEE
	return ""

## 往上找有 m3d_add_dialog 的主畫面（單獨測 NPC 視窗時沒有 → null）
func _main_screen() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("m3d_add_dialog"):
			return n
		n = n.get_parent()
	return null

## 天師／半仙：開消災視窗（NPC 列的 cleanse 由 npc_menu 不帶 → 看名字判斷：半仙＝PK、其餘＝殺氣）
func open_cleanse() -> void:
	if cleanse_dialog == null:
		cleanse_dialog = CleanseDialog.new()
		cleanse_dialog.name = "CleanseDialog"
		cleanse_dialog.gate = gate
		cleanse_dialog.visible = false
		var host_node: Node = get_parent() if get_parent() != null else self
		host_node.add_child(cleanse_dialog)
		# M3d 審查：加入主畫面的視窗清單（Esc 關、與其他視窗互斥）
		var ms := _main_screen()
		if ms != null:
			ms.call("m3d_add_dialog", cleanse_dialog)
	var kind := "PK" if str(menu.get("cleanse", "")) == "PK" or npc_id().begins_with("n_law_banxian") else "KILLING"
	visible = false
	cleanse_dialog.open_for(menu, kind)

# ---- 預留給其他 WP（§9.2）：WP-LAW Day-0 只寫呼叫行與空函式，函式本體由該 WP 改 ----
## WP-ARTS 的選單項：回 Array of { "choice": String（唯一，建議 "ARTS_*"）, "label": String, "intent": String,
## "args": Dictionary（送出時自動補 npc）, "why": String（非空＝灰掉並顯示原因） }
func _m3d_add_arts_choices(n: int, is_closed: bool) -> int:
	m3d_arts_items.clear()
	for it in _m3d_arts_menu(npc_id()):
		if not (it is Dictionary) or str(it.get("choice", "")) == "":
			continue
		var c := str(it["choice"])
		n += 1
		var row := UiBuild.hbox(services_box, 2)
		var num := UiBuild.accent(UiBuild.label(row, "%d." % n, 18))
		num.custom_minimum_size = Vector2(24, 0)
		var b := UiBuild.button(row, str(it.get("label", c)))
		b.name = "Arts_" + c
		b.theme_type_variation = "ChoiceButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var why := str(it.get("why", ""))
		b.disabled = is_closed or why != ""
		if why != "":
			UiBuild.muted(UiBuild.label(row, "（%s）" % why, 14))
			b.tooltip_text = why
		b.pressed.connect(_on_service.bind(c, b))
		service_buttons[c] = b
		choice_order.append(c)
		m3d_arts_items[c] = it
	return n

func _m3d_arts_pressed(svc: String, b: Button) -> void:
	var it: Variant = m3d_arts_items.get(svc)
	if not (it is Dictionary) or str(it.get("intent", "")) == "":
		return
	var args: Dictionary = (it.get("args", {}) as Dictionary).duplicate() if it.get("args") is Dictionary else {}
	if not args.has("npc"):
		args["npc"] = npc_id()
	send(str(it["intent"]), args, [b])

# ==== M3d WP-ARTS ====（M3D_PLAN §9.2：血刀弟子的「恐嚇」選單項；格式見 _m3d_add_arts_choices）
## 只對血刀弟子、只對合格的對象（ArtsRules.intimidate_target_ok：故事／功能／商店／任務 NPC，不是本派、衙門、佈告欄……）顯示；
## 今天恐嚇過、精神不足、任務對象等由主機判斷（回原因碼，照一般錯誤顯示）。
const ARTS_INTIMIDATE := "ARTS_INTIMIDATE"

func _m3d_arts_menu(npc: String) -> Array:
	if SectUi.my_sect(UiClient.sheet()) != ArtsRules.INTIMIDATE_SECT:
		return []
	var row := UiClient.row("npcs", npc)
	if not ArtsRules.intimidate_target_ok(row, NpcDialog.arts_npc_sect(row), ArtsRules.INTIMIDATE_SECT, false):
		return []
	return [{ "choice": ARTS_INTIMIDATE, "label": "恐嚇", "intent": "intimidate", "args": {}, "why": "" }]

## NPC 的門派（客戶端版的 SectSystem.npc_sect：join_sect，否則看 NPC 所在地區是不是某派的 gate_region）
static func arts_npc_sect(row: Dictionary) -> String:
	var js := str(row.get("join_sect", ""))
	if js != "":
		return js
	var region := str(row.get("region", ""))
	var sects := UiClient.table("sects")
	for sid in sects:
		if region != "" and str((sects[sid] as Dictionary).get("gate_region", "")) == region:
			return str(sid)
	return ""

# ==== M3d WP-EVENTS ====（M3D_PLAN §9.2：服務 TOURNEY 的按鈕處理；npc＝NPC id；回 true＝已處理）
## 「比武報名」：記下報名員並要一份 tourney_state；主畫面收到後打開 TourneyDialog（main_screen 的 WP-EVENTS 區塊）
func _m3d_events_service(svc: String, npc: String) -> bool:
	if svc != "TOURNEY":
		return false
	TourneyDialog.request(npc if npc != "" else npc_id())
	send(UiKeys.I_TOURNEY_INFO, {})
	return true
