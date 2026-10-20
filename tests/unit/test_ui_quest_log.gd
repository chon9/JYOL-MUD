extends "res://tests/test_case.gd"
## 故事包 WP-UI（STORY_PLAN §6.2、§6.7）：任務窗升級——依 chapter 分組與收合、目前階段（標題、log、目標進度）、
## 已走過的階段（看過的紀錄＋本機資料從 start 順著 next 補）、護送、提示地點（地圖標記）、已完成分頁（結局、次數、冷卻）、
## 舊格式角色表照樣顯示；屬性窗的江湖歷練。全部用假資料。

const Scenes := preload("res://tests/unit/test_ui_scenes.gd")

var _nodes: Array = []
var _saved_quests: Variant = null

func before_each() -> void:
	UiSettings.reset_for_tests(true)

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	var gd := tree.root.get_node_or_null("GameData")
	if gd != null and _saved_quests != null:
		gd.tables["quests"] = _saved_quests
	_saved_quests = null
	await tree.process_frame

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _gate(sent: Array) -> IntentGate:
	var g := IntentGate.new()
	_add(g)
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		var seq := sent.size()
		g.resolve.call_deferred(seq, true, "")
		return seq)
	return g

func _fake_quest(row: Dictionary) -> void:
	var gd := tree.root.get_node_or_null("GameData")
	if gd == null:
		return
	if _saved_quests == null:
		_saved_quests = (gd.tables.get("quests", {}) as Dictionary).duplicate()
	if not gd.tables.has("quests"):
		gd.tables["quests"] = {}
	gd.tables["quests"][str(row["id"])] = row

## STORY_PLAN §4.2 範例的形狀（雲兒）
static func yuner_def() -> Dictionary:
	return { "id": "q_ui_yuner", "name": "雲兒小姐的煩惱", "chapter": "西夏・開服事件", "giver": "n_xx_yuner",
		"text": "西夏城裡民房中的雲兒小姐，為了婚事而煩惱。", "start": "s_ask",
		"stages": [
			{ "id": "s_ask", "title": "雲兒的心事", "log": "到藥鋪看看李台安。", "objectives": [ { "id": "o_li", "type": "TALK", "npc": "n_xx_litaian" } ], "next": "s_abao" },
			{ "id": "s_abao", "title": "城外的阿寶", "log": "再去城北山坡看看阿寶。", "objectives": [ { "id": "o_abao", "type": "TALK", "npc": "n_xx_abao" } ], "next": "s_choose" },
			{ "id": "s_choose", "title": "替雲兒拿主意", "log": "回民房做個決定。", "objectives": [ { "id": "o_c", "type": "TALK", "npc": "n_xx_yuner" } ],
			  "next": [ { "if": [ { "type": "quest_var", "quest": "q_ui_yuner", "var": "pick", "value": "abao" } ], "goto": "s_thanks" }, { "goto": "END:li" } ] },
			{ "id": "s_thanks", "title": "阿寶的謝禮", "log": "回城北找阿寶。", "objectives": [ { "id": "o_t", "type": "TALK", "npc": "n_xx_abao" } ], "next": "END:abao" } ] }

static func row(stage: String, title: String, log: String, objs: Array = [], extra: Dictionary = {}) -> Dictionary:
	var r := { "id": "q_ui_yuner", "name": "雲兒小姐的煩惱", "chapter": "西夏・開服事件", "stage": stage,
		"stage_title": title, "log": log, "objectives": objs, "hint_room": "", "escort": "" }
	r.merge(extra, true)
	return r

func _panel(sent: Array = []) -> QuestPanel:
	var p := QuestPanel.new()
	p.gate = _gate(sent)
	_add(p)
	return p

func _texts(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)

func _has_text(n: Node, part: String) -> bool:
	return _texts(n).any(func(t): return str(t).contains(part))

func test_active_detail_shows_stage_log_and_objectives() -> void:
	_fake_quest(yuner_def())
	var p := _panel()
	await tree.process_frame
	p.apply_sheet({ "quests": [ row("s_ask", "雲兒的心事", "到藥鋪看看李台安。",
		[ { "text": "到藥鋪找李台安", "have": 0, "need": 1, "done": false }, { "text": "擊敗山賊", "have": 2, "need": 3, "done": false } ]) ] })
	assert_eq(p.selected, "q_ui_yuner", "自動選第一條")
	assert_true(_has_text(p.detail_box, "雲兒小姐的煩惱"))
	assert_true(_has_text(p.detail_box, "目前：雲兒的心事"))
	assert_true(_has_text(p.detail_box, "到藥鋪看看李台安。"), "log")
	assert_true(_has_text(p.detail_box, "西夏城裡民房中的雲兒小姐"), "任務說明（本機資料的 text）")
	assert_true(_has_text(p.detail_box, "・ 擊敗山賊（2/3）"), str(_texts(p.detail_box)))
	assert_eq(QuestPanel.objective_text({ "text": "找阿寶", "have": 1, "need": 1, "done": true }), "　◎ 找阿寶（1/1）", "完成打勾")

