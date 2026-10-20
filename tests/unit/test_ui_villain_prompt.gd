extends "res://tests/test_case.gd"
## 故事包 WP-UI（STORY_PLAN §6.4、§6.5）：惡人警告 VillainPrompt（倒數、迎戰、求救、villain_clear、換房間）、
## 主畫面接線；場景卷軸的任務動作（story_act）、【惡】標記、護送「（隨行）」。全部用假資料。

const Scenes := preload("res://tests/unit/test_ui_scenes.gd")

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

static func prompt(wid := "w_nanhai", can_call := true) -> Dictionary:
	return { "wid": wid, "npc_name": "南海鱷神", "countdown_s": 3.0, "can_call": can_call }

func _prompt(sent: Array, ok := true, reason := "") -> VillainPrompt:
	var v := VillainPrompt.new()
	v.gate = _gate(sent, ok, reason)
	_add(v)
	return v

func test_prompt_text_and_countdown() -> void:
	var v := _prompt([])
	await tree.process_frame
	v.open_prompt(prompt(), "xw_road")
	assert_true(v.visible)
	assert_eq(v.title_label.text, "南海鱷神朝你逼近！")
	assert_true(v.hint_label.text.contains("快離開這裡"))
	assert_eq(v.fight_button.text, "迎戰")
	assert_true(v.call_button.visible)
	assert_true(v.left_s() > 2.0 and v.left_s() <= 3.0)
	assert_eq(v.countdown_label.text, "3 秒")
	assert_true(v.countdown_bar.value > 0.0)
	v._deadline_ms = Time.get_ticks_msec() - 1
	v._update_countdown()
	assert_eq(v.countdown_label.text, "躲不掉了！")
	v.open_prompt(prompt("w_x", false))
	assert_false(v.call_button.visible, "can_call == false：不顯示求救")
	assert_eq(StoryUi.villain_text({}), "惡人朝你逼近！")

func test_fight_sends_reply_and_closes() -> void:
	var sent: Array = []
	var v := _prompt(sent)
	await tree.process_frame
	v.open_prompt(prompt())
	v.fight()
	assert_eq(sent, [["villain_reply", { "wid": "w_nanhai", "choice": "FIGHT" }]])
	await _frames()
	assert_false(v.visible, "迎戰成功後收起（戰鬥畫面接手）")

func test_fight_failure_keeps_prompt_with_reason() -> void:
	var sent: Array = []
	var v := _prompt(sent, false, "villain_none")
	await tree.process_frame
	v.open_prompt(prompt())
	v.fight()
	await _frames()
	assert_true(v.visible)
	assert_true(v.status_label.visible and v.status_label.text != "")
	assert_false(v.fight_button.disabled, "解鎖")

func test_call_once() -> void:
	var sent: Array = []
	var v := _prompt(sent)
	await tree.process_frame
	v.open_prompt(prompt())
	v.call_help()
	assert_eq(sent, [["villain_reply", { "wid": "w_nanhai", "choice": "CALL" }]])
	await _frames()
	assert_true(v.visible, "求救後倒數照走")
	assert_eq(v.call_button.text, "已求救")
	assert_true(v.call_button.disabled)
	v.call_help()
	assert_eq(sent.size(), 1, "只能求救一次")

func test_clear_and_room_change() -> void:
	var v := _prompt([])
	await tree.process_frame
	v.open_prompt(prompt("w_nanhai"), "xw_road")
	v.on_clear({ "wid": "w_other", "why": "GONE" })
	assert_true(v.visible, "別的惡人的 clear 不收")
	v.on_clear({ "wid": "w_nanhai", "why": "ESCAPED" })
	assert_false(v.visible)
	v.open_prompt(prompt("w_nanhai"), "xw_road")
	v.on_room("xw_road")
	assert_true(v.visible, "同一個房間")
	v.on_room("xw_creek")
	assert_false(v.visible, "離開房間就收起")

