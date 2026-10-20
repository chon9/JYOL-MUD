extends "res://tests/test_case.gd"
## WP-UI（M3A_PLAN §10.1 test_ui_m3a_sect）：拜師確認、叛教兩段確認送出 intent、坐牢提示與倒數、贖人鈕、
## 學藝視窗被拒原因、屬性燈籠變色、HUD 狀態；另含查看偵察的「查看」鈕（M3a 小範圍）。全部用假資料。

var _nodes: Array = []
var _old_sheet: Dictionary = {}
var _old_wi: Dictionary = {}
var _patched: Dictionary = {}     # table -> { id: 原本的列或 null }

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

## 暫時放進 GameData 的資料列（after_each 還原）
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

func _wudang() -> void:
	_put("sects", "t_wudang", { "id": "t_wudang", "name": "武當", "gender": ["M"], "sect_skill": "xiayi", "sect_skill_name": "俠義",
		"join_requires": [ { "type": "morality_min", "value": 50 }, { "type": "no_sect" },
			{ "type": "not_enemy_of", "sect": "t_wudang" }, { "type": "quest_flag", "flag": "wd_recommended" } ] })
	_put("sect_rules", "t_wd_r_morality", { "id": "t_wd_r_morality", "sect": "t_wudang", "tier": "BREACH", "kind": "STATE", "text": "rule_t_wd_morality" })
	_put("text_templates", "rule_t_wd_morality", { "id": "rule_t_wd_morality", "self": "【系統】善惡不得低於 -99。" })
	_put("martial_arts", "t_wd_quan", { "id": "t_wd_quan", "name": "武當長拳", "sect_id": "t_wudang", "category": "FIST", "moves": [] })
	_put("martial_arts", "t_other", { "id": "t_other", "name": "野球拳", "sect_id": "", "category": "FIST", "moves": [] })

static func wd_sheet() -> Dictionary:
	return { "char_id": "ch_me", "name": "我", "sect": "t_wudang", "sect_name": "武當", "money": 200000, "morality": -90,
		"pk": 0, "killing_intent": 0, "vitals": {},
		"skills": [ { "id": "t_wd_quan", "name": "武當長拳", "kind": "ART", "level": 21 },
			{ "id": "t_other", "name": "野球拳", "kind": "ART", "level": 9 },
			{ "id": "basic_fist", "name": "基本拳腳", "kind": "BASIC", "level": 30 },
			{ "id": "xiayi", "name": "俠義", "kind": "SECT", "level": 12 } ],
		"sect_info": { "id": "t_wudang", "name": "武當", "skill_id": "xiayi", "skill_name": "俠義", "skill_level": 12,
			"master": "", "stop_teach": "", "ban_left_s": 0, "warnings": ["morality"] },
		"enemy_of": [], "jail": null, "conditions": [] }

# ---------------------------------------------------------------- 拜師確認

