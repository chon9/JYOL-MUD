extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §5.3、§10.1、§10.4（WP-EVENTS）介面：比武報名視窗（場次、報名／退出、對戰表、點名、日曆、主機開辦）、
## 報名員選單「比武報名」、擂臺倒數名牌、劫鏢確認視窗（押鏢的人清單、本機先擋、送出 rob_escort）。

var dlg: TourneyDialog = null
var npc_dlg: NpcDialog = null
var rob: JiebiaoConfirm = null

func before_each() -> void:
	world_name = "w_ui_m3d_tourney"
	UiSettings.reset_for_tests(true)
	super.before_each()
	cs.world_info = ws.world_info()
	TourneyDialog.pending_open = false
	TourneyDialog.pending_npc = ""

func after_each() -> void:
	for n in [dlg, npc_dlg, rob]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	await tree.process_frame
	dlg = null
	npc_dlg = null
	rob = null
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

func _new_dialog() -> TourneyDialog:
	dlg = TourneyDialog.new()
	dlg.gate = _gate()
	tree.root.add_child(dlg)
	dlg.add_child(dlg.gate)
	return dlg

func test_pure_helpers() -> void:
	assert_eq(TourneyDialog.match_text({ "a": "甲", "b": "", "done": true, "winner": "甲", "how": "BYE" }), "甲（輪空）")
	assert_eq(TourneyDialog.match_text({ "a": "甲", "b": "乙", "done": false }), "甲 對 乙")
	assert_eq(TourneyDialog.match_text({ "a": "甲", "b": "乙", "done": true, "winner": "乙", "how": "JUDGE" }), "甲 對 乙 → 乙（判定）")
	assert_eq(TourneyDialog.match_text({ "a": "甲", "b": "乙", "done": true, "winner": "", "how": "FORFEIT" }), "甲 對 乙 → 雙雙判負")
	assert_eq(TourneyDialog.round_name(2, 3), "決賽")
	assert_eq(TourneyDialog.round_name(1, 3), "四強")
	assert_eq(TourneyDialog.round_name(0, 3), "八強")
	assert_eq(TourneyDialog.round_name(0, 4), "16 強")
	assert_eq(TourneyDialog.duration_text(75), "1 分 15 秒")
	assert_true(TourneyDialog.phase_line({ "phase": "SIGNUP", "start_left_s": 30 }).contains("30 秒"))
	assert_true(TourneyDialog.can_sign({ "kind": "WULIN", "phase": "SIGNUP" }, "", []))
	assert_false(TourneyDialog.can_sign({ "kind": "WULIN", "phase": "RUNNING" }, "", []), "開打了不能報")
	assert_false(TourneyDialog.can_sign({ "kind": "SECT:wudang", "phase": "SIGNUP" }, "SECT:shaolin", []), "別派不能報")
	assert_false(TourneyDialog.can_sign({ "kind": "WULIN", "phase": "SIGNUP" }, "", ["WULIN"]), "已報名")
	assert_eq(BattleScreen.duel_text(598.2), "擂臺　9:59")
	assert_eq(BattleScreen.duel_left({ "kind": "DUEL", "duel_left_s": 600.0, "tick": 100 }, 150.0), 595.0, "倒數用戰鬥時間")
	assert_eq(BattleScreen.duel_left({ "kind": "ENCOUNTER", "duel_left_s": -1.0 }, 0.0), -1.0, "不是比武沒有倒數")

