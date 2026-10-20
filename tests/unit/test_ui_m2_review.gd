extends "res://tests/test_case.gd"
## M2 審查修正（2026-10-18，M2_PLAN 8.3）的介面回歸：天外飛仙不能關、強制 PK 連結鍵可改、確認框的善惡說明、
## 頻道選單（只列發話頻道、耗水標記）、提示框不被視窗蓋住、隊伍動作要確認、戰鬥種類「打鬥」、卷軸主題的分頁與 TextEdit、
## 飛鴿未讀標記、屍體視窗、提示倒數不換行、伺服器面板列角色名、not_connected 的文字。

const M2 := preload("res://tests/unit/test_ui_m2.gd")

var _nodes: Array = []

func before_each() -> void:
	UiSettings.reset_for_tests(true)

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	UiSettings.reset_for_tests(true)
	await tree.process_frame

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _frame() -> void:
	await tree.process_frame

func _gate(sent: Array) -> IntentGate:
	var g := IntentGate.new()
	_add(g)
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		var seq := sent.size()
		g.resolve.call_deferred(seq, true, "")
		return seq)
	return g

# ---------------------------------------------------------------- 規則 1：天外飛仙不能關

func test_gm_channel_cannot_be_turned_off() -> void:
	UiSettings.set_value("ui.channels", { "天外飛仙": false, "千里傳音": false })   # 舊版設定檔存了「關」
	var ml := MessageLog.new()
	_add(ml)
	await _frame()
	assert_true(ml.channel_enabled("天外飛仙"), "saved 'off' is ignored for 天外飛仙")
	assert_false(ml.channel_enabled("千里傳音"), "other channels keep the saved value")
	ml.set_channel_enabled("天外飛仙", false)
	assert_true(ml.channel_enabled("天外飛仙"), "set_channel_enabled ignores the locked channel")
	ml.add_event({ "ch": "GM", "key": "chat_gm", "p": { "from": "主機", "from_peer": 0, "text": "今晚維修" } })
	assert_true(ml.text.get_parsed_text().contains("今晚維修"), "GM text always shown")
	# 系統窗：天外飛仙的開關灰掉、按著
	var sp := SystemPanel.new()
	sp.message_log = ml
	_add(sp)
	await _frame()
	sp.show_page("頻道開關")
	await _frame()
	var cb := sp.find_child("Channel_天外飛仙", true, false) as CheckButton
	assert_true(cb != null, "toggle exists")
	if cb != null:
		assert_true(cb.disabled and cb.button_pressed, "locked on")
	var other := sp.find_child("Channel_輕聲細語", true, false) as CheckButton
	assert_true(other != null and not other.disabled, "other toggles still work")

# ---------------------------------------------------------------- 規則 3：連結鍵

func test_force_pk_key_is_configurable() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.ctrl_pressed = true
	assert_eq(UiSocial.pk_key(), "ctrl", "default Ctrl")
	assert_true(UiSocial.pk_modifier_down(ev))
	UiSettings.set_value(UiSocial.PK_KEY_SETTING, "alt")
	assert_false(UiSocial.pk_modifier_down(ev), "Ctrl no longer fires once rebound to Alt")
	ev.ctrl_pressed = false
	ev.alt_pressed = true
	assert_true(UiSocial.pk_modifier_down(ev), "Alt fires")
	assert_true(UiSocial.act_label(UiSocial.ACT_FORCE_PK).contains("Alt"), UiSocial.act_label(UiSocial.ACT_FORCE_PK))
	assert_true(UiSocial.player_tip({ "name": "阿甲" }).contains("Alt+左鍵"))
	UiSettings.set_value(UiSocial.PK_KEY_SETTING, "bogus")
	assert_eq(UiSocial.pk_key(), "ctrl", "unknown value falls back to Ctrl")
	# 場景卷軸：記錄的是連結鍵，不是固定的 Ctrl
	UiSettings.set_value(UiSocial.PK_KEY_SETTING, "shift")
	var sp := ScenePanel.new()
	_add(sp)
	await _frame()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.ctrl_pressed = true
	sp._on_player_input(click)
	assert_false(sp._ctrl_click, "Ctrl ignored when the key is Shift")
	click.ctrl_pressed = false
	click.shift_pressed = true
	sp._on_player_input(click)
	assert_true(sp._ctrl_click, "Shift+click → force PK")

