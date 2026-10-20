extends "res://tests/test_case.gd"
## WP-UI（M3B_PLAN §11.1 test_ui_m3b_sect）：袋位顯示與「袋位」頁、乞討選項與指令、京城監獄提示、捉拿公敵、
## 伺服器設定新列（開放 1.0B）、創角出生城（京城（神鵰大俠））、UiKeys 與 Protocol 的 M3b 常數一致。全部假資料。

var _nodes: Array = []
var _old_sheet: Dictionary = {}
var _old_wi: Dictionary = {}
var _patched: Dictionary = {}

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	_old_sheet = ClientState.sheet
	_old_wi = ClientState.world_info

func after_each() -> void:
	ClientState.sheet = _old_sheet
	ClientState.world_info = _old_wi
	for t in _patched:
		var tbl: Dictionary = GameData.tables.get(t, {})
		for id in _patched[t]:
			if _patched[t][id] == null:
				tbl.erase(id)
			else:
				tbl[id] = _patched[t][id]
	_patched.clear()
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

func _put(table: String, id: String, row: Dictionary) -> void:
	if not GameData.tables.has(table):
		GameData.tables[table] = {}
	var tbl: Dictionary = GameData.tables[table]
	if not _patched.has(table):
		_patched[table] = {}
	if not _patched[table].has(id):
		_patched[table][id] = tbl.get(id, null)
	tbl[id] = row

func _gate(sent: Array, ok := true, reason := "") -> IntentGate:
	var g := IntentGate.new()
	_add(g)
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		var seq := sent.size()
		g.resolve.call_deferred(seq, ok, reason)
		return seq)
	return g

func _gaibang() -> void:
	_put("sects", "t_gb", { "id": "t_gb", "name": "丐幫", "gender": ["M", "F"], "sect_skill": "t_qitao", "sect_skill_name": "乞討",
		"ranks": "t_gb", "no_escort": true,
		"practice": { "verb": "乞討", "target": "NPC", "cost": { "jing": 20, "shen": 20 }, "prof": [3, 6], "per_npc_cd_s": 600,
			"npc_kinds": ["SHOP", "FUNC", "QUEST", "STORY"] } })
	_put("sect_ranks", "t_gb_dai0", { "id": "t_gb_dai0", "sect": "t_gb", "rank": 0, "name": "無袋弟子", "requires": [], "promote": "JOIN", "cost": {} })
	_put("sect_ranks", "t_gb_dai1", { "id": "t_gb_dai1", "sect": "t_gb", "rank": 1, "name": "一袋弟子",
		"requires": [ { "type": "fame_min", "value": 250 }, { "type": "lilian_min", "value": 250 } ],
		"promote": "QUEST", "quest": "t_q_dai1", "assembly": true, "cost": {} })
	_put("sect_ranks", "t_gb_dai2", { "id": "t_gb_dai2", "sect": "t_gb", "rank": 2, "name": "二袋弟子",
		"requires": [ { "type": "fame_min", "value": 500 }, { "type": "sect_rank_min", "sect": "t_gb", "value": 1 } ],
		"promote": "QUEST", "quest": "t_q_dai2", "assembly": true, "cost": { "fame": 250, "lilian": 250 } })
	_put("quests", "t_q_dai1", { "id": "t_q_dai1", "name": "升一袋" })
	_put("npcs", "t_n_shop", { "id": "t_n_shop", "name": "掌櫃", "kind": "SHOP" })
	_put("npcs", "t_n_guard", { "id": "t_n_guard", "name": "守衛", "kind": "GUARD" })
	_put("npcs", "t_n_master", { "id": "t_n_master", "name": "陳長老", "kind": "SHOP", "no_beg": true })

