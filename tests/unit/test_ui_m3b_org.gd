extends "res://tests/test_case.gd"
## WP-UI（M3B_PLAN §11.1 test_ui_m3b_org）：組織面板（成員表、權限按鈕、各 intent 形狀、解散兩段確認）、
## 衙門書吏（創立、連署）、組織邀請的待回覆提示、玩家選單「邀請入組織」。全部假資料。

var _nodes: Array = []
var _old_sheet: Dictionary = {}
var _old_wi: Dictionary = {}

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	_old_sheet = ClientState.sheet
	_old_wi = ClientState.world_info

func after_each() -> void:
	ClientState.sheet = _old_sheet
	ClientState.world_info = _old_wi
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

func _gate(sent: Array, ok := true, reason := "") -> IntentGate:
	var g := IntentGate.new()
	_add(g)
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		var seq := sent.size()
		g.resolve.call_deferred(seq, ok, reason)
		return seq)
	return g

static func leader_sheet() -> Dictionary:
	return { "char_id": "ch_a", "name": "阿甲", "money": 20000, "fame": 200,
		"org": { "id": "g1", "name": "江湖小築", "rank": 0, "rank_name": "幫主", "title": "", "leader_name": "阿甲", "members_online": 2 },
		"societies": ["天地會"] }

static func org_info_payload() -> Dictionary:
	return { "org": { "id": "g1", "name": "江湖小築", "status": "ACTIVE", "leader_name": "阿甲" },
		"members": [
			{ "char_id": "ch_b", "name": "阿乙", "rank": 4, "title": "", "online": true },
			{ "char_id": "ch_a", "name": "阿甲", "rank": 0, "title": "老大", "online": true },
			{ "char_id": "ch_c", "name": "阿丙", "rank": 2, "title": "", "online": false } ],
		"rank_names": ["幫主", "副幫主", "長老", "堂主", "幫眾"], "societies": ["天地會"], "member_max": 50 }

func test_normalize_info_shapes() -> void:
	var i := OrgUi.normalize_info(org_info_payload())
	assert_eq(i["members"].map(func(m): return m["name"]), ["阿甲", "阿丙", "阿乙"], "位階高（數字小）的在前")
	assert_eq(i["members"][2]["rank_name"], "幫眾", "沒給 rank_name 用 rank_names")
	assert_eq(OrgUi.org_header(i), "江湖小築（成員 3／50，在線 2）")
	assert_eq(OrgUi.member_line(i["members"][0]), "● 阿甲　幫主　「老大」")
	assert_eq(OrgUi.member_line(i["members"][1]), "○ 阿丙　長老")
	# 攤平寫法、成員是字典
	var flat := OrgUi.normalize_info({ "id": "g1", "name": "X", "members": { "ch_z": { "name": "阿丁", "rank": 1 } } })
	assert_eq(flat["org"]["name"], "X")
	assert_eq(flat["members"][0]["char_id"], "ch_z")
	assert_eq(flat["members"][0]["rank_name"], "副幫主")
	assert_eq(OrgUi.normalize_info({})["org"], {})
	# 權限
	assert_true(OrgUi.can_invite(1))
	assert_false(OrgUi.can_invite(2))
	assert_true(OrgUi.can_kick(1, 3))
	assert_false(OrgUi.can_kick(2, 2), "同位階不能踢")
	assert_false(OrgUi.can_kick(0, 0), "幫主不能被踢")
	assert_eq(OrgUi.leave_block(0), "leader_must_transfer")
	assert_eq(OrgUi.leave_block(4), "")
	# 名字
	assert_eq(OrgUi.name_block("江湖小築"), "")
	assert_eq(OrgUi.name_block("江"), "bad_org_name")
	assert_eq(OrgUi.name_block("江湖小築江湖小築江"), "bad_org_name")
	assert_eq(OrgUi.name_block("abc幫"), "bad_org_name")
	assert_eq(OrgUi.name_block("第7幫"), "")
	assert_true(OrgUi.rank_name_ok("長老"))
	assert_false(OrgUi.rank_name_ok("太上長老大人"))
	assert_true(OrgUi.title_ok(""))
	assert_false(OrgUi.title_ok("一二三四五六七"))