func test_system_panel_has_pk_key_option() -> void:
	var sp := SystemPanel.new()
	_add(sp)
	await _frame()
	sp.show_page("特殊開關")
	await _frame()
	var ob := sp.find_child("PkKeyOption", true, false) as OptionButton
	assert_true(ob != null, "PkKeyOption on the 特殊開關 page")
	if ob == null:
		return
	assert_eq(ob.item_count, UiSocial.PK_KEYS.size())
	ob.select(1)
	ob.item_selected.emit(1)
	assert_eq(UiSocial.pk_key(), UiSocial.PK_KEYS[1], "saved to settings")

# ---------------------------------------------------------------- 規則 4：確認框的善惡說明

func test_force_pk_confirm_text_depends_on_alignment() -> void:
	var evil := UiSocial.force_pk_confirm_text({ "name": "惡人甲", "align": "EVIL" })
	assert_true(evil.contains("惡人甲") and evil.contains("變好"), evil)
	assert_false(evil.contains("變差"), evil)
	for al in ["NEUTRAL", "GOOD", ""]:
		var t := UiSocial.force_pk_confirm_text({ "name": "乙", "align": al })
		assert_true(t.contains("變差"), "%s: %s" % [al, t])
	var ms: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	ms.gate.set_sender(func(_k, _a): return -1)
	ms.apply_sheet(M2.sheet_m2())
	ms.apply_view(M2.view_m2(true))
	ms._on_player_action("force_pk", M2.view_m2()["players"][1])   # 阿甲 align EVIL
	assert_true(ms.confirm_dialog.message_label.text.contains("變好"), ms.confirm_dialog.message_label.text)

## M2 審查：確認框要寫出殺氣、善惡為負的守衛條件；依自己的善惡算出殺後會不會挨官兵
func test_force_pk_confirm_text_warns_guards_and_killing_intent() -> void:
	var t := UiSocial.force_pk_confirm_text({ "name": "乙", "align": "NEUTRAL" })
	assert_true(t.contains("殺氣 +100"), t)
	assert_true(t.contains("善惡變負") and t.contains("超過 3"), t)
	assert_true(t.contains("善惡變差（%d）" % MoralityPk.FORCED_KILL_MORALITY), t)
	var risky := UiSocial.force_pk_confirm_text({ "name": "乙", "align": "NEUTRAL" }, { "morality": 0, "pk": 0 })
	assert_true(risky.contains("下次進出城就會有官兵出手"), risky)
	var safe := UiSocial.force_pk_confirm_text({ "name": "乙", "align": "NEUTRAL" }, { "morality": 200, "pk": 0 })
	assert_false(safe.contains("下次進出城"), safe)
	var wanted := UiSocial.force_pk_confirm_text({ "name": "乙", "align": "NEUTRAL" }, { "morality": 900, "pk": 3 })
	assert_true(wanted.contains("PK 值 4"), wanted)

# ---------------------------------------------------------------- 介面 5：頻道選單

