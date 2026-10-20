extends "res://tests/test_case.gd"
## 故事包 WP-UI（STORY_PLAN §6.1）：任務對話視窗 StoryDialog——dialogue（ui）事件的顯示、逐字顯示與跳過、
## 選項送出的 dialogue_choose、上鎖選項、「繼續」「結束」、Esc／⊠ 的 dialogue_close、主機收回；
## 主畫面的接線（開對話、移動與開戰時收起）；NPC 選單任務項的 quest_talk（詳談／交談）。全部用假資料。

const Scenes := preload("res://tests/unit/test_ui_scenes.gd")

var _nodes: Array = []
var _saved_quests: Variant = null
var _saved_sheet: Variant = null

func before_each() -> void:
	UiSettings.reset_for_tests(true)

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_restore_data()
	await tree.process_frame

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _gate(sent: Array, ok := true, reason := "") -> IntentGate:
	var g := IntentGate.new()
	_add(g)
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		var seq := sent.size()
		g.resolve.call_deferred(seq, ok, reason)
		return seq)
	return g

func _frames(n := 2) -> void:
	for i in n:
		await tree.process_frame

## 測試期間在 GameData 的 quests 表放一條假任務（第 2 版格式），結束後還原
func _fake_quest(row: Dictionary) -> void:
	var gd := tree.root.get_node_or_null("GameData")
	if gd == null:
		return
	if _saved_quests == null:
		_saved_quests = (gd.tables.get("quests", {}) as Dictionary).duplicate()
	if not gd.tables.has("quests"):
		gd.tables["quests"] = {}
	gd.tables["quests"][str(row["id"])] = row

func _fake_sheet(s: Dictionary) -> void:
	var cs := tree.root.get_node_or_null("ClientState")
	if cs == null:
		return
	if _saved_sheet == null:
		_saved_sheet = cs.get("sheet")
	cs.set("sheet", s)

func _restore_data() -> void:
	var gd := tree.root.get_node_or_null("GameData")
	if gd != null and _saved_quests != null:
		gd.tables["quests"] = _saved_quests
	_saved_quests = null
	var cs := tree.root.get_node_or_null("ClientState")
	if cs != null and _saved_sheet != null:
		cs.set("sheet", _saved_sheet)
	_saved_sheet = null

static func node(node_id := "n0", choices: Array = [], end := false) -> Dictionary:
	return { "npc": "n_xx_yuner", "npc_name": "雲兒", "quest": "q_yuner", "quest_name": "雲兒小姐的煩惱",
		"dlg": "d_choose", "node": node_id, "speaker_name": "雲兒", "text": "你都見過他們了？你說，我該選誰？",
		"choices": choices, "end": end }

static func two_choices() -> Array:
	return [ { "id": "c_abao", "label": "阿寶對妳一片真心。", "locked": false, "why": "" },
		{ "id": "c_li", "label": "李台安有份正當差事。", "locked": true, "why": "你還沒見過李台安" } ]

func _dialog(sent: Array, ok := true, reason := "") -> StoryDialog:
	var d := StoryDialog.new()
	d.gate = _gate(sent, ok, reason)
	_add(d)
	return d

func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k

# ---------------------------------------------------------------- 顯示