func test_join_confirm_shows_conditions_and_rules() -> void:
	_wudang()
	var sent: Array = []
	var d := NpcDialog.new()
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	d.open_menu({ "npc": "n_t_zsf", "npc_name": "張三丰", "services": ["JOIN"], "join_sect": "t_wudang", "sect_name": "武當" })
	(d.service_buttons["JOIN"] as Button).pressed.emit()
	var txt := (d.detail_box.find_child("JoinText", true, false) as Label).text
	assert_true(txt.contains("拜入武當門下"), txt)
	assert_true(txt.contains("只收男弟子"), txt)
	assert_true(txt.contains("善惡 50 以上"), txt)
	assert_true(txt.contains("需要引薦"), txt)
	assert_true(txt.contains("善惡不得低於 -99") and not txt.contains("【系統】"), "rule summary without channel tag: " + txt)
	# 確認按鈕在捲動區外（M3a 審查 C1：條件與門規很長時按鈕被擠到捲動區底下）
	assert_true(d.detail_box.find_child("JoinOk", true, false) == null, "按鈕不在捲動區裡")
	assert_true(d.footer_box.visible)
	(d.footer_box.find_child("JoinOk", true, false) as Button).pressed.emit()
	assert_eq(sent, [["join_sect", { "npc": "n_t_zsf" }]])
	assert_true(d.detail_box.find_child("JoinUnmet", true, false) == null, "沒有角色表：不列不符合")
	# 角色表看得出來的不符合條件另外用紅字列出（M3a 審查）
	ClientState.sheet = { "gender": "F", "morality": 10, "pk": 0, "killing_intent": 0, "sect": "", "enemy_of": [], "traitor_of": ["武當"] }
	var miss := SectUi.unmet_conditions("t_wudang", ClientState.sheet)
	assert_true("只收男弟子" in miss, str(miss))
	assert_true("善惡 50 以上" in miss, str(miss))
	assert_true("不是武當的公敵或叛徒" in miss, "叛徒記號：" + str(miss))
	assert_false("尚未拜入任何門派" in miss)
	d.open_menu({ "npc": "n_t_zsf", "npc_name": "張三丰", "services": ["JOIN"], "join_sect": "t_wudang", "sect_name": "武當" })
	(d.service_buttons["JOIN"] as Button).pressed.emit()
	var um := d.detail_box.find_child("JoinUnmet", true, false) as Label
	assert_true(um != null and um.text.contains("只收男弟子"), "unmet line shown")
	# 不符合時「確定拜師」變灰、原因在提示裡，按了也不送（M3a UI 審查 #1）
	var okb := d.footer_box.find_child("JoinOk", true, false) as Button
	assert_true(okb.disabled, "join confirm greyed when unmet")
	assert_true(okb.tooltip_text.contains("只收男弟子"), okb.tooltip_text)
	sent.clear()
	okb.pressed.emit()
	assert_eq(sent, [], "disabled confirm sends nothing")
	# 沒有資料列（舊主機 / 未合併）時仍有基本文字
	assert_true(SectUi.join_text("nope", "某派").contains("拜入某派門下"))
	assert_eq(SectUi.gender_text({ "gender": ["M", "F"] }), "男女皆收")

# ---------------------------------------------------------------- 叛教

func test_betray_two_step_sends_confirm_true() -> void:
	_wudang()
	ClientState.sheet = wd_sheet()
	ClientState.world_info = { "rule_profile": { "betrayal_halves_basics": false } }
	var sent: Array = []
	var d := NpcDialog.new()
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	d.open_menu({ "npc": "n_t_zsf", "npc_name": "張三丰", "services": ["TEACH", "BETRAY"], "betray": true })
	assert_eq((d.service_buttons["BETRAY"] as Button).text, "叛教")
	d.open_menu({ "npc": "n_t_zsf", "npc_name": "張三丰", "services": ["TEACH", "BETRAY"], "betray": false })
	assert_false(d.service_buttons.has("BETRAY"), "not this sect's member → no 叛教")
	d.open_menu({ "npc": "n_t_zsf", "npc_name": "張三丰", "services": ["TEACH", "BETRAY"], "betray": true })
	(d.service_buttons["BETRAY"] as Button).pressed.emit()
	var txt := (d.detail_box.find_child("BetrayText", true, false) as Label).text
	assert_true(txt.contains("武當長拳 21 → 10 級"), txt)
	assert_false(txt.contains("野球拳"), "only the sect's own arts are halved by default")
	assert_true(txt.contains("公敵") and txt.contains("叛徒"), txt)
	assert_false(txt.contains("歸零"), "2001 規則：門派技能不歸零（後期官方規則才歸零）：" + txt)
	var late := SectUi.betray_text(wd_sheet(), "t_wudang", true)
	assert_true(late.contains("俠義") and late.contains("歸零"), late)
	assert_eq(sent.size(), 0, "first step sends nothing")
	(d.detail_box.find_child("BetrayStep1", true, false) as Button).pressed.emit()
	var le := d.detail_box.find_child("BetrayWord", true, false) as LineEdit
	var ok := d.detail_box.find_child("BetrayOk", true, false) as Button
	assert_true(ok.disabled, "must type the word first")
	le.text = "叛"
	le.text_changed.emit(le.text)
	assert_true(ok.disabled)
	le.text = "叛教"
	le.text_changed.emit(le.text)
	assert_false(ok.disabled)
	ok.pressed.emit()
	assert_eq(sent, [["sect_betray", { "npc": "n_t_zsf", "confirm": true }]])
	# betrayal_halves_basics：全部武功與基本武學
	var all := SectUi.betray_halved(wd_sheet(), "t_wudang", true)
	assert_eq(all.map(func(x): return x["id"]), ["t_wd_quan", "t_other", "basic_fist"])

# ---------------------------------------------------------------- 思過處

