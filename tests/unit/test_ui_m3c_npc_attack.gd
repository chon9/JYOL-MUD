extends "res://tests/test_case.gd"
## WP-NPCPK 介面（M3C_PLAN §5.8、§12.1）：場景卷軸 Ctrl+點 NPC → npc_attack_requested（一般點＝交談）、可動手 NPC 的提示；
## 主畫面：受保護 NPC 不送、只在訊息列說明；可動手 → 紅色確認框 → npc_attack { npc, mode: ATTACK }；
## 確認文字三種門派情境（同門違規、成為公敵、叛派）＋善惡與 CHALLENGE 說明；NPC 對話框的「滅派」選項（灰掉附原因、確認後送 MIEPAI）；
## 伺服器設定面板的兩列新選項（主機沒開放時灰掉顯示 100%）。全部用假資料。

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

func _gate(sent: Array, ok := true, reason := "") -> IntentGate:
	var g := IntentGate.new()
	_add(g)
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		var seq := sent.size()
		g.resolve.call_deferred(seq, ok, reason)
		return seq)
	return g

static func kid_entry() -> Dictionary:
	return { "id": "n_na_dl_xiaohai", "name": "小孩", "kind": "STORY", "services": [], "closed": false,
		"atk": { "mode": "KILL", "category": "CHILD", "align": "GOOD", "sect": "", "menu_label": "",
			"warn": "殺死善良的人，善惡會下降", "via": "CTRL", "effect": "" } }

static func quest_entry() -> Dictionary:
	return { "id": "n_lj_baiyong", "name": "白勇", "kind": "STORY", "services": ["QUEST"], "closed": false, "atk": null }

static func view_dali() -> Dictionary:
	return {
		"region": "dali", "region_name": "大理", "room": "dl_square", "room_name": "五華樓前", "desc": "廣場。",
		"clock": "辰時", "night": false, "exits": [], "features": [], "players": [], "safe": true, "danger": false,
		"npcs": [kid_entry(), quest_entry()],
	}

static func sheet_plain(sect := "") -> Dictionary:
	return { "char_id": "ch_me", "name": "我", "sect": sect, "in_battle": false, "enemy_of": [], "vitals": { "water": 50, "food": 50 },
		"is_admin": false, "mail_unread": 0, "prefs": { "accept_challenge": true, "accept_party": true },
		"party": {}, "pending": { "party_invite": {}, "challenges": [] }, "my_corpses": [] }

# ---------------------------------------------------------------- 場景卷軸
func test_scene_panel_ctrl_click_emits_and_plain_click_talks() -> void:
	var sp := ScenePanel.new()
	_add(sp)
	await _frame()
	var sent: Array = []
	sp.gate = _gate(sent)
	sp.apply_sheet(sheet_plain())
	sp.apply_view(view_dali())
	var kid: Button = sp.npc_buttons["n_na_dl_xiaohai"]
	var quest: Button = sp.npc_buttons["n_lj_baiyong"]
	assert_true(kid.tooltip_text.contains("動手"), "attackable NPC tooltip: %s" % kid.tooltip_text)
	assert_true(kid.tooltip_text.contains("Ctrl"), "uses the PK link key")
	assert_false(quest.tooltip_text.contains("動手"), "protected NPC has no hint")
	var got: Array = []
	sp.npc_attack_requested.connect(func(n): got.append(str(n.get("id", ""))))
	sp.on_npc_clicked(view_dali()["npcs"][0], true)
	assert_eq(got, ["n_na_dl_xiaohai"], "Ctrl+click → npc_attack_requested")
	assert_eq(sent.size(), 0, "Ctrl+click does not talk")
	sp.on_npc_clicked(view_dali()["npcs"][1], true)
	assert_eq(got.size(), 2, "protected NPCs are still reported (main screen refuses locally)")
	sp.on_npc_clicked(view_dali()["npcs"][0], false, kid)
	assert_eq(sent[0], ["talk", { "npc": "n_na_dl_xiaohai" }], "plain click talks")
	# 修飾鍵偵測：Ctrl＋左鍵
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.ctrl_pressed = true
	sp._on_npc_input(mb)
	assert_true(sp._npc_ctrl_click)