func test_chapters_group_and_collapse() -> void:
	var p := _panel()
	await tree.process_frame
	p.apply_sheet({ "quests": [
		{ "id": "q_a", "name": "甲", "chapter": "峨嵋派", "stage": "s", "objectives": [] },
		{ "id": "q_b", "name": "乙", "chapter": "西夏・開服事件", "stage": "s", "objectives": [] },
		{ "id": "q_c", "name": "丙", "chapter": "峨嵋派", "stage": "s", "objectives": [] },
		{ "id": "q_rabbit_ui", "name": "大兔皮", "giver_name": "武介山", "steps": [] } ] })
	var heads := p.list_box.get_children().filter(func(c): return str(c.name).begins_with("Chapter_")).map(func(c): return (c as Button).text)
	assert_eq(heads, ["▼ 峨嵋派（2）", "▼ 西夏・開服事件（1）", "▼ %s（1）" % StoryUi.DEFAULT_CHAPTER], "依第一次出現的順序分章，舊任務歸「江湖雜事」")
	assert_true(p.quest_buttons.has("q_a") and p.quest_buttons.has("q_c"))
	p.toggle_chapter("峨嵋派")
	assert_false(p.quest_buttons.has("q_a"), "收合後不列")
	assert_true(p.list_box.get_children().any(func(c): return c is Button and (c as Button).text == "▶ 峨嵋派（2）"))
	p.apply_sheet(p.sheet)
	assert_false(p.quest_buttons.has("q_a"), "角色表更新後仍收合")
	p.toggle_chapter("峨嵋派")
	assert_true(p.quest_buttons.has("q_a"))
	p.select_quest("q_b")
	assert_eq(p.selected, "q_b")
	assert_true(_has_text(p.detail_box, "乙"))

func test_past_stages_from_data_and_history() -> void:
	_fake_quest(yuner_def())
	var p := _panel()
	await tree.process_frame
	# 剛重新上線、直接在第 3 階段：本機資料從 start 補前兩段
	p.apply_sheet({ "quests": [ row("s_choose", "替雲兒拿主意", "回民房做個決定。") ] })
	var past := p.past_stages(p.active_rows()[0])
	assert_eq(past.map(func(h): return h["stage"]), ["s_ask", "s_abao"])
	assert_true(p.detail_box.find_child("Past_s_ask", true, false) != null, "灰字列出已走過的階段")
	# 條件分支：看過 s_choose 之後到了 s_thanks
	p.apply_sheet({ "quests": [ row("s_thanks", "阿寶的謝禮", "回城北找阿寶。") ] })
	past = p.past_stages(p.active_rows()[0])
	assert_eq(past.map(func(h): return h["stage"]), ["s_ask", "s_abao", "s_choose"], "分支依看過的紀錄選路")
	# 完成後重接：紀錄清掉
	p.apply_sheet({ "quests": [] })
	assert_false(p.history.has("q_ui_yuner"))

func test_past_stages_without_data_use_seen_history() -> void:
	var p := _panel()
	await tree.process_frame
	var base := { "id": "q_nodata", "name": "無資料", "chapter": "測試" }
	var r1 := base.duplicate()
	r1.merge({ "stage": "a", "stage_title": "第一段", "log": "先做這個" })
	p.apply_sheet({ "quests": [ r1 ] })
	var r2 := base.duplicate()
	r2.merge({ "stage": "b", "stage_title": "第二段", "log": "再做那個" })
	p.apply_sheet({ "quests": [ r2 ] })
	var past := p.past_stages(r2)
	assert_eq(past.size(), 1)
	assert_eq(past[0]["title"], "第一段")
	assert_true(_has_text(p.detail_box, "✓ 第一段：先做這個"))

func test_escort_and_hint_room() -> void:
	var p := _panel()
	await tree.process_frame
	var hinted: Array = []
	p.hint_requested.connect(func(r): hinted.append(r))
	p.apply_sheet({ "quests": [ row("s_x", "護送虛竹", "帶虛竹到皇宮門口。", [], { "escort": "n_ui_nobody", "hint_room": "xx_square" }) ] })
	var esc := p.detail_box.find_child("Escort", true, false) as Label
	assert_true(esc != null and esc.text.contains("n_ui_nobody"), "查不到名字時顯示 id")
	assert_eq(QuestPanel.escort_name({ "npc": "n_x", "name": "虛竹" }), "虛竹")
	assert_eq(QuestPanel.escort_name([{ "name": "虛竹" }, { "name": "阿紫" }]), "虛竹、阿紫")
	assert_eq(QuestPanel.escort_name(""), "")
	var hb := p.detail_box.find_child("HintRoom", true, false) as Button
	assert_true(hb != null, "提示地點按鈕")
	hb.pressed.emit()
	assert_eq(hinted, ["xx_square"])