func test_jail_banner_and_countdown() -> void:
	assert_eq(SectUi.duration_text(5520), "1 小時 32 分")
	assert_eq(SectUi.duration_text(320), "5 分 20 秒")
	assert_eq(SectUi.duration_text(40), "40 秒")
	assert_eq(SectUi.jail_banner({ "sect_name": "少林", "room_name": "思過處", "left_s": 5520 }, 5520.0), "思過處：剩 1 小時 32 分（上線時間）")
	assert_eq(SectUi.jail_banner({}, 10.0), "")
	# 房名已經帶「思過處」：不再寫成「思過處（少林思過處）」（M3a UI 審查 #2）
	assert_eq(SectUi.jail_banner({ "room_name": "少林思過處" }, 7200.0), "少林思過處：剩 2 小時 0 分（上線時間）")
	assert_eq(SectUi.jail_banner({ "room_name": "後山" }, 7200.0), "思過處（後山）：剩 2 小時 0 分（上線時間）")
	assert_eq(SectUi.left_now(100.0, 1000, 31000), 70.0, "local countdown since the sheet arrived")
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	var s := wd_sheet()
	s["jail"] = { "sect_name": "少林", "room_name": "思過處", "left_s": 5520 }
	s["_rx_ms"] = Time.get_ticks_msec()
	main.apply_sheet(s)
	assert_true(main.jail_banner.visible)
	assert_true(main.jail_text().begins_with("思過處：剩 1 小時 3"), main.jail_text())
	# 提示列不蓋左上的聊天／系統浮層（M3a UI 審查 #2）
	var br := Rect2(main.jail_banner.position, main.jail_banner.size)
	var ov: Rect2 = main.get_script().get_script_constant_map()["OVERLAY_RECT"]
	assert_false(br.intersects(ov), "jail banner %s overlaps chat overlay %s" % [br, ov])
	assert_true(br.size.x > 0.0)
	s = s.duplicate()
	s["jail"] = null
	main.apply_sheet(s)
	assert_false(main.jail_banner.visible, "released → banner gone")

func test_jailer_lists_prisoners_and_ransom() -> void:
	ClientState.sheet = { "money": 150000 }
	var sent: Array = []
	var d := NpcDialog.new()
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	d.open_menu({ "npc": "n_sl_kanshou", "npc_name": "看守僧", "services": ["JAIL"],
		"jail": { "prisoners": [ { "name": "阿甲", "left_s": 3600 } ], "ransom": 100000 } })
	assert_eq((d.service_buttons["JAIL"] as Button).text, "思過處")
	(d.service_buttons["JAIL"] as Button).pressed.emit()
	var b := d.detail_box.find_child("Ransom_阿甲", true, false) as Button
	assert_true(b != null)
	assert_eq(b.text, "贖人（十萬兩）")
	assert_false(b.disabled)
	b.pressed.emit()
	assert_eq(sent, [["jail_ransom", { "npc": "n_sl_kanshou", "name": "阿甲" }]])
	# 錢不夠：灰掉，原因直接印出來（M3a 審查 C6）
	ClientState.sheet = { "money": 5 }
	d.show_jail()
	assert_true((d.detail_box.find_child("Ransom_阿甲", true, false) as Button).disabled)
	var why := d.detail_box.find_child("RansomWhy_阿甲", true, false) as Label
	assert_true(why != null and why.visible and why.text.contains("銀兩不夠"), "灰掉的原因看得到")
	assert_eq(SectUi.money_text(100000), "十萬兩")
	assert_eq(SectUi.money_text(1234), "1234 兩")

func test_trial_and_guide() -> void:
	var sent: Array = []
	var d := NpcDialog.new()
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	d.open_menu({ "npc": "n_sl_tongren", "npc_name": "達摩院首座", "services": ["TRIAL", "GUIDE"],
		"trial": { "name": "十八銅人陣", "party_min": 3, "party_max": 3, "ok": false, "reason": "trial_party" },
		"guide": { "room_name": "古墓大廳", "ok": true } })
	assert_eq((d.service_buttons["GUIDE"] as Button).text, "引路（往古墓大廳）")
	(d.service_buttons["TRIAL"] as Button).pressed.emit()
	var txt := (d.detail_box.find_child("TrialText", true, false) as Label).text
	assert_true(txt.contains("十八銅人陣") and txt.contains("3 人"), txt)
	assert_true((d.detail_box.find_child("TrialOk", true, false) as Button).disabled, "party not ready")
	d.menu["trial"]["ok"] = true
	d.show_trial()
	(d.detail_box.find_child("TrialOk", true, false) as Button).pressed.emit()
	assert_eq(sent[0], ["sect_trial", { "npc": "n_sl_tongren" }])
	(d.service_buttons["GUIDE"] as Button).pressed.emit()
	assert_eq(sent[1], ["npc_guide", { "npc": "n_sl_tongren" }])