func test_leader_panel_actions_send_intents() -> void:
	var sent: Array = []
	var p := OrgPanel.new()
	p.gate = _gate(sent)
	_add(p)
	await _frame()
	ClientState.sheet = leader_sheet()
	p.apply_sheet(leader_sheet())
	p.open_panel()
	assert_eq(sent[0], ["org_info", {}], "打開就向主機要 org_info")
	await _frame()
	p.apply_info(org_info_payload())
	assert_eq(p.head_label.text, "江湖小築（成員 3／50，在線 2）")
	assert_eq(p.me_label.text, "你的位階：幫主　封號：老大")
	assert_eq(p.soc_label.text, "會籍：天地會")
	for id in ["invite", "kick", "set_rank", "title", "lead", "rank_names", "disband", "leave"]:
		assert_true(p.action_buttons.has(id), "幫主有 " + id)
	assert_true((p.action_buttons["leave"] as Button).disabled, "幫主不能直接退出")
	assert_true((p.action_buttons["kick"] as Button).disabled, "還沒選人")
	assert_true((p.action_buttons["rank_pick"] as OptionButton).disabled, "M3b 審查 4：還沒選人，位階下拉也停用")
	# 邀請
	p.invite_edit.text = "阿丁"
	(p.action_buttons["invite"] as Button).pressed.emit()
	assert_eq(sent[1], ["org_invite", { "name": "阿丁" }])
	await _frame()
	await _frame()
	# 數字鍵 3 選第三列（阿乙）→ 開除要確認
	assert_true(p.press_number(3))
	assert_eq(p.target, "阿乙")
	assert_false((p.action_buttons["kick"] as Button).disabled)
	(p.action_buttons["kick"] as Button).pressed.emit()
	var ct := p.detail_box.find_child("ConfirmText", true, false) as Label
	assert_true(ct != null and ct.text.contains("阿乙"), "開除先確認")
	var n := sent.size()
	(p.detail_box.find_child("ConfirmOk", true, false) as Button).pressed.emit()
	assert_eq(sent[n], ["org_kick", { "name": "阿乙" }])
	await _frame()
	await _frame()
	# 設位階（下拉 1–4）、封號
	# M3b 審查 4：選到自己（幫主）→ 位階下拉停用
	p.select_member(str(leader_sheet().get("name", "")))
	assert_true((p.action_buttons["rank_pick"] as OptionButton).disabled, "選自己時位階下拉停用")
	p.select_member("阿乙")
	var ob := p.action_buttons["rank_pick"] as OptionButton
	assert_false(ob.disabled, "選幫眾時可以選位階")
	assert_eq(ob.item_count, 4, "不能設 0（移交才行）")
	ob.select(ob.get_item_index(2))
	(p.action_buttons["set_rank"] as Button).pressed.emit()
	assert_eq(sent[sent.size() - 1], ["org_set_rank", { "name": "阿乙", "rank": 2 }])
	await _frame()
	await _frame()
	p.select_member("阿乙")
	(p.action_buttons["title_edit"] as LineEdit).text = "鐵掌"
	(p.action_buttons["title"] as Button).pressed.emit()
	assert_true(sent.any(func(x): return x == ["org_title", { "name": "阿乙", "title": "鐵掌" }]), str(sent))
	await _frame()
	await _frame()
	# 移交要確認
	p.select_member("阿乙")
	(p.action_buttons["lead"] as Button).pressed.emit()
	n = sent.size()
	(p.detail_box.find_child("ConfirmOk", true, false) as Button).pressed.emit()
	assert_eq(sent[n], ["org_lead", { "name": "阿乙" }])
	await _frame()
	await _frame()
	# 改位階名稱
	p.select_member("阿乙")
	(p.action_buttons["rank_names"] as Button).pressed.emit()
	(p.detail_box.find_child("RankName4", true, false) as LineEdit).text = "弟子"
	n = sent.size()
	(p.detail_box.find_child("RankNamesOk", true, false) as Button).pressed.emit()
	assert_eq(sent[n], ["org_rank_names", { "names": ["幫主", "副幫主", "長老", "堂主", "弟子"] }])
	await _frame()
	await _frame()
	# 位階名稱太長：不送
	n = sent.size()
	assert_eq(p.do_rank_names(["幫主", "副幫主", "長老", "堂主", "很長的名稱"]), -1)
	assert_eq(sent.size(), n)