func test_main_screen_villain_prompt_wiring() -> void:
	var main: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	var sent: Array = []
	main.gate.set_sender(func(k, a):
		sent.append([k, a])
		return -1)
	main.apply_sheet(Scenes.fake_sheet())
	main.apply_view(Scenes.fake_view())
	main.handle_event({ "ch": "SYSTEM", "key": "villain_prompt", "ui": true, "p": prompt() })
	var vp: VillainPrompt = main.villain_prompt
	assert_true(vp.visible, "警告出現")
	assert_false(main.npc_dialog.visible)
	var overlay: Rect2 = main.OVERLAY_RECT
	assert_true(vp.position.x >= overlay.end.x or vp.position.y >= overlay.end.y, "不蓋聊天浮層：%s" % str(vp.position))
	main.handle_event({ "ch": "SYSTEM", "key": "villain_clear", "ui": true, "p": { "wid": "w_nanhai", "why": "ESCAPED" } })
	assert_false(vp.visible)
	# 非模態：警告開著時照樣能開視窗
	main.handle_event({ "ch": "SYSTEM", "key": "villain_prompt", "ui": true, "p": prompt() })
	main.open_panel("attributes")
	assert_true(vp.visible and main.panel_frame.visible, "不擋其他操作")
	main.open_battle(Scenes._battle_state())
	await tree.process_frame
	assert_false(vp.visible, "開戰時收起")

# ---------------------------------------------------------------- 場景卷軸

func _scene(sent: Array) -> ScenePanel:
	var sp := ScenePanel.new()
	sp.gate = _gate(sent)
	_add(sp)
	return sp

func test_scene_story_actions_send_story_act() -> void:
	var sent: Array = []
	var sp := _scene(sent)
	await tree.process_frame
	var v: Dictionary = Scenes.fake_view()
	v["story_actions"] = [ { "act": "q_lanfeng:a_wugong", "label": "捕捉蜈蚣" }, { "act": "q_liu_jinpen_2:a_rest", "label": "休息" } ]
	sp.apply_view(v)
	assert_eq(sp.story_buttons.size(), 2)
	var b: Button = sp.story_buttons["q_lanfeng:a_wugong"]
	assert_eq(b.text, "捕捉蜈蚣")
	assert_eq(b.get_theme_color("font_color"), ScenePanel.STORY_ACT_COLOR, "紅字")
	assert_eq(sp.life_box.get_child(0), b, "任務動作排在最前面")
	b.pressed.emit()
	assert_eq(sent, [["story_act", { "act": "q_lanfeng:a_wugong" }]])
	# 主機不再列 → 按鈕消失
	v["story_actions"] = []
	sp.apply_view(v)
	assert_eq(sp.story_buttons.size(), 0)

func test_scene_marks_villains_and_escort() -> void:
	var sp := _scene([])
	await tree.process_frame
	var v: Dictionary = Scenes.fake_view()
	v["npcs"] = [ { "id": "n_nanhai", "name": "南海鱷神", "services": [] }, { "id": "n_x", "name": "路人", "services": [] },
		{ "id": "n_xx_xuzhu", "name": "虛竹", "services": [], "escort": true } ]
	v["wanderers"] = [ { "wid": "w_nanhai", "npc": "n_nanhai", "name": "南海鱷神", "hostile": true },
		{ "wid": "w_etou_1", "npc": "n_amb_etou_1", "name": "惡人頭子", "hostile": true } ]
	v["escort"] = [ { "npc": "n_xx_xuzhu", "name": "虛竹" } ]
	sp.apply_view(v)
	assert_eq((sp.npc_buttons["n_nanhai"] as Button).text, "【惡】南海鱷神", "同一位 NPC 標在名字上")
	assert_eq((sp.npc_buttons["n_x"] as Button).text, "路人")
	var w := sp.npcs_box.find_child("Wanderer_w_etou_1", true, false) as Label
	assert_true(w != null and w.text == "【惡】惡人頭子", "不在 npcs 的遊蕩惡人另列")
	assert_eq((sp.npc_buttons["n_xx_xuzhu"] as Button).text, "虛竹（隨行）", "護送 NPC 在 npcs 裡：名字後加（隨行）")
	assert_true(sp.npcs_box.find_child("Escort_n_xx_xuzhu", true, false) == null, "不重複列")
	# 主機沒把護送 NPC 放進 npcs（舊形狀）：另列
	v["npcs"] = []
	sp.apply_view(v)
	var e := sp.npcs_box.find_child("Escort_n_xx_xuzhu", true, false) as Label
	assert_true(e != null and e.text == "虛竹（隨行）")
	assert_eq(ScenePanel.wanderers_by_npc(v).keys(), ["n_nanhai", "n_amb_etou_1"])