static func gb_sheet(pending := false) -> Dictionary:
	return { "char_id": "ch_me", "name": "我", "sect": "t_gb", "sect_name": "丐幫", "fame": 300, "money": 10, "vitals": {},
		"sect_info": { "id": "t_gb", "name": "丐幫", "skill_id": "t_qitao", "skill_name": "乞討", "skill_level": 12, "master": "",
			"stop_teach": "", "ban_left_s": 0, "warnings": [],
			"rank": { "level": 1, "name": "一袋弟子", "pending": { "rank": 2, "name": "二袋弟子" } if pending else null,
				"next": { "name": "二袋弟子", "requires_text": ["名聲 500 以上"] } } },
		"enemy_of": [], "jail": null, "conditions": [] }

# ---------------------------------------------------------------- 袋位

func test_rank_text_in_attributes() -> void:
	_gaibang()
	assert_eq(SectUi.rank_text(gb_sheet()), "袋位：一袋弟子")
	assert_eq(SectUi.rank_text(gb_sheet(true)), "袋位：一袋弟子（升二袋弟子，待聚會）")
	assert_eq(SectUi.rank_text({ "sect_info": { "id": "x" } }), "", "沒有位階的門派不顯示")
	var ap := AttributesPanel.new()
	_add(ap)
	await _frame()
	ap.apply_sheet(gb_sheet(true))
	assert_true(ap.misc_label.text.contains("袋位：一袋弟子（升二袋弟子，待聚會）"), ap.misc_label.text)
	assert_true(ap.misc_label.text.contains("乞討 12 級"), ap.misc_label.text)
	# 新條件型別的文字
	assert_eq(SectUi.requirement_text({ "type": "sect_rank_min", "sect": "t_gb", "value": 2 }), "丐幫二袋弟子以上")
	assert_eq(SectUi.requirement_text({ "type": "sect_not", "sect": "t_gb" }), "不是丐幫弟子")
	assert_eq(SectUi.requirement_text({ "type": "fame_min", "value": 250 }), "名聲 250 以上")
	assert_eq(SectUi.requirement_text({ "type": "no_org" }), "不在任何組織裡")
	assert_eq(SectUi.requirement_text({ "type": "skill_min", "skill": "t_qitao", "value": 30 }), "乞討 30 級以上")

func test_rank_page_in_npc_menu() -> void:
	_gaibang()
	ClientState.sheet = gb_sheet(true)
	var rows := SectUi.rank_page({ "sect": "t_gb" }, gb_sheet(true))
	assert_eq(rows.map(func(r): return r["state"]), ["DONE", "DONE", "PENDING"])
	assert_eq(rows[1]["quest_name"], "升一袋")
	assert_true(rows[2]["conditions"].has("丐幫一袋弟子以上"), str(rows[2]["conditions"]))
	assert_eq(rows[2]["cost_text"], "升袋時扣 名聲 250、江湖歷練 250")
	var d := NpcDialog.new()
	d.gate = _gate([])
	_add(d)
	await _frame()
	d.open_menu({ "npc": "n_gb_chen", "npc_name": "陳長老", "services": ["RANK", "TEACH"], "rank": { "sect": "t_gb", "level": 1 } })
	assert_eq((d.service_buttons["RANK"] as Button).text, "袋位")
	(d.service_buttons["RANK"] as Button).pressed.emit()
	var l2 := d.detail_box.find_child("Rank_2", true, false) as Label
	assert_true(l2 != null and l2.text.contains("二袋弟子") and l2.text.contains("【待聚會】"), l2.text if l2 else "missing")
	var l1 := d.detail_box.find_child("Rank_1", true, false) as Label
	assert_true(l1.text.contains("任務：升一袋") and l1.text.contains("聚會"), l1.text)
	# 主機給 rows（含 requires_text）就照主機
	var given := SectUi.rank_page({ "level": 0, "rows": [ { "rank": 1, "name": "一袋", "requires_text": ["名聲 250"], "promote": "QUEST" } ] }, {})
	assert_eq(given[0]["conditions"], ["名聲 250"])
	assert_eq(given[0]["state"], "NEXT")

# ---------------------------------------------------------------- 乞討