func test_disband_two_step_needs_org_name() -> void:
	var sent: Array = []
	var p := OrgPanel.new()
	p.gate = _gate(sent)
	_add(p)
	await _frame()
	ClientState.sheet = leader_sheet()
	p.apply_sheet(leader_sheet())
	p.open_panel()
	await _frame()
	p.apply_info(org_info_payload())
	sent.clear()
	(p.action_buttons["disband"] as Button).pressed.emit()
	assert_true((p.detail_box.find_child("DisbandText", true, false) as Label).text.contains("無法復原"))
	assert_eq(sent, [], "第一段不送")
	(p.detail_box.find_child("DisbandStep1", true, false) as Button).pressed.emit()
	var le := p.detail_box.find_child("DisbandWord", true, false) as LineEdit
	var ok := p.detail_box.find_child("DisbandOk", true, false) as Button
	assert_true(ok.disabled)
	le.text = "江湖"
	le.text_changed.emit(le.text)
	assert_true(ok.disabled, "名字不對")
	le.text = "江湖小築"
	le.text_changed.emit(le.text)
	assert_false(ok.disabled)
	ok.pressed.emit()
	assert_eq(sent[0], ["org_disband", { "confirm": true }])

func test_member_panel_limited_and_leave() -> void:
	var sent: Array = []
	var p := OrgPanel.new()
	p.gate = _gate(sent)
	_add(p)
	await _frame()
	var s := { "char_id": "ch_b", "name": "阿乙", "org": { "id": "g1", "name": "江湖小築", "rank": 4, "rank_name": "幫眾" } }
	ClientState.sheet = s
	p.apply_sheet(s)
	p.open_panel()
	await _frame()
	p.apply_info(org_info_payload())
	for id in ["invite", "kick", "set_rank", "title", "lead", "rank_names", "disband"]:
		assert_false(p.action_buttons.has(id), "幫眾沒有 " + id)
	assert_false((p.action_buttons["leave"] as Button).disabled)
	sent.clear()
	(p.action_buttons["leave"] as Button).pressed.emit()
	(p.detail_box.find_child("ConfirmOk", true, false) as Button).pressed.emit()
	assert_eq(sent[0], ["org_leave", {}])

func test_no_org_and_clerk_found_sign() -> void:
	var sent: Array = []
	var p := OrgPanel.new()
	p.gate = _gate(sent)
	_add(p)
	await _frame()
	var s := { "char_id": "ch_d", "name": "阿丁", "fame": 200, "societies": ["天地會"] }
	ClientState.sheet = s
	ClientState.world_info = { "org_found_fee": 10000, "guild_signers": 3 }
	p.apply_sheet(s)
	p.open_clerk({ "npc": "n_og_xx_shuli", "npc_name": "書吏", "services": ["ORG"],
		"org": { "can_found": true, "fee": 10000,
			"petitions": [ { "id": "g9", "name": "青龍會", "leader_name": "阿戊", "signed": 1, "need": 3 } ] } })
	assert_eq(p.head_label.text, "你不在任何組織裡。")
	assert_true(p.me_label.text.contains("衙門找書吏"), p.me_label.text)
	assert_eq(p.soc_label.text, "會籍：天地會", "天地會不是組織，只列會籍")
	var ft := p.clerk_box.find_child("FoundText", true, false) as Label
	assert_true(ft.text.contains("一萬兩") and ft.text.contains("名聲 150"), ft.text)
	# 名字不合法：不送
	(p.clerk_box.find_child("FoundName", true, false) as LineEdit).text = "ab"
	(p.clerk_box.find_child("Found", true, false) as Button).pressed.emit()
	assert_eq(sent, [])
	assert_true(p.status_label.text.contains("2–8"), p.status_label.text)
	(p.clerk_box.find_child("FoundName", true, false) as LineEdit).text = "江湖小築"
	(p.clerk_box.find_child("Found", true, false) as Button).pressed.emit()
	assert_eq(sent[0], ["org_found", { "npc": "n_og_xx_shuli", "name": "江湖小築" }])
	await _frame()
	var line := ""
	for l in p.clerk_box.find_children("*", "Label", true, false):
		line += (l as Label).text
	assert_true(line.contains("「青龍會」　發起人 阿戊　已連署 1／3"), line)
	(p.clerk_box.find_child("Sign_g9", true, false) as Button).pressed.emit()
	assert_eq(sent[1], ["org_sign", { "npc": "n_og_xx_shuli", "org": "g9" }])
	# M3b 審查：主機在創立／連署後重送選單 → 書吏頁的清單更新、並重要 org_info
	await _frame()
	p.refresh_menu({ "npc": "n_og_xx_shuli", "npc_name": "書吏", "services": ["ORG"], "refresh": true,
		"org": { "can_found": false, "fee": 10000, "petitions": [
			{ "id": "g9", "name": "青龍會", "leader_name": "阿戊", "signed": 2, "need": 3, "can_sign": false, "reason": "already_signed" },
			{ "id": "g10", "name": "江湖小築", "leader_name": "阿丁", "signed": 0, "need": 3, "can_sign": false, "reason": "self_target" } ] } })
	var line2 := ""
	for l in p.clerk_box.find_children("*", "Label", true, false):
		line2 += (l as Label).text
	assert_true(line2.contains("江湖小築") and line2.contains("已連署 2／3"), line2)
	assert_true((p.clerk_box.find_child("Found", true, false) as Button).disabled, "已經發起 → 創立灰掉")
	assert_eq(sent[sent.size() - 1], ["org_info", {}], "重要 org_info")