func test_open_node_shows_names_text_and_types_out() -> void:
	var d := _dialog([])
	await tree.process_frame
	d.open_node(node("n0", two_choices()))
	assert_true(d.visible)
	assert_eq(d.title_label.text, "雲兒", "NPC 名在上方")
	assert_eq(d.quest_label.text, "任務：雲兒小姐的煩惱")
	assert_eq(d.speaker_label.text, "雲兒")
	assert_false(d.speaker_label.visible, "審查修正：NPC 自己說話時不重複顯示說話者（名牌已有名字）")
	assert_eq(d.name_plate.text, "雲兒", "立繪下方名牌（AUTHENTIC_UI_SPEC §8.7）")
	assert_eq(d.dialog_size(), Vector2(680, 416), "§8.7 尺寸")
	assert_eq(d.portrait.custom_minimum_size, Vector2(180, 240), "§8.7 立繪框")
	var p2 := node("n1", two_choices())
	p2["speaker_name"] = "李台安"
	d.open_node(p2)
	assert_true(d.speaker_label.visible, "第三人說話時顯示說話者")
	assert_eq(d.speaker_label.text, "李台安")
	d.open_node(node("n0", two_choices()))
	assert_eq(d.text_label.text, "你都見過他們了？你說，我該選誰？")
	assert_true(d.is_typing(), "逐字顯示中")
	assert_false(d.choices_box.visible, "逐字顯示完之前不顯示選項")
	d.skip_typing()
	assert_false(d.is_typing())
	assert_true(d.choices_box.visible)
	assert_eq(d.choice_ids(), ["c_abao", "c_li"])
	assert_eq((d.choice_buttons[0] as Button).text, "阿寶對妳一片真心。")

func test_typing_finishes_by_itself() -> void:
	var d := _dialog([])
	await tree.process_frame
	d.open_node(node("n0", two_choices()))
	d._process(5.0)   # 5 秒 × 40 字／秒，整段都出來了
	assert_false(d.is_typing())
	assert_true(d.choices_box.visible)

func test_locked_choice_is_grey_with_reason() -> void:
	var sent: Array = []
	var d := _dialog(sent)
	await tree.process_frame
	d.open_node(node("n0", two_choices()))
	d.skip_typing()
	var locked: Button = d.choice_buttons[1]
	assert_true(locked.disabled, "上鎖的選項灰色")
	assert_eq(locked.tooltip_text, "你還沒見過李台安", "滑鼠提示 why")
	d.choose_index(1)
	assert_eq(sent.size(), 0, "上鎖的選項不送")

func test_choice_sends_dialogue_choose_with_cursor() -> void:
	var sent: Array = []
	var d := _dialog(sent)
	await tree.process_frame
	d.open_node(node("n0", two_choices()))
	d.skip_typing()
	d.choose_index(0)
	assert_eq(sent, [["dialogue_choose", { "npc": "n_xx_yuner", "quest": "q_yuner", "node": "n0", "choice": "c_abao" }]])
	d.choose_index(0)
	assert_eq(sent.size(), 1, "等主機回覆時不重送")
	await _frames()
	assert_true((d.choice_buttons[1] as Button).disabled, "解鎖後上鎖的選項仍是灰的")
	# 主機回下一句
	d.open_node(node("n_abao", [], true))
	assert_eq(d.node_id(), "n_abao")
	d.skip_typing()
	assert_eq(d.choice_ids(), ["__end"], "結束節點只剩「結束」")

func test_choice_failure_shows_reason_and_allows_retry() -> void:
	var sent: Array = []
	var d := _dialog(sent, false, "dialogue_stale")
	await tree.process_frame
	d.open_node(node("n0", two_choices()))
	d.skip_typing()
	d.choose_index(0)
	await _frames()
	assert_true(d.visible, "失敗時留著")
	assert_true(d.status_label.text != "", "顯示原因")
	assert_false(d.status_label.text.contains("【"), "內嵌原因不帶頻道標籤：" + d.status_label.text)
	d.choose_index(0)
	assert_eq(sent.size(), 2, "可以再選")

func test_digit_key_skips_then_chooses() -> void:
	var sent: Array = []
	var d := _dialog(sent)
	await tree.process_frame
	d.open_node(node("n0", two_choices()))
	d._unhandled_key_input(_key(KEY_1))
	assert_eq(sent.size(), 0, "逐字顯示中按數字鍵只跳過")
	assert_false(d.is_typing())
	d._unhandled_key_input(_key(KEY_1))
	assert_eq(sent.size(), 1)
	assert_eq(sent[0][1]["choice"], "c_abao")