# ---------------------------------------------------------------- 學藝視窗

func test_learn_dialog_shows_block_and_greys_out() -> void:
	var sent: Array = []
	var d := LearnDialog.new()
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	var p := { "npc": "n_t", "npc_name": "宋遠橋", "teach_blocked": "sect_stop_teach",
		"entries": [ { "skill": "t_wd_quan", "name": "武當長拳", "kind": "ART", "level": 3, "cap": 50, "ok": true, "reason": "" } ] }
	d.open_list(p)
	assert_true(d.block_label.visible)
	assert_true(d.block_label.text.begins_with("停止傳功"), d.block_label.text)
	var any_enabled := false
	for b in d.list.find_children("*", "Button", true, false):
		if not (b as Button).disabled:
			any_enabled = true
	assert_false(any_enabled, "all learn buttons greyed")
	p["teach_blocked"] = ""
	d.open_list(p)
	assert_false(d.block_label.visible)
	var enabled := 0
	for b in d.list.find_children("*", "Button", true, false):
		if not (b as Button).disabled:
			enabled += 1
	assert_eq(enabled, 3, "×1 ×5 ×10")
	# 禁止學武附剩餘時間
	ClientState.sheet = { "sect_info": { "ban_left_s": 3700 } }
	assert_true(SectUi.block_text("sect_banned", 3700).contains("1 小時 1 分"), SectUi.block_text("sect_banned", 3700))

func test_main_screen_passes_teach_blocked_from_menu() -> void:
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	main.handle_event({ "ch": "SYSTEM", "key": "npc_menu", "ui": true,
		"p": { "npc": "n_t", "npc_name": "宋遠橋", "services": ["TEACH"], "teach_blocked": "sect_banned" } })
	main.handle_event({ "ch": "SYSTEM", "key": "teach_list", "ui": true,
		"p": { "npc": "n_t", "npc_name": "宋遠橋", "entries": [] } })
	assert_true(main.learn_dialog.visible)
	assert_eq(main.learn_dialog.blocked, "sect_banned")

# ---------------------------------------------------------------- 屬性燈籠、HUD 狀態

func test_attribute_warnings_turn_red() -> void:
	var ap := AttributesPanel.new()
	_add(ap)
	await _frame()
	var s := wd_sheet()
	s["enemy_of"] = ["星宿"]
	ap.apply_sheet(s)
	assert_true(ap.is_warned("善惡"))
	assert_false(ap.is_warned("殺氣"))
	assert_eq((ap.value_labels["善惡"] as Label).tooltip_text, UiKeys.SECT_WARN_TIP)
	assert_true(ap.misc_label.text.contains("俠義 12 級"), ap.misc_label.text)
	assert_true(ap.misc_label.text.contains("公敵：星宿"), ap.misc_label.text)
	s["sect_info"]["warnings"] = []
	ap.apply_sheet(s)
	assert_false(ap.is_warned("善惡"))
	# 主畫面的屬性燈籠
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	var s2 := wd_sheet()
	main.apply_sheet(s2)
	var lt: JyButton = main.lanterns.lanterns["attributes"]
	assert_true(lt.self_modulate != Color.WHITE, "lantern tinted")
	assert_true(lt.tooltip_text.contains(UiKeys.SECT_WARN_TIP))
	s2["sect_info"]["warnings"] = []
	main.apply_sheet(s2)
	assert_eq(lt.self_modulate, Color.WHITE)

func test_hud_status_shows_conditions_with_time() -> void:
	var sb := StatusBar.new()
	_add(sb)
	await _frame()
	var s := { "vitals": {}, "morality": 10,
		"conditions": [ { "id": "poison", "name": "中毒", "glyph": "毒", "color": "#3c9a3c", "level": 2, "left_s": 200 } ] }
	sb.apply_sheet(s)
	assert_true(sb.icon_text("status").contains("中毒（2 級，剩 3 分 20 秒）"), sb.icon_text("status"))
	assert_eq((sb.icons["status"] as JyButton).tint, Color("3c9a3c"))
	sb.apply_sheet({ "vitals": {}, "conditions": [] })
	assert_eq(sb.icon_text("status"), "狀態：正常")
	assert_eq((sb.icons["status"] as JyButton).tint, Color(0, 0, 0, 0))
	sb.apply_sheet({ "vitals": {}, "morality": -95, "sect_info": { "warnings": ["morality"] } })
	assert_true(sb.icon_text("morality").contains(UiKeys.SECT_WARN_TIP))