func test_main_screen_org_routing_and_npc_service() -> void:
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.apply_sheet(leader_sheet())
	# 指令窗「組織」分頁開放
	assert_false("GUILD" in UiCommands.LOCKED_TABS)
	assert_eq(UiCommands.ids_in_tab("GUILD"), ["org"])
	main.run_command(Hotbar.CMD_PREFIX + "org")
	assert_true(main.org_panel.visible)
	main.handle_event({ "ch": "SYSTEM", "key": "org_info", "ui": true, "p": org_info_payload() })
	assert_eq(main.org_panel.head_label.text, "江湖小築（成員 3／50，在線 2）")
	# 書吏
	main.handle_event({ "ch": "SYSTEM", "key": "npc_menu", "ui": true,
		"p": { "npc": "n_og_xx_shuli", "npc_name": "書吏", "services": ["ORG"], "org": { "petitions": [], "can_found": false } } })
	assert_eq((main.npc_dialog.service_buttons["ORG"] as Button).text, "組織")
	(main.npc_dialog.service_buttons["ORG"] as Button).pressed.emit()
	assert_true(main.org_panel.visible)
	assert_eq(main.org_panel.npc_id(), "n_og_xx_shuli")
	assert_true(main.org_panel.clerk_box.visible)

func test_org_invite_pending_prompt_and_reply() -> void:
	var sent: Array = []
	var pp := PendingPrompts.new()
	pp.gate = _gate(sent)
	_add(pp)
	await _frame()
	pp.apply_sheet({ "char_id": "ch_b", "pending": {} })
	pp.add_org_invite({ "org": "g1", "org_name": "江湖小築", "from_name": "阿甲", "left_s": 60 })
	assert_true(pp.visible)
	var rows := pp.open_rows()
	assert_eq(rows.size(), 1)
	assert_eq(UiSocial.pending_head(rows[0]), "阿甲邀請你加入組織「江湖小築」")
	await tree.create_timer(0.35).timeout   # 移位防誤點（MOVE_GUARD_MS）
	assert_true(pp.answer("org:g1", true) > 0)
	assert_eq(sent[0], ["org_reply", { "org": "g1", "accept": true }])
	await _frame()
	await _frame()
	assert_eq(pp.open_rows().size(), 0, "回覆後不再顯示")
	# 角色表帶的邀請（重連後）
	pp.apply_sheet({ "char_id": "ch_b", "pending": { "org_invite": { "org": "g2", "org_name": "青龍會", "from_name": "阿戊", "left_s": 30 } } })
	rows = pp.open_rows()
	assert_eq(rows.size(), 1)
	assert_eq(str(rows[0]["org"]), "g2")
	await tree.create_timer(0.35).timeout
	pp.answer("org:g2", false)
	assert_eq(sent[1], ["org_reply", { "org": "g2", "accept": false }])
	# 主畫面：org_invite（ui）事件 → 提示框
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.apply_sheet({ "char_id": "ch_b", "name": "阿乙", "vitals": {}, "pending": {} })
	main.handle_event({ "ch": "SYSTEM", "key": "org_invite", "ui": true, "p": { "org": "g3", "org_name": "白虎堂", "from_name": "阿己" } })
	assert_true(main.pending_prompts.visible)
	assert_true(main.pending_prompts.open_rows().any(func(r): return str(r.get("org", "")) == "g3"))