func test_channel_menu_lists_talk_channels_with_water_tags() -> void:
	assert_eq(MessageLog.WATER_TALK.map(func(c): return MessageLog.TALK_CH[c]), SocialSystem.WATER_CHANNELS,
		"water tags match the host's WATER_CHANNELS")
	var ml := MessageLog.new()
	_add(ml)
	var row := HBoxContainer.new()
	_add(row)
	ml.build_input(row)
	await _frame()
	var pm := ml.channel_button.get_popup()
	ml._refresh_channel_menu()
	assert_eq(pm.item_count, MessageLog.TALK_CHANNELS.size(), "only the 8 talk channels")
	var texts: Array = []
	for i in pm.item_count:
		texts.append(pm.get_item_text(i))
	assert_has(texts, "千里傳音（耗水）")
	assert_has(texts, "傳音入密")
	assert_has(texts, "江湖謠言（耗水）")
	assert_has(texts, "天外飛仙（只限主機）")
	assert_false(texts.any(func(t): return str(t).contains("尚未開放")), "display-only channels left out")
	# id 仍是 CHANNELS 的索引：選「隊伍交談」
	pm.id_pressed.emit(MessageLog.CHANNELS.find("隊伍交談"))
	assert_eq(ml.talk_channel, "隊伍交談")
	assert_true(ml.input.placeholder_text.contains("耗水"), ml.input.placeholder_text)
	# M2 審查：目前的頻道在選單裡打勾；耗水頻道的頻道鈕染色、提示寫明
	ml._refresh_channel_menu()
	var checked: Array = []
	for i in pm.item_count:
		if pm.is_item_checked(i):
			checked.append(pm.get_item_id(i))
	assert_eq(checked, [MessageLog.CHANNELS.find("隊伍交談")], "only the current channel is checked")
	assert_true(pm.is_item_radio_checkable(0), "radio items")
	assert_true(ml.channel_button.has_theme_color_override("font_color"), "water channel tinted")
	assert_true(ml.channel_button.tooltip_text.contains("喝水"), ml.channel_button.tooltip_text)
	ml.set_talk_channel("傳音入密")
	assert_false(ml.input.placeholder_text.contains("耗水"), "whisper costs no water")
	assert_false(ml.channel_button.has_theme_color_override("font_color"), "no tint for whisper")
	# 選單開在頻道鈕上方，不蓋住按鈕（否則放開滑鼠就選中蓋在按鈕上的那一項）
	row.position = Vector2(200, 600)
	await _frame()
	ml.channel_button.show_popup()
	await _frame()
	await _frame()
	var top: float = ml.channel_button.get_screen_position().y
	assert_true(pm.visible, "popup shown")
	assert_true(float(pm.position.y + pm.size.y) <= top + 1.0, "popup bottom %d above button top %s" % [pm.position.y + pm.size.y, top])
	pm.hide()

# ---------------------------------------------------------------- 介面 1：提示框不被視窗蓋住

func test_prompts_drawn_above_dialogs_and_dialogs_move_down() -> void:
	var ms: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	ms.gate.set_sender(func(_k, _a): return -1)
	assert_true(ms.pending_prompts.get_index() > ms.dialog_layer.get_index(), "prompts after (above) the dialog layer")
	var s: Dictionary = M2.sheet_m2()
	s[CooldownTracker.RX_KEY] = Time.get_ticks_msec()
	s["pending"] = { "party_invite": {}, "challenges": [ { "from_char": "ch_y", "name": "岳不群", "left_s": 30 } ] }
	ms.apply_sheet(s)
	await _frame()
	await _frame()
	assert_true(ms.pending_prompts.visible)
	var band: float = ms.prompt_band_bottom()
	assert_true(band > 8.0, "band bottom %s" % band)
	assert_eq(ms.dialog_layer.offset_top, band, "dialog layer starts below the prompt band")
	ms.open_mail()
	await _frame()
	await _frame()
	var md: Control = ms.mail_dialog
	assert_true(md.get_global_rect().position.y >= ms.pending_prompts.get_global_rect().end.y - 0.5,
		"mail dialog %s does not overlap prompts %s" % [str(md.get_global_rect()), str(ms.pending_prompts.get_global_rect())])
	# 提示沒了：對話框層回到頂端
	ms.apply_sheet(M2.sheet_m2())
	await _frame()
	assert_eq(ms.dialog_layer.offset_top, 0.0)

# ---------------------------------------------------------------- 介面 2：隊伍動作要確認

