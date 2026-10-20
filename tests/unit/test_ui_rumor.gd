extends "res://tests/test_case.gd"
## 故事包 WP-UI（STORY_PLAN §6.3、§6.6）：系統【江湖傳聞】——jianghu_rumor（CH_JIANGHU）進公告框與聊天浮層、
## 頻道開關「江湖傳聞」、系統窗「江湖傳聞」頁（rumor_list）、伺服器設定面板的江湖事件八項。全部用假資料。

const Scenes := preload("res://tests/unit/test_ui_scenes.gd")

var _nodes: Array = []
var _saved_tpl: Variant = null

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	_fake_templates()

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	var gd := tree.root.get_node_or_null("GameData")
	if gd != null and _saved_tpl != null:
		gd.tables["text_templates"] = _saved_tpl
	_saved_tpl = null
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

func _fake_templates() -> void:
	var gd := tree.root.get_node_or_null("GameData")
	if gd == null:
		return
	if _saved_tpl == null:
		_saved_tpl = (gd.tables.get("text_templates", {}) as Dictionary).duplicate()
	if not gd.tables.has("text_templates"):
		gd.tables["text_templates"] = {}
	gd.tables["text_templates"]["rmr_ui_first"] = { "id": "rmr_ui_first", "other": "聽說{name}替雲兒拿了主意，雲兒嫁給了{who}。" }
	gd.tables["text_templates"]["rmr_ui_self"] = { "id": "rmr_ui_self", "self": "【系統】{name}擊退了南海鱷神。" }

static func rumor(key := "rmr_ui_first", world_s := 100.0, kind := "QUEST") -> Dictionary:
	return { "text_key": key, "params": { "name": "小蝦米", "who": "阿寶" }, "kind": kind, "world_s": world_s }

func test_rumor_text_from_templates() -> void:
	var t := UiClient.templates()
	assert_eq(StoryUi.rumor_text(rumor(), t), "聽說小蝦米替雲兒拿了主意，雲兒嫁給了阿寶。")
	assert_eq(StoryUi.rumor_text(rumor("rmr_ui_self"), t), "小蝦米擊退了南海鱷神。", "只有 self 變體也用；頻道標籤拿掉")
	assert_eq(StoryUi.rumor_line(rumor(), t), "【江湖傳聞】聽說小蝦米替雲兒拿了主意，雲兒嫁給了阿寶。")
	assert_eq(StoryUi.rumor_text({ "text_key": "rmr_missing", "params": { "text": "直接的文字" } }, t), "直接的文字")
	assert_eq(StoryUi.rumor_text({ "text_key": "rmr_missing", "params": {} }, t), "", "沒有模板也沒有文字：不顯示")
	assert_eq(StoryUi.rumor_kind_label("VILLAIN"), "惡人")
	assert_eq(StoryUi.rumor_kind_label("???"), "傳聞")

func test_message_log_shows_rumor_and_channel_toggle() -> void:
	var ml := MessageLog.new()
	_add(ml)
	await tree.process_frame
	var box := RichTextLabel.new()
	_add(box)
	ml.build_announce(box)
	ml.announce_lines.clear()
	ml.entries.clear()
	ml.add_event({ "ch": "JIANGHU", "key": "jianghu_rumor", "p": rumor() })
	assert_eq(ml.announce_lines.size(), 1, "進右下系統訊息框")
	assert_eq(str(ml.announce_lines[0]["t"]), "【江湖傳聞】聽說小蝦米替雲兒拿了主意，雲兒嫁給了阿寶。")
	assert_eq(ml.entries.size(), 1, "也進左上浮層")
	assert_eq(str(ml.entries[0]["ch"]), "JIANGHU")
	assert_false(str(ml.entries[0]["bb"]).contains("jianghu_rumor"), "不是除錯用的 key + JSON")
	assert_true(ml.announce.get_parsed_text().contains("江湖傳聞"))
	assert_eq(ml.visible_lines(), 1)
	# 關掉「江湖傳聞」：兩處都不顯示；「江湖謠言」不受影響
	ml.set_channel_enabled("江湖傳聞", false)
	assert_eq(ml.visible_lines(), 0)
	assert_false(ml.announce.get_parsed_text().contains("江湖傳聞"))
	ml.add_announcement("某某拜入少林")   # 一般公告（江湖謠言控制）
	assert_true(ml.announce.get_parsed_text().contains("某某拜入少林"))
	ml.set_channel_enabled("江湖傳聞", true)
	assert_true(ml.announce.get_parsed_text().contains("江湖傳聞"))
	assert_eq(MessageLog.CHANNELS.size(), 13, "原作 13 個頻道不變")
	assert_has(MessageLog.EXTRA_CHANNELS, "江湖傳聞")
	assert_eq(MessageLog.CHANNEL_OF["JIANGHU"], "江湖傳聞")

func test_channel_page_has_rumor_toggle() -> void:
	var sp := SystemPanel.new()
	var ml := MessageLog.new()
	_add(ml)
	_add(sp)
	sp.message_log = ml
	await tree.process_frame
	sp.show_page("頻道開關")
	var cb := sp.find_child("Channel_江湖傳聞", true, false) as CheckButton
	assert_true(cb != null, "頻道開關多了江湖傳聞")
	assert_true(cb.button_pressed and not cb.disabled)
	cb.button_pressed = false
	assert_false(ml.channel_enabled("江湖傳聞"))