func test_beg_option_in_npc_menu() -> void:
	_gaibang()
	ClientState.sheet = gb_sheet()
	var sent: Array = []
	var d := NpcDialog.new()
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	d.open_menu({ "npc": "t_n_shop", "npc_name": "掌櫃", "services": ["SHOP"], "beg": { "ok": true, "reason": "" } })
	assert_true(d.service_buttons.has(UiKeys.BEG_CHOICE))
	var b := d.service_buttons[UiKeys.BEG_CHOICE] as Button
	assert_eq(b.text, "乞討")
	assert_false(b.disabled)
	assert_eq(d.choice_order, ["SHOP", "BEG"], "編號接在服務後面（數字鍵 2）")
	b.pressed.emit()
	assert_eq(sent, [["beg", { "npc": "t_n_shop" }]])
	await _frame()
	await _frame()
	b = d.service_buttons[UiKeys.BEG_CHOICE] as Button
	assert_true(b.disabled, "討過一次：同一位 NPC 冷卻")
	assert_true(b.tooltip_text.contains("10 分"), b.tooltip_text)
	# 主機說冷卻 / 精神不足
	d.open_menu({ "npc": "t_n_shop", "npc_name": "掌櫃", "services": [], "beg": { "ok": false, "reason": "beg_cooldown", "left_s": 185 } })
	var why := d.services_box.find_child("BegWhy", true, false) as Label
	assert_true(why != null and why.text.contains("3 分 5 秒"), why.text if why else "missing")
	assert_eq(SectUi.beg_block_text({ "ok": false, "reason": "not_enough_shen" }), "神不足")
	assert_eq(SectUi.beg_block_text({ "ok": false, "reason": "not_enough_jing" }), "精不足")
	# 沒有 beg 欄位（不是丐幫）：沒有這個選項
	d.open_menu({ "npc": "t_n_shop", "npc_name": "掌櫃", "services": ["SHOP"] })
	assert_false(d.service_buttons.has(UiKeys.BEG_CHOICE))

func test_beg_command_targets_room_npc() -> void:
	_gaibang()
	var v := { "room": "r1", "npcs": [ { "id": "t_n_guard", "name": "守衛" }, { "id": "t_n_master", "name": "陳長老" },
		{ "id": "t_n_shop", "name": "掌櫃" } ], "features": [], "exits": [] }
	assert_eq(SectUi.beg_target(v, gb_sheet()), "t_n_shop", "守衛（kind 不在清單）、no_beg 的跳過")
	assert_eq(SectUi.beg_target(v, gb_sheet(), "t_n_master"), "t_n_shop", "最近交談的不能討就找別人")
	assert_eq(SectUi.beg_target(v, { "sect": "" }), "")
	assert_eq(UiCommands.unavailable_reason("beg", gb_sheet(), v), "")
	assert_eq(UiCommands.unavailable_reason("beg", { "sect": "" }, v), "本派沒有乞討這門功夫")
	assert_eq(UiCommands.unavailable_reason("beg", gb_sheet(), { "npcs": [] }), "這裡沒有可以乞討的人")
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	var sent: Array = []
	main.gate.set_sender(func(kind, args):
		sent.append([kind, args])
		return -1)
	main.apply_sheet(gb_sheet())
	main.view = v
	main.run_command(Hotbar.CMD_PREFIX + "beg")
	assert_eq(sent, [["beg", { "npc": "t_n_shop" }]])

# ---------------------------------------------------------------- 京城監獄

func test_capital_jail_banner() -> void:
	assert_eq(SectUi.jail_banner({ "scope": "CAPITAL", "room_name": "京城監獄", "left_s": 7200 }, 7200.0), "京城監獄：剩 2 小時 0 分（上線時間）")
	assert_eq(SectUi.jail_banner({ "scope": "SECT", "room_name": "思過處" }, 40.0), "思過處：剩 40 秒（上線時間）")
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	var s := gb_sheet()
	s["jail"] = { "scope": "CAPITAL", "sect_name": "少林", "room_name": "大牢", "left_s": 3600 }
	s["_rx_ms"] = Time.get_ticks_msec()
	main.apply_sheet(s)
	assert_true(main.jail_text().begins_with("京城監獄：剩"), main.jail_text())

# ---------------------------------------------------------------- 捉拿公敵