# ---------------------------------------------------------------- 主畫面
func test_main_screen_protected_and_confirm() -> void:
	var ms: Control = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await _frame()
	var sent: Array = []
	ms.gate.set_sender(func(kind, args):
		sent.append([kind, args])
		return -1)
	ms.apply_sheet(sheet_plain())
	ms.apply_view(view_dali())
	var before: int = ms.message_log.entries.size()
	ms.request_npc_attack(quest_entry())
	assert_false(ms.confirm_dialog.visible, "protected: no confirm")
	assert_eq(sent.size(), 0, "protected: nothing sent")
	assert_eq(ms.message_log.entries.size(), before + 1, "one line in the log")
	assert_true(str(ms.message_log.entries.back()["bb"]).contains("白勇不是你能動手的對象"))
	# 經由場景卷軸的訊號（主畫面 _build 接線）
	ms.scene_panel.on_npc_clicked(kid_entry(), true)
	assert_true(ms.confirm_dialog.visible, "attackable: confirm first")
	assert_eq(sent.size(), 0)
	var msg: String = ms.confirm_dialog.message_label.text
	assert_true(msg.contains("小孩") and msg.contains("善惡會下降"), msg)
	assert_true(msg.contains("暫時消失"), "KILL NPC note")
	assert_eq(ms.confirm_dialog.ok_button.text, "動手")
	ms.confirm_dialog.confirm()
	assert_eq(sent[0], ["npc_attack", { "npc": "n_na_dl_xiaohai", "mode": "ATTACK" }])
	# 戰鬥中：不開確認
	var sh := sheet_plain()
	sh["in_battle"] = true
	ms.apply_sheet(sh)
	ms.request_npc_attack(kid_entry())
	assert_false(ms.confirm_dialog.visible)
	assert_eq(sent.size(), 1)

# ---------------------------------------------------------------- 確認文字
func test_confirm_text_sect_cases() -> void:
	# 同門：武當弟子打武當門人
	var wd := { "id": "n_wd_zhongfei", "name": "鍾飛", "atk": { "mode": "CHALLENGE", "category": "SECT_DISCIPLE", "align": "GOOD",
		"sect": "wudang", "menu_label": "", "warn": "", "via": "CTRL" } }
	var t1 := NpcAttackUi.confirm_text(wd, sheet_plain("wudang"), {})
	assert_true(t1.contains("你是武當派弟子，對同門動手會違反門規"), t1)
	# M3c 審查：CHALLENGE 不說「殺死」（對方只會敗走）
	assert_true(t1.contains("對方只會敗走、不會死"), t1)
	assert_false(t1.contains("殺死"), "CHALLENGE text must not say 殺死: " + t1)
	var t1b := NpcAttackUi.confirm_text(wd, sheet_plain(""), {})
	assert_false(t1b.contains("門規") or t1b.contains("公敵"), "outsider vs disciple: just a fight: " + t1b)
	# 外人滅派：古墓公敵
	var gm := { "id": "n_gm_sunpopo", "name": "孫婆婆", "atk": { "mode": "CHALLENGE", "category": "SECT_GATE", "align": "GOOD",
		"sect": "gumu", "menu_label": "滅派", "via": "MENU" } }
	var t2 := NpcAttackUi.confirm_text(gm, sheet_plain(""), {}, NpcAttackUi.MODE_MIEPAI)
	assert_true(t2.contains("動手後你將成為古墓派公敵"), t2)
	assert_true(t2.begins_with("確定要滅派，跟古墓派動手"), t2)
	# M3c 審查：滅派要說清楚面對幾個人（資料表：孫婆婆＋5 名古墓弟子）
	assert_true(t2.contains("古墓弟子 ×5") and t2.contains("共 6 人"), t2)
	var gm2 := gm.duplicate(true)
	gm2["atk"]["foes"] = [{ "name": "孫婆婆", "n": "1" }, { "name": "古墓弟子", "n": "3" }]
	assert_true(NpcAttackUi.confirm_text(gm2, sheet_plain(""), {}, NpcAttackUi.MODE_MIEPAI).contains("共 4 人"), "host foes win (second time 4)")
	# M3c 審查：善惡變負後會被官兵追打（主機依新手保護給 morality_guard）
	var kid_g := kid_entry()
	kid_g["atk"]["morality_guard"] = true
	assert_true(NpcAttackUi.confirm_text(kid_g, sheet_plain(), {}).contains("每次進出有官兵把守的城"), "morality guard warning")
	kid_g["atk"]["morality_guard"] = false
	assert_false(NpcAttackUi.confirm_text(kid_g, sheet_plain(), {}).contains("每次進出有官兵把守的城"), "newbie: no warning")
	assert_eq(NpcAttackUi.TITLE, "動手", "no English 'NPC' in the title")
	var sh_enemy := sheet_plain("")
	sh_enemy["enemy_of"] = ["古墓"]
	assert_false(NpcAttackUi.confirm_text(gm, sh_enemy, {}, NpcAttackUi.MODE_MIEPAI).contains("公敵"), "already an enemy")
	# 叛派：星宿弟子對丁春秋
	var dcq := { "id": "n_xh_dingchunqiu", "name": "丁春秋", "atk": { "mode": "CHALLENGE", "category": "SECT_MASTER",
		"align": "EVIL", "sect": "xingxiu", "via": "CTRL" } }
	var t3 := NpcAttackUi.confirm_text(dcq, sheet_plain("xingxiu"), {})
	assert_true(t3.contains("對丁春秋動手＝叛出星宿派"), t3)
	assert_true(t3.contains("善惡會上升"), t3)
	# 主機給的 effect 優先
	var dcq2 := dcq.duplicate(true)
	dcq2["atk"]["effect"] = "ENEMY"
	assert_true(NpcAttackUi.confirm_text(dcq2, sheet_plain("xingxiu"), {}).contains("公敵"))
	# 城內守衛
	var kid := kid_entry()
	assert_true(NpcAttackUi.confirm_text(kid, sheet_plain(), view_dali()).contains("守城官兵"), "Dali has guards")
	var wild := view_dali()
	wild["region"] = "xixia_wild"
	assert_false(NpcAttackUi.confirm_text(kid, sheet_plain(), wild).contains("守城官兵"))