func test_system_rumor_page_requests_and_lists() -> void:
	var sent: Array = []
	var sp := SystemPanel.new()
	sp.gate = _gate(sent)
	_add(sp)
	await tree.process_frame
	assert_has(SystemPanel.ITEMS, "江湖傳聞")
	sp.show_page("江湖傳聞")
	assert_eq(sent, [["rumor_list", {}]], "打開時要最近的傳聞")
	var box := sp.find_child("RumorList", true, false) as VBoxContainer
	assert_true(box != null)
	assert_true(_label_texts(box).any(func(t): return str(t).contains("風平浪靜")), "還沒拿到時")
	sp.apply_rumor_list([ rumor("rmr_ui_first", 100.0, "QUEST"), rumor("rmr_ui_self", 900.0, "VILLAIN"), { "text_key": "rmr_missing" } ])
	var texts := _label_texts(box)
	assert_true(texts.has("［惡人］") and texts.has("［事件］"), str(texts))
	var i_new := texts.find("小蝦米擊退了南海鱷神。")
	var i_old := texts.find("聽說小蝦米替雲兒拿了主意，雲兒嫁給了阿寶。")
	assert_true(i_new >= 0 and i_old > i_new, "新的在前：%s" % str(texts))
	assert_true(texts.has(StoryUi.world_time_label(900.0)), "附遊戲時間")
	(sp.find_child("RumorRefresh", true, false) as Button).pressed.emit()
	assert_eq(sent.size(), 2, "重新整理")

func test_main_routes_rumor_list_to_system_panel() -> void:
	var main: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	main.gate.set_sender(func(_k, _a): return -1)
	main.apply_sheet(Scenes.fake_sheet())
	main.open_panel("system")
	var sp: SystemPanel = main.panels["system"]
	sp.show_page("江湖傳聞")
	main.handle_event({ "ch": "SYSTEM", "key": "rumor_list", "ui": true, "p": { "items": [ rumor() ] } })
	assert_eq(sp.rumor_items.size(), 1)
	assert_true(_label_texts(sp.find_child("RumorList", true, false)).has("聽說小蝦米替雲兒拿了主意，雲兒嫁給了阿寶。"))

func _label_texts(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)

# ---------------------------------------------------------------- 伺服器設定：江湖事件八項

func test_server_options_story_rows_greyed_when_host_lacks_them() -> void:
	var d := ServerOptionsDialog.new()
	d.gate = _gate([])
	_add(d)
	await tree.process_frame
	var o: Dictionary = preload("res://tests/unit/test_ui_m2.gd").server_opts()
	d.apply_options(o)
	assert_eq(d.selectors.size(), 4, "主機的四項照舊")
	assert_eq(d.story_rows.size(), 8, "江湖事件八項都在")
	assert_eq(StoryUi.story_option_keys(), ["rumors_enabled", "rumor_min_gap_s", "rumor_chat_inner_min", "wanderers_enabled",
		"villain_warn_s", "chase_npcs", "ambient_lines", "npc_reactions"], "§5.5 的八個 key")
	var ob: OptionButton = d.story_rows["npc_reactions"]
	assert_true(ob.disabled, "主機還沒開放：灰掉")
	assert_eq(str(ob.get_item_metadata(ob.selected)), "FULL", "預設值")
	assert_eq(str((d.story_rows["rumor_min_gap_s"] as OptionButton).get_item_metadata((d.story_rows["rumor_min_gap_s"] as OptionButton).selected)), "120")
	assert_eq(str((d.story_rows["villain_warn_s"] as OptionButton).get_item_metadata((d.story_rows["villain_warn_s"] as OptionButton).selected)), "3")
	assert_true(d.story_note.visible)
	# 主機給了目前值（options）
	o["options"] = { "wanderers_enabled": false, "rumor_min_gap_s": 300.0 }
	d.apply_options(o)
	var w: OptionButton = d.story_rows["wanderers_enabled"]
	assert_eq(str(w.get_item_metadata(w.selected)), "false")
	var g: OptionButton = d.story_rows["rumor_min_gap_s"]
	assert_eq(str(g.get_item_metadata(g.selected)), "300", "JSON 的 300.0 → \"300\"")

func test_server_options_story_rows_editable_when_hosted() -> void:
	var sent: Array = []
	var d := ServerOptionsDialog.new()
	d.gate = _gate(sent)
	_add(d)
	await tree.process_frame
	var o: Dictionary = preload("res://tests/unit/test_ui_m2.gd").server_opts()
	(o["editable"] as Array).append({ "key": "npc_reactions", "label": "NPC 反應", "value": "FLAVOR",
		"choices": [ { "value": "OFF", "label": "關" }, { "value": "FLAVOR", "label": "招呼語" }, { "value": "FULL", "label": "全部" } ] })
	d.apply_options(o)
	assert_eq(d.selectors.size(), 5)
	var ob: OptionButton = d.story_rows["npc_reactions"]
	assert_false(ob.disabled, "主機開放了：可以改")
	assert_true(ob.get_parent() == d.story_grid, "放在江湖事件區")
	d.select_value("npc_reactions", "OFF")
	assert_eq(sent, [["server_opts_set", { "key": "npc_reactions", "value": "OFF" }]])
	assert_true((d.story_rows["rumors_enabled"] as OptionButton).disabled, "其餘仍灰")