func test_seize_menu_dialog_and_command() -> void:
	var v := { "room": "jcw_crossroad", "room_name": "古道交會處", "pk_allowed": true, "exits": [], "npcs": [], "features": [],
		"players": [ { "char_id": "ch_t", "name": "叛徒", "seizable": true, "align": "EVIL" },
			{ "char_id": "ch_u", "name": "路人", "seizable": false } ] }
	var acts: Array = UiSocial.player_menu(v["players"][0], {}).map(func(x): return x[0])
	assert_true(acts.has(UiSocial.ACT_SEIZE), str(acts))
	acts = UiSocial.player_menu(v["players"][1], {}).map(func(x): return x[0])
	assert_false(acts.has(UiSocial.ACT_SEIZE))
	assert_eq(SeizeDialog.targets(v).map(func(p): return p["name"]), ["叛徒"])
	assert_eq(UiCommands.unavailable_reason("seize", {}, v), "")
	assert_eq(UiCommands.unavailable_reason("seize", {}, { "players": [] }), "這裡沒有本派的公敵")
	var sent: Array = []
	var d := SeizeDialog.new()
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	d.open_list(v)
	assert_true(d.find_child("Seize_叛徒", true, false) != null)
	assert_true(d.find_child("Seize_路人", true, false) == null)
	assert_true(d.press_number(1), "數字鍵 1")
	var t := d.find_child("SeizeText", true, false) as Label
	assert_eq(t.text, "確定要捉拿本派公敵叛徒？")
	assert_eq(sent, [], "確認前不送")
	(d.find_child("SeizeOk", true, false) as Button).pressed.emit()
	assert_eq(sent, [["seize_enemy", { "name": "叛徒" }]])
	# 主畫面：玩家選單「捉拿」開確認段；指令「捉拿公敵」開清單
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.apply_view(v)
	main._on_player_action(UiSocial.ACT_SEIZE, v["players"][0])
	assert_true(main.seize_dialog.visible)
	assert_true(main.seize_dialog.find_child("SeizeText", true, false) != null)
	main._close_dialogs()
	main.run_command(Hotbar.CMD_PREFIX + "seize")
	assert_true(main.seize_dialog.visible)

# ---------------------------------------------------------------- 伺服器設定

static func opts(value := "", choices := [ { "value": "on", "label": "開放" } ]) -> Dictionary:
	return { "editable": [
			{ "key": "enable_era_1_0b", "label": "開放神鵰大俠（1.0B）內容", "value": value, "choices": choices },
			{ "key": "jail_location", "label": "監獄位置", "value": "AUTO",
				"choices": [ { "value": "AUTO", "label": "自動" }, { "value": "SECT", "label": "各派思過處" }, { "value": "CAPITAL", "label": "京城監獄" } ] },
			{ "key": "gb_assembly", "label": "丐幫聚會", "value": "DAILY",
				"choices": [ { "value": "DAILY", "label": "每日" }, { "value": "MONTHLY", "label": "每月初" } ] },
			{ "key": "seize_enabled", "label": "捉拿公敵", "value": "true",
				"choices": [ { "value": "true", "label": "開" }, { "value": "false", "label": "關" } ] } ],
		"info": { "world_name": "測試", "players": [] } }