func test_party_actions_go_through_confirm() -> void:
	var pf := PartyFrame.new()
	_add(pf)
	await _frame()
	var sent: Array = []
	pf.gate = _gate(sent)
	var asked: Array = []
	pf.confirm_requested.connect(func(title, msg, _ok, cb): asked.append([title, msg, cb]))
	pf.apply_sheet(M2.party_sheet(true))
	var row: HBoxContainer = pf.member_rows["ch_a"]
	var kick := row.find_child("Kick_ch_a", false, false) as Button
	var lead := row.find_child("Lead_ch_a", false, false) as Button
	assert_true(kick != null and lead != null)
	assert_true(kick.get_index() - lead.get_index() > 1, "a gap between 領 and 踢")
	kick.pressed.emit()
	lead.pressed.emit()
	pf.leave_button.pressed.emit()
	assert_eq(sent.size(), 0, "nothing sent before confirming")
	assert_eq(asked.size(), 3)
	assert_true(str(asked[0][1]).contains("阿甲"))
	(asked[0][2] as Callable).call()
	assert_eq(sent[0], ["party_kick", { "target": "ch_a" }])
	# 主畫面：選單的請出／移交也要確認
	var ms: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	var ms_sent: Array = []
	ms.gate.set_sender(func(kind, args):
		ms_sent.append([kind, args])
		return -1)
	ms.apply_sheet(M2.party_sheet(true))
	ms._on_player_action("kick", { "char_id": "ch_a", "name": "阿甲" })
	assert_true(ms.confirm_dialog.visible)
	assert_eq(ms_sent.size(), 0)
	ms.confirm_dialog.confirm()
	assert_eq(ms_sent[0], ["party_kick", { "target": "ch_a" }])
	(ms.party_frame.member_rows["ch_a"].find_child("Lead_ch_a", false, false) as Button).pressed.emit()
	assert_true(ms.confirm_dialog.visible, "party frame routes to the main confirm dialog")
	assert_eq(ms_sent.size(), 1)

# ---------------------------------------------------------------- 介面 3：打 NPC 不是切磋

func test_npc_fight_not_labelled_sparring() -> void:
	assert_eq(UiKeys.BATTLE_KIND_LABELS["FIGHT"], "打鬥")
	var t := UiSocial.battle_label({ "kind": "FIGHT", "names": [["丙"], ["山賊頭目"]] })
	assert_false(t.contains("切磋"), t)

# ---------------------------------------------------------------- 介面 4：卷軸主題

func test_paper_theme_tabs_and_text_edit_readable() -> void:
	var t := UiTheme.build_paper()
	var sel := t.get_stylebox("tab_selected", "TabBar") as StyleBoxFlat
	assert_true(sel != null, "paper TabBar tab_selected defined")
	if sel != null:
		var ink := t.get_color("font_selected_color", "TabBar")
		assert_true(sel.bg_color.get_luminance() - ink.get_luminance() > 0.5, "ink on light tab")
	var te := t.get_stylebox("normal", "TextEdit") as StyleBoxFlat
	assert_true(te != null and te.bg_color.get_luminance() > 0.8, "TextEdit is a light field")
	assert_eq(t.get_color("font_color", "TextEdit"), UiTheme.INK)
	var le_focus := t.get_stylebox("focus", "LineEdit") as StyleBoxFlat
	assert_true(le_focus != null and le_focus.bg_color.get_luminance() > 0.8, "focused LineEdit stays light on paper")

# ---------------------------------------------------------------- 介面 9：未讀標記

func test_mail_unread_marker_not_emoji() -> void:
	var d := MailDialog.new()
	d.gate = _gate([])
	_add(d)
	await _frame()
	d.apply_mail_list([ { "id": "ml_1", "from_name": "阿甲", "text": "x", "sent_clock": "第 1 日", "read": false } ])
	var t: String = (d.mail_buttons["ml_1"] as Button).text
	assert_false(t.contains("●"), t)
	assert_true(t.begins_with(MailDialog.UNREAD_MARK), t)

# ---------------------------------------------------------------- 介面 7：屍體視窗

