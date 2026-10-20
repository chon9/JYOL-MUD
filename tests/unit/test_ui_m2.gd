extends "res://tests/test_case.gd"
## WP-UI（M2_PLAN 6.1 test_ui_m2）：鏡像座標換算往返、頻道選擇與 ChatInput、鴿章閃爍、待決提示由 sheet 重建、
## 伺服器面板依 server_options 產生控制項、屍體視窗按鈕狀態；另含玩家選單／強制 PK 本機檢查、隊伍面板、中途加入的單位、
## 重新連線流程、斷線分類、大廳版本判斷、護照視窗。全部用假資料，不需要主機端的 M2 系統。

var _nodes: Array = []

func before_each() -> void:
	UiSettings.reset_for_tests(true)

func after_each() -> void:
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

## 不送出、只記錄的 IntentGate
func _gate(sent: Array, ok := true, reason := "") -> IntentGate:
	var g := IntentGate.new()
	_add(g)
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		var seq := sent.size()
		g.resolve.call_deferred(seq, ok, reason)
		return seq)
	return g

static func sheet_m2() -> Dictionary:
	return {
		"char_id": "ch_me", "name": "我", "vitals": { "water": 50, "food": 50 },
		"is_admin": false, "mail_unread": 0, "prefs": { "accept_challenge": true, "accept_party": true },
		"party": {}, "pending": { "party_invite": {}, "challenges": [] }, "my_corpses": [],
	}

static func party_sheet(leader_me := true) -> Dictionary:
	var s := sheet_m2()
	s["party"] = { "id": "pt_1", "leader": "ch_me" if leader_me else "ch_a",
		"members": [
			{ "char_id": "ch_me", "name": "我", "peer": 1, "online": true, "room_name": "東門", "in_battle": false, "leader": leader_me },
			{ "char_id": "ch_a", "name": "阿甲", "peer": 101, "online": true, "room_name": "荒草坡", "in_battle": true, "leader": not leader_me },
		] }
	return s

static func view_m2(pk_allowed := true) -> Dictionary:
	return {
		"region": "xixia_wild", "region_name": "西夏郊外", "room": "xw_road", "room_name": "東門外官道",
		"desc": "官道。", "clock": "辰時", "night": false, "exits": [], "npcs": [], "features": [],
		"pk_allowed": pk_allowed,
		"players": [
			{ "peer": 1, "name": "我", "char_id": "ch_me", "align": "NEUTRAL", "newbie": false, "party_id": "", "in_battle": false, "battle_id": 0 },
			{ "peer": 101, "name": "阿甲", "char_id": "ch_a", "align": "EVIL", "newbie": false, "party_id": "", "in_battle": false, "battle_id": 0 },
			{ "peer": 102, "name": "小乙", "char_id": "ch_b", "align": "GOOD", "newbie": true, "party_id": "", "in_battle": false, "battle_id": 0 },
		],
		"battles": [ { "bid": 7, "kind": "FIGHT", "names": [["阿甲"], ["山賊頭目"]], "joinable": true },
			{ "bid": 8, "kind": "CHALLENGE", "names": [["丙"], ["丁"]], "joinable": false } ],
		"corpses": [],
	}

# ---------------------------------------------------------------- 1. 鏡像（4.5.3）

func test_mirror_round_trip_and_pvp_state() -> void:
	for x in 12:
		var c := Vector2i(x, 3)
		assert_eq(UiSocial.mirror_cell(UiSocial.mirror_cell(c, 12), 12), c, "round trip %d" % x)
	assert_eq(UiSocial.mirror_cell(Vector2i(0, 5), 12), Vector2i(11, 5), "x' = 11 - x")
	assert_eq(UiSocial.mirror_arr([2, 4], 12), [9, 4])
	var st := {
		"bid": 9, "w": 12, "h": 8, "tick": 0, "wait_mode": true, "my_uid": 2, "kind": "FORCED", "my_side": 1,
		"escape": [[0, 6], [11, 1]],
		"units": [
			{ "uid": 1, "name": "狂徒", "side": 0, "kind": "PLAYER", "look": "player_m", "pos": [1, 3], "qi": 100, "qi_max": 100, "state": "CHARGING" },
			{ "uid": 2, "name": "路人", "side": 1, "kind": "PLAYER", "pos": [10, 3], "qi": 90, "qi_max": 90, "state": "CHARGING", "move_range": 2 },
		],
	}
	var vm := BattleViewModel.from_state(st)
	assert_true(vm.mirrored, "my_side 1 mirrors")
	assert_true(vm.is_pvp())
	assert_eq(vm.unit(2)["pos"], Vector2i(1, 3), "I stand on the left")
	assert_eq(vm.unit(1)["pos"], Vector2i(10, 3), "attacker on the right")
	assert_true(vm.is_escape(Vector2i(11, 6)) and vm.is_escape(Vector2i(0, 1)), "escape cells mirrored")
	assert_eq(vm.to_host_arr(Vector2i(2, 3)), [9, 3], "target back to host coords")
	# battle_move 的 from／to 由主機座標轉成畫面座標
	var e := { "ch": "BATTLE", "key": "battle_move", "bid": 9, "p": { "uid": 1, "from": [1, 3], "to": [3, 3] } }
	var le := vm.localize_event(e)
	assert_eq(le["p"]["to"], [8, 3])
	assert_eq(e["p"]["to"], [3, 3], "original event untouched")
	vm.apply_event(le)
	assert_eq(vm.unit(1)["pos"], Vector2i(8, 3))
	# 沒鏡像（side 0）時原樣
	st["my_uid"] = 1
	st["my_side"] = 0
	var vm0 := BattleViewModel.from_state(st)
	assert_false(vm0.mirrored)
	assert_eq(vm0.localize_event(e), e)
	assert_eq(vm0.to_host_arr(Vector2i(2, 3)), [2, 3])