func test_server_options_era_row_states() -> void:
	var sent: Array = []
	var d := ServerOptionsDialog.new()
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	# 未開放：第一項「未開放」，選「開放」→ server_opts_set，成功後顯示「下次開服生效」並灰掉
	ClientState.world_info = { "enabled_eras": ["1.0A"], "pending_eras": [] }
	d.apply_options(opts())
	var ob := d.selectors["enable_era_1_0b"] as OptionButton
	assert_eq(ob.get_item_text(ob.selected), "未開放")
	assert_false(ob.disabled)
	for k in ["jail_location", "gb_assembly", "seize_enabled"]:
		assert_true(d.selectors.has(k), "新列 " + k)
	var idx := -1
	for i in ob.item_count:
		if str(ob.get_item_metadata(i)) == "on":
			idx = i
	ob.select(idx)
	ob.item_selected.emit(idx)
	assert_eq(sent, [["server_opts_set", { "key": "enable_era_1_0b", "value": "on" }]])
	await _frame()
	await _frame()
	assert_true(ob.disabled)
	assert_eq(ob.get_item_text(0), "下次開服生效")
	# pending_eras 非空：一打開就是「下次開服生效」
	ClientState.world_info = { "enabled_eras": ["1.0A"], "pending_eras": ["1.0A", "1.0B"] }
	d.apply_options(opts())
	ob = d.selectors["enable_era_1_0b"] as OptionButton
	assert_true(ob.disabled)
	assert_eq(ob.get_item_text(ob.selected), "下次開服生效")
	# 已開 1.0B：「已開放」灰掉
	ClientState.world_info = { "enabled_eras": ["1.0A", "1.0B"] }
	d.apply_options(opts("", []))
	ob = d.selectors["enable_era_1_0b"] as OptionButton
	assert_true(ob.disabled)
	assert_eq(ob.get_item_text(ob.selected), "已開放")

# ---------------------------------------------------------------- 創角出生城

func test_birth_cities_include_capital_with_era_name() -> void:
	_put("regions", "t_jc", { "id": "t_jc", "name": "測京", "type": "CITY", "birth_allowed": true, "era": "1.0B", "world_pos": [850, 196] })
	ClientState.world_info = { "enabled_eras": ["1.0A", "1.0B"] }
	var cs := UiClient.birth_cities()
	var row: Dictionary = {}
	for c in cs:
		if c["id"] == "t_jc":
			row = c
	assert_false(row.is_empty(), "1.0B 世界：京城可出生")
	assert_eq(row["name"], "測京（神鵰大俠）")
	assert_eq(row["seal"], "測京", "印章只寫城名")
	ClientState.world_info = { "enabled_eras": ["1.0A"] }
	assert_false(UiClient.birth_cities().any(func(c): return c["id"] == "t_jc"), "1.0A 世界：沒有京城")

# ---------------------------------------------------------------- 常數

func test_m3b_constants_match_protocol() -> void:
	for s in ["BANK", "ESCORT", "ORG", "RANK"]:
		assert_has(UiKeys.SERVICES, s)
	assert_eq(UiKeys.service_label("BANK"), "錢莊")
	assert_eq(UiKeys.service_label("ESCORT"), "鏢局")
	assert_eq(UiKeys.service_label("ORG"), "組織")
	assert_eq(UiKeys.service_label("RANK"), "袋位")
	for k in UiKeys.M3B_UI_KEYS:
		assert_has(UiKeys.UI_ONLY_KEYS, k)
	# Day-0 的 Protocol 落地後逐一比對（還沒落地時略過，字面值照 M3B_PLAN §6）
	var cm: Dictionary = (load("res://core/protocol.gd") as Script).get_script_constant_map()
	var schema: Variant = cm.get("INTENT_SCHEMA", {})
	if schema is Dictionary and (schema as Dictionary).has("bank_open"):
		for kind in UiKeys.M3B_INTENTS:
			assert_true((schema as Dictionary).has(kind), "Protocol.INTENT_SCHEMA 有 " + kind)
	var svcs: Variant = cm.get("NPC_SERVICES", [])
	if svcs is Array and (svcs as Array).has("BANK"):
		for s in ["BANK", "ESCORT", "ORG", "RANK"]:
			assert_has(svcs, s)

## M3b 審查：主機不再為「永遠不會施捨」的 NPC 送 beg（例：陳長老）；客戶端照「沒有 beg 欄位」處理，不出現灰掉的乞討
func test_no_beg_row_for_never_giving_npc() -> void:
	_gaibang()
	var d := NpcDialog.new()
	_add(d)
	await _frame()
	d.open_menu({ "npc": "t_n_master", "npc_name": "陳長老", "services": ["TEACH", "RANK"], "beg": null })
	assert_false(d.service_buttons.has(UiKeys.BEG_CHOICE), "沒有乞討列")
	assert_true(d.services_box.find_child("BegWhy", true, false) == null)