func test_goto_node_has_continue() -> void:
	var sent: Array = []
	var d := _dialog(sent)
	await tree.process_frame
	d.open_node(node("n1", [], false))
	d.skip_typing()
	assert_eq(d.choice_ids(), [StoryDialog.CONTINUE_CHOICE])
	assert_eq((d.choice_buttons[0] as Button).text, "繼續……")
	d._unhandled_key_input(_key(KEY_ENTER))
	assert_eq(sent, [["dialogue_choose", { "npc": "n_xx_yuner", "quest": "q_yuner", "node": "n1", "choice": "" }]])

func test_end_node_closes_without_sending() -> void:
	var sent: Array = []
	var d := _dialog(sent)
	await tree.process_frame
	d.open_node(node("n_li", [], true))
	d.skip_typing()
	assert_true(d.find_child("StoryLeave", true, false) == null, "結束節點沒有另一顆「結束對話」")
	d.choose_index(0)
	assert_false(d.visible)
	d.open_node(node("n_li", [], true))
	d.close()   # Esc
	assert_false(d.visible)
	assert_eq(sent.size(), 0, "結束後主機已清掉游標，不送 dialogue_close")

func test_close_mid_dialogue_sends_close() -> void:
	var sent: Array = []
	var d := _dialog(sent)
	await tree.process_frame
	d.open_node(node("n0", two_choices()))
	d.skip_typing()
	var leave := d.find_child("StoryLeave", true, false) as Button
	assert_true(leave != null, "選項外有「結束對話」")
	leave.pressed.emit()
	assert_false(d.visible)
	assert_eq(sent, [["dialogue_close", {}]])

func test_host_close_only_for_same_npc() -> void:
	var sent: Array = []
	var d := _dialog(sent)
	await tree.process_frame
	d.open_node(node("n0", two_choices()))
	d.on_closed({ "npc": "n_other" })
	assert_true(d.visible, "別的 NPC 的 dialogue_close 不關")
	d.on_closed({ "npc": "n_xx_yuner" })
	assert_false(d.visible)
	d.open_node(node("n0", two_choices()))
	d.dismiss()
	assert_false(d.visible)
	assert_eq(sent.size(), 0, "主機收回的不送")

# ---------------------------------------------------------------- 主畫面

func _main(sent: Array) -> Control:
	var main: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	main.gate.set_sender(func(kind, args):
		sent.append([kind, args])
		return -1)
	main.apply_sheet(Scenes.fake_sheet())
	main.apply_view(Scenes.fake_view())
	return main

func test_main_screen_opens_and_closes_story_dialog() -> void:
	var sent: Array = []
	var main = await _main(sent)
	main.handle_event({ "ch": "SYSTEM", "key": "npc_menu", "ui": true, "p": { "npc": "n_xx_yuner", "npc_name": "雲兒",
		"services": ["QUEST"], "closed": false, "quests": [], "routes": [], "inn_price": 0 } })
	assert_true(main.npc_dialog.visible)
	main.handle_event({ "ch": "SYSTEM", "key": "dialogue", "ui": true, "p": node("n0", two_choices()) })
	var d: StoryDialog = main.story_dialog
	assert_true(d.visible, "dialogue 開對話視窗")
	assert_false(main.npc_dialog.visible, "和服務選單互斥")
	main.handle_event({ "ch": "SYSTEM", "key": "dialogue", "ui": true, "p": node("n_abao", [], true) })
	assert_eq(d.node_id(), "n_abao", "下一句就地更新")
	main.handle_event({ "ch": "SYSTEM", "key": "dialogue_close", "ui": true, "p": { "npc": "n_xx_yuner" } })
	assert_false(d.visible)
	# 移動：換房間就收起（主機已清掉游標，不送）
	main.handle_event({ "ch": "SYSTEM", "key": "dialogue", "ui": true, "p": node("n0", two_choices()) })
	var v: Dictionary = Scenes.fake_view()
	v["room"] = "xw_road"
	v["room_name"] = "大道"
	main.apply_view(v)
	assert_false(d.visible, "移動時收起")
	assert_false(sent.any(func(x): return x[0] == "dialogue_close"), "移動收起不送 dialogue_close")
	# Esc：送 dialogue_close
	main.handle_event({ "ch": "SYSTEM", "key": "dialogue", "ui": true, "p": node("n0", two_choices()) })
	main._shortcut_input(_key(KEY_ESCAPE))
	assert_false(d.visible)
	assert_true(sent.any(func(x): return x[0] == "dialogue_close"), "Esc 送 dialogue_close")