func test_battle_unit_join_adds_unit_and_sprite() -> void:
	var st := {
		"bid": 4, "w": 12, "h": 8, "tick": 0, "wait_mode": true, "my_uid": 1, "kind": "FIGHT", "my_side": 0,
		"escape": [], "units": [
			{ "uid": 1, "name": "我", "side": 0, "kind": "PLAYER", "pos": [1, 3], "qi": 100, "qi_max": 100, "state": "CHARGING" },
			{ "uid": 2, "name": "山賊頭目", "side": 1, "kind": "MONSTER", "pos": [10, 3], "qi": 1500, "qi_max": 1500, "state": "CHARGING" } ],
	}
	var bs: BattleScreen = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	bs.size = Vector2(1280, 552)
	bs.setup(st)
	await _frame()
	bs.apply_event({ "ch": "BATTLE", "key": "battle_unit_join", "bid": 4, "ui": true,
		"p": { "unit": { "uid": 3, "name": "隊員", "side": 0, "kind": "PLAYER", "pos": [0, 5], "qi": 80, "qi_max": 80, "state": "CHARGING", "gauge": 0.0, "rate": 5.0 } } })
	assert_eq(bs.vm.order.size(), 3)
	assert_eq(bs.vm.unit(3)["pos"], Vector2i(0, 5))
	assert_false(bs.vm.is_enemy(3), "joined on my side")
	assert_true(bs.grid_view.sprites.has(3), "sprite created")
	assert_true(bs._gauge_rows.has(3), "gauge row added")

# ---------------------------------------------------------------- 2. 頻道與 ChatInput

func test_channels_default_whisper_and_args() -> void:
	var ml := MessageLog.new()
	_add(ml)
	var row := HBoxContainer.new()
	_add(row)
	ml.build_input(row)
	await _frame()
	assert_eq(str(ml.input.name), "ChatInput", "ui_playthrough finds the box by name")
	assert_eq(ml.talk_channel, "輕聲細語", "default 輕聲細語 (AUTHENTIC_UI_SPEC 9.2)")
	assert_eq(ml.chat_args("你好"), { "text": "你好", "ch": "CHAT_SAY" })
	ml.set_talk_channel("千里傳音")
	assert_eq(ml.chat_args("大家好"), { "text": "大家好" }, "world chat keeps the M0 shape")
	assert_eq(str(UiSettings.get_value("ui.talk_channel", "")), "千里傳音", "remembered")
	ml.set_talk_channel("天外飛仙")
	assert_eq(ml.talk_channel, "輕聲細語", "GM channel needs admin")
	ml.set_admin(true)
	ml.set_talk_channel("天外飛仙")
	assert_eq(ml.chat_args("公告")["ch"], "GM")
	ml.set_admin(false)
	assert_eq(ml.talk_channel, "輕聲細語", "losing admin drops GM channel")
	ml.set_talk_channel("賭博頻道")
	assert_eq(ml.talk_channel, "輕聲細語", "not-open channel refused")
	ml.start_whisper("阿甲")
	assert_eq(ml.talk_channel, "傳音入密")
	assert_true(ml.whisper_to.visible)
	assert_eq(ml.chat_args("悄悄話"), { "text": "悄悄話", "ch": "CHAT_WHISPER", "to": "阿甲" })
	ml.whisper_to.text = ""
	assert_eq(ml.chat_args("悄悄話"), {}, "whisper without target not sent")
	ml.set_talk_channel("隊伍交談")
	assert_false(ml.whisper_to.visible)
	assert_eq(ml.chat_args("走")["ch"], "CHAT_PARTY")
	for c in MessageLog.TALK_CH:
		assert_has(UiKeys.CHAT_CHANNELS, MessageLog.TALK_CH[c], "4.1 channel " + c)
		assert_eq(MessageLog.CHANNEL_OF[MessageLog.TALK_CH[c]], c, "round trip " + c)
	# 送出：IntentGate 收到 chat 參數
	var sent: Array = []
	ml.gate = _gate(sent)
	ml.set_talk_channel("門派交談")
	ml.input.text = "師兄好"
	ml._on_send()
	assert_eq(sent[0], ["chat", { "text": "師兄好", "ch": "CHAT_SECT" }])