func test_signup_through_npc_menu_and_dialog() -> void:
	if not game_ok():
		return
	make_char("報名甲")
	ch().combat_xp = int(TourneyRules.WULIN_ENTRY.xp)   # M3d 審查：武林大會要實戰 1 萬
	goto(TourneyRules.REST_ROOM)
	ok("tourney_host", { "kind": "WULIN", "signup_s": 300 })
	npc_dlg = NpcDialog.new()
	npc_dlg.gate = _gate()
	tree.root.add_child(npc_dlg)
	npc_dlg.add_child(npc_dlg.gate)
	npc_dlg.open_menu({ "npc": TourneyRules.CLERK_NPC, "npc_name": "比武報名員", "services": ["TOURNEY"] })
	await tree.process_frame
	assert_true(npc_dlg.service_buttons.has("TOURNEY"), "報名員選單有「比武報名」")
	(npc_dlg.service_buttons["TOURNEY"] as Button).pressed.emit()
	await tree.process_frame
	assert_true(TourneyDialog.pending_open, "按下後等主機回 tourney_state 打開視窗")
	assert_eq(TourneyDialog.pending_npc, TourneyRules.CLERK_NPC)
	var st := lastp("tourney_state")
	assert_false(st.is_empty(), "主機回 tourney_state")
	_new_dialog()
	dlg.apply_state(st)
	dlg.visible = true
	await tree.process_frame
	var t := _texts(dlg)
	assert_true(t.contains("武林大會"), "場次名")
	assert_true(t.contains("報名中"), "階段")
	var sb := _find(dlg, "Signup_WULIN") as Button
	assert_true(sb != null and not sb.disabled, "報名鈕")
	sb.pressed.emit()
	await tree.process_frame
	var ev: Dictionary = host().tourney.event_of("WULIN")
	assert_eq((ev.get("entrants", []) as Array).size(), 1, "經由視窗報名")
	dlg.apply_state(lastp("tourney_state"))
	await tree.process_frame
	assert_true(_texts(dlg).contains("已報名"))
	assert_true(_find(dlg, "Withdraw_WULIN") != null, "退出鈕")
	assert_true(dlg.press_number(1), "數字鍵 1 → 第一顆（退出）")
	await tree.process_frame
	assert_eq((host().tourney.event_of("WULIN").get("entrants", []) as Array).size(), 0, "退出了")
	# 主機列：本機是主機
	assert_true((_find(dlg, "TourneyHost") as Control).visible, "主機看得到開辦列")

func test_bracket_render() -> void:
	if not game_ok():
		return
	make_char("看表乙")
	_new_dialog()
	dlg.npc = TourneyRules.CLERK_NPC
	dlg.apply_state({ "kind": "WULIN", "kind_name": "武林大會", "phase": "RUNNING", "exhibition": false,
		"entrants": ["甲", "乙", "丙", "丁", "戊"],
		"bracket": [[{ "a": "甲", "b": "", "done": true, "winner": "甲", "how": "BYE" },
			{ "a": "乙", "b": "", "done": true, "winner": "乙", "how": "BYE" },
			{ "a": "丙", "b": "", "done": true, "winner": "丙", "how": "BYE" },
			{ "a": "丁", "b": "戊", "done": true, "winner": "戊", "how": "FORFEIT" }],
			[{ "a": "甲", "b": "乙", "done": false }, { "a": "丙", "b": "戊", "done": false }]],
		"next_match": { "a": "甲", "b": "乙", "calls": 2, "fighting": false },
		"events": [{ "kind": "WULIN", "kind_name": "武林大會", "phase": "RUNNING", "n": 5 }],
		"upcoming": [{ "kind_name": "武林大會", "text": "2 月 15 日午時" }], "signed": ["WULIN"], "my_sect_kind": "" })
	dlg.visible = true
	await tree.process_frame
	var t := _texts(dlg)
	for s in ["八強", "四強", "甲（輪空）", "丁 對 戊 → 戊（棄權）", "下一場：甲 對 乙（點名第 2 次", "2 月 15 日午時", "比賽進行中"]:
		assert_true(t.contains(s), "畫面有「%s」" % s)
	assert_eq(_find(dlg, "Signup_WULIN"), null, "開打了沒有報名鈕")

func test_rob_dialog() -> void:
	if not game_ok():
		return
	make_char("劫鏢丙")
	ch().combat_xp = 100000
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()
	var v := { "pk_allowed": true, "players": [
		{ "name": "押鏢人", "char_id": "c_x", "tags": ["押鏢"], "in_battle": false },
		{ "name": "路人", "char_id": "c_y", "tags": [] },
		{ "name": "劫鏢丙", "char_id": str(ch().id), "tags": ["押鏢"] } ] }
	assert_eq(JiebiaoConfirm.targets(v, str(ch().id)).size(), 1, "只列別人、押鏢中的")
	assert_eq(JiebiaoConfirm.block_reason(v.players[0], v, { "combat_xp": 5 }), "實戰不到十萬，還沒有劫鏢的本事。")
	assert_eq(JiebiaoConfirm.block_reason(v.players[0], { "pk_allowed": false }, { "combat_xp": 100000 }), "這裡不能動手。")
	assert_eq(JiebiaoConfirm.block_reason(v.players[0], v, { "combat_xp": 100000 }), "")
	rob = JiebiaoConfirm.new()
	rob.gate = _gate()
	tree.root.add_child(rob)
	rob.add_child(rob.gate)
	rob.open_list(v)
	await tree.process_frame
	assert_true(_texts(rob).contains("押鏢人"))
	assert_false(_texts(rob).contains("路人"))
	(_find(rob, "Rob_押鏢人") as Button).pressed.emit()
	await tree.process_frame
	assert_true(_texts(rob).contains("確定要劫押鏢人的鏢？"), "確認段")
	(_find(rob, "RobOk") as Button).pressed.emit()
	await tree.process_frame
	assert_eq(rob.status_label.text, UiClient.reason_inline("target_not_here"), "送出 rob_escort（對方不在 → 主機回原因）")