func test_battle_closes_story_dialog() -> void:
	var main = await _main([])
	main.handle_event({ "ch": "SYSTEM", "key": "dialogue", "ui": true, "p": node("n0", two_choices()) })
	assert_true(main.story_dialog.visible)
	main.open_battle(Scenes._battle_state())
	await tree.process_frame
	assert_false(main.story_dialog.visible, "開戰時收起")
	main.handle_event({ "ch": "SYSTEM", "key": "dialogue", "ui": true, "p": node("n0", two_choices()) })
	assert_false(main.story_dialog.visible, "戰鬥中不開")

# ---------------------------------------------------------------- NPC 選單的任務項

func _npc_dialog(sent: Array) -> NpcDialog:
	var d := NpcDialog.new()
	d.gate = _gate(sent)
	_add(d)
	return d

func test_npc_menu_available_with_offer_sends_quest_talk() -> void:
	_fake_quest({ "id": "q_ui_story", "name": "測試故事", "giver": "n_xx_yuner", "offer": "d_offer", "start": "s1",
		"stages": [ { "id": "s1", "title": "一", "objectives": [ { "id": "o1", "type": "TALK", "npc": "n_xx_litaian" } ], "next": "END" } ] })
	var sent: Array = []
	var d := _npc_dialog(sent)
	await tree.process_frame
	d.open_menu({ "npc": "n_xx_yuner", "npc_name": "雲兒", "services": ["QUEST"],
		"quests": [ { "id": "q_ui_story", "name": "測試故事", "state": "AVAILABLE", "chapter": "西夏" },
			{ "id": "q_rabbit", "name": "大兔皮", "state": "AVAILABLE" } ] })
	d.show_quests()
	var talk := d.find_child("QuestTalk_q_ui_story", true, false) as Button
	assert_true(talk != null and talk.text == "詳談", "有 offer 對話的任務：詳談")
	talk.pressed.emit()
	assert_eq(sent[0], ["quest_talk", { "npc": "n_xx_yuner", "quest": "q_ui_story" }])
	var accept_found := false
	for b in d.detail_box.find_children("*", "Button", true, false):
		if (b as Button).text == "接受":
			accept_found = true
	assert_true(accept_found, "沒有 offer 的舊任務仍是「接受」")

func test_npc_menu_active_objective_here_sends_quest_talk() -> void:
	_fake_quest({ "id": "q_ui_story", "name": "測試故事", "giver": "n_xx_yuner", "start": "s1",
		"stages": [ { "id": "s1", "title": "一", "objectives": [ { "id": "o1", "type": "TALK", "npc": "n_xx_litaian", "dialogue": "d_li" } ], "next": "END" } ] })
	_fake_sheet({ "quests": [ { "id": "q_ui_story", "name": "測試故事", "stage": "s1",
		"objectives": [ { "text": "找李台安", "have": 0, "need": 1, "done": false } ] } ] })
	var sent: Array = []
	var d := _npc_dialog(sent)
	await tree.process_frame
	d.open_menu({ "npc": "n_xx_litaian", "npc_name": "李台安", "services": ["QUEST"],
		"quests": [ { "id": "q_ui_story", "name": "測試故事", "state": "ACTIVE" } ] })
	d.show_quests()
	var talk := d.find_child("QuestTalk_q_ui_story", true, false) as Button
	assert_true(talk != null and talk.text == "交談", "目前目標在這位 NPC：交談")
	talk.pressed.emit()
	assert_eq(sent[0], ["quest_talk", { "npc": "n_xx_litaian", "quest": "q_ui_story" }])
	# 別的 NPC：沒有交談鈕
	d.open_menu({ "npc": "n_xx_yuner", "npc_name": "雲兒", "services": ["QUEST"],
		"quests": [ { "id": "q_ui_story", "name": "測試故事", "state": "ACTIVE" } ] })
	d.show_quests()
	assert_true(d.find_child("QuestTalk_q_ui_story", true, false) == null, "目標不在這裡就只顯示進行中")