func test_rumor_and_whisper_render_with_channel_toggle() -> void:
	var ml := MessageLog.new()
	_add(ml)
	await _frame()
	ml.add_event({ "ch": "CHAT_RUMOR", "key": "chat_rumor", "p": { "from": "", "from_peer": 0, "text": "鬼王出世" } })
	ml.add_event({ "ch": "CHAT_PARTY", "key": "chat_party", "p": { "from": "阿甲", "from_peer": 101, "text": "在破廟集合m2ui" } })
	assert_true(ml.text.get_parsed_text().contains("在破廟集合m2ui"))
	ml.set_channel_enabled("隊伍交談", false)
	assert_false(ml.text.get_parsed_text().contains("在破廟集合m2ui"), "party chat hidden when 隊伍交談 off")
	assert_eq(TextRenderer.CHANNEL_COLORS["CHAT_WHISPER"], "#ff80ff")
	assert_eq(TextRenderer.CHANNEL_COLORS["CHAT_PARTY"], "#80c0ff")

# ---------------------------------------------------------------- 3. 鴿章

func test_pigeon_blinks_only_with_unread_mail() -> void:
	var hud := BottomHud.new()
	_add(hud)
	await _frame()
	var s := sheet_m2()
	hud.apply_sheet(s)
	assert_false(hud.pigeon_blinking())
	assert_false(UiSocial.pigeon_blinks(s))
	assert_eq(hud.pigeon.modulate.a, 1.0)
	s["mail_unread"] = 2
	hud.apply_sheet(s)
	assert_true(hud.pigeon_blinking())
	assert_true(hud.pigeon.tooltip_text.contains("2"))
	var a := UiSocial.blink_alpha(0)
	var b := UiSocial.blink_alpha(500)
	assert_true(a > b, "alpha oscillates")
	s["mail_unread"] = 0
	hud.apply_sheet(s)
	assert_false(hud.pigeon_blinking())
	assert_eq(hud.pigeon.modulate.a, 1.0, "stops dimmed state")

# ---------------------------------------------------------------- 4. 待決提示

func test_pending_prompts_rebuild_from_sheet() -> void:
	var now := Time.get_ticks_msec()
	var s := sheet_m2()
	s[CooldownTracker.RX_KEY] = now - 5000
	s["pending"] = { "party_invite": { "from_char": "ch_a", "name": "阿甲", "left_s": 60 },
		"challenges": [ { "from_char": "ch_b", "name": "小乙", "left_s": 3 } ] }
	var rows := UiSocial.pending_rows(s, now)
	assert_eq(rows.size(), 1, "challenge with 3 s left expired after 5 s")
	assert_eq(rows[0]["type"], "party")
	assert_eq(int(rows[0]["left"]), 55)
	assert_true(UiSocial.pending_text(rows[0]).contains("阿甲"))
	s[CooldownTracker.RX_KEY] = now
	var pp := PendingPrompts.new()
	_add(pp)
	var sent: Array = []
	pp.gate = _gate(sent)
	pp.apply_sheet(s)
	assert_eq(pp.rows.size(), 2)
	assert_true(pp.visible)
	# 重連後同一份 sheet 再來一次：一樣兩個（不重複）
	pp.apply_sheet(s.duplicate(true))
	assert_eq(pp.rows.size(), 2)
	pp._moved_ms = -100000
	pp.answer("challenge:ch_b", false)
	assert_eq(sent[0], ["challenge_reply", { "from": "ch_b", "accept": false }])
	# M2 審查：回覆的列留在原位、停用並顯示「已回覆」，下面的列不會移到游標底下
	assert_eq(pp.rows.size(), 2, "answered prompt stays in place")
	assert_true((pp.rows["challenge:ch_b"]["yes"] as Button).disabled, "answered row disabled")
	assert_eq((pp.rows["challenge:ch_b"]["countdown"] as Label).text, PendingPrompts.ANSWERED_TEXT)
	assert_eq(pp.answer("challenge:ch_b", true), -1, "second click on an answered row ignored")
	assert_eq(sent.size(), 1)
	pp.answer("party:ch_a", true)
	assert_eq(sent[1], ["party_reply", { "from": "ch_a", "accept": true }])
	assert_true(pp.visible, "still shown until the host updates")
	# 主機更新後不再列：清掉回覆標記；新的邀請再出現
	var s2 := sheet_m2()
	pp.apply_sheet(s2)
	assert_eq(pp._answered.size(), 0)
	assert_eq(pp.rows.size(), 0, "removed once the host stops listing them")
	assert_false(pp.visible)
	# 有列剛移除：MOVE_GUARD_MS 內的點擊不算
	s2["pending"] = { "party_invite": {}, "challenges": [ { "from_char": "ch_b", "name": "小乙", "left_s": 60 } ] }
	s2[CooldownTracker.RX_KEY] = Time.get_ticks_msec()
	pp.apply_sheet(s2)
	pp._moved_ms = Time.get_ticks_msec()
	assert_eq(pp.answer("challenge:ch_b", true), -1, "click right after rows moved is ignored")
	assert_true(UiSocial.pending_head(pp.rows["challenge:ch_b"]["row"]).contains("生死自負"), "challenge warns the loser can die")
	assert_true((pp.rows["challenge:ch_b"]["yes"] as Button).tooltip_text.contains("輸了會死"))
	s2["pending"] = {}
	pp.apply_sheet(s2)
	s2["pending"] = { "party_invite": { "from_char": "ch_a", "name": "阿甲", "left_s": 60 }, "challenges": [] }
	s2[CooldownTracker.RX_KEY] = Time.get_ticks_msec()
	pp.apply_sheet(s2)
	assert_eq(pp.rows.size(), 1, "rebuilt from sheet")