func test_corpse_dialog_layout_and_auth_list() -> void:
	var d := CorpseDialog.new()
	d.gate = _gate([])
	_add(d)
	await _frame()
	d.open_corpse({ "id": "cp_1", "owner_name": "路人", "mine": false, "n_items": 3, "can_loot": false, "public": false, "left_s": 300 })
	assert_false(d.items_scroll.visible, "no duplicate protection text in the item area")
	assert_false(d.take_all_button.visible, "no grey full-width slab")
	assert_eq(d.items_box.get_child_count(), 0)
	assert_eq(d.info_label.text.count("保護期"), 1)
	d.open_corpse({ "id": "cp_2", "owner_name": "我", "mine": true, "n_items": 1, "can_loot": true, "public": false, "left_s": 500,
		"authorized_names": ["阿甲", "小乙"], "auth_max": 4, "items": [ { "uid": "it_9", "id": "a_buyi", "name": "布衣", "n": 1 } ] })
	assert_true(d.items_scroll.visible and d.take_all_button.visible)
	assert_true(d.items_scroll.custom_minimum_size.y < 160.0, "item area sized to one row")
	assert_true(d.auth_list_label.visible)
	assert_true(d.auth_list_label.text.contains("2／4") and d.auth_list_label.text.contains("阿甲"), d.auth_list_label.text)
	assert_eq(d.take_all_button.size_flags_horizontal, Control.SIZE_SHRINK_END)
	var full := CorpseDialog.auth_list_text({ "authorized_names": ["甲", "乙", "丙", "丁"], "auth_max": 4 })
	assert_true(full.contains("名額已滿"), full)
	assert_true(CorpseDialog.auth_list_text({ "auth_max": 4 }).contains("還沒有"))

# ---------------------------------------------------------------- 介面 8：倒數不換行

func test_prompt_countdown_is_separate_unwrapped_label() -> void:
	var pp := PendingPrompts.new()
	pp.gate = _gate([])
	_add(pp)
	var s: Dictionary = M2.sheet_m2()
	s[CooldownTracker.RX_KEY] = Time.get_ticks_msec()
	s["pending"] = { "party_invite": { "from_char": "ch_d", "name": "東方不敗", "left_s": 60 }, "challenges": [] }
	pp.apply_sheet(s)
	var entry: Dictionary = pp.rows["party:ch_d"]
	assert_eq((entry["label"] as Label).text, "東方不敗邀請你加入隊伍")
	# M2 第三輪審查：主文整句一行、不換行（不會斷成「…加／入隊伍」）
	assert_eq((entry["label"] as Label).autowrap_mode, TextServer.AUTOWRAP_OFF, "head does not wrap")
	assert_true((entry["label"] as Label).get_parent() != cd_parent_of(entry), "head has its own line")
	var cd := entry["countdown"] as Label
	assert_eq(cd.text, "（60 秒）")
	assert_eq(cd.autowrap_mode, TextServer.AUTOWRAP_OFF)
	assert_eq(UiSocial.pending_text(UiSocial.pending_rows(s, Time.get_ticks_msec())[0]), "東方不敗邀請你加入隊伍（60 秒）")

# ---------------------------------------------------------------- 介面 6：伺服器面板列角色名

func test_server_panel_lists_character_names() -> void:
	var t := UiSocial.admin_player_label({ "peer": 101, "name": "俠客Uibot Rv 1", "char_name": "介面俠客", "identity_short": "local_cd", "is_admin": false })
	assert_true(t.begins_with("介面俠客"), t)
	assert_true(t.contains("俠客Uibot Rv 1") and t.contains("local_cd"), t)
	assert_true(UiSocial.admin_player_label({ "name": "旁觀", "identity_short": "x" }).begins_with("（未選角）"))
	var d := ServerOptionsDialog.new()
	d.gate = _gate([])
	_add(d)
	await _frame()
	var opts: Dictionary = M2.server_opts()
	opts["info"]["players"][1]["char_name"] = "阿甲俠"
	d.apply_options(opts)
	var found := false
	for l in d.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("阿甲俠"):
			found = true
	assert_true(found, "player row starts with the character name")