# ---------------------------------------------------------------- 查看偵察（小範圍）

func test_scout_button_in_wild_rooms_only() -> void:
	ClientState.world_info = { "scout_enabled": true }
	var sent: Array = []
	var sp := ScenePanel.new()
	sp.gate = _gate(sent)
	_add(sp)
	await _frame()
	sp.apply_view({ "room": "w_1", "room_name": "荒草坡", "region_name": "西夏郊外", "danger": true, "exits": [], "npcs": [], "features": [] })
	assert_true(sp.scout_button != null)
	assert_true(sp.life_box.get_parent().visible, "動作 row visible for the scout button")
	assert_eq(sp.scout_button.text, "查看", "與 F3 熱鍵同名")
	sp.scout_button.pressed.emit()
	assert_eq(sent, [["look", { "scout": true }]])
	await _frame()
	await _frame()
	# 冷卻：sheet.cooldowns.scout
	sp.apply_sheet({ "cooldowns": { "scout": 5.0 } })
	sp._process(0.0)
	assert_true(sp.scout_button.disabled)
	assert_eq(sp.scout_button.text, "查看（5 秒）")
	# 安全的房間、或主機關掉偵察：沒有鈕
	sp.apply_view({ "room": "c_1", "room_name": "市集", "safe": true, "exits": [], "npcs": [], "features": [] })
	assert_true(sp.scout_button == null)
	ClientState.world_info = { "scout_enabled": false }
	sp.apply_view({ "room": "w_1", "room_name": "荒草坡", "danger": true, "exits": [], "npcs": [], "features": [] })
	assert_true(sp.scout_button == null)

# ---------------------------------------------------------------- M3a 第三輪審查（C5、C10）

## 坐牢中：出口按鈕全部灰掉並標「思過中」（以前點了才被主機拒絕）
func test_jailed_exits_are_greyed() -> void:
	var sp := ScenePanel.new()
	_add(sp)
	await _frame()
	var view := { "room_name": "思過處", "region_name": "少林", "desc": "", "exits": [{ "dir": "SE", "to_name": "大雄寶殿" }],
		"npcs": [], "players": [], "corpses": [], "features": [] }
	sp.apply_view(view)
	var b := sp.exits_box.get_child(0) as Button
	assert_false(b.disabled, "沒有坐牢：可以走")
	sp.apply_sheet({ "jail": { "sect_name": "少林", "room_name": "思過處", "left_s": 7200 } })
	b = sp.exits_box.get_child(0) as Button
	assert_true(b.disabled, "坐牢：出口灰掉")
	assert_true(b.text.contains("思過中"), b.text)
	sp.apply_sheet({})
	b = sp.exits_box.get_child(0) as Button
	assert_false(b.disabled, "出獄：恢復")

## 已經是這一派的弟子：「拜師」灰掉並註明「已是本門弟子」
func test_join_greyed_for_own_sect() -> void:
	_wudang()
	var d := NpcDialog.new()
	d.gate = _gate([])
	_add(d)
	await _frame()
	ClientState.sheet = { "sect": "t_wudang" }
	d.open_menu({ "npc": "n_t_zsf", "npc_name": "張三丰", "services": ["JOIN", "TEACH"], "join_sect": "t_wudang", "sect_name": "武當" })
	assert_true((d.service_buttons["JOIN"] as Button).disabled, "已是本門弟子")
	assert_false((d.service_buttons["TEACH"] as Button).disabled)
	ClientState.sheet = { "sect": "" }
	d.open_menu({ "npc": "n_t_zsf", "npc_name": "張三丰", "services": ["JOIN"], "join_sect": "t_wudang", "sect_name": "武當" })
	assert_false((d.service_buttons["JOIN"] as Button).disabled)
	assert_true(NpcDialog.joined_this_sect({ "join_sect": "x" }, { "sect_info": { "id": "x" } }))
	assert_false(NpcDialog.joined_this_sect({}, { "sect": "x" }))