# ---------------------------------------------------------------- 5. 伺服器設定面板

static func server_opts() -> Dictionary:
	return { "editable": [
		{ "key": "rule_preset", "label": "死亡規則", "value": "classic_standard",
		  "choices": [ { "value": "classic_standard", "label": "懷舊標準（預設）" }, { "value": "classic_strict", "label": "懷舊嚴格" } ] },
		{ "key": "pk_mode", "label": "PK 模式", "value": "CLASSIC",
		  "choices": [ { "value": "CLASSIC", "label": "懷舊（叫戰＋強制 PK）" }, { "value": "CHALLENGE_ONLY", "label": "只能叫戰" }, { "value": "OFF", "label": "禁止 PK" } ] },
		{ "key": "wait_mode", "label": "戰鬥等待模式", "value": "true", "choices": [ { "value": "true", "label": "開" }, { "value": "false", "label": "關" } ] },
		{ "key": "stagecoach_enabled", "label": "驛站馬車（非原作）", "value": "false", "choices": [ { "value": "true", "label": "開" }, { "value": "false", "label": "關" } ] } ],
		"info": { "world_name": "朋友世界", "host_offline_policy": "FROZEN", "players": [
			{ "peer": 0, "name": "主機", "identity_short": "local_ab", "is_admin": true },
			{ "peer": 101, "name": "阿甲", "identity_short": "local_cd", "is_admin": false } ] } }

func test_server_options_panel_builds_controls() -> void:
	var d := ServerOptionsDialog.new()
	var sent: Array = []
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	d.apply_options(server_opts())
	assert_eq(d.selectors.size(), 4)
	var pk: OptionButton = d.selectors["pk_mode"]
	assert_eq(pk.item_count, 3)
	assert_eq(str(pk.get_item_metadata(pk.selected)), "CLASSIC", "current value selected")
	assert_true(d.info_label.text.contains("朋友世界") and d.info_label.text.contains("凍結"))
	d.select_value("pk_mode", "OFF")
	assert_eq(sent[0], ["server_opts_set", { "key": "pk_mode", "value": "OFF" }])
	await _frame()
	assert_eq(str(pk.get_meta("value")), "OFF", "committed after ok")
	# 踢人需要確認
	d.ask_kick(101, true, "阿甲")
	assert_true(d.confirm_row.visible)
	assert_true(d.confirm_label.text.contains("禁止"))
	d.confirm_kick()
	assert_eq(sent[1], ["admin_kick", { "peer": 101, "ban": true }])
	assert_false(d.confirm_row.visible)
	# 事件 server_options（ui）會重畫
	var o := server_opts()
	o["editable"][1]["value"] = "CHALLENGE_ONLY"
	d._on_events([{ "ch": "SYSTEM", "key": "server_options", "ui": true, "p": o }])
	pk = d.selectors["pk_mode"]
	assert_eq(str(pk.get_item_metadata(pk.selected)), "CHALLENGE_ONLY")