# ---------------------------------------------------------------- 介面 10：not_connected

func test_not_connected_has_text() -> void:
	var t := UiClient.reason_inline("not_connected")
	assert_false(t.contains("not_connected"), t)
	assert_true(t.contains("連線"), t)

## M2 審查：自己的屍體按鈕寫「我的屍體（n 件）」，不再重複「自己的」
func test_corpse_label_mine_not_repeated() -> void:
	var t := UiSocial.corpse_label({ "owner_name": "介面俠客", "n_items": 2, "mine": true })
	assert_eq(t, "我的屍體（2 件）")
	assert_false(t.contains("自己的"))
	assert_eq(UiSocial.corpse_label({ "owner_name": "阿甲", "n_items": 1, "can_loot": true }), "阿甲的屍體（1 件）　可翻動")

## M2 審查：特殊開關頁比視窗高時在系統窗內捲動，不撐高視窗（不蓋住精氣條、熱鍵列）；換頁時視窗大小不變
func test_system_options_page_scrolls_inside_frame() -> void:
	var ms: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	ms.gate.set_sender(func(_k, _a): return -1)
	var sh := M2.sheet_m2()
	sh["is_admin"] = true
	ms.apply_sheet(sh)
	ms.open_panel("system")
	var sp: SystemPanel = ms.panels["system"]
	sp.show_page("累計上線時間")
	for i in 3:
		await _frame()
	var h_first: float = ms.panel_frame.size.y
	sp.show_page("特殊開關")
	for i in 3:
		await _frame()
	assert_true(sp.page_scroll != null and sp.page.get_parent() == sp.page_scroll, "page lives in a ScrollContainer")
	assert_true(ms.panel_frame.size.y <= h_first + 1.0, "frame height unchanged: %s -> %s" % [h_first, ms.panel_frame.size.y])
	var avail: Vector2 = ms.panel_area_size()
	assert_true(ms.panel_frame.size.y <= avail.y, "frame fits the panel area: %s > %s" % [ms.panel_frame.size.y, avail.y])

## M2 審查：開關的結果（pref_changed）只進聊天紀錄一次：不進右下系統框、不進面板回饋列
func test_pref_changed_reported_once() -> void:
	var e := { "ch": "SYSTEM", "key": "pref_changed", "p": { "label": "接受組隊邀請", "state": "關", "peer": 1 } }
	assert_true(MessageLog.is_quiet_system(e))
	var ml := MessageLog.new()
	_add(ml)
	await _frame()
	var before: int = ml.announce_lines.size()
	ml.add_event(e)
	assert_eq(ml.announce_lines.size(), before, "not in the system box")
	var pf := PanelFeedback.new()
	_add(pf)
	await _frame()
	pf.add_event(e)
	assert_eq(pf.feed_label.text, "", "not in the panel feedback strip")
	assert_false(MessageLog.is_quiet_system({ "ch": "SYSTEM", "key": "learn_ok" }))

## M2 審查：伺服器設定面板在規則組合下面顯示目前那一組的說明（後期官方的屍體時間是暫定值）
func test_server_options_show_preset_desc() -> void:
	var d := ServerOptionsDialog.new()
	_add(d)
	await _frame()
	d.apply_options({ "editable": [ { "key": "rule_preset", "label": "死亡規則", "value": "later_official",
		"choices": [ { "value": "classic_standard", "label": "懷舊標準（預設）", "desc": "屍體：30 分鐘" },
			{ "value": "later_official", "label": "後期官方規則", "desc": "屍體：原作沒寫何時消失" } ] } ],
		"info": { "world_name": "w", "players": [] } })
	assert_true(d.desc_label.visible)
	assert_true(d.desc_label.text.contains("原作沒寫"), d.desc_label.text)