## M3d 整合：房間玩家列的標籤與玩家選單「劫鏢」（對方頭上有「押鏢」、不同隊）
func test_rob_menu_and_tags_suffix() -> void:
	var p := { "char_id": "ch_x", "name": "押鏢客", "tags": ["押鏢", "懸賞"] }
	assert_eq(UiSocial.tags_suffix(p), "〔押鏢〕〔懸賞〕")
	assert_eq(UiSocial.tags_suffix({ "name": "路人" }), "")
	var acts := (UiSocial.player_menu(p, {}) as Array).map(func(e): return e[0])
	assert_has(acts, UiSocial.ACT_ROB, "押鏢的人 → 劫鏢")
	var plain := (UiSocial.player_menu({ "char_id": "ch_y", "name": "路人" }, {}) as Array).map(func(e): return e[0])
	assert_not_has(plain, UiSocial.ACT_ROB, "沒押鏢 → 沒有劫鏢")
	var mate := { "party": { "members": [{ "char_id": "ch_x" }] } }
	var acts2 := (UiSocial.player_menu(p, mate) as Array).map(func(e): return e[0])
	if UiSocial.in_my_party(mate, "ch_x"):
		assert_not_has(acts2, UiSocial.ACT_ROB, "隊友不能劫")

## M3d 審查：不能報名的原因、日曆用「第 N 日」、對戰表高度跟著行數、表頭那一場一定列出來
func test_review_reasons_calendar_and_height() -> void:
	assert_eq(TourneyDialog.block_text({ "kind": "SECT:gumu", "kind_name": "古墓門派比武", "phase": "SIGNUP" }, "SECT:shaolin", []).begins_with("限"), true)
	assert_true(TourneyDialog.block_text({ "kind": "SECT:gumu", "kind_name": "古墓門派比武", "phase": "SIGNUP" }, "", []).ends_with("弟子"))
	assert_eq(TourneyDialog.block_text({ "kind": "WULIN", "phase": "RUNNING" }, "", []), "報名已截止")
	assert_eq(TourneyDialog.block_text({ "kind": "WULIN", "phase": "SIGNUP" }, "", []), "", "能報名就不寫原因")
	assert_eq(TourneySystem.calendar_text(15, 6, 10), "第 15 日午時（還有 5 日）")
	assert_eq(TourneySystem.calendar_text(15, 6, 15), "第 15 日午時（今天）")
	assert_true(TourneyDialog.bracket_height(0) <= 30.0, "沒有對戰表不留空白")
	assert_true(TourneyDialog.bracket_height(15) > 120.0, "八人的對戰表放得下")
	assert_true(TourneyDialog.bracket_height(100) <= 300.0)
	_new_dialog()
	dlg.apply_state({ "kind": "SECT:gumu", "kind_name": "古墓門派比武", "phase": "SIGNUP", "start_left_s": 577, "enabled": true,
		"events": [{ "kind": "SECT:gumu", "kind_name": "古墓門派比武", "phase": "SIGNUP", "start_left_s": 577, "n": 0 }],
		"signed": [], "my_sect_kind": "SECT:shaolin", "bracket": [], "entrants": [] })
	dlg.visible = true
	await tree.process_frame
	var t := _texts(dlg)
	assert_false(t.contains("現在沒有開放報名或進行中的比武"), "表頭講的那一場有列出來")
	assert_true(_find(dlg, "Why_SECT_gumu") != null, "寫出不能報名的原因")