func test_server_option_reverts_on_failure() -> void:
	var d := ServerOptionsDialog.new()
	var sent: Array = []
	d.gate = _gate(sent, false, "not_admin")
	_add(d)
	await _frame()
	d.apply_options(server_opts())
	d.select_value("wait_mode", "false")
	await _frame()
	var ob: OptionButton = d.selectors["wait_mode"]
	assert_eq(str(ob.get_item_metadata(ob.selected)), "true", "reverted")
	assert_true(d.status_label.text != "", "reason shown")

# ---------------------------------------------------------------- 6. 屍體視窗

func test_corpse_dialog_button_states() -> void:
	var d := CorpseDialog.new()
	var sent: Array = []
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	# 保護期內、別人的：不能撿、沒有授權列
	d.open_corpse({ "id": "cp_1", "owner_name": "路人", "mine": false, "n_items": 3, "can_loot": false, "public": false, "left_s": 300, "authorized_me": false })
	assert_true(d.take_all_button.disabled)
	assert_false(d.auth_row.visible)
	assert_true(d.info_label.text.contains("保護期"))
	# 授權後：可以撿，單件與全部
	d.open_corpse({ "id": "cp_1", "owner_name": "路人", "mine": false, "n_items": 2, "can_loot": true, "public": false, "left_s": 290, "authorized_me": true,
		"items": [ { "uid": "it_1", "id": "w_dandao", "name": "單刀", "n": 1 }, { "uid": "it_2", "id": "c_qiyao", "name": "氣藥", "n": 2 } ] })
	assert_false(d.take_all_button.disabled)
	assert_eq(d.items_box.get_child_count(), 2)
	assert_true(d.info_label.text.contains("允許你"))
	d.take_one("it_1")
	d.take_all()
	assert_eq(sent[0], ["loot_corpse", { "corpse_id": "cp_1", "item_uid": "it_1" }])
	assert_eq(sent[1], ["loot_corpse", { "corpse_id": "cp_1" }])
	# 自己的屍體：有授權列
	d.open_corpse({ "id": "cp_2", "owner_name": "我", "mine": true, "n_items": 1, "can_loot": true, "public": true, "left_s": 900,
		"items": [ { "uid": "it_9", "id": "a_buyi", "name": "布衣", "n": 1 } ] })
	assert_true(d.auth_row.visible)
	assert_true(d.info_label.text.contains("誰都能翻動"))
	d.authorize("  阿甲 ")
	assert_eq(sent[2], ["corpse_authorize", { "corpse_id": "cp_2", "name": "阿甲" }])
	# 房間更新：屍體不在了 → 關掉
	d.refresh_from_view({ "corpses": [] })
	assert_false(d.visible)
	# 舊主機（沒有 can_loot）：只有自己的能撿
	d.open_corpse({ "id": "cp_3", "owner_name": "我", "mine": true, "n_items": 1 })
	assert_true(d.can_loot())

# ---------------------------------------------------------------- 7. 玩家選單、強制 PK、場景卷軸

func test_player_menu_and_force_pk_checks() -> void:
	var v := view_m2(true)
	var a: Dictionary = v["players"][1]
	var newbie: Dictionary = v["players"][2]
	var s := sheet_m2()
	var acts := UiSocial.player_menu(a, s).map(func(x): return x[0])
	assert_eq(acts, ["invite", "challenge", "whisper", "mail", "force_pk"])
	var ps := party_sheet(true)
	acts = UiSocial.player_menu(a, ps).map(func(x): return x[0])
	assert_eq(acts, ["whisper", "mail", "kick", "lead"], "leader menu for a party mate")
	acts = UiSocial.player_menu(a, party_sheet(false)).map(func(x): return x[0])
	assert_eq(acts, ["whisper", "mail"], "non-leader cannot kick")
	assert_eq(UiSocial.force_pk_block(a, v, s, "CLASSIC"), "")
	assert_eq(UiSocial.force_pk_block(newbie, v, s, "CLASSIC"), "target_newbie_protected")
	assert_eq(UiSocial.force_pk_block(a, view_m2(false), s, "CLASSIC"), "pk_not_allowed_here")
	assert_eq(UiSocial.force_pk_block(a, v, s, "OFF"), "pk_disabled")
	assert_eq(UiSocial.force_pk_block(a, v, s, "CHALLENGE_ONLY"), "pk_challenge_only")
	assert_eq(UiSocial.force_pk_block(a, v, ps, "CLASSIC"), "target_in_party")
	assert_eq(UiSocial.challenge_block(newbie, v, s, "CHALLENGE_ONLY"), "", "challenge ignores newbie / challenge-only")
	assert_eq(UiSocial.align_color("EVIL"), Color("4060ff"))
	assert_eq(UiSocial.align_color("NEUTRAL"), Color("f0d060"))
	assert_eq(UiSocial.align_color("GOOD"), Color.WHITE)