func test_player_menu_org_invite() -> void:
	var me := leader_sheet()
	var stranger := { "char_id": "ch_x", "name": "路人", "org_name": "" }
	var acts: Array = UiSocial.player_menu(stranger, me).map(func(x): return x[0])
	assert_true(acts.has(UiSocial.ACT_ORG_INVITE), str(acts))
	var member := { "char_id": "ch_y", "name": "別幫", "org_name": "青龍會" }
	acts = UiSocial.player_menu(member, me).map(func(x): return x[0])
	assert_false(acts.has(UiSocial.ACT_ORG_INVITE), "對方已有組織")
	var plain := { "char_id": "ch_z", "name": "舊主機" }
	acts = UiSocial.player_menu(plain, me).map(func(x): return x[0])
	assert_false(acts.has(UiSocial.ACT_ORG_INVITE), "主機沒給 org_name：不顯示")
	var low := { "char_id": "ch_b", "org": { "id": "g1", "name": "江湖小築", "rank": 4 } }
	acts = UiSocial.player_menu(stranger, low).map(func(x): return x[0])
	assert_false(acts.has(UiSocial.ACT_ORG_INVITE), "幫眾沒有邀請權")
	# 主畫面：選單動作送 org_invite { name }
	var sent: Array = []
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.gate.set_sender(func(kind, args):
		sent.append([kind, args])
		return -1)
	main._on_player_action(UiSocial.ACT_ORG_INVITE, stranger)
	assert_eq(sent, [["org_invite", { "name": "路人" }]])

func test_attributes_org_line() -> void:
	var s := leader_sheet()
	s["org"]["title"] = "老大"
	assert_eq(AttributesPanel.org_line(s), "組織：江湖小築（幫主・老大）　會籍：天地會")
	assert_eq(AttributesPanel.org_line({}), "")

## M3b 審查：連署中的發起人（還沒有成員列、角色表沒有 org）照主機的 my.can_disband 顯示「撤回連署」，不顯示灰掉的退出
func test_petition_founder_can_withdraw_in_panel() -> void:
	var sent: Array = []
	var p := OrgPanel.new()
	p.gate = _gate(sent)
	_add(p)
	await _frame()
	var s := { "char_id": "ch_a", "name": "阿甲", "money": 10000, "fame": 200 }
	ClientState.sheet = s
	p.apply_sheet(s)
	p.open_panel()
	await _frame()
	var payload := { "org": { "id": "g9", "name": "江湖小築", "status": "PETITION", "leader_name": "阿甲",
			"petition": { "signed": 1, "need": 3, "signers": ["阿乙"], "left_s": 3600 } },
		"members": [], "my": { "rank": 0, "rank_name": "幫主", "title": "", "can_disband": true, "can_leave": false },
		"societies": [] }
	var ni := OrgUi.normalize_info(payload)
	assert_eq(bool(ni["my"].get("can_disband", false)), true, "normalize_info 留著 my")
	assert_eq(OrgUi.rank_in(ni, "ch_a", s), 0, "成員列沒有我 → 用 my.rank")
	p.apply_info(payload)
	assert_true(p.action_buttons.has("withdraw"), "有撤回連署")
	assert_false(p.action_buttons.has("leave"), "連署中沒有退出組織")
	sent.clear()
	(p.action_buttons["withdraw"] as Button).pressed.emit()
	assert_true((p.detail_box.find_child("DisbandText", true, false) as Label).text.contains("撤回"))
	(p.detail_box.find_child("DisbandStep1", true, false) as Button).pressed.emit()
	var le := p.detail_box.find_child("DisbandWord", true, false) as LineEdit
	le.text = "江湖小築"
	le.text_changed.emit(le.text)
	(p.detail_box.find_child("DisbandOk", true, false) as Button).pressed.emit()
	assert_eq(sent[0], ["org_disband", { "confirm": true }])