# ---------------------------------------------------------------- NPC 對話框「滅派」
func test_npc_dialog_miepai_option() -> void:
	var d := NpcDialog.new()
	var sent: Array = []
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	d.open_menu({ "npc": "n_wd_zhike", "npc_name": "知客道長", "services": [],
		"attack": { "ok": true, "reason": "", "label": "滅派", "warn": "動手後你將成為武當派公敵", "effect": "ENEMY" } })
	var b: Button = d.service_buttons.get(NpcDialog.ATTACK_CHOICE)
	assert_true(b != null, "滅派 option shown")
	assert_eq(b.text, "滅派")
	assert_false(b.disabled)
	assert_eq(b.get_theme_color("font_color"), UiTheme.JY_RED.lightened(0.15), "red option")
	b.pressed.emit()
	var txt: Label = d.detail_box.find_child("AttackText", true, false)
	assert_true(txt != null and txt.text.contains("公敵"), "confirm text first")
	assert_eq(sent.size(), 0)
	var okb: Button = d.footer_box.find_child("AttackOk", true, false)
	assert_true(okb != null)
	okb.pressed.emit()
	assert_eq(sent[0], ["npc_attack", { "npc": "n_wd_zhike", "mode": "MIEPAI" }])
	# 不能動手：灰掉並附原因
	d.open_menu({ "npc": "n_wd_zhike", "npc_name": "知客道長", "services": [],
		"attack": { "ok": false, "reason": "req_sect_not", "label": "滅派", "warn": "" } })
	var b2: Button = d.service_buttons.get(NpcDialog.ATTACK_CHOICE)
	assert_true(b2.disabled)
	assert_true(d.services_box.find_child("AttackWhy", true, false) != null, "reason shown")
	# 沒有 attack：沒有選項
	d.open_menu({ "npc": "n_dl_cunmin", "npc_name": "大理村民", "services": [], "attack": {} })
	assert_false(d.service_buttons.has(NpcDialog.ATTACK_CHOICE))

# ---------------------------------------------------------------- 伺服器設定
func test_server_options_m3c_rows() -> void:
	var d := ServerOptionsDialog.new()
	var sent: Array = []
	d.gate = _gate(sent)
	_add(d)
	await _frame()
	d.apply_options({ "editable": [{ "key": "pk_mode", "label": "PK 模式", "value": "CLASSIC",
		"choices": [{ "value": "CLASSIC", "label": "懷舊" }, { "value": "OFF", "label": "禁止 PK" }] }],
		"info": { "world_name": "測試", "players": [] } })
	for k in ["npc_respawn_pct", "loot_drop_pct"]:
		var ob: OptionButton = d.m3c_rows.get(k)
		assert_true(ob != null, k)
		assert_true(ob.disabled, k + " read-only while the host does not offer it")
		assert_eq(ob.get_item_text(ob.selected), "100%", k)
	# 主機開放了 → 走一般路徑（可改）
	d.apply_options({ "editable": [{ "key": "npc_respawn_pct", "label": "NPC 重生時間", "value": "200",
		"choices": [{ "value": "100", "label": "100%" }, { "value": "200", "label": "200%" }] }],
		"info": { "world_name": "測試", "players": [] } })
	var ob2: OptionButton = d.m3c_rows.get("npc_respawn_pct")
	assert_false(ob2.disabled)
	assert_eq(str(ob2.get_item_metadata(ob2.selected)), "200")