func test_scene_panel_players_battles_and_ctrl_click() -> void:
	var sp := ScenePanel.new()
	_add(sp)
	await _frame()
	var sent: Array = []
	sp.gate = _gate(sent)
	sp.apply_sheet(sheet_m2())
	sp.apply_view(view_m2(true))
	assert_eq(sp.player_buttons.size(), 2, "self is a label, others are buttons")
	var evil: Button = sp.player_buttons["ch_a"]
	assert_eq(evil.get_theme_color("font_color"), Color("4060ff"), "evil name blue")
	var actions: Array = []
	sp.player_action.connect(func(act, p): actions.append([act, str(p.get("char_id", ""))]))
	sp.on_player_clicked(view_m2()["players"][1], true)
	assert_eq(actions[0], ["force_pk", "ch_a"], "Ctrl+click → force PK")
	sp.on_player_clicked(view_m2()["players"][1], false)
	assert_eq(sp.menu_actions(), ["invite", "challenge", "whisper", "mail", "force_pk"])
	sp.choose_menu_action("invite")
	assert_eq(actions[1], ["invite", "ch_a"])
	# 加入戰鬥：只有 joinable 的是按鈕
	assert_true(sp.battles_box.get_parent().visible)
	var join: Button = null
	for c in sp.battles_box.get_children():
		if c is Button:
			join = c
	assert_true(join != null and join.text.contains("加入戰鬥"))
	sp._on_join_battle(7, join)
	assert_eq(sent[0], ["battle_join", { "battle_id": 7 }])
	# 屍體：點了發 corpse_opened
	var v := view_m2()
	v["corpses"] = [ { "id": "cp_9", "owner_name": "小乙", "mine": false, "n_items": 2, "can_loot": true } ]
	sp.apply_view(v)
	var opened: Array = []
	sp.corpse_opened.connect(func(c): opened.append(str(c.get("id", ""))))
	(sp.corpses_box.get_child(0) as Button).pressed.emit()
	assert_eq(opened, ["cp_9"])

func test_main_screen_force_pk_confirm_and_mail_compose() -> void:
	var ms: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	var sent: Array = []
	ms.gate.set_sender(func(kind, args):
		sent.append([kind, args])
		return -1)
	ms.apply_sheet(sheet_m2())
	ms.apply_view(view_m2(true))
	var p: Dictionary = view_m2()["players"][1]
	ms._on_player_action("force_pk", p)
	assert_true(ms.confirm_dialog.visible, "confirm first")
	assert_eq(sent.size(), 0)
	ms.confirm_dialog.confirm()
	assert_eq(sent[0], ["force_pk", { "target": "ch_a" }])
	# 新手：不送、不開確認
	ms._on_player_action("force_pk", view_m2()["players"][2])
	assert_false(ms.confirm_dialog.visible)
	assert_eq(sent.size(), 1)
	ms._on_player_action("mail", p)
	assert_true(ms.mail_dialog.visible)
	assert_eq(ms.mail_dialog.to_edit.text, "阿甲")
	ms._on_player_action("whisper", p)
	assert_eq(ms.message_log.talk_channel, "傳音入密")
	ms._on_player_action("invite", p)
	assert_eq(sent[sent.size() - 1], ["party_invite", { "target": "ch_a" }])
	# 隊伍面板：有隊伍才顯示
	assert_false(ms.party_frame.visible)
	ms.apply_sheet(party_sheet(true))
	assert_true(ms.party_frame.visible)
	assert_eq(ms.party_frame.member_rows.size(), 2)

# ---------------------------------------------------------------- 8. 隊伍面板

func test_party_frame_leader_controls() -> void:
	var pf := PartyFrame.new()
	_add(pf)
	await _frame()
	var sent: Array = []
	pf.gate = _gate(sent)
	pf.apply_sheet(sheet_m2())
	assert_false(pf.visible)
	pf.apply_sheet(party_sheet(true))
	assert_true(pf.visible)
	assert_true(pf.title_label.text.contains("2"))
	var row_a: HBoxContainer = pf.member_rows["ch_a"]
	assert_eq(row_a.get_child_count(), 5, "leader sees 戰鬥中 tag, 領, a gap and 踢 for others")
	# M2 審查：戰鬥中是獨立、不截斷的標籤；主文不含戰鬥中
	var tag := row_a.find_child("Battle_ch_a", false, false) as Label
	assert_true(tag != null and tag.text == "戰鬥中", "in-battle tag visible")
	assert_false((row_a.get_child(0) as Label).text.contains("戰鬥中"))
	assert_eq((pf.member_rows["ch_me"] as HBoxContainer).get_child_count(), 1)
	assert_true(UiSocial.member_line(party_sheet()["party"]["members"][1]).contains("戰鬥中"))
	pf.kick("ch_a")
	pf.lead_to("ch_a")
	pf.leave()
	assert_eq(sent, [["party_kick", { "target": "ch_a" }], ["party_lead", { "target": "ch_a" }], ["party_leave", {}]])
	pf.apply_sheet(party_sheet(false))
	assert_eq((pf.member_rows["ch_a"] as HBoxContainer).get_child_count(), 2, "non-leader has no controls (label + 戰鬥中 tag)")