func test_abandon_needs_confirm() -> void:
	var sent: Array = []
	var p := _panel(sent)
	await tree.process_frame
	p.apply_sheet({ "quests": [ row("s_ask", "雲兒的心事", "") ] })
	(p.detail_box.find_child("Abandon", true, false) as Button).pressed.emit()
	assert_true(p.confirm_row.visible)
	assert_eq(sent.size(), 0)
	p._on_confirm()
	assert_eq(sent, [["quest_abandon", { "quest": "q_ui_yuner" }]])

func test_done_tab_outcome_count_and_cooldown() -> void:
	var p := _panel()
	await tree.process_frame
	p.apply_sheet({ "quests": [], "quest_cd": { "q_xingxia": 1800.0 },
		"quests_done": [ { "id": "q_yuner", "name": "雲兒小姐的煩惱", "chapter": "西夏・開服事件", "outcome_label": "雲兒嫁給了阿寶", "n": 1 },
			{ "id": "q_xingxia", "name": "行俠仗義", "chapter": "雁門關", "outcome_label": "", "n": 3 } ] })
	assert_true(_has_text(p.list_box, "目前沒有任務"))
	p.set_tab(QuestPanel.TAB_DONE)
	assert_eq(p.selected, "q_yuner")
	assert_true(_has_text(p.detail_box, "結局：雲兒嫁給了阿寶"))
	assert_true(_has_text(p.detail_box, "完成 1 次"))
	assert_true((p.quest_buttons["q_xingxia"] as Button).text.contains("×3"), "左欄標次數")
	p.select_quest("q_xingxia")
	var cl := p.detail_box.find_child("Cooldown", true, false) as Label
	assert_true(cl != null and cl.text.contains("約 3 個時辰"), cl.text if cl != null else "no cooldown label")
	# 舊格式 quests_done（qid 陣列）
	p.apply_sheet({ "quests": [], "quests_done": ["q_rice_ui"] })
	assert_true(p.quest_buttons.has("q_rice_ui"))

func test_legacy_sheet_rows_still_show() -> void:
	var p := _panel()
	await tree.process_frame
	p.apply_sheet(Scenes.fake_sheet())
	assert_true(_has_text(p.detail_box, "狩獵事件：大兔皮"))
	assert_true(_has_text(p.detail_box, "委託：武介山"))
	assert_true(_has_text(p.detail_box, "交給武介山 1 張大兔皮（0/1）"), str(_texts(p.detail_box)))
	p.set_tab(QuestPanel.TAB_DONE)
	assert_true(p.quest_buttons.has("q_rice"), "舊格式已完成")

func test_span_text() -> void:
	assert_eq(StoryUi.span_text(0.0, 7200.0), "")
	assert_eq(StoryUi.span_text(1.0, 7200.0), "約 1 個時辰")
	assert_eq(StoryUi.span_text(600.0, 7200.0), "約 1 個時辰")
	assert_eq(StoryUi.span_text(601.0, 7200.0), "約 2 個時辰")
	assert_eq(StoryUi.span_text(7200.0, 7200.0), "約 1 天")
	assert_eq(StoryUi.span_text(7200.0 + 1300.0, 7200.0), "約 1 天 3 個時辰")
	assert_eq(StoryUi.world_time_label(0.0, 7200.0), "第 1 天 辰時", "新世界從辰時開始")
	assert_eq(StoryUi.world_time_label(7200.0 / 12.0 * 8.0, 7200.0), "第 2 天 子時")

func test_main_hint_opens_map_with_mark() -> void:
	var main: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	main.apply_sheet(Scenes.fake_sheet())
	main.apply_view(Scenes.fake_view())
	var qp: QuestPanel = main.panels["quests"]
	qp.hint_requested.emit("xw_creek")
	assert_eq(main.current_panel, "map", "打開地圖")
	assert_eq(main.map_panel.quest_mark, "xw_creek")
	assert_eq(main.map_panel.region_view.quest_mark, "xw_creek", "區域圖標記")
	assert_eq(main.mini_map.view.quest_mark, "xw_creek", "小地圖也標")
	assert_true(main.map_panel.status_label.text.begins_with("任務地點："), main.map_panel.status_label.text)
	main.map_panel.clear_quest_mark()
	assert_eq(main.map_panel.region_view.quest_mark, "")

func test_attributes_show_lilian() -> void:
	var a := AttributesPanel.new()
	_add(a)
	await tree.process_frame
	var s: Dictionary = Scenes.fake_sheet()
	s["lilian"] = 45
	a.apply_sheet(s)
	assert_eq((a.value_labels["江湖歷練"] as Label).text, "45")
	var labels := a.progress_grid.get_children().map(func(c): return (c as Label).text)
	assert_eq(labels.find("江湖歷練") + 2, labels.find("名聲"), "江湖歷練緊鄰名聲")
	s.erase("lilian")
	s["lili"] = 7
	a.apply_sheet(s)
	assert_eq((a.value_labels["江湖歷練"] as Label).text, "7", "舊主機的 lili")