## M3d 審查（第 3 輪）：報名條件不合 → 報名鈕灰掉、旁邊寫「需 實戰 10000 以上、沒有 PK值」；倒數寫明現實時間；
## 沒有比武時不印「報名名單：（還沒有人）」
func test_entry_block_realtime_and_empty() -> void:
	if not game_ok():
		return
	make_char("新手丁")
	assert_true(TourneyDialog.phase_line({ "phase": "SIGNUP", "start_left_s": 7200 }).contains("現實時間"), "倒數是現實時間")
	assert_eq(TourneyDialog.entry_block_text({ "WULIN": { "text": "實戰 10000 以上", "why": "" } }, "WULIN"), "")
	assert_eq(TourneyDialog.entry_block_text({ "WULIN": { "text": "實戰 10000 以上", "why": "tourney_need_xp" } }, "WULIN"), "需實戰 10000 以上")
	goto(TourneyRules.REST_ROOM)
	ok("tourney_host", { "kind": "WULIN", "signup_s": 300 })
	ok("tourney_info")
	var st := lastp("tourney_state")
	assert_eq(str(st.get("entry", {}).get("WULIN", {}).get("why", "")), "tourney_need_xp", "主機帶出不能報的原因")
	_new_dialog()
	dlg.npc = TourneyRules.CLERK_NPC
	dlg.apply_state(st)
	dlg.visible = true
	await tree.process_frame
	var sb := _find(dlg, "Signup_WULIN") as Button
	assert_true(sb != null and sb.disabled, "條件不合 → 報名鈕灰掉")
	assert_true(sb.tooltip_text.contains("實戰"), "提示寫條件")
	assert_true(_find(dlg, "Need_WULIN") != null, "列上寫出條件")
	dlg.apply_state({ "kind": "", "kind_name": "", "phase": "DONE", "entrants": [], "bracket": [], "next_match": {},
		"events": [], "upcoming": [], "signed": [], "my_sect_kind": "", "enabled": true })
	await tree.process_frame
	assert_false(_texts(dlg).contains("報名名單"), "沒有比武 → 不印報名名單")

## M3d 審查第三輪：比賽進行中視窗不能長過可用高度（對戰表縮短、捲動）；報名倒數每秒往下數
func test_review3_fit_height_and_ticking_countdown() -> void:
	assert_eq(TourneyDialog.fit_bracket_h(200.0, 300.0, 552.0), 200.0, "放得下 → 照行數")
	assert_eq(TourneyDialog.fit_bracket_h(300.0, 400.0, 540.0), 140.0, "放不下 → 縮到剩下的高度")
	assert_eq(TourneyDialog.fit_bracket_h(300.0, 520.0, 540.0), TourneyDialog.BRACKET_MIN_H, "最少留幾行")
	assert_eq(TourneyDialog.with_elapsed({ "start_left_s": 600 }, 5)["start_left_s"], 595)
	assert_eq(TourneyDialog.with_elapsed({ "start_left_s": 3 }, 5)["start_left_s"], 0)
	_new_dialog()
	dlg.avail_h_override = 540.0
	var rounds: Array = []
	var r0: Array = []
	for i in 8:
		r0.append({ "a": "選手%d甲" % i, "b": "選手%d乙" % i, "done": i < 3, "winner": "選手%d甲" % i if i < 3 else "", "how": "KO" })
	rounds.append(r0)
	dlg.apply_state({ "kind": "WULIN", "kind_name": "武林大會", "phase": "RUNNING", "enabled": true,
		"events": [{ "kind": "WULIN", "kind_name": "武林大會", "phase": "RUNNING", "n": 16 }],
		"signed": ["WULIN"], "my_sect_kind": "", "bracket": rounds, "entrants": [],
		"next_match": { "a": "選手3甲", "b": "選手3乙", "calls": 1 },
		"upcoming": [{ "kind_name": "少林門派比武", "text": "第 32 日巳時（還有 17 日）" }] })
	dlg.visible = true
	for i in 3:
		await tree.process_frame
	dlg.fit_height()
	await tree.process_frame
	assert_true(dlg.get_combined_minimum_size().y <= 540.0 + 1.0, "視窗高 %.0f 不超過可用高度 540" % dlg.get_combined_minimum_size().y)
	# 倒數：apply_state 之後 5 秒，標題與列表都少 5 秒
	dlg.apply_state({ "kind": "WULIN", "kind_name": "武林大會", "phase": "SIGNUP", "start_left_s": 600, "enabled": true,
		"events": [{ "kind": "WULIN", "kind_name": "武林大會", "phase": "SIGNUP", "start_left_s": 600, "n": 1 }],
		"signed": [], "my_sect_kind": "", "bracket": [], "entrants": [] })
	assert_true(dlg.head_label.text.contains("10 分 0 秒"), dlg.head_label.text)
	dlg._applied_ms -= 5000
	dlg.tick_countdown()
	assert_true(dlg.head_label.text.contains("9 分 55 秒"), "標題倒數往下數：%s" % dlg.head_label.text)
	assert_true(_texts(dlg).contains("武林大會　報名中（現實時間約 9 分 55 秒後開打）　1 人"), "列表倒數也往下數：%s" % _texts(dlg))