# ---------------------------------------------------------------- 9. 飛鴿視窗

func test_mail_dialog_inbox_read_delete_compose() -> void:
	var d := MailDialog.new()
	var sent: Array = []
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	d.apply_mail_list([
		{ "id": "ml_2", "from_name": "阿甲", "text": "晚上狼嚎丘見", "sent_clock": "第 3 日 戌時", "read": false },
		{ "id": "ml_1", "from_name": "小乙", "text": "謝啦", "sent_clock": "第 2 日 辰時", "read": true } ])
	assert_eq(d.mail_buttons.size(), 2)
	assert_eq(d.unread_count(), 1)
	d.select_mail("ml_2")
	assert_eq(d.read_text.text, "晚上狼嚎丘見")
	assert_eq(sent[0], ["mail_read", { "id": "ml_2" }], "unread → mail_read")
	d.select_mail("ml_1")
	assert_eq(sent.size(), 1, "already read: no intent")
	d.delete_selected()
	assert_eq(sent[1], ["mail_delete", { "id": "ml_1" }])
	d.compose_to("阿甲")
	assert_true(d.compose_page.visible)
	d.body_edit.text = "字".repeat(250)
	d._on_body_changed()
	assert_eq(d.body_edit.text.length(), UiKeys.MAIL_MAX_LEN, "200 字上限")
	d.body_edit.text = "收到"
	d.send_mail()
	assert_eq(sent[2], ["mail_send", { "to": "阿甲", "text": "收到" }])
	# mail_list 事件（ui）重畫
	d._on_events([{ "ch": "MAIL", "key": "mail_list", "ui": true, "p": { "mails": [] } }])
	assert_eq(d.mails.size(), 0)
	# M2 審查：空的收件匣不顯示回信／刪除，讀信欄放寫信說明和「寫信」鈕
	assert_false(d.reply_row.visible, "reply/delete hidden when empty")
	assert_true(d.write_button.visible)
	assert_true(d.read_text.text.contains("放出信鴿"), d.read_text.text)
	d.write_button.pressed.emit()
	assert_true(d.compose_page.visible, "寫信 opens the compose tab")
	d.apply_mail_list([{ "id": "ml_3", "from_name": "阿甲", "text": "嗨", "sent_clock": "", "read": true }])
	assert_true(d.reply_row.visible and not d.write_button.visible, "buttons back with mail")

# ---------------------------------------------------------------- 10. 系統窗特殊開關

func test_system_panel_prefs_and_admin_button() -> void:
	var sp := SystemPanel.new()
	var sent: Array = []
	sp.gate = _gate(sent)
	_add(sp)
	await _frame()
	var s := sheet_m2()
	s["prefs"] = { "accept_challenge": false, "accept_party": true }
	sp.apply_sheet(s)
	sp.show_page("特殊開關")
	var cb: CheckButton = sp.pref_buttons["accept_challenge"]
	assert_false(cb.button_pressed, "mirrors sheet.prefs")
	assert_false(sp.admin_button.visible, "only admins")
	cb.button_pressed = true
	assert_eq(sent[0], ["set_pref", { "key": "accept_challenge", "value": true }])
	s["is_admin"] = true
	sp.apply_sheet(s)
	assert_true(sp.admin_button.visible)
	var asked := [false]
	sp.server_options_requested.connect(func(): asked[0] = true)
	sp.admin_button.pressed.emit()
	assert_true(asked[0])

# ---------------------------------------------------------------- 11. 連線

func test_disconnect_classification() -> void:
	var router := tree.root.get_node("SceneRouter")
	var d: Dictionary = router.classify_disconnect("連線結束：server_disconnected", false)
	assert_eq(d["kind"], "HOST_CLOSED")
	assert_true(str(d["text"]).contains("主機已離線，江湖凍結"))
	d = router.classify_disconnect("whatever", true)
	assert_eq(d["kind"], "HOST_CLOSED", "host_closing seen")
	d = router.classify_disconnect("被主機請出：admin", false)
	assert_eq(d["kind"], "KICKED")
	assert_true(bool(d["can_reconnect"]))
	d = router.classify_disconnect("被主機請出：banned", false)
	assert_false(bool(d["can_reconnect"]))
	assert_eq(UiSocial.reject_text("banned"), "你被主機禁止進入這個江湖。")