func cd_parent_of(entry: Dictionary) -> Node:
	return (entry["countdown"] as Label).get_parent()

# ---------------------------------------------------------------- 第三輪審查（2026-10-18）

func test_r3_force_pk_confirm_is_red_and_cancel_has_focus() -> void:
	var ms: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	ms.gate.set_sender(func(_kind, _args): return -1)
	ms.apply_sheet(M2.sheet_m2())
	ms.apply_view(M2.view_m2(true))
	ms._on_player_action("force_pk", M2.view_m2()["players"][1])
	await _frame()
	await _frame()
	var d: ConfirmDialog = ms.confirm_dialog
	assert_true(d.visible)
	assert_true(d.is_danger(), "出手 is coloured as a dangerous action")
	assert_eq(d.ok_button.get_theme_color("font_color"), UiTheme.JY_RED)
	assert_true(d.cancel_button.has_focus(), "keyboard default is 取消")
	d.close()
	ms.ask_confirm("離開隊伍", "確定？", "離開", func(): pass)
	await _frame()
	assert_false(d.is_danger(), "ordinary confirms are not red")

func test_r3_corpse_authorize_row_and_owner_wording() -> void:
	var d := CorpseDialog.new()
	d.gate = _gate([])
	_add(d)
	await _frame()
	d.open_corpse({ "id": "cp_3", "owner_name": "我", "mine": true, "n_items": 1, "can_loot": true, "public": false, "left_s": 500,
		"authorized_names": [], "auth_max": 4, "items": [ { "uid": "it_9", "id": "a_buyi", "name": "布衣", "n": 1 } ] })
	assert_eq(d.auth_button.text, "允許", "the button submits the typed name")
	assert_true((d.auth_row.get_child(0) as Label).text.contains("讓這人翻動"))
	assert_true(d.info_label.text.contains("只有你和你允許的人"), d.info_label.text)
	d.open_corpse({ "id": "cp_4", "owner_name": "路人", "mine": false, "n_items": 1, "can_loot": false, "public": false, "left_s": 500 })
	assert_true(d.info_label.text.contains("只有本人和他允許的人"), d.info_label.text)

func test_r3_my_corpse_loot_button_is_grouped_and_labelled() -> void:
	var sp := ScenePanel.new()
	_add(sp)
	await _frame()
	sp.gate = _gate([])
	sp.apply_sheet(M2.sheet_m2())
	var v: Dictionary = M2.view_m2()
	v["corpses"] = [ { "id": "cp_8", "owner_name": "我", "mine": true, "n_items": 2, "can_loot": true } ]
	sp.apply_view(v)
	var grp := sp.corpses_box.find_child("MyCorpse", true, false)
	assert_true(grp != null, "my corpse button and its loot button are one group")
	var lb := sp.corpses_box.find_child("LootMine", true, false) as Button
	assert_true(lb != null and lb.text == "全部拾回", "says what it does")
	assert_eq(lb.get_parent(), grp)

func test_r3_popup_radio_icons_are_visible_on_dark_wood() -> void:
	var t := UiTheme.build()
	for n in ["radio_unchecked", "radio_checked"]:
		assert_true(t.has_icon(n, "PopupMenu"), n)
		var img := t.get_icon(n, "PopupMenu").get_image()
		var lit := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.5 and c.get_luminance() > 0.5:
					lit += 1
		assert_true(lit > 10, "%s has a bright outline (%d px)" % [n, lit])

func test_r3_empty_inbox_hides_list_column() -> void:
	var d := MailDialog.new()
	d.gate = _gate([])
	_add(d)
	await _frame()
	d.apply_mail_list([])
	var list_scroll := d.list_box.get_parent() as Control
	assert_false(list_scroll.visible, "no second 'empty' message in the list column")
	assert_true(d.read_text.text.contains("收件匣是空的"))
	d.apply_mail_list([ { "id": "ml_1", "from_name": "阿甲", "text": "x", "sent_clock": "第 1 日", "read": false } ])
	assert_true(list_scroll.visible)