func test_npc_menu_cooldown_label() -> void:
	var d := _npc_dialog([])
	await tree.process_frame
	d.open_menu({ "npc": "n_ym_lingzhi", "npc_name": "靈芝商人", "services": ["QUEST"],
		"quests": [ { "id": "q_xingxia", "name": "行俠仗義", "state": "COOLDOWN", "left_s": 1200.0 } ] })
	d.show_quests()
	var txt := ""
	for l in d.detail_box.find_children("*", "Label", true, false):
		if (l as Label).text.contains("行俠仗義"):
			txt = (l as Label).text
	assert_true(txt.contains("冷卻中") and txt.contains("時辰"), txt)
	assert_eq(d.detail_box.find_children("*", "Button", true, false).size(), 0, "冷卻中沒有按鈕")

# ---------------------------------------------------------------- 協定值

## UiKeys 的故事包常數 = STORY_PLAN §4.14 的字串；Protocol（WP-ENGINE）已登錄時兩邊要一致
func test_story_keys_match_contract_and_protocol() -> void:
	assert_eq(UiKeys.STORY_INTENTS, ["quest_talk", "dialogue_choose", "dialogue_close", "story_act", "villain_reply", "rumor_list"])
	assert_eq([UiKeys.E_DIALOGUE, UiKeys.E_DIALOGUE_CLOSE, UiKeys.E_QUEST_STAGE, UiKeys.E_QUEST_FAIL, UiKeys.E_RUMOR,
		UiKeys.E_RUMOR_LIST, UiKeys.E_VILLAIN_PROMPT, UiKeys.E_VILLAIN_CLEAR],
		["dialogue", "dialogue_close", "quest_stage", "quest_fail", "jianghu_rumor", "rumor_list", "villain_prompt", "villain_clear"])
	assert_eq(UiKeys.CH_JIANGHU, "JIANGHU")
	var scr := load("res://core/protocol.gd") as GDScript
	if scr == null:
		return
	var consts := scr.get_script_constant_map()
	var pairs := { "I_QUEST_TALK": UiKeys.I_QUEST_TALK, "I_DIALOGUE_CHOOSE": UiKeys.I_DIALOGUE_CHOOSE,
		"I_DIALOGUE_CLOSE": UiKeys.I_DIALOGUE_CLOSE, "I_STORY_ACT": UiKeys.I_STORY_ACT, "I_VILLAIN_REPLY": UiKeys.I_VILLAIN_REPLY,
		"I_RUMOR_LIST": UiKeys.I_RUMOR_LIST, "E_DIALOGUE": UiKeys.E_DIALOGUE, "E_DIALOGUE_CLOSE": UiKeys.E_DIALOGUE_CLOSE,
		"E_QUEST_STAGE": UiKeys.E_QUEST_STAGE, "E_QUEST_FAIL": UiKeys.E_QUEST_FAIL, "E_RUMOR": UiKeys.E_RUMOR,
		"E_RUMOR_LIST": UiKeys.E_RUMOR_LIST, "E_VILLAIN_PROMPT": UiKeys.E_VILLAIN_PROMPT, "E_VILLAIN_CLEAR": UiKeys.E_VILLAIN_CLEAR,
		"CH_JIANGHU": UiKeys.CH_JIANGHU }
	for k in pairs:
		if consts.has(k):
			assert_eq(consts[k], pairs[k], "Protocol.%s" % k)