func test_reconnect_flow_retries_three_times() -> void:
	var rf := ReconnectFlow.new()
	_add(rf)
	var calls := [0]
	rf.reconnect_fn = func() -> int:
		calls[0] += 1
		return OK
	var done: Array = []
	rf.finished.connect(func(ok): done.append(ok))
	rf.start()
	assert_eq(calls[0], 1)
	for i in 3:
		rf.on_failed("連不上主機")
		rf.advance(ReconnectFlow.RETRY_DELAY_S - 0.5)
		assert_eq(calls[0], i + 1, "waits 5 s")
		rf.advance(0.6)
		assert_eq(calls[0], i + 2, "retry %d" % (i + 1))
	rf.on_failed("連不上主機")
	rf.advance(10.0)
	assert_eq(calls[0], 4, "1 attempt + 3 retries")
	assert_eq(done, [false])
	# 成功
	rf.start()
	rf._on_welcomed({})
	assert_eq(done, [false, true])
	# 被拒（禁止）就停
	rf.start()
	rf._on_rejected("banned")
	assert_eq(done, [false, true, false])
	assert_false(rf.running)

func test_lobby_version_gray_out() -> void:
	var TitleScript: GDScript = load("res://ui/game/title/title_screen.gd")
	var TL = TitleScript.TitleLobby
	assert_true(TL.compatible({ "proto": str(Protocol.VERSION) }))
	assert_false(TL.compatible({ "proto": "1" }))
	assert_true(TL.label({ "name": "房", "members": 2, "proto": "1" }).contains("版本不符"))

func test_passport_dialog_lists_and_restores() -> void:
	var d := PassportDialog.new()
	var sent: Array = []
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	assert_true(d.note_label.text.contains("不是防作弊"), "honest note (4.6.8)")
	var pp := { "v": 1, "world_id": "w1", "char_id": "ch_me", "identity": "local_x", "name": "我", "char": {}, "sig": "ab", "saved_s": 7260.0 }
	d.apply_entries([{ "char_id": "ch_me", "name": "我", "saved_s": 7260.0, "data": pp }])
	assert_eq(d.list_box.get_child_count(), 1)
	d.restore(d.entries[0])
	assert_eq(sent[0], ["passport_restore", { "passport": pp }])
	assert_eq(PassportDialog.online_text(7260.0), "2 小時 1 分")
	d.apply_entries([])
	assert_eq(d.list_box.get_child_count(), 1, "empty hint row")

# ---------------------------------------------------------------- 12. 字串與 Protocol 一致（4.1；Day-0 協定落地後才比對）

func test_ui_keys_match_protocol() -> void:
	assert_eq(UiKeys.M2_INTENTS.size(), 21)
	assert_eq(UiKeys.CHAT_CHANNELS, ["CHAT_WORLD", "CHAT_WHISPER", "CHAT_SAY", "CHAT_SECT", "CHAT_GUILD", "CHAT_PARTY", "CHAT_RUMOR", "GM"])
	for k in ["battle_unit_join", "mail_list", "server_options", "world_info_changed", "passport"]:
		assert_has(UiKeys.UI_ONLY_KEYS, k)
	if Protocol.VERSION < 3:
		return
	for kind in UiKeys.M2_INTENTS:
		assert_true(Protocol.is_known(kind), "Protocol knows " + kind)
	var consts := (Protocol as GDScript).get_script_constant_map()
	if consts.has("CHAT_CHANNELS"):
		assert_eq(consts["CHAT_CHANNELS"], UiKeys.CHAT_CHANNELS)
	if consts.has("PREF_KEYS"):
		assert_eq(consts["PREF_KEYS"], UiKeys.PREF_KEYS)
	if consts.has("PK_MODES"):
		assert_eq(consts["PK_MODES"], UiKeys.PK_MODES)
	if consts.has("MAIL_MAX_LEN"):
		assert_eq(consts["MAIL_MAX_LEN"], UiKeys.MAIL_MAX_LEN)

func test_attributes_lists_my_corpses() -> void:
	var s := sheet_m2()
	assert_eq(AttributesPanel.corpse_lines(s), "")
	s["my_corpses"] = [ { "id": "cp_1", "room_name": "東門外官道", "public": false, "left_s": 300, "n_items": 3 } ]
	var t := AttributesPanel.corpse_lines(s)
	assert_true(t.contains("東門外官道") and t.contains("3 件") and t.contains("5 分 0 秒"), t)
